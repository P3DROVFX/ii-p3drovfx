import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// pointer events report positions short by the monitor origin until the cursor physically
// moves, so poll hyprland until then and hand out surface-local coordinates either way
Scope {
    id: root

    required property HyprlandMonitor monitor
    property bool active: false

    property real cursorX: 0
    property real cursorY: 0
    property bool moved: false

    property string _seed: ""

    onActiveChanged: if (!root.active) {
        root._seed = ""
        root.moved = false
    }

    function track(eventX, eventY) {
        if (!root.moved) return false
        root.cursorX = eventX
        root.cursorY = eventY
        return true
    }

    function localX(eventX) { return root.moved ? eventX : root.cursorX }
    function localY(eventY) { return root.moved ? eventY : root.cursorY }

    Timer {
        running: root.active
        interval: root.moved ? 300 : 60
        repeat: true
        triggeredOnStart: true
        onTriggered: pollProc.running = true
    }

    Process {
        id: pollProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim()
                const pos = raw.split(",")
                if (pos.length !== 2) return

                if (root._seed === "")
                    root._seed = raw
                else if (raw !== root._seed)
                    root.moved = true
                if (root.moved) return

                root.cursorX = parseInt(pos[0]) - root.monitor.x
                root.cursorY = parseInt(pos[1]) - root.monitor.y
            }
        }
    }
}
