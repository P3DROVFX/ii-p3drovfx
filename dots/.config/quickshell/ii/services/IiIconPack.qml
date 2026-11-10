pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * ii-icon-pack, managed from the shell.
 *
 * The pack lives in its own repository (github.com/P3DROVFX/ii-icon-pack) together with the
 * code that renders it: `scripts/iipack.py` installs the theme into ~/.local/share/icons,
 * redraws every app icon on another plate shape and pulls updates. This service only drives
 * it through scripts/icons/ii_icon_pack.sh, which clones the repository on the first install,
 * so the pack's own install.sh and this page always run the same code.
 *
 * Every job (install, update, reshape) runs one at a time. A reshape asked for while another
 * job runs is kept - only the newest, since the ones in between were never on screen - and
 * starts when the running job ends. When the pack is the desktop's icon theme (or the base
 * themed icons recolor), a finished job hands it back to IconThemes so the recolored copy is
 * rebuilt and every running app reloads its icons.
 */
Singleton {
    id: root

    readonly property string themeName: "ii-icon-pack"
    readonly property var options: Config.options.appearance.icons.iiPack
    readonly property string scriptPath: `${Directories.scriptPath}/icons/ii_icon_pack.sh`
    readonly property string previewRoot: FileUtils.trimFileProtocol(`${Directories.cache}/ii-icon-pack/previews`)

    // ------------------------------------------------------------------------- status

    property bool statusReady: false
    property bool sourcePresent: false
    property bool installed: false
    /// Installed by iipack.py (it remembers its options). A theme copied or symlinked in by hand is not.
    property bool managed: false
    property string sourceCommit: ""
    property string installedCommit: ""
    property string installedDate: ""
    property string remoteCommit: ""
    property bool updateAvailable: false
    property bool checkingRemote: false
    property var installedOptions: ({})

    /// [{ key, name, glyphFactor, materialShape }]
    property var shapes: []

    /// A function, not a binding: shell.qml creates this service at startup for its IPC, and a
    /// binding would drag IconThemes (loaded on demand by Settings) in with it.
    function isCurrentPack(): bool {
        return IconThemes.currentPack === root.themeName;
    }

    /// The options in Config are what the user picked; the installed theme may still be on older ones.
    readonly property bool optionsPending: root.installed && root.managed && (
        String(root.installedOptions.shape ?? "") !== String(root.options.shape)
        || Math.abs(Number(root.installedOptions.plateScale ?? 1) - root.options.plateScale) > 0.001
        || Math.abs(Number(root.installedOptions.glyphScale ?? 1) - root.options.glyphScale) > 0.001)

    function shapeName(key: string): string {
        const entry = root.shapes.find(shape => shape.key === key);
        return entry ? entry.name : key;
    }

    // ---------------------------------------------------------------------------- jobs

    property bool busy: false
    property string busyAction: ""
    property real progress: 0
    property string message: ""
    property string lastError: ""
    property var queuedJob: null

    function _sourceArg(): string {
        return String(root.options.source ?? "").trim();
    }

    function _shapeArgs(): var {
        return ["--shape", String(root.options.shape),
            "--plate-scale", Number(root.options.plateScale).toFixed(3),
            "--glyph-scale", Number(root.options.glyphScale).toFixed(3)];
    }

    /// Download (first time) and render the pack with the picked shape.
    function install() {
        root._request({ "action": "install", "args": ["install", ...root._shapeArgs()] });
    }

    /// Pull the newest pack from GitHub and render it again with the installed shape.
    function update() {
        root._request({ "action": "update", "args": ["update"] });
    }

    /**
     * Render the installed pack with the options in Config. Debounced, so dragging a slider or
     * clicking through shapes ends in one render rather than one per step.
     */
    function applyOptions() {
        if (!root.installed && !root.busy) return;
        applyDebounce.restart();
    }

    Timer {
        id: applyDebounce
        interval: 700
        onTriggered: root._request({ "action": "apply", "args": ["install", ...root._shapeArgs()] })
    }

    function _request(job: var) {
        if (root.busy) {
            root.queuedJob = job;
            return;
        }
        root._start(job);
    }

    function _start(job: var) {
        root.busy = true;
        root.busyAction = job.action;
        root.progress = 0;
        root.lastError = "";
        root.message = job.action === "update" ? Translation.tr("Checking for updates")
            : Translation.tr("Preparing the icons");
        jobProcess.result = null;
        jobProcess.command = ["bash", root.scriptPath, root._sourceArg(), ...job.args];
        jobProcess.running = true;
    }

    Process {
        id: jobProcess
        property var result: null

        stdout: SplitParser {
            onRead: data => {
                const line = String(data);
                if (line.startsWith("@progress ")) {
                    const rest = line.slice(10);
                    const space = rest.indexOf(" ");
                    root.progress = Math.max(0, Math.min(1, parseFloat(space > 0 ? rest.slice(0, space) : rest) || 0));
                    if (space > 0) root.message = rest.slice(space + 1);
                    return;
                }
                if (line.startsWith("{")) {
                    try {
                        jobProcess.result = JSON.parse(line);
                    } catch (e) {}
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = jobProcess.result;
            const ok = exitCode === 0 && result && result.ok !== false;
            const action = root.busyAction;
            root.busy = false;
            root.busyAction = "";
            if (!ok) {
                root.lastError = result?.error ?? Translation.tr("The icon pack job failed (exit %1).").arg(exitCode);
                root.message = "";
                console.warn("[IiIconPack]", action, "failed:", root.lastError);
            } else {
                root.progress = 1;
                root.message = "";
                if (action === "update") root.updateAvailable = false;
                // The theme on disk changed under the name the desktop uses: rebuild the recolored
                // copy (themed icons) or have every app reload the pack.
                if (root.isCurrentPack() && result.installed !== false) IconThemes.applyPack(root.themeName);
                IconThemes.refreshPacks();
            }
            root.refresh(false);
            if (root.queuedJob) {
                const next = root.queuedJob;
                root.queuedJob = null;
                root._start(next);
            }
        }
    }

    /// Make the pack the desktop's icon theme (or the base themed icons recolor).
    function useAsIconTheme() {
        IconThemes.applyPack(root.themeName);
    }

    // -------------------------------------------------------------------------- status

    /// Local status is a file read; `remote` also asks GitHub whether a newer pack exists.
    function refresh(remote = false) {
        if (statusProcess.running) return;
        root.checkingRemote = remote;
        statusProcess.command = ["bash", root.scriptPath, root._sourceArg(), "status", ...(remote ? ["--remote"] : [])];
        statusProcess.running = true;
    }

    Process {
        id: statusProcess
        stdout: StdioCollector {
            onStreamFinished: {
                let status = null;
                for (const line of String(text).split("\n")) {
                    if (!line.startsWith("{")) continue;
                    try {
                        status = JSON.parse(line);
                    } catch (e) {}
                }
                root.checkingRemote = false;
                if (!status || status.ok === false) return;
                root.sourcePresent = status.sourcePresent === true;
                root.installed = status.installed === true;
                root.managed = status.managed === true;
                root.sourceCommit = status.sourceCommit ?? "";
                root.installedCommit = status.installedCommit ?? "";
                root.installedDate = status.installedDate ?? "";
                root.installedOptions = status.options ?? {};
                if (status.remoteCommit !== undefined) {
                    root.remoteCommit = status.remoteCommit;
                    root.updateAvailable = status.updateAvailable === true;
                } else if (status.renderPending === true) {
                    root.updateAvailable = true;
                }
                root.statusReady = true;
                if (root.sourcePresent && root.shapes.length === 0 && !shapesProcess.running) shapesProcess.running = true;
            }
        }
        onExited: root.checkingRemote = false
    }

    Process {
        id: shapesProcess
        command: ["bash", root.scriptPath, root._sourceArg(), "shapes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(String(text).trim().split("\n").pop());
                    if (parsed.ok) root.shapes = parsed.shapes.map(shape => ({
                        "key": shape.key,
                        "name": shape.name,
                        "glyphFactor": shape.glyphFactor,
                        "materialShape": shape.materialShape
                    }));
                } catch (e) {
                    console.warn("[IiIconPack] could not read the shape list");
                }
            }
        }
    }

    // ------------------------------------------------------------------------ previews

    /// key -> file path of a sample icon drawn in that shape, in the current palette.
    property var previews: ({})
    property int previewRevision: 0
    property var _queuedPreview: null

    /**
     * One sample icon per shape, painted with the given plate/glyph colors and the slider
     * values, so the picker shows what each shape will look like before anything is rendered.
     * Each run writes into a fresh directory: Image caches by URL.
     */
    function refreshPreviews(plateColor: color, glyphColor: color) {
        if (!root.sourcePresent) return;
        const request = { "plate": root._hex(plateColor), "glyph": root._hex(glyphColor) };
        if (previewProcess.running) {
            root._queuedPreview = request;
            return;
        }
        root._runPreview(request);
    }

    /// "#rrggbb" for the pack, alpha dropped.
    function _hex(value: color): string {
        const channel = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return `#${channel(value.r)}${channel(value.g)}${channel(value.b)}`;
    }

    function _runPreview(request: var) {
        root.previewRevision += 1;
        previewProcess.command = ["bash", "-c",
            `rm -rf "$1"; mkdir -p "$1" && exec bash "$2" "$3" preview --out "$1/${root.previewRevision}" --plate-color "$4" --glyph-color "$5" --plate-scale "$6" --glyph-scale "$7"`,
            "preview", root.previewRoot, root.scriptPath, root._sourceArg(), request.plate, request.glyph,
            Number(root.options.plateScale).toFixed(3), Number(root.options.glyphScale).toFixed(3)];
        previewProcess.running = true;
    }

    /// `qs -c ii ipc call iconPack setShape squircle`, for keybinds and scripts.
    IpcHandler {
        target: "iconPack"

        function install(): void {
            root.install();
        }

        function update(): void {
            root.update();
        }

        function setShape(shape: string): void {
            // Accept the shell's MaterialShape names too ("Cookie9Sided" -> "cookie-9").
            const wanted = String(shape).trim();
            const entry = root.shapes.find(s => s.key === wanted.toLowerCase() || s.materialShape === wanted);
            root.options.shape = entry ? entry.key : wanted.toLowerCase();
            if (root.installed) root.applyOptions();
            else root.install();
        }

        function setScales(plateScale: real, glyphScale: real): void {
            root.options.plateScale = Math.max(0.6, Math.min(1.08, plateScale));
            root.options.glyphScale = Math.max(0.5, Math.min(1.5, glyphScale));
            root.applyOptions();
        }

        /// The last known state; also starts a fresh local read for the next call.
        function status(): string {
            root.refresh(false);
            return JSON.stringify({
                "installed": root.installed,
                "managed": root.managed,
                "busy": root.busy,
                "progress": root.progress,
                "message": root.message,
                "error": root.lastError,
                "shape": root.installedOptions.shape ?? "",
                "commit": root.installedCommit,
                "updateAvailable": root.updateAvailable
            });
        }
    }

    Process {
        id: previewProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(String(text).trim().split("\n").pop());
                    if (parsed.ok) root.previews = parsed.previews;
                } catch (e) {}
            }
        }
        onExited: {
            if (!root._queuedPreview) return;
            const next = root._queuedPreview;
            root._queuedPreview = null;
            root._runPreview(next);
        }
    }

}
