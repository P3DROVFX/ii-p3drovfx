pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.regionSelector.annotations
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects

PanelWindow {
    id: root
    visible: false
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
    // "rect", "arrow", "line", "circle", "star", "pencil", "highlighter", "text", "number", "blur", "none"
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
        source: root.inlineEditorActive ? root.screenshotPath : ""
        width: 0
        height: 0
        visible: false
        asynchronous: true
        cache: true
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
    // Toolbar color/width edits retarget the selected annotation (blur keeps its
    // fixed masking style). Each edit is one undo step.
    onCurrentColorChanged: {
        var sel = root.selectedAnnotation();
        if (!sel || sel.type === "blur")
            return;
        root.pushUndo();
        root.restyleSelected("stroke", String(root.currentColor));
        // Keep a filled shape's interior in sync with its outline colour.
        if (sel.style && sel.style.fill)
            root.restyleSelected("fill", String(root.currentColor));
    }
    onCurrentLineWidthChanged: {
        var sel = root.selectedAnnotation();
        if (!sel || sel.type === "blur")
            return;
        root.pushUndo();
        root.restyleSelected("strokeWidth", root.currentLineWidth);
    }
    // Toggling fill retargets a selected closed shape (rect/circle/star).
    onFillEnabledChanged: {
        var sel = root.selectedAnnotation();
        if (!sel || (sel.type !== "rect" && sel.type !== "circle" && sel.type !== "star"))
            return;
        root.pushUndo();
        root.restyleSelected("fill", root.fillEnabled ? String(root.currentColor) : null);
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
            var ann = AnnotationModel.clone(newList[i]);
            var g = ann.geom;
            switch (ann.type) {
            case "rect":
            case "circle":
            case "star":
            case "text":
            case "number":
                g.x += dx;
                g.y += dy;
                break;
            case "arrow":
            case "line":
                g.x1 += dx;
                g.y1 += dy;
                g.x2 += dx;
                g.y2 += dy;
                break;
            case "pencil":
            case "blur":
            case "highlighter":
                for (var p = 0; p < g.points.length; p++) {
                    g.points[p].x += dx;
                    g.points[p].y += dy;
                }
                break;
            }
            newList[i] = ann;
            break;
        }
        root.annotations = newList;
    }

    function restyleSelected(key, value) {
        if (root.selectedId === null)
            return;
        var newList = root.annotations.slice();
        for (var i = 0; i < newList.length; i++) {
            if (newList[i].id !== root.selectedId)
                continue;
            if (newList[i].type === "blur")
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
        editorOverlay.forceActiveFocus();
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
        root.phase = RegionSelection.Phase.Select;
        root.dragging = false;
        root.dragStartX = 0;
        root.dragStartY = 0;
        root.draggingX = 0;
        root.draggingY = 0;
        root.dragDiffX = 0;
        root.dragDiffY = 0;
        root.points = [];
        root.editorRegionW = 0;
        root.editorRegionH = 0;
    }

    function finalizeScreenshot(saveToFile) {
        ScreenshotAction.playShutterSound(ScreenshotAction.Action.Copy);
        // Grab at the capture's native resolution (e.g. 2880×1800 on a 1.5×
        // display) rather than logical, so the exported PNG isn't downscaled.
        var targetW = Math.round(root.editorRegionW * root.captureScale);
        var targetH = Math.round(root.editorRegionH * root.captureScale);
        // Drop all editor chrome for one frame so handles/outlines
        // never get baked into the exported PNG.
        root.exporting = true;
        editorContent.grabToImage(function (result) {
            var tempPath = "/tmp/quickshell-snip-" + Date.now() + ".png";
            result.saveToFile(tempPath);
            if (saveToFile) {
                var saveDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : (Directories.home + "/Pictures/Screenshots");
                var fileName = "screenshot-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_hh.mm.ss") + ".png";
                var fullPath = saveDir + "/" + fileName;
                Quickshell.execDetached(["bash", "-c", "mkdir -p '" + StringUtils.shellSingleQuoteEscape(saveDir) + "' && mv '" + StringUtils.shellSingleQuoteEscape(tempPath) + "' '" + StringUtils.shellSingleQuoteEscape(fullPath) + "' && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Screenshot saved' 'Saved to: " + StringUtils.shellSingleQuoteEscape(fullPath) + "'"]);
            } else {
                Quickshell.execDetached(["bash", "-c", "wl-copy < '" + StringUtils.shellSingleQuoteEscape(tempPath) + "' && rm '" + StringUtils.shellSingleQuoteEscape(tempPath) + "' && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Screenshot copied' 'Copied to clipboard'"]);
            }
            root.exporting = false;
            root.dismiss();
        }, Qt.size(targetW, targetH));
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
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
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
    readonly property list<var> windowRegions: RegionFunctions.filterWindowRegionsByLayers(root.windows.filter(w => w.workspace.id === root.activeWorkspaceId), root.layerRegions).map(window => {
        return {
            at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
            size: [window.size[0], window.size[1]],
            class: window.class,
            title: window.title
        };
    })
    readonly property list<var> layerRegions: {
        const layersOfThisMonitor = root.layers[root.hyprlandMonitor.name];
        const topLayers = layersOfThisMonitor?.levels["2"];
        if (!topLayers)
            return [];
        const nonBarTopLayers = topLayers.filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock"))).map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace
            };
        });
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace
            };
        });
        return offsetAdjustedLayers;
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
    function setRegionToTargeted() {
        const padding = Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
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

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (root.enableContentRegions)
                imageDetectionProcess.running = true;
            root.preparationDone = !checkRecordingProc.running;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["bash", "-c", "pidof wf-recorder > /dev/null 2>&1 || (pgrep -x obs > /dev/null 2>&1 && python3 '" + Directories.scriptPath + "/videos/obs_control.py' status 2>/dev/null | grep -q active)"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running;
            root.recordingShouldStop = (exitCode === 0);
        }
    }
    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone)
            return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            root.dismiss();
            return;
        }
        root.visible = true;
    }

    onVisibleChanged: {
        if (!root.visible) {
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

    function getScreenshotAction() {
        switch (root.action) {
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
    function snip() {
        // Validity check
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
        }

        // Clamp region to screen bounds
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));

        // Adjust action
        if (root.action === RegionSelection.SnipAction.Copy || root.action === RegionSelection.SnipAction.Edit) {
            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        }
        if (root.action === RegionSelection.SnipAction.Search || root.action === RegionSelection.SnipAction.AskAI) {
            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.AskAI : RegionSelection.SnipAction.Search;
        }

        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //
        Config.options.screenSnip.savePath : "";
        var screenshotAction = root.getScreenshotAction();
        const command = ScreenshotAction.getCommand(root.regionX * root.monitorScale //
        , root.regionY * root.monitorScale //
        , root.regionWidth * root.monitorScale//
        , root.regionHeight * root.monitorScale //
        , root.screenshotPath //
        , screenshotAction //
        , screenshotDir);
        Quickshell.execDetached(command);
        ScreenshotAction.playShutterSound(screenshotAction);
        if (root.action === RegionSelection.SnipAction.AskAI) {
            Ai.handleClipboardAndAttach();
            GlobalStates.policiesPanelOpen = true;
        }
        root.dismiss();
    }

    // Dont use anything like stdout here, this is being called detached
    Process {
        id: snipProc
    }

    ScreencopyView { // For freezing
        anchors.fill: parent
        live: false
        captureSource: root.screen
        visible: root.visible

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
                root.regionX = minX - padding;
                root.regionY = minY - padding;
                root.regionWidth = maxX - minX + padding * 2;
                root.regionHeight = maxY - minY + padding * 2;
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
            visible: root.phase === RegionSelection.Phase.Select
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

    // Inline editor overlay
    Item {
        id: editorOverlay
        z: 10
        visible: root.inlineEditorActive
        anchors.fill: parent
        focus: root.inlineEditorActive
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
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                root.deleteSelected();
                event.accepted = true;
            }
        }

        // Darken everything outside the selected region
        Rectangle {
            anchors.fill: parent
            color: "#00000000"
            // No darken needed; ScreencopyView still shows the frozen screen
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
                source: root.inlineEditorActive ? root.screenshotPath : ""
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
                    sourceComponent: {
                        switch (modelData.type) {
                        case "rect":
                            return rectAnnotationComp;
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

            Canvas {
                id: blurCanvas
                anchors.fill: parent
                z: 1
                visible: root.inlineEditorActive

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    var blurAnns = [];
                    for (var i = 0; i < root.annotations.length; i++) {
                        if (root.annotations[i].type === "blur") {
                            blurAnns.push(root.annotations[i]);
                        }
                    }
                    if (drawingArea.tempAnnotation && drawingArea.tempAnnotation.type === "blur") {
                        blurAnns.push(drawingArea.tempAnnotation);
                    }

                    if (blurAnns.length === 0)
                        return;

                    ctx.save();

                    // 1. Draw all masking strokes as standard solid drawings first
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    for (var j = 0; j < blurAnns.length; j++) {
                        var ann = blurAnns[j];
                        var pts = (ann.geom ?? ann).points;
                        if (!pts || pts.length === 0)
                            continue;

                        ctx.lineWidth = (ann.style ?? ann).strokeWidth ?? ann.lineWidth;
                        ctx.strokeStyle = "rgba(0,0,0,1.0)";
                        ctx.fillStyle = "rgba(0,0,0,1.0)";

                        ctx.beginPath();
                        ctx.moveTo(pts[0].x, pts[0].y);
                        for (var k = 1; k < pts.length - 2; k++) {
                            var xc = (pts[k].x + pts[k + 1].x) / 2;
                            var yc = (pts[k].y + pts[k + 1].y) / 2;
                            ctx.quadraticCurveTo(pts[k].x, pts[k].y, xc, yc);
                        }
                        if (pts.length > 2) {
                            ctx.quadraticCurveTo(pts[pts.length - 2].x, pts[pts.length - 2].y, pts[pts.length - 1].x, pts[pts.length - 1].y);
                        } else if (pts.length === 2) {
                            ctx.lineTo(pts[1].x, pts[1].y);
                        } else if (pts.length === 1) {
                            // Support single dot on single click
                            ctx.arc(pts[0].x, pts[0].y, ((ann.style ?? ann).strokeWidth ?? ann.lineWidth) / 2, 0, 2 * Math.PI);
                            ctx.fill();
                            continue;
                        }
                        ctx.stroke();
                    }

                    // 2. Switch composite operation to source-in (draw image only where strokes exist)
                    ctx.globalCompositeOperation = "source-in";

                    // 3. Draw the screenshot portion downscaled onto the small canvas
                    var smallCtx = smallCanvas.getContext("2d");
                    smallCtx.clearRect(0, 0, smallCanvas.width, smallCanvas.height);
                    smallCtx.drawImage(editorImage, root.editorRegionX, root.editorRegionY, width, height, 0, 0, smallCanvas.width, smallCanvas.height);

                    // 4. Draw the pixelated, upscaled image to fill the main canvas (smoothing disabled)
                    ctx.imageSmoothingEnabled = false;
                    ctx.drawImage(smallCanvas, 0, 0, smallCanvas.width, smallCanvas.height, 0, 0, width, height);

                    ctx.restore();
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
            // ----------------------------------------

            // Drawing area
            MouseArea {
                id: drawingArea
                anchors.fill: parent
                // Disabled while editing text so canvas clicks don't place a
                // second text box (the commit catcher handles those clicks).
                enabled: root.currentTool !== "none" && root.editingTextId === null
                cursorShape: {
                    if (root.currentTool === "text")
                        return Qt.IBeamCursor;
                    if (root.currentTool === "pencil" || root.currentTool === "blur" || root.currentTool === "highlighter")
                        return Qt.CrossCursor;
                    return Qt.ArrowCursor;
                }
                property real startX: 0
                property real startY: 0
                property var tempAnnotation: null

                onPressed: mouse => {
                    startX = mouse.x;
                    startY = mouse.y;
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
                    if (root.currentTool === "rect") {
                        tempAnnotation = AnnotationModel.make("rect", id, z, {
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
                    } else if (root.currentTool === "highlighter") {
                        var hlStyle = AnnotationModel.defaultStyle(root.currentColor, root.currentLineWidth * 4);
                        hlStyle.opacity = Config.options.regionSelector.annotation.highlighterOpacity;
                        tempAnnotation = AnnotationModel.make("highlighter", id, z, {
                            "points": [
                                {
                                    "x": startX,
                                    "y": startY
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
                        tempAnnotation = AnnotationModel.make("pencil", id, z, {
                            "points": [
                                {
                                    "x": startX,
                                    "y": startY
                                }
                            ]
                        }, style);
                    } else if (root.currentTool === "blur") {
                        var blurStyle = AnnotationModel.defaultStyle("#ffffff", root.currentLineWidth * 10);
                        tempAnnotation = AnnotationModel.make("blur", id, z, {
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
                    if (!tempAnnotation)
                        return;
                    var id = tempAnnotation.id;
                    var z = tempAnnotation.z;
                    var style = tempAnnotation.style;
                    if (root.currentTool === "rect") {
                        tempAnnotation = AnnotationModel.make("rect", id, z, {
                            "x": Math.min(startX, mouse.x),
                            "y": Math.min(startY, mouse.y),
                            "w": Math.abs(mouse.x - startX),
                            "h": Math.abs(mouse.y - startY)
                        }, style);
                    } else if (root.currentTool === "arrow") {
                        tempAnnotation = AnnotationModel.make("arrow", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": mouse.x,
                            "y2": mouse.y
                        }, style);
                    } else if (root.currentTool === "line") {
                        tempAnnotation = AnnotationModel.make("line", id, z, {
                            "x1": startX,
                            "y1": startY,
                            "x2": mouse.x,
                            "y2": mouse.y
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
                    } else if (root.currentTool === "pencil" || root.currentTool === "blur" || root.currentTool === "highlighter") {
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
                    if (!tempAnnotation)
                        return;
                    var g = tempAnnotation.geom;
                    if (root.currentTool === "rect") {
                        if (g.w < 2 || g.h < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "arrow" || root.currentTool === "line") {
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
                    } else if (root.currentTool === "pencil" || root.currentTool === "blur" || root.currentTool === "highlighter") {
                        if (g.points.length < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    }
                    var newList = root.annotations.slice();
                    newList.push(AnnotationModel.clone(tempAnnotation));
                    root.annotations = newList;
                    // Keep the just-drawn shape selected so a fill/colour/width
                    // toggle applies to it without re-selecting it first.
                    root.selectedId = tempAnnotation.id;
                    tempAnnotation = null;
                }

                // Temp annotation while drawing
                RectAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "rect" ? drawingArea.tempAnnotation : null
                }

                ArrowAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "arrow" ? drawingArea.tempAnnotation : null
                }
                LineAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "line" ? drawingArea.tempAnnotation : null
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

                    root.editorRegionX = newX;
                    root.editorRegionY = newY;

                    root.dragStartX = newX;
                    root.dragStartY = newY;
                    root.draggingX = newX + root.editorRegionW;
                    root.draggingY = newY + root.editorRegionH;
                }
            }

            // Selection outline + delete affordance for the selected annotation.
            // Sits above the move area so its chip wins the click; hidden during
            // export so it never bakes into the PNG.
            Item {
                id: selectionOverlay
                z: 6
                readonly property var sel: root.selectedAnnotation()
                readonly property var bb: sel ? AnnotationModel.boundingBox(sel) : null
                readonly property real pad: (sel && sel.style ? (sel.style.strokeWidth ?? 2) : 2) / 2 + 4
                visible: sel !== null && !root.exporting
                x: bb ? bb.x - pad : 0
                y: bb ? bb.y - pad : 0
                width: bb ? bb.w + pad * 2 : 0
                height: bb ? bb.h + pad * 2 : 0

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: 4
                    border.width: 1.5
                    border.color: Appearance.colors.colPrimary
                }

                Rectangle {
                    id: deleteChip
                    width: 22
                    height: 22
                    radius: width / 2
                    color: Appearance.colors.colPrimary
                    anchors.left: parent.right
                    anchors.bottom: parent.top
                    anchors.leftMargin: -width / 2
                    anchors.bottomMargin: -height / 2

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.deleteSelected()
                    }
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

                readonly property int hitSize: 26
                readonly property int gripSize: 12
                // The dashed selection border is drawn 6px outside the true
                // region (borderWidth 1 + 5, see RectCornersSelectionDetails);
                // centre the grips on that visible line, not the raw edge.
                readonly property real outset: 6
                z: 9999
                visible: !root.exporting && root.editingTextId === null
                width: hitSize
                height: hitSize
                x: (root.editorRegionX - outset) + (root.editorRegionW + outset * 2) * modelData.ax - width / 2
                y: (root.editorRegionY - outset) + (root.editorRegionH + outset * 2) * modelData.ay - height / 2

                // Small square grip (Spectacle-style) rather than a round dot.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.gripSize
                    height: parent.gripSize
                    radius: 2
                    color: Appearance.colors.colPrimary
                    border.width: 1
                    border.color: Appearance.colors.colOnPrimary
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
                visible: !root.exporting && root.editingTextId === null
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

        // Editor toolbar
        Row {
            id: editorToolbarRow
            z: 10
            spacing: 6
            focus: root.inlineEditorActive
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: root.inlineEditorActive ? 8 : -height
            }
            opacity: root.inlineEditorActive ? 1 : 0
            Behavior on anchors.topMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
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
