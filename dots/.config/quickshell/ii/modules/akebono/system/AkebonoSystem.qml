pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.services

/**
 * The native plugin behind the Akebono family's process list.
 *
 * `Yunhai.Sys` (ProcessTable, and the SysMon behind it) ships as a cxx-qt Rust plugin
 * and is built from <shell>/scripts/yunhai/plugin, exactly like the shell's two touch
 * helpers are built from protected source. Until it is compiled there is no
 * `Yunhai.Sys` module to `import` — which is why this service exists as its gate: it
 * builds the plugin, and the plugin's QML consumer (ProcessMonitor) is only
 * instantiated once the family's task-manager surface is actually on screen.
 *
 * The CPU/RAM/GPU/disk readouts Akebono draws do NOT come from this plugin: the shell
 * already owns that data in services/ResourceUsage.qml, with its own vendor-aware GPU
 * picking. Only the process table is compiled here.
 *
 * The plugin is resolved through QML2_IMPORT_PATH pointing at the shell's `imports`
 * directory — quickshell does not add it to the import path on its own, so a launch
 * that creates the Akebono surfaces needs it exported:
 *   `env QML2_IMPORT_PATH=<shell>/imports qs -c ii`
 *
 * The build machinery is the tablet helper setup's — see RustHelperBuild. This is the
 * third consumer of it, and the only one whose output is a plugin module rather than a
 * single binary, which is what RustHelperBuild.installCommand is for.
 */
Singleton {
    id: root

    /// Where the plugin workspace lives. Mirrors the helper source layout under scripts/.
    readonly property string sourceDir: Directories.scriptPath + "/yunhai/plugin"
    /// Where build.sh installs the module. Derived, not guessed: the build script and
    /// this property both come from the same root, so they cannot disagree.
    readonly property string installDir: Directories.scriptPath + "/../imports/Yunhai/Sys"
    readonly property string binaryPath: `${root.installDir}/libYunhai_Sys.so`

    readonly property bool built: root.binaryExists

    // ── Presence ────────────────────────────────────────────────────────────
    property bool binaryExists: false

    Process {
        id: checkBinaryProcess
        command: ["test", "-f", root.binaryPath]
        onExited: (code) => {
            root.binaryExists = (code === 0);
            if (root._checkPending) {
                root._checkPending = false;
                Qt.callLater(root.checkBinary);
            }
        }
    }

    /// A check asked for while one was already running. See the same note in
    /// TouchGestureService: killing a running `test` makes it exit non-zero, so a
    /// second caller arriving mid-check would report "missing" for a built plugin.
    property bool _checkPending: false

    function checkBinary() {
        if (root.sourceDir.length === 0)
            return;
        if (checkBinaryProcess.running) {
            root._checkPending = true;
            return;
        }
        checkBinaryProcess.running = true;
    }

    readonly property string _scriptPath: Directories.scriptPath
    on_ScriptPathChanged: root.checkBinary()

    Component.onCompleted: root.checkBinary()

    // ── Building ────────────────────────────────────────────────────────────
    readonly property RustHelperBuild helperBuild: RustHelperBuild {
        label: "Yunhai.Sys"
        sourceDir: root.sourceDir
        // The library name under target/release; only used as the plugin's identity.
        crateName: "libYunhai_Sys.so"
        binaryPath: root.binaryPath
        // The whole install is the plugin's own script — it has to land the library,
        // the qmltypes and a rewritten qmldir, not just one binary.
        installCommand: "bash build.sh release"
        onFinished: ok => root.checkBinary()
    }

    readonly property bool building: root.helperBuild.building
    readonly property string buildResult: root.helperBuild.buildResult
    readonly property string buildOutput: root.helperBuild.buildOutput
    readonly property bool cargoAvailable: root.helperBuild.cargoAvailable
    readonly property string buildProgress: root.helperBuild.progressText
    readonly property int buildUnits: root.helperBuild.unitsCompiled
    readonly property int buildSeconds: root.helperBuild.elapsedSeconds
    readonly property real buildProgressValue: root.helperBuild.progress

    function build() {
        root.helperBuild.build();
    }
}