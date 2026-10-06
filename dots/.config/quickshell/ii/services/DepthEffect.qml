import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * The wallpaper's subject drawn over the desktop widgets.
 *
 * A model the user downloads (Settings → Background) cuts the subject out of
 * the picture once - scripts/depth/depth.py, at idle priority, in a process
 * that exits and gives its memory back - and the desktop draws that cutout in
 * the widgets window, on top of the widgets, landing on the wallpaper's own
 * pixels (modules/ii/background/depth/DepthCutoutLayer.qml). At rest the cost
 * is one textured quad; the model only runs when a picture without a cutout
 * comes on screen.
 *
 * Nothing ships installed and nothing is on by default: the ONNX runtime comes
 * with the first model and goes with the last, and cutouts are kept only for
 * the pictures on screen right now.
 */
Singleton {
    id: root

    readonly property string dataDir: FileUtils.trimFileProtocol(`${Directories.state}/depth`)
    readonly property string script: `${Directories.scriptPath}/depth/depth.sh`
    readonly property var options: Config.options.background.depthEffect

    // ── Catalogue and what is installed ─────────────────────────────────────
    property var models: []
    property var installed: []
    property bool runtimeReady: false
    property bool statusKnown: false
    readonly property bool anyInstalled: root.installed.length > 0
    // On and runnable. Read by every surface that draws or offers the effect.
    readonly property bool active: Config.ready && (root.options?.enable ?? false) && root.anyInstalled
    readonly property var installedModels: root.models.filter(m => root.installed.includes(m.id))

    function modelInfo(id) {
        return root.models.find(m => m.id === id) ?? null;
    }
    function isInstalled(id) {
        return root.installed.includes(id);
    }

    FileView {
        path: `${Directories.scriptPath}/depth/models.json`
        onLoaded: {
            try {
                root.models = JSON.parse(text()).models ?? [];
            } catch (e) {
                console.warn("[DepthEffect] models.json:", e);
            }
        }
    }

    function refreshStatus() {
        statusProc.running = true;
    }
    Component.onCompleted: root.refreshStatus()

    Process {
        id: statusProc
        command: [root.script, "--root", root.dataDir, "status"]
        stdout: SplitParser {
            onRead: data => root.handleEvent(data)
        }
    }

    // ── Downloads ───────────────────────────────────────────────────────────
    // One at a time: the first one also installs the runtime.
    property string downloadingModel: ""
    property real downloadProgress: 0
    property string downloadPhase: ""
    property string errorModel: ""
    property string errorMessage: ""
    property bool cancelling: false

    function download(id) {
        if (root.downloadingModel !== "" || root.isInstalled(id))
            return;
        root.errorModel = "";
        root.errorMessage = "";
        root.downloadProgress = 0;
        root.downloadPhase = "";
        root.downloadingModel = id;
        downloadProc.command = [root.script, "--root", root.dataDir, "download", id];
        downloadProc.running = true;
    }
    function cancelDownload() {
        if (root.downloadingModel === "")
            return;
        root.cancelling = true;
        downloadProc.running = false;
    }
    function remove(id) {
        if (removeProc.running)
            return;
        // A picture set to this model falls back to the default; no cutout of
        // it stays in memory either.
        root.dropCutoutsOf(id);
        removeProc.command = [root.script, "--root", root.dataDir, "remove", id];
        removeProc.running = true;
    }

    Process {
        id: downloadProc
        stdout: SplitParser {
            onRead: data => root.handleEvent(data, root.downloadingModel)
        }
        onExited: (exitCode, exitStatus) => {
            const id = root.downloadingModel;
            root.downloadingModel = "";
            if (root.cancelling) {
                root.cancelling = false;
                // Leaves nothing half-written behind (.part, a half runtime).
                removeProc.command = [root.script, "--root", root.dataDir, "remove", id];
                removeProc.running = true;
                return;
            }
            if (exitCode !== 0 && root.errorMessage === "") {
                root.errorModel = id;
                root.errorMessage = Translation.tr("The download stopped (exit code %1)").arg(exitCode);
            }
            root.refreshStatus();
        }
    }

    Process {
        id: removeProc
        stdout: SplitParser {
            onRead: data => root.handleEvent(data)
        }
    }

    // ── Per picture ─────────────────────────────────────────────────────────
    function cleanPath(path) {
        return FileUtils.trimFileProtocol(String(path ?? ""));
    }
    // "" = the default model, "off" = no cutout, or a model id.
    function choiceFor(path) {
        const clean = root.cleanPath(path);
        const entry = (root.options?.wallpapers ?? []).find(e => e && e.path === clean);
        return entry ? String(entry.model ?? "") : "";
    }
    function setChoice(path, model) {
        const clean = root.cleanPath(path);
        if (clean === "")
            return;
        const list = Array.from(root.options.wallpapers ?? []).filter(e => e && e.path !== clean);
        if (model !== "")
            list.push({ "path": clean, "model": model });
        Config.options.background.depthEffect.wallpapers = list;
    }
    readonly property string defaultModel: {
        const wanted = root.options?.model ?? "";
        if (wanted !== "" && root.isInstalled(wanted))
            return wanted;
        return root.installedModels.length > 0 ? root.installedModels[0].id : "";
    }
    // The model that cuts this picture, or "" when it gets no cutout.
    function modelFor(path) {
        if (!root.active || root.cleanPath(path) === "")
            return "";
        const choice = root.choiceFor(path);
        if (choice === "off")
            return "";
        if (choice !== "" && root.isInstalled(choice))
            return choice;
        return root.defaultModel;
    }

    // ── Wallpaper planes ────────────────────────────────────────────────────
    // Each screen's WallpaperImage, registered by BackgroundRoot. The cutout in
    // the widgets window reads the plane's live geometry from it.
    property var planes: ({})
    function registerPlane(screenName, plane) {
        const next = Object.assign({}, root.planes);
        next[screenName] = plane;
        root.planes = next;
    }
    function unregisterPlane(screenName, plane) {
        if (root.planes[screenName] !== plane)
            return;
        const next = Object.assign({}, root.planes);
        delete next[screenName];
        root.planes = next;
    }

    // ── Cutouts ─────────────────────────────────────────────────────────────
    // `${model}\n${path}` → the script's result: png, x/y/width/height in the
    // file's pixels, sourceWidth/sourceHeight, empty.
    property var cutouts: ({})
    property var failures: ({})
    property var wanted: ({}) // screen name → path on its plane
    property string workingKey: ""

    function keyOf(model, path) {
        return model + "\n" + root.cleanPath(path);
    }
    function cutoutFor(path) {
        const model = root.modelFor(path);
        return model === "" ? null : (root.cutouts[root.keyOf(model, path)] ?? null);
    }
    // "off", "working", "ready", "empty" (no subject found), "failed", "waiting".
    function stateFor(path) {
        const model = root.modelFor(path);
        if (model === "")
            return "off";
        const key = root.keyOf(model, path);
        if (root.workingKey === key)
            return "working";
        const cutout = root.cutouts[key];
        if (cutout)
            return cutout.empty ? "empty" : "ready";
        return root.failures[key] !== undefined ? "failed" : "waiting";
    }
    // Called by each screen's layer with the picture on its plane ("" for none).
    function want(screenName, path) {
        const clean = root.cleanPath(path);
        if ((root.wanted[screenName] ?? "") === clean)
            return;
        const next = Object.assign({}, root.wanted);
        if (clean === "")
            delete next[screenName];
        else
            next[screenName] = clean;
        root.wanted = next;
        root.schedule();
    }
    function dropCutoutsOf(model) {
        const next = {};
        for (const key in root.cutouts)
            if (!key.startsWith(model + "\n"))
                next[key] = root.cutouts[key];
        root.cutouts = next;
    }

    onActiveChanged: root.schedule()
    onDefaultModelChanged: root.schedule()
    Connections {
        target: Config.options.background.depthEffect
        function onWallpapersChanged() {
            root.schedule();
        }
    }

    function schedule() {
        pumpTimer.restart();
    }
    // Coalesces the burst of changes a wallpaper switch makes (path, then size,
    // then the commit) into one look at what is missing.
    Timer {
        id: pumpTimer
        interval: 250
        onTriggered: root.pump()
    }

    function wantedKeys() {
        const keys = [];
        for (const screen in root.wanted) {
            const path = root.wanted[screen];
            const model = root.modelFor(path);
            if (model !== "" && !keys.includes(root.keyOf(model, path)))
                keys.push(root.keyOf(model, path));
        }
        return keys;
    }

    function pump() {
        if (segmentProc.running || pruneProc.running)
            return;
        const keys = root.wantedKeys();
        // Only the pictures on screen keep their cutout, in memory and on disk.
        const kept = {};
        let dropped = false;
        for (const key in root.cutouts) {
            if (keys.includes(key))
                kept[key] = root.cutouts[key];
            else
                dropped = true;
        }
        if (dropped)
            root.cutouts = kept;
        const next = keys.find(key => root.cutouts[key] === undefined && root.failures[key] === undefined);
        if (next !== undefined) {
            const parts = next.split("\n");
            root.workingKey = next;
            segmentProc.command = [root.script, "--root", root.dataDir, "segment", "--model", parts[0], "--image", parts[1]];
            segmentProc.running = true;
            return;
        }
        // Nothing left to cut: the cutout files on disk follow the set kept
        // above (none at all once the effect is off).
        const keep = keys.map(key => root.cutouts[key]?.key).filter(k => !!k).sort();
        if (root.anyInstalled && keep.join(" ") !== root.prunedTo) {
            root.prunedTo = keep.join(" ");
            pruneProc.command = [root.script, "--root", root.dataDir, "prune", "--keep"].concat(keep);
            pruneProc.running = true;
        }
    }
    // The kept set the last prune left on disk; null until the first one, which
    // also clears whatever a previous session left behind.
    property var prunedTo: null

    Process {
        id: segmentProc
        stdout: SplitParser {
            onRead: data => root.handleEvent(data)
        }
        onExited: (exitCode, exitStatus) => {
            const key = root.workingKey;
            root.workingKey = "";
            if (key !== "" && root.cutouts[key] === undefined && root.failures[key] === undefined) {
                const failures = Object.assign({}, root.failures);
                failures[key] = Translation.tr("The cutout failed (exit code %1)").arg(exitCode);
                root.failures = failures;
            }
            root.schedule();
        }
    }

    Process {
        id: pruneProc
        onExited: root.schedule()
    }

    // ── Notifications ───────────────────────────────────────────────────────
    // One per run of the model, never for a cutout already on disk: posted when
    // the model starts and replaced in place when it ends, so the cutout's
    // couple of seconds (nine for the large model) are never silent.
    readonly property bool notificationsOn: root.options?.notify ?? true
    property int notificationId: 0
    property string notifiedKey: ""
    function describe(key) {
        const parts = key.split("\n");
        const model = root.modelInfo(parts[0]);
        const path = parts[1] ?? "";
        return "%1 · %2".arg(path.substring(path.lastIndexOf("/") + 1)).arg(model ? model.shortName : parts[0]);
    }
    // The card's icon is picked from the title (NotificationUtils keywords:
    // "subject" → layers, "cutout failed" → error); notify-send's -i would only
    // arrive as an image path. A timeout of 0 means "no popup" to this shell,
    // so the start card gets a long one and is replaced long before it ends.
    function notifyStarted(key) {
        if (!root.notificationsOn || key === "")
            return;
        root.notifiedKey = key;
        root.notificationId = 0;
        notifyStartProc.command = ["notify-send", "-p", "-a", Translation.tr("Depth effect"),
            "-t", "120000", "--hint=boolean:suppress-sound:true",
            Translation.tr("Cutting out the subject"), root.describe(key)];
        notifyStartProc.running = true;
    }
    function notifyFinished(key, title, detail) {
        if (!root.notificationsOn || key === "" || key !== root.notifiedKey)
            return;
        const args = ["notify-send", "-a", Translation.tr("Depth effect"), "-t", "5000",
            "--hint=boolean:suppress-sound:true"];
        if (root.notificationId > 0)
            args.push("-r", String(root.notificationId));
        Quickshell.execDetached(args.concat([title, root.describe(key) + "\n" + detail]));
        root.notifiedKey = "";
    }
    Process {
        id: notifyStartProc
        stdout: SplitParser {
            onRead: data => {
                const id = parseInt(data);
                if (!isNaN(id))
                    root.notificationId = id;
            }
        }
    }

    function handleEvent(line, modelId) {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (event.event) {
        case "status":
            root.runtimeReady = event.runtime;
            root.installed = event.models ?? [];
            root.statusKnown = true;
            // A model that came back gets another try at what it failed.
            root.failures = ({});
            root.prunedTo = null;
            root.schedule();
            break;
        case "progress":
            root.downloadPhase = event.phase;
            root.downloadProgress = event.total > 0 ? Math.min(1, event.received / event.total) : 0;
            break;
        case "working":
            root.notifyStarted(root.workingKey);
            break;
        case "result": {
            const key = root.workingKey;
            if (key === "")
                break;
            const cutouts = Object.assign({}, root.cutouts);
            cutouts[key] = event;
            root.cutouts = cutouts;
            if (!event.cached) {
                if (event.empty)
                    root.notifyFinished(key, Translation.tr("No clear subject"),
                        Translation.tr("Widgets stay in front of this picture. Another model may find one."));
                else
                    root.notifyFinished(key, Translation.tr("Subject cut out"),
                        Translation.tr("Ready in %1 s.").arg((event.ms / 1000).toFixed(1)));
            }
            break;
        }
        case "error":
            if (modelId) {
                root.errorModel = modelId;
                root.errorMessage = event.message;
            } else if (root.workingKey !== "") {
                const failures = Object.assign({}, root.failures);
                failures[root.workingKey] = event.message;
                root.failures = failures;
                root.notifyFinished(root.workingKey, Translation.tr("Subject cutout failed"), event.message);
            }
            console.warn("[DepthEffect]", event.message, event.detail ?? "");
            break;
        }
    }
}
