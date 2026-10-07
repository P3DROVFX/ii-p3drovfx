pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.regionSelector.annotations
import "../../common/draw/StrokeGeometry.js" as StrokeGeometry
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    visible: GlobalStates.regionSelectorOpen && root.preparationDone
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    enum SnipAction {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound,
        AskAI
    }
    enum SelectionMode {
        RectCorners,
        Circle
    }
    enum Phase {
        Select,
        Post
    }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var phase: RegionSelection.Phase.Select
    signal dismiss

    // Inline editor state
    property bool inlineEditorActive: false
    property list<var> annotations: []
    property list<var> undoStack: []
    property list<var> redoStack: []
    // Hides all editor chrome (temp shapes, handles, crop overlay)
    // for one frame before grabToImage() so none of it is baked into the PNG.
    property bool exporting: false
    // Monotonic source for annotation ids and z-order; reset in clearEditor().
    property int annotationCounter: 0
    // "rect", "ellipse", "arrow", "line", "ruler", "circle", "star", "pencil", "highlighter", "eraser", "text", "number", "blur", "gaussblur", "recrop", "none"
    property string currentTool: "none"
    property color currentColor: "#ff3b30"
    property list<color> presetColors: ["#ff3b30", "#ffcc00", "#34c759", "#007aff", "#af52de", "#ffffff", "#000000"]
    property int currentLineWidth: 2
    // Pixelation coarseness for the blur tool, decoupled from line thickness.
    property int blurStrength: Config.options.regionSelector.annotation.blurStrength
    property bool blurStrengthPopupVisible: false
    // Fill toggle for closed shapes (rect/circle/star); number badges & the
    // next badge value; id of the text annotation being edited inline.
    property bool fillEnabled: false
    property int nextBadgeNumber: Config.options.regionSelector.annotation.badgeStartNumber
    property var editingTextId: null
    property real editorRegionX: 0
    property real editorRegionY: 0
    property real editorRegionW: 0
    property real editorRegionH: 0
    // Ratio between the frozen screenshot's native pixels and logical screen
    // coords (== display scale). Derived from the actual captured file so
    // exports stay full-resolution even if HyprlandMonitor.scale is unreliable.
    // Falls back to monitorScale until the probe loads.
    readonly property real captureScale: (captureProbe.implicitWidth > 0 && root.screen.width > 0) ? (captureProbe.implicitWidth / root.screen.width) : (root.monitorScale > 0 ? root.monitorScale : 1)
    Image {
        id: captureProbe
        source: root.inlineEditorActive ? `file://${root.screenshotPath}` : ""
        width: 0
        height: 0
        visible: false
        asynchronous: true
        cache: false
    }
    property bool shapePopupVisible: false
    property bool colorPopupVisible: false
    property bool lineWidthPopupVisible: false
    // Id of the annotation currently selected for editing (move/delete/restyle),
    // and the one under the cursor while hovering in select mode.
    property var selectedId: null
    property var hoveredId: null

    // Picking a drawing tool cancels any active selection.
    onCurrentToolChanged: {
        if (root.currentTool !== "none")
            root.selectedId = null;
    }
    // Toolbar color/width edits retarget the selected annotation (blur and the
    // ruler keep their fixed styling). Each edit is one undo step.
    onCurrentColorChanged: {
        var sel = root.selectedAnnotation();
        if (!sel || sel.type === "blur" || sel.type === "gaussblur" || sel.type === "ruler")
            return;
        root.pushUndo();
        root.restyleSelected("stroke", String(root.currentColor));
        // Keep a filled shape's interior in sync with its outline colour.
        if (sel.style && sel.style.fill)
            root.restyleSelected("fill", String(root.currentColor));
    }
    onCurrentLineWidthChanged: {
        var sel = root.selectedAnnotation();
        if (!sel || sel.type === "blur" || sel.type === "gaussblur" || sel.type === "ruler")
            return;
        root.pushUndo();
        root.restyleSelected("strokeWidth", root.currentLineWidth);
    }
    // Toggling fill retargets a selected closed shape (rect/circle/star).
    onFillEnabledChanged: {
        var sel = root.selectedAnnotation();
        if (!sel || (sel.type !== "rect" && sel.type !== "ellipse" && sel.type !== "circle" && sel.type !== "star"))
            return;
        root.pushUndo();
        root.restyleSelected("fill", root.fillEnabled ? String(root.currentColor) : null);
    }

    /// The thickness steps the toolbar offers, thinnest first.
    readonly property var lineWidthSteps: [2, 4, 8, 14]

    /**
     * Live draw's tool shortcuts, in the screenshot editor: always Ctrl+key, so a
     * letter typed into a text annotation is a letter.
     *   Ctrl+P pencil · Ctrl+H highlighter · Ctrl+A arrow · Ctrl+R rectangle
     *   Ctrl+O ellipse · Ctrl+I line · Ctrl+E eraser · Ctrl+1–9 colour
     *   Ctrl+[ / Ctrl+] thinner / thicker
     */
    function drawShortcut(event) {
        const tools = {};
        tools[Qt.Key_P] = "pencil";
        tools[Qt.Key_H] = "highlighter";
        tools[Qt.Key_A] = "arrow";
        tools[Qt.Key_R] = "rect";
        tools[Qt.Key_O] = "ellipse";
        tools[Qt.Key_I] = "line";
        tools[Qt.Key_E] = "eraser";
        const tool = tools[event.key];
        if (tool) {
            root.currentTool = root.currentTool === tool ? "none" : tool;
            if (tool === "ellipse")
                root.shapePopupVisible = true;
            return true;
        }
        // By position as well as by symbol, for layouts whose number row types
        // something else without Shift (AZERTY).
        const scan = event.nativeScanCode;
        const digit = (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) ? event.key - Qt.Key_1
            : (scan >= 10 && scan <= 18 ? scan - 10 : -1);
        if (digit >= 0) {
            if (digit < root.presetColors.length)
                root.currentColor = root.presetColors[digit];
            return true;
        }
        if (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight) {
            const steps = root.lineWidthSteps;
            let i = steps.indexOf(root.currentLineWidth);
            if (i < 0)
                i = 0;
            i = Math.max(0, Math.min(steps.length - 1, i + (event.key === Qt.Key_BracketRight ? 1 : -1)));
            root.currentLineWidth = steps[i];
            return true;
        }
        return false;
    }

    function pushUndo() {
        var newStack = root.undoStack.slice();
        newStack.push(AnnotationModel.snapshot(root.annotations));
        root.undoStack = newStack;
        root.redoStack = [];
    }

    function undo() {
        if (root.undoStack.length === 0)
            return;
        var newRedo = root.redoStack.slice();
        newRedo.push(AnnotationModel.snapshot(root.annotations));
        root.redoStack = newRedo;
        var newStack = root.undoStack.slice();
        root.annotations = newStack.pop();
        root.undoStack = newStack;
    }

    function redo() {
        if (root.redoStack.length === 0)
            return;
        var newUndo = root.undoStack.slice();
        newUndo.push(AnnotationModel.snapshot(root.annotations));
        root.undoStack = newUndo;
        var newRedo = root.redoStack.slice();
        root.annotations = newRedo.pop();
        root.redoStack = newRedo;
    }

    function selectedAnnotation() {
        if (root.selectedId === null)
            return null;
        for (var i = 0; i < root.annotations.length; i++) {
            if (root.annotations[i].id === root.selectedId)
                return root.annotations[i];
        }
        return null;
    }

    function deleteSelected() {
        if (root.selectedId === null)
            return;
        root.pushUndo();
        var newList = [];
        for (var i = 0; i < root.annotations.length; i++) {
            if (root.annotations[i].id !== root.selectedId)
                newList.push(root.annotations[i]);
        }
        root.annotations = newList;
        root.selectedId = null;
    }

    // Shift the selected annotation's geometry by (dx, dy) in editor-local space.
    // Caller owns the undo bookkeeping (one push per drag, not per motion event).
    function translateSelected(dx, dy) {
        if (root.selectedId === null)
            return;
        var newList = root.annotations.slice();
        for (var i = 0; i < newList.length; i++) {
            if (newList[i].id !== root.selectedId)
                continue;
            newList[i] = AnnotationModel.translate(AnnotationModel.clone(newList[i]), dx, dy);
            break;
        }
        root.annotations = newList;
    }

    // Swap an annotation for a new version of itself (matched by id).
    function replaceAnnotation(ann) {
        var newList = root.annotations.slice();
        for (var i = 0; i < newList.length; i++) {
            if (newList[i].id === ann.id) {
                newList[i] = ann;
                break;
            }
        }
        root.annotations = newList;
    }

    // Annotations live in region-local coords, so when the region's origin
    // moves (drag, resize from the top/left, recrop) they have to shift the
    // other way to stay on the part of the screenshot they were drawn on. The
    // undo/redo snapshots shift too, or undoing would put things back at
    // pre-move positions.
    function shiftScene(dx, dy) {
        if (dx === 0 && dy === 0)
            return;
        var shiftAll = function (anns) {
            return Array.from(anns).map(function (a) {
                return AnnotationModel.translate(AnnotationModel.clone(a), dx, dy);
            });
        };
        if (root.annotations.length > 0)
            root.annotations = shiftAll(root.annotations);
        if (root.undoStack.length > 0)
            root.undoStack = Array.from(root.undoStack).map(shiftAll);
        if (root.redoStack.length > 0)
            root.redoStack = Array.from(root.redoStack).map(shiftAll);
    }

    function restyleSelected(key, value) {
        if (root.selectedId === null)
            return;
        var newList = root.annotations.slice();
        for (var i = 0; i < newList.length; i++) {
            if (newList[i].id !== root.selectedId)
                continue;
            if (newList[i].type === "blur" || newList[i].type === "gaussblur")
                return;
            var ann = AnnotationModel.clone(newList[i]);
            ann.style[key] = value;
            newList[i] = ann;
            break;
        }
        root.annotations = newList;
    }

    // Next badge value derived from the live scene, not a monotonic counter, so
    // undo/redo and deletions renumber correctly (place 1,2,3 → undo 3 → next is 3).
    function nextBadgeValue() {
        var maxN = Config.options.regionSelector.annotation.badgeStartNumber - 1;
        for (var i = 0; i < root.annotations.length; i++) {
            var a = root.annotations[i];
            if (a.type !== "number")
                continue;
            var n = (a.geom?.n ?? a.n ?? 0);
            if (n > maxN)
                maxN = n;
        }
        return maxN + 1;
    }

    // Resize the capture region from a start-rect + flags (which edges move) and
    // a pointer delta. Shared by the corner/edge handles and the edge strips so
    // the min-size + screen clamps stay in one place. Keeps the dotted outline
    // (dragStart*/dragging*) in sync with the region.
    function applyResize(flags, startX, startY, startW, startH, dx, dy) {
        var x1 = startX, y1 = startY, x2 = startX + startW, y2 = startY + startH;
        if (flags.l)
            x1 = Math.min(startX + dx, x2 - 20);
        if (flags.r)
            x2 = Math.max(startX + startW + dx, x1 + 20);
        if (flags.t)
            y1 = Math.min(startY + dy, y2 - 20);
        if (flags.b)
            y2 = Math.max(startY + startH + dy, y1 + 20);
        x1 = Math.max(0, x1);
        y1 = Math.max(0, y1);
        x2 = Math.min(root.screen.width, x2);
        y2 = Math.min(root.screen.height, y2);
        root.shiftScene(root.editorRegionX - x1, root.editorRegionY - y1);
        root.editorRegionX = x1;
        root.editorRegionY = y1;
        root.editorRegionW = x2 - x1;
        root.editorRegionH = y2 - y1;
        root.dragStartX = x1;
        root.dragStartY = y1;
        root.draggingX = x2;
        root.draggingY = y2;
    }

    function editingAnnotation() {
        if (root.editingTextId === null)
            return null;
        for (var i = 0; i < root.annotations.length; i++) {
            if (root.annotations[i].id === root.editingTextId)
                return root.annotations[i];
        }
        return null;
    }

    // Persist the inline text edit back onto its annotation. An empty string
    // drops the annotation entirely. Undo was already pushed when it was placed.
    function commitText(newText, measuredW, measuredH) {
        if (root.editingTextId === null)
            return;
        var id = root.editingTextId;
        var newList = root.annotations.slice();
        for (var i = 0; i < newList.length; i++) {
            if (newList[i].id !== id)
                continue;
            if (String(newText).trim() === "") {
                newList.splice(i, 1);
                if (root.selectedId === id)
                    root.selectedId = null;
                break;
            }
            var ann = AnnotationModel.clone(newList[i]);
            ann.geom.text = newText;
            ann.geom.w = measuredW;
            ann.geom.h = measuredH;
            newList[i] = ann;
            break;
        }
        root.annotations = newList;
        root.editingTextId = null;
        if (editorOverlayLoader.item)
            editorOverlayLoader.item.forceActiveFocus();
    }

    function clearEditor() {
        root.annotations = [];
        root.undoStack = [];
        root.redoStack = [];
        root.annotationCounter = 0;
        root.selectedId = null;
        root.hoveredId = null;
        root.editingTextId = null;
        root.fillEnabled = false;
        root.nextBadgeNumber = Config.options.regionSelector.annotation.badgeStartNumber;
        root.currentTool = "none";
        root.inlineEditorActive = false;
        root.exporting = false;
        root.phase = RegionSelection.Phase.Select;
        root.dragging = false;
        root.dragStartX = 0;
        root.dragStartY = 0;
        root.draggingX = 0;
        root.draggingY = 0;
        root.dragDiffX = 0;
        root.dragDiffY = 0;
        root.points = [];
        root.editorRegionX = 0;
        root.editorRegionY = 0;
        root.editorRegionW = 0;
        root.editorRegionH = 0;
        root.mouseButton = null;
        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    // Grab the annotated selection to a temp PNG at the capture's native
    // resolution (e.g. 2880x1800 on a 1.5x display), hiding editor chrome for
    // the single frame of the grab, then hand the path to cb.
    function grabAnnotated(cb) {
        const target = editorOverlayLoader.item?.grabTarget ?? null;
        if (!target) {
            console.warn("[Region Selector] No editor content to grab.");
            root.exporting = false;
            return;
        }
        const targetW = Math.round(root.editorRegionW * root.captureScale);
        const targetH = Math.round(root.editorRegionH * root.captureScale);
        root.exporting = true;
        // grabToImage returns false when the item can't be rendered; without
        // this, exporting sticks true and hides the toolbar for every later run.
        const started = target.grabToImage(function (result) {
            root.exporting = false;
            // The render is already done at this point; only the synchronous
            // PNG encode below is left, which can run to a second or more at
            // native resolution. Close the overlay now and defer the encode
            // to the next tick so the compositor gets a frame to unmap it in,
            // instead of blocking the GUI thread first and closing late.
            root.dismiss();
            exportEncodeTimer.pendingResult = result;
            exportEncodeTimer.pendingCb = cb;
            exportEncodeTimer.start();
        }, Qt.size(targetW, targetH));
        if (!started) {
            console.warn("[Region Selector] grabToImage failed to start.");
            root.exporting = false;
        }
    }

    Timer {
        id: exportEncodeTimer
        interval: 1
        repeat: false
        property var pendingResult: null
        property var pendingCb: null
        onTriggered: {
            // Qt's own PNG writer (QImage::save) has no adaptive filtering and
            // compresses noticeably worse than magick on photo-like content —
            // worse than the annotations pushing the file over cliphist's
            // undocumented ~5MB store cutoff. Dump the grab as PPM (trivial,
            // uncompressed write) and let magick do the actual PNG encode,
            // matching what the non-annotated crop path already uses.
            const base = "/tmp/quickshell-snip-" + Date.now();
            const ppmPath = base + ".ppm";
            const pngPath = base + ".png";
            const cb = exportEncodeTimer.pendingCb;
            exportEncodeTimer.pendingResult.saveToFile(ppmPath);
            exportEncodeTimer.pendingResult = null;
            exportEncodeTimer.pendingCb = null;
            const esc = StringUtils.shellSingleQuoteEscape;
            exportEncodeProcess.pendingCb = cb;
            exportEncodeProcess.pngPath = pngPath;
            exportEncodeProcess.command = ["bash", "-c", `magick '${esc(ppmPath)}' -strip 'png:${esc(pngPath)}' && rm -f '${esc(ppmPath)}'`];
            exportEncodeProcess.running = true;
        }
    }

    Process {
        id: exportEncodeProcess
        running: false
        property string pngPath: ""
        property var pendingCb: null
        onExited: (exitCode, exitStatus) => {
            const cb = exportEncodeProcess.pendingCb;
            exportEncodeProcess.pendingCb = null;
            if (exitCode !== 0)
                console.warn("[Region Selector] magick re-encode failed, exit code", exitCode);
            cb(exportEncodeProcess.pngPath);
        }
    }

    function defaultSaveDir() {
        return (Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : (Directories.home + "/Pictures/Screenshots")).toString().replace(/^file:\/\//, "");
    }
    function timestampedName() {
        return "screenshot-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_hh.mm.ss") + ".png";
    }

    function finalizeScreenshot(saveToFile) {
        ScreenshotAction.playShutterSound(ScreenshotAction.Action.Copy);
        // No annotations means the composited grab is pixel-identical to a
        // plain crop of the raw capture, so skip the QQuickItem render +
        // synchronous PNG encode (seconds on a full-monitor grab) and go
        // through the same fast native crop the non-editor Copy path uses.
        if (root.annotations.length === 0) {
            const screenshotDir = saveToFile ? root.defaultSaveDir() : "";
            const command = ScreenshotAction.getCommand(root.editorRegionX * root.monitorScale //
            , root.editorRegionY * root.monitorScale //
            , root.editorRegionW * root.monitorScale //
            , root.editorRegionH * root.monitorScale //
            , root.screenshotPath //
            , ScreenshotAction.Action.Copy //
            , screenshotDir);
            Quickshell.execDetached(command);
            if (Config.options.regionSelector.enableOverlay ?? true) {
                GlobalStates.screenshotOverlayMonitor = root.screen?.name ?? ""
                GlobalStates.screenshotOverlayImagePath = root.screenshotPath;
                GlobalStates.screenshotOverlayRegionX = root.editorRegionX * root.monitorScale;
                GlobalStates.screenshotOverlayRegionY = root.editorRegionY * root.monitorScale;
                GlobalStates.screenshotOverlayRegionW = root.editorRegionW * root.monitorScale;
                GlobalStates.screenshotOverlayRegionH = root.editorRegionH * root.monitorScale;
                GlobalStates.screenshotOverlayOpen = true;
            }
            root.dismiss();
            return;
        }
        root.grabAnnotated(function (tempPath) {
            var esc = StringUtils.shellSingleQuoteEscape;
            var overlayEnabled = Config.options.regionSelector.enableOverlay ?? true;
            if (saveToFile) {
                var saveDir = root.defaultSaveDir();
                var fullPath = saveDir + "/" + root.timestampedName();
                Quickshell.execDetached(["bash", "-c", "mkdir -p '" + esc(saveDir) + "' && mv '" + esc(tempPath) + "' '" + esc(fullPath) + "' && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Screenshot saved' 'Saved to: " + esc(fullPath) + "'"]);
            } else {
                var cleanCmd = overlayEnabled ? ":" : "rm '" + esc(tempPath) + "'";
                var copyNotifyCmd = (Config.options.regionSelector.copyNotification ?? false)
                    ? " && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Screenshot copied' 'Copied to clipboard'"
                    : "";
                Quickshell.execDetached(["bash", "-c", "wl-copy < '" + esc(tempPath) + "' && " + cleanCmd + copyNotifyCmd]);
            }
            // Trigger screenshot overlay
            if (overlayEnabled) {
                GlobalStates.screenshotOverlayMonitor = root.screen?.name ?? ""
                GlobalStates.screenshotOverlayImagePath = tempPath;
                GlobalStates.screenshotOverlayRegionX = 0;
                GlobalStates.screenshotOverlayRegionY = 0;
                GlobalStates.screenshotOverlayRegionW = 0;
                GlobalStates.screenshotOverlayRegionH = 0;
                GlobalStates.screenshotOverlayOpen = true;
            }
            root.dismiss();
        });
    }

    // Save As... - grab, then pick a path with a zenity dialog.
    function finalizeScreenshotAs() {
        ScreenshotAction.playShutterSound(ScreenshotAction.Action.Copy);
        root.grabAnnotated(function (tempPath) {
            var esc = StringUtils.shellSingleQuoteEscape;
            var saveDir = root.defaultSaveDir();
            var suggested = saveDir + "/" + root.timestampedName();
            var cmd = "mkdir -p '" + esc(saveDir) + "'; dest=$(zenity --file-selection --save --confirm-overwrite --filename='" + esc(suggested) + "' 2>/dev/null); if [ -n " + '"$dest"' + " ]; then mv '" + esc(tempPath) + "' " + '"$dest"' + " && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Screenshot saved' " + '"Saved to: $dest"' + "; else rm -f '" + esc(tempPath) + "'; fi";
            Quickshell.execDetached(["bash", "-c", cmd]);
            root.dismiss();
        });
    }

    // Extract Text - OCR the grab and copy the recognised text.
    function extractText() {
        root.grabAnnotated(function (tempPath) {
            var esc = StringUtils.shellSingleQuoteEscape;
            var cmd = "langs=$(tesseract --list-langs 2>/dev/null | sed 1d | paste -sd+ -); tesseract '" + esc(tempPath) + "' stdout -l " + '"${langs:-eng}"' + " 2>/dev/null | wl-copy && rm -f '" + esc(tempPath) + "' && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Text extracted' 'Copied to clipboard'";
            Quickshell.execDetached(["bash", "-c", cmd]);
            root.dismiss();
        });
    }

    // Export - open the grab in the default image application.
    function exportOpenWith() {
        root.grabAnnotated(function (tempPath) {
            var esc = StringUtils.shellSingleQuoteEscape;
            Quickshell.execDetached(["bash", "-c", "xdg-open '" + esc(tempPath) + "'"]);
            root.dismiss();
        });
    }

    // Export - reverse image search (upload, then open in the browser).
    function exportSearch() {
        root.grabAnnotated(function (tempPath) {
            var esc = StringUtils.shellSingleQuoteEscape;
            var base = ScreenshotAction.imageSearchEngineBaseUrl;
            var cmd = "url=$(curl -sF files[]=@'" + esc(tempPath) + "' https://uguu.se/upload | jq -r '.files[0].url'); [ -n " + '"$url"' + " ] && xdg-open '" + esc(base) + "'" + '"$url"' + "; rm -f '" + esc(tempPath) + "'";
            Quickshell.execDetached(["bash", "-c", cmd]);
            root.dismiss();
        });
    }

    // Export - save to disk and copy the file path to the clipboard.
    function exportCopyPath() {
        root.grabAnnotated(function (tempPath) {
            var esc = StringUtils.shellSingleQuoteEscape;
            var saveDir = root.defaultSaveDir();
            var fullPath = saveDir + "/" + root.timestampedName();
            Quickshell.execDetached(["bash", "-c", "mkdir -p '" + esc(saveDir) + "' && mv '" + esc(tempPath) + "' '" + esc(fullPath) + "' && printf %s '" + esc(fullPath) + "' | wl-copy && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Path copied' '" + esc(fullPath) + "'"]);
            root.dismiss();
        });
    }

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.4)
    property color brightText: Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0
    property color brightSecondary: Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary
    property color brightTertiary: Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary)
    property color selectionBorderColor: ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: "#ff000000"
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    // Vars for indicators
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating)
            return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor.scale
    readonly property real monitorOffsetX: hyprlandMonitor.x
    readonly property real monitorOffsetY: hyprlandMonitor.y
    property int activeWorkspaceId: hyprlandMonitor.activeWorkspace?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}.ppm`
    property bool captureReady: false
    property int captureToken: 0
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    // Windows on the active workspace, plus the special workspace when one is
    // shown on top of it.
    readonly property int specialWorkspaceId: root.hyprlandMonitor.lastIpcObject?.specialWorkspace?.id ?? 0
    readonly property list<var> windowRegions: RegionFunctions.filterWindowRegionsByLayers(root.windows.filter(w => w.workspace.id === root.activeWorkspaceId || (root.specialWorkspaceId !== 0 && w.workspace.id === root.specialWorkspaceId)).map(window => {
        return {
            at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
            size: [window.size[0], window.size[1]],
            class: window.class,
            title: window.title,
            special: window.workspace.id === root.specialWorkspaceId
        };
    }), root.layerRegions).sort((a, b) => {
        // Special-workspace windows sit above the regular ones (stable sort
        // keeps floating-before-tiled inside each group).
        return (b.special ? 1 : 0) - (a.special ? 1 : 0);
    })
    // Shell layers that are not a target by themselves: helpers, input
    // catchers, the selector itself, and chrome that spans the whole edge.
    readonly property var ignoredLayerNamespaces: ["quickshell", "quickshell:bar", "quickshell:verticalBar", "quickshell:dock", "quickshell:regionSelector", "quickshell:screenCorners", "quickshell:screenshotOverlay", "quickshell:policiesDismissCatcher", "quickshell:pinReserver", "quickshell:idleDim", "quickshell:oledSaver", "quickshell:workspaceBlurOverlay", "quickshell:gestureFeedback", "quickshell:overviewWindowTransition", "quickshell:tiling_stack_badges", "quickshell:tiling_assistant", "quickshell:editMode", "quickshell:topLayer", "quickshell:sleepShade"]
    function layerLabel(namespace) {
        const name = String(namespace).replace(/^quickshell:/, "");
        return name.length > 0 ? name.charAt(0).toUpperCase() + name.slice(1) : name;
    }
    readonly property list<var> layerRegions: {
        const levels = root.layers[root.hyprlandMonitor.name]?.levels;
        if (!levels)
            return [];
        const screenArea = root.screen.width * root.screen.height;
        // Real layer geometry is only meaningful for surfaces sized to their
        // content; full-screen shell surfaces report their card through
        // ShellRegions instead.
        const sized = [...(levels["2"] ?? []), ...(levels["3"] ?? [])].filter(layer => {
            if (root.ignoredLayerNamespaces.includes(layer.namespace))
                return false;
            if (layer.w < 24 || layer.h < 24)
                return false;
            return layer.w * layer.h < screenArea * 0.85;
        }).map(layer => {
            return {
                at: [layer.x - root.monitorOffsetX, layer.y - root.monitorOffsetY],
                size: [layer.w, layer.h],
                namespace: root.layerLabel(layer.namespace)
            };
        });
        const shell = ShellRegions.frozen.filter(region => region.screen === root.screen.name).map(region => {
            // Clip to the monitor; a card can hang off an edge mid-animation.
            const x1 = Math.max(0, region.at[0] - root.monitorOffsetX);
            const y1 = Math.max(0, region.at[1] - root.monitorOffsetY);
            const x2 = Math.min(root.screen.width, region.at[0] - root.monitorOffsetX + region.size[0]);
            const y2 = Math.min(root.screen.height, region.at[1] - root.monitorOffsetY + region.size[1]);
            return {
                at: [x1, y1],
                size: [x2 - x1, y2 - y1],
                namespace: region.label
            };
        }).filter(region => region.size[0] >= 8 && region.size[1] >= 8);
        // Smallest first, so a card nested in a bigger surface wins the hover.
        return [...shell, ...sized].sort((a, b) => a.size[0] * a.size[1] - b.size[0] * b.size[1]);
    }

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0);
    }
    // regionX/Y/Width/Height are bindings over dragStart/dragging. Assigning
    // those computed properties breaks the bindings, with a sticky-loaded
    // overlay that freeze is the next session's "stuck" previous region.
    function setRegion(x, y, w, h) {
        root.dragStartX = x;
        root.dragStartY = y;
        root.draggingX = x + w;
        root.draggingY = y + h;
    }
    function setRegionToTargeted() {
        const padding = Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
        root.setRegion(root.targetedRegionX - padding, root.targetedRegionY - padding, root.targetedRegionWidth + padding * 2, root.targetedRegionHeight + padding * 2);
    }

    function updateTargetedRegion(x, y) {
        // Image regions
        const clickedRegion = root.imageRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        // Layer regions
        const clickedLayer = root.layerRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedLayer) {
            root.targetedRegionX = clickedLayer.at[0];
            root.targetedRegionY = clickedLayer.at[1];
            root.targetedRegionWidth = clickedLayer.size[0];
            root.targetedRegionHeight = clickedLayer.size[1];
            return;
        }

        // Window regions
        const clickedWindow = root.windowRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)

    // Screenshot is taken by the parent Scope as soon as screenshot mode is
    // requested, in parallel with creating this overlay. We only map once the
    // freeze-frame file is ready so the overlay is never baked into the capture.
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    property bool preparationDone: false

    function tryFinishPreparation() {
        if (root.captureToken <= 0 || !root.captureReady)
            return;
        if (root.isRecording && checkRecordingProc.running)
            return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            root.dismiss();
            return;
        }
        if (root.enableContentRegions) {
            imageDetectionProcess.running = false;
            imageDetectionProcess.running = true;
        }
        // Load synchronously before mapping so the first painted frame already
        // has the frozen screen; an async load could flash an empty window.
        // Cache-bust because screenshotPath is reused across activations.
        freezeFrame.source = `file://${root.screenshotPath}`;
        root.preparationDone = true;
    }

    onCaptureReadyChanged: root.tryFinishPreparation()

    onCaptureTokenChanged: {
        freezeFrame.source = "";
        root.preparationDone = false;
        root.recordingShouldStop = false;
        root.imageRegions = [];
        imageDetectionProcess.running = false;
        root.clearEditor();
        if (root.isRecording) {
            checkRecordingProc.running = false;
            checkRecordingProc.running = true;
        }
        root.tryFinishPreparation();
    }

    Process {
        id: checkRecordingProc
        running: false
        command: ["bash", "-c", "pidof wf-recorder > /dev/null 2>&1 || (pgrep -x obs > /dev/null 2>&1 && python3 '" + Directories.scriptPath + "/videos/obs_control.py' status 2>/dev/null | grep -q active)"]
        onExited: (exitCode, exitStatus) => {
            root.recordingShouldStop = (exitCode === 0);
            root.tryFinishPreparation();
        }
    }

    Component.onCompleted: {
        if (root.isRecording)
            checkRecordingProc.running = true;
        root.tryFinishPreparation();
    }

    onVisibleChanged: {
        if (!root.visible) {
            root.clearEditor();
        }
    }

    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen)
                return;
            root.preparationDone = false;
            freezeFrame.source = "";
            root.imageRegions = [];
            imageDetectionProcess.running = false;
            root.clearEditor();
        }
    }

    Process {
        id: imageDetectionProcess
        command: ["bash", "-c", `${Directories.scriptPath}/images/find-regions-venv.sh ` + `--hyprctl ` + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' ` + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} ` + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                imageRegions = RegionFunctions.filterImageRegions(JSON.parse(imageDimensionCollector.text), root.windowRegions);
            }
        }
    }

    function actionToScreenshotAction(snipAction) {
        switch (snipAction) {
        case RegionSelection.SnipAction.Copy:
            return ScreenshotAction.Action.Copy;
        case RegionSelection.SnipAction.Edit:
            return ScreenshotAction.Action.Edit;
        case RegionSelection.SnipAction.Search:
            return ScreenshotAction.Action.Search;
        case RegionSelection.SnipAction.CharRecognition:
            return ScreenshotAction.Action.CharRecognition;
        case RegionSelection.SnipAction.Record:
            return ScreenshotAction.Action.Record;
        case RegionSelection.SnipAction.RecordWithSound:
            return ScreenshotAction.Action.RecordWithSound;
        case RegionSelection.SnipAction.AskAI:
            return ScreenshotAction.Action.AskAI;
        default:
            console.warn("[Region Selector] Unknown snip action, skipping snip.");
            root.dismiss();
            return;
        }
    }

    // Execution after selection
    function getScreenshotAction() {
        return root.actionToScreenshotAction(root.action);
    }

    function snip() {
        var rx = root.regionX;
        var ry = root.regionY;
        var rw = root.regionWidth;
        var rh = root.regionHeight;
        if (rw <= 0 || rh <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
            return;
        }

        rx = Math.max(0, Math.min(rx, root.screen.width - rw));
        ry = Math.max(0, Math.min(ry, root.screen.height - rh));
        rw = Math.max(0, Math.min(rw, root.screen.width - rx));
        rh = Math.max(0, Math.min(rh, root.screen.height - ry));

        var snipAction = root.action;
        if (snipAction === RegionSelection.SnipAction.Copy || snipAction === RegionSelection.SnipAction.Edit) {
            snipAction = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        }
        // Right-dragging a search turns it into a question for the assistant.
        // It does not work the other way round: a selection started from the
        // chat was asked for by name, and turning it into an image search sent
        // the shot somewhere the composer never sees.
        if (snipAction === RegionSelection.SnipAction.Search && root.mouseButton === Qt.RightButton) {
            snipAction = RegionSelection.SnipAction.AskAI;
        }

        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //
        Config.options.screenSnip.savePath : "";
        var screenshotAction = root.actionToScreenshotAction(snipAction);
        // The assistant is handed a file of its own rather than the clipboard:
        // see ScreenshotAction.getCommand.
        const askingAi = snipAction === RegionSelection.SnipAction.AskAI;
        const aiPath = askingAi ? `${Directories.cliphistDecode}/ai-snip-${Date.now()}.png` : "";
        const isRecording = snipAction === RegionSelection.SnipAction.Record || snipAction === RegionSelection.SnipAction.RecordWithSound;
        const recordGeometry = isRecording ? {
            // The selector is local to this monitor; wf-recorder matches
            // regions against xdg-output's global logical coordinates.
            x: rx + root.monitorOffsetX,
            y: ry + root.monitorOffsetY,
            width: rw,
            height: rh
        } : null;
        const command = ScreenshotAction.getCommand(rx * root.monitorScale //
        , ry * root.monitorScale //
        , rw * root.monitorScale//
        , rh * root.monitorScale //
        , root.screenshotPath //
        , screenshotAction //
        , screenshotDir //
        , aiPath
        , recordGeometry);
        Quickshell.execDetached(command);
        ScreenshotAction.playShutterSound(screenshotAction);
        if (askingAi) {
            Ai.attachSnip(aiPath);
            Ai.surfaceRouter.open({
                "surface": "sidebar",
                "monitorName": root.screen?.name ?? "",
                "focusIntent": "composer",
                "attachmentPath": aiPath
            });
        }
        // Trigger screenshot overlay
        if (!isRecording && (Config.options.regionSelector.enableOverlay ?? true)) {
            GlobalStates.screenshotOverlayMonitor = root.screen?.name ?? ""
            GlobalStates.screenshotOverlayImagePath = root.screenshotPath;
            GlobalStates.screenshotOverlayRegionX = rx * root.monitorScale;
            GlobalStates.screenshotOverlayRegionY = ry * root.monitorScale;
            GlobalStates.screenshotOverlayRegionW = rw * root.monitorScale;
            GlobalStates.screenshotOverlayRegionH = rh * root.monitorScale;
            GlobalStates.screenshotOverlayOpen = true;
        }
        root.dismiss();
    }

    // Dont use anything like stdout here, this is being called detached
    Process {
        id: snipProc
    }

    // Freeze frame. Sourced from the grim capture that TempScreenshotProcess
    // already wrote while this window was still unmapped, NOT from a live
    // ScreencopyView: a screencopy issued here would only be taken once the
    // window renders, which races the compositor's first commit of this very
    // overlay and, on a cold shell, bakes the dim layer and the cursor guide
    // into the "frozen" screen.
    // cache: false because screenshotPath is a constant path reused on every
    // activation, so a cached pixmap would serve the previous frame.
    Image {
        id: freezeFrame
        anchors.fill: parent
        fillMode: Image.Stretch
        cache: false
        asynchronous: false

        focus: root.visible && !root.inlineEditorActive
        Keys.onPressed: event => { // Esc to close
            if (event.key === Qt.Key_Escape) {
                root.dismiss();
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.dismiss()
    }

    Shortcut {
        sequence: "Ctrl+Z"
        onActivated: root.undo()
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: root.inlineEditorActive ? Qt.ArrowCursor : Qt.CrossCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        enabled: !root.inlineEditorActive

        // Controls
        onPressed: mouse => {
            root.dragStartX = mouse.x;
            root.dragStartY = mouse.y;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragging = true;
            root.mouseButton = mouse.button;
        }
        onReleased: mouse => {
            // Detect if it was a click -> Try to select targeted region
            if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                } else {
                    // No window/layer/image under the cursor (e.g. empty workspace) —
                    // fall back to the whole monitor instead of silently no-op'ing.
                    root.setRegion(0, 0, root.screen.width, root.screen.height);
                }
            } else
            // Circle dragging?
            if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                const dragPoints = (root.points.length > 0) ? root.points : [
                    {
                        x: mouseArea.mouseX,
                        y: mouseArea.mouseY
                    }
                ];
                const maxX = Math.max(...dragPoints.map(p => p.x));
                const minX = Math.min(...dragPoints.map(p => p.x));
                const maxY = Math.max(...dragPoints.map(p => p.y));
                const minY = Math.min(...dragPoints.map(p => p.y));
                root.setRegion(minX - padding, minY - padding, maxX - minX + padding * 2, maxY - minY + padding * 2);
            }
            // Inline editor intercept (right-click only, when editor enabled)
            if (root.mouseButton === Qt.RightButton && Config.options.regionSelector.annotation.enableInlineEditor && root.selectionMode !== RegionSelection.SelectionMode.Circle && root.regionWidth > 0 && root.regionHeight > 0) {
                root.editorRegionX = root.regionX;
                root.editorRegionY = root.regionY;
                root.editorRegionW = root.regionWidth;
                root.editorRegionH = root.regionHeight;
                root.inlineEditorActive = true;
                root.dragging = false;
                return;
            }
            root.snip();
        }
        onPositionChanged: mouse => {
            root.updateTargetedRegion(mouse.x, mouse.y);
            if (!root.dragging)
                return;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragDiffX = mouse.x - root.dragStartX;
            root.dragDiffY = mouse.y - root.dragStartY;
            root.points.push({
                x: mouse.x,
                y: mouse.y
            });
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
            sourceComponent: RectCornersSelectionDetails {
                regionX: root.regionX
                regionY: root.regionY
                regionWidth: root.regionWidth
                regionHeight: root.regionHeight
                mouseX: root.inlineEditorActive ? (root.editorRegionX + root.editorRegionW) : mouseArea.mouseX
                mouseY: root.inlineEditorActive ? (root.editorRegionY + root.editorRegionH) : mouseArea.mouseY
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                breathingBorderOnly: root.phase === RegionSelection.Phase.Post
                showDimensions: !root.inlineEditorActive
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        // The thing to the bottom-right with an icon
        CursorGuide {
            z: 9999
            visible: root.phase === RegionSelection.Phase.Select && !root.inlineEditorActive
            x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
            y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
            action: root.action
            selectionMode: root.selectionMode
        }

        // Window regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions) {
                        return root.windowRegions;
                    } else {
                        return [];
                    }
                }
            }
            delegate: TargetRegion {
                z: 2
                required property var modelData
                clientDimensions: modelData
                showIcon: true
                targeted: !root.draggedAway && //
                (root.targetedRegionX === modelData.at[0]  //
                    && root.targetedRegionY === modelData.at[1] //
                    && root.targetedRegionWidth === modelData.size[0] //
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.class}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Layer regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableLayerRegions) {
                        return root.layerRegions;
                    } else {
                        return [];
                    }
                }
            }
            delegate: TargetRegion {
                z: 3
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway && (root.targetedRegionX === modelData.at[0] && root.targetedRegionY === modelData.at[1] && root.targetedRegionWidth === modelData.size[0] && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.namespace}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Content regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions) {
                        return root.imageRegions;
                    } else {
                        return [];
                    }
                }
            }
            delegate: TargetRegion {
                z: 4
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway && (root.targetedRegionX === modelData.at[0] && root.targetedRegionY === modelData.at[1] && root.targetedRegionWidth === modelData.size[0] && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                borderColor: root.imageBorderColor
                fillColor: targeted ? root.imageFillColor : "transparent"
                text: Translation.tr("Content region")
            }
        }

        // Controls
        Row {
            id: regionSelectionControls
            z: 10
            width: implicitWidth
            height: implicitHeight
            visible: root.phase === RegionSelection.Phase.Select && !root.inlineEditorActive
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: -height
            }
            opacity: 0
            Connections {
                target: root
                function onVisibleChanged() {
                    if (!visible)
                        return;
                    regionSelectionControls.anchors.bottomMargin = 8;
                    regionSelectionControls.opacity = 1;
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on anchors.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            spacing: 6

            OptionsToolbar {
                Synchronizer on action {
                    property alias source: root.action
                }
                Synchronizer on selectionMode {
                    property alias source: root.selectionMode
                }
                onDismiss: root.dismiss()
            }
            ToolbarPairedFab {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "close"
                onClicked: root.dismiss()
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }
    }

    // Inline editor overlay — instantiated only when the user enters annotate
    // mode so screenshot-open isn't paying for canvases, handles, and toolbars.
    Loader {
        id: editorOverlayLoader
        z: 10
        anchors.fill: parent
        active: root.inlineEditorActive
        onLoaded: {
            if (item)
                item.forceActiveFocus();
        }
        sourceComponent: editorOverlayComponent
    }

    Component {
        id: editorOverlayComponent
        Item {
            id: editorOverlay
            anchors.fill: parent
            focus: true
            // editorContent is scoped to this Component, so grabAnnotated() on
            // the outer root can only reach it through the Loader's item.
            readonly property Item grabTarget: editorContent

            readonly property bool editorToolbarAtBottom: {
                var tbHeight = (editorToolbarRow && editorToolbarRow.height > 0) ? editorToolbarRow.height : 50;
                var topClearance = root.editorRegionY;
                var bottomClearance = root.screen.height - (root.editorRegionY + root.editorRegionH);
                return (topClearance < tbHeight + 32) && (bottomClearance > topClearance);
            }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.dismiss();
            } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Z) {
                root.redo();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Y) {
                root.redo();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
                root.undo();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                root.finalizeScreenshot(false);
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && root.editingTextId === null && root.drawShortcut(event)) {
                event.accepted = true;
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                root.deleteSelected();
                event.accepted = true;
            }
        }

        // Darken everything outside the selected region
        Rectangle {
            anchors.fill: parent
            color: "#00000000"
            // No darken needed; the freeze frame still shows the frozen screen
        }

        // Selected region with screenshot
        Item {
            id: editorContent
            x: root.editorRegionX
            y: root.editorRegionY
            width: root.editorRegionW
            height: root.editorRegionH
            clip: true
            visible: root.inlineEditorActive && root.editorRegionW > 0 && root.editorRegionH > 0

            Image {
                id: editorImage
                source: root.inlineEditorActive ? `file://${root.screenshotPath}` : ""
                width: root.screen.width
                height: root.screen.height
                x: -root.editorRegionX
                y: -root.editorRegionY
                cache: false
            }

            Component {
                id: rectAnnotationComp
                RectAnnotationComponent {}
            }
            Component {
                id: ellipseAnnotationComp
                EllipseAnnotationComponent {}
            }
            Component {
                id: arrowAnnotationComp
                ArrowAnnotationComponent {}
            }
            Component {
                id: circleAnnotationComp
                CircleAnnotationComponent {}
            }
            Component {
                id: starAnnotationComp
                StarAnnotationComponent {}
            }
            Component {
                id: pencilAnnotationComp
                PencilAnnotationComponent {}
            }
            Component {
                id: lineAnnotationComp
                LineAnnotationComponent {}
            }
            Component {
                id: rulerAnnotationComp
                RulerAnnotationComponent {
                    captureScale: root.captureScale
                }
            }
            Component {
                id: textAnnotationComp
                TextAnnotationComponent {}
            }
            Component {
                id: numberAnnotationComp
                NumberBadgeAnnotationComponent {}
            }

            // Existing annotations
            Repeater {
                model: root.annotations
                delegate: Loader {
                    required property var modelData
                    // Highlighter under every other mark, as on live draw: a pass of
                    // marker over an arrow must not cover the arrow.
                    z: modelData.type === "highlighter" ? 0 : 0.5
                    sourceComponent: {
                        switch (modelData.type) {
                        case "rect":
                            return rectAnnotationComp;
                        case "ellipse":
                            return ellipseAnnotationComp;
                        case "arrow":
                            return arrowAnnotationComp;
                        case "circle":
                            return circleAnnotationComp;
                        case "star":
                            return starAnnotationComp;
                        case "pencil":
                        case "highlighter":
                            return pencilAnnotationComp;
                        case "line":
                            return lineAnnotationComp;
                        case "ruler":
                            return rulerAnnotationComp;
                        case "text":
                            return textAnnotationComp;
                        case "number":
                            return numberAnnotationComp;
                        default:
                            return null;
                        }
                    }
                    onLoaded: {
                        if (!item)
                            return;
                        item.annData = modelData;
                        if (modelData.type === "pencil" || modelData.type === "highlighter") {
                            item.canvasWidth = editorContent.width;
                            item.canvasHeight = editorContent.height;
                        }
                    }
                }
            }

            // --- Pixelation / Blur Implementation ---
            // Pixelation coarseness is driven by the dedicated blur-strength
            // control (independent of line thickness): a bigger divisor = fewer
            // source pixels sampled = chunkier blocks.
            Canvas {
                id: smallCanvas
                readonly property int blurDivisor: Math.max(4, root.blurStrength)
                width: Math.max(1, Math.round(editorContent.width / blurDivisor))
                height: Math.max(1, Math.round(editorContent.height / blurDivisor))
                visible: false
                onWidthChanged: blurCanvas.requestPaint()
                onHeightChanged: blurCanvas.requestPaint()
            }

            // Isolated scratch buffer. source-in clobbers whatever is already
            // on a canvas, so the pixelate and blur groups are each rendered
            // here in turn and then drawn back over the visible blur canvas.
            Canvas {
                id: blurGroupCanvas
                anchors.fill: parent
                visible: false
            }

            Canvas {
                id: blurCanvas
                anchors.fill: parent
                z: 1
                visible: root.inlineEditorActive

                // Rasterise one group's masking strokes, keep the processed
                // image only under them (source-in), then composite the result
                // over the visible canvas. smooth=false -> blocky pixelation;
                // smooth=true -> soft blur (bilinear upscale of the same
                // downscaled screenshot).
                function paintMaskedGroup(anns, smooth) {
                    if (!anns || anns.length === 0)
                        return;
                    var gctx = blurGroupCanvas.getContext("2d");
                    gctx.clearRect(0, 0, width, height);
                    gctx.save();
                    gctx.lineCap = "round";
                    gctx.lineJoin = "round";
                    for (var j = 0; j < anns.length; j++) {
                        var ann = anns[j];
                        var pts = (ann.geom ?? ann).points;
                        if (!pts || pts.length === 0)
                            continue;
                        gctx.lineWidth = (ann.style ?? ann).strokeWidth ?? ann.lineWidth;
                        gctx.strokeStyle = "rgba(0,0,0,1.0)";
                        gctx.fillStyle = "rgba(0,0,0,1.0)";
                        gctx.beginPath();
                        gctx.moveTo(pts[0].x, pts[0].y);
                        for (var k = 1; k < pts.length - 2; k++) {
                            var xc = (pts[k].x + pts[k + 1].x) / 2;
                            var yc = (pts[k].y + pts[k + 1].y) / 2;
                            gctx.quadraticCurveTo(pts[k].x, pts[k].y, xc, yc);
                        }
                        if (pts.length > 2) {
                            gctx.quadraticCurveTo(pts[pts.length - 2].x, pts[pts.length - 2].y, pts[pts.length - 1].x, pts[pts.length - 1].y);
                        } else if (pts.length === 2) {
                            gctx.lineTo(pts[1].x, pts[1].y);
                        } else if (pts.length === 1) {
                            gctx.arc(pts[0].x, pts[0].y, ((ann.style ?? ann).strokeWidth ?? ann.lineWidth) / 2, 0, 2 * Math.PI);
                            gctx.fill();
                            continue;
                        }
                        gctx.stroke();
                    }
                    gctx.globalCompositeOperation = "source-in";
                    gctx.imageSmoothingEnabled = smooth;
                    gctx.drawImage(smallCanvas, 0, 0, smallCanvas.width, smallCanvas.height, 0, 0, width, height);
                    gctx.restore();
                    getContext("2d").drawImage(blurGroupCanvas, 0, 0);
                }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    // Pixelation only. The blur is a real Gaussian blur (gaussBlur
                    // below): upscaling the same downscaled image with smoothing on was
                    // supposed to blur, but a Canvas ignores the hint and the result was
                    // a second pixelation.
                    var pixelateAnns = [];
                    for (var i = 0; i < root.annotations.length; i++) {
                        if (root.annotations[i].type === "blur")
                            pixelateAnns.push(root.annotations[i]);
                    }
                    var temp = drawingArea.tempAnnotation;
                    if (temp && temp.type === "blur")
                        pixelateAnns.push(temp);

                    if (pixelateAnns.length === 0)
                        return;

                    // Downscaled screenshot region, shared by both groups.
                    var smallCtx = smallCanvas.getContext("2d");
                    smallCtx.clearRect(0, 0, smallCanvas.width, smallCanvas.height);
                    smallCtx.drawImage(editorImage, root.editorRegionX, root.editorRegionY, width, height, 0, 0, smallCanvas.width, smallCanvas.height);

                    paintMaskedGroup(pixelateAnns, false);
                }
                Connections {
                    target: root
                    function onAnnotationsChanged() {
                        blurCanvas.requestPaint();
                    }
                }
                Connections {
                    target: drawingArea
                    function onTempAnnotationChanged() {
                        blurCanvas.requestPaint();
                    }
                }
                Connections {
                    target: editorImage
                    function onStatusChanged() {
                        if (editorImage.status === Image.Ready) {
                            blurCanvas.requestPaint();
                        }
                    }
                }
            }
            // --- Gaussian blur ---
            // The screenshot blurred for real (MultiEffect, on the GPU) and shown only
            // under the blur strokes, which are drawn white into a mask. A binary mask
            // is exactly what MultiEffect's thresholded mask is good at. Built only
            // while there is a blur stroke; the strength chips set the radius.
            readonly property var gaussAnns: {
                var list = [];
                for (var i = 0; i < root.annotations.length; i++) {
                    if (root.annotations[i].type === "gaussblur")
                        list.push(root.annotations[i]);
                }
                var temp = drawingArea.tempAnnotation;
                if (temp && temp.type === "gaussblur")
                    list.push(temp);
                return list;
            }

            Loader {
                id: gaussBlur
                anchors.fill: parent
                z: 1
                active: root.inlineEditorActive && editorContent.gaussAnns.length > 0

                sourceComponent: Item {
                    // Sampled with a margin of the screenshot all round: a blur reads
                    // the pixels around each one, and at the region's edge those would
                    // otherwise be transparent, darkening the blur where it meets it.
                    readonly property real pad: 64

                    // The mask: every blur stroke, white, in editor coordinates.
                    Item {
                        id: blurMask
                        x: -parent.pad
                        y: -parent.pad
                        width: editorContent.width + parent.pad * 2
                        height: editorContent.height + parent.pad * 2
                        layer.enabled: true
                        visible: false

                        Item {
                            x: blurMask.parent.pad
                            y: blurMask.parent.pad
                            width: editorContent.width
                            height: editorContent.height

                            Repeater {
                                model: editorContent.gaussAnns
                                delegate: PencilAnnotationComponent {
                                    required property var modelData
                                    annData: modelData
                                    canvasWidth: editorContent.width
                                    canvasHeight: editorContent.height
                                }
                            }
                        }
                    }

                    // The part of the screenshot the editor shows, and the margin.
                    ShaderEffectSource {
                        id: regionSource
                        width: blurMask.width
                        height: blurMask.height
                        sourceItem: editorImage
                        sourceRect: Qt.rect(root.editorRegionX - parent.pad, root.editorRegionY - parent.pad,
                                            blurMask.width, blurMask.height)
                        visible: false
                    }

                    MultiEffect {
                        x: blurMask.x
                        y: blurMask.y
                        width: blurMask.width
                        height: blurMask.height
                        source: regionSource
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 64
                        // 12 / 24 / 48 on the strength chips: soft, medium, heavy.
                        blurMultiplier: Math.max(0.25, root.blurStrength / 24)
                        autoPaddingEnabled: false
                        maskEnabled: true
                        maskSource: blurMask
                    }
                }
            }

            // ----------------------------------------

            // Drawing area
            MouseArea {
                id: drawingArea
                anchors.fill: parent
                // Disabled while editing text so canvas clicks don't place a
                // second text box (the commit catcher handles those clicks).
                enabled: root.currentTool !== "none" && root.currentTool !== "recrop" && root.editingTextId === null
                cursorShape: {
                    if (root.currentTool === "text")
                        return Qt.IBeamCursor;
                    if (root.currentTool === "pencil" || root.currentTool === "blur" || root.currentTool === "gaussblur" || root.currentTool === "highlighter" || root.currentTool === "eraser")
                        return Qt.CrossCursor;
                    return Qt.ArrowCursor;
                }
                property real startX: 0
                property real startY: 0
                property var tempAnnotation: null

                // ── Live draw's pen engine (pencil and highlighter) ─────────────
                // Pressure from a stylus (the handler below), an exponential filter
                // and thinning on every sample, and for a mouse, touchpad or finger the
                // lazy brush: the line hangs on a short string behind the pointer so a
                // shaky hand never reaches it. Same numbers as live draw.
                property var smoothPoint: null
                property var brush: null
                property var lastRaw: null
                property bool steadied: false
                property bool erasedAny: false
                readonly property real stringLength: LiveDraw.mouseSmoothing * 18
                readonly property real eraserRadius: Math.max(10, root.currentLineWidth * 3)

                function pressure() {
                    return stylus.active ? stylus.point.pressure : 1;
                }

                function freehandTool(tool) {
                    return tool === "pencil" || tool === "highlighter";
                }

                // Feeds one sample into the stroke being drawn; false when it was too
                // close to the last one to keep.
                function appendSmoothed(sample) {
                    smoothPoint = StrokeGeometry.smoothed(smoothPoint, sample, LiveDraw.smoothing);
                    var pts = tempAnnotation.geom.points;
                    if (!StrokeGeometry.shouldAppend(pts[pts.length - 1], smoothPoint))
                        return false;
                    var next = pts.slice();
                    next.push({ "x": smoothPoint.x, "y": smoothPoint.y, "p": smoothPoint.p });
                    tempAnnotation = AnnotationModel.make(tempAnnotation.type, tempAnnotation.id, tempAnnotation.z, {
                        "points": next
                    }, tempAnnotation.style);
                    return true;
                }

                function eraseAt(x, y) {
                    var kept = [];
                    var hit = false;
                    var list = Array.from(root.annotations);
                    for (var i = 0; i < list.length; i++) {
                        if (AnnotationModel.hitBy(list[i], x, y, eraserRadius))
                            hit = true;
                        else
                            kept.push(list[i]);
                    }
                    if (!hit)
                        return;
                    // One undo step for the whole rub, taken at the first thing it hit.
                    if (!erasedAny)
                        root.pushUndo();
                    erasedAny = true;
                    root.annotations = kept;
                }

                // The end of a shape drag, snapped while Shift is held.
                function shapeEnd(mouse) {
                    if (!(mouse.modifiers & Qt.ShiftModifier))
                        return { "x": mouse.x, "y": mouse.y };
                    return AnnotationModel.constrained(root.currentTool, startX, startY, mouse.x, mouse.y);
                }

                /// A stylus, for its pressure. Passive: the strokes still come in through
                /// this MouseArea (Qt synthesises mouse events from the tablet's), the
                /// handler only answers how hard the pen is pressed.
                PointHandler {
                    id: stylus
                    acceptedDevices: PointerDevice.Stylus
                    enabled: drawingArea.freehandTool(root.currentTool)
                }

                onPressed: mouse => {
                    startX = mouse.x;
                    startY = mouse.y;
                    if (root.currentTool === "eraser") {
                        erasedAny = false;
                        eraseAt(mouse.x, mouse.y);
                        tempAnnotation = null;
                        return;
                    }
                    root.pushUndo();
                    var id = "a" + root.annotationCounter;
                    var z = root.annotationCounter;
                    root.annotationCounter += 1;
                    var style = AnnotationModel.defaultStyle(root.currentColor, root.currentLineWidth);
                    if (root.fillEnabled)
                        style.fill = String(root.currentColor);
                    if (root.currentTool === "text") {
                        // Place an empty text box and enter inline edit mode.
                        var tann = AnnotationModel.make("text", id, z, {
                            "x": startX,
                            "y": startY,
                            "w": 0,
                            "h": 0,
                            "text": ""
                        }, style);
                        var tl = root.annotations.slice();
                        tl.push(tann);
                        root.annotations = tl;
                        root.selectedId = id;
                        root.editingTextId = id;
                        tempAnnotation = null;
                        return;
                    } else if (root.currentTool === "number") {
                        // Number badges are placed on click, not dragged.
                        var badgeR = 14 + root.currentLineWidth * 2;
                        var badge = AnnotationModel.make("number", id, z, {
                            "x": startX,
                            "y": startY,
                            "r": badgeR,
                            "n": root.nextBadgeValue()
                        }, style);
                        var bl = root.annotations.slice();
                        bl.push(badge);
                        root.annotations = bl;
                        tempAnnotation = null;
                        return;
                    }
                    if (freehandTool(root.currentTool)) {
                        var first = StrokeGeometry.point(startX, startY, drawingArea.pressure());
                        smoothPoint = first;
                        brush = first;
                        lastRaw = first;
                        steadied = !stylus.active && stringLength > 0.5;
                    }
                    if (root.currentTool === "rect" || root.currentTool === "ellipse") {
                        tempAnnotation = AnnotationModel.make(root.currentTool, id, z, {
                            "x": startX,
                            "y": startY,
                            "w": 0,
                            "h": 0
                        }, style);
                    } else if (root.currentTool === "arrow") {
                        tempAnnotation = AnnotationModel.make("arrow", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": startX,
                            "y2": startY
                        }, style);
                    } else if (root.currentTool === "line") {
                        tempAnnotation = AnnotationModel.make("line", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": startX,
                            "y2": startY
                        }, style);
                    } else if (root.currentTool === "ruler") {
                        tempAnnotation = AnnotationModel.make("ruler", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": startX,
                            "y2": startY
                        }, style);
                    } else if (root.currentTool === "highlighter") {
                        var hlStyle = AnnotationModel.defaultStyle(root.currentColor, root.currentLineWidth * 4);
                        hlStyle.opacity = Config.options.regionSelector.annotation.highlighterOpacity;
                        tempAnnotation = AnnotationModel.make("highlighter", id, z, {
                            "points": [
                                {
                                    "x": startX,
                                    "y": startY,
                                    "p": 1
                                }
                            ]
                        }, hlStyle);
                    } else if (root.currentTool === "circle") {
                        tempAnnotation = AnnotationModel.make("circle", id, z, {
                            "x": startX,
                            "y": startY,
                            "r": 0
                        }, style);
                    } else if (root.currentTool === "star") {
                        tempAnnotation = AnnotationModel.make("star", id, z, {
                            "x": startX,
                            "y": startY,
                            "outerR": 0,
                            "innerR": 0
                        }, style);
                    } else if (root.currentTool === "pencil") {
                        // Pressure shapes the line only for a pen, and only when live
                        // draw's pressure setting is on — the same preference.
                        style.usePressure = stylus.active && LiveDraw.usePressure;
                        tempAnnotation = AnnotationModel.make("pencil", id, z, {
                            "points": [
                                {
                                    "x": startX,
                                    "y": startY,
                                    "p": drawingArea.pressure()
                                }
                            ]
                        }, style);
                    } else if (root.currentTool === "blur" || root.currentTool === "gaussblur") {
                        var blurStyle = AnnotationModel.defaultStyle("#ffffff", root.currentLineWidth * 10);
                        tempAnnotation = AnnotationModel.make(root.currentTool, id, z, {
                            "points": [
                                {
                                    "x": startX,
                                    "y": startY
                                }
                            ]
                        }, blurStyle);
                    }
                }
                onPositionChanged: mouse => {
                    if (root.currentTool === "eraser") {
                        if (pressed)
                            eraseAt(mouse.x, mouse.y);
                        return;
                    }
                    if (!tempAnnotation)
                        return;
                    var id = tempAnnotation.id;
                    var z = tempAnnotation.z;
                    var style = tempAnnotation.style;
                    var end = shapeEnd(mouse);
                    if (root.currentTool === "rect" || root.currentTool === "ellipse") {
                        tempAnnotation = AnnotationModel.make(root.currentTool, id, z, {
                            "x": Math.min(startX, end.x),
                            "y": Math.min(startY, end.y),
                            "w": Math.abs(end.x - startX),
                            "h": Math.abs(end.y - startY)
                        }, style);
                    } else if (root.currentTool === "arrow") {
                        tempAnnotation = AnnotationModel.make("arrow", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": end.x,
                            "y2": end.y
                        }, style);
                    } else if (root.currentTool === "line") {
                        tempAnnotation = AnnotationModel.make("line", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": end.x,
                            "y2": end.y
                        }, style);
                    } else if (root.currentTool === "ruler") {
                        tempAnnotation = AnnotationModel.make("ruler", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": end.x,
                            "y2": end.y
                        }, style);
                    } else if (root.currentTool === "circle") {
                        var dx = mouse.x - startX;
                        var dy = mouse.y - startY;
                        var radius = Math.sqrt(dx * dx + dy * dy);
                        tempAnnotation = AnnotationModel.make("circle", id, z, {
                            "x": startX,
                            "y": startY,
                            "r": radius
                        }, style);
                    } else if (root.currentTool === "star") {
                        var dxs = mouse.x - startX;
                        var dys = mouse.y - startY;
                        var outerRadius = Math.sqrt(dxs * dxs + dys * dys);
                        var innerRadius = outerRadius * 0.4;
                        tempAnnotation = AnnotationModel.make("star", id, z, {
                            "x": startX,
                            "y": startY,
                            "outerR": outerRadius,
                            "innerR": innerRadius
                        }, style);
                    } else if (freehandTool(root.currentTool)) {
                        var raw = StrokeGeometry.point(mouse.x, mouse.y, drawingArea.pressure());
                        lastRaw = raw;
                        var sample = raw;
                        if (steadied) {
                            sample = StrokeGeometry.pulled(brush, raw, stringLength);
                            if (!sample)
                                return;
                            brush = sample;
                        }
                        appendSmoothed(sample);
                    } else if (root.currentTool === "blur" || root.currentTool === "gaussblur") {
                        var pts = tempAnnotation.geom.points;
                        var lastPoint = pts[pts.length - 1];
                        var dxP = mouse.x - lastPoint.x;
                        var dyP = mouse.y - lastPoint.y;
                        if (dxP * dxP + dyP * dyP < 16)
                            return;
                        var newPoints = pts.slice();
                        newPoints.push({
                            "x": mouse.x,
                            "y": mouse.y
                        });
                        tempAnnotation = AnnotationModel.make(tempAnnotation.type, id, z, {
                            "points": newPoints
                        }, style);
                    }
                }
                onReleased: mouse => {
                    if (root.currentTool === "eraser") {
                        erasedAny = false;
                        return;
                    }
                    if (!tempAnnotation)
                        return;
                    // The lazy brush's slack is taken up: the line ends where the
                    // pointer let go.
                    if (freehandTool(tempAnnotation.type) && steadied && lastRaw) {
                        for (var step of [0.5, 1])
                            appendSmoothed(StrokeGeometry.point(brush.x + (lastRaw.x - brush.x) * step,
                                                                brush.y + (lastRaw.y - brush.y) * step, lastRaw.p));
                    }
                    var g = tempAnnotation.geom;
                    if (root.currentTool === "rect" || root.currentTool === "ellipse") {
                        if (g.w < 2 || g.h < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "arrow" || root.currentTool === "line" || root.currentTool === "ruler") {
                        if (Math.abs(g.x2 - g.x1) < 2 && Math.abs(g.y2 - g.y1) < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "circle") {
                        if (g.r < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "star") {
                        if (g.outerR < 5) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "blur" || root.currentTool === "gaussblur") {
                        if (g.points.length < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    }
                    var newList = root.annotations.slice();
                    newList.push(AnnotationModel.clone(tempAnnotation));
                    root.annotations = newList;
                    // Don't auto-select the freshly drawn shape; the user picks
                    // the Select tool explicitly to edit it.
                    root.selectedId = null;
                    tempAnnotation = null;
                }

                // Temp annotation while drawing
                RectAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "rect" ? drawingArea.tempAnnotation : null
                }
                EllipseAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "ellipse" ? drawingArea.tempAnnotation : null
                }

                ArrowAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "arrow" ? drawingArea.tempAnnotation : null
                }
                LineAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "line" ? drawingArea.tempAnnotation : null
                }
                RulerAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "ruler" ? drawingArea.tempAnnotation : null
                    captureScale: root.captureScale
                }
                CircleAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "circle" ? drawingArea.tempAnnotation : null
                }
                StarAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "star" ? drawingArea.tempAnnotation : null
                }
                PencilAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "pencil" ? drawingArea.tempAnnotation : null
                    canvasWidth: editorContent.width
                    canvasHeight: editorContent.height
                }
                PencilAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "highlighter" ? drawingArea.tempAnnotation : null
                    canvasWidth: editorContent.width
                    canvasHeight: editorContent.height
                }
            }

            // Select / move mode (active when no drawing tool is chosen).
            // Pressing on an annotation selects and drags it; pressing empty
            // canvas deselects and moves the whole capture region instead.
            MouseArea {
                id: moveArea
                anchors.fill: parent
                enabled: root.currentTool === "none"
                hoverEnabled: true
                cursorShape: {
                    if (!enabled)
                        return Qt.ArrowCursor;
                    if (movingAnnotation)
                        return Qt.ClosedHandCursor;
                    if (root.hoveredId !== null)
                        return Qt.OpenHandCursor;
                    return Qt.SizeAllCursor;
                }
                property real startMouseX: 0
                property real startMouseY: 0
                property real lastX: 0
                property real lastY: 0
                property bool movingAnnotation: false
                property bool movedThisDrag: false

                onPressed: mouse => {
                    var hit = AnnotationModel.annotationAt(root.annotations, mouse.x, mouse.y, 6);
                    if (hit) {
                        root.selectedId = hit.id;
                        movingAnnotation = true;
                        movedThisDrag = false;
                        lastX = mouse.x;
                        lastY = mouse.y;
                        return;
                    }
                    root.selectedId = null;
                    movingAnnotation = false;
                    startMouseX = mouse.x;
                    startMouseY = mouse.y;
                }

                onReleased: {
                    movingAnnotation = false;
                }

                onPositionChanged: mouse => {
                    if (!pressed) {
                        var h = AnnotationModel.annotationAt(root.annotations, mouse.x, mouse.y, 6);
                        root.hoveredId = h ? h.id : null;
                        return;
                    }

                    // Moving the selected annotation
                    if (movingAnnotation) {
                        if (!movedThisDrag) {
                            root.pushUndo();
                            movedThisDrag = true;
                        }
                        root.translateSelected(mouse.x - lastX, mouse.y - lastY);
                        lastX = mouse.x;
                        lastY = mouse.y;
                        return;
                    }

                    // Moving the whole capture region
                    var deltaX = mouse.x - startMouseX;
                    var deltaY = mouse.y - startMouseY;

                    var newX = root.editorRegionX + deltaX;
                    var newY = root.editorRegionY + deltaY;

                    newX = Math.max(0, Math.min(newX, root.screen.width - root.editorRegionW));
                    newY = Math.max(0, Math.min(newY, root.screen.height - root.editorRegionH));

                    root.shiftScene(root.editorRegionX - newX, root.editorRegionY - newY);
                    root.editorRegionX = newX;
                    root.editorRegionY = newY;

                    root.dragStartX = newX;
                    root.dragStartY = newY;
                    root.draggingX = newX + root.editorRegionW;
                    root.draggingY = newY + root.editorRegionH;
                }
            }

            // Catches clicks outside the text box to commit the current edit.
            MouseArea {
                z: 7
                anchors.fill: parent
                enabled: root.editingTextId !== null
                onPressed: root.commitText(textEditor.text, textEditor.contentWidth, textEditor.contentHeight)
            }

            // Inline text editor. Reuses one TextInput for whichever text
            // annotation is being edited; keeps focus so keystrokes don't leak
            // to the editorOverlay shortcuts (Esc/Delete/Ctrl+Z).
            TextInput {
                id: textEditor
                z: 8
                readonly property var ann: root.editingAnnotation()
                visible: root.editingTextId !== null && ann !== null
                x: ann ? (ann.geom?.x ?? 0) : 0
                y: ann ? (ann.geom?.y ?? 0) : 0
                color: ann ? (ann.style?.stroke ?? "#ff3b30") : "#ff3b30"
                font.pixelSize: ann ? (ann.style?.fontPx ?? 20) : 20
                selectByMouse: true
                cursorVisible: true

                onAccepted: root.commitText(text, contentWidth, contentHeight)
                onActiveFocusChanged: {
                    if (!activeFocus && root.editingTextId !== null)
                        root.commitText(text, contentWidth, contentHeight);
                }
                Keys.onPressed: event => {
                    // Swallow Esc so it commits the text instead of dismissing
                    // the whole selector.
                    if (event.key === Qt.Key_Escape) {
                        root.commitText(text, contentWidth, contentHeight);
                        event.accepted = true;
                    }
                }
                Connections {
                    target: root
                    function onEditingTextIdChanged() {
                        if (root.editingTextId === null)
                            return;
                        var a = root.editingAnnotation();
                        textEditor.text = a ? (a.geom?.text ?? "") : "";
                        textEditor.forceActiveFocus();
                        textEditor.selectAll();
                    }
                }
            }
        }

        // 8-handle region resize: 4 corners + 4 edge midpoints. Each grip's
        // (ax, ay) is its normalised anchor on the region box; l/t/r/b say which
        // edges it moves. Hidden during export and inline text editing.
        Repeater {
            model: [
                {
                    "ax": 0,
                    "ay": 0,
                    "cur": Qt.SizeFDiagCursor,
                    "l": true,
                    "t": true,
                    "r": false,
                    "b": false
                },
                {
                    "ax": 0.5,
                    "ay": 0,
                    "cur": Qt.SizeVerCursor,
                    "l": false,
                    "t": true,
                    "r": false,
                    "b": false
                },
                {
                    "ax": 1,
                    "ay": 0,
                    "cur": Qt.SizeBDiagCursor,
                    "l": false,
                    "t": true,
                    "r": true,
                    "b": false
                },
                {
                    "ax": 1,
                    "ay": 0.5,
                    "cur": Qt.SizeHorCursor,
                    "l": false,
                    "t": false,
                    "r": true,
                    "b": false
                },
                {
                    "ax": 1,
                    "ay": 1,
                    "cur": Qt.SizeFDiagCursor,
                    "l": false,
                    "t": false,
                    "r": true,
                    "b": true
                },
                {
                    "ax": 0.5,
                    "ay": 1,
                    "cur": Qt.SizeVerCursor,
                    "l": false,
                    "t": false,
                    "r": false,
                    "b": true
                },
                {
                    "ax": 0,
                    "ay": 1,
                    "cur": Qt.SizeBDiagCursor,
                    "l": true,
                    "t": false,
                    "r": false,
                    "b": true
                },
                {
                    "ax": 0,
                    "ay": 0.5,
                    "cur": Qt.SizeHorCursor,
                    "l": true,
                    "t": false,
                    "r": false,
                    "b": false
                }
            ]

            delegate: Item {
                required property var modelData

                readonly property int hitSize: 30
                // The dashed selection border is drawn 6px outside the true
                // region (borderWidth 1 + 5, see RectCornersSelectionDetails);
                // centre the grips on that visible line, not the raw edge.
                readonly property real outset: 6
                z: 9999
                visible: !root.exporting && root.editingTextId === null && root.currentTool !== "recrop"
                width: hitSize
                height: hitSize
                x: (root.editorRegionX - outset) + (root.editorRegionW + outset * 2) * modelData.ax - width / 2
                y: (root.editorRegionY - outset) + (root.editorRegionH + outset * 2) * modelData.ay - height / 2

                // Crop-style grips: corners are thick L brackets hugging the
                // selection, edge midpoints a short bar along the edge. A soft
                // dark halo under each keeps them readable on light captures.
                id: regionGrip
                readonly property bool corner: modelData.ax !== 0.5 && modelData.ay !== 0.5
                readonly property bool horizontalEdge: modelData.ax === 0.5
                readonly property int thickness: 5
                readonly property int arm: 22
                readonly property int bar: 30
                // Arms point into the selection.
                readonly property int dirX: modelData.ax === 0 ? 1 : -1
                readonly property int dirY: modelData.ay === 0 ? 1 : -1
                readonly property real c: hitSize / 2
                readonly property real armRadius: Appearance.rounding.scale === 0 ? 0 : thickness / 2

                Repeater {
                    // [halo spread, colour]: the halo pass first, the grip on top.
                    model: [[1.5, Qt.rgba(0, 0, 0, 0.28)], [0, Appearance.colors.colPrimary]]

                    delegate: Item {
                        id: gripLayer
                        required property var modelData
                        readonly property real s: modelData[0]
                        anchors.fill: parent

                        // Corner: horizontal arm
                        Rectangle {
                            visible: regionGrip.corner
                            width: regionGrip.arm + gripLayer.s * 2
                            height: regionGrip.thickness + gripLayer.s * 2
                            radius: regionGrip.armRadius + gripLayer.s
                            color: gripLayer.modelData[1]
                            x: (regionGrip.dirX > 0 ? regionGrip.c - regionGrip.thickness / 2 : regionGrip.c + regionGrip.thickness / 2 - regionGrip.arm) - gripLayer.s
                            y: regionGrip.c - regionGrip.thickness / 2 - gripLayer.s
                        }
                        // Corner: vertical arm
                        Rectangle {
                            visible: regionGrip.corner
                            width: regionGrip.thickness + gripLayer.s * 2
                            height: regionGrip.arm + gripLayer.s * 2
                            radius: regionGrip.armRadius + gripLayer.s
                            color: gripLayer.modelData[1]
                            x: regionGrip.c - regionGrip.thickness / 2 - gripLayer.s
                            y: (regionGrip.dirY > 0 ? regionGrip.c - regionGrip.thickness / 2 : regionGrip.c + regionGrip.thickness / 2 - regionGrip.arm) - gripLayer.s
                        }
                        // Edge midpoint bar
                        Rectangle {
                            visible: !regionGrip.corner
                            width: (regionGrip.horizontalEdge ? regionGrip.bar : regionGrip.thickness) + gripLayer.s * 2
                            height: (regionGrip.horizontalEdge ? regionGrip.thickness : regionGrip.bar) + gripLayer.s * 2
                            radius: regionGrip.armRadius + gripLayer.s
                            color: gripLayer.modelData[1]
                            x: regionGrip.c - width / 2
                            y: regionGrip.c - height / 2
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: modelData.cur
                    preventStealing: true

                    property real startPx: 0
                    property real startPy: 0
                    property real startX: 0
                    property real startY: 0
                    property real startW: 0
                    property real startH: 0

                    onPressed: mouse => {
                        var p = mapToItem(editorOverlay, mouse.x, mouse.y);
                        startPx = p.x;
                        startPy = p.y;
                        startX = root.editorRegionX;
                        startY = root.editorRegionY;
                        startW = root.editorRegionW;
                        startH = root.editorRegionH;
                    }

                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        var p = mapToItem(editorOverlay, mouse.x, mouse.y);
                        root.applyResize(modelData, startX, startY, startW, startH, p.x - startPx, p.y - startPy);
                    }
                }
            }
        }

        // Full-length edge grips: let you drag any whole edge, not just the
        // midpoint handle (Spectacle behaviour). Sit just below the corner
        // handles in z so corners win their overlap; inset from the corners so
        // the two don't fight.
        Repeater {
            model: [
                {
                    "side": "t",
                    "cur": Qt.SizeVerCursor,
                    "l": false,
                    "t": true,
                    "r": false,
                    "b": false
                },
                {
                    "side": "b",
                    "cur": Qt.SizeVerCursor,
                    "l": false,
                    "t": false,
                    "r": false,
                    "b": true
                },
                {
                    "side": "l",
                    "cur": Qt.SizeHorCursor,
                    "l": true,
                    "t": false,
                    "r": false,
                    "b": false
                },
                {
                    "side": "r",
                    "cur": Qt.SizeHorCursor,
                    "l": false,
                    "t": false,
                    "r": true,
                    "b": false
                }
            ]

            delegate: MouseArea {
                required property var modelData

                readonly property real outset: 6
                readonly property int thickness: 14
                readonly property bool horizontal: modelData.side === "t" || modelData.side === "b"
                z: 9998
                visible: !root.exporting && root.editingTextId === null && root.currentTool !== "recrop"
                cursorShape: modelData.cur
                preventStealing: true
                x: {
                    if (modelData.side === "l")
                        return root.editorRegionX - outset - thickness / 2;
                    if (modelData.side === "r")
                        return root.editorRegionX + root.editorRegionW + outset - thickness / 2;
                    return root.editorRegionX + 16;
                }
                y: {
                    if (modelData.side === "t")
                        return root.editorRegionY - outset - thickness / 2;
                    if (modelData.side === "b")
                        return root.editorRegionY + root.editorRegionH + outset - thickness / 2;
                    return root.editorRegionY + 16;
                }
                width: horizontal ? Math.max(1, root.editorRegionW - 32) : thickness
                height: horizontal ? thickness : Math.max(1, root.editorRegionH - 32)

                property real startPx: 0
                property real startPy: 0
                property real startX: 0
                property real startY: 0
                property real startW: 0
                property real startH: 0

                onPressed: mouse => {
                    var p = mapToItem(editorOverlay, mouse.x, mouse.y);
                    startPx = p.x;
                    startPy = p.y;
                    startX = root.editorRegionX;
                    startY = root.editorRegionY;
                    startW = root.editorRegionW;
                    startH = root.editorRegionH;
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    var p = mapToItem(editorOverlay, mouse.x, mouse.y);
                    root.applyResize(modelData, startX, startY, startW, startH, p.x - startPx, p.y - startPy);
                }
            }
        }

        // Selection outline, delete chip and resize grips for the selected
        // annotation. Kept outside editorContent so they aren't clipped when
        // an annotation touches the region edge and never reach grabToImage.
        // Same z as the region grips but declared later, so an annotation
        // grip wins where the two overlap.
        Item {
            id: selectionOverlay
            z: 9999
            readonly property var sel: root.selectedAnnotation()
            readonly property var bb: sel ? AnnotationModel.boundingBox(sel) : null
            readonly property real pad: (sel && sel.style ? (sel.style.strokeWidth ?? 2) : 2) / 2 + 4
            visible: sel !== null && !root.exporting
            x: root.editorRegionX + (bb ? bb.x - pad : 0)
            y: root.editorRegionY + (bb ? bb.y - pad : 0)
            width: bb ? bb.w + pad * 2 : 0
            height: bb ? bb.h + pad * 2 : 0

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: 4
                border.width: 1.5
                border.color: Appearance.colors.colPrimary
            }

            // Sits just off the top-right corner so it clears that grip.
            // Destructive, so it speaks in the error voice; hovering squares it
            // off before the click lands.
            Rectangle {
                id: deleteChip
                width: 28
                height: 28
                radius: Appearance.rounding.scale === 0 ? 0 : (deleteHover.hovered ? 9 : width / 2)
                color: deleteHover.hovered ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer
                anchors.left: parent.right
                anchors.bottom: parent.top
                anchors.leftMargin: 4
                anchors.bottomMargin: 4

                Behavior on radius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: 18
                    fill: deleteHover.hovered ? 1 : 0
                    color: Appearance.colors.colOnErrorContainer
                }

                HoverHandler {
                    id: deleteHover
                    cursorShape: Qt.PointingHandCursor
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.deleteSelected()
                }
            }
        }

        // One delegate per grip slot (see AnnotationModel.gripSlots). The model
        // is a fixed count so the delegates, and the pressed MouseArea, survive
        // the annotation being replaced on every motion event of a drag.
        Item {
            id: annotationGrips
            z: 9999
            x: root.editorRegionX
            y: root.editorRegionY
            visible: selectionOverlay.visible && root.currentTool === "none" && root.editingTextId === null

            Repeater {
                model: AnnotationModel.gripSlots.length

                delegate: Item {
                    id: grip
                    required property int index
                    readonly property var slot: AnnotationModel.gripSlots[index]
                    readonly property var pos: AnnotationModel.gripPosition(selectionOverlay.sel, slot,
                                                                            selectionOverlay.pad)
                    readonly property bool endpoint: slot.id === "p1" || slot.id === "p2"
                    visible: pos !== null
                    width: 20
                    height: 20
                    x: (pos?.x ?? 0) - width / 2
                    y: (pos?.y ?? 0) - height / 2

                    Rectangle {
                        anchors.centerIn: parent
                        width: 10
                        height: 10
                        radius: grip.endpoint ? width / 2 : 2
                        color: Appearance.colors.colOnPrimary
                        border.width: 1.5
                        border.color: Appearance.colors.colPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: {
                            switch (grip.slot.id) {
                            case "tl":
                            case "br":
                                return Qt.SizeFDiagCursor;
                            case "tr":
                            case "bl":
                                return Qt.SizeBDiagCursor;
                            case "t":
                            case "b":
                                return Qt.SizeVerCursor;
                            case "l":
                            case "r":
                                return Qt.SizeHorCursor;
                            default:
                                return Qt.CrossCursor;
                            }
                        }

                        property var startAnn: null
                        property real startPx: 0
                        property real startPy: 0

                        // Map to editorOverlay: this grip moves with the
                        // annotation, so its own coords shift mid-drag.
                        onPressed: mouse => {
                            var p = mapToItem(editorOverlay, mouse.x, mouse.y);
                            startPx = p.x;
                            startPy = p.y;
                            startAnn = null;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed || !selectionOverlay.sel)
                                return;
                            if (startAnn === null) {
                                // First motion: one undo step per drag.
                                root.pushUndo();
                                startAnn = AnnotationModel.clone(selectionOverlay.sel);
                            }
                            var p = mapToItem(editorOverlay, mouse.x, mouse.y);
                            var dx = p.x - startPx;
                            var dy = p.y - startPy;
                            root.replaceAnnotation(AnnotationModel.resized(startAnn, grip.slot, dx, dy));
                        }
                        onReleased: startAnn = null
                    }
                }
            }
        }

        // Middle action bar (Spectacle-style): selection size + terminal
        // actions. Lives outside editorContent so grabToImage never captures
        // it; z sits above the handles so the Export menu isn't occluded.
        EditorActionBar {
            id: actionBar
            z: 9999
            physW: Math.round(root.editorRegionW * root.captureScale)
            physH: Math.round(root.editorRegionH * root.captureScale)
            visible: root.inlineEditorActive && !root.exporting && root.currentTool !== "recrop" && root.editingTextId === null && root.editorRegionW > 0 && root.editorRegionH > 0
            x: Math.max(8, Math.min(root.editorRegionX + root.editorRegionW / 2 - width / 2, root.screen.width - width - 8))
            y: {
                var gap = 12;
                var barHeight = height > 0 ? height : 56;

                // Determine vertical boundaries to avoid screen edges and editorToolbarRow
                var topBound = 8;
                var bottomBound = root.screen.height - 8;
                if (editorOverlay.editorToolbarAtBottom) {
                    bottomBound = Math.min(bottomBound, editorToolbarRow.y - 8);
                } else {
                    topBound = Math.max(topBound, editorToolbarRow.y + editorToolbarRow.height + 8);
                }

                // 1. Preferred: position below the selected region
                var below = root.editorRegionY + root.editorRegionH + gap;
                if (below + barHeight <= bottomBound)
                    return below;

                // 2. Alternative: position above the selected region
                var above = root.editorRegionY - barHeight - gap;
                if (above >= topBound)
                    return above;

                // 3. Fallback: tuck inside the selection without colliding with topBound/bottomBound
                return Math.max(topBound, Math.min(bottomBound - barHeight, root.editorRegionY + root.editorRegionH - barHeight - gap));
            }

            onCopyRequested: root.finalizeScreenshot(false)
            onSaveRequested: root.finalizeScreenshot(true)
            onSaveAsRequested: root.finalizeScreenshotAs()
            onExtractTextRequested: root.extractText()
            onOpenWithRequested: root.exportOpenWith()
            onSearchRequested: root.exportSearch()
            onCopyPathRequested: root.exportCopyPath()
            onCancelRequested: root.dismiss()
        }

        // Click-away catcher that closes the Export menu.
        MouseArea {
            z: 9998
            anchors.fill: parent
            visible: actionBar.exportMenuOpen
            enabled: visible
            onPressed: actionBar.exportMenuOpen = false
        }

        // Rectangular region re-crop. Active only while the "recrop" tool is
        // selected; drag anywhere over the frozen screen to pick a new crop.
        MouseArea {
            id: recropArea
            anchors.fill: parent
            z: 9997
            visible: root.inlineEditorActive && root.currentTool === "recrop"
            enabled: visible
            cursorShape: Qt.CrossCursor
            preventStealing: true

            property real sx: 0
            property real sy: 0
            property bool active: false

            onPressed: mouse => {
                sx = mouse.x;
                sy = mouse.y;
                active = true;
                recropRect.x = sx;
                recropRect.y = sy;
                recropRect.width = 0;
                recropRect.height = 0;
            }
            onPositionChanged: mouse => {
                if (!active)
                    return;
                recropRect.x = Math.min(sx, mouse.x);
                recropRect.y = Math.min(sy, mouse.y);
                recropRect.width = Math.abs(mouse.x - sx);
                recropRect.height = Math.abs(mouse.y - sy);
            }
            onReleased: mouse => {
                active = false;
                if (recropRect.width < 8 || recropRect.height < 8) {
                    root.currentTool = "none";
                    return;
                }
                root.shiftScene(root.editorRegionX - recropRect.x, root.editorRegionY - recropRect.y);
                root.editorRegionX = recropRect.x;
                root.editorRegionY = recropRect.y;
                root.editorRegionW = recropRect.width;
                root.editorRegionH = recropRect.height;
                // Keep the drag vars (which drive the darken overlay + dashed
                // border) in sync with the new crop, else the old region's
                // chrome lingers until the next resize.
                root.dragStartX = recropRect.x;
                root.dragStartY = recropRect.y;
                root.draggingX = recropRect.x + recropRect.width;
                root.draggingY = recropRect.y + recropRect.height;
                root.currentTool = "none";
            }

            Rectangle {
                id: recropRect
                visible: recropArea.active
                color: "#33ffffff"
                border.width: 1
                border.color: root.selectionBorderColor
            }
        }

        // Editor toolbar
        Row {
            id: editorToolbarRow
            z: 10
            spacing: 6
            width: implicitWidth
            height: implicitHeight
            focus: root.inlineEditorActive
            anchors.horizontalCenter: parent.horizontalCenter

            y: {
                if (!root.inlineEditorActive) {
                    return editorOverlay.editorToolbarAtBottom ? root.screen.height : -height;
                }
                return editorOverlay.editorToolbarAtBottom ? (root.screen.height - height - 8) : 8;
            }
            opacity: root.inlineEditorActive ? 1 : 0
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(editorToolbarRow)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            EditorToolbar {
                id: editorToolbarInstance
                editor: root
            }
        }
        }
    }

}
