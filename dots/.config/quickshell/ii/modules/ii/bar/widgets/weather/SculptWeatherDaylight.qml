pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * `daylight` variant of Sculpt weather — the day drawn as an arc.
 *
 * A horizon, the day's arc over it and a shallower night arc under it. The sun
 * travels the upper arc from sunrise (left) to sunset (right), the stretch it
 * has already covered drawn in the accent; after dark a moon travels the lower
 * arc back. Movement here is the time of day, nothing decorative. Beside it the
 * temperature in the rounded title face and, in a slanted voice, the next
 * sunrise or sunset.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property string digits: "--"
    property bool night: false
    property real progress: 0.5
    property string nextEvent: ""
    property bool showDetails: true

    readonly property bool detailed: root.showDetails && !root.vertical
    readonly property real arcWidth: root.vertical ? root.thickness : Math.round(root.thickness * 1.45)
    readonly property real horizon: Math.round(root.thickness * 0.66)
    readonly property real rx: (root.arcWidth - 8) / 2
    readonly property real dayRy: root.horizon - 6
    readonly property real nightRy: root.thickness - root.horizon - 4
    readonly property real cx: root.arcWidth / 2
    readonly property real p: Math.max(0, Math.min(1, root.progress))

    property real animatedP: root.p
    Behavior on animatedP {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    readonly property color colTrack: ColorUtils.transparentize(root.tones.colBare, 0.72)
    readonly property color colLit: root.tones.colBareAccent

    implicitWidth: root.vertical ? root.thickness : root.arcWidth + (labels.visible ? labels.implicitWidth + 6 : tempOnly.implicitWidth + 6)
    implicitHeight: root.vertical ? root.thickness + tempOnly.implicitHeight + 2 : root.thickness

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: Appearance.rounding.scale === 0 ? 0 : Math.min(width, height) / 2
        color: ColorUtils.transparentize(root.tones.colBare, 0.92)
        opacity: root.hovered ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(parent)
        }
    }

    Item {
        id: sky
        width: root.arcWidth
        height: root.thickness

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Horizon.
            ShapePath {
                strokeColor: root.colTrack
                strokeWidth: 1.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 1
                startY: root.horizon
                PathLine {
                    x: root.arcWidth - 1
                    y: root.horizon
                }
            }

            // Day arc, whole.
            ShapePath {
                strokeColor: root.colTrack
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.cx
                    centerY: root.horizon
                    radiusX: root.rx
                    radiusY: root.dayRy
                    startAngle: 180
                    sweepAngle: 180
                }
            }

            // Day arc, travelled.
            ShapePath {
                strokeColor: root.night ? "transparent" : root.colLit
                strokeWidth: 2.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.cx
                    centerY: root.horizon
                    radiusX: root.rx
                    radiusY: root.dayRy
                    startAngle: 180
                    sweepAngle: root.night ? 0 : 180 * root.animatedP
                }
            }

            // Night arc, travelled.
            ShapePath {
                strokeColor: root.night ? root.colTrack : "transparent"
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.cx
                    centerY: root.horizon
                    radiusX: root.rx
                    radiusY: root.nightRy
                    startAngle: 0
                    sweepAngle: root.night ? 180 * root.animatedP : 0
                }
            }
        }

        // The sun, or the moon after dark.
        MaterialShape {
            readonly property real angle: Math.PI * (1 - root.animatedP)
            visible: !root.night
            implicitSize: 11
            shape: MaterialShape.Shape.Sunny
            color: root.colLit
            x: root.cx + root.rx * Math.cos(angle) - width / 2
            y: root.horizon - root.dayRy * Math.sin(angle) - height / 2
        }

        Rectangle {
            readonly property real angle: Math.PI * root.animatedP
            visible: root.night
            width: 8
            height: 8
            radius: 4
            color: root.tones.colBare
            x: root.cx + root.rx * Math.cos(angle) - width / 2
            y: root.horizon + root.nightRy * Math.sin(angle) - height / 2
        }
    }

    StyledText {
        id: tempOnly
        visible: !labels.visible
        x: root.vertical ? Math.round((root.thickness - width) / 2) : root.arcWidth + 6
        y: root.vertical ? root.thickness + 2 : Math.round((root.thickness - height) / 2)
        text: root.digits + "°"
        color: root.tones.colBare
        font.family: Appearance.font.family.title
        font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.4 : 0.5))
        font.variableAxes: ({
            "wght": 750,
            "ROND": 100
        })
    }

    Column {
        id: labels
        visible: root.detailed
        x: root.arcWidth + 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2

        StyledText {
            text: root.digits + "°"
            color: root.tones.colBare
            font.family: Appearance.font.family.title
            font.pixelSize: Math.round(root.thickness * 0.5)
            font.variableAxes: ({
                "wght": 750,
                "ROND": 100
            })
        }

        StyledText {
            text: root.nextEvent
            color: root.tones.colBare
            opacity: 0.72
            font.family: Appearance.font.family.main
            font.pixelSize: 9
            font.variableAxes: ({
                "wght": 420,
                "wdth": 100,
                "slnt": -10,
                "ROND": 100
            })
        }
    }
}
