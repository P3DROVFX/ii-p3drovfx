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
    readonly property bool drawing: TabletLiveDrawStore.drawing && root.trayShown
    readonly property bool shown: (root.trayShown || root.hasInk) && !root.shellSurfaceOpen

    property string statusText: ""

    function statusFor(text) {
        root.statusText = text;
        statusTimer.restart();
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
            root.statusFor(Translation.tr("Saved to Pictures, and on the clipboard."));
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
            return;
        }
        const result = NotesService.createSketch(path);
        if (!result.ok) {
            root.statusFor(Translation.tr("Could not add it to Notes."));
            return;
        }
        root.statusFor(Translation.tr("Saved to Notes as “%1”.").arg(result.title));
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

    DrawSurface {
        id: inkSurface
        anchors.fill: parent

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
