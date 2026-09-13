// Exercise the real Config migration without loading Quickshell or writing config.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../../modules/common/Config.qml'), 'utf8');
const start = source.indexOf('    function migrateRaw(raw) {');
const end = source.indexOf('\n    // list<var>/list<string>', start);
assert.ok(start >= 0 && end > start);
const version = Number(source.match(/currentConfigVersion:\s*(\d+)/)[1]);
assert.ok(version >= 19, 'The production schema must run the new migration');
const context = vm.createContext({root: {currentConfigVersion: version}, console: {log() {}}});
vm.runInContext(source.slice(start, end), context);

for (const enabled of [false, true]) {
    const config = {configVersion: 18, cheatsheet: {keepKeybindsLoaded: enabled, superKey: 'custom'}};
    assert.equal(context.migrateRaw(config), true);
    assert.deepEqual(config, {configVersion: version, cheatsheet: {keepLastTabLoaded: enabled, superKey: 'custom'}});
    assert.equal(context.migrateRaw(config), false, 'Already migrated config is unchanged');
}
const explicit = {configVersion: 18, cheatsheet: {keepLastTabLoaded: false, keepKeybindsLoaded: true}};
context.migrateRaw(explicit);
assert.deepEqual(explicit.cheatsheet, {keepLastTabLoaded: false});

const invalidLegacy = {configVersion: 18, cheatsheet: {keepKeybindsLoaded: 'false'}};
context.migrateRaw(invalidLegacy);
assert.deepEqual(invalidLegacy.cheatsheet, {}, 'Do not copy an invalid type into the new option');

for (const cheatsheet of [undefined, null, [], 'invalid']) {
    const config = {configVersion: 18, cheatsheet};
    context.migrateRaw(config);
    assert.equal(config.cheatsheet, cheatsheet, 'Malformed containers remain for the existing repair pass');
}
console.log('PASS: cache migration preserves opt-out, explicit new values, unrelated fields and idempotence.');
