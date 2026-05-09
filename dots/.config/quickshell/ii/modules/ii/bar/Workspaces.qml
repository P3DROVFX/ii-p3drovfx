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

    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: barLoader.monitorIndex
    property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0

    readonly property int workspacesShown: dynamicWorkspaces ? ((workspaceMap[monitorIndex + 1] ?? workspaceMap[monitorIndex] + Config.options.bar.workspaces.shown) - workspaceMap[monitorIndex]) : Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((monitor?.activeWorkspace?.id - root.workspaceOffset - 1) / root.workspacesShown)
    property list<bool> workspaceOccupied: []
    property int workspaceIndexInGroup: (monitor?.activeWorkspace?.id - root.workspaceOffset - 1) % root.workspacesShown
    property var monitorWindows
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1

    property int individualIconBoxHeight: 22
    property int iconBoxWrapperSize: 26
    property int workspaceDotSize: 4
    property real iconRatio: 0.8
    property bool showIcons: Config.options.bar.workspaces.showAppIcons

    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    property int maxWindowCount: isScrollingLayout ? Config.options.bar.workspaces.maxWindowCount : 1

    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    function isWorkspaceVisible(wsIndex) {
        const wsId = workspaceGroup * workspacesShown + wsIndex + 1 + workspaceOffset;
        const isActive = wsId === effectiveActiveWorkspaceId;
        const isOccupied = workspaceOccupied[wsIndex];
        return !dynamicWorkspaces || isActive || isOccupied;
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

    // Window list updates
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            const windowsOnMonitor = HyprlandData.windowList.filter(win => win.monitor === root.monitorIndex && !win.floating);
            windowsOnMonitor.sort((a, b) => a.at[0] - b.at[0]);
            root.monitorWindows = windowsOnMonitor.map(win => ({
                        icon: Quickshell.iconPath(AppSearch.guessIcon(win?.class), "image-missing"),
                        workspace: win.workspace?.id,
                        revision: TaskbarApps.iconThemeRevision // Add revision here for reactivity
                    }));
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
    implicitHeight: root.vertical ? contentLayout.implicitHeight : Appearance.sizes.barHeight

    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // Active workspace indicator
    Rectangle {
        z: 2
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        color: Appearance.colors.colPrimary
        opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
        radius: Appearance.rounding.full

        AnimatedTabIndexPair {
            id: idxPair
            index: root.visibleActiveIndex
        }

        function offsetFor(index) {
            let y = 0;
            for (let i = 0; i < index; i++) {
                const item = contentLayout.children[i];
                y += root.vertical ? item?.height - baseHeight : item?.width - baseHeight;
            }
            return y;
        }

        function getWindowCount(workspaceId) {
            return HyprlandData.windowList.filter(w => w.workspace.id === workspaceId && !w.floating).length;
        }

        property int index: root.workspaceIndexInGroup
        property int baseHeight: root.iconBoxWrapperSize
        property int windowCount: getWindowCount(index + root.workspaceOffset + root.workspaceGroup * root.workspacesShown + 1)

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

        property real pairMin: Math.min(idxPair.idx1, idxPair.idx2)
        property real pairAbs: Math.abs(idxPair.idx1 - idxPair.idx2)

        property real currentItemOffset: {
            const item = contentLayout.children[root.workspaceIndexInGroup];
            const itemSize = root.vertical ? item?.height : item?.width;
            return itemSize - baseHeight;
        }

        readonly property real accumulatedPreviousOffsets: offsetFor(root.workspaceIndexInGroup + 1)

        readonly property real baseIndicatorPosition: pairMin * root.iconBoxWrapperSize
        readonly property real baseIndicatorLength: (pairAbs + 1) * root.iconBoxWrapperSize

        property real indicatorPosition: baseIndicatorPosition + accumulatedPreviousOffsets - currentItemOffset + visualInset
        property real indicatorLength: baseIndicatorLength + currentItemOffset - visualInset * 2

        y: root.vertical ? indicatorPosition : 0
        x: root.vertical ? 0 : indicatorPosition
        implicitHeight: root.vertical ? indicatorLength : individualIconBoxHeight
        implicitWidth: root.vertical ? individualIconBoxHeight : indicatorLength
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
                Hyprland.dispatch(`togglespecialworkspace`);
            }
            if (event.button === Qt.LeftButton) {
                const wsId = workspaceOffset + workspaceGroup * workspacesShown + hoverIndex + 1;
                Hyprland.dispatch(`workspace ${wsId}`);
            }
        }

        onWheel: event => {
            // console.log(event.angleDelta.y)
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`workspace r+1`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`workspace r-1`);
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
                property bool currentOccupied: workspaceOccupied[index] && wsId != effectiveActiveWorkspaceId
                property bool previousOccupied: index > 0 && workspaceOccupied[index - 1] && (wsId - 1) != effectiveActiveWorkspaceId
                property bool nextOccupied: index < workspacesShown - 1 && workspaceOccupied[index + 1] && (wsId + 1) != effectiveActiveWorkspaceId

                property int windowCount: root.getWindowCountForWorkspace(wsId)

                property real itemSize: {
                    const item = contentLayout.children[index];
                    return root.vertical ? (item?.height ?? root.iconBoxWrapperSize) : (item?.width ?? root.iconBoxWrapperSize);
                }

                implicitWidth: root.vertical ? root.iconBoxWrapperSize : (wsBg.wsVisible ? itemSize : 0)
                implicitHeight: root.vertical ? (wsBg.wsVisible ? itemSize : 0) : root.iconBoxWrapperSize
                property bool wsVisible: root.isWorkspaceVisible(index)

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

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
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
                            Layout.alignment: Qt.AlignHCenter
                            width: root.individualIconBoxHeight
                            height: root.individualIconBoxHeight
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

                                // Force reload when theme changes
                                backer.sourceSize: Qt.size(implicitSize + (modelData.revision || 0), implicitSize + (modelData.revision || 0))

                                Behavior on anchors.leftMargin {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on anchors.topMargin {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on implicitSize {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
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
