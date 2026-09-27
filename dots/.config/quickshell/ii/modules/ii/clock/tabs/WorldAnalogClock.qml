pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The local time as a Pixel-style dial, with a slim hand and a name tag for every world
 * city — where everyone is on the same face at once.
 */
Item {
    id: root

    property date now: new Date()
    property bool showSeconds: true
    property bool showCities: true

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real size: Math.min(root.width, root.height)
    readonly property real radius: root.size / 2
    readonly property color colFace: ClockStyle.colSurfaceHigh
    readonly property color colMarks: ClockStyle.colOutline
    readonly property color colNumbers: ClockStyle.colSubtext
    readonly property color colHour: ClockStyle.colPrimary
    readonly property color colMinute: ClockStyle.colTertiary
    readonly property color colSecond: ClockStyle.colPrimary
    readonly property color colCityHand: ClockStyle.colOnSurfaceVariant
    readonly property color colCityTag: ClockStyle.colSecondaryContainer
    readonly property color colOnCityTag: ClockStyle.colOnSecondaryContainer
    readonly property real hourHandWidth: root.size * 0.05
    readonly property real minuteHandWidth: root.size * 0.032
    readonly property real cityHandWidth: Math.max(2, root.size * 0.008)
    readonly property real tagHeight: Math.max(18, root.size * 0.07)
    readonly property var tagRadii: [0.4, 0.66, 0.53, 0.78, 0.46]

    readonly property real hourAngle: ((root.now.getHours() % 12) + root.now.getMinutes() / 60) * 30
    readonly property real minuteAngle: (root.now.getMinutes() + root.now.getSeconds() / 60) * 6
    readonly property real secondAngle: root.now.getSeconds() * 6

    implicitWidth: 280
    implicitHeight: 280

    component Hand: Rectangle {
        id: hand
        property real angle: 0
        property real length: 0
        property real thickness: 4

        width: hand.thickness
        height: hand.length
        radius: hand.thickness / 2
        antialiasing: true
        x: root.width / 2 - hand.width / 2
        y: root.height / 2 - hand.length + hand.thickness / 2
        transformOrigin: Item.Bottom
        rotation: hand.angle

        Behavior on rotation {
            enabled: !ClockStyle.reducedMotion
            RotationAnimation {
                direction: RotationAnimation.Shortest
                duration: ClockStyle.motionSpatial.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionSpatial.bezierCurve
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: root.radius
        color: root.colFace
    }

    Repeater {
        model: 60

        Rectangle {
            id: mark
            required property int index
            readonly property bool major: mark.index % 5 === 0
            readonly property real angle: mark.index * 6 * Math.PI / 180
            readonly property real distance: root.radius * 0.9

            visible: !mark.major || (mark.index % 15 !== 0)
            width: mark.major ? root.size * 0.018 : root.size * 0.008
            height: width
            radius: width / 2
            color: root.colMarks
            x: root.width / 2 + mark.distance * Math.sin(mark.angle) - width / 2
            y: root.height / 2 - mark.distance * Math.cos(mark.angle) - height / 2
        }
    }

    Repeater {
        model: 4

        StyledText {
            id: numeral
            required property int index
            readonly property real angle: numeral.index * 90 * Math.PI / 180
            readonly property real distance: root.radius * 0.84

            text: String(numeral.index === 0 ? 12 : numeral.index * 3)
            font.family: ClockStyle.fontMain
            font.variableAxes: ClockStyle.axesDigitsBold
            font.pixelSize: root.size * 0.13
            color: root.colNumbers
            x: root.width / 2 + numeral.distance * Math.sin(numeral.angle) - width / 2
            y: root.height / 2 - numeral.distance * Math.cos(numeral.angle) - height / 2
        }
    }

    Repeater {
        model: root.showCities ? WorldClockService.clocks.length : 0

        Item {
            id: city
            required property int index
            readonly property var entry: WorldClockService.clocks[city.index]
            readonly property var wall: WorldClockService.wallClock(city.entry?.tz, root.now)
            readonly property real angle: city.wall ? ((city.wall.getHours() % 12) + city.wall.getMinutes() / 60) * 30 : 0
            readonly property real length: root.radius * root.tagRadii[city.index % root.tagRadii.length]
            readonly property real radians: city.angle * Math.PI / 180

            anchors.fill: parent
            visible: city.wall !== null

            Hand {
                angle: city.angle
                length: city.length
                thickness: root.cityHandWidth
                color: root.colCityHand
                opacity: 0.55
            }

            Rectangle {
                width: tagText.implicitWidth + root.tagHeight * 0.7
                height: root.tagHeight
                radius: height / 2
                color: root.colCityTag
                x: root.width / 2 + city.length * Math.sin(city.radians) - width / 2
                y: root.height / 2 - city.length * Math.cos(city.radians) - height / 2

                Behavior on x {
                    animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                }

                StyledText {
                    id: tagText
                    anchors.centerIn: parent
                    text: WorldClockService.displayName(city.entry)
                    font.pixelSize: root.tagHeight * 0.55
                    font.weight: Font.DemiBold
                    color: root.colOnCityTag
                }
            }
        }
    }

    Hand {
        angle: root.hourAngle
        length: root.radius * 0.5
        thickness: root.hourHandWidth
        color: root.colHour
    }

    Hand {
        angle: root.minuteAngle
        length: root.radius * 0.72
        thickness: root.minuteHandWidth
        color: root.colMinute
    }

    Rectangle {
        visible: root.showSeconds
        readonly property real radians: root.secondAngle * Math.PI / 180
        readonly property real distance: root.radius * 0.78
        width: root.size * 0.04
        height: width
        radius: width / 2
        color: root.colSecond
        x: root.width / 2 + distance * Math.sin(radians) - width / 2
        y: root.height / 2 - distance * Math.cos(radians) - height / 2
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.hourHandWidth * 1.6
        height: width
        radius: width / 2
        color: root.colHour
    }
}
