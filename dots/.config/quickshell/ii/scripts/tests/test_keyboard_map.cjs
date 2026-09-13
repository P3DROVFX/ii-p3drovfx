// Run with node scripts/tests/test_keyboard_map.cjs. No HID, desktop, or file writes.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const rootPath = path.resolve(__dirname, '../..');
const read = p => fs.readFileSync(path.join(rootPath, p), 'utf8');
const map = vm.createContext({});
vm.runInContext(read('modules/common/functions/KeyboardMap.js'), map);
const layoutText = read('modules/ii/overview/typing/TypingKeyboardLayouts.qml');
const layouts = vm.runInContext('(' + layoutText.split('readonly property var layouts: (')[1].split('\n    })')[0] + '\n})', map);

for (const [id, rows] of Object.entries(layouts)) {
    const board = map.manual(rows, id);
    assert.ok(board);
    assert.equal(map.problem(board), '');
    assert.ok(board.keys.every(k => k.x + k.w <= board.width && k.y + k.h <= board.height));
    const changed = map.editKey(board, 0, 0, 'á', 'keyboard_command_key', 'Ação');
    assert.equal(board.layers[0][0].label, 'Esc');
    assert.equal(changed.layers[0][0].label, 'á');
    assert.equal(map.normalized(JSON.parse(JSON.stringify(changed))).layers[0][0].icon, 'keyboard_command_key');
}

const board = map.manual(layouts.qwerty, 'qwerty');
board.source = 'vial'; board.deviceUid = 'test-board';
board.layers[0][0].code = 4; board.layers[0][0].resolvedCode = 4;
const edit = map.editKey(board, 0, 0, 'Custom', 'code', 'note');
const snapshot = JSON.parse(JSON.stringify(board)); snapshot.available = true;
assert.equal(map.refreshed(edit, snapshot).layers[0][0].label, 'Custom');
snapshot.layers[0][0].resolvedCode = 5;
assert.notEqual(map.refreshed(edit, snapshot).layers[0][0].label, 'Custom');
snapshot.layers[0][0].resolvedCode = 4;
snapshot.layers[0][0].code = 5;
assert.notEqual(map.refreshed(edit, snapshot).layers[0][0].label, 'Custom');
snapshot.layers[0][0].code = 4;
snapshot.deviceUid = 'different';
assert.notEqual(map.refreshed(edit, snapshot).layers[0][0].label, 'Custom');
for (const mutate of [x => x.keys.push(x.keys[0]), x => x.layers[0].pop(), x => x.width = 0, x => x.keys[0].w = NaN, x => x.keys[0] = null]) {
    const invalid = JSON.parse(JSON.stringify(board)); mutate(invalid);
    assert.ok(map.problem(invalid)); assert.equal(map.normalized(invalid), null);
}

// Execute the actual pure persistence methods, with the IO boundary replaced.
// This catches a serializer silently dropping keyboard metadata on legacy pages,
// mixed collections, imports or successive edits.
const serviceText = read('services/KeybindsService.qml');
const service = { schemaVersion: 3, maxPages: 500, maxKeybindsPerPage: 10000, pages: [], ready: true, writable: true };
const context = vm.createContext({ root: service, KeyboardMap: map,
    Translation: { tr: s => s }, KeybindTokenizer: { canonical: s => s },
    writeDebounce: { restart() {} } });
vm.runInContext('String.prototype.arg = function(value) { return this.replace(/%[1-9]/, String(value)); }; Translation = {tr: s => String(s)};', context);
for (const match of serviceText.matchAll(/^    function (\w+)\(([^\n]*)\): \w+ \{([\s\S]*?)^    }/gm)) {
    const [, name, args, body] = match;
    service[name] = vm.runInContext(`(function(${args}) {${body}\n})`, context);
}
service.operationFinished = () => {};
service.publish = d => { service.pages = d.pages; };
const legacy = { schemaVersion: 2, pages: [{ id: 'app', name: 'Editor', keybinds: [{ id: 'shortcut', keys: 'Ctrl+S', description: 'Save' }] }] };
assert.equal(service.documentProblem(legacy, true), '');
service.pages = service.normalizedDocument(legacy).pages;
const id = service.createKeyboardPage(board); assert.ok(id);
assert.equal(service.pages[0].keybinds[0].keys, 'Ctrl+S');
assert.equal(service.pageById(id).kind, 'keyboard');
assert.equal(service.pageById(id).keyboard.keys.length, board.keys.length);
assert.equal(service.updateKeyboardKey(id, 0, 1, 'Save', 'save', 'Save file'), true);
assert.equal(service.updateKeyboardKey(id, 0, 2, 'á', 'none', ''), true);
const encoded = service.serializedDocument(service.currentDocument());
const roundTrip = JSON.parse(encoded);
assert.equal(service.documentProblem(roundTrip, true), '');
assert.equal(roundTrip.pages[1].keyboard.layers[0][1].icon, 'save');
assert.equal(roundTrip.pages[1].keyboard.layers[0][2].label, 'á');
const detected = JSON.parse(JSON.stringify(board)); detected.available = true;
const beforeDetectionCount = service.pages.length;
assert.equal(service.importKeyboardSnapshot(detected), id);
assert.equal(service.pages.length, beforeDetectionCount);
assert.equal(service.importKeyboardSnapshot(null), '');
assert.equal(service.pages.length, beforeDetectionCount);
const imported = service.importPayload({schemaVersion: 3, page: roundTrip.pages[1]});
assert.ok(imported); assert.notEqual(imported, id);
assert.equal(service.pageById(imported).keyboard.layers[0][1].label, 'Save');
const invalid = JSON.parse(encoded); invalid.pages[1].keyboard.layers[0].pop();
assert.notEqual(service.documentProblem(invalid, true), '');

// Real ABNT2 symbols through the same read-only helper used by the button.
const cp = require('node:child_process');
const systemBoard = JSON.parse(cp.execFileSync('python3', [path.join(rootPath, 'scripts/typing/system_keyboard.py'), '--preset', 'abnt2'], {encoding:'utf8'}));
systemBoard.source = 'system'; systemBoard.deviceUid = 'xkb:test-br';
const brId = service.importSystemKeyboardSnapshot(systemBoard);
assert.ok(brId);
const br = service.pageById(brId).keyboard;
assert.equal(br.layout, 'br'); assert.equal(br.source, 'system');
assert.equal(br.layerNames[2], 'AltGr'); assert.equal(br.preset, 'abnt2');
const cedilla = systemBoard.keys.findIndex(k => k.name === 'AC10');
assert.equal(br.layers[0][cedilla].label, 'ç');
service.updateKeyboardKey(brId, 0, cedilla, 'Minha tecla', 'code', 'custom');
const countBeforeRefresh = service.pages.length;
assert.equal(service.importSystemKeyboardSnapshot(systemBoard), brId);
assert.equal(service.pages.length, countBeforeRefresh);
assert.equal(service.pageById(brId).keyboard.layers[0][cedilla].label, 'Minha tecla');
systemBoard.layers[0][cedilla].resolvedCode++;
service.importSystemKeyboardSnapshot(systemBoard);
assert.equal(service.pageById(brId).keyboard.layers[0][cedilla].label, 'ç');
assert.equal(service.importSystemKeyboardSnapshot({available:false, error:'not connected'}), '');
assert.equal(service.pages.length, countBeforeRefresh);
const brRoundTrip = JSON.parse(service.serializedDocument(service.currentDocument())).pages.find(p => p.id === brId);
assert.equal(brRoundTrip.keyboard.source, 'system');
assert.equal(brRoundTrip.keyboard.layerNames[2], 'AltGr');
console.log('PASS: manual/Vial/system layouts, geometry, editing, refresh preservation/invalidation, legacy migration, mixed pages and export/import.');
