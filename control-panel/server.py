#!/usr/bin/env python3
"""
control-panel/server.py — local-only web terminal bridge for
setup-silverblue.sh, so the whole transition can be driven from a browser
tab instead of a real terminal window.

Stdlib only, on purpose: this runs on the HOST (not a toolbox/distrobox —
same reasoning setup-silverblue.sh already uses for git/lshw/restic: it
operates ON the host, so it has to run FROM the host), and the host is
supposed to stay minimal. No pip installs, no compiled native modules
(node-pty and friends need a compiler toolchain this host deliberately
doesn't have) — just python3, which `./setup-silverblue.sh control-panel`
layers if it isn't already present.

THREAT MODEL — read this before running it
--------------------------------------------
This process spawns a real PTY running your login shell, with real sudo
access. That's the point: you type setup-silverblue.sh commands, sudo
prompts appear exactly like they do in a normal terminal, you either type
your password to proceed or Ctrl-C to decline. But it also means anything
that can talk to this server can act as you.

The realistic threat isn't a remote attacker — this binds to 127.0.0.1
only, nothing on your network can reach it. It's a MALICIOUS OR COMPROMISED
WEB PAGE OPEN IN ANOTHER TAB while this is running, blindly sending
requests to a well-known local port. Browsers block that page from
*reading* this server's responses (no CORS headers are ever sent), but a
"simple" cross-origin request can still be *sent* even when the response
can't be read — unless the request needs something a simple request isn't
allowed to carry. That's why every state-changing endpoint (/input,
/resize) and the output stream (/events) require a random per-run
X-Auth-Token header: a custom header forces the browser into CORS preflight
mode, and this server never grants a foreign origin permission to proceed.
The only place that token is ever handed out is server-side, templated into
the one HTML page this process serves at "/".

Layered on top:
  - Host-header allowlisting on every request — blocks DNS rebinding (a
    remote page whose hostname briefly resolves to 127.0.0.1).
  - X-Frame-Options / CSP frame-ancestors 'none' — blocks clickjacking (a
    malicious page iframing the real control panel to trick you into
    clicking a button you didn't mean to click).
  - A strict CSP (default-src 'self', no external script/style/connect) —
    the page never loads anything off-box, so there's nothing to poison.

None of this replaces sudo's own password prompt as the real authorization
boundary. It exists so that boundary is the ONLY thing standing between a
stray browser tab and your root shell, not an afterthought.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import pathlib
import pty
import queue
import re
import secrets
import signal
import struct
import sys
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML_PATH = pathlib.Path(__file__).resolve().parent / "control-panel.html"
BACKLOG_CHARS = 200_000
HEARTBEAT_SECS = 20

AUTH_TOKEN = secrets.token_urlsafe(32)
SUDO_PROMPT_RE = re.compile(r"\[sudo\] password for|^Password:\s*$", re.MULTILINE)


class PTYSession:
    """Owns the single shared PTY. Persists across browser disconnects —
    closing the tab must never kill a running rpm-ostree/harden step."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.fd: int | None = None
        self.pid: int | None = None
        self.backlog = ""
        self.clients: list[queue.Queue] = []
        self._spawn()
        threading.Thread(target=self._read_loop, daemon=True).start()

    def _spawn(self) -> None:
        # Called both from __init__ (single-threaded, safe) and from
        # _read_loop after the shell exits (that thread already holds
        # self.lock at the call site — see below). fork() in an already-
        # multithreaded process is the classic footgun (another thread can
        # hold e.g. an import/logging lock at the instant of fork, leaving
        # the child with a permanently-locked mutex); the standard-safe
        # pattern, followed here, is to do nothing but chdir/exec in the
        # child and never fall back into normal Python control flow if exec
        # fails (os._exit, not sys.exit/return).
        shell = os.environ.get("SHELL", "/bin/bash")
        pid, fd = pty.fork()
        if pid == 0:
            # child
            os.chdir(str(REPO_ROOT))
            env = dict(os.environ)
            # TERM=dumb deliberately: disables bash readline's cursor-
            # addressing line editing, so we only ever need to render plain
            # text + \r/\n + basic SGR color, not a full VT100 grid. Trade-off
            # (no tab-completion menu, no arrow-key history recall) is
            # documented in the README — worth it to avoid needing a real
            # terminal emulator for a five-command setup script.
            env["TERM"] = "dumb"
            env["SILVERBLUE_CONTROL_PANEL"] = "1"
            try:
                os.execvpe(shell, [shell, "-l"], env)
            except OSError:
                os._exit(1)
        else:
            self.fd = fd
            self.pid = pid
            try:
                self._resize(24, 80)
            except OSError:
                pass

    def _resize(self, rows: int, cols: int) -> None:
        if self.fd is None:
            return
        rows = max(5, min(200, rows))
        cols = max(20, min(500, cols))
        packed = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, packed)

    def resize(self, rows: int, cols: int) -> None:
        with self.lock:
            self._resize(rows, cols)

    def write(self, data: bytes) -> None:
        # fd read AND written while holding the lock — releasing it in
        # between (as an earlier version did) leaves a window where the
        # read loop can close this fd and respawn a new one before the
        # write() call happens, writing into a stale/closed descriptor.
        # os.write() to a pty master for keystroke-sized input doesn't block
        # meaningfully, so holding the lock for the call is cheap.
        with self.lock:
            fd = self.fd
            if fd is None:
                return
            try:
                os.write(fd, data)
            except OSError:
                pass

    def _broadcast(self, text: str) -> None:
        with self.lock:
            self.backlog += text
            if len(self.backlog) > BACKLOG_CHARS:
                self.backlog = self.backlog[-BACKLOG_CHARS:]
            clients = list(self.clients)
        for q in clients:
            q.put(text)

    def _read_loop(self) -> None:
        while True:
            with self.lock:
                fd = self.fd
                pid = self.pid
            try:
                data = os.read(fd, 4096) if fd is not None else b""
            except OSError:
                data = b""
            if not data:
                # child exited (or fd never got set) — clean up and respawn
                # so an accidental `exit` doesn't wedge the whole panel.
                with self.lock:
                    if self.fd is not None:
                        try:
                            os.close(self.fd)
                        except OSError:
                            pass
                    if pid is not None:
                        try:
                            os.waitpid(pid, os.WNOHANG)
                        except ChildProcessError:
                            pass
                    self.fd = None
                self._broadcast(
                    "\r\n\x1b[33m[session ended — starting a new shell]\x1b[0m\r\n"
                )
                time.sleep(0.2)
                with self.lock:
                    self._spawn()
                continue
            self._broadcast(data.decode("utf-8", errors="replace"))

    def subscribe(self) -> tuple[queue.Queue, str]:
        q: queue.Queue = queue.Queue()
        with self.lock:
            self.clients.append(q)
            backlog = self.backlog
        return q, backlog

    def unsubscribe(self, q: queue.Queue) -> None:
        with self.lock:
            if q in self.clients:
                self.clients.remove(q)


SESSION = PTYSession()


def _allowed_host(host: str | None, port: int) -> bool:
    if not host:
        return False
    host = host.strip().lower()
    return host in (f"127.0.0.1:{port}", f"localhost:{port}", "127.0.0.1", "localhost")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "SilverblueControlPanel/1.0"

    # Silence the default noisy per-request stderr logging; the systemd
    # journal already captures stdout/stderr for the unit if you want it.
    def log_message(self, fmt, *args):  # noqa: D401 - matches base signature
        pass

    # -- helpers --------------------------------------------------------
    def _security_headers(self) -> None:
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self' 'unsafe-inline'; "
            "style-src 'self' 'unsafe-inline'; connect-src 'self'; "
            "frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
        )
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")

    def _host_ok(self) -> bool:
        if _allowed_host(self.headers.get("Host"), self.server.server_port):
            return True
        self.send_response(403)
        self._security_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def _token_ok(self) -> bool:
        token = self.headers.get("X-Auth-Token", "")
        if secrets.compare_digest(token, AUTH_TOKEN):
            return True
        self.send_response(403)
        self._security_headers()
        body = b"forbidden: missing/invalid X-Auth-Token"
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        return False

    def _send_chunk(self, text: str) -> bool:
        data = text.encode("utf-8")
        try:
            self.wfile.write(("%x\r\n" % len(data)).encode() + data + b"\r\n")
            self.wfile.flush()
            return True
        except (BrokenPipeError, ConnectionResetError, OSError):
            return False

    # -- routes -----------------------------------------------------------
    def do_GET(self):
        if not self._host_ok():
            return
        path = urlsplit(self.path).path

        if path == "/":
            self._serve_index()
        elif path == "/term-parser.js":
            self._serve_static(pathlib.Path(__file__).resolve().parent / "term-parser.js", "application/javascript")
        elif path == "/healthz":
            self._serve_health()
        elif path == "/events":
            self._serve_events()
        else:
            self.send_response(404)
            self._security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()

    def do_POST(self):
        if not self._host_ok():
            return
        path = urlsplit(self.path).path
        try:
            length = int(self.headers.get("Content-Length", 0) or 0)
        except ValueError:
            self.send_response(400)
            self._security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = self.rfile.read(length) if length else b""

        if path == "/input":
            if not self._token_ok():
                return
            SESSION.write(body)
            self.send_response(204)
            self._security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif path == "/resize":
            if not self._token_ok():
                return
            try:
                payload = json.loads(body or b"{}")
                SESSION.resize(int(payload.get("rows", 24)), int(payload.get("cols", 80)))
            except (ValueError, TypeError, json.JSONDecodeError):
                pass
            self.send_response(204)
            self._security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self.send_response(404)
            self._security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()

    # -- handlers -----------------------------------------------------------
    def _serve_index(self):
        try:
            html = HTML_PATH.read_text(encoding="utf-8")
        except OSError:
            self.send_response(500)
            self._security_headers()
            self.end_headers()
            return
        html = html.replace("__AUTH_TOKEN__", AUTH_TOKEN)
        html = html.replace("__PORT__", str(self.server.server_port))
        body = html.encode("utf-8")
        self.send_response(200)
        self._security_headers()
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_static(self, path: pathlib.Path, content_type: str):
        # Only ever called with a hardcoded path from do_GET's own routing
        # table above (never from user input), so there's no path-traversal
        # surface here — this isn't a general static file server.
        try:
            body = path.read_bytes()
        except OSError:
            self.send_response(404)
            self._security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self._security_headers()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_health(self):
        body = b"ok"
        self.send_response(200)
        self._security_headers()
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_events(self):
        if not self._token_ok():
            return
        q, backlog = SESSION.subscribe()
        self.send_response(200)
        self._security_headers()
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            if backlog:
                if not self._send_chunk(backlog):
                    return
            while True:
                try:
                    text = q.get(timeout=HEARTBEAT_SECS)
                except queue.Empty:
                    text = "\x00"  # heartbeat filler; frontend strips NULs
                if not self._send_chunk(text):
                    break
        finally:
            SESSION.unsubscribe(q)
            try:
                self.wfile.write(b"0\r\n\r\n")
            except OSError:
                pass


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8642)
    args = parser.parse_args()

    # Deliberately no --bind flag: this tool's whole security model assumes
    # 127.0.0.1-only (see module docstring). Exposing it to a LAN needs real
    # auth/TLS work this design doesn't do — not a one-flag change.
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True

    def _shutdown(signum, frame):
        # NOT server.shutdown() here: signals are delivered to (and this
        # handler runs on) the main thread, which is the exact same thread
        # blocked inside serve_forever()'s select loop below. shutdown()
        # blocks until serve_forever() acknowledges and exits — but
        # serve_forever() can't do that while it's the thing calling this
        # handler. That's a guaranteed self-deadlock (this is called out
        # explicitly in the socketserver docs: shutdown() "must be called
        # while serve_forever() is running in a different thread"). Caught
        # in testing: 'control-panel stop' hung instead of stopping.
        #
        # Killing the child shell directly and exiting hard is also just
        # more correct here: 'stop' should actually stop the session, not
        # leave it orphaned under init while the parent quietly vanishes.
        if SESSION.pid:
            try:
                os.kill(SESSION.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        os._exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    print(f"Silverblue control panel: http://127.0.0.1:{args.port}/", file=sys.stderr)
    print("(token is embedded server-side in the page — nothing to copy/paste)", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
