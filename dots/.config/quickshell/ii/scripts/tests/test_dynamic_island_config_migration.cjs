// Run with node scripts/tests/test_dynamic_island_config_migration.cjs
//
// Contract for the v22 -> v23 config migration, which moves the Dynamic Island out of
// ~40 flat keys under `bar.floatingNotch` and into its own block.
//
// The block is extracted from Config.qml and executed as-is, so this tests the shipping
// code rather than a copy of it. A migration that loses a user's settings is the kind of
// bug you only find in someone else's config, months later.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const configSource = fs.readFileSync(path.join(root, 'modules/common/Config.qml'), 'utf8');

// Slice the whole `if (from < 23 …) { … }` statement by walking its braces, guard
// included - the guard is part of the contract: a config with no island block at all
// must be left untouched rather than crash the migration.
function extractStatement(source, marker) {
    const start = source.indexOf(marker);
    assert.notEqual(start, -1, `migration block not found: ${marker}`);
    let depth = 0;
    let i = source.indexOf('{', start);
    for (; i < source.length; i++) {
        if (source[i] === '{') depth++;
        else if (source[i] === '}') {
            depth--;
            if (depth === 0) return source.slice(start, i + 1);
        }
    }
    throw new Error('unbalanced migration block');
}

const statement = extractStatement(configSource, 'if (from < 23 &&');
const cleanup = extractStatement(configSource, 'if (from < 24) {');

function runCleanup(raw, from = 23) {
    const context = vm.createContext({ raw, from, Array, Object, console: { log() {} } });
    vm.runInContext(`(function () {\n${cleanup}\n})()`, context);
    return raw;
}

function migrate(raw, from = 22) {
    const context = vm.createContext({
        raw,
        from,
        Array,
        Object,
        console: { log() {} },
    });
    vm.runInContext(`(function () {\n${statement}\n})()`, context);
    return raw;
}

// A v22 config as an existing user would have it: the island on in bar-centre mode, a
// couple of activities turned off, two custom heights.
function legacyConfig(overrides = {}) {
    return {
        configVersion: 22,
        bar: {
            cornerStyle: 0,
            floatingNotch: Object.assign({
                enable: false,
                centerInBar: true,
                autoHide: false,
                dropShadow: true,
                clickToExpand: false,
                onlyShowOnSingleMonitor: true,
                singleMonitorName: 'eDP-1',
                disableMedia: false,
                disableClipboard: true,
                disableAiStatus: false,
                disableKdeConnectInLocalSend: true,
                checklistAlwaysVisible: true,
                heightMedia: 52,
                heightClipboard: 40,
                heightHome: 36,
            }, overrides),
        },
    };
}

const tests = [];
function test(name, fn) { tests.push([name, fn]); }

test('the island ends up enabled when either legacy switch was on', () => {
    assert.equal(migrate(legacyConfig()).dynamicIsland.enable, true, 'centerInBar counts');
    assert.equal(
        migrate(legacyConfig({ enable: true, centerInBar: false })).dynamicIsland.enable, true,
        'the floating switch counts');
    assert.equal(
        migrate(legacyConfig({ enable: false, centerInBar: false })).dynamicIsland.enable, false);
});

test('an existing user keeps the notch look', () => {
    // "pills" is the default for a fresh install only: silently changing how an existing
    // user's shell looks is not a migration.
    assert.equal(migrate(legacyConfig()).dynamicIsland.style, 'notch');
});

test('disable<Widget> inverts into widgets.<id>.enable', () => {
    const island = migrate(legacyConfig()).dynamicIsland;
    assert.equal(island.widgets.clipboard.enable, false, 'disableClipboard was true');
    assert.equal(island.widgets.media.enable, true, 'disableMedia was false');
    assert.equal(island.widgets.ai.enable, true, 'disableAiStatus -> widgets.ai');
});

test('contracted heights follow their activity', () => {
    const island = migrate(legacyConfig()).dynamicIsland;
    assert.equal(island.widgets.media.notchHeight, 52);
    assert.equal(island.widgets.clipboard.notchHeight, 40);
    assert.equal(island.widgets.clock.notchHeight, 36, 'heightHome belongs to the clock');
});

test('the monitor preference inverts into followFocus', () => {
    const pinned = migrate(legacyConfig()).dynamicIsland.monitor;
    assert.equal(pinned.followFocus, false);
    assert.equal(pinned.name, 'eDP-1');

    const following = migrate(legacyConfig({ onlyShowOnSingleMonitor: false })).dynamicIsland.monitor;
    assert.equal(following.followFocus, true);
});

test('notch-only settings land under notch', () => {
    const island = migrate(legacyConfig({ clickToExpand: true })).dynamicIsland;
    assert.equal(island.notch.centerInBar, true);
    assert.equal(island.notch.clickToExpand, true);
});

test('extra compact is dropped rather than carried over', () => {
    // It scaled the whole surface to fake a smaller island; the engine sizes the notch
    // from its activities, so the option has nothing left to mean.
    const migrated = migrate(legacyConfig({ extraCompact: true }));
    assert.equal(migrated.dynamicIsland.notch.extraCompact, undefined);
    assert.equal(migrated.bar.floatingNotch.extraCompact, undefined,
        'the old key must go, or it comes back as an unknown key');
});

test('behaviour and appearance keys are carried over', () => {
    const island = migrate(legacyConfig({ autoHide: true, dropShadow: false })).dynamicIsland;
    assert.equal(island.behavior.autoHide, true);
    assert.equal(island.appearance.dropShadow, false);
});

test('the KDE Connect column inverts rather than inheriting a disable flag', () => {
    const island = migrate(legacyConfig()).dynamicIsland;
    assert.equal(island.widgets.localSend.kdeConnectColumn, false,
        'disableKdeConnectInLocalSend was true');
});

test('the legacy block survives the migration', () => {
    // The legacy notch surface and the current settings page still read it; deleting it
    // here would drop an existing user's island settings.
    const migrated = migrate(legacyConfig());
    assert.ok(migrated.bar.floatingNotch, 'bar.floatingNotch must still be there');
    assert.equal(migrated.bar.floatingNotch.centerInBar, true);
});

test('migrating twice changes nothing and never overwrites a chosen value', () => {
    const once = migrate(legacyConfig());
    once.dynamicIsland.style = 'pills';
    once.dynamicIsland.widgets.media.enable = false;
    const twice = migrate(JSON.parse(JSON.stringify(once)));
    assert.equal(twice.dynamicIsland.style, 'pills', 'a chosen style is not reset');
    assert.equal(twice.dynamicIsland.widgets.media.enable, false,
        'a chosen widget toggle is not reset');
});

test('a config with no island block at all is left alone', () => {
    const raw = { configVersion: 22, bar: { cornerStyle: 0 } };
    migrate(raw);
    assert.equal(raw.dynamicIsland, undefined);
});

test('a config already at v23 is not migrated again', () => {
    const raw = legacyConfig();
    migrate(raw, 23);
    assert.equal(raw.dynamicIsland, undefined, 'the version guard has to hold');
});

test('every activity the registry knows gets an entry it can read', () => {
    // A descriptor with no config entry means its toggle silently does nothing.
    const registry = fs.readFileSync(
        path.join(root, 'modules/ii/dynamicIsland/core/IslandRegistry.qml'), 'utf8');
    const ids = [...registry.matchAll(/^\s*id: "([a-zA-Z]+)",$/gm)].map(m => m[1]);
    const schema = configSource.slice(configSource.indexOf('property JsonObject dynamicIsland'));
    const widgets = schema.slice(schema.indexOf('property JsonObject widgets'));
    for (const id of ids) {
        assert.ok(widgets.includes(`property JsonObject ${id}: JsonObject {`),
            `no config entry for registry activity "${id}"`);
    }
});

test('a config already at v23 still loses the extra compact key', () => {
    const raw = {
        configVersion: 23,
        bar: { floatingNotch: { extraCompact: true, enable: true } },
        dynamicIsland: { notch: { extraCompact: true, centerInBar: false } },
    };
    runCleanup(raw);
    assert.equal(raw.bar.floatingNotch.extraCompact, undefined);
    assert.equal(raw.dynamicIsland.notch.extraCompact, undefined);
    assert.equal(raw.bar.floatingNotch.enable, true, 'nothing else may be touched');
});

let failed = 0;
for (const [name, fn] of tests) {
    try {
        fn();
        console.log(`  ok   ${name}`);
    } catch (error) {
        failed++;
        console.log(`  FAIL ${name}\n       ${error.message}`);
    }
}
console.log(`\n${tests.length - failed}/${tests.length} passed`);
process.exit(failed === 0 ? 0 : 1);
