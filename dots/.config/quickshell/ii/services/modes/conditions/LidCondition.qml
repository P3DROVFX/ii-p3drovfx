import QtQuick
import Quickshell.Io
import ".."

/**
 * The laptop lid is closed (`closed: true`, default) or open, read from
 * /proc/acpi/button/lid every few seconds while the condition exists.
 * Machines without a lid never hold.
 */
ModeCondition {
    id: root
    readonly property bool wantClosed: root.params?.closed !== false

    property string state: ""

    readonly property Process reader: Process {
        command: ["sh", "-c", "cat /proc/acpi/button/lid/*/state 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /:\s*(\w+)/.exec(this.text);
                root.state = m ? m[1].toLowerCase() : "";
            }
        }
    }

    readonly property Timer poll: Timer {
        interval: 4000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!root.reader.running)
                root.reader.running = true;
        }
    }

    satisfied: root.state.length > 0 && (root.state === "closed") === root.wantClosed
    reason: root.state.length ? root.state : "no lid"
}
