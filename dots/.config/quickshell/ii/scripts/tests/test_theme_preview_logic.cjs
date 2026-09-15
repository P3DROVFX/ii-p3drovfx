// Run with node scripts/tests/test_theme_preview_logic.cjs.
// No shell, no Quickshell, no file writes outside /tmp.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');

const rootPath = path.resolve(__dirname, '../..');
const logicContext = vm.createContext({});
vm.runInContext(
    fs.readFileSync(path.join(rootPath, 'services/themePreview/ThemePreviewLogic.js'), 'utf8')
        .replace(/^\.pragma library\s*/, ''),
    logicContext);
const logic = logicContext;

// The module runs inside a vm context, so its object literals carry that
// context's prototype and deepStrictEqual refuses them. Comparing the
// serialised shape says the same thing and is what these assertions are about.
const same = (actual, expected, message) =>
    assert.equal(JSON.stringify(actual), JSON.stringify(expected), message);

const SEED = { 'scheme-tonal-spot': { primary: '#111111' } };
const USER = { 'scheme-tonal-spot': { primary: '#222222' } };

// ── Which document answers ──────────────────────────────────────────────────
// The user's own previews win even when the shell is on the shipped wallpaper:
// they describe the image the swatches are being derived from.
same(logic.resolvePreviews(USER, SEED, true), USER);
same(logic.resolvePreviews(USER, SEED, false), USER);

// The seed answers only for the wallpaper it describes.
same(logic.resolvePreviews({}, SEED, true), SEED);
same(logic.resolvePreviews(null, SEED, true), SEED);

// A user's wallpaper with nothing generated is empty, which is what sends a
// swatch to the generation instead of painting colours from another image.
same(logic.resolvePreviews({}, SEED, false), {});
same(logic.resolvePreviews(null, null, true), {});

// ── Mode ────────────────────────────────────────────────────────────────────
assert.equal(logic.previewMode(false, true), 'dark');
assert.equal(logic.previewMode(false, false), 'light');
// A forced dark terminal palette pins the previews too, or the swatches would
// disagree with the file a switchwall run produces.
assert.equal(logic.previewMode(true, false), 'dark');
assert.equal(logic.previewMode(undefined, true), 'dark');
assert.equal(logic.previewMode(null, false), 'light');

// ── Whether a swatch may start the shared generation ────────────────────────
const decision = (state) => logic.generationDecision(Object.assign({
    ready: false, wallpaper: '/img.png', mode: 'dark',
    generatedFor: '', generating: false
}, state));

// Known colours: nothing to do, and no process.
same(decision({ ready: true }), { handled: true, start: false, reason: 'known' });
assert.equal(decision({ ready: true, wallpaper: '' }).start, false);

// No wallpaper at all: this one cannot be helped, so the caller owns the fallback.
same(decision({ wallpaper: '' }), { handled: false, start: false, reason: 'no-wallpaper' });

// First swatch of the grid owns the process; the rest ride along on it. This is
// what keeps eleven schemes from opening eleven pythons.
same(decision({}), { handled: true, start: true, reason: 'start' });
same(decision({ generatedFor: 'dark|/img.png', generating: true }),
    { handled: true, start: false, reason: 'running' });

// A generation that already failed for this exact pair must not loop: the
// swatch goes on to its own process instead.
same(decision({ generatedFor: 'dark|/img.png', generating: false }),
    { handled: false, start: false, reason: 'attempted' });

// A different mode or a different image is a new question, and gets a new try.
assert.equal(decision({ generatedFor: 'light|/img.png', generating: false }).start, true);
assert.equal(decision({ generatedFor: 'dark|/other.png', generating: false }).start, true);

// ── Quoting a path into the bash that activates the venv ────────────────────
const hostile = [
    '/home/user/Pictures/wall one.png',
    "/home/user/it's.png",
    '/tmp/$(touch /tmp/pwned).png',
    '/tmp/`touch /tmp/pwned`.png',
    '/tmp/a"; rm -rf /tmp/nope; echo ".png',
    '/tmp/explode$(id).png',
];
for (const value of hostile) {
    // The quoted form has to come back byte-for-byte from a real shell, and must
    // not run whatever the path pretends to be.
    const echoed = execFileSync('bash', ['-c', `printf %s ${logic.shellQuote(value)}`]).toString();
    assert.equal(echoed, value, `round trip failed for ${value}`);
}
assert.equal(fs.existsSync('/tmp/pwned'), false, 'a path was executed as a command');
assert.equal(fs.existsSync('/tmp/nope'), false, 'a path was executed as a command');

// The command ThemePreviewCache builds has to keep quoting, and keep passing the
// termscheme: without it the generator exits non-zero after writing.
const cache = fs.readFileSync(path.join(rootPath, 'services/ThemePreviewCache.qml'), 'utf8');
assert.ok(cache.includes('PreviewLogic.shellQuote('), 'the generator command must quote every path');
assert.ok(cache.includes('--termscheme'), 'the generator needs a termscheme or it exits non-zero');

console.log('OK: preview source, generation gating and shell quoting');
