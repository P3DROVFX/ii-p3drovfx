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
    property var mangohud: ({
        "installed": false,
        "configured": false,
        "hidden": false,
        "confPath": "~/.config/MangoHud/MangoHud.conf",
        "installCommand": "",
        "steamFlatpak": false,
        "flatpakLayer": false,
        "flatpakConfigured": false
    })
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
                root.mangohud = Object.assign({}, root.mangohud, data.mangohud);
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
            root.mangohud = Object.assign({}, root.mangohud, data.mangohud);

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

    // ---------------------------------------------------------------- MangoHud

    // True while a setup/remove/status call runs; `mangoMessage` says how the
    // last one went, so the Settings page can show it instead of guessing.
    property bool mangoBusy: false
    property string mangoMessage: ""

    // Reads MangoHud's state now (installed, configured, distro install
    // command, Flatpak Steam) instead of waiting for the sampler's next report.
    function refreshMangoHud() {
        root.runMango(["status", "--dir", root.logDir], "");
    }

    // Writes (or removes) the logging block in MangoHud.conf (and in Flatpak
    // Steam's own copy when it is installed), then reports the new state.
    function setMangoHudLogging(enable) {
        const args = enable
            ? ["setup", "--dir", root.logDir, "--interval", String(root.settings.mangohudLogInterval)]
            : ["unsetup", "--dir", root.logDir];
        if (enable && root.settings.mangohudHideHud)
            args.push("--hide-hud");
        root.runMango(args, enable ? "saved" : "removed");
    }

    function runMango(args, success) {
        if (mangoProc.running)
            return;
        mangoProc.success = success;
        mangoProc.command = ["python3", root.scriptPath].concat(args);
        root.mangoBusy = true;
        mangoProc.running = true;
    }

    property Process _mangoProc: Process {
        id: mangoProc
        property string success: ""
        stdout: StdioCollector {
            id: mangoOut
            onStreamFinished: {
                root.mangoBusy = false;
                try {
                    root.mangohud = JSON.parse(mangoOut.text.trim().split("\n").pop());
                    root.mangoMessage = mangoProc.success;
                } catch (e) {
                    root.mangoMessage = "error";
                }
            }
        }
        stderr: StdioCollector {
            id: mangoErr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                return;
            root.mangoBusy = false;
            root.mangoMessage = "error";
            console.warn("[PerfSampler] MangoHud setup failed:", exitCode, mangoErr.text.trim());
        }
    }

    // ---------------------------------------------------------------- games

    // Games and launchers found on the system, with whether MangoHud is
    // already wired into each (see the games section of perf_monitor.py).
    property var games: []
    property string gamesBusyId: ""
    property string gamesError: ""
    property string gamesErrorId: ""
    property string layerCommand: ""

    function refreshGames() {
        root.runGames(["games"], "");
    }
    function setGameFps(id, enable) {
        root.runGames([enable ? "enable" : "disable", id], id);
    }
    function launchGame(id) {
        root.runGames(["launch", id], id);
    }
    function runGames(args, id) {
        if (gamesProc.running)
            return;
        root.gamesBusyId = id || "*";
        root.gamesError = "";
        gamesProc.command = ["python3", root.scriptPath].concat(args).concat(["--dir", root.logDir]);
        gamesProc.running = true;
    }

    property Process _gamesProc: Process {
        id: gamesProc
        stdout: StdioCollector {
            id: gamesOut
            onStreamFinished: {
                try {
                    const data = JSON.parse(gamesOut.text.trim().split("\n").pop());
                    root.games = data.games ?? [];
                    root.layerCommand = data.layerCommand ?? "";
                    root.gamesError = data.error ?? "";
                    root.gamesErrorId = data.id ?? "";
                    if (data.mangohud)
                        root.mangohud = Object.assign({}, root.mangohud, data.mangohud);
                } catch (e) {
                    root.gamesError = "failed";
                }
                root.gamesBusyId = "";
            }
        }
        stderr: StdioCollector {
            id: gamesErr
            onStreamFinished: {
                if (gamesErr.text.trim().length > 0)
                    console.warn("[PerfSampler]", gamesErr.text.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.gamesBusyId = "";
                root.gamesError = "failed";
            }
        }
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
