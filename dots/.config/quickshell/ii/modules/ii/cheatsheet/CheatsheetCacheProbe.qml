pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.modules.common

// Explicit diagnostic only. The production host never constructs this probe.
// Runs against the existing process and requests only hidden cache creation.
Item {
    id: root
    required property var controller
    property bool cacheReady: false
    property string phase: "baseline"
    property real started: 0
    property real buildMs: 0
    property string runId: "paired-" + Date.now()
    property int cycle: 1
    Component.onCompleted: settle.start()
    onCacheReadyChanged: {
        if (cacheReady && phase === "building") {
            buildMs = Date.now() - started;
            phase = "cached";
            settle.restart();
        }
    }
    Timer {
        id: settle
        // First sample follows startup/hot-reload settling; later pairs avoid
        // repeatedly reloading the shell and reuse this same generation.
        interval: root.phase === "baseline" ? 45000 : root.phase === "cached" ? 0 : 4000
        onTriggered: {
            reader.command = ["python3", Directories.scriptPath + "/diagnostics/process_memory_sample.py",
                "--samples", "1",
                "--label", root.runId + ":" + root.phase + ":cycle=" + root.cycle + ":build=" + root.buildMs,
                "--output", "/tmp/ii-cheatsheet-cache-probe.jsonl"];
            reader.running = true;
        }
    }
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                console.log("[CheatsheetCacheProbe] " + text.trim());
                if (root.phase === "baseline" || root.phase === "released") {
                    root.phase = "building";
                    root.started = Date.now();
                    root.controller.prepareCache();
                } else if (root.phase === "cached" && root.cycle < 4) {
                    root.cycle++;
                    root.phase = "released";
                    root.controller.cachePrepared = false;
                    settle.restart();
                }
            }
        }
    }
}
