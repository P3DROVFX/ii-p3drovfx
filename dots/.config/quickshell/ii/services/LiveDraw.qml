pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import "../modules/common/draw/StrokeGeometry.js" as StrokeGeometry

/**
 * Live draw: the ink, which workspace each sheet of it belongs to, and the pen.
 *
 * Shared by every family that draws on the screen — the tablet's pen tray and the
 * desktop's annotation overlay are two surfaces over this one store, so whatever opens
 * live draw (a keybind, a quick toggle, the dock, the bar, the recording controls) only
 * has to call `toggle()` and read `trayOpen`.
 *
 * A drawing here is not a document — it is a note stuck to a workspace. You draw on top
 * of whatever is there, and it stays over that workspace until you rub it out or save
 * it, the way a sticky note stays on the monitor it was stuck to. So the store is keyed
 * by workspace, and the surface that draws it shows the sheet for the workspace in
 * front and nothing else.
 *
 * Deliberately in memory only. A workspace annotation that outlived a reboot would be a
 * surprise — you would come back to a machine with drawings on it and no memory of
 * making them — and the ink that is meant to last has a button that puts it in Notes.
 */
Singleton {
    id: root

    /// The pen preferences. They were the tablet's first and kept their place in the
    /// config, but they are the pen's, not the tablet's: both families read them.
    readonly property var opts: Config.options?.tablet?.liveDraw ?? null

    /// A stroke: { points: [{x, y, p}], color, width, usePressure }.
    /// Sheets: { "<monitor>:<workspace>": [stroke, …] }.
    ///
    /// Held by a PersistentProperties, so a live reload of the shell — which rebuilds
    /// every singleton, and on this machine happens whenever any QML file is saved —
    /// does not rub out a drawing someone is in the middle of presenting. Still memory
    /// only: a restart starts clean, as it should.
    property alias sheets: keptSheets.sheets

    PersistentProperties {
        id: keptSheets
        reloadableId: "liveDrawSheets"
        property var sheets: ({})
        // The pen and the tray too: a reload mid-annotation should leave the user
        // where they were, not drop them out of drawing.
        property bool drawing: false
        property bool trayOpen: false
        property real trayOffsetX: 0
        property real trayOffsetY: 0
        property bool trayCollapsed: false
        onLoaded: root.revision++
    }
    /// Bumped on every change, because a nested mutation of `sheets` is invisible to a
    /// binding. Everything that draws watches this rather than the object.
    property int revision: 0

    /**
     * Whether the pen is down.
     *
     * Off with the tray still up is the "keep it on this workspace" state: the ink shows,
     * taps go through to the applications, and one tap on the pencil picks the pen back
     * up. That round trip is the whole point — the first version had no way back, so a
     * sheet you had stopped drawing on could never be drawn on again, and the toolbar sat
     * there looking like it should still work.
     */
    property alias drawing: keptSheets.drawing

    /**
     * Whether the toolbar is on screen.
     *
     * Separate from `drawing`, because "put the pen down" and "put everything away" are
     * different requests and were previously the same button. Closing the tray leaves the
     * ink exactly where it is: losing work must never be a side effect of tidying up.
     */
    property alias trayOpen: keptSheets.trayOpen

    /**
     * Whether live draw exists at all in the running family. Off, every launcher hides
     * and `toggle()` does nothing; the ink already on screen is rubbed out with it.
     */
    readonly property bool enabled: Config.ready && (PanelFamily.isTablet
        ? (Config.options?.tablet?.liveDraw?.enable ?? true)
        : (Config.options?.liveDraw?.enable ?? true))
    onEnabledChanged: {
        // Only an actual switch-off: `enabled` is also false for the moment before the
        // config has loaded, and that must not rub out ink kept across a reload.
        if (!root.enabled && Config.ready) {
            root.close();
            root.clearAll();
        }
    }

    /// Enter live draw: tray up, pen down.
    function open() {
        if (!root.enabled)
            return;
        root.ensureTools();
        root.refreshWorkspaceAnimation();
        root.trayOpen = true;
        root.drawing = true;
    }

    /// The whole feature on or off — what every launcher calls.
    function toggle() {
        if (root.trayOpen)
            root.close();
        else
            root.open();
    }

    /**
     * Where the user dragged the tray, as an offset from where it starts.
     *
     * Kept here rather than on the surface, which is unloaded whenever there is nothing
     * to show: a tray moved out of the way of what is being recorded should still be out
     * of the way the next time it opens.
     */
    property alias trayOffsetX: keptSheets.trayOffsetX
    property alias trayOffsetY: keptSheets.trayOffsetY
    /// The tray folded down to the pen and the way back out, so it covers as little of
    /// a recording as possible.
    property alias trayCollapsed: keptSheets.trayCollapsed

    /// Leave live draw entirely. The ink stays on its workspace until it is rubbed out.
    function close() {
        root.drawing = false;
        root.trayOpen = false;
    }

    function toggleDrawing() {
        if (!root.trayOpen) {
            root.open();
            return;
        }
        root.drawing = !root.drawing;
    }

    // ── Tools ───────────────────────────────────────────────────────────────
    // Live, not persisted: which colour you were last using is a property of the drawing
    // you were doing. The defaults come from Config, which is where the durable
    // preferences live.
    property string color: ""
    property real width: 0
    property bool eraser: false

    readonly property var palette: {
        const configured = root.opts?.palette ?? [];
        const list = [];
        for (const entry of configured) {
            const value = String(entry ?? "").trim();
            if (value.length > 0)
                list.push(value);
        }
        return list.length > 0 ? list : ["#ffffff"];
    }

    readonly property bool usePressure: root.opts?.pressure ?? true
    readonly property real smoothing: Math.max(0, Math.min(0.95, (root.opts?.smoothing ?? 55) / 100))
    /// 0..1. See Config `liveDraw.mouseSmoothing` and DrawSurface.mouseSmoothing.
    readonly property real mouseSmoothing: Math.max(0, Math.min(1, (Config.options?.liveDraw?.mouseSmoothing ?? 60) / 100))

    function ensureTools() {
        if (root.color.length === 0)
            root.color = root.palette[0];
        if (root.width <= 0)
            root.width = Math.max(1, root.opts?.width ?? 4);
    }

    // ── Which sheet ─────────────────────────────────────────────────────────
    /**
     * The key for the workspace in front of a given monitor.
     *
     * Monitor as well as workspace, because Hyprland numbers workspaces across the whole
     * layout: two monitors never show the same one, but a sheet drawn on an external
     * display should not reappear on the laptop's because the numbers happened to line up
     * after a hotplug.
     */
    function keyFor(screenName) {
        const name = String(screenName ?? "");
        // A special workspace open over the monitor is what is in front, so it is the
        // sheet being drawn on — a scratchpad annotated and closed again should not
        // leave its ink on the workspace underneath.
        const special = root.specialFor(name);
        if (special.length > 0)
            return `${name}:${special}`;
        for (const monitor of (Hyprland.monitors?.values ?? [])) {
            if (String(monitor?.name ?? "") === name)
                return `${name}:${monitor?.activeWorkspace?.id ?? -1}`;
        }
        return `${name}:${Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1}`;
    }

    /// The special workspace open on a monitor, or "".
    function specialFor(screenName) {
        const monitor = (HyprlandData.monitors ?? []).find(entry => entry?.name === screenName);
        return String(monitor?.specialWorkspace?.name ?? "");
    }

    /// Whether any sheet on one monitor has ink. A screen with nothing drawn on any of its
    /// workspaces needs no surface at all.
    function screenHasInk(screenName) {
        void root.revision;
        const prefix = `${screenName}:`;
        for (const key in root.sheets) {
            if (key.startsWith(prefix) && (root.sheets[key] ?? []).length > 0)
                return true;
        }
        return false;
    }

    function strokesFor(key) {
        return root.sheets[key] ?? [];
    }

    function hasInk(key) {
        return root.strokesFor(key).length > 0;
    }

    /// Every sheet with something on it, so the surface knows whether to exist at all.
    readonly property int sheetCount: {
        void root.revision;
        let count = 0;
        for (const key in root.sheets) {
            if ((root.sheets[key] ?? []).length > 0)
                count++;
        }
        return count;
    }

    // ── Editing ─────────────────────────────────────────────────────────────
    /**
     * Undo and redo, per sheet, as snapshots of the sheet's stroke list.
     *
     * Snapshots rather than a log of operations because every edit already builds a new
     * list out of the same stroke objects: keeping the previous list costs one array of
     * references, and undoing a rubbed-out stroke or a cleared sheet is then the same
     * operation as undoing a new one. Memory only and not kept across a reload — a
     * history that outlived the shell would undo into drawings nobody remembers.
     */
    property var history: ({})
    property var future: ({})
    readonly property int historyLimit: 100

    function _setSheet(key, strokes) {
        const next = Object.assign({}, root.sheets);
        if (strokes.length > 0)
            next[key] = strokes;
        else
            delete next[key];
        root.sheets = next;
        root.revision++;
    }

    /// Records the sheet as it is now before an edit, and drops whatever was undone.
    function _remember(key) {
        const past = (root.history[key] ?? []).concat([root.sheets[key] ?? []]);
        root.history[key] = past.length > root.historyLimit ? past.slice(past.length - root.historyLimit) : past;
        root.future[key] = [];
        root.historyRevision++;
    }

    property int historyRevision: 0

    function canUndo(key) {
        void root.historyRevision;
        return (root.history[key] ?? []).length > 0;
    }

    function canRedo(key) {
        void root.historyRevision;
        return (root.future[key] ?? []).length > 0;
    }

    function addStroke(key, stroke) {
        if (!stroke || !stroke.points || stroke.points.length === 0)
            return;
        root._remember(key);
        root._setSheet(key, (root.sheets[key] ?? []).concat([stroke]));
    }

    function undo(key) {
        const past = root.history[key] ?? [];
        if (past.length === 0)
            return false;
        root.future[key] = (root.future[key] ?? []).concat([root.sheets[key] ?? []]);
        root.history[key] = past.slice(0, past.length - 1);
        root.historyRevision++;
        root._setSheet(key, past[past.length - 1]);
        return true;
    }

    function redo(key) {
        const ahead = root.future[key] ?? [];
        if (ahead.length === 0)
            return false;
        root.history[key] = (root.history[key] ?? []).concat([root.sheets[key] ?? []]);
        root.future[key] = ahead.slice(0, ahead.length - 1);
        root.historyRevision++;
        root._setSheet(key, ahead[ahead.length - 1]);
        return true;
    }

    /// Removes the strokes a rubbing gesture touched. Returns how many went.
    function eraseAt(key, x, y, radius) {
        const existing = root.sheets[key] ?? [];
        if (existing.length === 0)
            return 0;
        const kept = existing.filter(stroke => !StrokeGeometry.strokeHitBy(stroke, x, y, radius));
        if (kept.length === existing.length)
            return 0;
        root._remember(key);
        root._setSheet(key, kept);
        return existing.length - kept.length;
    }

    /// Rubs one sheet out. Undoable: the whole sheet comes back with one undo.
    function clear(key) {
        if ((root.sheets[key] ?? []).length === 0)
            return;
        root._remember(key);
        root._setSheet(key, []);
    }

    /// Every sheet, and every history with them: nothing left to undo into.
    function clearAll() {
        root.sheets = ({});
        root.history = ({});
        root.future = ({});
        root.historyRevision++;
        root.revision++;
    }

    // ── The compositor's workspace animation ────────────────────────────────
    /**
     * How Hyprland slides between workspaces, read from Hyprland.
     *
     * The ink travels alongside the windows, so its animation has to be *the same*
     * animation — and the first version hard-coded a duration and a curve copied out of
     * the user's config by hand. That is a guess with a shelf life: it was already wrong
     * (the curve was written with four values where `Easing.BezierSpline` needs six, so
     * QML fell back to linear and the ink kept sliding long after the windows had
     * arrived), and it would have gone wrong again the first time anyone edited their
     * `animations` block.
     *
     * `hyprctl animations -j` returns the configured animations and the bezier table, so
     * there is nothing here to keep in step by hand.
     */
    property int workspaceSlideMs: 500
    property var workspaceSlideCurve: [0.25, 0.1, 0.25, 1, 1, 1]
    /// False when the compositor animates workspaces instantly. Nothing to travel with.
    property bool workspaceSlideEnabled: true

    Process {
        id: animationProbe
        command: ["hyprctl", "animations", "-j"]
        stdout: StdioCollector { id: animationOut }
        onExited: code => {
            if (code !== 0)
                return;
            try {
                const parsed = JSON.parse(animationOut.text);
                const animations = parsed[0] ?? [];
                const beziers = parsed[1] ?? [];
                const workspaces = animations.find(entry => entry?.name === "workspaces");
                if (!workspaces)
                    return;

                root.workspaceSlideEnabled = workspaces.enabled !== false;
                // Hyprland's speed is in deciseconds. Zero means "inherit", which in
                // practice is the built-in default rather than an instant switch.
                const speed = Number(workspaces.speed ?? 0);
                root.workspaceSlideMs = speed > 0 ? Math.round(speed * 100) : 500;

                const curve = beziers.find(entry => entry?.name === workspaces.bezier);
                if (curve) {
                    // Six values: the two control points and the end point, which
                    // Easing.BezierSpline requires to be exactly (1, 1).
                    root.workspaceSlideCurve = [Number(curve.X0), Number(curve.Y0),
                                                Number(curve.X1), Number(curve.Y1), 1, 1];
                }
            } catch (error) {
                console.warn("[LiveDraw] could not read the workspace animation:", error);
            }
        }
    }

    /// Read on the first open rather than at startup: the launchers reference this store
    /// from the bar, the dock and the toggles, and a hyprctl call on every shell start
    /// for a feature most sessions never open is a call for nothing.
    property bool workspaceAnimationRead: false

    function refreshWorkspaceAnimation(force) {
        if (animationProbe.running || (root.workspaceAnimationRead && !force))
            return;
        root.workspaceAnimationRead = true;
        animationProbe.running = true;
    }

    /// A reloaded Hyprland config can change both numbers under us.
    Connections {
        target: Hyprland
        enabled: root.workspaceAnimationRead
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.refreshWorkspaceAnimation(true);
        }
    }
}
