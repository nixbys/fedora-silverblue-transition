# Control panel

Runs the entire transition from a browser tab instead of a terminal window.
It's a real shell — `sudo` prompts, `read -p` prompts in `fedora-harden.sh`,
`rpm-ostree` progress output, all of it — reachable at
`http://127.0.0.1:8642/` once it's running.

## Start it

```bash
./setup-silverblue.sh control-panel start
```

If you already ran `./setup-silverblue.sh base`, `python3` is already there —
it's folded into that phase's single reboot specifically so trying the
control panel later doesn't cost a second one. If you haven't, `start`
layers it standalone (idempotent, same pattern as everything else in
`setup-silverblue.sh`) and tells you to reboot once, then re-run. Either
way it then writes a `systemd --user` service so the shell session survives
you closing the browser tab mid-command, and prints the URL. `control-panel
status` / `control-panel stop` do what they say (`status` is also folded
into `./setup-silverblue.sh status`'s own output).

Open the URL, click a command in the sidebar to **stage** it into the
terminal (it appears typed but not submitted), press **Enter** to actually
run it. Anything that hits `sudo` shows the normal password prompt right
there — type it to proceed, `Ctrl-C` (or the Cancel button on the banner
that pops up) to decline. If the tab isn't focused when a prompt appears and
you've clicked "Enable desktop notifications" once, you get a real OS
notification instead of missing it.

## What this is not

It's not xterm.js/a full VT100 emulator, and it's not networked beyond your
own machine:

- **The shell runs with `TERM=dumb`.** That's deliberate — it disables
  bash's readline line-editing (which normally repositions the cursor with
  escape sequences to redraw multi-line prompts, tab-completion menus,
  etc.), so the browser side only ever has to render plain text plus basic
  `\r`/`\n`/backspace/color — not arbitrary cursor placement. You lose
  tab-completion and arrow-key history recall in this shell specifically.
  Full-screen interactive programs (`vim`, `htop`, `less` without `-F`)
  won't render correctly here — everything `setup-silverblue.sh` and
  `fedora-hardening` actually do is linear `echo`/`read` prompts, which
  this handles fine.
- **It binds to `127.0.0.1` only**, hardcoded, no flag to change that. See
  "Trust model" below for why that's not a one-line change to "just also
  allow my phone."

## Trust model

This process spawns a real PTY with real `sudo` access. That's the entire
point, and it's also the thing worth being deliberate about — anything that
can talk to this server can act as you.

The realistic risk isn't a remote attacker (nothing routes to `127.0.0.1`
from your network) — it's **a malicious or compromised web page open in
another tab** while the control panel is running, blindly sending requests
to a known local port. A browser blocks that page from *reading* this
server's responses, but a same-origin-policy "simple" request can still be
*sent* even when the response can't be read back — unless the request needs
something a simple request isn't allowed to carry. That's why:

- Every state-changing endpoint (`/input`, `/resize`) and the output stream
  (`/events`) require a random per-run `X-Auth-Token` header, generated at
  startup and only ever handed to the one page this server itself serves.
  Setting a custom header forces the browser into CORS preflight, and this
  server never grants a foreign origin permission to proceed.
- Every request is checked against a `Host` allowlist (`127.0.0.1:8642` /
  `localhost:8642`), which defeats DNS rebinding — a page whose hostname
  briefly resolves to `127.0.0.1` to borrow same-origin trust it hasn't
  earned.
- Responses carry `X-Frame-Options: DENY` and a `frame-ancestors 'none'`
  CSP, so the real control panel can't be iframed by another page for a
  clickjacking trick (tricking you into clicking a button you didn't mean
  to click).
- The CSP is otherwise `default-src 'self'` — the page loads nothing
  off-box, so there's nothing external to poison.

None of this replaces `sudo`'s own password prompt as the actual
authorization boundary. It exists so that prompt is the *only* thing
standing between a stray browser tab and your root shell, not an
afterthought bolted on top of a wide-open localhost API.

**Multi-device access (phone, another machine on your LAN) is explicitly
out of scope for this design.** `server.py` has no `--bind` flag on
purpose — exposing this beyond loopback needs real auth (not just a
CSRF-resistant token a same-machine browser already trusts implicitly) and
TLS (so the token and everything you type, including sudo passwords, isn't
plaintext on the wire), which is a different, bigger piece of work than
this tool does today.

## Tests

The hand-rolled ANSI-lite terminal renderer (`term-parser.js`, shared
between the actual page and this test suite so there's one source of
truth, not a copy that can drift) has a plain-Node, no-dependency test
suite:

```bash
node control-panel/test/term-parser.test.js
```

Worth running after touching `term-parser.js` — it's the part of this tool
most likely to have a subtle bug, since it's hand-parsing a text stream
rather than delegating to a real terminal library. It's already caught two
real ones during review: `\r` unconditionally wiping the current line (so
every ordinary `\r\n` line ending silently blanked the line it was ending),
and 24-bit color's RGB sub-parameters (`\x1b[38;2;R;G;Bm`) being misread as
unrelated SGR codes.

## Why Python stdlib, no dependencies

The server has to run on the host, not in a toolbox/distrobox — same
reasoning `setup-silverblue.sh` already uses for `git`/`lshw`/`restic`: it
runs `sudo rpm-ostree`/`firewall-cmd`/`systemctl` against the host, so it
has to run *from* the host. The host is supposed to stay minimal
(`TRANSITION-PLAN.md`'s whole compartmentalization argument), so this
avoids anything that would need a compiler toolchain on the host to install
(e.g. `node-pty`, the dependency a Node-based version of this would need) —
just `python3` itself, which ships as a single small layered package.
