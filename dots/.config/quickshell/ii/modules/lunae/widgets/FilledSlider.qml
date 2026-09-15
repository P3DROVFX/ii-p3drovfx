pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import qs.modules.common
import qs.modules.common.widgets

T.Slider {
    id: root

    required property string icon
    property bool initialized: false
    property real oldValue

    orientation: Qt.Vertical

    readonly property bool isVertical: orientation === Qt.Vertical
    readonly property real handleSize: isVertical ? width : height

    background: Rectangle {
        color: Appearance.colors.colSurfaceContainer
        radius: Appearance.rounding.full

        Rectangle {
            color: Appearance.m3colors.m3secondary
            radius: parent.radius

            x: 0
            y: root.isVertical ? root.handle.y : 0
            width: root.isVertical ? parent.width : root.handle.x + root.handleSize
            height: root.isVertical ? parent.height - y : parent.height
        }
    }

    handle: Item {
        id: handle

        property bool moving: false

        x: root.isVertical
            ? 0
            : root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.isVertical
            ? root.topPadding + root.visualPosition * (root.availableHeight - height)
            : 0

        implicitWidth: root.handleSize
        implicitHeight: root.handleSize

        StyledRectangularShadow {
            target: handleRect
        }

        Rectangle {
            id: handleRect
            anchors.fill: parent
            color: Appearance.m3colors.m3inverseSurface
            radius: Appearance.rounding.full

            MouseArea {
                id: handleHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.NoButton
            }

            MaterialSymbol {
                id: iconDisplay
                anchors.centerIn: parent

                property bool showPercent: handle.moving

                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.m3colors.m3inverseOnSurface

                font {
                    family: showPercent ? Appearance.font.family.numbers : Appearance.font.family.iconMaterial
                    pixelSize: showPercent ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.large
                    variableAxes: showPercent ? Appearance.font.variableAxes.numbers : ({})
                }

                onShowPercentChanged: swapAnim.restart()

                Binding {
                    target: iconDisplay
                    property: "text"
                    value: Math.round(root.value * 100)
                    when: iconDisplay.showPercent
                }

                SequentialAnimation {
                    id: swapAnim

                    NumberAnimation {
                        target: iconDisplay
                        property: "scale"
                        to: 0
                        duration: 100
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardAccel
                    }
                    ScriptAction {
                        script: {
                            if (iconDisplay.showPercent)
                                iconDisplay.text = Math.round(root.value * 100)
                            else
                                iconDisplay.text = root.icon
                        }
                    }
                    NumberAnimation {
                        target: iconDisplay
                        property: "scale"
                        to: 1
                        duration: 100
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardDecel
                    }
                }
            }
        }
    }

    onPressedChanged: handle.moving = pressed

    onValueChanged: {
        if (!initialized) {
            initialized = true
            return
        }
        if (Math.abs(value - oldValue) < 0.01)
            return
        oldValue = value
        handle.moving = true
        stateChangeDelay.restart()
    }

    Timer {
        id: stateChangeDelay
        interval: 500
        onTriggered: {
            if (!root.pressed)
                handle.moving = false
        }
    }

    Behavior on value {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
}
