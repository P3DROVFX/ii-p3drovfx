pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: root

    property bool vertical: BarPlacement.vertical

    BarWidgetPalette {
        id: widgetPalette
        colorMode: Config.options.bar.workspaces.colorMode
    }

    WorkspaceBarModel {
        id: wsModel
        screen: root.QsWindow.window?.screen ?? null
        trackWindows: false
    }

    readonly property bool scratchpadOpen: wsModel.scratchpadOpen
    readonly property int activeWsId: wsModel.activeId
    readonly property int count: wsModel.visibleIds.length
    readonly property real thickness: (root.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 8
    readonly property real pillAlong: Math.max(7, Math.round(root.thickness * 0.28))
    readonly property real activeCross: Math.max(14, Math.round(root.thickness * 0.66))
    readonly property real scratchpadCross: Math.max(16, Math.round(root.thickness * 0.78))
    readonly property real inactiveCross: Math.max(9, Math.round(root.thickness * 0.42))
    readonly property int pillSpacing: 5
    readonly property int sidePadding: 6

    readonly property real rowLength: root.count <= 0
        ? 0
        : (root.count * root.pillAlong
            + (root.count - 1) * root.pillSpacing
            + root.sidePadding * 2)

    readonly property color colInactiveOccupied: ColorUtils.mix(
        Appearance.colors.colOnLayer1,
        Appearance.colors.colLayer1,
        0.55
    )
    readonly property color colInactiveEmpty: ColorUtils.mix(
        Appearance.colors.colOnLayer1,
        Appearance.colors.colLayer1,
        0.34
    )
    readonly property color colInactiveHover: ColorUtils.mix(
        Appearance.colors.colOnLayer1,
        Appearance.colors.colLayer1,
        0.72
    )

    implicitWidth: root.vertical ? root.thickness : root.rowLength
    implicitHeight: root.vertical ? root.rowLength : root.thickness

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.MiddleButton | Qt.BackButton
        onPressed: event => {
            if (event.button === Qt.BackButton || event.button === Qt.MiddleButton)
                wsModel.toggleScratchpad();
            else if (event.button === Qt.RightButton)
                GlobalStates.toggleOverview();
        }
        onWheel: wheel => {
            wheel.accepted = true;
            wsModel.scroll(wheel.angleDelta.y);
        }
    }

    Grid {
        id: pillFlow
        x: root.vertical ? 0 : root.sidePadding
        y: root.vertical ? root.sidePadding : 0
        columns: root.vertical ? 1 : root.count
        rows: root.vertical ? root.count : 1
        spacing: root.pillSpacing

        Repeater {
            model: wsModel.visibleIds

            delegate: Item {
                id: wsDelegate
                required property int index
                required property var modelData

                readonly property int wsId: modelData
                readonly property bool isActive: wsId === root.activeWsId
                readonly property bool isOccupied: wsModel.occupied[wsId] === true
                readonly property bool isScratchpadActive: root.scratchpadOpen && isActive
                readonly property real targetCross: isScratchpadActive
                    ? root.scratchpadCross
                    : (isActive ? root.activeCross : root.inactiveCross)

                width: root.vertical ? root.thickness : root.pillAlong
                height: root.vertical ? root.pillAlong : root.thickness

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                    id: pillBody
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                    width: root.vertical ? wsDelegate.targetCross : root.pillAlong
                    height: root.vertical ? root.pillAlong : wsDelegate.targetCross
                    radius: Appearance.rounding.scale === 0 ? 0 : Math.min(width, height) / 2
                    opacity: root.scratchpadOpen && !wsDelegate.isActive ? 0.45 : 1.0
                    property real glowOpacity: wsDelegate.isActive ? 1.0 : 0.0
                    color: {
                        if (wsDelegate.isScratchpadActive)
                            return hover.hovered ? widgetPalette.colAccentHover : widgetPalette.colAccent;
                        if (wsDelegate.isActive)
                            return hover.hovered ? widgetPalette.colBackgroundHover : widgetPalette.colBackground;
                        if (hover.hovered)
                            return root.colInactiveHover;
                        return wsDelegate.isOccupied ? root.colInactiveOccupied : root.colInactiveEmpty;
                    }

                    layer.enabled: pillBody.glowOpacity > 0.01
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: ColorUtils.transparentize(pillBody.color, 1.0 - pillBody.glowOpacity * 0.7)
                        shadowBlur: 1.9
                        shadowScale: 1.15
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        blurMax: 16
                    }

                    Behavior on glowOpacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.BackButton
                    onPressed: event => {
                        if (event.button === Qt.LeftButton)
                            wsModel.focus(wsDelegate.wsId);
                        else if (event.button === Qt.BackButton || event.button === Qt.MiddleButton)
                            wsModel.toggleScratchpad();
                        else if (event.button === Qt.RightButton)
                            GlobalStates.toggleOverview();
                    }
                    onWheel: wheel => {
                        wheel.accepted = true;
                        wsModel.scroll(wheel.angleDelta.y);
                    }
                }
            }
        }
    }
}
