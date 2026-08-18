// term-parser.js — the ANSI-lite terminal renderer's pure parsing logic,
// factored out of control-panel.html so it has no DOM dependency and can be
// unit-tested with plain Node (see control-panel/test/term-parser.test.js).
// control-panel.html loads this via <script src="term-parser.js"> and wires
// TermParser.createParser()'s output into the actual page.
//
// Deliberately NOT a full VT100 emulator — see control-panel/README.md for
// why (TERM=dumb on the shell side is the other half of that decision).
// Handles: plain text, \r/\n, backspace/DEL, SGR color (\x1b[...m), and
// \x1b[2K line-erase (covers progress-bar-style output like
// rpm-ostree/dnf). Everything else is stripped rather than misrendered.
(function (root, factory) {
  if (typeof module !== "undefined" && module.exports) {
    module.exports = factory();
  } else {
    root.TermParser = factory();
  }
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // Cap on how long a "this might still be an incomplete escape sequence,
  // wait for more data" buffer is allowed to grow. Guards against a
  // pathological/buggy program that opens an OSC sequence (\x1b]...) and
  // never sends its terminator — without this, pendingBuf would grow
  // unbounded across every future chunk instead of eventually giving up.
  const MAX_PENDING_ESC = 4096;

  function createParser() {
    let lines = [];
    let curLine = [];
    let curStyle = new Set();
    // Holds input this parser can't act on yet and needs the next feed()
    // call to resolve — either the start of an escape sequence that hasn't
    // been terminated within this chunk, or a lone trailing \r that might
    // turn out to be the first half of a \r\n pair once more data arrives.
    let pendingBuf = "";
    const MAX_LINES = 3000;

    function escapeHtml(s) {
      return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    function dropPrefixed(prefix) {
      for (const c of Array.from(curStyle)) if (c.startsWith(prefix)) curStyle.delete(c);
    }
    function sgrApply(params) {
      const codes = (params || "0").split(";").map(s => parseInt(s || "0", 10));
      for (let idx = 0; idx < codes.length; idx++) {
        const code = codes[idx];
        if (code === 0) curStyle.clear();
        else if (code === 1) curStyle.add("b");
        else if (code === 4) curStyle.add("u");
        else if (code === 39) dropPrefixed("fg");
        else if (code === 49) dropPrefixed("bg");
        else if (code === 38 || code === 48) {
          // Extended color (256-color palette or 24-bit RGB): 38;5;N or
          // 38;2;R;G;B. This renderer only has CSS classes for the basic
          // 16-color set, so recognize the whole directive and skip its
          // sub-parameters rather than falling through to the generic
          // per-code loop below — without this, an RGB component like 100
          // gets misread as the unrelated "bright background" SGR code 100.
          // Found by the parser's own test suite, not by inspection.
          const mode = codes[idx + 1];
          if (mode === 5) idx += 2;
          else if (mode === 2) idx += 4;
          else idx += 1;
        }
        else if ((code >= 30 && code <= 37) || (code >= 90 && code <= 97)) { dropPrefixed("fg"); curStyle.add("fg" + code); }
        else if ((code >= 40 && code <= 47) || (code >= 100 && code <= 107)) { dropPrefixed("bg"); curStyle.add("bg" + code); }
      }
    }
    function pushChar(ch) {
      const cls = Array.from(curStyle).join(" ");
      const last = curLine[curLine.length - 1];
      if (last && last.cls === cls) last.text += ch;
      else curLine.push({ text: ch, cls });
    }
    function renderRun(runs) {
      return runs.map(r => r.cls ? '<span class="' + r.cls + '">' + escapeHtml(r.text) + "</span>" : escapeHtml(r.text)).join("");
    }
    function endLine() {
      lines.push(renderRun(curLine));
      curLine = [];
      if (lines.length > MAX_LINES) lines.splice(0, lines.length - MAX_LINES);
    }

    function feed(raw) {
      const text = pendingBuf + raw;
      pendingBuf = "";
      let i = 0;
      while (i < text.length) {
        const ch = text[i];
        if (ch === "\x00") { i++; continue; } // heartbeat filler from the server
        if (ch === "\x1b") {
          const rest = text.slice(i);
          let m = /^\x1b\][^\x07\x1b]*(\x07|\x1b\\)/.exec(rest);
          if (m) { i += m[0].length; continue; }
          m = /^\x1b\[([0-9;]*)([A-Za-z])/.exec(rest);
          if (m) {
            if (m[2] === "m") sgrApply(m[1]);
            // \x1b[2K = erase whole current line. Plain \x1b[K (erase from
            // cursor to end) is a correct no-op here specifically because
            // this renderer never supports moving the cursor mid-line — the
            // "cursor" is always conceptually at the end of curLine, so
            // "erase from cursor to end" has nothing to do.
            else if (m[2] === "K" && m[1] === "2") curLine = [];
            i += m[0].length;
            continue;
          }
          // Not a complete, recognized sequence yet — is it still a valid
          // PREFIX of one (OSC/CSI opened but not terminated within this
          // chunk), or definitely something this renderer doesn't handle?
          // Only the former should be buffered and retried once more data
          // arrives. An earlier version used a flat byte-length cutoff here,
          // which mis-handled long parameter lists (24-bit color's
          // \x1b[38;2;R;G;Bm easily clears a short threshold) by treating a
          // sequence that was legitimately still arriving as garbage text.
          const looksIncomplete =
            rest === "\x1b" ||
            /^\x1b\[[0-9;]*$/.test(rest) ||
            /^\x1b\][^\x07\x1b]*$/.test(rest);
          if (looksIncomplete && rest.length <= MAX_PENDING_ESC) {
            pendingBuf = rest;
            break;
          }
          i += 1; // genuinely unrecognized (or pathologically long) escape — drop just the ESC byte
          continue;
        }
        if (ch === "\r") {
          // \r immediately followed by \n is just a normal line ending
          // (extremely common — PTY echo of Enter, plenty of programs use
          // CRLF outright) and must NOT wipe the line first; only a bare \r
          // NOT followed by \n is the progress-bar-style "overwrite this
          // line in place" case this renderer approximates by clearing it.
          // (An earlier version clered unconditionally on \r, which meant
          // every ordinary \r\n silently blanked the line it was ending —
          // caught by this parser's own test suite, not by inspection.)
          if (i === text.length - 1) {
            // \r is the very last byte in this chunk — could be a lone
            // overwrite \r, or half of a \r\n split across the chunk
            // boundary. Hold it and decide once the next chunk arrives.
            pendingBuf = "\r";
            break;
          }
          if (text[i + 1] === "\n") { i++; continue; } // let the \n do the line break
          curLine = [];
          i++;
          continue;
        }
        if (ch === "\n") { endLine(); i++; continue; }
        if (ch === "\x08" || ch === "\x7f") {
          const last = curLine[curLine.length - 1];
          if (last) { last.text = last.text.slice(0, -1); if (!last.text) curLine.pop(); }
          i++; continue;
        }
        pushChar(ch);
        i++;
      }
      return html();
    }

    function html() {
      return lines.join("\n") + (lines.length ? "\n" : "") + renderRun(curLine);
    }

    // Exposed for tests — internal shape (array of {text, cls} runs per
    // line) rather than just the rendered HTML string, so assertions don't
    // have to fight escaping/markup to check "what text is on screen."
    function state() {
      return {
        lines: lines.slice(),
        curLine: curLine.map(r => Object.assign({}, r)),
        pendingBuf,
        curStyle: Array.from(curStyle),
      };
    }

    return { feed, html, state, escapeHtml };
  }

  return { createParser };
});
