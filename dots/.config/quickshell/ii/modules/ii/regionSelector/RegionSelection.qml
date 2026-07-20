pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
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
    property string currentTool: "none" // "rect", "arrow", "circle", "star", "pencil", "blur", "none"
    property color currentColor: "#ff3b30"
    property list<color> presetColors: ["#ff3b30", "#ffcc00", "#34c759", "#007aff", "#af52de", "#ffffff", "#000000"]
    property int currentLineWidth: 2
    property real editorRegionX: 0
    property real editorRegionY: 0
    property real editorRegionW: 0
    property real editorRegionH: 0
    property bool shapePopupVisible: false
    property bool colorPopupVisible: false
    property bool lineWidthPopupVisible: false

    function pushUndo() {
        var clone = root.annotations.slice();
        var newStack = root.undoStack.slice();
        newStack.push(clone);
        root.undoStack = newStack;
    }

    function undo() {
        if (root.undoStack.length === 0)
            return;
        var newStack = root.undoStack.slice();
        root.annotations = newStack.pop();
        root.undoStack = newStack;
    }

    function clearEditor() {
        root.annotations = [];
        root.undoStack = [];
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
        var targetW = Math.round(root.editorRegionW * root.monitorScale);
        var targetH = Math.round(root.editorRegionH * root.monitorScale);
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
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
                root.undo();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                root.finalizeScreenshot(false);
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
                            return pencilAnnotationComp;
                        default:
                            return null;
                        }
                    }
                    onLoaded: {
                        if (item) item.annData = modelData;
                    }
                }
            }

            // --- Pixelation / Blur Implementation ---
            Canvas {
                id: smallCanvas
                width: Math.max(1, Math.round(editorContent.width / 24))
                height: Math.max(1, Math.round(editorContent.height / 24))
                visible: false
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
                        var pts = ann.points;
                        if (!pts || pts.length === 0)
                            continue;

                        ctx.lineWidth = ann.lineWidth;
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
                            ctx.arc(pts[0].x, pts[0].y, ann.lineWidth / 2, 0, 2 * Math.PI);
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
                enabled: root.currentTool !== "none"
                cursorShape: (root.currentTool === "pencil" || root.currentTool === "blur") ? Qt.CrossCursor : Qt.ArrowCursor
                property real startX: 0
                property real startY: 0
                property var tempAnnotation: null

                onPressed: mouse => {
                    startX = mouse.x;
                    startY = mouse.y;
                    root.pushUndo();
                    if (root.currentTool === "rect") {
                        tempAnnotation = {
                            type: "rect",
                            x: startX,
                            y: startY,
                            width: 0,
                            height: 0,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "arrow") {
                        tempAnnotation = {
                            type: "arrow",
                            x1: startX,
                            y1: startY,
                            x2: startX,
                            y2: startY,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "circle") {
                        tempAnnotation = {
                            type: "circle",
                            x: startX,
                            y: startY,
                            radius: 0,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "star") {
                        tempAnnotation = {
                            type: "star",
                            x: startX,
                            y: startY,
                            outerRadius: 0,
                            innerRadius: 0,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "pencil") {
                        tempAnnotation = {
                            type: "pencil",
                            points: [
                                {
                                    x: startX,
                                    y: startY
                                }
                            ],
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "blur") {
                        tempAnnotation = {
                            type: "blur",
                            points: [
                                {
                                    x: startX,
                                    y: startY
                                }
                            ],
                            color: "#ffffff", // solid mask color
                            lineWidth: root.currentLineWidth * 10 // large stroke
                        };
                    }
                }
                onPositionChanged: mouse => {
                    if (!tempAnnotation)
                        return;
                    if (root.currentTool === "rect") {
                        var newRect = {
                            type: "rect",
                            x: Math.min(startX, mouse.x),
                            y: Math.min(startY, mouse.y),
                            width: Math.abs(mouse.x - startX),
                            height: Math.abs(mouse.y - startY),
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                        tempAnnotation = newRect;
                    } else if (root.currentTool === "arrow") {
                        var newArrow = {
                            type: "arrow",
                            x1: startX,
                            y1: startY,
                            x2: mouse.x,
                            y2: mouse.y,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                        tempAnnotation = newArrow;
                    } else if (root.currentTool === "circle") {
                        var dx = mouse.x - startX;
                        var dy = mouse.y - startY;
                        var radius = Math.sqrt(dx * dx + dy * dy);
                        tempAnnotation = {
                            type: "circle",
                            x: startX,
                            y: startY,
                            radius: radius,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "star") {
                        var dx = mouse.x - startX;
                        var dy = mouse.y - startY;
                        var outerRadius = Math.sqrt(dx * dx + dy * dy);
                        var innerRadius = outerRadius * 0.4;
                        tempAnnotation = {
                            type: "star",
                            x: startX,
                            y: startY,
                            outerRadius: outerRadius,
                            innerRadius: innerRadius,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "pencil") {
                        var lastPoint = tempAnnotation.points[tempAnnotation.points.length - 1];
                        var dxP = mouse.x - lastPoint.x;
                        var dyP = mouse.y - lastPoint.y;
                        if (dxP * dxP + dyP * dyP < 16)
                            return;
                        var newPoints = tempAnnotation.points.slice();
                        newPoints.push({
                            x: mouse.x,
                            y: mouse.y
                        });
                        tempAnnotation = {
                            type: "pencil",
                            points: newPoints,
                            color: root.currentColor,
                            lineWidth: root.currentLineWidth
                        };
                    } else if (root.currentTool === "blur") {
                        var lastPointBlur = tempAnnotation.points[tempAnnotation.points.length - 1];
                        var dxB = mouse.x - lastPointBlur.x;
                        var dyB = mouse.y - lastPointBlur.y;
                        if (dxB * dxB + dyB * dyB < 16)
                            return;
                        var newPointsBlur = tempAnnotation.points.slice();
                        newPointsBlur.push({
                            x: mouse.x,
                            y: mouse.y
                        });
                        tempAnnotation = {
                            type: "blur",
                            points: newPointsBlur,
                            color: "#ffffff",
                            lineWidth: tempAnnotation.lineWidth
                        };
                    }
                }
                onReleased: mouse => {
                    if (!tempAnnotation)
                        return;
                    if (root.currentTool === "rect") {
                        if (tempAnnotation.width < 2 || tempAnnotation.height < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "arrow") {
                        if (Math.abs(tempAnnotation.x2 - tempAnnotation.x1) < 2 && Math.abs(tempAnnotation.y2 - tempAnnotation.y1) < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "circle") {
                        if (tempAnnotation.radius < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "star") {
                        if (tempAnnotation.outerRadius < 5) {
                            tempAnnotation = null;
                            return;
                        }
                    } else if (root.currentTool === "pencil" || root.currentTool === "blur") {
                        if (tempAnnotation.points.length < 2) {
                            tempAnnotation = null;
                            return;
                        }
                    }
                    var newList = root.annotations.slice();
                    var clone = Object.assign({}, tempAnnotation);
                    newList.push(clone);
                    root.annotations = newList;
                    tempAnnotation = null;
                }

                // Temp annotation while drawing
                Rectangle {
                    id: tempRect
                    visible: drawingArea.tempAnnotation !== null && drawingArea.tempAnnotation?.type === "rect"
                    x: drawingArea.tempAnnotation?.x ?? 0
                    y: drawingArea.tempAnnotation?.y ?? 0
                    width: drawingArea.tempAnnotation?.width ?? 0
                    height: drawingArea.tempAnnotation?.height ?? 0
                    color: "transparent"
                    border.color: drawingArea.tempAnnotation?.color ?? "#ff3b30"
                    border.width: drawingArea.tempAnnotation?.lineWidth ?? 2
                    radius: 0
                }

                ArrowAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "arrow" ? drawingArea.tempAnnotation : null
                }
                CircleAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "circle" ? drawingArea.tempAnnotation : null
                }
                StarAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "star" ? drawingArea.tempAnnotation : null
                }
                PencilAnnotationComponent {
                    annData: drawingArea.tempAnnotation?.type === "pencil" ? drawingArea.tempAnnotation : null
                }
            }

            MouseArea {
                id: moveArea
                anchors.fill: parent
                enabled: root.currentTool === "none"
                cursorShape: enabled ? Qt.SizeAllCursor : Qt.ArrowCursor
                property real startMouseX: 0
                property real startMouseY: 0

                onPressed: mouse => {
                    startMouseX = mouse.x;
                    startMouseY = mouse.y;
                }

                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
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
        }

        // Resize handle
        Item {
            id: resizeHandle
            z: 9999
            x: root.editorRegionX + root.editorRegionW
            y: root.editorRegionY + root.editorRegionH

            property int margins: 8
            width: resizeContent.implicitWidth + margins * 2
            height: resizeContent.implicitHeight + margins * 2

            Rectangle {
                id: resizeContent
                anchors.centerIn: parent
                implicitHeight: 38
                implicitWidth: implicitHeight
                topLeftRadius: 6
                bottomLeftRadius: implicitHeight - topLeftRadius
                bottomRightRadius: bottomLeftRadius
                topRightRadius: bottomLeftRadius
                color: Appearance.colors.colPrimary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "open_in_full"
                    iconSize: 22
                    color: Appearance.colors.colOnPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeFDiagCursor
                preventStealing: true

                property real startMouseX: 0
                property real startMouseY: 0

                onPressed: mouse => {
                    startMouseX = mouse.x;
                    startMouseY = mouse.y;
                }

                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    var deltaX = mouse.x - startMouseX;
                    var deltaY = mouse.y - startMouseY;

                    var newW = root.editorRegionW + deltaX;
                    var newH = root.editorRegionH + deltaY;

                    newW = Math.max(20, newW);
                    newH = Math.max(20, newH);
                    newW = Math.min(newW, root.screen.width - root.editorRegionX);
                    newH = Math.min(newH, root.screen.height - root.editorRegionY);

                    root.editorRegionW = newW;
                    root.editorRegionH = newH;

                    // Sync original selection region for visual overlay (dotted lines and dark area)
                    root.dragStartX = root.editorRegionX;
                    root.dragStartY = root.editorRegionY;
                    root.draggingX = root.editorRegionX + newW;
                    root.draggingY = root.editorRegionY + newH;
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
            }
        }
    }

    component RectAnnotationComponent: Rectangle {
        property var annData: null
        x: annData?.x ?? 0
        y: annData?.y ?? 0
        width: annData?.width ?? 0
        height: annData?.height ?? 0
        color: "transparent"
        border.color: annData?.color ?? "#ff3b30"
        border.width: annData?.lineWidth ?? 2
        radius: 0
    }

    component ArrowAnnotationComponent: Shape {
        id: arrowRoot
        property var annData: null
        x: Math.min(annData?.x1 ?? 0, annData?.x2 ?? 0) - 20
        y: Math.min(annData?.y1 ?? 0, annData?.y2 ?? 0) - 20
        width: Math.abs((annData?.x2 ?? 0) - (annData?.x1 ?? 0)) + 40
        height: Math.abs((annData?.y2 ?? 0) - (annData?.y1 ?? 0)) + 40
        visible: annData !== null

        ShapePath {
            strokeColor: annData?.color ?? "transparent"
            strokeWidth: annData?.lineWidth ?? 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            startX: (annData?.x1 ?? 0) - arrowRoot.x
            startY: (annData?.y1 ?? 0) - arrowRoot.y

            PathLine {
                x: (annData?.x2 ?? 0) - arrowRoot.x
                y: (annData?.y2 ?? 0) - arrowRoot.y
            }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: annData?.color ?? "transparent"

            startX: (annData?.x2 ?? 0) - arrowRoot.x
            startY: (annData?.y2 ?? 0) - arrowRoot.y

            PathLine {
                x: ((annData?.x2 ?? 0) - arrowRoot.x) - Math.max(15, (annData?.lineWidth ?? 2) * 3) * Math.cos(Math.atan2((annData?.y2 ?? 0) - (annData?.y1 ?? 0), (annData?.x2 ?? 0) - (annData?.x1 ?? 0)) - Math.PI / 6)
                y: ((annData?.y2 ?? 0) - arrowRoot.y) - Math.max(15, (annData?.lineWidth ?? 2) * 3) * Math.sin(Math.atan2((annData?.y2 ?? 0) - (annData?.y1 ?? 0), (annData?.x2 ?? 0) - (annData?.x1 ?? 0)) - Math.PI / 6)
            }
            PathLine {
                x: ((annData?.x2 ?? 0) - arrowRoot.x) - Math.max(15, (annData?.lineWidth ?? 2) * 3) * Math.cos(Math.atan2((annData?.y2 ?? 0) - (annData?.y1 ?? 0), (annData?.x2 ?? 0) - (annData?.x1 ?? 0)) + Math.PI / 6)
                y: ((annData?.y2 ?? 0) - arrowRoot.y) - Math.max(15, (annData?.lineWidth ?? 2) * 3) * Math.sin(Math.atan2((annData?.y2 ?? 0) - (annData?.y1 ?? 0), (annData?.x2 ?? 0) - (annData?.x1 ?? 0)) + Math.PI / 6)
            }
            PathLine {
                x: (annData?.x2 ?? 0) - arrowRoot.x
                y: (annData?.y2 ?? 0) - arrowRoot.y
            }
        }
    }

    component CircleAnnotationComponent: Rectangle {
        property var annData: null
        x: (annData?.x ?? 0) - (annData?.radius ?? 0)
        y: (annData?.y ?? 0) - (annData?.radius ?? 0)
        width: (annData?.radius ?? 0) * 2
        height: (annData?.radius ?? 0) * 2
        color: "transparent"
        border.color: annData?.color ?? "transparent"
        border.width: annData?.lineWidth ?? 2
        radius: width / 2
        visible: annData !== null
    }

    component StarAnnotationComponent: Shape {
        id: starRoot
        property var annData: null
        x: (annData?.x ?? 0) - (annData?.outerRadius ?? 0) - 5
        y: (annData?.y ?? 0) - (annData?.outerRadius ?? 0) - 5
        width: ((annData?.outerRadius ?? 0) * 2) + 10
        height: ((annData?.outerRadius ?? 0) * 2) + 10
        visible: annData !== null

        ShapePath {
            strokeColor: annData?.color ?? "transparent"
            strokeWidth: annData?.lineWidth ?? 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: {
                    if (!annData)
                        return "";
                    var cx = annData.x - starRoot.x;
                    var cy = annData.y - starRoot.y;
                    var outerR = annData.outerRadius;
                    var innerR = annData.innerRadius;
                    var spikes = 5;
                    var rot = Math.PI / 2 * 3;
                    var step = Math.PI / spikes;

                    var d = "";
                    for (var i = 0; i < spikes; i++) {
                        var outerX = cx + Math.cos(rot) * outerR;
                        var outerY = cy + Math.sin(rot) * outerR;
                        d += (i === 0 ? "M " : " L ") + outerX + " " + outerY;
                        rot += step;
                        var innerX = cx + Math.cos(rot) * innerR;
                        var innerY = cy + Math.sin(rot) * innerR;
                        d += " L " + innerX + " " + innerY;
                        rot += step;
                    }
                    d += " Z";
                    return d;
                }
            }
        }
    }

    component PencilAnnotationComponent: Shape {
        id: pencilRoot
        property var annData: null
        x: 0
        y: 0
        width: typeof editorContent !== "undefined" && editorContent ? editorContent.width : 4000
        height: typeof editorContent !== "undefined" && editorContent ? editorContent.height : 4000
        visible: annData !== null

        ShapePath {
            strokeColor: annData?.color ?? "transparent"
            strokeWidth: annData?.lineWidth ?? 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: {
                    var pts = annData?.points;
                    if (!pts || pts.length === 0)
                        return "";
                    var d = "M " + pts[0].x + " " + pts[0].y;
                    for (var i = 1; i < pts.length - 2; i++) {
                        var xc = (pts[i].x + pts[i + 1].x) / 2;
                        var yc = (pts[i].y + pts[i + 1].y) / 2;
                        d += " Q " + pts[i].x + " " + pts[i].y + ", " + xc + " " + yc;
                    }
                    if (pts.length > 2) {
                        d += " Q " + pts[pts.length - 2].x + " " + pts[pts.length - 2].y + ", " + pts[pts.length - 1].x + " " + pts[pts.length - 1].y;
                    } else if (pts.length === 2) {
                        d += " L " + pts[1].x + " " + pts[1].y;
                    }
                    return d;
                }
            }
        }
    }

    component EditorToolbar: Toolbar {
        spacing: 8

        // Arrow
        IconToolbarButton {
            id: arrowBtn
            text: "north_east"
            toggled: root.currentTool === "arrow"
            onClicked: root.currentTool = root.currentTool === "arrow" ? "none" : "arrow"
            StyledToolTip {
                z: 9999
                text: Translation.tr("Arrow")
            }
        }

        // Rectangle with shape accordion
        Item {
            id: shapeSelectorContainer
            implicitWidth: shapeRow.implicitWidth
            implicitHeight: Math.max(shapeBtn.implicitHeight, dropdownBtn.implicitHeight)

            Row {
                id: shapeRow
                spacing: 2

                IconToolbarButton {
                    id: shapeBtn
                    text: "crop_square"
                    toggled: root.currentTool === "rect"
                    onClicked: {
                        root.currentTool = root.currentTool === "rect" ? "none" : "rect";
                        root.shapePopupVisible = false;
                    }
                    StyledToolTip {
                        z: 9999
                        text: Translation.tr("Rectangle")
                    }
                }

                Item {
                    id: shapeCollapsible
                    implicitHeight: shapeBtn.implicitHeight
                    clip: true
                    implicitWidth: root.shapePopupVisible ? shapesExpandedRow.implicitWidth : 0
                    opacity: root.shapePopupVisible ? 1 : 0

                    Behavior on implicitWidth {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.InOutCubic
                        }
                    }

                    Row {
                        id: shapesExpandedRow
                        spacing: 2
                        scale: root.shapePopupVisible ? 1 : 0.9

                        Behavior on scale {
                            NumberAnimation {
                                duration: 350
                                easing.type: Easing.InOutCubic
                            }
                        }

                        IconToolbarButton {
                            id: circleBtn
                            text: "circle"
                            toggled: root.currentTool === "circle"
                            onClicked: root.currentTool = root.currentTool === "circle" ? "none" : "circle"
                            StyledToolTip {
                                z: 9999
                                text: Translation.tr("Circle")
                            }
                        }

                        IconToolbarButton {
                            id: starBtn
                            text: "star"
                            toggled: root.currentTool === "star"
                            onClicked: root.currentTool = root.currentTool === "star" ? "none" : "star"
                            StyledToolTip {
                                z: 9999
                                text: Translation.tr("Star")
                            }
                        }
                    }
                }

                IconToolbarButton {
                    id: dropdownBtn
                    text: root.shapePopupVisible ? "chevron_left" : "chevron_right"
                    toggled: root.shapePopupVisible
                    onClicked: {
                        root.shapePopupVisible = !root.shapePopupVisible;
                        if (root.shapePopupVisible) {
                            root.colorPopupVisible = false;
                            root.lineWidthPopupVisible = false;
                        }
                    }
                    StyledToolTip {
                        z: 9999
                        text: root.shapePopupVisible ? Translation.tr("Less shapes") : Translation.tr("More shapes")
                    }
                }
            }
        }

        // Pencil
        IconToolbarButton {
            id: pencilBtn
            text: "edit"
            toggled: root.currentTool === "pencil"
            onClicked: root.currentTool = root.currentTool === "pencil" ? "none" : "pencil"
            StyledToolTip {
                z: 9999
                text: Translation.tr("Pencil")
            }
        }

        // Blur/Pixelate
        IconToolbarButton {
            id: blurBtn
            text: "blur_on"
            toggled: root.currentTool === "blur"
            onClicked: root.currentTool = root.currentTool === "blur" ? "none" : "blur"
            StyledToolTip {
                z: 9999
                text: Translation.tr("Pixelate")
            }
        }

        // Line Width Accordion
        Item {
            id: lineWidthSelectorContainer
            implicitWidth: lineWidthRow.implicitWidth
            implicitHeight: 32

            Row {
                id: lineWidthRow
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                IconToolbarButton {
                    id: lineWidthBtn
                    toggled: root.lineWidthPopupVisible
                    onClicked: {
                        root.lineWidthPopupVisible = !root.lineWidthPopupVisible;
                        if (root.lineWidthPopupVisible) {
                            root.colorPopupVisible = false;
                            root.shapePopupVisible = false;
                        }
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Rectangle {
                            anchors.centerIn: parent
                            width: 20
                            height: Math.max(1, root.currentLineWidth)
                            color: lineWidthBtn.colText
                            radius: height / 2
                        }
                    }
                    StyledToolTip {
                        z: 9999
                        text: Translation.tr("Line Thickness")
                    }
                }

                Item {
                    id: lineWidthCollapsible
                    implicitHeight: 32
                    clip: true
                    implicitWidth: root.lineWidthPopupVisible ? lineWidthExpandedRow.implicitWidth : 0
                    opacity: root.lineWidthPopupVisible ? 1 : 0

                    Behavior on implicitWidth {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.InOutCubic
                        }
                    }

                    Row {
                        id: lineWidthExpandedRow
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter
                        scale: root.lineWidthPopupVisible ? 1 : 0.9

                        Behavior on scale {
                            NumberAnimation {
                                duration: 350
                                easing.type: Easing.InOutCubic
                            }
                        }

                        Repeater {
                            model: [2, 4, 8]
                            delegate: RippleButton {
                                required property var modelData
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: {
                                    root.currentLineWidth = Number(modelData);
                                    root.lineWidthPopupVisible = false;
                                }
                                contentItem: Item {
                                    anchors.fill: parent
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 16
                                        height: Number(modelData)
                                        color: Appearance.colors.colOnLayer1
                                        radius: Number(modelData) / 2
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Color Picker Accordion
        Item {
            id: colorSelectorContainer
            implicitWidth: colorRow.implicitWidth
            implicitHeight: 32

            Row {
                id: colorRow
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                RippleButton {
                    id: colorPickerBtn
                    implicitWidth: 36
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.normal
                    toggled: root.colorPopupVisible
                    onClicked: {
                        root.colorPopupVisible = !root.colorPopupVisible;
                        if (root.colorPopupVisible) {
                            root.lineWidthPopupVisible = false;
                            root.shapePopupVisible = false;
                        }
                    }
                    contentItem: Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: width / 2
                        color: root.currentColor
                        border.width: 1
                        border.color: Appearance.colors.colOutline
                    }

                    StyledToolTip {
                        z: 9999
                        text: Translation.tr("Color")
                    }
                }

                Item {
                    id: colorCollapsible
                    implicitHeight: 32
                    clip: true
                    implicitWidth: root.colorPopupVisible ? colorExpandedRow.implicitWidth : 0
                    opacity: root.colorPopupVisible ? 1 : 0

                    Behavior on implicitWidth {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.InOutCubic
                        }
                    }

                    Row {
                        id: colorExpandedRow
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        scale: root.colorPopupVisible ? 1 : 0.9

                        Behavior on scale {
                            NumberAnimation {
                                duration: 350
                                easing.type: Easing.InOutCubic
                            }
                        }

                        Repeater {
                            model: root.presetColors
                            delegate: RippleButton {
                                required property color modelData
                                implicitWidth: 24
                                implicitHeight: 24
                                buttonRadius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: {
                                    root.currentColor = modelData;
                                    root.colorPopupVisible = false;
                                }
                                contentItem: Rectangle {
                                    anchors.fill: parent
                                    radius: parent.buttonRadius
                                    color: modelData
                                    border.width: 1
                                    border.color: Appearance.colors.colOutline
                                }
                            }
                        }
                    }
                }
            }
        }

        // Undo
        IconToolbarButton {
            text: "undo"
            enabled: root.undoStack.length > 0
            onClicked: root.undo()
            StyledToolTip {
                z: 9999
                text: Translation.tr("Undo")
            }
        }

        // Copy
        IconToolbarButton {
            text: "content_copy"
            onClicked: root.finalizeScreenshot(false)
            StyledToolTip {
                z: 9999
                text: Translation.tr("Copy to clipboard")
            }
        }

        // Save
        IconToolbarButton {
            text: "save"
            onClicked: root.finalizeScreenshot(true)
            StyledToolTip {
                z: 9999
                text: Translation.tr("Save to file")
            }
        }
    }

}
