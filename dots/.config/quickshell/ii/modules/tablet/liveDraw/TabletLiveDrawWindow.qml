pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "TabletStrokeGeometry.js" as StrokeGeometry

/**
 * Draw on the screen, over whatever is on it.
 *
 * The surface exists in two states and the difference between them is the whole feature:
 *
 *   drawing — the layer takes every touch, so a pen stroke goes to the ink and not to
 *             the browser underneath. The pen tray is up.
 *   kept    — the ink is still there and still on top, and the layer takes nothing: taps
 *             go straight through to the applications. This is the sticky-note state,
 *             and it lasts until the sheet is rubbed out.
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

    /// Drawing mode belongs to the focused monitor only: two pen trays on two screens
    /// would both claim the pen, and only one of them is where the pen is.
    readonly property bool focusedHere: String(Hyprland.focusedMonitor?.name ?? "") === root.screenName
    readonly property bool drawing: TabletLiveDrawStore.drawing && root.focusedHere
        && !GlobalStates.screenLocked

    /// Shell surfaces cover the screen; ink floating over the app drawer would be ink
    /// annotating the wrong thing.
    readonly property bool shellSurfaceOpen: GlobalStates.appDrawerOpen
        || GlobalStates.recentsOpen
        || GlobalStates.sessionOpen
        || GlobalStates.screenLocked

    readonly property bool shown: (root.drawing || root.hasInk) && !root.shellSurfaceOpen

    // ── Pen state ───────────────────────────────────────────────────────────
    /// Whether anything on this seat has ever reported a stylus. Drives the pressure
    /// control's enabled state, so it explains itself instead of looking broken.
    property bool penSeen: false
    property var livePoints: []
    property var smoothPoint: null

    readonly property real eraserRadius: Math.max(20, TabletLiveDrawStore.width * 3)

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

    // ── Drawing ─────────────────────────────────────────────────────────────
    function beginStroke(x, y, pressure) {
        TabletLiveDrawStore.ensureTools();
        const first = StrokeGeometry.point(x, y, pressure);
        root.smoothPoint = first;
        root.livePoints = [first];
        canvas.liveStroke = root.currentStrokeRecord();
        canvas.refreshLive();
    }

    function currentStrokeRecord() {
        return {
            points: root.livePoints,
            color: TabletLiveDrawStore.color,
            width: TabletLiveDrawStore.width,
            usePressure: TabletLiveDrawStore.usePressure
        };
    }

    function extendStroke(x, y, pressure) {
        if (root.livePoints.length === 0)
            return;
        const raw = StrokeGeometry.point(x, y, pressure);
        // Smoothed before the distance test, so the filter sees every sample and the
        // thinning only decides what is worth keeping afterwards.
        root.smoothPoint = StrokeGeometry.smoothed(root.smoothPoint, raw, TabletLiveDrawStore.smoothing);
        const last = root.livePoints[root.livePoints.length - 1];
        if (!StrokeGeometry.shouldAppend(last, root.smoothPoint))
            return;
        root.livePoints = root.livePoints.concat([root.smoothPoint]);
        canvas.liveStroke = root.currentStrokeRecord();
        canvas.refreshLive();
    }

    function endStroke() {
        if (root.livePoints.length > 0)
            TabletLiveDrawStore.addStroke(root.sheetKey, root.currentStrokeRecord());
        root.livePoints = [];
        root.smoothPoint = null;
        canvas.liveStroke = null;
        canvas.refreshLive();
    }

    function eraseAt(x, y) {
        TabletLiveDrawStore.eraseAt(root.sheetKey, x, y, root.eraserRadius);
    }

    // ── Saving ──────────────────────────────────────────────────────────────
    /**
     * Crops the ink out of the screen-sized sheet and puts it in Notes.
     *
     * Cropped because a note holding a 1920×1080 PNG that is almost entirely empty is a
     * note nobody can read at a glance — what you drew is usually a corner of the
     * screen, and the corner is the note.
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
        TabletLiveDrawStore.drawing = false;
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
    // Never takes the keyboard. The pen tray has no text in it, and a surface holding
    // focus over every application is a surface that breaks typing everywhere.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    /**
     * What the layer accepts.
     *
     * Everything while drawing; only the tray once the drawing is being kept. This is
     * the mechanism behind "leave it on this workspace": the ink stays painted on the
     * Overlay layer and the compositor stops routing input to it, so the applications
     * underneath behave exactly as if it were not there.
     */
    mask: Region {
        regions: root.drawing ? [fullRegion] : [trayRegion]
    }

    Region {
        id: fullRegion
        item: inkArea
        intersection: root.drawing ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: trayRegion
        item: tray
        intersection: (!root.drawing && root.hasInk) ? Intersection.Combine : Intersection.Subtract
    }

    Item {
        id: inkArea
        anchors.fill: parent

        TabletLiveDrawCanvas {
            id: canvas
            anchors.fill: parent
            strokes: root.strokes
        }

        /**
         * The same ink again, at the size of its own bounding box, offscreen.
         *
         * `Canvas.save` writes the whole item, so cropping means painting the strokes a
         * second time into a canvas that *is* the crop, with every point re-expressed
         * relative to its corner. One extra paint of a finished drawing, in exchange for
         * a file that is the drawing rather than the screen it happened to be on.
         */
        TabletLiveDrawCanvas {
            id: cropCanvas
            property var bounds: null
            property var sourceStrokes: []
            property string pendingPath: ""

            // Moved off the surface rather than hidden: an invisible item is not
            // rendered, and this one exists for nothing but its pixels.
            x: -20000
            y: -20000
            // Painted in the GUI thread and into an image, which is what `save` reads.
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
            // earlier gets an empty image: a Canvas has nothing in its scene graph until
            // it has painted once.
            onCommittedPainted: {
                if (cropCanvas.pendingPath.length === 0)
                    return;
                const path = cropCanvas.pendingPath;
                cropCanvas.pendingPath = "";
                cropCanvas.saveCommitted(path);
            }

            onSaved: (ok, path) => root.finishSave(ok, path)
        }

        /**
         * The pen.
         *
         * A PointHandler rather than a MouseArea, because a MouseArea reports no
         * pressure: Qt delivers a stylus as a pointer device with a `pressure` on each
         * point, and that number is what OpenTabletDriver spends its whole existence
         * producing. Fingers and the mouse arrive through the same handler and report
         * pressure 1, which is the right answer for them — a finger has no pressure to
         * report and a stroke drawn with one should be an even line.
         *
         * The eraser end of a stylus is a distinct pointer type, so turning the pen over
         * rubs out without going near the tray.
         */
        PointHandler {
            id: pen
            enabled: root.drawing

            readonly property bool eraserTip:
                pen.point.device?.pointerType === PointerDevice.Eraser
            readonly property bool erasing: pen.eraserTip || TabletLiveDrawStore.eraser

            /**
             * Whether a real pressure-reporting device has been seen.
             *
             * Measured from the values rather than asked of the device: a mouse and a
             * finger both report exactly 1, and anything strictly between the ends is a
             * device that is actually measuring. That test needs no enum to be spelled
             * correctly and no assumption about how the driver presents itself, which
             * matters when the driver is OpenTabletDriver presenting a virtual tablet.
             */
            function noteDevice() {
                const pressure = pen.point.pressure;
                if (pressure > 0.001 && pressure < 0.999)
                    root.penSeen = true;
                if (pen.point.device?.pointerType === PointerDevice.Pen
                        || pen.point.device?.pointerType === PointerDevice.Eraser)
                    root.penSeen = true;
            }

            onActiveChanged: {
                if (pen.active) {
                    pen.noteDevice();
                    if (pen.erasing)
                        root.eraseAt(pen.point.position.x, pen.point.position.y);
                    else
                        root.beginStroke(pen.point.position.x, pen.point.position.y, pen.point.pressure);
                } else if (root.livePoints.length > 0) {
                    root.endStroke();
                }
            }

            onPointChanged: {
                if (!pen.active)
                    return;
                pen.noteDevice();
                if (pen.erasing)
                    root.eraseAt(pen.point.position.x, pen.point.position.y);
                else
                    root.extendStroke(pen.point.position.x, pen.point.position.y, pen.point.pressure);
            }
        }
    }

    // ── The pen tray ────────────────────────────────────────────────────────
    TabletLiveDrawToolbar {
        id: tray
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Clear of the dock, which is where a tray anchored to the bottom would land.
        anchors.bottomMargin: Appearance.sizes.minimumTouchTarget * 2.6
        visible: root.shown
        opacity: root.drawing || root.hasInk ? 1 : 0

        palette: TabletLiveDrawStore.palette
        currentColor: TabletLiveDrawStore.color
        strokeWidth: TabletLiveDrawStore.width
        eraser: TabletLiveDrawStore.eraser
        usePressure: TabletLiveDrawStore.usePressure
        pressureAvailable: root.penSeen
        canUndo: root.hasInk
        canSave: root.hasInk
        statusText: root.statusText

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tray)
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
        onSaveRequested: root.saveToNotes()
        onKeepRequested: {
            TabletLiveDrawStore.drawing = false;
            root.statusFor(Translation.tr("Left on this workspace. Rub it out to remove it."));
        }
        onCloseRequested: {
            // Closes the pen, not the drawing: ink already on the sheet stays where it
            // is. Rubbing out is a separate, deliberate button, because "put the pen
            // down" should never be the thing that loses work.
            TabletLiveDrawStore.drawing = false;
        }
    }

    Connections {
        target: GlobalStates
        function onLiveDrawSaveRequestChanged() {
            if (root.focusedHere)
                root.saveToNotes();
        }
    }

    // Drawing mode is per-monitor, and leaving the monitor puts the pen down rather than
    // leaving a surface swallowing every touch on a screen the user has left.
    onFocusedHereChanged: {
        if (!root.focusedHere && TabletLiveDrawStore.drawing)
            root.endStroke();
    }
}
