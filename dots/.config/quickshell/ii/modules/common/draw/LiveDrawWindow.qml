pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "StrokeGeometry.js" as StrokeGeometry

/**
 * Draw on the screen, over whatever is on it.
 *
 * One per screen, shared by the families: the tablet's pen tray and the desktop's
 * annotation overlay differ only in what may cover the ink (`coveredByShell`), what takes
 * the pointer away from it for a while (`inputSuspended`), where the tray sits and the
 * layer's namespace. Everything else — the sheets, the slide, the save, the tray — is
 * this file.
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
        void LiveDraw.revision;
        void root.activeWorkspaceId;
        void root.specialName;
        return LiveDraw.keyFor(root.screenName);
    }

    readonly property var strokes: {
        void LiveDraw.revision;
        return LiveDraw.strokesFor(root.sheetKey);
    }
    readonly property bool hasInk: root.strokes.length > 0

    /// Drawing mode belongs to the focused monitor only: two trays on two screens would
    /// both claim the pen, and only one of them is where the pen is.
    readonly property bool focusedHere: String(Hyprland.focusedMonitor?.name ?? "") === root.screenName

    /// A shell surface covers the screen. Ink floating over an app drawer or an overview
    /// would be ink annotating the wrong thing, so the whole layer goes.
    property bool coveredByShell: false
    /// Another shell tool needs the pointer for a moment (a region selection, say). The
    /// ink stays — it is often exactly what is being captured — but the tray goes and
    /// the pen stops taking input, so the tool underneath gets its clicks.
    property bool inputSuspended: false
    /// Where the tray rests, above the bottom edge.
    property real trayBottomMargin: Appearance.sizes.minimumTouchTarget * 2.6
    /// Whether the tray can be picked up and moved, and folded down to the pen.
    property bool trayMovable: false
    property bool parallaxEnabled: true

    readonly property bool shellSurfaceOpen: root.coveredByShell

    /// Hidden for the length of a screenshot, so the tray is not in the picture.
    property bool hiddenForCapture: false

    readonly property bool trayShown: LiveDraw.trayOpen && root.focusedHere
        && !root.shellSurfaceOpen && !root.hiddenForCapture && !root.inputSuspended
    // Not while the sheets are sliding past each other: the ink is translated then, so a
    // stroke would land wherever the animation happened to have put the canvas.
    readonly property bool drawing: LiveDraw.drawing && root.trayShown && !root.sliding
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
    readonly property int activeWorkspaceId: {
        for (const monitor of (Hyprland.monitors?.values ?? [])) {
            if (String(monitor?.name ?? "") === root.screenName)
                return monitor?.activeWorkspace?.id ?? -1;
        }
        return -1;
    }
    /// A special workspace slides in from above rather than across, and the sheet
    /// swaps without travelling — its key is its own, see LiveDraw.keyFor.
    readonly property string specialName: {
        void HyprlandData.monitors;
        return LiveDraw.specialFor(root.screenName);
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
        if (root.specialName.length > 0)
            return;
        if (!root.parallaxEnabled || !LiveDraw.workspaceSlideEnabled)
            return;

        const previous = LiveDraw.strokesFor(`${root.screenName}:${from}`);
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
        // The compositor's own numbers, read from `hyprctl animations`. Not this shell's
        // element animations and not a constant copied out of a config by hand: the ink
        // travels alongside the windows, and the two finishing at different times is
        // exactly what gives the trick away. See LiveDraw.
        duration: LiveDraw.workspaceSlideMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: LiveDraw.workspaceSlideCurve
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
        LiveDraw.clear(root.sheetKey);
        LiveDraw.close();
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
    property string namespace: "quickshell:liveDraw"
    WlrLayershell.namespace: root.namespace
    WlrLayershell.layer: WlrLayer.Overlay
    /**
     * The keyboard, only while the pen is down.
     *
     * While drawing every click already lands here, so taking the keys too costs the
     * applications nothing and is what makes Ctrl+Z, the inks on 1–9 and Esc work. The
     * moment the pen goes up — clicks through, or the tray closed — the keyboard goes
     * straight back to the window underneath, as if this surface were not there.
     * Exclusive rather than on-demand so the shortcuts work from the first stroke,
     * without a click to focus first; the compositor's own binds still run either way.
     */
    WlrLayershell.keyboardFocus: (root.drawing || root.settingsOpen) && root.visible
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── Settings popup ──────────────────────────────────────────────────────
    property bool settingsOpen: false
    readonly property bool settingsShown: root.settingsOpen && root.trayShown && !LiveDraw.trayCollapsed
    onTrayShownChanged: if (!root.trayShown) root.settingsOpen = false

    // ── Keyboard ────────────────────────────────────────────────────────────
    function nudgeWidth(delta) {
        LiveDraw.ensureTools();
        const next = Math.max(1, Math.min(24, Math.round(LiveDraw.width) + delta));
        LiveDraw.width = next;
        if (Config.ready)
            Config.options.tablet.liveDraw.width = next;
        root.statusFor(Translation.tr("Thickness %1 px").arg(next));
    }

    /// 1–9 for the number row's keys by position (evdev KEY_1..KEY_9 are X keycodes
    /// 10..18), 0 for anything else.
    function digitRow(event) {
        const code = event.nativeScanCode;
        return code >= 10 && code <= 18 ? code - 9 : 0;
    }

    function handleKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const key = event.key;

        if (key === Qt.Key_Escape) {
            if (root.settingsOpen)
                root.settingsOpen = false;
            else
                LiveDraw.close();
        } else if (ctrl && (key === Qt.Key_Z) && !shift) {
            if (!LiveDraw.undo(root.sheetKey))
                root.statusFor(Translation.tr("Nothing to undo."));
        } else if (ctrl && ((key === Qt.Key_Z && shift) || key === Qt.Key_Y)) {
            if (!LiveDraw.redo(root.sheetKey))
                root.statusFor(Translation.tr("Nothing to redo."));
        } else if (ctrl && key === Qt.Key_S) {
            root.saveToNotes();
        } else if (ctrl) {
            return false;
        } else if (key === Qt.Key_E) {
            LiveDraw.eraser = !LiveDraw.eraser;
        } else if (key === Qt.Key_P || key === Qt.Key_B) {
            LiveDraw.eraser = false;
        } else if ((key >= Qt.Key_1 && key <= Qt.Key_9) || root.digitRow(event) > 0) {
            // By the key's place as well as its symbol: on AZERTY the number row types
            // & é " ' without Shift, and those are still the keys labelled 1–9.
            const index = (key >= Qt.Key_1 && key <= Qt.Key_9) ? key - Qt.Key_1 : root.digitRow(event) - 1;
            const ink = LiveDraw.palette[index];
            if (ink) {
                LiveDraw.color = ink;
                LiveDraw.eraser = false;
            }
        } else if (key === Qt.Key_BracketLeft || key === Qt.Key_Minus) {
            root.nudgeWidth(-1);
        } else if (key === Qt.Key_BracketRight || key === Qt.Key_Plus || key === Qt.Key_Equal) {
            root.nudgeWidth(1);
        } else if (key === Qt.Key_Delete || key === Qt.Key_Backspace) {
            if (root.hasInk) {
                LiveDraw.clear(root.sheetKey);
                root.statusFor(Translation.tr("Screen cleared — Ctrl+Z brings it back."));
            }
        } else if (key === Qt.Key_Tab) {
            LiveDraw.drawing = !LiveDraw.drawing;
        } else if (key === Qt.Key_C && root.trayMovable) {
            LiveDraw.trayCollapsed = !LiveDraw.trayCollapsed;
        } else {
            return false;
        }
        return true;
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: event => event.accepted = root.handleKey(event)
    }

    onDrawingChanged: if (root.drawing) keyCatcher.forceActiveFocus()

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
        regions: [fullRegion, trayRegion, settingsRegion]
    }

    Region {
        id: settingsRegion
        item: settingsSheet
        intersection: root.settingsShown ? Intersection.Combine : Intersection.Subtract
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
        color: LiveDraw.color
        strokeWidth: LiveDraw.width
        usePressure: LiveDraw.usePressure
        smoothing: LiveDraw.smoothing
        eraser: LiveDraw.eraser
        // The tray floats over the sheet; without this the canvas swallowed every pen
        // tap on it. See DrawSurface.excludeItem.
        excludeItem: tray
        excludeItems: [settingsSheet]
        mouseSmoothing: LiveDraw.mouseSmoothing

        onStrokeFinished: stroke => LiveDraw.addStroke(root.sheetKey, stroke)
        onEraseRequested: (x, y) => LiveDraw.eraseAt(root.sheetKey, x, y, inkSurface.eraserRadius)
    }

    /**
     * The drawing's own settings, next to the tray: above it while the tray sits in the
     * lower half of the screen, below it otherwise, and never off the edge.
     */
    StyledRectangularShadow {
        target: settingsSheet
        visible: settingsSheet.visible && !Config.options.appearance.transparency.enable
    }

    LiveDrawSettings {
        id: settingsSheet
        readonly property real gap: 10
        readonly property bool above: tray.y + tray.height / 2 > root.height / 2

        visible: root.settingsShown || settingsSheet.opacity > 0
        opacity: root.settingsShown ? 1 : 0
        penSeen: inkSurface.penSeen
        x: Math.round(Math.max(tray.edge, Math.min(root.width - settingsSheet.width - tray.edge,
            tray.x + tray.width - settingsSheet.width)))
        y: Math.round(settingsSheet.above
            ? Math.max(tray.edge, tray.y - settingsSheet.height - settingsSheet.gap)
            : Math.min(root.height - settingsSheet.height - tray.edge, tray.y + tray.height + settingsSheet.gap))
        transform: Translate {
            y: root.settingsShown ? 0 : (settingsSheet.above ? 16 : -16)
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        onCloseRequested: root.settingsOpen = false
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
    // Elevation by shadow, drawn beside the tray rather than inside it (a child shadow
    // is painted over the tray's own fill). Cached: a static texture, not a per-frame
    // blur.
    StyledRectangularShadow {
        target: tray
        visible: tray.visible && !Config.options.appearance.transparency.enable
    }

    DrawToolbar {
        id: tray

        /// The resting place: centred, clear of the dock, which is where a tray anchored
        /// to the bottom would otherwise land. A drag moves it from there.
        readonly property real restX: (root.width - tray.width) / 2
        readonly property real restY: root.height - root.trayBottomMargin - tray.height
        readonly property real edge: Appearance.sizes.elevationMargin

        x: Math.round(Math.max(tray.edge, Math.min(root.width - tray.width - tray.edge,
            tray.restX + LiveDraw.trayOffsetX)))
        y: Math.round(Math.max(tray.edge, Math.min(root.height - tray.height - tray.edge,
            tray.restY + LiveDraw.trayOffsetY)))
        visible: root.trayShown
        opacity: root.trayShown ? 1 : 0

        palette: LiveDraw.palette
        currentColor: LiveDraw.color
        strokeWidth: LiveDraw.width
        eraser: LiveDraw.eraser
        usePressure: LiveDraw.usePressure
        pressureAvailable: inkSurface.penSeen
        canUndo: LiveDraw.canUndo(root.sheetKey)
        canRedo: LiveDraw.canRedo(root.sheetKey)
        canClear: root.hasInk
        showRedo: true
        statusText: root.statusText
        drawing: LiveDraw.drawing
        showDrawToggle: true
        title: Translation.tr("Draw")
        subtitle: LiveDraw.drawing ? Translation.tr("On screen") : Translation.tr("Clicks go through")
        showSettings: true
        settingsOpen: root.settingsOpen
        showClose: true
        // The words and the thickness digits give way on screens narrower than the
        // full tray (about 1280 px wide).
        dense: root.width < 1440
        onSettingsToggled: root.settingsOpen = !root.settingsOpen
        onCloseRequested: LiveDraw.close()
        onRedoRequested: LiveDraw.redo(root.sheetKey)
        // On a desktop most pointers are a mouse, and a pressure switch that can never be
        // used is a disabled button sitting in every frame of a recording. It appears the
        // first time a pen touches the sheet.
        // In the settings popup now, with the rest of the pen's preferences.
        showPressure: false
        collapsible: root.trayMovable
        collapsed: root.trayMovable && LiveDraw.trayCollapsed

        onCollapseToggled: LiveDraw.trayCollapsed = !LiveDraw.trayCollapsed

        // The grip: the one part of the tray that moves it. A drag anywhere on the tray
        // would fight the width slider for the same gesture.
        leadingContent: [
            Item {
                visible: root.trayMovable
                implicitWidth: Appearance.sizes.minimumTouchTarget * 0.6
                implicitHeight: Appearance.sizes.minimumTouchTarget

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "drag_indicator"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: gripDrag.active ? 1 : 0.7
                }

                HoverHandler {
                    cursorShape: gripDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }

                DragHandler {
                    id: gripDrag
                    target: null
                    acceptedDevices: PointerDevice.AllDevices
                    property point startOffset: Qt.point(0, 0)
                    onActiveChanged: {
                        if (gripDrag.active)
                            gripDrag.startOffset = Qt.point(tray.x - tray.restX, tray.y - tray.restY);
                    }
                    onActiveTranslationChanged: {
                        if (gripDrag.active) {
                            LiveDraw.trayOffsetX = gripDrag.startOffset.x + gripDrag.activeTranslation.x;
                            LiveDraw.trayOffsetY = gripDrag.startOffset.y + gripDrag.activeTranslation.y;
                        }
                    }
                }
            }
        ]

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tray)
        }

        // The state is said in the tray itself, under the word "Draw".
        onDrawToggled: LiveDraw.drawing = !LiveDraw.drawing
        onColorPicked: colorValue => {
            LiveDraw.color = colorValue;
            LiveDraw.eraser = false;
        }
        onWidthPicked: widthValue => {
            LiveDraw.width = widthValue;
            if (Config.ready)
                Config.options.tablet.liveDraw.width = Math.round(widthValue);
        }
        onEraserToggled: LiveDraw.eraser = !LiveDraw.eraser
        onPressureToggled: {
            if (Config.ready)
                Config.options.tablet.liveDraw.pressure = !Config.options.tablet.liveDraw.pressure;
        }
        onUndoRequested: LiveDraw.undo(root.sheetKey)
        onClearRequested: {
            LiveDraw.clear(root.sheetKey);
            root.statusFor(Translation.tr("Screen cleared — Ctrl+Z brings it back."));
        }

        // ── What happens to the drawing ─────────────────────────────────────
        trailingContent: [
            DrawToolButton {
                useDynamicRadius: true
                symbol: "screenshot_monitor"
                enabled: !root.hiddenForCapture
                tooltipText: Translation.tr("Screenshot without the toolbar")
                onTriggered: root.captureScreen()
            },
            DrawToolButton {
                useDynamicRadius: true
                symbol: "note_add"
                enabled: root.hasInk
                emphasised: true
                tooltipText: Translation.tr("Save to Notes")
                shortcut: "Ctrl+S"
                onTriggered: root.saveToNotes()
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
