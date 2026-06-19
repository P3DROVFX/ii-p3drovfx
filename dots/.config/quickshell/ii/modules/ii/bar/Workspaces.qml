import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property bool vertical: false
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    readonly property var currentHyprlandMonitorData: HyprlandData.monitors.find(mon => mon.name === root.monitor?.name)
    readonly property bool scratchpadOpen: !!(currentHyprlandMonitorData && currentHyprlandMonitorData.specialWorkspace && currentHyprlandMonitorData.specialWorkspace.name !== "")
    readonly property int scratchpadWindowsCount: HyprlandData.windowList.filter(win => win.workspace && win.workspace.name && win.workspace.name.startsWith("special")).length

    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: root.QsWindow.window && root.QsWindow.window.screen ? Quickshell.screens.indexOf(root.QsWindow.window.screen) : 0
    property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0

    property var shapesList: ["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]
    property string currentRandomShape: "Circle"
    property real randomRotation: 0

    readonly property real stableActivePosition: {
        let basePos = root.visibleActiveIndex * root.iconBoxWrapperSize;
        let offset = activeIndicator ? activeIndicator.offsetFor(root.workspaceIndexInGroup) : 0;
        let inset = Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? (root.iconBoxWrapperSize - root.individualIconBoxHeight) / 2 : (activeIndicator ? activeIndicator.visualInset : 0);
        return basePos + offset + inset;
    }
    property real animatedStablePosition: stableActivePosition
    Behavior on animatedStablePosition {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutBack
        }
    }

    function updateRandomShape() {
        if (!Config.options.bar.workspaces.useRandomShapeForActiveIndicator)
            return;
        let nextShape = currentRandomShape;
        let attempts = 0;
        while (nextShape === currentRandomShape && attempts < 10) {
            let randIdx = Math.floor(Math.random() * shapesList.length);
            nextShape = shapesList[randIdx];
            attempts++;
        }
        currentRandomShape = nextShape;
        randomRotation = randomRotation + 90;
    }

    onEffectiveActiveWorkspaceIdChanged: {
        updateRandomShape();
    }

    readonly property int workspacesShown: {
        if (useWorkspaceMap && workspaceMap.length > monitorIndex) {
            let start = workspaceMap[monitorIndex];
            let end = (monitorIndex + 1 < workspaceMap.length) ? workspaceMap[monitorIndex + 1] : (start + Config.options.bar.workspaces.shown);
            return dynamicWorkspaces ? (end - start) : Config.options.bar.workspaces.shown;
        }
        return Config.options.bar.workspaces.shown;
    }
    readonly property int workspaceGroup: {
        let activeId = monitor?.activeWorkspace?.id;
        if (!activeId) return 0;
        if (activeId <= workspaceOffset) return 0;
        if (useWorkspaceMap && workspaceMap.length > monitorIndex + 1) {
            let nextMonitorStart = workspaceMap[monitorIndex + 1];
            if (activeId > nextMonitorStart) return 0;
        }
        let group = Math.floor((activeId - workspaceOffset - 1) / workspacesShown);
        return Math.max(0, group);
    }
    property list<bool> workspaceOccupied: []
    property int workspaceIndexInGroup: {
        let activeId = monitor?.activeWorkspace?.id;
        if (!activeId) return -1;
        let startWs = workspaceOffset + workspaceGroup * workspacesShown + 1;
        let endWs = workspaceOffset + (workspaceGroup + 1) * workspacesShown;
        if (activeId >= startWs && activeId <= endWs) {
            return activeId - startWs;
        }
        return -1;
    }
    property var monitorWindows
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? (workspaceOffset + 1)

    property int individualIconBoxHeight: 22
    property int iconBoxWrapperSize: 26
    property int workspaceDotSize: 4
    property real iconRatio: 0.8
    property bool showIcons: Config.options.bar.workspaces.showAppIcons

    readonly property bool isScrollingLayout: Persistent.ready && Persistent.states.hyprland && Persistent.states.hyprland.layout === "scrolling"
    property int maxWindowCount: isScrollingLayout ? Config.options.bar.workspaces.maxWindowCount : 1

    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    function isWorkspaceVisible(wsIndex) {
        const wsId = workspaceGroup * workspacesShown + wsIndex + 1 + workspaceOffset;
        const isActive = wsId === effectiveActiveWorkspaceId;
        const isOccupied = workspaceOccupied[wsIndex];
        return !dynamicWorkspaces || isActive || (isOccupied || false);
    }

    readonly property int visibleActiveIndex: {
        if (!dynamicWorkspaces)
            return workspaceIndexInGroup;
        let count = 0;
        for (let i = 0; i < workspacesShown; i++) {
            if (i === workspaceIndexInGroup)
                return count;
            if (isWorkspaceVisible(i))
                count++;
        }
        return count;
    }

    property bool showNumbersByMs: false
    Timer {
        id: showNumbersTimer
        interval: (Config.options.bar.workspaces.showNumberDelay ?? 100)
        repeat: false
        onTriggered: {
            root.showNumbersByMs = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                return;
            if (GlobalStates.superDown)
                showNumbersTimer.restart();
            else {
                showNumbersTimer.stop();
                root.showNumbersByMs = false;
            }
        }
        function onSuperReleaseMightTriggerChanged() {
            showNumbersTimer.stop();
        }
    }

    function updateWorkspaceOccupied() {
        workspaceOccupied = Array.from({
            length: root.workspacesShown
        }, (_, i) => {
            const wsId = workspaceGroup * root.workspacesShown + i + 1 + root.workspaceOffset;
            return Hyprland.workspaces.values.some(ws => ws.id === wsId);
        });
    }

    function hasWindowsInWorkspace(workspaceId) {
        return HyprlandData.windowList.some(w => w.workspace.id === workspaceId);
    }

    function getWindowCountForWorkspace(workspaceId) {
        return HyprlandData.windowList.filter(w => w.workspace.id === workspaceId && !w.floating).length;
    }

    function updateMonitorWindows() {
        const windowsOnMonitor = HyprlandData.windowList.filter(win => win.monitor === root.monitorIndex && !win.floating);
        windowsOnMonitor.sort((a, b) => a.at[0] - b.at[0]);
        root.monitorWindows = windowsOnMonitor.map(win => ({
                    icon: Quickshell.iconPath(AppSearch.guessIcon(win?.class), "image-missing"),
                    workspace: win.workspace?.id
                }));
    }

    // Window list updates
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            root.updateMonitorWindows();
        }
    }

    Connections {
        target: TaskbarApps
        function onIconThemeRevisionChanged() {
            root.updateMonitorWindows();
        }
    }

    // Occupied workspace updates
    Component.onCompleted: {
        updateWorkspaceOccupied();
    }
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateWorkspaceOccupied();
        }
    }
    onWorkspaceGroupChanged: {
        updateWorkspaceOccupied();
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : contentLayout.implicitWidth
    implicitHeight: root.vertical ? contentLayout.implicitHeight : Appearance.sizes.baseBarHeight

    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // Active workspace indicator
    Loader {
        id: activeIndicator
        z: 2
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

        function offsetFor(index) {
            let y = 0;
            if (contentLayout && contentLayout.children) {
                let limit = Math.min(index, contentLayout.children.length);
                for (let i = 0; i < limit; i++) {
                    const item = contentLayout.children[i];
                    if (item) {
                        y += root.vertical ? item.height - baseHeight : item.width - baseHeight;
                    }
                }
            }
            return y;
        }

        function getWindowCount(workspaceId) {
            return HyprlandData.windowList.filter(w => w.workspace.id === workspaceId && !w.floating).length;
        }

        property int index: root.workspaceIndexInGroup
        property int baseHeight: root.iconBoxWrapperSize
        property int windowCount: index < 0 ? 0 : getWindowCount(index + root.workspaceOffset + root.workspaceGroup * root.workspacesShown + 1)

        property bool isEmptyWorkspace: windowCount === 0
        property bool isOneWindow: windowCount === 1

        property real indicatorInsetEmpty: root.iconBoxWrapperSize * 0.07
        property real indicatorInsetOneWindow: root.iconBoxWrapperSize * 0.14
        property real indicatorInset: root.iconBoxWrapperSize * 0.1

        property real visualInset: {
            if (!root.showIcons)
                return indicatorInsetEmpty - 0.5;
            if (isEmptyWorkspace)
                return indicatorInsetEmpty;
            if (isOneWindow)
                return indicatorInsetOneWindow;
            return indicatorInset;
        }

        AnimatedTabIndexPair {
            id: idxPair
            index: Math.max(0, root.visibleActiveIndex)
            easingType: Easing.OutBack
            easingOvershoot: 1.7
            idx1Duration: 250
            idx2Duration: 350
        }

        property real pairMin: Math.min(idxPair.idx1, idxPair.idx2)
        property real pairAbs: Math.abs(idxPair.idx1 - idxPair.idx2)

        property real currentItemOffset: {
            if (root.workspaceIndexInGroup < 0 || !contentLayout || !contentLayout.children || root.workspaceIndexInGroup >= contentLayout.children.length)
                return 0;
            const item = contentLayout.children[root.workspaceIndexInGroup];
            const itemSize = root.vertical ? item?.height : item?.width;
            return (itemSize ?? root.iconBoxWrapperSize) - baseHeight;
        }

        readonly property real accumulatedPreviousOffsets: offsetFor(root.workspaceIndexInGroup + 1)

        readonly property real baseIndicatorPosition: pairMin * root.iconBoxWrapperSize
        readonly property real baseIndicatorLength: (pairAbs + 1) * root.iconBoxWrapperSize

        property real indicatorPosition: baseIndicatorPosition + accumulatedPreviousOffsets - currentItemOffset + visualInset
        property real indicatorLength: baseIndicatorLength + currentItemOffset - visualInset * 2

        y: root.vertical ? (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? root.animatedStablePosition : indicatorPosition) : 0
        x: root.vertical ? 0 : (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? root.animatedStablePosition : indicatorPosition)
        width: root.vertical ? individualIconBoxHeight : (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? individualIconBoxHeight : indicatorLength)
        height: root.vertical ? (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? individualIconBoxHeight : indicatorLength) : individualIconBoxHeight

        opacity: root.scratchpadOpen || root.workspaceIndexInGroup < 0 ? 0.0 : 1.0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        sourceComponent: (Config.options.bar.workspaces.useMaterialShapeForActiveIndicator || Config.options.bar.workspaces.useRandomShapeForActiveIndicator) ? materialShapeComponent : rectangleComponent

        Component {
            id: rectangleComponent
            Rectangle {
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
            }
        }

        Component {
            id: materialShapeComponent
            MaterialShape {
                anchors.fill: parent
                transformOrigin: Item.Center
                shapeString: Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? root.currentRandomShape : Config.options.bar.workspaces.activeIndicatorShape
                color: Appearance.colors.colPrimary
                opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                rotation: Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? root.randomRotation : 0
                Behavior on rotation {
                    RotationAnimation {
                        duration: 350
                        direction: RotationAnimation.Clockwise
                        easing.type: Easing.OutBack
                    }
                }
            }
        }
    }

    Rectangle { // NOTE: we still dont have an unhover animation
        id: hoverIndicator
        z: 2
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

        color: "transparent"
        radius: Appearance.rounding.full

        visible: interactionMouseArea.containsMouse
        opacity: visible ? 1 : 0

        property int hoverIdx: interactionMouseArea.hoverIndex
        property bool wasVisible: false

        onVisibleChanged: { // we disable the animations on first contact, then enable it
            if (visible && !wasVisible) {
                positionBehavior.enabled = false;
                lengthBehavior.enabled = false;

                Qt.callLater(function () {
                    positionBehavior.enabled = true;
                    lengthBehavior.enabled = true;
                });
            }
            wasVisible = visible;
        }

        function offsetFor(index) {
            let y = 0;
            for (let i = 0; i < index; i++) {
                const item = contentLayout.children[i];
                y += root.vertical ? item?.height - root.iconBoxWrapperSize : item?.width - root.iconBoxWrapperSize;
            }
            return y;
        }

        property real currentItemOffset: {
            const item = contentLayout.children[hoverIdx];
            const itemSize = root.vertical ? item?.height : item?.width;
            return itemSize - root.iconBoxWrapperSize;
        }

        readonly property real accumulatedPreviousOffsets: offsetFor(hoverIdx)

        property real indicatorPosition: hoverIdx * root.iconBoxWrapperSize + accumulatedPreviousOffsets + root.iconBoxWrapperSize * 0.05
        property real indicatorLength: root.iconBoxWrapperSize + currentItemOffset - root.iconBoxWrapperSize * 0.1

        y: root.vertical ? indicatorPosition : 0
        x: root.vertical ? 0 : indicatorPosition
        implicitHeight: root.vertical ? indicatorLength : individualIconBoxHeight
        implicitWidth: root.vertical ? individualIconBoxHeight : indicatorLength

        Behavior on indicatorPosition {
            id: positionBehavior
            animation: Appearance.animation.elementMove.numberAnimation.createObject(hoverIndicator)
        }
        Behavior on indicatorLength {
            id: lengthBehavior
            animation: Appearance.animation.elementMove.numberAnimation.createObject(hoverIndicator)
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(hoverIndicator)
        }

        HoverOverlay {
            hover: interactionMouseArea.containsMouse
        }
    }

    MouseArea {
        id: interactionMouseArea
        z: 4
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.RightButton | Qt.LeftButton | Qt.BackButton

        property int hoverIndex: {
            const position = root.vertical ? mouseY : mouseX;
            let accumulated = 0;

            // calculating the every workspace's length
            for (let i = 0; i < root.workspacesShown; i++) {
                const item = contentLayout.children[i];
                if (!item)
                    continue;

                const itemSize = root.vertical ? item.height : item.width;

                if (position < accumulated + itemSize) {
                    return i;
                }

                accumulated += itemSize;
            }

            return root.workspacesShown - 1;
        }

        onPressed: event => {
            if (event.button === Qt.RightButton) {
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            }
            if (event.button === Qt.BackButton) {
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
            }
            if (event.button === Qt.LeftButton) {
                const wsId = workspaceOffset + workspaceGroup * workspacesShown + hoverIndex + 1;
                Hyprland.dispatch(`hl.dsp.focus({ workspace = "${wsId}" })`);
            }
        }

        onWheel: event => {
            event.accepted = true;
            if (dynamicWorkspaces) {
                if (event.angleDelta.y < 0)
                    Hyprland.dispatch("hl.dsp.focus({workspace = 'r+1'})");
                else if (event.angleDelta.y > 0)
                    Hyprland.dispatch("hl.dsp.focus({workspace = 'r-1'})");
            } else {
                let nextId = effectiveActiveWorkspaceId + (event.angleDelta.y < 0 ? 1 : -1);
                const minId = workspaceOffset + workspaceGroup * workspacesShown + 1;
                const maxId = workspaceOffset + (workspaceGroup + 1) * workspacesShown;
                if (nextId < minId || nextId > maxId)
                    return;
                Hyprland.dispatch("hl.dsp.focus({ workspace = '" + nextId + "' })");
            }
        }
    }

    StyledRectangle {
        id: occupiedIndicatorsBg
        anchors.fill: occupiedIndicatorsLayout
        contentLayer: StyledRectangle.ContentLayer.Group
        color: ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.4)
        visible: false
    }

    GridLayout {
        id: occupiedIndicatorsLayout
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
        z: 1

        columns: root.vertical ? 1 : 99
        rows: root.vertical ? 99 : 1

        layer.enabled: true
        visible: false

        Repeater {
            model: root.workspacesShown
            delegate: Item {
                id: wsBg
                Layout.alignment: Qt.AlignCenter

                property int wsId: workspaceGroup * workspacesShown + index + 1 + workspaceOffset
                property bool currentOccupied: (workspaceOccupied[index] || false) && wsId != effectiveActiveWorkspaceId
                property bool previousOccupied: index > 0 && (workspaceOccupied[index - 1] || false) && (wsId - 1) != effectiveActiveWorkspaceId
                property bool nextOccupied: index < workspacesShown - 1 && (workspaceOccupied[index + 1] || false) && (wsId + 1) != effectiveActiveWorkspaceId

                property int windowCount: root.getWindowCountForWorkspace(wsId)

                property real itemSize: {
                    const item = contentLayout.children[index];
                    return root.vertical ? (item?.height ?? root.iconBoxWrapperSize) : (item?.width ?? root.iconBoxWrapperSize);
                }

                implicitWidth: root.vertical ? root.iconBoxWrapperSize : (wsBg.wsVisible ? itemSize : 0)
                implicitHeight: root.vertical ? (wsBg.wsVisible ? itemSize : 0) : root.iconBoxWrapperSize
                property bool wsVisible: root.isWorkspaceVisible(index)

                opacity: root.scratchpadOpen && index !== root.workspaceIndexInGroup ? 0.35 : 1.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Pill {
                    property real stretchAmount: 12 // not using multiplier because it mulitplies multi-windowed workspaces A LOT

                    property real undirectionalWidth: root.iconBoxWrapperSize * wsBg.currentOccupied

                    property real undirectionalLength: {
                        if (!wsBg.currentOccupied)
                            return 0;

                        let baseLength = wsBg.itemSize;

                        if (wsBg.previousOccupied && index > 0) {
                            baseLength += stretchAmount;
                        }

                        if (wsBg.nextOccupied && index < workspacesShown - 1) {
                            baseLength += stretchAmount;
                        }

                        return baseLength;
                    }

                    property real undirectionalOffset: {
                        if (!wsBg.currentOccupied)
                            return 0.5 * root.iconBoxWrapperSize;

                        if (!wsBg.previousOccupied || index === 0)
                            return 0;

                        return -stretchAmount;
                    }

                    anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                    x: root.vertical ? 0 : undirectionalOffset
                    y: root.vertical ? undirectionalOffset : 0
                    implicitWidth: root.vertical ? undirectionalWidth : undirectionalLength
                    implicitHeight: root.vertical ? undirectionalLength : undirectionalWidth

                    Behavior on undirectionalWidth {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on undirectionalLength {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on undirectionalOffset {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    MultiEffect {
        id: occupiedIndicatorsMultiEffect
        z: 1
        anchors.centerIn: parent
        implicitWidth: occupiedIndicatorsLayout.implicitWidth
        implicitHeight: occupiedIndicatorsLayout.implicitHeight
        source: occupiedIndicatorsBg
        maskEnabled: true
        maskSource: occupiedIndicatorsLayout
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
        z: 3

        columns: root.vertical ? 1 : 99
        rows: root.vertical ? 99 : 1

        Repeater {
            id: workspaceRepeater
            model: root.workspacesShown

            delegate: Item {
                id: background
                Layout.alignment: Qt.AlignCenter

                visible: wsVisible
                property bool wsVisible: root.isWorkspaceVisible(index)
                implicitWidth: root.vertical ? root.iconBoxWrapperSize : (Math.max(layout.implicitWidth + 8, root.iconBoxWrapperSize))
                implicitHeight: root.vertical ? (Math.max(layout.implicitHeight + 8, root.iconBoxWrapperSize)) : root.iconBoxWrapperSize

                readonly property bool isShowingScratchpad: root.scratchpadOpen && (index === root.workspaceIndexInGroup)

                opacity: root.scratchpadOpen && !isShowingScratchpad ? 0.35 : 1.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }

                Item {
                    id: normalContentWrapper
                    anchors.fill: parent

                    opacity: background.isShowingScratchpad ? 0.0 : 1.0
                    scale: background.isShowingScratchpad ? 0.8 : 1.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    WorkspaceBackgroundIndicator {
                        workspaceValue: workspaceOffset + workspaceGroup * workspacesShown + index + 1
                        activeWorkspace: monitor?.activeWorkspace?.id === workspaceValue
                    }

                    GridLayout {
                        id: layout
                        anchors.centerIn: parent
                        columnSpacing: 0
                        rowSpacing: 0
                        columns: root.vertical ? 1 : 99
                        rows: root.vertical ? 99 : 1

                        Repeater {
                            property int workspaceIndex: workspaceOffset + workspaceGroup * workspacesShown + index + 1
                            model: root.showIcons ? root.monitorWindows?.filter(win => win.workspace === workspaceIndex).splice(0, Config.options.bar.workspaces.maxWindowCount) : []
                            delegate: Item {
                                id: iconContainer
                                Layout.alignment: Qt.AlignHCenter
                                width: root.individualIconBoxHeight
                                height: root.individualIconBoxHeight

                                layer.enabled: Config.options.appearance.icons.enableShapeMask
                                layer.effect: OpacityMask {
                                    maskSource: iconMask
                                }

                                MaterialShape {
                                    id: iconMask
                                    anchors.fill: parent
                                    shapeString: Config.options.appearance.icons.shapeMask
                                    visible: false
                                }

                                IconImage {
                                    id: mainAppIcon
                                    Layout.alignment: Qt.AlignHCenter
                                    anchors {
                                        left: parent.left
                                        top: parent.top
                                        leftMargin: root.showNumbersByMs ? 15 : 2
                                        topMargin: root.showNumbersByMs ? 15 : 2
                                    }
                                    source: modelData.icon
                                    implicitSize: (root.individualIconBoxHeight * root.iconRatio) * (root.showNumbersByMs ? 1 / 1.5 : 1)

                                    Behavior on anchors.leftMargin {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                    Behavior on anchors.topMargin {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                    Behavior on implicitSize {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }

                                    layer.enabled: Config.options.appearance.icons.enableShapeMask
                                    layer.effect: OpacityMask {
                                        maskSource: iconMask
                                    }
                                }
                                Loader {
                                    active: Config.options.bar.workspaces.monochromeIcons
                                    anchors.fill: mainAppIcon
                                    sourceComponent: Item {
                                        Desaturate {
                                            id: desaturatedIcon
                                            visible: false
                                            anchors.fill: parent
                                            source: mainAppIcon
                                            desaturation: 0.8
                                            layer.enabled: Config.options.appearance.icons.enableShapeMask
                                            layer.effect: OpacityMask {
                                                maskSource: iconMask
                                            }
                                        }
                                        ColorOverlay {
                                            anchors.fill: desaturatedIcon
                                            source: desaturatedIcon
                                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: scratchpadIndicator
                    anchors.centerIn: parent
                    width: root.individualIconBoxHeight + 2
                    height: root.individualIconBoxHeight + 2

                    visible: opacity > 0.0
                    opacity: background.isShowingScratchpad ? 1.0 : 0.0
                    scale: background.isShowingScratchpad ? 1.0 : 0.7

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    // Background shape (colTertiary)
                    MaterialShape {
                        id: shapeContainer
                        anchors.fill: parent
                        shapeString: "Flower"
                        color: Appearance.colors.colTertiary
                    }

                    // Pulse/glowing window representation dots inside the shape
                    Row {
                        anchors.centerIn: parent
                        spacing: 3
                        z: 2
                        Repeater {
                            model: Math.max(1, Math.min(3, root.scratchpadWindowsCount))
                            delegate: Rectangle {
                                width: 4
                                height: 4
                                radius: 2
                                color: Appearance.colors.colOnTertiary
                                opacity: root.scratchpadWindowsCount === 0 ? 0.4 : 1.0

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: root.scratchpadOpen
                                    NumberAnimation {
                                        to: 0.3
                                        duration: 1500
                                        easing.type: Easing.InOutQuad
                                    }
                                    NumberAnimation {
                                        to: root.scratchpadWindowsCount === 0 ? 0.4 : 1.0
                                        duration: 1500
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component HoverOverlay: Rectangle {
        id: hoverOverlay
        anchors.fill: parent

        property bool hover: false

        color: Appearance.colors.colPrimary
        radius: Appearance.rounding.full
        opacity: hover ? 0.1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    component WorkspaceBackgroundIndicator: Rectangle {
        property bool showNumbers: Config.options.bar.workspaces.alwaysShowNumbers || root.showNumbersByMs
        property int workspaceValue
        property bool activeWorkspace
        property color indColor: (activeWorkspace) ? Appearance.m3colors.m3onPrimary : (root.workspaceOccupied[index] ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1Inactive)

        anchors.centerIn: parent
        width: root.workspaceDotSize
        height: width
        radius: width / 2
        visible: layout.implicitHeight + 8 < root.iconBoxWrapperSize || root.showNumbersByMs
        color: !showNumbers ? indColor : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StyledText {
            opacity: showNumbers ? 1 : 0
            anchors.centerIn: parent
            text: Config.options?.bar.workspaces.numberMap[workspaceValue - 1] || workspaceValue
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: indColor
            Behavior on opacity {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
    }
}
