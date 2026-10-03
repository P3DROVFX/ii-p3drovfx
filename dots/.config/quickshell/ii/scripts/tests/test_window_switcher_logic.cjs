// Run with node scripts/tests/test_window_switcher_logic.cjs
//
// Behaviour of Alt+Tab's pure logic (services/windowSwitcher/WindowSwitcherLogic.js): which
// windows the switcher lists and in what order, what a search matches and highlights, where
// the keys move the selection, how a peeked window is read back from hyprctl, and the corner
// path the peek draws. No QML or compositor needed.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const context = vm.createContext({ Math, Number, String, JSON, isFinite, RegExp, Array, Set, Object });
vm.runInContext(
    fs.readFileSync(path.join(root, 'services/windowSwitcher/WindowSwitcherLogic.js'), 'utf8')
        .replace(/^\.pragma library\s*/, ''),
    context);
const L = context;

let failures = 0;
function test(name, fn) {
    try {
        fn();
        console.log(`ok - ${name}`);
    } catch (error) {
        failures++;
        console.log(`not ok - ${name}\n  ${error.message.split('\n').join('\n  ')}`);
    }
}

function client(address, extra = {}) {
    return Object.assign({
        address, class: 'kitty', title: `win ${address}`, mapped: true, hidden: false,
        workspace: { id: 1, name: '1' }, monitor: 0, at: [0, 0], size: [800, 600],
        floating: false, fullscreen: 0, focusHistoryID: 5
    }, extra);
}
const everything = { includeOtherWorkspaces: true, visibleWorkspaceIds: [1], monitor: -1, appClass: '' };
// Arrays made inside the vm context have its own Array prototype: copy them out to compare.
const plain = value => JSON.parse(JSON.stringify(value));
const addresses = list => plain(list.map(e => e.address));

test('addresses are normalised to 0x form', () => {
    assert.equal(L.normalisedAddress('abc'), '0xabc');
    assert.equal(L.normalisedAddress('0xabc'), '0xabc');
    assert.equal(L.normalisedAddress(' '), '');
    assert.equal(L.normalisedAddress(undefined), '');
});

test('snapshot orders by focus history with the focused window first', () => {
    const clients = [client('0x1', { focusHistoryID: 2 }), client('0x2', { focusHistoryID: 0 }), client('0x3', { focusHistoryID: 1 })];
    // Stale stack says 0x2 is focused; the event socket says 0x3.
    assert.deepEqual(addresses(L.snapshot(clients, {}, everything, '0x3')), ['0x3', '0x2', '0x1']);
    assert.deepEqual(addresses(L.snapshot(clients, {}, everything, '')), ['0x2', '0x3', '0x1']);
});

test('torn-down, unmapped and grouped-away windows are left out', () => {
    const clients = [client('0x1'), client('0x2', { mapped: false }), client('0x3', { workspace: { id: -1 } }),
        client('0x4', { hidden: true })];
    assert.deepEqual(addresses(L.snapshot(clients, {}, everything, '')), ['0x1']);
});

test('special workspaces count as windows and are marked', () => {
    const [entry] = L.snapshot([client('0x1', { workspace: { id: -98, name: 'special:magic' } })], {}, everything, '');
    assert.equal(entry.special, true);
});

test('workspace filter keeps only what is on screen', () => {
    const clients = [client('0x1', { workspace: { id: 1 } }), client('0x2', { workspace: { id: 2 } })];
    const onScreen = Object.assign({}, everything, { includeOtherWorkspaces: false, visibleWorkspaceIds: [2] });
    assert.deepEqual(addresses(L.snapshot(clients, {}, onScreen, '')), ['0x2']);
});

test('current monitor filter is separate from the workspace filter', () => {
    const clients = [client('0x1', { monitor: 0 }), client('0x2', { monitor: 1, workspace: { id: 7 } })];
    const monitorOne = Object.assign({}, everything, { monitor: 1 });
    assert.deepEqual(addresses(L.snapshot(clients, {}, monitorOne, '')), ['0x2']);
    assert.deepEqual(addresses(L.snapshot(clients, {}, everything, '')).sort(), ['0x1', '0x2']);
});

test('app filter keeps one app, whatever the case of its class', () => {
    const clients = [client('0x1', { class: 'firefox' }), client('0x2', { class: 'kitty' }), client('0x3', { class: 'Firefox' })];
    const firefox = Object.assign({}, everything, { appClass: 'firefox' });
    assert.deepEqual(addresses(L.snapshot(clients, {}, firefox, '')).sort(), ['0x1', '0x3']);
});

test('reconcile keeps order, drops the gone, appends the new', () => {
    const before = L.snapshot([client('0x1', { focusHistoryID: 0 }), client('0x2', { focusHistoryID: 1 })], {}, everything, '');
    const after = L.reconcile(before, [client('0x2', { title: 'renamed' }), client('0x3'), client('0x1')], {}, everything);
    assert.deepEqual(addresses(after), ['0x1', '0x2', '0x3']);
    assert.equal(after[1].title, 'renamed');
    assert.deepEqual(addresses(L.reconcile(before, [client('0x2')], {}, everything)), ['0x2']);
});

test('the app name joins the search', () => {
    const entries = L.snapshot([client('0x1', { class: 'zen', title: 'Inbox' }), client('0x2', { class: 'kitty', title: 'zsh' })],
        {}, everything, '', cls => cls === 'zen' ? 'Zen Browser' : '');
    assert.equal(entries[0].appName, 'Zen Browser');
    assert.equal(entries[1].appName, 'kitty');
    assert.deepEqual(addresses(L.filtered(entries, 'brow')), ['0x1']);
});

test('search tiers: word start, then anywhere, then letters in order', () => {
    const e = (address, title) => ({ address, appClass: 'app', appName: 'App', title, toplevel: null });
    const list = [e('in-order', 'f x o y o'), e('anywhere', 'xfoo'), e('word', 'the foo bar'), e('none', 'bar')];
    assert.deepEqual(addresses(L.filtered(list, 'foo')), ['word', 'anywhere', 'in-order']);
    assert.equal(L.matchTier(list[3], 'foo'), -1);
    assert.deepEqual(addresses(L.filtered(list, '  ')), addresses(list));
});

test('matched characters: a word start first, then a substring, then letters in order', () => {
    assert.deepEqual(plain(L.matchedIndices('Xfoo foo', 'foo')), [5, 6, 7]);
    assert.deepEqual(plain(L.matchedIndices('xfoo', 'foo')), [1, 2, 3]);
    assert.deepEqual(plain(L.matchedIndices('f-x-o', 'fo')), [0, 4]);
    assert.deepEqual(plain(L.matchedIndices('abc', 'z')), []);
    assert.deepEqual(plain(L.matchedIndices('abc', '')), []);
});

test('highlighting escapes the title and wraps only the matched characters', () => {
    assert.equal(L.highlighted('a<b> fo', 'fo', '#ff0000'), 'a&lt;b&gt; <b><font color="#ff0000">fo</font></b>');
    assert.equal(L.highlighted('x & y', '', '#000'), 'x &amp; y');
});

test('stepping wraps both ways', () => {
    assert.equal(L.stepIndex(0, -1, 3), 2);
    assert.equal(L.stepIndex(2, 1, 3), 0);
    assert.equal(L.stepIndex(0, 1, 0), 0);
});

test('Up/Down on the grid wrap to the same column', () => {
    // 7 cards, 4 columns: row 0 = 0..3, row 1 = 4..6.
    assert.equal(L.stepRow(1, 1, 7, 4), 5);
    assert.equal(L.stepRow(5, 1, 7, 4), 1);
    // Column 3 has no second row: up from it lands on the last card.
    assert.equal(L.stepRow(3, -1, 7, 4), 6);
    assert.equal(L.stepRow(1, -1, 7, 4), 5);
    // One row: Up/Down are Left/Right.
    assert.equal(L.stepRow(1, 1, 3, 4), 2);
});

test('Alt+1…9 picks window N only when it exists', () => {
    assert.equal(L.jumpIndex('1', 5), 0);
    assert.equal(L.jumpIndex('5', 5), 4);
    assert.equal(L.jumpIndex('6', 5), -1);
    assert.equal(L.jumpIndex('0', 5), -1);
});

test('the position counter is 1-based', () => {
    assert.equal(L.positionText(3, 17), '4 / 17');
    assert.equal(L.positionText(0, 0), '');
});

test('workspace labels: none here, a name elsewhere, specials marked', () => {
    assert.equal(L.workspaceLabel({ workspaceId: 1, workspaceName: '1' }, 1).text, '');
    assert.deepEqual(Object.assign({}, L.workspaceLabel({ workspaceId: 3, workspaceName: '3' }, 1)), { text: '3', special: false });
    assert.deepEqual(Object.assign({}, L.workspaceLabel({ workspaceId: -98, workspaceName: 'special:magic', special: true }, 1)),
        { text: 'magic', special: true });
    assert.equal(L.workspaceLabel({ workspaceId: -99, workspaceName: 'special', special: true }, 1).text, 'special');
});

test('one hyprctl batch asks everything the peek needs, in parseable order', () => {
    const batch = L.windowLookBatch('0xabc');
    assert.equal(batch.split('; ').length, 17);
    assert.match(batch, /^getprop address:0xabc opacity; /);
    assert.match(batch, /j\/getoption decoration:dim_inactive/);
});

test('the batch answer is read back into the window look', () => {
    // As `hyprctl --batch` prints it: answers separated by two blank lines.
    const answers = ['1', 'false', '1', 'true', '0.9', 'false',
        '{"option": "decoration:active_opacity", "float": 0.850000, "set": true }',
        '{"option": "decoration:fullscreen_opacity", "float": 1.000000, "set": false }',
        '{"option": "decoration:inactive_opacity", "float": 0.800000, "set": true }',
        '2', 'aac6bfff 0deg', '595959aa', '18', '2.5', 'false',
        '{"option": "decoration:dim_inactive", "bool": true, "set": true }',
        '{"option": "decoration:dim_special", "float": 0.300000, "set": true }'];
    const look = L.parseWindowLook(answers.join('\n\n\n') + '\n');
    assert.equal(look.active, 0.85);
    assert.equal(look.fullscreen, 1);
    assert.ok(Math.abs(look.inactive - 0.72) < 1e-9);
    assert.equal(look.border, 2);
    assert.equal(look.borderColor, '#aac6bfff');
    assert.equal(look.inactiveBorderColor, '#595959aa');
    assert.equal(look.rounding, 18);
    assert.equal(look.roundingPower, 2.5);
    assert.equal(look.dimmed, true);
    assert.equal(look.dimSpecial, 0.3);
    // An override takes the rule's opacity as it is; no_dim already set means no undimming.
    answers[1] = 'true';
    answers[14] = 'true';
    const overridden = L.parseWindowLook(answers.join('\n\n\n'));
    assert.equal(overridden.active, 1);
    assert.equal(overridden.dimmed, false);
});

test('a failed batch falls back to an opaque, borderless, circular window', () => {
    const look = L.parseWindowLook('');
    assert.equal(look.active, 1);
    assert.equal(look.border, 0);
    assert.equal(look.borderColor, 'transparent');
    assert.equal(look.roundingPower, 2);
    assert.equal(look.dimmed, false);
});

test('corner path: closed, inside the box, squarer with a higher rounding power', () => {
    const points = d => d.replace(/[MLZ]/g, ' ').trim().split(/\s+/).map(Number);
    const circle = points(L.roundedPath(100, 60, 20, 2));
    const squircle = points(L.roundedPath(100, 60, 20, 4));
    for (const p of [circle, squircle]) {
        for (let i = 0; i < p.length; i += 2) {
            assert.ok(p[i] >= -0.01 && p[i] <= 100.01, `x ${p[i]}`);
            assert.ok(p[i + 1] >= -0.01 && p[i + 1] <= 60.01, `y ${p[i + 1]}`);
        }
    }
    assert.match(L.roundedPath(100, 60, 20, 2), / Z$/);
    // The 45° point of the top-right corner sits further out on the squarer corner.
    const mid = p => [p[2 + 2 * 6], p[3 + 2 * 6]];
    assert.ok(mid(squircle)[0] > mid(circle)[0]);
    assert.ok(mid(squircle)[1] < mid(circle)[1]);
    // No rounding: a plain rectangle; a radius too big for the box is clamped.
    assert.equal(L.roundedPath(10, 10, 0, 2), 'M 0 0 L 10 0 L 10 10 L 0 10 Z');
    assert.ok(!/NaN/.test(L.roundedPath(10, 10, 50, 2.5)));
});

test('stacking: tiled under floating, focus order inside each, the peeked one raised', () => {
    const e = (address, floating, focusOrder, fullscreen = false) => ({ address, floating, focusOrder, fullscreen });
    const list = [e('t-old', false, 5), e('f-new', true, 0), e('t-new', false, 1), e('f-old', true, 3)];
    assert.deepEqual(addresses(L.stacking(list, '')), ['t-old', 't-new', 'f-old', 'f-new']);
    // A tiled window peeked at stays under the floating ones, on top of the tiled.
    assert.deepEqual(addresses(L.stacking(list, 't-old')), ['t-new', 't-old', 'f-old', 'f-new']);
    // A fullscreen one goes over everything.
    list[0].fullscreen = true;
    assert.deepEqual(addresses(L.stacking(list, 't-old')).at(-1), 't-old');
});

test('springStep: settles without overshoot and keeps its speed on a retarget', () => {
    const k = 300, c = 2 * 0.9 * Math.sqrt(k);
    const run = (offset, velocity, seconds) => {
        let s = [offset, velocity], low = offset;
        for (let t = 0; t < seconds; t += 1 / 60) {
            s = L.springStep(s[0], s[1], 1 / 60, k, c, 0.1);
            low = Math.min(low, s[0]);
        }
        return { s, low };
    };
    // 300 px away: at rest within half a second, never more than a pixel past the target.
    const settled = run(300, 0, 0.5);
    assert.deepEqual(plain(settled.s), [0, 0]);
    assert.ok(settled.low > -1, `overshot to ${settled.low}`);
    // Mid-flight the velocity carries on: one step from moving is not one step from rest.
    const moving = L.springStep(100, -800, 1 / 60, k, c, 0.1);
    const fromRest = L.springStep(100, 0, 1 / 60, k, c, 0.1);
    assert.ok(moving[0] < fromRest[0]);
    // A long frame is clamped and still stable.
    assert.ok(Math.abs(L.springStep(300, 0, 2, k, c, 0.1)[0]) < 300);
});

if (failures > 0) {
    console.log(`\n${failures} failed`);
    process.exit(1);
}
console.log('\nall passed');
