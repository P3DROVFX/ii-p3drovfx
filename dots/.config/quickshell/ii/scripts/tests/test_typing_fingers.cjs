// Offline physical fingering tests. No HID access, desktop events, or IPC.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const f = vm.createContext({});
vm.runInContext(read('modules/ii/overview/typing/TypingFingers.js'), f);
const layoutText = read('modules/ii/overview/typing/TypingKeyboardLayouts.qml');
const layouts = vm.runInContext('(' + layoutText.split('readonly property var layouts: (')[1].split('\n    })')[0] + '\n})', f);
const plain = v => JSON.parse(JSON.stringify(v));
for (const [id, rows] of Object.entries(layouts)) {
    const b = f.classicBoard(rows, id);
    assert.equal(b.keys.length, rows.flat().length + 1);
    // Same physical positions have the same fingering in every language.
    assert.deepEqual(plain(b.fingers.slice(0, 10)), [-5, -4, -3, -2, -2, 2, 2, 3, 4, 5]);
    assert.equal(b.fingers.at(-1), 6);
    rows.flat().forEach((ch, i) => assert.ok(f.targets(b.entries, ch.toUpperCase()).includes(i)));
    assert.ok(b.keys.every(k => k.x >= 0 && k.x + k.w <= b.width));
}
const corne = JSON.parse(read('docs/keyboards/corne-v4.1/cheatsheet-current.json')).page.keyboard;
const fingers = f.infer(corne.keys);
const expectedColumns = [-5, -5, -4, -3, -2, -2, -2];
corne.keys.forEach((key, i) => {
    const expected = key.row % 4 === 3 ? (key.row < 4 ? -1 : 1)
        : expectedColumns[key.col] * (key.row < 4 ? 1 : -1);
    assert.equal(fingers[i], expected, JSON.stringify(key));
});
// Reordering firmware keys and remapping labels must not alter assignments.
const reordered = corne.keys.slice().reverse();
assert.deepEqual(plain(f.infer(reordered)), plain(fingers.slice().reverse()));
for (const layer of corne.layers) {
    assert.equal(f.assignments(fingers, corne.keys, 'corne', []).length, layer.length);
}
const grid = (cols, rotation = 0) => Array.from({length: 3 * cols}, (_, i) => ({
    row: Math.floor(i / cols), col: i % cols, x: i % cols, y: Math.floor(i / cols),
    w: 1, h: 1, r: rotation, rx: 0, ry: 0
}));
assert.deepEqual(plain(f.infer(grid(10)).slice(0, 10)), [-5, -4, -3, -2, -2, 2, 2, 3, 4, 5]);
assert.deepEqual(plain(f.infer(grid(12)).slice(0, 12)), [-5, -5, -4, -3, -2, -2, 2, 2, 3, 4, 5, 5]);
assert.deepEqual(plain(f.infer(grid(10, 12))), plain(f.infer(grid(10))));
// Conventional ANSI/ISO and the number row are geometric, not label-based.
const full = [];
function row(y, widths) {
    let x = 0;
    widths.forEach((w, col) => {full.push({row:y,col,x,y,w,h:1,r:0,rx:0,ry:0});x+=w;});
}
row(0, [...Array(13).fill(1), 2]);
row(1, [1.5, ...Array(12).fill(1), 1.5]);
row(2, [1.75, ...Array(11).fill(1), 2.25]);
row(3, [2.25, ...Array(10).fill(1), 2.75]);
row(4, [1.25,1.25,1.25,6.25,1.25,1.25,1.25,1.25]);
const fullFingers = f.infer(full);
function at(row, col) {return fullFingers[full.findIndex(k => k.row === row && k.col === col)];}
assert.deepEqual(Array.from({length:10},(_,i)=>at(2,i+1)),[-5,-4,-3,-2,-2,2,2,3,4,5]);
assert.deepEqual(Array.from({length:10},(_,i)=>at(1,i+1)),[-5,-4,-3,-2,-2,2,2,3,4,5]);
assert.deepEqual(Array.from({length:10},(_,i)=>at(3,i+1)),[-5,-4,-3,-2,-2,2,2,3,4,5]);
assert.deepEqual(Array.from({length:10},(_,i)=>at(0,i+1)),[-5,-4,-3,-2,-2,2,2,3,4,5]);
assert.equal(at(4,3),6);
assert.deepEqual(plain(f.infer(grid(3))), Array(9).fill(0));
const encoder = {...corne.keys[0], encoder: true};
assert.equal(f.infer([...corne.keys, encoder]).at(-1), 0);
// Overrides survive label/layer changes, are isolated per UID, accept neutral,
// and are serialized as strings (safe in a nested Quickshell JsonObject).
let saved = f.saveAssignment([], 'board:a', corne.keys[0], -2);
saved = f.saveAssignment(saved, 'board:b', corne.keys[0], 4);
assert.equal(f.assignments(fingers, corne.keys, 'board:a', saved)[0], -2);
assert.equal(f.assignments(fingers, corne.keys, 'board:b', saved)[0], 4);
saved = f.saveAssignment(saved, 'board:a', corne.keys[0], 0);
assert.equal(saved.length, 2);
assert.equal(f.assignments(fingers, corne.keys, 'board:a', saved)[0], 0);
saved = f.resetBoard(saved, 'board:a');
assert.equal(saved.length, 1);
assert.equal(f.assignments(fingers, corne.keys, 'board:a', saved)[0], fingers[0]);
assert.ok(saved.every(item => typeof item === 'string'));
assert.deepEqual(plain(f.targets([{char:'á'},{char:'a'},{char:'Á'},{char:''}], 'Á')), [0,2]);
assert.deepEqual(plain(f.targets([{char:'a'}], 'á')), []);
assert.deepEqual(plain(f.targets([{char:''}], '')), []);
console.log('Typing fingers: static layouts, Corne, layers, rotated grids, ANSI/ISO, overrides and Unicode passed.');
