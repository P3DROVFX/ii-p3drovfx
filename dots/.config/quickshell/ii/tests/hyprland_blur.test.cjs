const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');
const {test} = require('node:test');
const root = path.resolve(__dirname, '..');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'modules/common/HyprlandBlur.js'), 'utf8').replace(/^\.pragma library\s*/, ''), context);

function evaluate(size, options) {
    const script = context.buildScript(size, options);
    // Parse the actual emitted Lua, without contacting the compositor.
    const result = execFileSync('lua', ['-e', `
        hl = {config = function(c)
            for k,v in pairs(c.decoration.blur) do print(k .. '=' .. tostring(v)) end
        end}
        assert(load(io.read('*a')))()
    `], {input: script, encoding: 'utf8'});
    return Object.fromEntries(result.trim().split('\n').map(line => {
        const [key, value] = line.split('=');
        return [key, value === 'true' ? true : value === 'false' ? false : Number(value)];
    }));
}

test('old presets without advanced blur options retain the II defaults', () => {
    const values = evaluate(17, undefined);
    assert.equal(values.size, 17);
    assert.equal(values.passes, 3);
    assert.equal(values.noise, 0.05);
    assert.equal(values.contrast, 0.89);
    assert.equal(values.brightness, 1);
    assert.equal(values.vibrancy_darkness, 0.2);
    assert.equal(values.input_methods_ignorealpha, 0.8);
    assert.equal(evaluate(0, {}).size, 0);
});

test('size and passes use integers, while color adjustments retain fine precision', () => {
    const values = evaluate(23.8, {passes: 4.3, noise: 0.137, contrast: 1.367, brightness: 1.728, vibrancy: 0.621, vibrancyDarkness: 0.456});
    assert.equal(values.size, 24);
    assert.equal(values.passes, 4);
    assert.equal(values.noise, 0.137);
    assert.equal(values.contrast, 1.367);
    assert.equal(values.brightness, 1.728);
    assert.equal(values.vibrancy, 0.621);
    assert.equal(values.vibrancy_darkness, 0.456);
});

test('invalid presets cannot emit out-of-range values or inject Lua', () => {
    const values = evaluate(-10, {passes: 100, noise: Infinity, contrast: -1, brightness: 20, vibrancy: NaN, vibrancyDarkness: '0 }); os.exit(1)', inputMethodsIgnoreAlpha: -5, popupsIgnoreAlpha: 8});
    assert.equal(values.size, 0);
    assert.equal(values.passes, 10);
    assert.equal(values.noise, 0.05);
    assert.equal(values.contrast, 0);
    assert.equal(values.brightness, 2);
    assert.equal(values.vibrancy, 0.2);
    assert.equal(values.vibrancy_darkness, 0.2);
    assert.equal(values.input_methods_ignorealpha, 0);
    assert.equal(values.popups_ignorealpha, 1);
    assert.equal(evaluate(1000, {}).size, 100);
});

test('reapplying appearance does not re-enable blur disabled by Game Mode', () => {
    assert.equal('enabled' in evaluate(10, {enabled: true}), false);
});

test('X-ray follows optimization availability without changing its saved preference', () => {
    const options = {xray: true, newOptimizations: false, ignoreOpacity: false, special: true, popups: true, inputMethods: false};
    const values = evaluate(10, options);
    assert.equal(values.xray, false);
    assert.equal(options.xray, true);
    assert.equal(values.ignore_opacity, false);
    assert.equal(values.special, true);
    assert.equal(values.popups, true);
    assert.equal(values.input_methods, false);
    options.newOptimizations = true;
    assert.equal(evaluate(10, options).xray, true);
});

test('blur keys have one settings owner, and every new label is translated', () => {
    const gui = fs.readFileSync(path.join(root, 'services/HyprlandGui.qml'), 'utf8');
    for (const key of Object.keys(evaluate(10, {})))
        assert.ok(gui.includes(`"decoration:blur:${key}": "windows"`), key);
    const page = fs.readFileSync(path.join(root, 'modules/settings/configs/WindowsConfig.qml'), 'utf8').split('title: Translation.tr("Gaps")')[0];
    for (const lang of ['en_US', 'pt_BR']) {
        const translations = JSON.parse(fs.readFileSync(path.join(root, `translations/${lang}.json`), 'utf8'));
        for (const [, label] of page.matchAll(/Translation\.tr\("([^"]+)"\)/g))
            assert.ok(label in translations, `${lang}: ${label}`);
    }
});
