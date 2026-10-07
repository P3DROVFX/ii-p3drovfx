pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "StrokeGeometry.js" as StrokeGeometry

/**
 * Draw on the screen, over whatever is on it — or on a board over it.
 *
 * One per screen, shared by the families: the tablet's pen tray and the desktop's
 * annotation overlay differ only in what may cover the ink (`coveredByShell`), what takes
 * the pointer away from it for a while (`inputSuspended`), where the tray sits and the
 * layer's namespace. Everything else is this file.
 *
 * What the surface can be, from the bottom up:
 *
 *   board      an opaque page over the screen (light or dark, blank or patterned), with
 *              a drawing of its own
 *   ink        the sheet in front — the workspace's, the screen's, or the board's
 *   spotlight  everything dimmed but a circle around the pointer
 *   zoom       a still of the screen magnified around the pointer
 *   tray       the toolbar, and the menus it opens
 *
 * And what it lets through: everything while the pen is down (or a board, a spotlight or
 * a zoom covers the screen); only the tray while the pen is up; nothing once the tray is
 * closed — the ink stays painted and the applications behave as if it were not there.
 */
PanelWindow {
    id: root

    readonly property string screenName: root.screen?.name ?? ""
    /// The sheet in front: the board's, the screen's, or this monitor's workspace's.
    readonly property string sheetKey: {
        void LiveDraw.revision;
        void root.activeWorkspaceId;
        void root.specialName;
        void LiveDraw.board;
        void LiveDraw.sheetMode;
        return LiveDraw.keyFor(root.screenName);
    }

    readonly property var strokes: {
        void LiveDraw.revision;
        return LiveDraw.strokesFor(root.sheetKey);
    }
    readonly property bool hasInk: root.strokes.length > 0

    /// The tray, the board and the modes belong to the focused monitor only.
    readonly property bool focusedHere: String(Hyprland.focusedMonitor?.name ?? "") === root.screenName

    /// A shell surface covers the screen. Ink floating over an app drawer or an overview
    /// would be ink annotating the wrong thing, so the whole layer goes.
    property bool coveredByShell: false
    /// Another shell tool needs the pointer for a moment (a region selection, say). The
    /// ink stays — it is often exactly what is being captured — but the tray, the board
    /// and the pen step aside so the tool underneath gets its clicks.
    property bool inputSuspended: false
    /// Where the tray rests, above the bottom edge.
    property real trayBottomMargin: Appearance.sizes.minimumTouchTarget * 2.6
    /// Whether the tray can be picked up, moved, docked to an edge and folded down.
    property bool trayMovable: false
    property bool parallaxEnabled: true

    /// Hidden for the length of a capture, so the tray is not in the picture.
    property bool hiddenForCapture: false

    readonly property bool active: LiveDraw.trayOpen && root.focusedHere && !root.coveredByShell
        && !root.hiddenForCapture && !root.inputSuspended
    readonly property bool presenting: root.focusedHere && !root.coveredByShell && !root.inputSuspended
        && (LiveDraw.spotlight || LiveDraw.zoom)
    readonly property bool boardHere: LiveDraw.boardOn && LiveDraw.trayOpen && root.focusedHere
        && !root.coveredByShell && !root.inputSuspended
    readonly property bool trayShown: root.active && !LiveDraw.trayHidden && !root.presenting
    // Not while the sheets are sliding past each other: the ink is translated then, so a
    // stroke would land wherever the animation happened to have put the canvas.
    readonly property bool drawing: root.active && (LiveDraw.drawing || root.boardHere) && !root.sliding
        && !root.presenting
    readonly property bool shown: (root.active || root.hasInk || root.sliding || root.presenting || root.boardHere)
        && !root.coveredByShell

    // ── Sliding between workspaces ──────────────────────────────────────────
    /**
     * The ink travels with the workspace it belongs to, the way the compositor moves the
     * windows: across for `slide`, up and down for `slidevert`, a crossfade for `fade`,
     * and both for `slidefade`. Read from `hyprctl animations` (LiveDraw), never assumed.
     */
    readonly property int activeWorkspaceId: {
        for (const monitor of (Hyprland.monitors?.values ?? [])) {
            if (String(monitor?.name ?? "") === root.screenName)
                return monitor?.activeWorkspace?.id ?? -1;
        }
        return -1;
    }
    /// A special workspace has a sheet of its own, swapped without travelling.
    readonly property string specialName: {
        void HyprlandData.monitors;
        return LiveDraw.specialFor(root.screenName);
    }

    property int lastWorkspaceId: -1
    /// The sheet being left behind, painted only for the length of the transition.
    property var outgoingStrokes: []
    /// +1 when the new workspace is further along, which is the way Hyprland moves.
    property int slideDirection: 1
    /// 0 at the start of the transition, 1 at rest.
    property real slideProgress: 1
    readonly property bool sliding: root.slideProgress < 0.999

    /**
     * How far the ink travels, against the full distance the windows travel. Greater
     * than one, so the sheet swings a little wider than the windows and trails them into
     * place — a plane in front of them, which is where the Overlay layer is.
     */
    readonly property real parallaxFactor: 1.12
    readonly property bool slideVertical: LiveDraw.workspaceSlideAxis === "y"
    readonly property real slideSpan: (root.slideVertical ? root.height : root.width)
        * LiveDraw.workspaceSlideDistance * root.parallaxFactor
    readonly property bool slideMoves: LiveDraw.workspaceSlideAxis === "x" || LiveDraw.workspaceSlideAxis === "y"

    onActiveWorkspaceIdChanged: {
        const from = root.lastWorkspaceId;
        root.lastWorkspaceId = root.activeWorkspaceId;
        if (from < 0 || root.activeWorkspaceId < 0 || from === root.activeWorkspaceId)
            return;
        // Sheets that do not belong to a workspace do not travel with one.
        if (root.specialName.length > 0 || LiveDraw.boardOn || LiveDraw.sheetMode === "screen")
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
        duration: LiveDraw.workspaceSlideMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: LiveDraw.workspaceSlideCurve
        onFinished: root.outgoingStrokes = []
    }

    Component.onCompleted: root.lastWorkspaceId = root.activeWorkspaceId

    // ── Feedback ────────────────────────────────────────────────────────────
    property string statusText: ""

    function statusFor(text) {
        root.statusText = text;
        statusTimer.restart();
    }

    /// Says something that outlives the toolbar: a save, a copy, a capture.
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

    // ── Captures of the screen ──────────────────────────────────────────────
    /**
     * Takes the tray out of the picture, then takes the picture. Two steps because the
     * tray is part of this layer and the capture photographs the composited output. The
     * ink is meant to be in the shot — annotating a screen and then capturing it is the
     * point — so only the tray goes.
     *
     * `mode`: "screenshot" (file and clipboard, the shell's own action) or "copy"
     * (clipboard only).
     */
    property string captureMode: ""

    function captureScreen(mode) {
        root.captureMode = mode === "copy" ? "copy" : "screenshot";
        root.flyout = "";
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
            if (root.captureMode === "copy")
                Quickshell.execDetached(["sh", "-c", 'grim -o "$1" - | wl-copy --type image/png', "sh", root.screenName]);
            else
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
            if (root.captureMode === "copy") {
                root.statusFor(Translation.tr("Screen copied."));
            } else {
                root.statusFor(Translation.tr("Screenshot saved."));
                root.announce(Translation.tr("Screenshot saved"),
                              Translation.tr("In Pictures/Screenshots, and on the clipboard."),
                              "camera-photo");
            }
        }
    }

    // ── The drawing as a file ───────────────────────────────────────────────
    /**
     * Crops the ink out of the screen-sized sheet and does something with it: "notes",
     * "copy" (a transparent PNG on the clipboard) or "png" (a transparent PNG in
     * Pictures/Drawings). SVG needs no rendering and is written straight from the
     * strokes, see `exportSvg`.
     *
     * Cropped because a PNG of 1920×1080 that is almost entirely empty is a picture
     * nobody can read at a glance — what you drew is usually a corner of the screen.
     * Two steps, because a Canvas paints when the scene graph gets round to it: the crop
     * is requested here and grabbed once it has painted.
     */
    readonly property string drawingsDir: `${FileUtils.trimFileProtocol(Directories.pictures)}/Drawings`

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH.mm.ss");
    }

    function renderInk(action) {
        if (!root.hasInk) {
            root.statusFor(Translation.tr("Nothing drawn yet."));
            return;
        }
        const bounds = StrokeGeometry.boundsOf(root.strokes);
        if (!bounds)
            return;
        let dir;
        let path;
        if (action === "notes") {
            path = NotesService.newSketchPath();
            dir = path.substring(0, path.lastIndexOf("/"));
        } else if (action === "copy") {
            dir = Directories.screenshotTemp;
            path = `${dir}/live-draw-${root.stamp()}.png`;
        } else {
            dir = root.drawingsDir;
            path = `${dir}/Drawing_${root.stamp()}.png`;
        }
        cropCanvas.bounds = bounds;
        cropCanvas.sourceStrokes = root.strokes;
        cropCanvas.pendingAction = action;
        cropCanvas.width = Math.max(1, Math.round(bounds.width));
        cropCanvas.height = Math.max(1, Math.round(bounds.height));
        // The folder first: a grab writes a file, it does not make the folders to it.
        dirMaker.then = () => {
            cropCanvas.pendingPath = path;
            cropCanvas.refresh();
        };
        dirMaker.command = ["mkdir", "-p", dir];
        dirMaker.running = true;
        if (action !== "copy")
            root.statusFor(Translation.tr("Saving…"));
    }

    Process {
        id: dirMaker
        property var then: null
        onExited: {
            const next = dirMaker.then;
            dirMaker.then = null;
            if (next)
                next();
        }
    }

    function finishRender(action, written, path) {
        if (!written) {
            root.statusFor(Translation.tr("Could not write the drawing."));
            root.announce(Translation.tr("Could not save the drawing"),
                          Translation.tr("Writing the image failed."), "dialog-error");
            return;
        }
        if (action === "copy") {
            Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", path]);
            root.statusFor(Translation.tr("Drawing copied — paste it anywhere."));
            return;
        }
        if (action === "png") {
            root.statusFor(Translation.tr("Saved to Pictures/Drawings."));
            root.announce(Translation.tr("Drawing saved"), path, "image-x-generic");
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
        root.announce(Translation.tr("Saved to Notes"),
                      Translation.tr("As “%1”.").arg(result.title), "accessories-text-editor");
        // The ink has somewhere permanent to live now, so the sheet goes. Leaving it
        // would mean the next save wrote the same drawing to a second note.
        LiveDraw.clear(root.sheetKey);
        LiveDraw.close();
    }

    /// The strokes as an SVG document, cropped to the ink: vectors, sharp at any size.
    function exportSvg() {
        if (!root.hasInk) {
            root.statusFor(Translation.tr("Nothing drawn yet."));
            return;
        }
        const svg = StrokeGeometry.documentSvg(root.strokes);
        const path = `${root.drawingsDir}/Drawing_${root.stamp()}.svg`;
        dirMaker.then = () => {
            svgFile.path = path;
            svgFile.setText(svg);
            root.statusFor(Translation.tr("Saved to Pictures/Drawings."));
            root.announce(Translation.tr("Drawing saved"), path, "image-svg+xml");
        };
        dirMaker.command = ["mkdir", "-p", root.drawingsDir];
        dirMaker.running = true;
    }

    FileView {
        id: svgFile
        blockLoading: false
        watchChanges: false
        printErrors: false
    }

    // ── Commands from elsewhere (IPC, dock, keyboard) ──────────────────────
    function run(action, argument) {
        switch (action) {
        case "save": root.renderInk("notes"); break;
        case "copy": root.renderInk("copy"); break;
        case "exportPng": root.renderInk("png"); break;
        case "exportSvg": root.exportSvg(); break;
        case "copyScreen": root.captureScreen("copy"); break;
        case "screenshot": root.captureScreen("screenshot"); break;
        case "undo": LiveDraw.undo(root.sheetKey); break;
        case "redo": LiveDraw.redo(root.sheetKey); break;
        case "clear": LiveDraw.clear(root.sheetKey); break;
        default: return false;
        }
        return true;
    }

    Connections {
        target: LiveDraw
        function onCommand(action, argument) {
            if (root.focusedHere)
                root.run(action, argument);
        }
    }

    // Kept for callers of the older counter.
    Connections {
        target: GlobalStates
        function onLiveDrawSaveRequestChanged() {
            if (root.focusedHere)
                root.renderInk("notes");
        }
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
     * The keyboard: grabbed when drawing starts, then let go on demand.
     *
     * Opening live draw takes the keyboard outright for a moment, so Ctrl+Z, the inks on
     * 1–9 and Esc work from the first stroke without a click to focus. Then it drops to
     * on-demand: the layer keeps the focus it has, but focusing a window with a keybind
     * (Super+number, Alt+Tab) hands the keyboard to that window, and typing there works
     * with the pen still down. A click on the sheet or the tray takes it back. Once the
     * pen is up or the tray closed, the layer asks for no keyboard at all.
     */
    readonly property bool wantsKeys: root.visible && (root.drawing || root.presenting || root.flyout.length > 0)
    property bool grabbingKeys: false
    onWantsKeysChanged: {
        if (root.wantsKeys) {
            root.grabbingKeys = true;
            keyGrab.restart();
            keyCatcher.forceActiveFocus();
        }
    }

    Timer {
        id: keyGrab
        interval: 400
        onTriggered: root.grabbingKeys = false
    }

    WlrLayershell.keyboardFocus: !root.wantsKeys ? WlrKeyboardFocus.None
        : (root.grabbingKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)

    /**
     * What the layer accepts: everything while the pen is down or something covers the
     * screen, the tray and its menu while the pen is up, nothing once the tray is closed.
     * Every region is always listed and the intersection flags do the work.
     */
    mask: Region {
        regions: [fullRegion, trayRegion, flyoutRegion]
    }

    Region {
        id: fullRegion
        item: inkSurface
        intersection: root.drawing || root.presenting || root.boardHere ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: trayRegion
        item: tray
        intersection: root.trayShown ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: flyoutRegion
        item: flyoutBox
        intersection: root.flyoutShown ? Intersection.Combine : Intersection.Subtract
    }

    // ── Keyboard ────────────────────────────────────────────────────────────
    property bool shiftHeld: false

    function nudgeWidth(delta) {
        LiveDraw.ensureTools();
        const next = Math.max(1, Math.min(24, Math.round(LiveDraw.width) + delta));
        root.setWidth(next);
        root.statusFor(Translation.tr("Thickness %1 px").arg(next));
    }

    function setWidth(value) {
        LiveDraw.width = value;
        if (Config.ready)
            Config.options.tablet.liveDraw.width = Math.round(value);
    }

    /// 1–9 for the number row's keys by position (evdev KEY_1..KEY_9 are X keycodes
    /// 10..18), 0 for anything else.
    function digitRow(event) {
        const code = event.nativeScanCode;
        return code >= 10 && code <= 18 ? code - 9 : 0;
    }

    function pickTool(name) {
        if (LiveDraw.setTool(name))
            root.flyout = "";
    }

    /**
     * Every shortcut is Ctrl+something (Esc aside). A bare letter is a letter typed into
     * whatever text field has the keyboard — and with the keyboard on demand, that is
     * often a window behind the drawing — so a tool on F or Z typed an F or a Z there
     * instead. Shift is still the snap while a shape is dragged.
     */
    function handleKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        const key = event.key;

        if (key === Qt.Key_Shift) {
            root.shiftHeld = true;
            return false;
        }

        // The modes first: in a zoom or a spotlight only their own keys mean anything.
        if (root.presenting) {
            if (key === Qt.Key_Escape || (ctrl && (key === Qt.Key_F || key === Qt.Key_M))) {
                LiveDraw.setSpotlight(false);
                LiveDraw.setZoom(false);
            } else if (key === Qt.Key_Plus || key === Qt.Key_Equal || key === Qt.Key_BracketRight) {
                presentMode.adjust(1);
            } else if (key === Qt.Key_Minus || key === Qt.Key_BracketLeft) {
                presentMode.adjust(-1);
            } else {
                return false;
            }
            return true;
        }

        if (key === Qt.Key_Escape) {
            if (root.flyout.length > 0)
                root.flyout = "";
            else
                LiveDraw.close();
            return true;
        }
        if (!ctrl)
            return false;

        if (key === Qt.Key_Z && !shift) {
            if (!LiveDraw.undo(root.sheetKey))
                root.statusFor(Translation.tr("Nothing to undo."));
        } else if ((key === Qt.Key_Z && shift) || key === Qt.Key_Y) {
            if (!LiveDraw.redo(root.sheetKey))
                root.statusFor(Translation.tr("Nothing to redo."));
        } else if (key === Qt.Key_S) {
            if (alt)
                root.exportSvg();
            else if (shift)
                root.renderInk("png");
            else
                root.renderInk("notes");
        } else if (key === Qt.Key_C) {
            if (shift)
                root.captureScreen("copy");
            else
                root.renderInk("copy");
        } else if (key === Qt.Key_E) {
            LiveDraw.eraser = !LiveDraw.eraser;
        } else if (key === Qt.Key_P || key === Qt.Key_B) {
            root.pickTool("pen");
        } else if (key === Qt.Key_H) {
            root.pickTool("highlighter");
        } else if (key === Qt.Key_L) {
            root.pickTool("laser");
        } else if (key === Qt.Key_A) {
            root.pickTool("arrow");
        } else if (key === Qt.Key_R) {
            root.pickTool("rect");
        } else if (key === Qt.Key_O) {
            root.pickTool("ellipse");
        } else if (key === Qt.Key_I) {
            root.pickTool("line");
        } else if (key === Qt.Key_W) {
            LiveDraw.setBoard("light");
        } else if (key === Qt.Key_K) {
            LiveDraw.setBoard("dark");
        } else if (key === Qt.Key_F) {
            // The zoom gets the key a left hand reaches without looking: it is the mode
            // used most.
            LiveDraw.setZoom(true);
        } else if (key === Qt.Key_M) {
            LiveDraw.setSpotlight(true);
        } else if (key === Qt.Key_T) {
            if (shift && root.trayMovable)
                LiveDraw.trayCollapsed = !LiveDraw.trayCollapsed;
            else if (!shift)
                LiveDraw.trayHidden = !LiveDraw.trayHidden;
        } else if (key === Qt.Key_D) {
            if (!LiveDraw.boardOn)
                LiveDraw.drawing = !LiveDraw.drawing;
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
        } else {
            return false;
        }
        return true;
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: event => event.accepted = root.handleKey(event)
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Shift)
                root.shiftHeld = false;
        }
    }

    onDrawingChanged: {
        if (root.drawing)
            keyCatcher.forceActiveFocus();
        else
            root.shiftHeld = false;
    }

    // ── The board ───────────────────────────────────────────────────────────
    /**
     * A page over the whole screen, under the ink. The pattern is one small tile repeated
     * by the GPU — a single textured quad, not a grid of items and not a screen-sized
     * canvas.
     */
    Item {
        id: board
        anchors.fill: parent
        visible: root.boardHere

        readonly property bool dark: LiveDraw.board === "dark"
        readonly property color paper: LiveDraw.boardColor

        Rectangle {
            anchors.fill: parent
            color: board.paper
        }

        // One small transparent tile per pattern and tone (assets/images/liveDraw),
        // repeated by the GPU: a single textured quad over the screen.
        Image {
            anchors.fill: parent
            visible: LiveDraw.boardPattern !== "none"
            fillMode: Image.Tile
            smooth: false
            source: !root.boardHere || LiveDraw.boardPattern === "none" ? ""
                : `file://${Directories.assetsPath}/images/liveDraw/${LiveDraw.boardPattern}-${board.dark ? "dark" : "light"}.png`
        }
    }

    // ── The ink ─────────────────────────────────────────────────────────────
    /// The sheet being left behind, painted only for the length of the transition.
    Loader {
        anchors.fill: parent
        active: root.sliding && root.outgoingStrokes.length > 0

        sourceComponent: DrawCanvas {
            strokes: root.outgoingStrokes
            opacity: LiveDraw.workspaceSlideFade ? 1 - root.slideProgress : 1
            transform: Translate {
                x: root.slideMoves && !root.slideVertical ? -root.slideProgress * root.slideSpan * root.slideDirection : 0
                y: root.slideMoves && root.slideVertical ? -root.slideProgress * root.slideSpan * root.slideDirection : 0
            }
        }
    }

    DrawSurface {
        id: inkSurface
        anchors.fill: parent

        opacity: root.sliding && LiveDraw.workspaceSlideFade ? root.slideProgress : 1
        transform: Translate {
            x: root.slideMoves && !root.slideVertical ? (1 - root.slideProgress) * root.slideSpan * root.slideDirection : 0
            y: root.slideMoves && root.slideVertical ? (1 - root.slideProgress) * root.slideSpan * root.slideDirection : 0
        }

        strokes: root.strokes
        drawing: root.drawing
        color: LiveDraw.color
        strokeWidth: LiveDraw.width
        usePressure: LiveDraw.usePressure
        smoothing: LiveDraw.smoothing
        eraser: LiveDraw.eraser
        tool: LiveDraw.tool
        constrain: root.shiftHeld
        nativeCursor: LiveDraw.nativeCursor
        // The tray and its menus float over the sheet; the pen must not take their taps.
        excludeItem: tray
        excludeItems: [flyoutBox]
        mouseSmoothing: LiveDraw.mouseSmoothing

        onStrokeFinished: stroke => LiveDraw.addStroke(root.sheetKey, stroke)
        onEraseRequested: (x, y) => LiveDraw.eraseAt(root.sheetKey, x, y, inkSurface.eraserRadius)
    }

    // ── Spotlight and zoom ──────────────────────────────────────────────────
    /**
     * Both follow the pointer and both resize with the wheel (or + and −). The spotlight
     * is a scrim with a hole in it — one vector shape, rebuilt when the pointer moves.
     * The zoom is a still of the screen, taken the moment it opens (with the ink, without
     * the tray) and magnified about the pointer, so the point under the pointer stays
     * under it and moving the pointer pans.
     */
    Item {
        id: presentMode
        anchors.fill: parent
        visible: root.presenting

        property point pointer: Qt.point(root.width / 2, root.height / 2)
        property real spotRadius: 180
        property real zoomFactor: 2

        function adjust(step) {
            if (LiveDraw.spotlight)
                presentMode.spotRadius = Math.max(60, Math.min(600, presentMode.spotRadius * (step > 0 ? 1.15 : 1 / 1.15)));
            else
                presentMode.zoomFactor = Math.max(1.25, Math.min(8, presentMode.zoomFactor * (step > 0 ? 1.25 : 0.8)));
        }

        HoverHandler {
            id: presentHover
            enabled: root.presenting
            onPointChanged: presentMode.pointer = presentHover.point.position
        }

        WheelHandler {
            enabled: root.presenting
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => presentMode.adjust(event.angleDelta.y > 0 ? 1 : -1)
        }

        // A click ends the mode where the pointer is: the thing shown is now in view.
        TapHandler {
            enabled: root.presenting
            onTapped: {
                LiveDraw.setSpotlight(false);
                LiveDraw.setZoom(false);
            }
        }

        // Zoom: the still, and the scrim's shape over it for the spotlight.
        ScreencopyView {
            id: still
            anchors.fill: parent
            visible: LiveDraw.zoom && root.presenting && still.hasContent && root.zoomReady
            captureSource: LiveDraw.zoom && root.focusedHere ? root.screen : null
            live: false
            transform: Scale {
                origin.x: presentMode.pointer.x
                origin.y: presentMode.pointer.y
                xScale: root.zoomShownFactor
                yScale: root.zoomShownFactor
            }
        }

        Shape {
            anchors.fill: parent
            visible: LiveDraw.spotlight && root.presenting
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: Qt.alpha(Appearance.m3colors.m3scrim, 0.66)
                fillRule: ShapePath.OddEvenFill
                PathSvg {
                    readonly property real r: presentMode.spotRadius
                    readonly property real cx: presentMode.pointer.x
                    readonly property real cy: presentMode.pointer.y
                    path: `M0 0H${root.width}V${root.height}H0Z`
                        + `M${cx - r} ${cy}A${r} ${r} 0 1 0 ${cx + r} ${cy}A${r} ${r} 0 1 0 ${cx - r} ${cy}Z`
                }
            }
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // What the mode is and how to leave it, in the corner it least covers.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.trayBottomMargin
            implicitWidth: hintRow.implicitWidth + 24
            implicitHeight: hintRow.implicitHeight + 12
            radius: Appearance.rounding.full
            color: Appearance.m3colors.m3inverseSurface
            opacity: hintTimer.running ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Row {
                id: hintRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: LiveDraw.spotlight ? "flashlight_on" : "zoom_in"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.m3colors.m3inverseOnSurface
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Scroll to resize · click or Esc to leave")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3inverseOnSurface
                }
            }

            Timer {
                id: hintTimer
                interval: 2400
            }
        }

        onVisibleChanged: if (presentMode.visible) hintTimer.restart()
    }

    /// The zoom's still is taken once the tray has left the screen, then grows in.
    property bool zoomReady: false
    property real zoomShownFactor: root.zoomReady ? presentMode.zoomFactor : 1
    Behavior on zoomShownFactor {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    readonly property bool zoomWanted: LiveDraw.zoom && root.presenting
    onZoomWantedChanged: {
        root.zoomReady = false;
        if (root.zoomWanted)
            zoomCapture.restart();
    }

    Timer {
        id: zoomCapture
        interval: 160
        onTriggered: {
            still.captureFrame();
            root.zoomReady = true;
        }
    }

    // ── The offscreen crop ──────────────────────────────────────────────────
    /**
     * The same ink again, at the size of its own bounding box, offscreen: painting the
     * strokes a second time into a canvas that *is* the crop, every point re-expressed
     * relative to its corner.
     */
    DrawCanvas {
        id: cropCanvas
        property var bounds: null
        property var sourceStrokes: []
        property string pendingPath: ""
        property string pendingAction: ""

        // Moved off the surface rather than hidden: an invisible item is not rendered at
        // all, and this one exists for nothing but its pixels.
        x: -20000
        y: -20000
        immediate: true

        strokes: {
            if (!cropCanvas.bounds)
                return [];
            return (cropCanvas.sourceStrokes ?? []).map(stroke => ({
                tool: stroke.tool,
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

        onCommittedPainted: {
            if (cropCanvas.pendingPath.length === 0)
                return;
            const path = cropCanvas.pendingPath;
            cropCanvas.pendingPath = "";
            cropCanvas.saveCommitted(path);
        }

        onSaved: (ok, path) => root.finishRender(cropCanvas.pendingAction, ok, path)
    }

    // ── The tray ────────────────────────────────────────────────────────────
    /**
     * Where the tray is: centred above the dock, moved by its grip, or docked upright to
     * the left or right edge when dropped there.
     */
    readonly property real edge: Appearance.sizes.elevationMargin
    readonly property real dockSnap: 28
    readonly property string dock: root.trayMovable ? LiveDraw.trayDock : ""

    StyledRectangularShadow {
        target: tray
        visible: tray.visible && !Config.options.appearance.transparency.enable
    }

    DrawToolbar {
        id: tray

        readonly property real restX: (root.width - tray.width) / 2
        readonly property real restY: root.dock.length > 0
            ? (root.height - tray.height) / 2
            : root.height - root.trayBottomMargin - tray.height
        readonly property real edge: root.edge

        vertical: root.dock.length > 0
        // The first level of compaction that fits the screen, measured, not guessed.
        level: {
            if (tray.vertical) {
                const tall = root.height - root.edge * 2;
                return tray.heightAt(0) <= tall ? 0 : 2;
            }
            const room = root.width - root.edge * 2;
            if (tray.widthAt(0) <= room)
                return 0;
            return tray.widthAt(1) <= room ? 1 : 2;
        }

        x: Math.round(root.dock === "left" ? root.edge
            : root.dock === "right" ? root.width - tray.width - root.edge
            : Math.max(root.edge, Math.min(root.width - tray.width - root.edge, tray.restX + LiveDraw.trayOffsetX)))
        y: Math.round(Math.max(root.edge, Math.min(root.height - tray.height - root.edge,
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
        drawing: LiveDraw.drawing || root.boardHere
        showDrawToggle: true
        title: root.boardHere ? Translation.tr("Board") : Translation.tr("Draw")
        subtitle: root.boardHere ? Translation.tr("Page over the screen")
            : LiveDraw.drawing ? Translation.tr("On screen") : Translation.tr("Clicks go through")
        showTools: true
        tool: LiveDraw.tool
        shapeTool: LiveDraw.lastShape
        showPresent: true
        boardOn: LiveDraw.boardOn
        spotlightOn: LiveDraw.spotlight
        zoomOn: LiveDraw.zoom
        showShare: true
        canShare: true
        showSettings: true
        settingsOpen: root.flyout === "settings"
        showClose: true
        // In the settings popup, with the rest of the pen's preferences.
        showPressure: false
        collapsible: root.trayMovable
        collapsed: root.trayMovable && LiveDraw.trayCollapsed

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tray)
        }

        onCollapseToggled: LiveDraw.trayCollapsed = !LiveDraw.trayCollapsed
        onSettingsToggled: anchor => root.toggleFlyout("settings", anchor)
        onShapeMenuRequested: anchor => root.toggleFlyout("shape", anchor)
        onInkMenuRequested: anchor => root.toggleFlyout("ink", anchor)
        onShareRequested: anchor => root.toggleFlyout("share", anchor)
        onCloseRequested: LiveDraw.close()
        onRedoRequested: LiveDraw.redo(root.sheetKey)
        onToolPicked: name => root.pickTool(name)
        onBoardToggled: LiveDraw.setBoard(LiveDraw.boardOn ? "" : "light")
        onSpotlightToggled: LiveDraw.setSpotlight(!LiveDraw.spotlight)
        onZoomToggled: LiveDraw.setZoom(!LiveDraw.zoom)
        // The state is said in the tray itself, under the word "Draw".
        onDrawToggled: {
            if (LiveDraw.boardOn)
                LiveDraw.setBoard("");
            else
                LiveDraw.drawing = !LiveDraw.drawing;
        }
        onColorPicked: colorValue => {
            LiveDraw.color = colorValue;
            LiveDraw.eraser = false;
        }
        onWidthPicked: widthValue => root.setWidth(widthValue)
        onEraserToggled: LiveDraw.eraser = !LiveDraw.eraser
        onUndoRequested: LiveDraw.undo(root.sheetKey)
        onClearRequested: {
            LiveDraw.clear(root.sheetKey);
            root.statusFor(Translation.tr("Screen cleared — Ctrl+Z brings it back."));
        }

        // The grip: the one part of the tray that moves it. A drag anywhere on the tray
        // would fight the width slider for the same gesture. Dropped against the left or
        // right edge, the tray docks there standing up; dragged away, it lies down again.
        leadingContent: [
            Item {
                visible: root.trayMovable
                implicitWidth: tray.vertical ? Appearance.sizes.minimumTouchTarget : Appearance.sizes.minimumTouchTarget * 0.6
                implicitHeight: tray.vertical ? Appearance.sizes.minimumTouchTarget * 0.6 : Appearance.sizes.minimumTouchTarget

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: tray.vertical ? "drag_handle" : "drag_indicator"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: gripDrag.active ? 1 : 0.7
                }

                HoverHandler {
                    id: gripHover
                    cursorShape: gripDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }

                // Hover from the handler: an Item has no `hovered`, and the tooltip
                // reads a missing one as "hovered", forever.
                StyledToolTip {
                    requireOverlay: false
                    extraVisibleCondition: gripHover.hovered && !gripDrag.active
                    text: Translation.tr("Drag to move · drop on a side edge to stand it up")
                }

                DragHandler {
                    id: gripDrag
                    target: null
                    acceptedDevices: PointerDevice.AllDevices
                    property point startOffset: Qt.point(0, 0)
                    property point lastPointer: Qt.point(0, 0)
                    onCentroidChanged: {
                        if (gripDrag.active)
                            gripDrag.lastPointer = gripDrag.centroid.scenePosition;
                    }
                    onActiveChanged: {
                        if (gripDrag.active) {
                            root.flyout = "";
                            gripDrag.startOffset = Qt.point(tray.x - tray.restX, tray.y - tray.restY);
                        } else {
                            root.settleTray(gripDrag.lastPointer);
                        }
                    }
                    onActiveTranslationChanged: {
                        if (!gripDrag.active)
                            return;
                        // Pulled away from the edge it is docked to: lie down under the
                        // pointer and carry on dragging.
                        if (root.dock.length > 0 && Math.abs(gripDrag.activeTranslation.x) > 60) {
                            const pointer = gripDrag.centroid.scenePosition;
                            LiveDraw.trayDock = "";
                            Qt.callLater(() => {
                                const ox = pointer.x - root.width / 2;
                                const oy = pointer.y - tray.height / 2 - tray.restY;
                                LiveDraw.trayOffsetX = ox;
                                LiveDraw.trayOffsetY = oy;
                                gripDrag.startOffset = Qt.point(ox - gripDrag.activeTranslation.x, oy - gripDrag.activeTranslation.y);
                            });
                            return;
                        }
                        if (root.dock.length === 0)
                            LiveDraw.trayOffsetX = gripDrag.startOffset.x + gripDrag.activeTranslation.x;
                        LiveDraw.trayOffsetY = gripDrag.startOffset.y + gripDrag.activeTranslation.y;
                    }
                }
            }
        ]
    }

    /// After a drop: dock to the side edge the pointer let go of it at, keeping its
    /// height. The pointer and not the tray's own edge: a lying tray is most of the
    /// screen wide, so its edge is at the screen's edge half the time.
    function settleTray(pointer) {
        if (!root.trayMovable || root.dock.length > 0)
            return;
        const reach = root.dockSnap + Appearance.sizes.minimumTouchTarget;
        const side = pointer.x <= reach ? "left" : pointer.x >= root.width - reach ? "right" : "";
        if (side.length === 0)
            return;
        const centreY = pointer.y;
        LiveDraw.trayDock = side;
        Qt.callLater(() => LiveDraw.trayOffsetY = centreY - root.height / 2);
    }

    // ── Menus ───────────────────────────────────────────────────────────────
    /**
     * One menu at a time, next to the button that opened it: above or below a lying
     * tray (whichever side has the room), beside a standing one.
     */
    property string flyout: ""
    property Item flyoutAnchor: null
    readonly property bool flyoutShown: root.flyout.length > 0 && root.trayShown && !LiveDraw.trayCollapsed
    onTrayShownChanged: if (!root.trayShown) root.flyout = ""

    function toggleFlyout(kind, anchor) {
        if (root.flyout === kind) {
            root.flyout = "";
            return;
        }
        root.flyoutAnchor = anchor;
        root.flyout = kind;
    }

    Item {
        id: flyoutBox

        readonly property Item content: root.flyout === "settings" ? settingsSheet : menus
        readonly property real gap: 10
        readonly property point anchorCentre: {
            void tray.x;
            void tray.y;
            const a = root.flyoutAnchor;
            if (!a)
                return Qt.point(tray.x + tray.width / 2, tray.y + tray.height / 2);
            return a.mapToItem(root.contentItem, a.width / 2, a.height / 2);
        }
        readonly property bool above: tray.y + tray.height / 2 > root.height / 2

        width: flyoutBox.content.implicitWidth
        height: flyoutBox.content.implicitHeight
        visible: root.flyoutShown || flyoutBox.opacity > 0
        opacity: root.flyoutShown ? 1 : 0

        x: Math.round(tray.vertical
            ? (root.dock === "left" ? tray.x + tray.width + flyoutBox.gap : tray.x - flyoutBox.width - flyoutBox.gap)
            : Math.max(root.edge, Math.min(root.width - flyoutBox.width - root.edge, flyoutBox.anchorCentre.x - flyoutBox.width / 2)))
        y: Math.round(tray.vertical
            ? Math.max(root.edge, Math.min(root.height - flyoutBox.height - root.edge, flyoutBox.anchorCentre.y - flyoutBox.height / 2))
            : (flyoutBox.above ? Math.max(root.edge, tray.y - flyoutBox.height - flyoutBox.gap)
                               : Math.min(root.height - flyoutBox.height - root.edge, tray.y + tray.height + flyoutBox.gap)))

        transform: Translate {
            y: root.flyoutShown || tray.vertical ? 0 : (flyoutBox.above ? 16 : -16)
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledRectangularShadow {
            target: flyoutBox.content
            visible: !Config.options.appearance.transparency.enable
        }

        LiveDrawSettings {
            id: settingsSheet
            visible: root.flyout === "settings"
            penSeen: inkSurface.penSeen
            onCloseRequested: root.flyout = ""
        }

        LiveDrawMenus {
            id: menus
            visible: root.flyout !== "settings" && root.flyout.length > 0
            kind: root.flyout === "settings" ? "" : root.flyout
            palette: LiveDraw.palette
            currentColor: LiveDraw.color
            currentTool: LiveDraw.tool
            hasInk: root.hasInk
            onAction: name => {
                root.flyout = "";
                root.run(name === "save" ? "save" : name, null);
            }
            onToolPicked: name => root.pickTool(name)
            onColorPicked: colorValue => {
                LiveDraw.color = colorValue;
                LiveDraw.eraser = false;
                root.flyout = "";
            }
        }
    }
}
