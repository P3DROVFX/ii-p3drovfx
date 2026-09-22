pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Singleton {
    id: root

    property int currentValue: 0
    property int maxValue: 0
    property string deviceName: ""
    property bool available: false
    property bool ready: false
    property bool initialValueLoaded: false

    // Set while an idle-driven write is in flight, so the OSD doesn't pop up for
    // a level change the user didn't ask for.
    property bool suppressOsd: false

    // The keyboard's own backlight key changed the level (see hwChangedView). Fires even
    // when a poll already picked the new value up, which currentValueChanged would not.
    signal keyChanged()

    readonly property bool autoOffEnabled: (Config.options?.light?.keyboardBacklight?.autoOff) ?? false
    readonly property int autoOffTimeout: (Config.options?.light?.keyboardBacklight?.timeout) ?? 15

    readonly property int levels: maxValue + 1
    readonly property real percentage: maxValue > 0 ? (currentValue / maxValue) * 100 : 0
    readonly property string levelText: {
        if (!available) return Translation.tr("N/A")
        if (currentValue === 0) return Translation.tr("Off")
        if (maxValue <= 2) {
            return currentValue === 1 ? Translation.tr("Low") : Translation.tr("High")
        }
        return Math.round(percentage) + "%"
    }

    reloadableId: "keyboardBacklight"

    Component.onCompleted: detectDevice()

    function detectDevice() {
        detectProc.running = true
    }

    function cycleNext() {
        if (!available || !ready) return
        const nextValue = (currentValue + 1) % levels
        setValue(nextValue)
    }

    function cyclePrevious() {
        if (!available || !ready) return
        const prevValue = currentValue <= 0 ? maxValue : currentValue - 1
        setValue(prevValue)
    }

    function setValue(value: int) {
        if (!available || !ready) return
        value = Math.max(0, Math.min(maxValue, value))
        setProc.command = ["brightnessctl", "--device", deviceName, "s", value.toString(), "--quiet"]
        setProc.running = true
    }

    function refresh() {
        if (!available) return
        getProc.running = true
    }

    // Write a level on behalf of the idle monitor rather than the user.
    function idleWrite(value: int) {
        root.suppressOsd = true
        osdSuppressTimer.restart()
        root.setValue(value)
    }

    // Persistent is reloadable, so its adapter can briefly lag behind a hot reload.
    readonly property var idleState: Persistent.ready ? (Persistent.states?.keyboardBacklight ?? null) : null

    function idleOff() {
        if (!available || !ready || currentValue === 0 || !idleState) return
        idleState.savedLevel = currentValue
        idleState.idleOffActive = true
        root.idleWrite(0)
    }

    function idleRestore() {
        const state = root.idleState
        if (!state || !state.idleOffActive) return
        state.idleOffActive = false
        // The backlight key may have been pressed while idle, in which case the
        // driver already picked a level and restoring would stomp on it.
        if (currentValue !== 0 || state.savedLevel <= 0) return
        root.idleWrite(state.savedLevel)
    }

    // A restart while idle-off would otherwise strand the backlight at 0 with the
    // saved level lost. Only restore if we were the ones who switched it off.
    function restoreStrandedLevel() {
        if (startupRestoreDone || !available || !ready || maxValue <= 0 || !idleState) return
        root.startupRestoreDone = true
        root.idleRestore()
    }

    property bool startupRestoreDone: false

    onReadyChanged: root.restoreStrandedLevel()
    onMaxValueChanged: root.restoreStrandedLevel()
    onIdleStateChanged: root.restoreStrandedLevel()
    onAutoOffEnabledChanged: if (!root.autoOffEnabled) root.idleRestore()

    // Changing IdleMonitor.timeout in place replaces the underlying wayland
    // notification, but isIdle stays latched to the one that was destroyed, so
    // the monitor never reports again. Cycling enabled re-arms it cleanly. The
    // delay also debounces the settings spin box stepping through values.
    property bool rearmingIdleMonitor: false

    onAutoOffTimeoutChanged: {
        if (!root.autoOffEnabled) return
        root.rearmingIdleMonitor = true
        idleMonitorRearmTimer.restart()
    }

    Timer {
        id: idleMonitorRearmTimer
        interval: 250
        repeat: false
        onTriggered: root.rearmingIdleMonitor = false
    }

    IdleMonitor {
        enabled: root.available && root.autoOffEnabled && !root.rearmingIdleMonitor
        timeout: root.autoOffTimeout
        // Track raw seat input instead of the compositor's idle state, so the
        // backlight still switches off while a video player holds an idle
        // inhibitor. Needs ext-idle-notify-v1 v2; older compositors fall back to
        // respecting inhibitors.
        respectInhibitors: false
        onIsIdleChanged: isIdle ? root.idleOff() : root.idleRestore()
    }

    Timer {
        id: osdSuppressTimer
        // Covers the brightnessctl write, the read-back that follows it, and one
        // full poll cycle in case the read-back misses. An explicit keypress inside
        // this window loses its OSD, which is a fair trade for never popping one up
        // on an idle transition.
        interval: 1200
        repeat: false
        onTriggered: root.suppressOsd = false
    }

    Process {
        id: detectProc
        command: ["sh", "-c", "ls /sys/class/leds/ 2>/dev/null | grep -E 'kbd_backlight|chromeos::kbd_backlight|cros_ec::kbd_backlight' | head -1"]
        stdout: SplitParser {
            onRead: data => {
                const device = data.trim()
                if (device.length > 0) {
                    root.deviceName = device
                    root.available = true
                    root.refresh()
                }
            }
        }
        onExited: {
            root.ready = true
        }
    }

    Process {
        id: getProc
        command: ["sh", "-c", `echo "$(brightnessctl --device '${StringUtils.shellSingleQuoteEscape(root.deviceName)}' get) $(brightnessctl --device '${StringUtils.shellSingleQuoteEscape(root.deviceName)}' max)"`]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(" ")
                if (parts.length >= 2) {
                    root.currentValue = parseInt(parts[0])
                    root.maxValue = parseInt(parts[1])
                    root.ready = true
                }
            }
        }
    }

    Process {
        id: setProc
        onExited: {
            root.refresh()
        }
    }

    FileView {
        id: brightnessFileView
        path: root.deviceName ? `/sys/class/leds/${root.deviceName}/brightness` : ""

        // reload() completes asynchronously, so the value has to be picked up here.
        // Reading straight after the call returns the *previous* poll's content, which
        // makes every real change bounce through a stale value one tick later.
        onLoaded: {
            const val = parseInt(brightnessFileView.text().trim())
            if (isNaN(val) || val === root.currentValue) return
            root.currentValue = val
        }

        // If the direct read fails (e.g. permission issue), fall back to brightnessctl
        // via refresh() and slow the polling down to 5 seconds to save CPU.
        onLoadFailed: {
            if (pollTimer.interval === 1000) pollTimer.interval = 5000
            root.refresh()
        }
    }

    // Drivers that set LED_BRIGHT_HW_CHANGED (samsung-galaxybook, thinkpad_acpi, dell-laptop,
    // asus-wmi, ...) notify this file when the keyboard's own backlight key changes the level,
    // and only then: software writes, the idle switch-off included, never touch it. So a key
    // press shows at once instead of on the next poll, even inside the idle-write window.
    // Other drivers have no such file; the poll still covers them.
    FileView {
        id: hwChangedView
        property bool armed: false
        path: root.deviceName ? `/sys/class/leds/${root.deviceName}/brightness_hw_changed` : ""
        watchChanges: true
        printErrors: false // absent on most drivers, ENODATA until the first key press
        onFileChanged: {
            hwChangedView.armed = true
            hwChangedView.reload()
        }
        // The file holds the level of the last key press, which can be older than the current
        // one, so the load that comes with setting the path is not news.
        onLoaded: {
            if (!hwChangedView.armed) return
            hwChangedView.armed = false
            const val = parseInt(hwChangedView.text().trim())
            if (isNaN(val)) return
            root.suppressOsd = false
            osdSuppressTimer.stop()
            root.currentValue = val
            root.keyChanged()
        }
    }

    Timer {
        id: pollTimer
        interval: 1000
        running: root.available && root.deviceName !== ""
        repeat: true
        onTriggered: brightnessFileView.reload()
    }

    IpcHandler {
        target: "keyboardBacklight"

        function cycle() {
            onPressed: root.cycleNext()
        }

        function set(value: string) {
            onPressed: root.setValue(parseInt(value))
        }
    }
}
