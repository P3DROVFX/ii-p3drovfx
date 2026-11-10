pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * The packages this fork uses on top of the base install, as reported by
 * scripts/deps/deps.py from defaults/dependencies.json.
 *
 * Settings > About lists them, and installs through the setup script's `deps`
 * command in a terminal, the way it updates: sudo needs somewhere to ask for a
 * password, and the package manager's output should stay readable.
 *
 * Install and update already offer the core set. The shell checks it once after
 * it starts anyway, because the first update that ships the manifest is run by
 * the previous setup script, which knows nothing about it. That check notifies
 * once per set of missing packages, never on every start.
 */
Singleton {
    id: root

    readonly property string depsScript: `${Directories.scriptPath}/deps/deps.py`
    // Next to the setup script's own record of what it installed.
    readonly property string notifiedFile: FileUtils.trimFileProtocol(Directories.home + "/.local/state/ii-p3drovfx/deps-notified")

    // Each {id, tier, label, description, status, installable, packages}, with
    // status one of installed, partial, missing or unavailable.
    property var features: []
    property string distro: ""
    property string aurHelper: ""
    property bool loading: false
    property bool loaded: false
    property string error: ""

    readonly property var requiredMissing: root.features.filter(f => f.tier === "required" && f.status !== "installed")
    readonly property var optionalFeatures: root.features.filter(f => f.tier === "optional")
    readonly property int optionalInstalled: root.optionalFeatures.filter(f => f.status === "installed").length

    property bool _checkAfterLoad: false

    function refresh() {
        if (statusProc.running)
            return;
        root.loading = true;
        statusProc.running = true;
    }

    // Once per engine generation, from shell.qml. Late on purpose: nothing about
    // it is urgent, and startup has enough to do.
    function checkCore() {
        coreCheckTimer.restart();
    }

    // ids is a list of feature ids; "core" stands for every required package.
    function install(ids) {
        if (!ids || ids.length === 0)
            return;
        ShellUpdates.launchInTerminal(["deps", "--add", ids.join(",")]);
    }

    function _notifyIfMissing() {
        const missing = root.requiredMissing.filter(f => f.installable);
        if (missing.length === 0)
            return;
        const key = missing.map(f => f.id).sort().join(",");
        const names = missing.map(f => f.packages.filter(p => !p.present).map(p => p.name).join(" ")).join(" ");
        // The latch lives in a file, so a hot reload or a new login does not
        // ask again about the same packages; a different set does.
        notifyProc.command = ["bash", "-c",
            'f="$1"; [ "$(cat "$f" 2>/dev/null)" = "$2" ] && exit 0; mkdir -p "$(dirname "$f")"; printf %s "$2" > "$f"; ' +
            'exec notify-send -a "II-P3DROVFX" -i system-software-install -A "install=$3" "$4" "$5"',
            "ii-deps", root.notifiedFile, key, Translation.tr("Install"),
            Translation.tr("Missing core packages"),
            Translation.tr("Some features of the shell need %1. Install opens a terminal.").arg(names)];
        notifyProc.running = true;
    }

    Timer {
        id: coreCheckTimer
        interval: 30000
        onTriggered: {
            root._checkAfterLoad = true;
            root.refresh();
        }
    }

    Process {
        id: statusProc
        command: ["python3", root.depsScript, "status", "--json"]

        stdout: StdioCollector {
            id: statusOutput
        }

        onExited: exitCode => {
            root.loading = false;
            const check = root._checkAfterLoad;
            root._checkAfterLoad = false;
            if (exitCode !== 0) {
                root.error = Translation.tr("Could not read the dependency list (exit %1).").arg(exitCode);
                return;
            }
            try {
                const report = JSON.parse(statusOutput.text);
                root.distro = report.distro ?? "";
                root.aurHelper = report.aurHelper ?? "";
                root.features = Array.from(report.features ?? []);
                root.error = "";
                root.loaded = true;
            } catch (e) {
                root.error = Translation.tr("Could not read the dependency list.");
                return;
            }
            if (check)
                root._notifyIfMissing();
        }
    }

    Process {
        id: notifyProc

        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "install")
                    root.install(["core"]);
            }
        }
    }
}
