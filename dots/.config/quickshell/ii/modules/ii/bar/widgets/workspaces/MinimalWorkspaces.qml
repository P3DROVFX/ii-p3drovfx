import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    BarWidgetPalette {
        id: widgetPalette
        colorMode: Config.options.bar.workspaces.colorMode
    }

    property bool vertical: false

    WorkspaceBarModel {
        id: wsModel
        screen: root.QsWindow.window?.screen ?? null
    }

    readonly property bool scratchpadOpen: wsModel.scratchpadOpen
    property real blur: root.scratchpadOpen ? 1 : 0

    readonly property int activeWsId: wsModel.activeId
    readonly property bool useRandomShape: wsModel.useRandomShape

    implicitWidth: vertical ? 34 : (mainLayout.implicitWidth + 12)
    implicitHeight: vertical ? (mainLayout.implicitHeight + 12) : 34

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
            index: Math.max(0, wsModel.activeIndex)
        }
        
        readonly property real animX1: getPosForIndex(idxPair.idx1)
        readonly property real animX2: getPosForIndex(idxPair.idx2)
        
        x: root.vertical ? (parent.width - width) / 2 : (root.useRandomShape ? (Math.min(animX1, animX2) + mainLayout.x + Math.abs(animX2 - animX1) / 2) : Math.min(animX1, animX2) + (root.vertical ? 0 : mainLayout.x))
        y: root.vertical ? (root.useRandomShape ? (Math.min(animX1, animX2) + mainLayout.y + Math.abs(animX2 - animX1) / 2) : Math.min(animX1, animX2) + mainLayout.y) : (parent.height - height) / 2
        
        width: root.vertical ? dotSize : (root.useRandomShape ? dotSize : Math.abs(animX2 - animX1) + dotSize)
        height: root.vertical ? (root.useRandomShape ? dotSize : Math.abs(animX2 - animX1) + dotSize) : dotSize

        opacity: root.scratchpadOpen || wsModel.activeIndex < 0 ? 0 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        sourceComponent: (Config.options.bar.workspaces.useMaterialShapeForActiveIndicator || root.useRandomShape) ? materialShapeComponent : rectangleComponent

        Component {
            id: rectangleComponent
            Rectangle {
                radius: Appearance.rounding.full
                color: widgetPalette.colBackground
                opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }
        }

        Component {
            id: materialShapeComponent
            MaterialShape {
                anchors.fill: parent
                transformOrigin: Item.Center
                shapeString: root.useRandomShape ? wsModel.randomShape : Config.options.bar.workspaces.activeIndicatorShape
                color: widgetPalette.colBackground
                opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                rotation: root.useRandomShape ? wsModel.randomRotation : 0
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
        columns: root.vertical ? 1 : wsModel.visibleIds.length
        rows: root.vertical ? wsModel.visibleIds.length : 1
        columnSpacing: 6
        rowSpacing: 6

        Repeater {
            id: dotRepeater
            model: wsModel.visibleIds
            delegate: Rectangle {
                id: dot
                required property int index
                required property var modelData
                readonly property int wsId: modelData
                readonly property bool isActive: wsId === root.activeWsId
                readonly property bool isOccupied: wsModel.occupied[wsId] === true

                readonly property bool isShowingScratchpad: root.scratchpadOpen && isActive

                width: 18
                height: 18
                radius: Appearance.rounding.full
                color: "transparent"
                z: 2

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
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: isOccupied ? 8 : 4
                        height: width
                        radius: width / 2
                        color: {
                            if (isActive) return "transparent";
                            if (hover.hovered) return widgetPalette.colBackgroundHover;
                            return isOccupied ? widgetPalette.colOnContainer : ColorUtils.transparentize(widgetPalette.colOnContainer, 0.45);
                        }
                        opacity: (isOccupied || hover.hovered) ? 1.0 : 0.4

                        Behavior on width {
                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                        }
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: isActive ? "-" : (dot.wsId).toString()
                        font.pixelSize: isActive ? 14 : 10
                        font.weight: isActive ? Font.Bold : Font.Normal
                        font.family: Appearance.font.family.numbers
                        color: widgetPalette.colOnBackground
                        opacity: isActive ? 1.0 : 0.0

                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wsModel.focus(dot.wsId)
                }
            }
        }
    }

        Item {
            id: scratchpadPositionHelper
            readonly property real dotSize: 18
            readonly property Item activeItem: wsModel.activeIndex >= 0 ? dotRepeater.itemAt(wsModel.activeIndex) : null

            x: activeItem ? root.vertical ? mainLayout.x + (mainLayout.width - dotSize) / 2 : activeItem.x + mainLayout.x + (activeItem.width - dotSize) / 2 : 0
            y: activeItem ? root.vertical ? activeItem.y + mainLayout.y + (activeItem.height - dotSize) / 2 : mainLayout.y + (mainLayout.height - dotSize) / 2 : 0
            width: dotSize
            height: dotSize
            visible: false
        }
    }

    Item {
        id: scratchpadOverlay
        z: 10

        x: scratchpadPositionHelper.x
        y: scratchpadPositionHelper.y
        width: scratchpadPositionHelper.width
        height: scratchpadPositionHelper.height

        readonly property bool _show: root.scratchpadOpen && wsModel.activeIndex >= 0

        visible: _show
        opacity: _show ? 1.0 : 0.0
        scale: _show ? 1.0 : 0.7

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialShape {
            anchors.fill: parent
            shapeString: "Flower"
            color: widgetPalette.colAccent
        }

        Rectangle {
            anchors.centerIn: parent
            width: 4
            height: 4
            radius: 2
            color: widgetPalette.colOnAccent
            opacity: 1.0

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.scratchpadOpen
                NumberAnimation {
                    to: 0.3
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    to: 1.0
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            wheel.accepted = true;
            wsModel.scroll(wheel.angleDelta.y);
        }
    }
}
