pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int currentValue: 0
    property int maxValue: 0
    property string deviceName: ""
    property bool available: false
    property bool ready: false
    property bool initialValueLoaded: false

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
    }

    Timer {
        id: pollTimer
        interval: 150
        running: root.available && root.deviceName !== ""
        repeat: true
        onTriggered: {
            brightnessFileView.reload()
            const valStr = brightnessFileView.text().trim()
            if (valStr.length > 0) {
                const val = parseInt(valStr)
                if (!isNaN(val) && val !== root.currentValue) {
                    root.currentValue = val
                }
            } else {
                // If direct read fails (e.g. permission issue), fallback to brightnessctl via refresh()
                // and slow down the polling to 2 seconds to save CPU.
                if (pollTimer.interval === 150) {
                    pollTimer.interval = 2000
                }
                root.refresh()
            }
        }
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
