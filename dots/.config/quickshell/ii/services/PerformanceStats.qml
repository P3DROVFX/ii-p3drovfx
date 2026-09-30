pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live numbers for the performance overlay (the RivaTuner-style HUD):
 * CPU, RAM, one GPU, and frame rate from MangoHud's CSV logger.
 *
 * Everything comes from scripts/perfOverlay/perf_monitor.py, a single
 * long-lived process that only runs while somebody holds `acquire()`: the
 * HUD while it is on screen, the Settings preview while it is open. A dGPU
 * that runtime PM has suspended is reported as "suspended" rather than woken.
 *
 * GPU switching restarts the sampler with the new device; `gpus` lists every
 * card found so Settings can offer them.
 */
Singleton {
    id: root

    readonly property var settings: Config.options.overlay.perfMonitor
    readonly property string scriptPath: `${Directories.scriptPath}/perfOverlay/perf_monitor.py`
    readonly property string logDir: FileUtils.trimFileProtocol(`${Directories.cache}/perf-overlay/mangohud`)

    property int users: 0
    readonly property bool active: root.users > 0 && Config.ready

    function acquire() {
        root.users += 1;
    }

    function release() {
        root.users = Math.max(0, root.users - 1);
    }

    // ---------------------------------------------------------------- devices

    property bool ready: false
    property string cpuModel: ""
    property int cpuThreads: 0
    property bool cpuHasPower: false
    property list<var> gpus: []
    property string selectedGpuId: ""
    readonly property var selectedGpu: root.gpus.find(g => g.id === root.selectedGpuId) ?? null

    // ---------------------------------------------------------------- samples

    property var cpu: ({})
    property var ram: ({})
    property var gpu: ({})
    property var fps: ({ "active": false })
    property var mangohud: ({ "installed": false, "configured": false, "hidden": false })

    readonly property bool fpsActive: root.fps?.active ?? false
    readonly property bool gpuSuspended: (root.gpu?.state ?? "") === "suspended"

    // Numbers MangoHud logs itself fill in what sysfs could not read (RAPL
    // is root-only on most kernels, but MangoHud may have the capability).
    readonly property var cpuPower: root.cpu?.power ?? root.fps?.extras?.cpu_power ?? null
    readonly property var gpuPower: root.gpu?.power ?? (root.fpsActive ? root.fps?.extras?.gpu_power : null) ?? null

    readonly property int historyLength: 40
    property list<real> cpuHistory: []
    property list<real> gpuHistory: []
    property list<real> ramHistory: []
    property list<real> vramHistory: []

    function pushHistory(history, value) {
        const next = [...history, Math.max(0, Math.min(1, value ?? 0))];
        if (next.length > root.historyLength)
            next.shift();
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
        root.gpuHistory = root.pushHistory(root.gpuHistory, root.gpu.usage);
        root.ramHistory = root.pushHistory(root.ramHistory, root.ram.total > 0 ? root.ram.used / root.ram.total : 0);
        root.vramHistory = root.pushHistory(root.vramHistory, root.gpu.vramTotal > 0 ? root.gpu.vramUsed / root.gpu.vramTotal : 0);
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
        root.vramHistory = [];
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
        mangoSetupProc.command = command;
        mangoSetupProc.running = true;
        root.mangohud = Object.assign({}, root.mangohud, {
            "configured": enable,
            "hidden": enable && root.settings.mangohudHideHud
        });
    }

    Process {
        id: mangoSetupProc
    }

    // ---------------------------------------------------------------- sampler

    readonly property string samplerArgs: [
        root.settings?.updateInterval ?? 1000,
        root.settings?.gpuDevice ?? "auto",
        root.settings?.statsWindow ?? 30
    ].join("|")

    onActiveChanged: root.syncSampler()
    onSamplerArgsChanged: {
        if (!sampler.running)
            return;
        sampler.running = false;
        restartTimer.restart();
    }

    function syncSampler() {
        if (root.active) {
            if (!sampler.running)
                restartTimer.restart();
            return;
        }
        restartTimer.stop();
        crashTimer.stop();
        sampler.running = false;
        root.reset();
    }

    Timer {
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
    Timer {
        id: crashTimer
        interval: 5000
        onTriggered: root.syncSampler()
    }

    Process {
        id: sampler
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.active && !restartTimer.running)
                crashTimer.restart();
        }
    }
}
