pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
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
    }

    readonly property bool scratchpadOpen: wsModel.scratchpadOpen
    property real blur: root.scratchpadOpen ? 1 : 0
    readonly property int activeWsId: wsModel.activeId

    // ── Sizing ────────────────────────────────────────────────────────────────
    readonly property real barDimension: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight
    readonly property real containerThickness: Math.max(16, barDimension - 16)
    readonly property real shapeDiameter: Math.max(6, containerThickness - 5)
    readonly property real pillLength: shapeDiameter * 1.5

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : container.implicitWidth
    implicitHeight: vertical ? container.implicitHeight : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on blur {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
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
            wsModel.scroll(wheel.angleDelta.y);
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
            model: wsModel.visibleIds
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
                readonly property bool isOccupied: wsModel.occupied[wsId] === true
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
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
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
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Rectangle {
                        id: innerShape
                        anchors.fill: parent
                        radius: root.vertical ? (width / 2) : (height / 2)

                        color: {
                            if (wsDelegate.isActive) {
                                if (wsDelegate.isShowingScratchpad)
                                    return hover.hovered ? widgetPalette.colAccentHover : widgetPalette.colAccent;
                                return hover.hovered ? widgetPalette.colBackgroundHover : widgetPalette.colBackground;
                            }
                            if (hover.hovered) {
                                const baseColor = wsDelegate.isOccupied ? widgetPalette.colContainerHover : widgetPalette.colContainer;
                                const mixTarget = root.scratchpadOpen ? widgetPalette.colAccentHover : widgetPalette.colBackgroundHover;
                                return ColorUtils.mix(baseColor, mixTarget, wsDelegate.isOccupied ? 0.35 : 0.5);
                            }
                            return wsDelegate.isOccupied
                                ? widgetPalette.colContainer
                                : ColorUtils.mix(widgetPalette.colContainer, Appearance.colors.colLayer1, 0.25);
                        }
                        opacity: {
                            if (wsDelegate.isActive)
                                return 1;
                            if (root.scratchpadOpen)
                                return hover.hovered ? 0.5 : 0.15;
                            if (hover.hovered)
                                return 0.9;
                            return wsDelegate.isOccupied ? 0.75 : 0.3;
                        }

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: wsModel.labelFor(wsDelegate.wsId)
                            font.pixelSize: Math.max(7, root.shapeDiameter - 4)
                            font.weight: wsDelegate.isActive ? Font.Bold : Font.Normal
                            font.family: Appearance.font.family.numbers

                            color: {
                                if (wsDelegate.isActive)
                                    return wsDelegate.isShowingScratchpad ? widgetPalette.colOnAccent : widgetPalette.colOnBackground;
                                return wsDelegate.isOccupied
                                    ? widgetPalette.colOnContainer
                                    : ColorUtils.transparentize(widgetPalette.colOnContainer, 0.35);
                            }
                            opacity: wsModel.showNumbers ? 1 : 0

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveSlow.numberAnimation.createObject(this)
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
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
                    onClicked: wsModel.focus(wsDelegate.wsId)
                }
            }
        }
    }

        Item {
            id: activePositionHelper
            readonly property real indicatorSize: root.shapeDiameter
            readonly property real pillLen: root.pillLength
            readonly property Item activeItem: wsModel.activeIndex >= 0 ? listView.itemAtIndex(wsModel.activeIndex) : null

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

        readonly property bool _show: root.scratchpadOpen && wsModel.activeIndex >= 0
        color: widgetPalette.colAccent
        visible: _show
        opacity: _show ? 1.0 : 0.0
        scale: _show ? 1.0 : 0.7

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledText {
            anchors.centerIn: parent
            text: wsModel.labelFor(root.activeWsId)
            font.pixelSize: Math.max(7, root.shapeDiameter - 4)
            font.weight: Font.Bold
            font.family: Appearance.font.family.numbers
            color: widgetPalette.colOnAccent
        }
    }
}
