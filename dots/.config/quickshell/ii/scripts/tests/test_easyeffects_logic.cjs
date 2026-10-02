// Run with node scripts/tests/test_easyeffects_logic.cjs
//
// Contract for the EasyEffects integration's pure helpers
// (services/easyEffects/EasyEffectsLogic.js) and the generated effect table
// (EasyEffectsPlugins.js). The editor rewrites real preset files, so the parts that
// decide what lands in them are pinned here: a new effect's block must carry every
// choice key (EasyEffects keeps the previous preset's choice when one is missing) and
// every band section (the banded loaders throw on a missing one), chain edits must
// not touch other blocks, and socket values must use EasyEffects' encoding.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
function load(file) {
    const context = vm.createContext({ Math, Number, JSON, isFinite, String, Array, Object, Date, parseInt, isNaN });
    vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8').replace(/^\.pragma library\s*/, ''), context);
    return context;
}
const L = load('services/easyEffects/EasyEffectsLogic.js');
const table = load('services/easyEffects/EasyEffectsPlugins.js').plugins;

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    console.log(`ok - ${name}`);
}

test('families split on the common separators', () => {
    assert.deepEqual(JSON.parse(JSON.stringify(L.splitName('A50 · Music'))), { family: 'A50', label: 'Music' });
    assert.equal(L.familyOf('Speakers - Movies'), 'Speakers');
    assert.equal(L.familyOf('HD600: Harman'), 'HD600');
    assert.equal(L.familyOf('Flat'), '');
    assert.equal(L.shortName('A50 · Voices'), 'Voices');
    assert.equal(L.shortName('Loudness'), 'Loudness');
});

test('device scope keeps to the default preset family', () => {
    const all = ['A50 · Movies', 'A50 · Music', 'Speakers · Music', 'Flat'];
    assert.deepEqual(Array.from(L.presetsForDevice(all, 'A50 · Music', '', 'device')), ['A50 · Movies', 'A50 · Music']);
    assert.deepEqual(Array.from(L.presetsForDevice(all, '', 'Speakers · Music', 'device')), ['Speakers · Music']);
    assert.deepEqual(Array.from(L.presetsForDevice(all, '', 'Flat', 'device')), all);
    assert.deepEqual(Array.from(L.presetsForDevice(all, 'A50 · Music', '', 'all')), all);
    assert.deepEqual(Array.from(L.presetsForDevice(all, 'Nope · X', '', 'device')), all);
});

test('stepping wraps and starts from an end when the current preset is unknown', () => {
    const list = ['a', 'b', 'c'];
    assert.equal(L.stepPreset(list, 'c', 1), 'a');
    assert.equal(L.stepPreset(list, 'a', -1), 'c');
    assert.equal(L.stepPreset(list, 'x', 1), 'a');
    assert.equal(L.stepPreset(list, 'x', -1), 'c');
    assert.equal(L.stepPreset([], 'x', 1), '');
});

test('icons come from the preset label', () => {
    assert.equal(L.iconFor('A50 · Music'), 'music_note');
    assert.equal(L.iconFor('Speakers · Movies'), 'movie');
    assert.equal(L.iconFor('A50 · Voices'), 'record_voice_over');
    assert.equal(L.iconFor('Mystery'), 'graphic_eq');
});

test('autoload keys match what EasyEffects writes', () => {
    assert.equal(L.routeFor({ 'device.routes': 1, 'device.profile.description': 'Speaker' }), 'Speaker');
    assert.equal(L.routeFor({ 'device.routes': 0, 'device.profile.description': 'Pro 1' }), '');
    assert.equal(L.autoloadFileName('alsa_output.usb-X.pro-output-1', ''), 'alsa_output.usb-X.pro-output-1:.json');
    const entries = [{ device: 'd', 'device-profile': 'Headphones', 'preset-name': 'h' },
        { device: 'd', 'device-profile': 'Speaker', 'preset-name': 's' }];
    assert.equal(L.autoloadFor(entries, 'd', 'Speaker')['preset-name'], 's');
    assert.equal(L.autoloadFor(entries, 'd', 'Other')['preset-name'], 'h');
    assert.equal(L.autoloadFor(entries, 'x', ''), null);
});

test('rc files parse into groups', () => {
    const rc = L.parseRc('[Presets]\nlastLoadedOutputPreset=A50 · Music\n\n[StreamOutputs]\nplugins=equalizer#0,limiter#0\n');
    assert.equal(rc.Presets.lastLoadedOutputPreset, 'A50 · Music');
    assert.equal(rc.StreamOutputs.plugins, 'equalizer#0,limiter#0');
});

test('preset names are sanitised and deduplicated', () => {
    assert.equal(L.sanitizePresetName('  ../My/Preset  '), 'My Preset');
    assert.equal(L.sanitizePresetName('.hidden'), 'hidden');
    assert.equal(L.uniqueName('A', ['A', 'A (2)']), 'A (3)');
});

test('every effect in the table has a complete default block', () => {
    for (const plugin of Object.keys(table)) {
        const block = L.defaultBlock(table, plugin);
        assert.ok(block, plugin);
        for (const control of table[plugin].controls) {
            const holder = control.section ? block[control.section] : block;
            assert.ok(holder && control.key in holder, `${plugin}: ${control.key}`);
            if (control.type === 'enum')
                assert.ok(control.options.includes(holder[control.key]), `${plugin}: ${control.key} default is a choice`);
        }
    }
});

test('banded effects get every band section', () => {
    const eq = L.defaultBlock(table, 'equalizer');
    const count = eq['num-bands'];
    assert.ok(count > 0);
    for (const channel of ['left', 'right']) {
        for (let n = 0; n < count; n++)
            assert.ok(eq[channel][`band${n}`] && 'type' in eq[channel][`band${n}`], `eq ${channel} band${n}`);
    }
    const mbc = L.defaultBlock(table, 'multiband_compressor');
    for (let n = 0; n < table.multiband_compressor.bands.count; n++)
        assert.ok(mbc[`band${n}`], `mbc band${n}`);
    assert.ok(!('enable-band' in mbc.band0), 'band 0 has no enable key');
    assert.ok('enable-band' in mbc.band1);
    const ms = L.defaultBlock(table, 'midside_equalizer');
    assert.ok(ms.mid && ms.side);
});

test('chain edits touch only the chain and the effect in question', () => {
    const preset = { output: { blocklist: [], plugins_order: ['equalizer#0', 'limiter#0'],
        'equalizer#0': { bypass: false }, 'limiter#0': { bypass: false } } };
    const added = L.addEffect(preset, 'output', table, 'limiter', 1);
    assert.deepEqual(Array.from(added.output.plugins_order), ['equalizer#0', 'limiter#1', 'limiter#0']);
    assert.ok(added.output['limiter#1'].mode);
    assert.deepEqual(Array.from(preset.output.plugins_order), ['equalizer#0', 'limiter#0'], 'input untouched');

    const removed = L.removeEffect(added, 'output', 'equalizer#0');
    assert.deepEqual(Array.from(removed.output.plugins_order), ['limiter#1', 'limiter#0']);
    assert.ok(!('equalizer#0' in removed.output));

    const moved = L.moveEffect(removed, 'output', 1, 0);
    assert.deepEqual(Array.from(moved.output.plugins_order), ['limiter#0', 'limiter#1']);
    assert.equal(L.nextInstanceId(['limiter#0', 'limiter#2'], 'limiter'), 'limiter#1');
});

test('values are written at their section', () => {
    let preset = { output: { plugins_order: ['equalizer#0'], 'equalizer#0': { left: { band0: { gain: 0 } } } } };
    preset = L.setValue(preset, 'output', 'equalizer#0', 'left/band0', 'gain', 3.5);
    preset = L.setValue(preset, 'output', 'equalizer#0', '', 'input-gain', -2);
    assert.equal(L.valueAt(preset, 'output', 'equalizer#0', 'left/band0', 'gain'), 3.5);
    assert.equal(L.valueAt(preset, 'output', 'equalizer#0', '', 'input-gain'), -2);
    assert.equal(L.valueAt(preset, 'output', 'equalizer#0', 'right/band0', 'gain'), undefined);
});

test('socket encoding matches the server', () => {
    const mode = table.limiter.controls.find(c => c.key === 'mode');
    assert.equal(L.encodeValue(mode, mode.options[2]), '2');
    assert.equal(L.encodeValue(mode, 'nope'), null);
    assert.equal(L.decodeValue(mode, '2'), mode.options[2]);
    const bypass = table.limiter.controls.find(c => c.key === 'bypass');
    assert.equal(L.encodeValue(bypass, true), 'true');
    assert.equal(L.decodeValue(bypass, 'false'), false);
    const gain = table.limiter.controls.find(c => c.key === 'input-gain');
    assert.equal(L.decodeValue(gain, '7.74'), 7.74);
    assert.equal(L.decodeValue(gain, 'error_property_not_found'), undefined);
    assert.equal(L.socketPath('limiter#0', gain), 'limiter:0:inputGain');
    const bandGain = table.equalizer.bands.controls.find(c => c.key === 'gain');
    assert.equal(L.socketPath('equalizer#0', bandGain, 3, 'left'), 'equalizer:0:left:band3Gain');
    assert.equal(L.socketPath('midside_equalizer#0', bandGain, 3, 'mid'), '');
});

test('labels, units and formatting', () => {
    assert.equal(L.labelFor('alr-knee-smooth'), 'ALR knee smooth');
    assert.equal(L.unitFor('input-gain'), 'dB');
    assert.equal(L.unitFor('attack'), 'ms');
    assert.equal(L.unitFor('split-frequency'), 'Hz');
    assert.equal(L.formatValue({ key: 'frequency', type: 'double' }, 2500), '2.5 kHz');
    assert.equal(L.formatValue({ key: 'input-gain', type: 'double' }, -7.6), '-7.6 dB');
    assert.ok(L.isLogControl({ key: 'frequency', type: 'double', min: 10, max: 24000 }));
});

test('the equalizer response follows its bands', () => {
    const freqs = L.logFrequencies(64, 20, 20000);
    assert.equal(freqs.length, 64);
    const flat = L.equalizerResponse({ band0: { type: 'Bell', gain: 0, frequency: 1000, q: 1 } }, 1, freqs);
    assert.ok(flat.every(v => Math.abs(v) < 1e-6));
    const bell = L.equalizerResponse({ band0: { type: 'Bell', gain: 6, frequency: 1000, q: 1 } }, 1, [1000, 50]);
    assert.ok(Math.abs(bell[0] - 6) < 0.05, `peak ${bell[0]}`);
    assert.ok(Math.abs(bell[1]) < 0.5);
    const shelf = L.equalizerResponse({ band0: { type: 'Lo-shelf', gain: 7.74, frequency: 105, q: 0.7 } }, 1, [20]);
    assert.ok(shelf[0] > 6, `shelf ${shelf[0]}`);
    const muted = L.equalizerResponse({ band0: { type: 'Bell', gain: 6, frequency: 1000, q: 1, mute: true } }, 1, [1000]);
    assert.equal(muted[0], 0);
});

test('the chain response sums the switched-on equalizers and ignores the rest', () => {
    const band = gain => ({ band0: { type: 'Bell', gain, frequency: 1000, q: 1 } });
    const preset = {
        output: {
            plugins_order: ['autogain#0', 'equalizer#0', 'equalizer#1'],
            'autogain#0': { bypass: false },
            'equalizer#0': { bypass: false, 'num-bands': 1, 'split-channels': false, left: band(6), right: band(6) },
            'equalizer#1': { bypass: true, 'num-bands': 1, 'split-channels': false, left: band(6), right: band(6) }
        }
    };
    assert.ok(Math.abs(L.chainResponse(preset, 'output', [1000])[0] - 6) < 0.05);
    assert.deepEqual(Array.from(L.chainResponse(preset, 'input', [1000, 50])), [0, 0]);
    assert.deepEqual(Array.from(L.chainResponse(null, 'output', [1000])), [0]);
    preset.output['equalizer#0']['split-channels'] = true;
    preset.output['equalizer#0'].right = band(0);
    assert.ok(Math.abs(L.chainResponse(preset, 'output', [1000])[0] - 3) < 0.05, 'split channels average');
    assert.deepEqual(Array.from(L.chainPlugins(preset, 'output')), ['autogain', 'equalizer', 'equalizer']);
});

test('controls get a glyph from their key and fall back to the generic one', () => {
    assert.equal(L.controlIcon('input-gain'), 'input');
    assert.equal(L.controlIcon('output-gain'), 'volume_up');
    assert.equal(L.controlIcon('target'), 'my_location');
    assert.equal(L.controlIcon('silence-threshold'), 'volume_mute');
    assert.equal(L.controlIcon('threshold'), 'vertical_align_center');
    assert.equal(L.controlIcon('lpf-frequency'), 'graphic_eq');
    assert.equal(L.controlIcon('something-new'), 'tune');
    assert.equal(L.controlIcon(undefined), 'tune');
});

test('the strongest band of an equalizer is the one that moves the sound most', () => {
    const block = gains => ({ 'num-bands': gains.length, left: Object.fromEntries(gains.map((g, i) => ['band' + i, { type: i === 0 ? 'Lo-shelf' : 'Bell', gain: g, frequency: i === 0 ? 31 : 1000 }])) });
    assert.deepEqual(JSON.parse(JSON.stringify(L.strongestBand(block([4, 1, 0]), 'left'))), { gain: 4, type: 'Lo-shelf', frequency: 31 });
    assert.equal(L.strongestBand(block([0, -2.5, 1]), 'left').gain, -2.5);
    assert.equal(L.strongestBand(block([0, 0]), 'left'), null);
    assert.equal(L.strongestBand(null, 'left'), null);
    assert.equal(L.unitFor('target'), 'dB');
});

console.log(`\n${passed} passed`);
