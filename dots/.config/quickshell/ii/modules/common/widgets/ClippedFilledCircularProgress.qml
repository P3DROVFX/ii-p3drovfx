import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property int implicitSize: 18
    property int lineWidth: 2
    property real value: 0
    property color colPrimary: Appearance?.colors.colOnSecondaryContainer ?? "#685496"
    property color colSecondary: ColorUtils.transparentize(colPrimary, 0.5) ?? "#F1D3F9"
    property real gapAngle: 360 / 18
    property bool fill: true
    property int fillOverflow: 2
    property bool enableAnimation: true
    property int animationDuration: 800
    property var easingType: Easing.OutCubic
    property bool accountForLightBleeding: true
    default property Item textMask: Item {
        parent: root
        width: root.implicitSize
        height: root.implicitSize
        opacity: 0
        StyledText {
            anchors.centerIn: parent
            text: Math.round(root.value * 100)
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    property real animatedValue: value
    Behavior on animatedValue {
        enabled: root.enableAnimation
        NumberAnimation {
            duration: root.animationDuration
            easing.type: root.easingType
        }
    }

    property real degree: animatedValue * 360
    property real centerX: width / 2
    property real centerY: height / 2
    property real arcRadius: implicitSize / 2 - lineWidth / 2 - (0.5 * accountForLightBleeding)
    property real startAngle: -90

    property real sz: implicitSize
    property real tipX: {
        if (animatedValue <= 0) return sz / 2
        if (animatedValue < 0.25) return sz / 2 + animatedValue * 4 * (sz / 2)
        if (animatedValue < 0.5)  return sz
        if (animatedValue < 0.75) return sz - (animatedValue - 0.5) * 4 * sz
        return 0
    }
    property real tipY: {
        if (animatedValue <= 0) return sz / 2
        if (animatedValue < 0.25) return 0
        if (animatedValue < 0.5)  return (animatedValue - 0.25) * 4 * sz
        if (animatedValue < 0.75) return sz
        return sz - (animatedValue - 0.75) * 4 * sz
    }
    property bool passedTopRight:    animatedValue > 0.25
    property bool passedBottomRight: animatedValue > 0.5
    property bool passedBottomLeft:  animatedValue > 0.75

    // Load only the active geometry (circular OR sharp) so each instance never
    // allocates two permanent offscreen layer FBOs + two OpacityMasks at once.
    Loader {
        anchors.fill: parent
        active: !Config.options.appearance.sharpMode
        sourceComponent: Item {
            anchors.fill: parent
            Rectangle {
                id: circularContent
                anchors.fill: parent
                radius: root.implicitSize / 2
                color: root.colSecondary
                visible: false
                layer.enabled: true
                layer.smooth: true

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        id: primaryPath
                        pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting
                        strokeColor: root.colPrimary
                        strokeWidth: root.lineWidth
                        capStyle: ShapePath.RoundCap
                        fillColor: root.colPrimary

                        startX: root.centerX
                        startY: root.centerY

                        PathAngleArc {
                            moveToStart: false
                            centerX: root.centerX
                            centerY: root.centerY
                            radiusX: root.arcRadius
                            radiusY: root.arcRadius
                            startAngle: root.startAngle
                            sweepAngle: root.degree
                        }
                        PathLine {
                            x: primaryPath.startX
                            y: primaryPath.startY
                        }
                    }
                }
            }

            OpacityMask {
                anchors.fill: parent
                source: circularContent
                invert: true
                maskSource: root.textMask
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: Config.options.appearance.sharpMode
        sourceComponent: Item {
            anchors.fill: parent
            Rectangle {
                id: squareContent
                anchors.fill: parent
                radius: 0
                color: root.colSecondary
                visible: false
                layer.enabled: true
                layer.smooth: true

                Shape {
                    anchors.fill: parent

                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: root.colPrimary

                        startX: root.sz / 2
                        startY: root.sz / 2

                        PathLine { x: root.sz / 2; y: 0 }
                        PathLine {
                            x: root.passedTopRight ? root.sz : root.tipX
                            y: root.passedTopRight ? 0       : root.tipY
                        }
                        PathLine {
                            x: root.passedBottomRight ? root.sz : root.tipX
                            y: root.passedBottomRight ? root.sz : root.tipY
                        }
                        PathLine {
                            x: root.passedBottomLeft ? 0       : root.tipX
                            y: root.passedBottomLeft ? root.sz : root.tipY
                        }
                        PathLine { x: root.tipX; y: root.tipY }
                        PathLine { x: root.sz / 2; y: root.sz / 2 }
                    }
                }
            }

            OpacityMask {
                anchors.fill: parent
                source: squareContent
                invert: true
                maskSource: root.textMask
            }
        }
    }
}
