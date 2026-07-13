import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland

Item {
    id: root

    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical

    property bool vertical: false
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)

    readonly property var currentHyprlandMonitorData: HyprlandData.monitors.find(mon => mon.name === root.monitor?.name)
    readonly property bool scratchpadOpen: !!(currentHyprlandMonitorData && currentHyprlandMonitorData.specialWorkspace && currentHyprlandMonitorData.specialWorkspace.name !== "")

    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: {
        if (!monitor || !monitor.name) return 0;
        let idx = HyprlandData.monitors.findIndex(mon => mon.name === monitor.name);
        return idx !== -1 ? idx : 0;
    }
    readonly property int workspaceOffset: useWorkspaceMap ? (workspaceMap.length > monitorIndex ? workspaceMap[monitorIndex] : monitorIndex * 10) : 0

    readonly property int startWsId: {
        if (dynamicWorkspaces) return workspaceOffset + 1;
        let activeVal = root.activeWsId;
        if (activeVal <= workspaceOffset) activeVal = workspaceOffset + 1;
        if (useWorkspaceMap && workspaceMap.length > monitorIndex + 1) {
            let nextMonitorStart = workspaceMap[monitorIndex + 1];
            if (activeVal > nextMonitorStart) activeVal = nextMonitorStart;
        }
        let page = Math.floor((activeVal - workspaceOffset - 1) / workspacesShown);
        return Math.max(0, page) * workspacesShown + 1 + workspaceOffset;
    }

    property var workspaceOccupied: ({})

    function updateOccupied() {
        let occupied = {};
        for (let ws of Hyprland.workspaces.values)
            occupied[ws.id] = true;
        workspaceOccupied = occupied;
    }

    property var workspaceWindows: ({})

    function getWorkspaceIcon(wsId) {
        let windows = root.workspaceWindows[wsId];
        return (windows && windows.length > 0) ? windows[0].icon : "";
    }

    function updateWorkspaceWindows() {
        let windows = {};
        for (let win of HyprlandData.windowList) {
            if (!win.workspace || win.workspace.id < 1) continue;
            if (win.monitor !== root.monitorIndex) continue;
            if (!windows[win.workspace.id]) windows[win.workspace.id] = [];
            if (windows[win.workspace.id].length < 3) {
                windows[win.workspace.id].push({
                    icon: Quickshell.iconPath(AppSearch.guessIcon(win.class), "image-missing"),
                    class: win.class,
                    title: win.title
                });
            }
        }
        root.workspaceWindows = windows;
    }

    readonly property real itemSize: 32
    readonly property real spacing: 4
    readonly property real activeIndicatorSize: 3

    property var visibleWsModel: []
    property string _prevModelKey: ""

    function rebuildModel() {
        let list;
        if (!dynamicWorkspaces) {
            list = Array.from({length: workspacesShown}, (_, i) => startWsId + i);
        } else {
            let l = [];
            for (let ws of Hyprland.workspaces.values) {
                if (ws.id < 1) continue;
                if (useWorkspaceMap) {
                    const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                    if (ws.id < workspaceOffset + 1 || ws.id > nextMonitorStart) continue;
                }
                if (!l.includes(ws.id)) l.push(ws.id);
            }
            if (activeWsId > 0 && !l.includes(activeWsId)) {
                if (useWorkspaceMap) {
                    const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                    if (activeWsId >= workspaceOffset + 1 && activeWsId <= nextMonitorStart) l.push(activeWsId);
                } else {
                    l.push(activeWsId);
                }
            }
            l.sort((a, b) => a - b);
            list = l;
        }
        let key = JSON.stringify(list);
        if (key !== root._prevModelKey) {
            root.visibleWsModel = list;
            root._prevModelKey = key;
        }
    }

    Component.onCompleted: {
        updateOccupied();
        updateWorkspaceWindows();
        rebuildModel();
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateOccupied();
            updateWorkspaceWindows();
            rebuildModel();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateOccupied();
            rebuildModel();
        }
    }
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            updateWorkspaceWindows();
        }
    }
    Connections {
        target: TaskbarApps
        function onIconThemeRevisionChanged() {
            updateWorkspaceWindows();
        }
    }

    onStartWsIdChanged: rebuildModel()

    readonly property real containerSize: Math.max(visibleWsModel.length || workspacesShown, 1) * (itemSize + spacing) - spacing

    implicitWidth: root.vertical ? itemSize + activeIndicatorSize + 6 : containerSize
    implicitHeight: root.vertical ? containerSize : itemSize + activeIndicatorSize + 6

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.elementResize.duration
            easing.type: Appearance.animation.elementResize.type
            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementResize.duration
            easing.type: Appearance.animation.elementResize.type
            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
        }
    }

    Flow {
        id: contentFlow
        anchors.centerIn: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        spacing: root.spacing

        Repeater {
            id: repeater
            model: root.visibleWsModel

            delegate: Item {
                id: wsItem
                required property int index
                required property var modelData

                readonly property int wsId: modelData
                readonly property bool isActive: wsId === root.activeWsId
                readonly property bool isOccupied: root.workspaceOccupied[wsId] ?? false
                readonly property string icon: root.getWorkspaceIcon(wsId)

                opacity: root.scratchpadOpen && !wsItem.isActive ? 0.35 : 1.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                readonly property real iconSize: root.itemSize
                readonly property real indicatorThickness: root.activeIndicatorSize
                readonly property real indicatorLength: wsItem.isActive ? root.itemSize * 0.55 : 0
                readonly property real gap: 1

                implicitWidth: root.vertical ? iconSize + indicatorThickness + gap : iconSize
                implicitHeight: root.vertical ? iconSize : iconSize + indicatorThickness + gap

                Item {
                    id: iconArea
                    x: 0
                    y: 0
                    width: root.vertical ? iconSize : parent.width
                    height: root.vertical ? parent.height : iconSize
                    clip: true

                    Image {
                        id: iconImage
                        anchors.fill: parent
                        anchors.margins: 2
                        source: wsItem.icon
                        sourceSize.width: iconSize * 2
                        sourceSize.height: iconSize * 2
                        fillMode: Image.PreserveAspectCrop
                        visible: wsItem.icon !== "" && wsItem.isOccupied
                        smooth: true

                        layer.enabled: Config.options.appearance.icons.enableShapeMask
                        layer.effect: OpacityMask {
                            maskSource: iconMaskShape
                        }
                    }

                    MaterialShape {
                        id: iconMaskShape
                        anchors.fill: iconImage
                        shapeString: Config.options.appearance.icons.shapeMask
                        visible: false
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: wsItem.isOccupied ? 7 : 5
                        height: width
                        radius: width / 2
                        color: wsItem.isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                        opacity: (wsItem.icon === "" || !wsItem.isOccupied) ? 1.0 : 0

                        Behavior on width {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutQuint
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }
                }

                Rectangle {
                    x: root.vertical ? iconSize + gap : parent.width / 2 - (root.vertical ? indicatorThickness / 2 : indicatorLength / 2)
                    y: root.vertical ? parent.height / 2 - indicatorLength / 2 : iconSize + gap
                    width: root.vertical ? indicatorThickness : indicatorLength
                    height: root.vertical ? indicatorLength : indicatorThickness
                    radius: indicatorThickness / 2
                    color: Appearance.colors.colPrimary

                    Behavior on width {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 4
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.BackButton

        readonly property real itemStep: root.itemSize + root.spacing
        readonly property int hoverWsIndex: {
            let pos = root.vertical ? mouseY : mouseX;
            let idx = Math.floor(pos / itemStep);
            return Math.max(0, Math.min(idx, root.visibleWsModel.length - 1));
        }

        onPressed: event => {
            if (event.button === Qt.RightButton) {
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            } else if (event.button === Qt.BackButton) {
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
            } else if (event.button === Qt.LeftButton) {
                let wsId = root.visibleWsModel[hoverWsIndex];
                if (wsId !== undefined)
                    Hyprland.dispatch("hl.dsp.focus({ workspace = '" + wsId + "' })");
            }
        }

        onWheel: wheel => {
            wheel.accepted = true;
            if (root.dynamicWorkspaces) {
                if (wheel.angleDelta.y > 0) Hyprland.dispatch("hl.dsp.focus({workspace = 'r-1'})");
                else Hyprland.dispatch("hl.dsp.focus({workspace = 'r+1'})");
            } else {
                let nextId = root.activeWsId + (wheel.angleDelta.y > 0 ? -1 : 1);
                if (nextId < 1) return;
                Hyprland.dispatch("hl.dsp.focus({ workspace = '" + nextId + "' })");
            }
        }
    }
}
