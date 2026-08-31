pragma ComponentBehavior: Bound

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
    property bool activated: false
    property color onActivatedColor: Appearance.colors.colOnPrimary
    property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0
    property var workspaceOccupied: ({})
    property bool showNumbersByMs: false
    property real blur: scratchpadOpen ? 1 : 0

    // ── Monitor State ─────────────────────────────────────────────────────────
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property var currentHyprlandMonitorData: HyprlandData.monitors.find(mon => mon.name === root.monitor?.name)
    readonly property bool scratchpadOpen: !!(currentHyprlandMonitorData && currentHyprlandMonitorData.specialWorkspace && currentHyprlandMonitorData.specialWorkspace.name !== "")

    // ── Workspace Config ──────────────────────────────────────────────────────
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1
    readonly property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamicWorkspaces

    // ── Pagination / Monitor Offset ───────────────────────────────────────────
    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: root.QsWindow.window && root.QsWindow.window.screen ? Quickshell.screens.indexOf(root.QsWindow.window.screen) : 0
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

    // ── Sizing ────────────────────────────────────────────────────────────────
    readonly property real barDimension: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight
    readonly property real containerThickness: Math.max(16, barDimension - 16)
    readonly property real shapeDiameter: Math.max(6, containerThickness - 5)
    readonly property real pillLength: shapeDiameter * 1.5

    // ── Computed Model ────────────────────────────────────────────────────────
    // Stable model — only updates when content actually changes,
    // NOT when activeWsId changes within the same page.
    // This prevents ListView from recreating delegates on every workspace switch,
    // allowing Behavior on width/height to animate smoothly.
    property var visibleWsModel: []
    property string _prevModelKey: ""
    function rebuildModel() {
        let list;
        if (!dynamicWorkspaces) {
            list = Array.from({ length: workspacesShown }, (_, i) => startWsId + i);
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
    readonly property bool numbersByInteractionVisible: showNumbersByMs && !GlobalStates.screenLocked && !GlobalStates.workspaceRestoreInProgress
    readonly property bool showNumbers: !GlobalStates.screenLocked && !GlobalStates.workspaceRestoreInProgress
        && (Config.options.bar.workspaces.alwaysShowNumbers || root.numbersByInteractionVisible)

    // ── Implicit Size ─────────────────────────────────────────────────────────
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : container.implicitWidth
    implicitHeight: vertical ? container.implicitHeight : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    Behavior on blur {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // ── Functions ─────────────────────────────────────────────────────────────
    function getWsIndex(wsId) {
        if (!root.visibleWsModel) return 0;
        for (let i = 0; i < root.visibleWsModel.length; i++) {
            if (root.visibleWsModel[i] === wsId) return i;
        }
        return 0;
    }

    function updateOccupied() {
        let occupied = {};
        for (let ws of Hyprland.workspaces.values) {
            occupied[ws.id] = true;
        }
        workspaceOccupied = occupied;
    }

    // ── Color Resolvers ────────────────────────────────────────────────────────
    function resolveCircleColor(isActive, isShowingScratchpad, hovered, isOccupied) {
        if (isActive) {
            if (isShowingScratchpad)
                return hovered ? Appearance.colors.colTertiaryHover : Appearance.colors.colTertiary;
            return hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary;
        }
        if (hovered) {
            let baseColor = isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant;
            let mixTarget = scratchpadOpen ? Appearance.colors.colTertiary : Appearance.colors.colPrimary;
            return ColorUtils.mix(baseColor, mixTarget, 0.25);
        }
        return isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant;
    }
    function resolveCircleOpacity(isActive, isShowingScratchpad, hovered, isOccupied) {
        if (isActive) return 1.0;
        if (scratchpadOpen) return hovered ? 0.5 : 0.15;
        if (hovered) return 0.9;
        return isOccupied ? 0.7 : 0.2;
    }
    function resolveTextColor(isActive, isShowingScratchpad, isOccupied) {
        if (isActive)
            return isShowingScratchpad ? Appearance.colors.colOnTertiary : Appearance.colors.colOnPrimary;
        return isOccupied ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant;
    }

    // ── Connections / Signals ─────────────────────────────────────────────────
    Component.onCompleted: {
        updateOccupied();
        rebuildModel();
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateOccupied();
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

    onStartWsIdChanged: rebuildModel()

    Timer {
        id: showNumbersTimer
        interval: (Config.options.bar.workspaces.showNumberDelay ?? 100)
        repeat: false
        onTriggered: { root.showNumbersByMs = true; }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
            if (GlobalStates.superDown)
                showNumbersTimer.restart();
            else {
                showNumbersTimer.stop();
                root.showNumbersByMs = false;
            }
        }
        function onSuperReleaseMightTriggerChanged() { showNumbersTimer.stop(); }
    }

    // ── Content container that blurs/dims when scratchpad is open ─────────────
    Item {
        id: contentContainer
        anchors.fill: parent
        z: 0
        opacity: root.scratchpadOpen ? 0.65 : 1
        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: root.blur
        }

    // ── Mouse Area (wheel only, right-click/back removed) ────────────────────
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            wheel.accepted = true;
            if (root.dynamicWorkspaces) {
                if (wheel.angleDelta.y > 0)
                    Hyprland.dispatch("hl.dsp.focus({workspace = 'r-1'})");
                else
                    Hyprland.dispatch("hl.dsp.focus({workspace = 'r+1'})");
            } else {
                let nextId = root.activeWsId + (wheel.angleDelta.y > 0 ? -1 : 1);
                if (nextId < 1) return;
                if (root.useWorkspaceMap) {
                    const nextMonitorStart = root.workspaceMap[root.monitorIndex + 1] ?? (root.workspaceMap[root.monitorIndex] + root.workspacesShown);
                    if (nextId < root.workspaceOffset + 1 || nextId > nextMonitorStart) return;
                }
                Hyprland.dispatch("hl.dsp.focus({ workspace = '" + nextId + "' })");
            }
        }
    }

    // ── Container Pill ────────────────────────────────────────────────────────
    Rectangle {
        id: container
        anchors.centerIn: parent

        color: "transparent"
        radius: vertical ? width / 2 : height / 2

        implicitWidth: vertical ? containerThickness : (listView.contentWidth + 10)
        implicitHeight: vertical ? (listView.contentHeight + 10) : containerThickness

        Behavior on implicitWidth {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }

        ListView {
            id: listView
            anchors.centerIn: parent

            width: root.vertical ? shapeDiameter : contentWidth
            height: root.vertical ? contentHeight : shapeDiameter

            orientation: root.vertical ? ListView.Vertical : ListView.Horizontal
            model: root.visibleWsModel
            spacing: 4
            interactive: false
            boundsBehavior: Flickable.StopAtBounds

            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0; to: 1.0
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
                NumberAnimation {
                    property: root.vertical ? "y" : "x"
                    from: root.vertical ? (listView.height) : (listView.width)
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
            }
            remove: Transition {
                NumberAnimation {
                    property: "scale"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Appearance.animation.elementMoveExit.type
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Appearance.animation.elementMoveExit.type
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
            }
            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
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

                width: root.vertical ? shapeDiameter : (isActive ? pillLength : shapeDiameter)
                height: root.vertical ? (isActive ? pillLength : shapeDiameter) : shapeDiameter

                Behavior on width {
                    animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                }

                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }

                Item {
                    id: normalContentWrapper
                    anchors.fill: parent

                    opacity: wsDelegate.isShowingScratchpad ? 0.0 : 1.0
                    scale: wsDelegate.isShowingScratchpad ? 0.8 : 1.0

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
                        id: innerShape
                        anchors.fill: parent
                        radius: root.vertical ? (width / 2) : (height / 2)

                        color: root.resolveCircleColor(isActive, isShowingScratchpad, hover.hovered, isOccupied)
                        opacity: root.resolveCircleOpacity(isActive, isShowingScratchpad, hover.hovered, isOccupied)

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: (Config.options?.bar.workspaces.numberMap[wsDelegate.wsId - 1] || wsDelegate.wsId).toString()
                            font.pixelSize: Math.max(7, shapeDiameter - 4)
                            font.weight: isActive ? Font.Bold : Font.Normal
                            font.family: Appearance.font.family.numbers

                            color: root.resolveTextColor(isActive, isShowingScratchpad, isOccupied)
                            opacity: root.showNumbers ? 1.0 : 0.0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveSlow.duration
                                    easing.type: Appearance.animation.elementMoveSlow.type
                                    easing.bezierCurve: Appearance.animation.elementMoveSlow.bezierCurve
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                        }
                    }
                }

                readonly property real hitAreaPadding: 6

                MouseArea {
                    anchors.centerIn: parent
                    width: parent.width + hitAreaPadding * 2
                    height: parent.height + hitAreaPadding * 2
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        Hyprland.dispatch("hl.dsp.focus({ workspace = '" + wsDelegate.wsId + "' })");
                    }
                }
            }
        }
    }

        Item {
            id: activePositionHelper
            readonly property real indicatorSize: root.shapeDiameter
            readonly property real pillLen: root.pillLength
            readonly property Item activeItem: listView.contentItem.children[root.getWsIndex(root.activeWsId)]

            x: activeItem ? root.vertical ? (root.width - indicatorSize) / 2 : activeItem.x + listView.x + (activeItem.width - indicatorSize) / 2 : 0
            y: activeItem ? root.vertical ? activeItem.y + listView.y + (activeItem.height - indicatorSize) / 2 : (root.height - indicatorSize) / 2 : 0
            width: root.vertical ? indicatorSize : pillLen
            height: root.vertical ? pillLen : indicatorSize
            visible: false
        }
    }

    Rectangle {
        id: activeOverlay
        z: 10

        x: activePositionHelper.x
        y: activePositionHelper.y
        width: activePositionHelper.width
        height: activePositionHelper.height
        radius: root.vertical ? width / 2 : height / 2

        readonly property bool _show: root.scratchpadOpen && root.activeWsId >= root.workspaceOffset + 1
        color: Appearance.colors.colTertiary
        visible: _show
        opacity: _show ? 1.0 : 0.0
        scale: _show ? 1.0 : 0.7

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

        StyledText {
            anchors.centerIn: parent
            text: (Config.options?.bar.workspaces.numberMap[root.activeWsId - 1] || root.activeWsId).toString()
            font.pixelSize: Math.max(7, root.shapeDiameter - 4)
            font.weight: Font.Bold
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnTertiary
        }
    }
}
