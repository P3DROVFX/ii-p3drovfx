const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const aodCode = fs.readFileSync(path.join(root, 'modules/common/functions/aod.js'), 'utf8')
    .replace(/^\.pragma library\s*/, '');

// Mock Qt
const Qt = {
    Key_Shift: 1,
    Key_Control: 2,
    Key_Alt: 3,
    Key_AltGr: 4,
    Key_Meta: 5,
    Key_Super_L: 6,
    Key_Super_R: 7,
    Key_Hyper_L: 8,
    Key_Hyper_R: 9,
    Key_A: 65,
    Key_Space: 32
};

let fakeTime = 100000;
const FakeDate = {
    now: () => fakeTime
};

const context = vm.createContext({
    Math,
    Qt,
    Date: FakeDate,
    console
});

vm.runInContext(aodCode, context);
const Aod = context;

let passed = 0;
function test(name, fn) {
    Aod.resetMotion();
    fakeTime = 100000;
    fn();
    passed++;
    console.log(`✓ ${name}`);
}

test('keyWakes ignores modifier keys and accepts regular keys', () => {
    assert.equal(Aod.keyWakes(Qt.Key_Super_L), false);
    assert.equal(Aod.keyWakes(Qt.Key_Control), false);
    assert.equal(Aod.keyWakes(Qt.Key_Shift), false);
    assert.equal(Aod.keyWakes(Qt.Key_A), true);
    assert.equal(Aod.keyWakes(Qt.Key_Space), true);
});

test('single brief desk bump does not wake', () => {
    // Bump at t=0
    assert.equal(Aod.registerMouseMove("DP-1", 100, 100), false);
    fakeTime += 20;
    assert.equal(Aod.registerMouseMove("DP-1", 103, 102), false);
    fakeTime += 30;
    assert.equal(Aod.registerMouseMove("DP-1", 104, 103), false);

    // Bump ends, 1 second passes with no movement
    fakeTime += 1000;
    // Next touch should start fresh, not wake
    assert.equal(Aod.registerMouseMove("DP-1", 105, 105), false);
});

test('moving for 500ms then stopping does not wake', () => {
    assert.equal(Aod.registerMouseMove("DP-1", 100, 100), false);
    for (let t = 20; t <= 500; t += 20) {
        fakeTime += 20;
        assert.equal(Aod.registerMouseMove("DP-1", 100 + t, 100), false);
    }
    // Stop moving. Wait 500ms.
    fakeTime += 500;
    // Movement stopped; next movement is after gap threshold, starts fresh
    assert.equal(Aod.registerMouseMove("DP-1", 605, 100), false);
});

test('continuous movement for at least 1 second wakes', () => {
    assert.equal(Aod.registerMouseMove("DP-1", 100, 100), false);
    let woke = false;
    for (let t = 20; t <= 1200; t += 20) {
        fakeTime += 20;
        if (Aod.registerMouseMove("DP-1", 100 + t, 100)) {
            woke = true;
            assert.ok(t >= 1000, `Should wake after at least 1000ms, woke at ${t}ms`);
            break;
        }
    }
    assert.equal(woke, true);
});

test('wiggling mouse back and forth in place for 1 second wakes', () => {
    assert.equal(Aod.registerMouseMove("DP-1", 100, 100), false);
    let woke = false;
    let x = 100;
    let dir = 1;
    for (let t = 20; t <= 1200; t += 20) {
        fakeTime += 20;
        x += dir * 10;
        if (x > 150) dir = -1;
        if (x < 100) dir = 1;
        if (Aod.registerMouseMove("DP-1", x, 100)) {
            woke = true;
            assert.ok(t >= 1000, `Woke at ${t}ms`);
            break;
        }
    }
    assert.equal(woke, true);
});

test('pause of >300ms in the middle resets streak', () => {
    assert.equal(Aod.registerMouseMove("DP-1", 100, 100), false);
    // Move for 600ms
    for (let t = 20; t <= 600; t += 20) {
        fakeTime += 20;
        assert.equal(Aod.registerMouseMove("DP-1", 100 + t, 100), false);
    }
    // Pause for 350ms (> 300ms gap threshold)
    fakeTime += 350;
    // Move for another 600ms (total time elapsed is > 1000ms, but streak was broken)
    let woke = false;
    for (let t = 20; t <= 600; t += 20) {
        fakeTime += 20;
        if (Aod.registerMouseMove("DP-1", 700 + t, 100)) {
            woke = true;
            break;
        }
    }
    // Should NOT have woken during the second 600ms because it restarted
    assert.equal(woke, false);

    // Keep moving for another 450ms (now continuous streak from reset is > 1000ms)
    for (let t = 20; t <= 450; t += 20) {
        fakeTime += 20;
        if (Aod.registerMouseMove("DP-1", 1300 + t, 100)) {
            woke = true;
            break;
        }
    }
    assert.equal(woke, true);
});

test('moving across monitors keeps time without false jump distance', () => {
    assert.equal(Aod.registerMouseMove("DP-1", 100, 100), false);
    let woke = false;
    for (let t = 20; t <= 1100; t += 20) {
        fakeTime += 20;
        const screen = t < 500 ? "DP-1" : "HDMI-A-1";
        const x = t < 500 ? (100 + t) : (t - 500 + 50);
        if (Aod.registerMouseMove(screen, x, 100)) {
            woke = true;
            assert.ok(t >= 1000, `Woke at ${t}ms`);
            break;
        }
    }
    assert.equal(woke, true);
});

console.log(`\nAll ${passed} tests passed successfully.`);

