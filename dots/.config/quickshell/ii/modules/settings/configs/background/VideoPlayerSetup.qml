import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Headless state of the libmpv wallpaper plugin set-up: what the build script reports
 * (--status), the build it runs and the probe that says whether the shell can import the
 * result. The set-up sub-page reads it; nothing runs until that page exists.
 */
Item {
    id: root

    // The status script only runs while the set-up is wanted.
    property bool active: true

    readonly property int statusPollInterval: 3000
    readonly property int statusPollTimeout: 600000

    readonly property string buildScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/build-mpv-wallpaper-plugin.sh`)

    // Distro family, missing build dependencies, this distro's install command, install dir.
    property var buildStatus: null
    readonly property var missingDeps: root.buildStatus?.missing ?? []
    readonly property bool depsReady: root.buildStatus !== null && root.missingDeps.length === 0
    readonly property bool pluginBuilt: (root.buildStatus?.installedDir ?? "") !== ""
    // Importable in this shell: the probe below loads only then.
    readonly property bool pluginLoaded: mpvPluginProbe.status === Loader.Ready
    // The running shell's environment, which the plugin dir has to be in.
    readonly property bool importPathReady: (Quickshell.env("QML_IMPORT_PATH") ?? "").split(":").includes(root.buildStatus?.userQmlDir ?? "")

    property bool building: false
    property bool buildFailed: false
    property string buildLine: ""
    property real buildProgress: 0
    // Set after "Install" opens a terminal; the status is polled until the dependencies
    // show up, since the terminal may return immediately.
    property bool waitingForDeps: false

    function refreshStatus() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function build() {
        if (buildProc.running)
            return;
        root.buildFailed = false;
        root.buildProgress = 0;
        root.buildLine = "";
        root.building = true;
        buildProc.running = true;
    }

    // Steps that need sudo or show long output run in the user's terminal.
    function runInTerminal(args) {
        const terminal = Config.options?.apps?.terminal || "kitty -1";
        const cmd = terminal.split(" ").filter(part => part.length > 0);
        cmd.push("-e", "bash", "-c", 'script="$1"; shift; bash "$script" "$@"; printf "\\n[Press Enter to close] "; read -r', "ii-mpv-wallpaper", root.buildScript, ...args);
        Quickshell.execDetached(cmd);
    }

    function installDependencies() {
        root.runInTerminal(["--install-deps"]);
        root.waitingForDeps = true;
    }

    function restartShell() {
        Quickshell.execDetached(["bash", root.buildScript, "--restart-shell"]);
    }

    onActiveChanged: if (root.active) root.refreshStatus()
    Component.onCompleted: if (root.active) root.refreshStatus()

    Process {
        id: statusProc
        command: ["bash", root.buildScript, "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.buildStatus = JSON.parse(text);
                } catch (e) {
                    console.warn("[VideoPlayerSetup] build status unreadable:", text);
                }
                if (root.waitingForDeps && root.depsReady)
                    root.waitingForDeps = false;
            }
        }
    }

    Timer {
        interval: root.statusPollInterval
        repeat: true
        running: root.waitingForDeps
        onTriggered: root.refreshStatus()
    }
    Timer {
        // Stop polling eventually if the install was abandoned.
        interval: root.statusPollTimeout
        running: root.waitingForDeps
        onTriggered: root.waitingForDeps = false
    }

    Process {
        id: buildProc
        command: ["bash", root.buildScript]
        function readLine(data) {
            const line = String(data).trim();
            if (line.length === 0)
                return;
            const step = line.match(/^\[(\d+)\/(\d+)\]/);
            if (step)
                root.buildProgress = Number(step[1]) / Math.max(1, Number(step[2]));
            root.buildLine = line;
        }
        stdout: SplitParser {
            onRead: data => buildProc.readLine(data)
        }
        stderr: SplitParser {
            onRead: data => buildProc.readLine(data)
        }
        onExited: (exitCode, exitStatus) => {
            root.building = false;
            root.buildFailed = exitCode !== 0;
            root.refreshStatus();
        }
    }

    // Importable only when the MpvWallpaper plugin is installed.
    Loader {
        id: mpvPluginProbe
        visible: false
        source: Qt.resolvedUrl("../../../ii/background/wallpaper/MpvWallpaperProbe.qml")
    }
}
