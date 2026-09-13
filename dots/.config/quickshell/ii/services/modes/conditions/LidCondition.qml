import QtQuick
import Quickshell.Io
import qs.modules.common.functions
import ".."

/**
 * The laptop lid is closed (`closed: true`, default) or open. The first
 * reading comes from /proc/acpi/button/lid — which also proves a lid exists;
 * machines without one never hold — and every flip after that arrives from
 * logind's LidClosed property over D-Bus, so nothing polls.
 */
ModeCondition {
    id: root
    readonly property bool wantClosed: root.params?.closed !== false

    // "closed" / "open"; "" before the first reading, or with no lid at all.
    property string state: ""

    readonly property Process reader: Process {
        running: true
        command: ["sh", "-c", "cat /proc/acpi/button/lid/*/state 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /:\s*(\w+)/.exec(this.text);
                root.state = m ? m[1].toLowerCase() : "";
            }
        }
    }

    // logind announces each lid flip as a PropertiesChanged on its manager.
    readonly property Process monitor: Process {
        running: true
        command: ProcUtils.pdeath(["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1"])
        stdout: SplitParser {
            onRead: data => root.handleChunk(data)
        }
        onExited: root.retry.restart()
    }

    function handleChunk(data) {
        // One chunk may carry several signals; the last LidClosed wins.
        const re = /'LidClosed':\s*<(true|false)>/g;
        let last = null;
        for (let m = re.exec(data); m !== null; m = re.exec(data))
            last = m[1] === "true";
        if (last === null || !root.state.length)
            return;
        root.state = last ? "closed" : "open";
    }

    // Comes back after logind or gdbus went away, re-reading a state that
    // may have flipped meanwhile.
    readonly property Timer retry: Timer {
        interval: 5000
        repeat: false
        onTriggered: {
            root.reader.running = true;
            root.monitor.running = true;
        }
    }

    satisfied: root.state.length > 0 && (root.state === "closed") === root.wantClosed
    reason: root.state.length ? root.state : "no lid"
}
