pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.akebono.system
import qs.modules.common
import qs.modules.common.widgets

/**
 * The one thing a fresh install of the Akebono family has to get past.
 *
 * Three native pieces ship incomplete:
 *  - the family's resource widgets read through a native plugin (`Yunhai.Sys`,
 *    a cxx-qt workspace under <shell>/scripts/yunhai/plugin) that must be
 *    compiled before the task manager has anything to show;
 *  - the SDF shaders under assets/shaders (`.qsb` artifacts, not source) must be
 *    compiled from their `.frag` sources with qsb;
 *  - the hyprbars plugin, loaded straight into the compositor, draws the
 *    family's window title bars and is installed with hyprpm. hyprpm refuses
 *    to run as root by design; it only needs its per-user cache under
 *    /var/cache/hyprpm/<user> to be writable, and a sub-second pkexec handover
 *    establishes that if a privileged run ever left it root-owned. The actual
 *    clone-and-compile then runs on the user side, streaming into this window.
 *
 * Until this window existed nothing said any of it was missing: the shelf showed
 * blank readouts, the shader effects snapped to their fallbacks, and windows had
 * no decorations — each with no word about why.
 *
 * So the family says it out loud, once, on the first launch where something is
 * missing, with each install as a button.
 *
 * Dismissal is remembered, per component. This is a prompt, not a nag: "Do it
 * later" means later, and a brand-new missing piece (a deleted module, a rebuild
 * after a source update) is what makes it return.
 */
Scope {
    id: root

    // ── The qs plugin ────────────────────────────────────────────────────────
    readonly property bool pluginMissing: !AkebonoSystem.binaryExists

    /**
     * Whether a build has been started from here this session.
     *
     * Without this the window closed the instant the build succeeded, so the one
     * thing the user pressed the button to find out — whether it worked — flashed
     * past on the way out. A result nobody sees is not a result.
     */
    readonly property bool sessionTouched: AkebonoSystem.building
        || AkebonoSystem.buildResult.length > 0
        || root.shadersTouched
        || root.hyprbarsTouched

    // ── The shaders ──────────────────────────────────────────────────────────
    readonly property string shadersScript: Quickshell.shellPath("scripts/shaders/build.sh")

    property bool qsbAvailable: false
    property bool shadersMissing: true
    property bool shadersBuilding: false
    property bool shadersFailed: false
    property string shadersDetail: ""
    property string shadersFailure: ""
    property bool shadersTouched: false

    readonly property Process _qsbCheck: Process {
        command: ["sh", "-c", "command -v qsb || test -x /usr/lib/qt6/bin/qsb"]
        onExited: code => root.qsbAvailable = (code === 0)
        Component.onCompleted: running = true
    }

    readonly property Process _shadersCheck: Process {
        command: ["bash", root.shadersScript, "status"]
        onExited: code => root.shadersMissing = (code !== 0)
    }

    readonly property Process _shadersBuild: Process {
        command: ["bash", root.shadersScript]
        stdout: SplitParser { onRead: line => root.shadersDetail = line.trim() }
        stderr: SplitParser { onRead: line => root.shadersDetail = line.trim() }
        onExited: code => {
            root.shadersBuilding = false;
            root.shadersTouched = true;
            if (code === 0) {
                root.shadersFailed = false;
                root.shadersFailure = "";
                root.shadersCheck();
            } else {
                root.shadersFailed = true;
                root.shadersFailure = root.shadersDetail;
                console.warn(`[AkebonoSetup] shader build failed (${code}): ${root.shadersDetail}`);
            }
        }
    }

    // ── hyprbars ─────────────────────────────────────────────────────────────
    readonly property string hyprbarsScript: Quickshell.shellPath("scripts/desktop/hyprbars.sh")

    property bool hyprpmAvailable: false
    property bool hyprbarsReady: false
    property bool hyprbarsInstalling: false
    property bool hyprbarsFailed: false
    property string hyprbarsDetail: ""
    property string hyprbarsFailure: ""
    property bool hyprbarsTouched: false

    readonly property Process _hyprpmCheck: Process {
        command: ["sh", "-c", "command -v hyprpm"]
        onExited: code => root.hyprpmAvailable = (code === 0)
        Component.onCompleted: running = true
    }

    readonly property Process _hyprbarsCheck: Process {
        command: ["sh", "-c", "hyprctl plugins list 2>/dev/null | grep -qi hyprbars"]
        onExited: code => root.hyprbarsReady = (code === 0)
    }

    readonly property Process _hyprbarsPrep: Process {
        // hyprpm deliberately refuses to run as root, but it needs to write its
        // per-user cache (state, headers, built plugins) under /var/cache/hyprpm.
        // On boxes where an earlier privileged run left that tree root-owned, a
        // one-shot handover of the per-user subdirectory fixes it. This is a
        // sub-second operation; the long part (cloning + compiling) stays on the
        // user side where hyprpm is designed to run and the progress is visible.
        command: ["pkexec", "sh", "-c",
            "u=$(getent passwd \"$PKEXEC_UID\" | cut -d: -f1);"
            + " g=$(id -g \"$u\");"
            + " [ -n \"$u\" ] && [ -n \"$g\" ] || exit 1;"
            + " install -d -o \"$u\" -g \"$g\" \"/var/cache/hyprpm/$u\";"
            + " chown -R \"$u\":\"$g\" \"/var/cache/hyprpm/$u\""]
        stdout: SplitParser { onRead: line => root.hyprbarsDetail = line.trim() }
        stderr: SplitParser { onRead: line => root.hyprbarsDetail = line.trim() }
        onExited: code => {
            root.hyprbarsInstalling = false;
            if (code === 0)
                root.runHyprbarsInstall();
            else {
                root.hyprbarsTouched = true;
                root.hyprbarsFailed = true;
                root.hyprbarsFailure = root.hyprbarsDetail
                    || Translation.tr("the cache handover was not authorized");
                console.warn(`[AkebonoSetup] hyprpm cache handover failed (${code})`);
            }
        }
    }

    readonly property Process _hyprbarsInstall: Process {
        // Runs as the unprivileged user, as hyprpm requires ("Don't run hyprpm
        // as a superuser."). With the per-user cache directory handed over above,
        // the whole chain — cloning the plugin sources, downloading headers,
        // compiling, and writing the plugin state — happens without a single
        // further password prompt, streamed into the row below.
        command: ["bash", "-c",
            "set -e; echo y | hyprpm --no-nix add https://github.com/hyprwm/hyprland-plugins"
            + " && echo y | hyprpm --no-nix update"
            + " && echo y | hyprpm --no-nix enable hyprbars"]
        stdout: SplitParser { onRead: line => root.hyprbarsDetail = line.trim() }
        stderr: SplitParser { onRead: line => root.hyprbarsDetail = line.trim() }
        onExited: code => {
            root.hyprbarsInstalling = false;
            root.hyprbarsTouched = true;
            if (code === 0) {
                root.hyprbarsFailed = false;
                root.hyprbarsFailure = "";
                Quickshell.execDetached(["bash", root.hyprbarsScript, "load"]);
                root.hyprbarsCheck();
            } else {
                root.hyprbarsFailed = true;
                root.hyprbarsFailure = root.hyprbarsDetail
                    || Translation.tr("hyprpm failed without a message");
                console.warn(`[AkebonoSetup] hyprbars install failed (${code}): ${root.hyprbarsDetail}`);
            }
        }
    }

    // ── What is missing ──────────────────────────────────────────────────────
    function missingComponents() {
        const missing = [];
        if (root.pluginMissing)
            missing.push("plugin");
        if (root.shadersMissing)
            missing.push("shaders");
        if (!root.hyprbarsReady)
            missing.push("hyprbars");
        return missing;
    }

    readonly property bool anyMissing: root.missingComponents().length > 0
    readonly property bool anyBuilding: root.hyprbarsInstalling || root.shadersBuilding

    readonly property bool dismissed: Persistent.ready && (() => {
        const list = Persistent.states.akebono.pluginSetupDismissed
            .split(",").map(s => s.trim()).filter(s => s.length > 0);
        const missing = root.missingComponents();
        return missing.length > 0 && missing.every(m => list.includes(m));
    })()

    /// Held back until the shell has finished coming up. A modal over a half-drawn
    /// desktop reads as a crash report, not as a welcome.
    property bool settled: false

    readonly property bool shouldShow: Config.ready && Persistent.ready && root.settled
        && (root.anyMissing || root.sessionTouched)
        && !root.dismissed && !GlobalStates.screenLocked

    readonly property Timer _settleTimer: Timer {
        interval: 2500
        repeat: false
        running: true
        onTriggered: root.settled = true
    }

    function dismiss() {
        if (!Persistent.ready)
            return;
        Persistent.states.akebono.pluginSetupDismissed = root.missingComponents().join(",");
    }

    function refresh() {
        root.shadersCheck();
        root.hyprbarsCheck();
    }

    function shadersCheck() {
        if (root.shadersBuilding)
            return;
        if (_shadersCheck.running) {
            Qt.callLater(root.shadersCheck);
            return;
        }
        _shadersCheck.running = true;
    }

    function hyprbarsCheck() {
        if (root.hyprbarsInstalling)
            return;
        if (_hyprbarsCheck.running) {
            Qt.callLater(root.hyprbarsCheck);
            return;
        }
        _hyprbarsCheck.running = true;
    }

    function buildShaders() {
        if (root.shadersBuilding || !root.qsbAvailable)
            return;
        root.shadersBuilding = true;
        root.shadersFailed = false;
        root.shadersFailure = "";
        root.shadersDetail = "";
        _shadersBuild.running = false;
        Qt.callLater(() => _shadersBuild.running = true);
    }

    function installHyprbars() {
        if (root.hyprbarsInstalling || !root.hyprpmAvailable)
            return;
        root.hyprbarsInstalling = true;
        root.hyprbarsFailed = false;
        root.hyprbarsFailure = "";
        root.hyprbarsDetail = "";
        _hyprbarsPrep.running = false;
        Qt.callLater(() => _hyprbarsPrep.running = true);
    }

    function runHyprbarsInstall() {
        root.hyprbarsInstalling = true;
        root.hyprbarsFailed = false;
        root.hyprbarsFailure = "";
        root.hyprbarsDetail = "";
        _hyprbarsInstall.running = false;
        Qt.callLater(() => _hyprbarsInstall.running = true);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.hyprbarsCheck();
        }
    }

    // ── The window ───────────────────────────────────────────────────────────
    FloatingWindow {
        id: setupWindow

        visible: root.shouldShow
        title: qsTr("Set up the Akebono helper components · illogical-impulse")
        implicitWidth: 620
        implicitHeight: 720
        minimumSize: Qt.size(560, 640)
        color: "transparent"

        onVisibleChanged: if (visible) root.refresh()

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0

            AkebonoPluginSetupContent {
                id: content

                anchors.fill: parent
                anchors.margins: 26

                qsPluginBuilt: !root.pluginMissing
                qsPluginBuilding: AkebonoSystem.building
                qsPluginFailed: AkebonoSystem.buildResult === "failed"
                qsPluginFailure: AkebonoSystem.buildOutput
                qsPluginProgressText: AkebonoSystem.buildProgress
                qsPluginUnits: AkebonoSystem.buildUnits ?? 0
                qsPluginSeconds: AkebonoSystem.elapsedSeconds ?? 0
                qsPluginProgress: AkebonoSystem.buildProgressValue ?? 0
                cargoAvailable: AkebonoSystem.cargoAvailable
                onQsPluginBuildRequested: AkebonoSystem.build()

                qsbAvailable: root.qsbAvailable
                shadersBuilt: !root.shadersMissing
                shadersBuilding: root.shadersBuilding
                shadersFailed: root.shadersFailed
                shadersDetail: root.shadersDetail
                shadersFailure: root.shadersFailure
                onShadersBuildRequested: root.buildShaders()

                hyprpmAvailable: root.hyprpmAvailable
                hyprbarsReady: root.hyprbarsReady
                hyprbarsInstalling: root.hyprbarsInstalling
                hyprbarsFailed: root.hyprbarsFailed
                hyprbarsDetail: root.hyprbarsDetail
                hyprbarsFailure: root.hyprbarsFailure
                onHyprbarsInstallRequested: root.installHyprbars()

                onDismissed: root.dismiss()
            }
        }
    }

    // ── IPC ──────────────────────────────────────────────────────────────────
    /// `qs -c ii ipc call akebonoSetup open` — for anyone who dismissed it and wants
    /// it back without hunting for the Settings page.
    ///
    /// Named `open` rather than `show` because `qs ipc call <target> show` collides
    /// with the CLI's own `ipc show` and prints the target's signature.
    IpcHandler {
        target: "akebonoSetup"

        function open(): string {
            if (!root.anyMissing)
                return "Everything is set up; nothing to install.";
            if (Persistent.ready)
                Persistent.states.akebono.pluginSetupDismissed = "";
            root.settled = true;
            return "Setup shown.";
        }

        /// Starts the plugin build, as the window's button does. Useful for a first-boot
        /// script, and for anyone who would rather not wait for the window.
        function build(): string {
            if (!root.pluginMissing)
                return "The plugin is already built.";
            AkebonoSystem.build();
            return "Building. Open `qs -c ii ipc call akebonoSetup status` to watch.";
        }

        function buildShaders(): string {
            if (root.shadersBuilding)
                return "Shader build already running.";
            if (!root.qsbAvailable)
                return "qsb is missing; install qt6-shadertools first.";
            root.buildShaders();
            return "Compiling shaders.";
        }

        function installHyprbars(): string {
            if (root.hyprbarsInstalling)
                return "hyprbars install already running.";
            if (root.hyprbarsReady)
                return "hyprbars is already loaded.";
            if (!root.hyprpmAvailable)
                return "hyprpm is missing; install hyprpm first.";
            root.installHyprbars();
            return "Installing hyprbars (a password prompt may appear).";
        }

        function status(): string {
            if (AkebonoSystem.building)
                return `plugin: building (${AkebonoSystem.buildProgress}, ${AkebonoSystem.buildUnits} crates, ${AkebonoSystem.buildSeconds}s)`;
            if (root.shadersBuilding)
                return `shaders: compiling: ${root.shadersDetail}`;
            if (root.hyprbarsInstalling)
                return `hyprbars: installing: ${root.hyprbarsDetail}`;
            const missing = root.missingComponents();
            const state = missing.length === 0 ? "all set up"
                : `missing: ${missing.join(", ")}`;
            return `${state} (plugin ${AkebonoSystem.binaryExists ? "built" : "missing"}, `
                + `shaders ${root.shadersMissing ? "missing" : "built"}, `
                + `hyprbars ${root.hyprbarsReady ? "loaded" : "missing"})`;
        }
    }
}