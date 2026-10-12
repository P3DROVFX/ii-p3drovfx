import QtQuick

/**
 * Caps lock and num lock as the keyboard LEDs show them.
 *
 * SDDM's Wayland keyboard backend never updates `keyboard.capsLock` or
 * `keyboard.numLock`, and Qt key events carry no lock state, so the greeter
 * reads the LEDs the compositor drives, from sysfs (like the battery: needs
 * QML_XHR_ALLOW_FILE_READ=1). Keyboards are numbered differently from boot to
 * boot, so the LEDs are found by probing once. A lock counts as on when any
 * keyboard lights it. Without any LED (an X11 greeter, a missing variable),
 * SDDM's own values are used.
 */
QtObject {
    id: root

    property var fallback: null                 // the greeter's `keyboard`
    readonly property bool available: root.capsLeds.length > 0 || root.numLeds.length > 0
    readonly property bool capsLock: root.capsLeds.length > 0 ? root.capsOn : (root.fallback ? root.fallback.capsLock : false)
    readonly property bool numLock: root.numLeds.length > 0 ? root.numOn : (root.fallback ? root.fallback.numLock : false)

    property var capsLeds: []
    property var numLeds: []
    property bool capsOn: false
    property bool numOn: false
    readonly property int maxInput: 64

    function readFile(path, callback) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE)
                callback(xhr.status === 200 || xhr.status === 0 ? String(xhr.responseText ?? "").trim() : "");
        };
        try {
            xhr.open("GET", "file://" + path);
            xhr.send();
        } catch (e) {
            callback("");
        }
    }

    // Read every known LED of one kind; `done(on)` once all have answered.
    function readLeds(paths, done) {
        let pending = paths.length, on = false;
        for (const path of paths) {
            root.readFile(path, text => {
                if (parseInt(text) > 0)
                    on = true;
                if (--pending === 0)
                    done(on);
            });
        }
    }

    function refresh() {
        if (root.capsLeds.length > 0)
            root.readLeds(root.capsLeds, on => root.capsOn = on);
        if (root.numLeds.length > 0)
            root.readLeds(root.numLeds, on => root.numOn = on);
    }
    // After a lock key: the compositor lights the LED a moment after the press.
    function refreshSoon() {
        refreshTimer.restart();
    }

    Component.onCompleted: {
        const caps = [], nums = [];
        let pending = root.maxInput * 2;
        const settle = () => {
            if (--pending > 0)
                return;
            root.capsLeds = caps;
            root.numLeds = nums;
            root.refresh();
        };
        for (let i = 0; i < root.maxInput; i++) {
            const base = "/sys/class/leds/input" + i;
            const capsPath = base + "::capslock/brightness", numPath = base + "::numlock/brightness";
            root.readFile(capsPath, text => {
                if (text !== "")
                    caps.push(capsPath);
                settle();
            });
            root.readFile(numPath, text => {
                if (text !== "")
                    nums.push(numPath);
                settle();
            });
        }
    }

    property Timer refreshTimer: Timer {
        interval: 80
        onTriggered: root.refresh()
    }
    // Catches lock keys pressed on another keyboard, or before focus came here.
    property Timer pollTimer: Timer {
        running: root.available
        interval: 1000
        repeat: true
        onTriggered: root.refresh()
    }
}
