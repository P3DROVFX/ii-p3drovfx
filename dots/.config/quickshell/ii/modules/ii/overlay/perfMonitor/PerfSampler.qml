pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live numbers for the performance HUD: CPU, RAM, one GPU, and frame rate
 * from MangoHud's CSV logger.
 *
 * Everything comes from scripts/perfOverlay/perf_monitor.py, one process that
 * runs only while `active` (the HUD on screen, the Settings preview open).
 * A dGPU that runtime PM has suspended is reported as "suspended" rather than
 * woken. Changing the GPU, interval or window restarts the process.
 *
 * Each consumer owns its sampler instead of sharing a singleton, so the HUD
 * never depends on a service being registered before it.
 */
QtObject {
    id: root

    property bool active: false

    readonly property var settings: Config.options.overlay.perfMonitor
    readonly property string scriptPath: `${Directories.scriptPath}/perfOverlay/perf_monitor.py`
    readonly property string logDir: FileUtils.trimFileProtocol(`${Directories.cache}/perf-overlay/mangohud`)

    // ---------------------------------------------------------------- devices

    property bool ready: false
    property string cpuModel: ""
    property int cpuThreads: 0
    property bool cpuHasPower: false
    property var gpus: []
    property string selectedGpuId: ""
    readonly property var selectedGpu: root.gpus.find(g => g.id === root.selectedGpuId) ?? null

    // ---------------------------------------------------------------- samples

    property var cpu: ({})
    property var ram: ({})
    property var gpu: ({})
    property var fps: ({ "active": false })
    property var mangohud: ({ "installed": false, "configured": false, "hidden": false })
    property string lastError: ""

    readonly property bool fpsActive: root.fps?.active ?? false
    readonly property bool gpuSuspended: (root.gpu?.state ?? "") === "suspended"

    // Numbers MangoHud logs itself fill in what sysfs could not read (RAPL
    // is root-only on most kernels, but MangoHud may have the capability).
    readonly property var cpuPower: root.cpu?.power ?? (root.fpsActive ? root.fps?.extras?.cpu_power : null) ?? null
    readonly property var gpuPower: root.gpu?.power ?? (root.fpsActive ? root.fps?.extras?.gpu_power : null) ?? null

    readonly property int historyLength: 40
    property var cpuHistory: []
    property var gpuHistory: []
    property var ramHistory: []

    function pushHistory(history, value) {
        const next = history.slice(Math.max(0, history.length - root.historyLength + 1));
        next.push(Math.max(0, Math.min(1, Number(value) || 0)));
        return next;
    }

    function handleLine(line) {
        let data;
        try {
            data = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (data.t === "devices") {
            root.cpuModel = data.cpu?.model ?? "";
            root.cpuThreads = data.cpu?.threads ?? 0;
            root.cpuHasPower = data.cpu?.hasPower ?? false;
            root.gpus = data.gpus ?? [];
            root.selectedGpuId = data.selectedGpu ?? "";
            if (data.mangohud)
                root.mangohud = data.mangohud;
            root.ready = true;
            root.lastError = "";
            return;
        }
        if (data.t !== "sample")
            return;
        root.cpu = data.cpu ?? {};
        root.ram = data.ram ?? {};
        root.gpu = data.gpu ?? {};
        root.fps = data.fps ?? { "active": false };
        if (data.mangohud)
            root.mangohud = data.mangohud;

        root.cpuHistory = root.pushHistory(root.cpuHistory, root.cpu.usage);
        root.gpuHistory = root.pushHistory(root.gpuHistory, root.gpuSuspended ? 0 : root.gpu.usage);
        root.ramHistory = root.pushHistory(root.ramHistory, root.ram.total > 0 ? root.ram.used / root.ram.total : 0);
    }

    function reset() {
        root.ready = false;
        root.cpu = {};
        root.ram = {};
        root.gpu = {};
        root.fps = { "active": false };
        root.cpuHistory = [];
        root.gpuHistory = [];
        root.ramHistory = [];
    }

    // ---------------------------------------------------------------- actions

    function cycleGpu() {
        if (root.gpus.length < 2)
            return;
        const index = root.gpus.findIndex(g => g.id === root.selectedGpuId);
        Config.options.overlay.perfMonitor.gpuDevice = root.gpus[(index + 1) % root.gpus.length].id;
    }

    // Writes (or removes) the logging block in ~/.config/MangoHud/MangoHud.conf.
    function setMangoHudLogging(enable) {
        const command = ["python3", root.scriptPath];
        if (enable) {
            command.push("setup", "--dir", root.logDir, "--interval", String(root.settings.mangohudLogInterval));
            if (root.settings.mangohudHideHud)
                command.push("--hide-hud");
        } else {
            command.push("unsetup");
        }
        Quickshell.execDetached(command);
        root.mangohud = Object.assign({}, root.mangohud, {
            "configured": enable,
            "hidden": enable && root.settings.mangohudHideHud
        });
    }

    // ---------------------------------------------------------------- sampler

    readonly property string samplerArgs: [
        root.settings?.updateInterval ?? 1000,
        root.settings?.gpuDevice ?? "auto",
        root.settings?.statsWindow ?? 30
    ].join("|")

    onActiveChanged: root.sync()
    onSamplerArgsChanged: {
        if (!sampler.running)
            return;
        sampler.running = false;
        restartTimer.restart();
    }
    Component.onCompleted: root.sync()
    Component.onDestruction: sampler.running = false

    function sync() {
        if (root.active) {
            if (!sampler.running)
                restartTimer.restart();
            return;
        }
        restartTimer.stop();
        retryTimer.stop();
        sampler.running = false;
        root.reset();
    }

    property Timer _restartTimer: Timer {
        id: restartTimer
        interval: 60
        onTriggered: {
            if (!root.active)
                return;
            sampler.command = ["python3", root.scriptPath, "run",
                "--interval", String(root.settings.updateInterval),
                "--gpu", root.settings.gpuDevice || "auto",
                "--mangohud-dir", root.logDir,
                "--window", String(root.settings.statsWindow)];
            sampler.running = true;
        }
    }

    // The sampler only exits on its own when something broke; retry slowly.
    property Timer _retryTimer: Timer {
        id: retryTimer
        interval: 5000
        onTriggered: root.sync()
    }

    property Process _process: Process {
        id: sampler
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        stderr: SplitParser {
            onRead: line => {
                root.lastError = line;
                console.warn("[PerfSampler]", line);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (!root.active || restartTimer.running)
                return;
            console.warn(`[PerfSampler] perf_monitor.py exited (${exitCode}), retrying`);
            retryTimer.restart();
        }
    }
}
