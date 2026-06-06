import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)

    readonly property var currentHyprlandMonitorData: HyprlandData.monitors.find(mon => mon.name === root.monitor?.name)
    readonly property bool scratchpadOpen: !!(currentHyprlandMonitorData && currentHyprlandMonitorData.specialWorkspace && currentHyprlandMonitorData.specialWorkspace.name !== "")

    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1
    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    // Pagination/Offset logic to match screens/monitor mapping
    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: root.QsWindow.window && root.QsWindow.window.screen ? Quickshell.screens.indexOf(root.QsWindow.window.screen) : 0
    property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0

    readonly property int startWsId: {
        if (dynamicWorkspaces) return workspaceOffset + 1;
        let activeVal = activeWsId;
        if (activeVal <= workspaceOffset) activeVal = workspaceOffset + 1;
        if (useWorkspaceMap && workspaceMap.length > monitorIndex + 1) {
            let nextMonitorStart = workspaceMap[monitorIndex + 1];
            if (activeVal > nextMonitorStart) activeVal = nextMonitorStart;
        }
        let page = Math.floor((activeVal - workspaceOffset - 1) / workspacesShown);
        return Math.max(0, page) * workspacesShown + 1 + workspaceOffset;
    }

    // Sizing system responsive to the bar size (padding, thickness, and diameters)
    readonly property real barDimension: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight
    readonly property real containerThickness: Math.max(16, barDimension - 16)
    readonly property real shapeDiameter: Math.max(6, containerThickness - 10)
    // Compact pill size (2x the diameter of a circle)
    readonly property real pillLength: shapeDiameter * 2

    property var workspaceOccupied: ({})

    function updateOccupied() {
        let occupied = {};
        for (let ws of Hyprland.workspaces.values) {
            occupied[ws.id] = true;
        }
        workspaceOccupied = occupied;
    }

    Component.onCompleted: updateOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateOccupied();
        }
    }

    readonly property var visibleWsModel: {
        if (!dynamicWorkspaces) {
            return Array.from({
                length: workspacesShown
            }, (_, i) => startWsId + i);
        }
        let list = [];
        for (let ws of Hyprland.workspaces.values) {
            // Ignore special/scratchpad workspaces with negative or 0 IDs
            if (ws.id < 1)
                continue;

            // Only show workspaces belonging to this monitor if using workspace maps
            if (useWorkspaceMap) {
                const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                if (ws.id < workspaceOffset + 1 || ws.id > nextMonitorStart) {
                    continue;
                }
            }
            if (!list.includes(ws.id))
                list.push(ws.id);
        }
        if (activeWsId > 0 && !list.includes(activeWsId)) {
            // Check if activeWsId falls within this monitor's range
            if (useWorkspaceMap) {
                const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                if (activeWsId >= workspaceOffset + 1 && activeWsId <= nextMonitorStart) {
                    list.push(activeWsId);
                }
            } else {
                list.push(activeWsId);
            }
        }
        list.sort((a, b) => a - b);
        return list;
    }

    // Number pressing/holding Super key logic
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
    readonly property bool showNumbers: Config.options.bar.workspaces.alwaysShowNumbers || root.showNumbersByMs

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : container.implicitWidth
    implicitHeight: vertical ? container.implicitHeight : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutQuint
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutQuint
        }
    }

    // Handle scroll wheel anywhere on the widget to switch workspaces
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            wheel.accepted = true;
            if (dynamicWorkspaces) {
                if (wheel.angleDelta.y > 0)
                    Hyprland.dispatch("hl.dsp.focus({workspace = 'r-1'})");
                else
                    Hyprland.dispatch("hl.dsp.focus({workspace = 'r+1'})");
            } else {
                let nextId = activeWsId + (wheel.angleDelta.y > 0 ? -1 : 1);
                if (nextId < 1)
                    return;
                // Bound check if using workspace maps
                if (useWorkspaceMap) {
                    const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                    if (nextId < workspaceOffset + 1 || nextId > nextMonitorStart)
                        return;
                }
                Hyprland.dispatch("hl.dsp.focus({ workspace = '" + nextId + "' })");
            }
        }
    }

    Rectangle {
        id: container
        anchors.centerIn: parent

        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)
        radius: vertical ? width / 2 : height / 2

        implicitWidth: vertical ? containerThickness : (listView.contentWidth + 16)
        implicitHeight: vertical ? (listView.contentHeight + 16) : containerThickness

        Behavior on implicitWidth {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuint
            }
        }
        Behavior on implicitHeight {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuint
            }
        }

        ListView {
            id: listView
            anchors.centerIn: parent

            // Align dimensions to exactly wrap the child delegates
            width: root.vertical ? shapeDiameter : contentWidth
            height: root.vertical ? contentHeight : shapeDiameter

            orientation: root.vertical ? ListView.Vertical : ListView.Horizontal
            model: root.visibleWsModel
            spacing: 8
            interactive: false
            boundsBehavior: Flickable.StopAtBounds

            // Entry transition (fade and scale in)
            add: Transition {
                NumberAnimation {
                    property: "scale"
                    from: 0
                    to: 1.0
                    duration: 250
                    easing.type: Easing.OutQuint
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1.0
                    duration: 250
                }
            }

            // Exit transition (fade and scale out)
            remove: Transition {
                NumberAnimation {
                    property: "scale"
                    to: 0
                    duration: 250
                    easing.type: Easing.OutQuint
                }
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: 250
                }
            }

            // Smoothly slide remaining items when layout changes
            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 250
                    easing.type: Easing.OutQuint
                }
            }

            // Smoothly slide items when they are reordered in the model
            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 250
                    easing.type: Easing.OutQuint
                }
            }

            delegate: Item {
                id: wsDelegate
                required property int index
                required property var modelData
                readonly property int wsId: modelData
                readonly property bool isActive: wsId === root.activeWsId
                readonly property bool isOccupied: root.workspaceOccupied[wsId] ?? false
                readonly property bool isShowingScratchpad: root.scratchpadOpen && isActive

                readonly property real targetWidth: root.vertical ? shapeDiameter : (isActive ? pillLength : shapeDiameter)
                readonly property real targetHeight: root.vertical ? (isActive ? pillLength : shapeDiameter) : shapeDiameter

                width: targetWidth
                height: targetHeight

                Behavior on width {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutQuint
                    }
                }
                Behavior on height {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutQuint
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                    id: innerShape
                    anchors.fill: parent
                    radius: root.vertical ? (width / 2) : (height / 2)

                    color: {
                        if (isActive) {
                            if (isShowingScratchpad) {
                                return hover.hovered ? Appearance.colors.colTertiaryHover : Appearance.colors.colTertiary;
                            } else {
                                return hover.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary;
                            }
                        }
                        if (hover.hovered) {
                            let baseColor = isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant;
                            let mixTarget = root.scratchpadOpen ? Appearance.colors.colTertiary : Appearance.colors.colPrimary;
                            return ColorUtils.mix(baseColor, mixTarget, 0.25);
                        }
                        return isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant;
                    }

                    opacity: {
                        if (isActive)
                            return 1.0;
                        if (root.scratchpadOpen)
                            return hover.hovered ? 0.5 : 0.25;
                        if (hover.hovered)
                            return 0.9;
                        return isOccupied ? 0.7 : 0.4;
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: (Config.options?.bar.workspaces.numberMap[wsDelegate.wsId - 1] || wsDelegate.wsId).toString()
                        font.pixelSize: Math.max(7, shapeDiameter - 4)
                        font.weight: isActive ? Font.Bold : Font.Normal
                        font.family: Appearance.font.family.numbers
                        color: {
                            if (isActive) {
                                return isShowingScratchpad ? Appearance.colors.colOnTertiary : Appearance.colors.colOnPrimary;
                            }
                            return isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant;
                        }
                        opacity: root.showNumbers ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        Hyprland.dispatch("hl.dsp.focus({ workspace = '" + wsDelegate.wsId + "' })");
                    }
                }
            }
        }
    }
}
