pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.draw
import qs.modules.common.widgets
import "../../common/draw/StrokeGeometry.js" as StrokeGeometry

/**
 * Draw on the screen, over whatever is on it.
 *
 * The surface has three states, and the difference between them is the whole feature:
 *
 *   drawing  — the layer takes every touch, so a stroke goes to the ink and not to the
 *              browser underneath. The tray is up and the pencil is lit.
 *   kept     — the ink is still there and still on top, the tray is still up, and the
 *              layer takes nothing but the tray: taps go straight through to the
 *              applications. One tap on the pencil goes back to drawing.
 *   closed   — no tray at all, and the ink still on its workspace until it is rubbed out.
 *
 * A sheet belongs to the workspace it was drawn on, so switching away takes the drawing
 * with it and switching back brings it out again — which is what makes it an annotation
 * of that screen rather than a drawing that follows you around.
 */
PanelWindow {
    id: root

    readonly property string screenName: root.screen?.name ?? ""
    /// The sheet in front: this monitor's active workspace.
    readonly property string sheetKey: {
        void TabletLiveDrawStore.revision;
        return TabletLiveDrawStore.keyFor(root.screenName);
    }

    readonly property var strokes: {
        void TabletLiveDrawStore.revision;
        return TabletLiveDrawStore.strokesFor(root.sheetKey);
    }
    readonly property bool hasInk: root.strokes.length > 0

    /// Drawing mode belongs to the focused monitor only: two trays on two screens would
    /// both claim the pen, and only one of them is where the pen is.
    readonly property bool focusedHere: String(Hyprland.focusedMonitor?.name ?? "") === root.screenName

    /// Shell surfaces cover the screen; ink floating over the app drawer would be ink
    /// annotating the wrong thing.
    readonly property bool shellSurfaceOpen: GlobalStates.appDrawerOpen
        || GlobalStates.recentsOpen
        || GlobalStates.sessionOpen
        || GlobalStates.screenLocked

    /// Hidden for the length of a screenshot, so the tray is not in the picture.
    property bool hiddenForCapture: false

    readonly property bool trayShown: TabletLiveDrawStore.trayOpen && root.focusedHere
        && !root.shellSurfaceOpen && !root.hiddenForCapture
    // Not while the sheets are sliding past each other: the ink is translated then, so a
    // stroke would land wherever the animation happened to have put the canvas.
    readonly property bool drawing: TabletLiveDrawStore.drawing && root.trayShown && !root.sliding
    readonly property bool shown: (root.trayShown || root.hasInk || root.sliding)
        && !root.shellSurfaceOpen

    // ── Sliding between workspaces ──────────────────────────────────────────
    /**
     * The ink travels with the workspace it belongs to, a little behind the windows.
     *
     * A sheet is tied to a workspace, so switching already swaps which one is painted —
     * but swapping it instantly made the drawing look like part of the shell rather than
     * part of the screen it annotates. Sliding it in alongside the windows says what it
     * is; letting it swing a little wider than they do is what gives it a plane of its
     * own instead of being stuck to the glass.
     */
    readonly property bool parallaxEnabled: Config.options?.tablet?.liveDraw?.workspaceParallax ?? true

    readonly property int activeWorkspaceId: {
        for (const monitor of (Hyprland.monitors?.values ?? [])) {
            if (String(monitor?.name ?? "") === root.screenName)
                return monitor?.activeWorkspace?.id ?? -1;
        }
        return -1;
    }

    property int lastWorkspaceId: -1
    /// The sheet being left behind, painted only for the length of the transition.
    property var outgoingStrokes: []
    /// +1 when the new workspace is to the right, which is the way Hyprland slides.
    property int slideDirection: 1
    /// 0 at the start of the transition, 1 at rest.
    property real slideProgress: 1
    readonly property bool sliding: root.slideProgress < 0.999

    /**
     * How far the ink travels, against the full screen width the windows travel.
     *
     * Greater than one, so the sheet swings a little wider than the windows and trails
     * them into place — which is what a plane *in front* of them does, and the ink is on
     * the Overlay layer, in front of everything.
     *
     * Less than one was the first try and it is wrong here for a concrete reason, not an
     * aesthetic one: a sheet that starts closer to its resting place is already partly on
     * screen when the transition begins, overlapping the sheet still leaving. Two
     * drawings crossing through each other reads as a glitch rather than as depth.
     */
    readonly property real parallaxFactor: 1.12

    onActiveWorkspaceIdChanged: {
        const from = root.lastWorkspaceId;
        root.lastWorkspaceId = root.activeWorkspaceId;
        if (from < 0 || root.activeWorkspaceId < 0 || from === root.activeWorkspaceId)
            return;
        if (!root.parallaxEnabled)
            return;

        const previous = TabletLiveDrawStore.strokesFor(`${root.screenName}:${from}`);
        // Two blank sheets have nothing to slide, and animating them would keep an
        // Overlay surface painting for no reason on every workspace change.
        if (previous.length === 0 && root.strokes.length === 0)
            return;

        root.outgoingStrokes = previous;
        root.slideDirection = root.activeWorkspaceId > from ? 1 : -1;
        root.slideProgress = 0;
        slideAnimation.restart();
    }

    NumberAnimation {
        id: slideAnimation
        target: root
        property: "slideProgress"
        from: 0
        to: 1
        // Tuned to the compositor's own workspace slide rather than to this shell's
        // element animations: the ink is travelling alongside the windows, and the two
        // finishing at different times is exactly what would give the trick away.
        // Hyprland's `animations` block has `workspaces, speed = 7, bezier = menu_decel`.
        duration: 700
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.1, 1, 0, 1]
        onFinished: root.outgoingStrokes = []
    }

    Component.onCompleted: root.lastWorkspaceId = root.activeWorkspaceId

    property string statusText: ""

    function statusFor(text) {
        root.statusText = text;
        statusTimer.restart();
    }

    /**
     * Says something that outlives the toolbar.
     *
     * The status line under the tray is immediate but it dies with the tray — and the two
     * things worth confirming, filing a drawing into Notes and taking a screenshot, both
     * end with the tray gone or hidden. So they went through with no feedback at all. A
     * notification is the shell's own way of saying a thing happened, and it is still
     * there a moment later when the user looks up.
     */
    function announce(title, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", "Live draw",
                                 String(title), String(body), "-i", String(icon)]);
    }

    Timer {
        id: statusTimer
        interval: 2600
        repeat: false
        onTriggered: root.statusText = ""
    }

    // ── Screenshot ──────────────────────────────────────────────────────────
    /**
     * Takes the tray out of the picture, then takes the picture.
     *
     * Two steps because the tray is part of this layer and `grim` photographs the
     * composited output: without the pause it would appear in its own screenshot. The
     * ink is meant to be in the shot — annotating a screen and then capturing it is the
     * point — so only the tray goes.
     */
    function captureScreen() {
        root.hiddenForCapture = true;
        captureDelay.restart();
    }

    Timer {
        id: captureDelay
        // Long enough for the tray's fade to finish and the compositor to present a
        // frame without it. Shorter than this and the shot catches it mid-fade.
        interval: 320
        repeat: false
        onTriggered: {
            ShellActionRegistry.trigger("fullscreenScreenshot", root.screenName);
            captureRestore.restart();
        }
    }

    Timer {
        id: captureRestore
        interval: 600
        repeat: false
        onTriggered: {
            root.hiddenForCapture = false;
            root.statusFor(Translation.tr("Screenshot saved."));
            root.announce(Translation.tr("Screenshot saved"),
                          Translation.tr("In Pictures/Screenshots, and on the clipboard."),
                          "camera-photo");
        }
    }

    // ── Saving to Notes ─────────────────────────────────────────────────────
    /**
     * Crops the ink out of the screen-sized sheet and puts it in Notes.
     *
     * Cropped because a note holding a 1920×1080 PNG that is almost entirely empty is a
     * note nobody can read at a glance — what you drew is usually a corner of the screen,
     * and the corner is the note.
     *
     * Two steps, because a Canvas paints when the scene graph gets round to it rather
     * than when asked: the crop is requested here and grabbed once it has painted. A grab
     * taken straight after `requestPaint()` returns an empty image.
     */
    function saveToNotes() {
        if (!root.hasInk) {
            root.statusFor(Translation.tr("Nothing drawn yet."));
            return;
        }
        const bounds = StrokeGeometry.boundsOf(root.strokes);
        if (!bounds) {
            root.statusFor(Translation.tr("Nothing drawn yet."));
            return;
        }
        cropCanvas.bounds = bounds;
        cropCanvas.sourceStrokes = root.strokes;
        cropCanvas.pendingPath = NotesService.newSketchPath();
        cropCanvas.width = Math.max(1, Math.round(bounds.width));
        cropCanvas.height = Math.max(1, Math.round(bounds.height));
        cropCanvas.refresh();
        root.statusFor(Translation.tr("Saving…"));
    }

    function finishSave(written, path) {
        if (!written) {
            root.statusFor(Translation.tr("Could not write the drawing."));
            root.announce(Translation.tr("Could not save the drawing"),
                          Translation.tr("Writing the image failed."), "dialog-error");
            return;
        }
        const result = NotesService.createSketch(path);
        if (!result.ok) {
            root.statusFor(Translation.tr("Could not add it to Notes."));
            root.announce(Translation.tr("Could not save the drawing"),
                          Translation.tr("Notes would not take it."), "dialog-error");
            return;
        }
        root.statusFor(Translation.tr("Saved to Notes as “%1”.").arg(result.title));
        // Said out loud as well: the next two lines take the tray off the screen, and
        // the status line with it.
        root.announce(Translation.tr("Saved to Notes"),
                      Translation.tr("As “%1”.").arg(result.title), "accessories-text-editor");
        // The ink has somewhere permanent to live now, so the sheet goes. Leaving it
        // would mean the next save wrote the same drawing to a second note.
        TabletLiveDrawStore.clear(root.sheetKey);
        TabletLiveDrawStore.close();
    }

    // ── Surface ─────────────────────────────────────────────────────────────
    visible: root.shown

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:tabletLiveDraw"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never takes the keyboard. The tray has no text in it, and a surface holding focus
    // over every application is a surface that breaks typing everywhere.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    /**
     * What the layer accepts.
     *
     * Everything while drawing; only the tray once the pen is down; nothing at all once
     * the tray is closed. That last state is what "leave it on this workspace" means —
     * the ink stays painted on the Overlay layer and the compositor stops routing input
     * to it, so the applications underneath behave exactly as if it were not there.
     *
     * Both regions are always listed and the intersection flags do the work: two
     * Subtracts leave an empty mask, which is the click-through state.
     */
    mask: Region {
        regions: [fullRegion, trayRegion]
    }

    Region {
        id: fullRegion
        item: inkSurface
        intersection: root.drawing ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: trayRegion
        item: tray
        intersection: root.trayShown ? Intersection.Combine : Intersection.Subtract
    }

    /**
     * The sheet being left behind.
     *
     * A plain canvas rather than a second DrawSurface: it is a picture for the length of
     * the transition and never takes input. Loaded only while it has something to show,
     * so an idle shell carries one canvas, not two.
     */
    Loader {
        anchors.fill: parent
        active: root.sliding && root.outgoingStrokes.length > 0

        sourceComponent: DrawCanvas {
            strokes: root.outgoingStrokes
            transform: Translate {
                x: -root.slideProgress * root.width * root.slideDirection * root.parallaxFactor
            }
        }
    }

    DrawSurface {
        id: inkSurface
        anchors.fill: parent

        transform: Translate {
            x: (1 - root.slideProgress) * root.width * root.slideDirection * root.parallaxFactor
        }

        strokes: root.strokes
        drawing: root.drawing
        color: TabletLiveDrawStore.color
        strokeWidth: TabletLiveDrawStore.width
        usePressure: TabletLiveDrawStore.usePressure
        smoothing: TabletLiveDrawStore.smoothing
        eraser: TabletLiveDrawStore.eraser
        // The tray floats over the sheet; without this the canvas swallowed every pen
        // tap on it. See DrawSurface.excludeItem.
        excludeItem: tray

        onStrokeFinished: stroke => TabletLiveDrawStore.addStroke(root.sheetKey, stroke)
        onEraseRequested: (x, y) => TabletLiveDrawStore.eraseAt(root.sheetKey, x, y, inkSurface.eraserRadius)
    }

    /**
     * The same ink again, at the size of its own bounding box, offscreen.
     *
     * `Canvas.save` writes the whole item, so cropping means painting the strokes a
     * second time into a canvas that *is* the crop, with every point re-expressed
     * relative to its corner. One extra paint of a finished drawing, in exchange for a
     * file that is the drawing rather than the screen it happened to be on.
     */
    DrawCanvas {
        id: cropCanvas
        property var bounds: null
        property var sourceStrokes: []
        property string pendingPath: ""

        // Moved off the surface rather than hidden: an invisible item is not rendered at
        // all, and this one exists for nothing but its pixels.
        x: -20000
        y: -20000
        // Painted in the GUI thread and into an image, which is what the grab reads.
        immediate: true

        strokes: {
            if (!cropCanvas.bounds)
                return [];
            return (cropCanvas.sourceStrokes ?? []).map(stroke => ({
                color: stroke.color,
                width: stroke.width,
                usePressure: stroke.usePressure,
                points: stroke.points.map(p => ({
                    x: p.x - cropCanvas.bounds.x,
                    y: p.y - cropCanvas.bounds.y,
                    p: p.p
                }))
            }));
        }

        // The paint has landed, so there are pixels to grab. Requesting the grab any
        // earlier gets an empty image: a Canvas has nothing in its scene graph until it
        // has painted once.
        onCommittedPainted: {
            if (cropCanvas.pendingPath.length === 0)
                return;
            const path = cropCanvas.pendingPath;
            cropCanvas.pendingPath = "";
            cropCanvas.saveCommitted(path);
        }

        onSaved: (ok, path) => root.finishSave(ok, path)
    }

    // ── The pen tray ────────────────────────────────────────────────────────
    DrawToolbar {
        id: tray
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Clear of the dock, which is where a tray anchored to the bottom would land.
        anchors.bottomMargin: Appearance.sizes.minimumTouchTarget * 2.6
        visible: root.trayShown
        opacity: root.trayShown ? 1 : 0

        palette: TabletLiveDrawStore.palette
        currentColor: TabletLiveDrawStore.color
        strokeWidth: TabletLiveDrawStore.width
        eraser: TabletLiveDrawStore.eraser
        usePressure: TabletLiveDrawStore.usePressure
        pressureAvailable: inkSurface.penSeen
        canUndo: root.hasInk
        statusText: root.statusText
        drawing: TabletLiveDrawStore.drawing
        showDrawToggle: true

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tray)
        }

        onDrawToggled: {
            TabletLiveDrawStore.drawing = !TabletLiveDrawStore.drawing;
            root.statusFor(TabletLiveDrawStore.drawing
                ? Translation.tr("Drawing.")
                : Translation.tr("Pen down — taps go through to the apps."));
        }
        onColorPicked: colorValue => {
            TabletLiveDrawStore.color = colorValue;
            TabletLiveDrawStore.eraser = false;
        }
        onWidthPicked: widthValue => {
            TabletLiveDrawStore.width = widthValue;
            if (Config.ready)
                Config.options.tablet.liveDraw.width = Math.round(widthValue);
        }
        onEraserToggled: TabletLiveDrawStore.eraser = !TabletLiveDrawStore.eraser
        onPressureToggled: {
            if (Config.ready)
                Config.options.tablet.liveDraw.pressure = !Config.options.tablet.liveDraw.pressure;
        }
        onUndoRequested: TabletLiveDrawStore.undo(root.sheetKey)
        onClearRequested: {
            TabletLiveDrawStore.clear(root.sheetKey);
            root.statusFor(Translation.tr("Sheet cleared."));
        }

        // ── What happens to the drawing ─────────────────────────────────────
        trailingContent: [
            DrawToolButton {
                symbol: "screenshot_monitor"
                enabled: !root.hiddenForCapture
                tooltipText: Translation.tr("Screenshot without the toolbar")
                onTriggered: root.captureScreen()
            },
            DrawToolButton {
                symbol: "note_add"
                enabled: root.hasInk
                emphasised: true
                tooltipText: Translation.tr("Save to Notes")
                onTriggered: root.saveToNotes()
            },
            DrawToolButton {
                symbol: "close"
                tooltipText: Translation.tr("Put the toolbar away and leave the drawing")
                // Closes the tray *and* the pen, and keeps the ink. Losing work must
                // never be a side effect of tidying up — rubbing out is its own button.
                onTriggered: TabletLiveDrawStore.close()
            }
        ]
    }

    Connections {
        target: GlobalStates
        function onLiveDrawSaveRequestChanged() {
            if (root.focusedHere)
                root.saveToNotes();
        }
    }
}
