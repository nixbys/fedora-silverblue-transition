#!/usr/bin/env node
// control-panel/test/term-parser.test.js — plain Node, no dependencies, no
// test framework (matches the rest of this repo's "no build step" bar).
// Run: node control-panel/test/term-parser.test.js
"use strict";

const assert = require("assert");
const { createParser } = require("../term-parser.js");

let failures = 0;
let passed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
  } catch (e) {
    failures++;
    console.error(`✗ ${name}\n  ${e.message}`);
  }
}

function textOf(state) {
  // Flatten a parser state's lines+curLine into plain visible text, ignoring
  // styling, for tests that only care what's on screen.
  const allRuns = state.lines
    .map(l => l) // lines are already-rendered HTML strings in .lines; use .html()/.feed() return instead for text-level checks
    .join("\n");
  return allRuns;
}

// ---- plain text + newlines -------------------------------------------------
test("plain text with a trailing newline becomes a completed line", () => {
  const p = createParser();
  const out = p.feed("hello world\n");
  assert.strictEqual(out, "hello world\n");
});

test("text without a trailing newline stays on the pending current line", () => {
  const p = createParser();
  const out = p.feed("no newline yet");
  assert.strictEqual(out, "no newline yet");
});

test("multiple feed() calls accumulate correctly", () => {
  const p = createParser();
  p.feed("first line\n");
  const out = p.feed("second ");
  const out2 = p.feed("line\n");
  assert.strictEqual(out2, "first line\nsecond line\n");
});

// ---- carriage return (documented simplification: clears whole line) -------
test("\\r clears the in-progress line (progress-bar style overwrite)", () => {
  const p = createParser();
  const out = p.feed("Downloading... 10%\rDownloading... 99%\n");
  assert.strictEqual(out, "Downloading... 99%\n");
});

// ---- backspace / DEL -------------------------------------------------------
test("backspace removes the last character", () => {
  const p = createParser();
  const out = p.feed("abcx\x7f\n");
  assert.strictEqual(out, "abc\n");
});

test("backspace at start of line is a harmless no-op", () => {
  const p = createParser();
  const out = p.feed("\x7f\x7fok\n");
  assert.strictEqual(out, "ok\n");
});

test("backspace across a style-run boundary removes the run entirely once empty", () => {
  const p = createParser();
  // bold "X" then plain backspace — should remove the bold run cleanly, not
  // leave a dangling empty <span>.
  const out = p.feed("\x1b[1mX\x1b[0m\x7f\n");
  assert.strictEqual(out, "\n");
});

// ---- SGR color -------------------------------------------------------------
test("SGR 31 (red) wraps subsequent text in a fg31 span", () => {
  const p = createParser();
  const out = p.feed("\x1b[31mred\x1b[0m plain\n");
  assert.strictEqual(out, '<span class="fg31">red</span> plain\n');
});

test("SGR 1;32 (bold green) combines both classes", () => {
  const p = createParser();
  const out = p.feed("\x1b[1;32mok\x1b[0m\n");
  assert.strictEqual(out, '<span class="b fg32">ok</span>\n');
});

test("bare \\x1b[m (no params) resets like \\x1b[0m", () => {
  const p = createParser();
  const out = p.feed("\x1b[31mred\x1b[mplain\n");
  assert.strictEqual(out, '<span class="fg31">red</span>plain\n');
});

test("SGR 39 clears only the foreground, leaving background intact", () => {
  const p = createParser();
  const out = p.feed("\x1b[31;44mtext\x1b[39mmore\x1b[0m\n");
  assert.strictEqual(out, '<span class="fg31 bg44">text</span><span class="bg44">more</span>\n');
});

// ---- \x1b[K / \x1b[2K line erase -------------------------------------------
test("\\x1b[2K clears the current line's content", () => {
  const p = createParser();
  const out = p.feed("garbage\x1b[2Kclean\n");
  assert.strictEqual(out, "clean\n");
});

test("bare \\x1b[K (erase-to-end) is a no-op since cursor is always at line end", () => {
  const p = createParser();
  const out = p.feed("abc\x1b[Kdef\n");
  assert.strictEqual(out, "abcdef\n");
});

// ---- OSC sequences (window title etc.) get stripped ------------------------
test("OSC sequence terminated by BEL is stripped", () => {
  const p = createParser();
  const out = p.feed("\x1b]0;my title\x07visible\n");
  assert.strictEqual(out, "visible\n");
});

test("OSC sequence terminated by ST (ESC \\\\) is stripped", () => {
  const p = createParser();
  const out = p.feed("\x1b]0;my title\x1b\\visible\n");
  assert.strictEqual(out, "visible\n");
});

// ---- chunk-boundary splitting (the actual bug found in review) ------------
test("a CSI sequence split mid-parameter-list across two feed() calls still applies", () => {
  const p = createParser();
  p.feed("\x1b[3");
  const out = p.feed("1mred\x1b[0m\n");
  assert.strictEqual(out, '<span class="fg31">red</span>\n');
});

test("a LONG (>8 byte) truecolor-style CSI split across chunks still applies " +
     "(regression test for the length-heuristic bug found in review — a flat " +
     "byte cutoff mis-treated legitimately-incomplete long sequences as garbage)", () => {
  const p = createParser();
  // \x1b[38;2;255;100;50 is already 18 bytes before even reaching the final 'm'
  p.feed("\x1b[38;2;255;100;5");
  const out = p.feed("0mtext\n");
  // Our parser doesn't specifically understand 24-bit color (code 38 isn't in
  // any of the recognized ranges), so it correctly falls through to "known
  // CSI, unhandled code" — the key assertion is that none of "[38;2;255;100;50m"
  // leaked into visible text, not that it was colored.
  assert.strictEqual(out, "text\n");
});

test("a split escape sequence that never completes eventually gets flushed as text, not stuck forever", () => {
  const p = createParser();
  p.feed("\x1b[31"); // looks like an incomplete CSI...
  const out = p.feed(" and then just normal text\n"); // ...but a space is never a valid CSI continuation
  // The space breaks the "still looks incomplete" pattern, so the buffered
  // "\x1b[31" plus everything after should fall through to literal text
  // rather than hanging onto the buffer forever.
  assert.strictEqual(out, "[31 and then just normal text\n");
});

test("a genuinely unrecognized short escape (charset designation) drops only the ESC byte", () => {
  const p = createParser();
  const out = p.feed("\x1b(Bplain text\n");
  assert.strictEqual(out, "(Bplain text\n");
});

test("pendingBuf is capped so a never-terminated OSC can't grow forever", () => {
  const p = createParser();
  p.feed("\x1b]0;" + "x".repeat(5000)); // never sends a terminator
  const state = p.state();
  assert.ok(state.pendingBuf.length <= 4096, `pendingBuf grew to ${state.pendingBuf.length}, expected it capped`);
});

// ---- \r\n regression (real bug: unconditional \r used to wipe the line
// a \n was about to end anyway, blanking every ordinary line break) --------
test("\\r\\n behaves like a plain newline — does NOT blank the line first", () => {
  const p = createParser();
  const out = p.feed("hello\r\nworld\r\n");
  assert.strictEqual(out, "hello\nworld\n");
});

test("a \\r\\n split exactly at the chunk boundary still behaves like a plain newline", () => {
  const p = createParser();
  p.feed("hello\r");
  const out = p.feed("\nworld\n");
  assert.strictEqual(out, "hello\nworld\n");
});

test("a bare trailing \\r NOT followed by \\n (real progress-bar case) still overwrites", () => {
  const p = createParser();
  p.feed("10%\r");
  const out = p.feed("99%\n");
  assert.strictEqual(out, "99%\n");
});

// ---- 24-bit color regression (real bug: RGB sub-params were misread as
// unrelated SGR codes, e.g. G/B component 100 -> "bright background 100") --
test("24-bit truecolor foreground doesn't leak its RGB numbers as stray SGR codes", () => {
  const p = createParser();
  const out = p.feed("\x1b[38;2;10;20;100mtext\x1b[0m\n");
  // No CSS class exists for arbitrary RGB — correct behavior is "recognized
  // and ignored", not "text", and definitely not a bg100 class picked up
  // from the blue component.
  assert.strictEqual(out, "text\n");
});

test("256-color palette form (38;5;N) is also recognized and skipped, not misparsed", () => {
  const p = createParser();
  const out = p.feed("\x1b[38;5;196mtext\x1b[0m\n");
  assert.strictEqual(out, "text\n");
});

test("a real SGR code following a truecolor directive on the same sequence still applies", () => {
  const p = createParser();
  // bold, then truecolor fg (ignored), then more text — the '1' must not get
  // swallowed by the truecolor skip-ahead logic.
  const out = p.feed("\x1b[1;38;2;1;2;3mtext\x1b[0m\n");
  assert.strictEqual(out, '<span class="b">text</span>\n');
});

// ---- NUL heartbeat filler is invisible -------------------------------------
test("NUL bytes (server heartbeat filler) never appear in rendered output", () => {
  const p = createParser();
  const out = p.feed("before\x00\x00\x00after\n");
  assert.strictEqual(out, "beforeafter\n");
});

// ---- HTML escaping ----------------------------------------------------------
test("shell output containing HTML-special characters is escaped, not injected", () => {
  const p = createParser();
  const out = p.feed("<script>alert(1)</script> & \"quotes\"\n");
  assert.strictEqual(out, "&lt;script&gt;alert(1)&lt;/script&gt; &amp; \"quotes\"\n");
});

// ---- realistic composite: something close to actual sudo/setup output -----
test("realistic composite chunk (colored log line + sudo prompt text) renders correctly", () => {
  const p = createParser();
  const out = p.feed(
    "\x1b[33m[17:55:51] === BASE ===\x1b[0m\r\n" +
    "[sudo] password for nixbys: "
  );
  assert.strictEqual(
    out,
    '<span class="fg33">[17:55:51] === BASE ===</span>\n[sudo] password for nixbys: '
  );
});

console.log(`\n${passed} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
