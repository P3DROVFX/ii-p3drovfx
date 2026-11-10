// Run with node scripts/tests/test_closed_windows_logic.cjs
//
// Behaviour of the reopen-closed-window logic (services/closedWindows/ClosedWindowsLogic.js):
// what a window's record keeps, which closes are remembered, how the app starts again and the
// Lua Hyprland is sent to place it. No QML or compositor needed.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const context = vm.createContext({ Math, Number, String, JSON, isFinite, RegExp, Array, Set, Object });
vm.runInContext(
    fs.readFileSync(path.join(root, 'services/closedWindows/ClosedWindowsLogic.js'), 'utf8')
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

const plain = value => JSON.parse(JSON.stringify(value));
const monitors = [{ id: 0, x: 0, y: 0 }, { id: 1, x: 1920, y: 0 }];
function client(address, extra = {}) {
    return Object.assign({
        address, pid: 100, class: 'kitty', title: 'shell', workspace: { id: 3, name: '3' },
        monitor: 1, at: [2020, 140], size: [800, 600], floating: false, fullscreen: 0
    }, extra);
}
function record(extra = {}) {
    return Object.assign(plain(L.recordFor(client('0xa'), null, monitors, 1000)), extra);
}
const proc = (extra = {}) => Object.assign({
    argv: ['kitty', '-1', 'claude'], cwd: '/home/u', flatpakId: '', appImage: '', cgroup: 'app-kitty-1.scope', exeOk: true
}, extra);
const opts = { ignoredClasses: ['org.quickshell', 'Hyprpolkitagent'], minLifetimeMs: 1500 };

test('a record keeps the workspace, geometry relative to its monitor, and when it was first seen', () => {
    const first = L.recordFor(client('a'), null, monitors, 1000);
    assert.deepEqual(plain(first), {
        address: '0xa', pid: 100, appClass: 'kitty', title: 'shell', workspaceId: 3, workspaceName: '3',
        floating: false, fullscreen: 0, at: [2020, 140], localAt: [100, 140], size: [800, 600], firstSeen: 1000, floatedAtOpen: false, reopened: false
    });
    // Floating since it opened is decided once: floating it later does not make it a dialog.
    const floatedLater = L.recordFor(client('a', { floating: true }), first, monitors, 2000);
    assert.equal(floatedLater.floatedAtOpen, false);
    assert.equal(L.recordFor(client('b', { floating: true }), null, monitors, 2000).floatedAtOpen, true);
    assert.equal(L.recordFor(client('a'), first, monitors, 9000).firstSeen, 1000);
});

test('a window parked on the lock workspace keeps the workspace it had before the lock', () => {
    const before = L.recordFor(client('a'), null, monitors, 1000);
    const locked = L.recordFor(client('a', { workspace: { id: 10001, name: '10001' } }), before, monitors, 2000);
    assert.equal(locked.workspaceId, 3);
    assert.equal(locked.workspaceName, '3');
});

test('the probe output parses into the shell pid and one entry per process', () => {
    const text = 'self\x1d42\x1e'
        + '100\x1dkitty\x1f-1\x1fclaude\x1d/home/u\x1d\x1d\x1dapp-kitty.scope\x1d1\x1e'
        + '200\x1d/app/bin/x\x1d/\x1dorg.x.App\x1d\x1dapp-flatpak-org.x.App-1.scope\x1d0\x1e';
    const parsed = plain(L.parseProbe(text));
    assert.equal(parsed.selfPid, 42);
    assert.deepEqual(parsed.procs[100].argv, ['kitty', '-1', 'claude']);
    assert.equal(parsed.procs[100].exeOk, true);
    assert.equal(parsed.procs[200].flatpakId, 'org.x.App');
});

test('closes worth remembering pass, the rest say why not', () => {
    assert.equal(L.skipReason(record(), proc(), [], opts, 5000, 42), '');
    assert.equal(L.skipReason(record({ appClass: '' }), proc(), [], opts, 5000, 42), 'no class');
    assert.equal(L.skipReason(record({ appClass: 'hyprpolkitagent' }), proc(), [], opts, 5000, 42), 'ignored class');
    assert.equal(L.skipReason(record({ pid: 42 }), proc(), [], opts, 5000, 42), "the shell's own window");
    assert.equal(L.skipReason(record(), proc({ argv: ['/usr/bin/qs', '-c', 'ii'] }), [], opts, 5000, 0), "the shell's own window");
    assert.equal(L.skipReason(record(), proc(), [], opts, 2000, 42), 'too short-lived');
});

test('a reopened window counts however soon it closes again', () => {
    assert.equal(L.skipReason(record({ reopened: true }), proc(), [], opts, 1100, 42), '');
    const before = L.recordFor(client('a'), null, monitors, 1000);
    before.reopened = true;
    assert.equal(L.recordFor(client('a'), before, monitors, 1200).reopened, true);
});

test('a window floating since it opened, over a bigger window of its process on its workspace, is a dialog', () => {
    const dialog = record({ address: '0xd', floating: true, floatedAtOpen: true, size: [500, 400] });
    const main = record({ address: '0xm', size: [1600, 1000] });
    assert.equal(L.skipReason(dialog, proc(), [main], opts, 5000, 42, {}), 'dialog');
    // The process's last window, or a tiled one, is a real window.
    assert.equal(L.skipReason(dialog, proc(), [], opts, 5000, 42, {}), '');
    assert.equal(L.skipReason(record({ address: '0xd', size: [500, 400] }), proc(), [main], opts, 5000, 42, {}), '');
    // Another process's bigger window says nothing about this one.
    assert.equal(L.skipReason(dialog, proc(), [record({ address: '0xm', pid: 7, size: [1600, 1000] })], opts, 5000, 42, {}), '');
});

test('the dialog guess leaves real floating windows alone', () => {
    const small = { address: '0xd', floating: true, floatedAtOpen: true, size: [500, 400] };
    const main = record({ address: '0xm', size: [1600, 1000] });
    // Floated by hand after it opened.
    assert.equal(L.skipReason(record(Object.assign({}, small, { floatedAtOpen: false })), proc(), [main], opts, 5000, 42, {}), '');
    // Its bigger sibling is on another workspace (a scratchpad terminal).
    assert.equal(L.skipReason(record(Object.assign({}, small, { workspaceId: -98, workspaceName: 'special:scratch' })),
        proc(), [main], opts, 5000, 42, {}), '');
    // The process runs several real windows (kitty -1).
    assert.equal(L.skipReason(record(small), proc(), [main], opts, 5000, 42, { 100: true }), '');
});

test('a process with two tiled windows at once runs several real windows', () => {
    const list = [record({ address: '0x1' }), record({ address: '0x2' }), record({ address: '0x3', pid: 7 }),
        record({ address: '0x4', pid: 7, floating: true })];
    assert.deepEqual(plain(L.tiledPids(list)), [100]);
});

test('the start command: Flatpak, then AppImage, then the command line, then the desktop entry', () => {
    const entry = { command: ['nautilus', '--new-window'], workingDirectory: '' };
    assert.equal(L.launchFor(proc({ flatpakId: 'org.x.App' }), entry).command, 'exec flatpak run org.x.App');
    assert.equal(L.launchFor(proc({ appImage: '/home/u/Apps/X.AppImage', argv: ['/tmp/.mount_x/AppRun', 'f.txt'] }), entry).command,
        'cd /home/u 2>/dev/null; exec /home/u/Apps/X.AppImage f.txt');
    assert.equal(L.launchFor(proc(), entry).command, 'cd /home/u 2>/dev/null; exec kitty -1 claude');
    assert.equal(L.launchFor(proc({ argv: ['nautilus', '--gapplication-service'] }), entry).source, 'desktop');
    assert.equal(L.launchFor(proc({ cgroup: 'dbus-:1.2-org.gnome.Nautilus@0.service' }), entry).source, 'desktop');
    assert.equal(L.launchFor(proc({ exeOk: false }), entry).command, 'exec nautilus --new-window');
    assert.equal(L.launchFor(null, entry).source, 'desktop');
    assert.equal(L.launchFor(null, null), null);
});

test('arguments are quoted for the shell', () => {
    assert.equal(L.shellCommand(['mpv', "it's a film.mkv", '$HOME'], '/tmp/my dir'),
        `cd '/tmp/my dir' 2>/dev/null; exec mpv 'it'\\''s a film.mkv' '$HOME'`);
});

test('placement rules: the workspace always, size and place only for a floating window', () => {
    const kept = 'maximize';
    assert.deepEqual(plain(L.placementRules(record())), { workspace: '3 silent', suppress_event: kept });
    assert.deepEqual(plain(L.placementRules(record({ floating: true }))),
        { workspace: '3 silent', suppress_event: kept, float: true, size: '800 600', move: '100 140' });
    assert.deepEqual(plain(L.placementRules(record({ fullscreen: 2, floating: true }))),
        { workspace: '3 silent', suppress_event: kept, fullscreen: true });
    assert.deepEqual(plain(L.placementRules(record({ fullscreen: 1 }))), { workspace: '3 silent', maximize: true });
    assert.equal(L.placementRules(record({ workspaceId: -98, workspaceName: 'special:magic' })).workspace, 'special:magic silent');
    assert.equal(L.placementRules(record({ workspaceId: 7, workspaceName: 'mail' })).workspace, 'name:mail silent');
});

test('the exec dispatch is valid Lua, whatever the command holds', () => {
    assert.equal(L.execDispatch(`exec say "hi" \\ there\n`, { workspace: '3 silent', float: true }),
        'hl.dsp.exec_cmd("exec say \\"hi\\" \\\\ there\\n", { workspace = "3 silent", float = true })');
    assert.equal(L.luaString('a\x01b'), '"a\\001b"');
});

test('the fallback moves the window, and floats it back to its size and place', () => {
    assert.deepEqual(plain(L.fallbackDispatches('0xb', record())),
        ['hl.dsp.window.move({ workspace = "3", follow = false, window = "address:0xb" })']);
    const floating = plain(L.fallbackDispatches('0xb', record({ floating: true })));
    assert.equal(floating.length, 4);
    assert.equal(floating[3], 'hl.dsp.window.move({ x = 2020, y = 140, window = "address:0xb" })');
});

test('a window opening during a reopen is ours only with the same class, before the deadline', () => {
    const pending = { record: record(), deadline: 10000 };
    const opened = data => plain(L.parseOpenWindow(data));
    assert.deepEqual(opened('b,3,kitty,a, b'), { address: '0xb', workspaceName: '3', appClass: 'kitty', title: 'a, b' });
    assert.equal(L.pendingVerdict(pending, opened('b,3,kitty,x'), 5000), 'placed');
    assert.equal(L.pendingVerdict(pending, opened('b,1,Kitty,x'), 5000), 'move');
    assert.equal(L.pendingVerdict(pending, opened('b,1,firefox,x'), 5000), '');
    assert.equal(L.pendingVerdict(pending, opened('b,1,kitty,x'), 20000), '');
    const named = { record: record({ workspaceId: 7, workspaceName: 'mail' }), deadline: 10000 };
    assert.equal(L.pendingVerdict(named, opened('b,mail,kitty,x'), 5000), 'placed');
});

test('the stack keeps the newest entries, up to its depth', () => {
    let stack = [];
    for (let i = 1; i <= 4; i++)
        stack = L.pushed(stack, i, 3);
    assert.deepEqual(plain(stack), [2, 3, 4]);
});

if (failures > 0) {
    console.log(`\n${failures} failed`);
    process.exit(1);
}
