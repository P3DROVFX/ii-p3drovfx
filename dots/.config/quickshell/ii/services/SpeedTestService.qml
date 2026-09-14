pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property bool running: false
    property string phase: "idle" // "idle", "ping", "download", "upload", "complete", "error"
    property string statusMessage: ""
    property real progress: 0.0
    property real ping: 0.0
    property real jitter: 0.0
    property real currentSpeed: 0.0
    property real downloadSpeed: 0.0
    property real downloadPeak: 0.0
    property real uploadSpeed: 0.0
    property real uploadPeak: 0.0
    property var downloadSamples: []
    property var uploadSamples: []
    property var lastResult: null
    property string errorText: ""
    property string errorType: "" // "offline", "connection_lost", "generic"

    property int testDuration: Config.options?.search?.speedTest?.duration ?? 10
    property string testMode: Config.options?.search?.speedTest?.mode ?? "both"
    property string speedUnit: Config.options?.search?.speedTest?.unit ?? "mbps"

    signal testStarted()
    signal testProgressUpdated()
    signal testCompleted(var result)
    signal testCancelled()

    readonly property string runnerScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/speedtest/speedtest_runner.py`

    function formatSpeed(mbps, unit) {
        const u = unit || root.speedUnit;
        const value = Number(mbps || 0);
        if (u === "mBps") {
            const mBps = value / 8.0;
            return mBps.toFixed(mBps >= 100 ? 0 : 1) + " MB/s";
        }
        return value.toFixed(value >= 100 ? 0 : 1) + " Mbps";
    }

    function speedValue(mbps, unit) {
        const u = unit || root.speedUnit;
        const value = Number(mbps || 0);
        if (u === "mBps") return value / 8.0;
        return value;
    }

    function unitLabel(unit) {
        const u = unit || root.speedUnit;
        return u === "mBps" ? "MB/s" : "Mbps";
    }

    function startTest(duration, mode) {
        if (root.running) return;

        root.reset();
        root.running = true;
        root.phase = "ping";
        root.statusMessage = Translation.tr("Measuring latency...");
        root.progress = 0.05;

        const dur = Number(duration || root.testDuration || 10);
        const md = String(mode || root.testMode || "both");

        speedtestProc.command = [
            "python3",
            root.runnerScriptPath,
            "--duration", String(dur),
            "--mode", md
        ];
        speedtestProc.running = false;
        speedtestProc.running = true;
        root.testStarted();
    }

    function cancelTest() {
        if (!root.running) return;
        speedtestProc.running = false;
        root.running = false;
        root.phase = "idle";
        root.statusMessage = Translation.tr("Test cancelled");
        root.testCancelled();
    }

    function reset() {
        root.currentSpeed = 0.0;
        root.downloadSpeed = 0.0;
        root.downloadPeak = 0.0;
        root.uploadSpeed = 0.0;
        root.uploadPeak = 0.0;
        root.ping = 0.0;
        root.jitter = 0.0;
        root.progress = 0.0;
        root.downloadSamples = [];
        root.uploadSamples = [];
        root.errorText = "";
        root.errorType = "";
    }

    function clearHistory() {
        root.lastResult = null;
        root.reset();
        root.phase = "idle";
        root.statusMessage = "";
    }

    function handleEvent(line) {
        if (!line || !line.trim()) return;
        try {
            const data = JSON.parse(line.trim());
            if (!data || !data.type) return;

            switch (data.type) {
            case "init":
                root.statusMessage = Translation.tr("Connecting to %1...").arg(data.server || "Server");
                break;
            case "status":
                root.statusMessage = Translation.tr(data.message || "");
                break;
            case "ping_result":
                root.ping = Number(data.ping || 0);
                root.jitter = Number(data.jitter || 0);
                root.progress = 0.1;
                break;
            case "download_progress":
                root.phase = "download";
                root.currentSpeed = Number(data.current || 0);
                root.downloadSpeed = Number(data.average || 0);
                root.downloadPeak = Number(data.peak || 0);
                if (root.testMode === "download") {
                    root.progress = 0.1 + (Number(data.progress || 0) * 0.85);
                } else {
                    root.progress = 0.1 + (Number(data.progress || 0) * 0.45);
                }
                if (data.current !== undefined) {
                    const samples = root.downloadSamples.slice();
                    samples.push(Number(data.current));
                    root.downloadSamples = samples;
                }
                root.testProgressUpdated();
                break;
            case "download_result":
                root.downloadSpeed = Number(data.average || 0);
                root.downloadPeak = Number(data.peak || 0);
                if (Array.isArray(data.samples)) {
                    root.downloadSamples = data.samples;
                }
                break;
            case "upload_progress":
                root.phase = "upload";
                root.currentSpeed = Number(data.current || 0);
                root.uploadSpeed = Number(data.average || 0);
                root.uploadPeak = Number(data.peak || 0);
                if (root.testMode === "upload") {
                    root.progress = 0.1 + (Number(data.progress || 0) * 0.85);
                } else {
                    root.progress = 0.55 + (Number(data.progress || 0) * 0.40);
                }
                if (data.current !== undefined) {
                    const samples = root.uploadSamples.slice();
                    samples.push(Number(data.current));
                    root.uploadSamples = samples;
                }
                root.testProgressUpdated();
                break;
            case "upload_result":
                root.uploadSpeed = Number(data.average || 0);
                root.uploadPeak = Number(data.peak || 0);
                if (Array.isArray(data.samples)) {
                    root.uploadSamples = data.samples;
                }
                break;
            case "complete":
                root.running = false;
                root.phase = "complete";
                root.progress = 1.0;
                root.statusMessage = Translation.tr("Test completed");
                root.currentSpeed = 0.0;
                root.ping = Number(data.ping || root.ping);
                root.jitter = Number(data.jitter || root.jitter);
                root.downloadSpeed = Number(data.downloadAvg || root.downloadSpeed);
                root.downloadPeak = Number(data.downloadPeak || root.downloadPeak);
                root.uploadSpeed = Number(data.uploadAvg || root.uploadSpeed);
                root.uploadPeak = Number(data.uploadPeak || root.uploadPeak);
                if (Array.isArray(data.downloadSamples) && data.downloadSamples.length > 0) {
                    root.downloadSamples = data.downloadSamples;
                }
                if (Array.isArray(data.uploadSamples) && data.uploadSamples.length > 0) {
                    root.uploadSamples = data.uploadSamples;
                }

                root.lastResult = {
                    ping: root.ping,
                    jitter: root.jitter,
                    downloadAvg: root.downloadSpeed,
                    downloadPeak: root.downloadPeak,
                    uploadAvg: root.uploadSpeed,
                    uploadPeak: root.uploadPeak,
                    downloadSamples: root.downloadSamples,
                    uploadSamples: root.uploadSamples,
                    timestamp: Number(data.timestamp || Math.floor(Date.now() / 1000)),
                    duration: root.testDuration,
                    mode: root.testMode
                };
                root.testCompleted(root.lastResult);
                break;
            case "error":
                root.running = false;
                root.phase = "error";
                root.errorType = String(data.error_type || "generic");
                root.errorText = String(data.message || Translation.tr("Speed test failed"));
                root.statusMessage = root.errorText;
                break;
            }
        } catch (e) {
            console.warn("[SpeedTestService] Error parsing line:", line, e);
        }
    }

    Process {
        id: speedtestProc
        running: false
        stdout: SplitParser {
            onRead: data => root.handleEvent(data)
        }
        stderr: SplitParser {
            onRead: err => console.warn("[SpeedTestService stderr]", err)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.running) {
                root.running = false;
                if (exitCode !== 0 && root.phase !== "complete") {
                    root.phase = "error";
                    root.errorText = Translation.tr("Test terminated unexpectedly (%1)").arg(exitCode);
                    root.statusMessage = root.errorText;
                }
            }
        }
    }
}
