import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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
    
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? (workspaceOffset + 1)
    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    // Pagination/Offset logic to match screens/monitor mapping
    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: root.QsWindow.window && root.QsWindow.window.screen ? Quickshell.screens.indexOf(root.QsWindow.window.screen) : 0
    property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0

    property var shapesList: [
        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle",
        "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided",
        "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst",
        "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
    ]
    property string currentRandomShape: "Circle"
    property real randomRotation: 0



    function updateRandomShape() {
        if (!Config.options.bar.workspaces.useRandomShapeForActiveIndicator) return;
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

    onActiveWsIdChanged: {
        updateRandomShape();
    }
    
    // Pagination logic
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
        function onValuesChanged() { updateOccupied() }
    }

    implicitWidth: vertical ? 34 : (mainLayout.implicitWidth + 12)
    implicitHeight: vertical ? (mainLayout.implicitHeight + 12) : 34

    // Helper to get index within the shown workspaces
    function getWsIndex(wsId) {
        if (dynamicWorkspaces) {
            // Find index in the list of visible workspaces
            for (let i = 0; i < visibleWsModel.length; i++) {
                if (visibleWsModel[i] === wsId) return i;
            }
            return 0;
        }
        return (wsId - workspaceOffset - 1) % workspacesShown;
    }

    readonly property var visibleWsModel: {
        if (!dynamicWorkspaces) {
            return Array.from({length: workspacesShown}, (_, i) => startWsId + i);
        }
        let list = [];
        for (let ws of Hyprland.workspaces.values) {
            if (ws.id < 1) continue;
            if (useWorkspaceMap) {
                const nextMonitorStart = workspaceMap[monitorIndex + 1] ?? (workspaceMap[monitorIndex] + workspacesShown);
                if (ws.id < workspaceOffset + 1 || ws.id > nextMonitorStart) {
                    continue;
                }
            }
            if (!list.includes(ws.id)) list.push(ws.id);
        }
        if (activeWsId > 0 && !list.includes(activeWsId)) {
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

    readonly property bool isActiveWsInRange: {
        if (useWorkspaceMap) {
            let start = workspaceOffset + 1;
            let end = useWorkspaceMap && workspaceMap.length > monitorIndex + 1 ? workspaceMap[monitorIndex + 1] : (workspaceOffset + workspacesShown);
            return activeWsId >= start && activeWsId <= end;
        }
        return true;
    }

    // The animated highlight (pill)
    Loader {
        id: tabHighlight
        z: 1
        
        readonly property real dotSize: 18
        readonly property real spacing: 6
        
        function getPosForIndex(i) {
            return i * (dotSize + spacing)
        }
        
        AnimatedTabIndexPair {
            id: idxPair
            index: Math.max(0, root.getWsIndex(activeWsId))
        }
        
        readonly property real animX1: getPosForIndex(idxPair.idx1)
        readonly property real animX2: getPosForIndex(idxPair.idx2)
        
        x: root.vertical ? (parent.width - width) / 2 : (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? (Math.min(animX1, animX2) + mainLayout.x + Math.abs(animX2 - animX1) / 2) : Math.min(animX1, animX2) + (root.vertical ? 0 : mainLayout.x))
        y: root.vertical ? (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? (Math.min(animX1, animX2) + mainLayout.y + Math.abs(animX2 - animX1) / 2) : Math.min(animX1, animX2) + mainLayout.y) : (parent.height - height) / 2
        
        width: root.vertical ? dotSize : (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? dotSize : Math.abs(animX2 - animX1) + dotSize)
        height: root.vertical ? (Config.options.bar.workspaces.useRandomShapeForActiveIndicator ? dotSize : Math.abs(animX2 - animX1) + dotSize) : dotSize

        opacity: root.scratchpadOpen || !root.isActiveWsInRange ? 0.0 : 1.0
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

    GridLayout {
        id: mainLayout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : visibleWsModel.length
        rows: root.vertical ? visibleWsModel.length : 1
        columnSpacing: 6
        rowSpacing: 6

        Repeater {
            model: root.visibleWsModel
            delegate: Rectangle {
                id: dot
                required property int index
                required property var modelData
                readonly property int wsId: modelData
                readonly property bool isActive: wsId === root.activeWsId
                readonly property bool isOccupied: root.workspaceOccupied[wsId] ?? false

                readonly property bool isShowingScratchpad: root.scratchpadOpen && isActive

                opacity: root.scratchpadOpen && !isShowingScratchpad ? 0.35 : 1.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                
                width: 18
                height: 18
                radius: Appearance.rounding.full
                color: "transparent"
                z: 2 // Above the highlight

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }
                
                Item {
                    id: normalContentWrapper
                    anchors.fill: parent

                    opacity: dot.isShowingScratchpad ? 0.0 : 1.0
                    scale: dot.isShowingScratchpad ? 0.8 : 1.0

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

                    Rectangle {
                        anchors.centerIn: parent
                        width: isOccupied ? 8 : 4
                        height: width
                        radius: width / 2
                        color: {
                            if (isActive) return "transparent";
                            if (hover.hovered) return Appearance.colors.colPrimary;
                            return isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant;
                        }
                        opacity: (isOccupied || hover.hovered) ? 1.0 : 0.4

                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: isActive ? "-" : (dot.wsId).toString()
                        font.pixelSize: isActive ? 14 : 10
                        font.weight: isActive ? Font.Bold : Font.Normal
                        font.family: Appearance.font.family.numbers
                        color: Appearance.colors.colOnPrimary
                        opacity: isActive ? 1.0 : 0.0

                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }

                Item {
                    id: scratchpadIndicator
                    anchors.fill: parent

                    visible: opacity > 0.0
                    opacity: dot.isShowingScratchpad ? 1.0 : 0.0
                    scale: dot.isShowingScratchpad ? 1.0 : 0.7

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

                    Rectangle {
                        id: scratchpadIndicatorBg
                        anchors.fill: parent
                        radius: width / 2
                        color: Appearance.colors.colLayer4

                        Shape {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.smooth: true

                            ShapePath {
                                strokeColor: Appearance.colors.colTertiary
                                strokeWidth: 1.5
                                strokeStyle: ShapePath.DashLine
                                dashPattern: [3, 3]
                                fillColor: "transparent"

                                PathAngleArc {
                                    centerX: scratchpadIndicatorBg.width / 2
                                    centerY: scratchpadIndicatorBg.height / 2
                                    radiusX: scratchpadIndicatorBg.width / 2 - 0.75
                                    radiusY: scratchpadIndicatorBg.height / 2 - 0.75
                                    startAngle: 0
                                    sweepAngle: 360
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + dot.wsId + "' })")
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.BackButton
        onWheel: (wheel) => {
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
        onClicked: event => {
            if (event.button === Qt.RightButton)
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        onPressed: event => {
            if (event.button === Qt.BackButton)
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
        }
    }
}
