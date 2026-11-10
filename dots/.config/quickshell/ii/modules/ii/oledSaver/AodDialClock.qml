pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * AOD face: three concentric dials centred on the left edge of the screen, so only
 * their right halves show. Hours, minutes and seconds are printed around the rims
 * like an analogue face, and each dial turns until the current value sits on the
 * horizontal line through the centre - read left to right, that line is the time.
 * The seconds dial ticks round once a minute.
 */
Item {
    id: root

    property bool running: true

    readonly property color dimColor: "#4a4a4a"
    readonly property color litColor: "#ececec"
    readonly property color guideColor: "#161616"
    readonly property color bandColor: "#101010"

    // The outer rim fits the width with room for the date, and may run off the top and
    // bottom: it is a slice of a much larger face.
    readonly property real outerRadius: Math.min(root.width * 0.42, root.height * 0.72)
    readonly property real secondsRadius: root.outerRadius
    readonly property real minutesRadius: root.outerRadius * 0.8
    readonly property real hoursRadius: root.outerRadius * 0.5
    readonly property real centerY: root.height / 2

    SystemClock {
        id: clock
        enabled: root.running
        precision: SystemClock.Seconds
    }

    readonly property bool twelveHour: DateTime.use12HourClock
    readonly property int hourValue: root.twelveHour ? clock.date.getHours() % 12 : clock.date.getHours()

    // The band the values line up on.
    Rectangle {
        x: root.hoursRadius - hoursDial.fontSize * 1.1
        width: root.secondsRadius + secondsDial.fontSize * 1.3 - x
        height: hoursDial.fontSize * 1.9
        y: root.centerY - height / 2
        radius: height / 2
        color: root.bandColor
    }

    Repeater {
        model: [root.hoursRadius, root.minutesRadius, root.secondsRadius]
        delegate: Rectangle {
            required property real modelData
            x: -modelData
            y: root.centerY - modelData
            width: modelData * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, root.outerRadius * 0.002)
            border.color: root.guideColor
        }
    }

    Dial {
        id: hoursDial
        count: root.twelveHour ? 12 : 24
        value: root.hourValue
        radius: root.hoursRadius
        fontSize: Math.min(root.outerRadius * 0.075, 2 * Math.PI * radius / count * 0.6)
        weight: 700
        label: i => root.twelveHour ? String(i === 0 ? 12 : i) : String(i).padStart(2, "0")
    }
    Dial {
        id: minutesDial
        count: 60
        value: clock.date.getMinutes()
        radius: root.minutesRadius
        fontSize: Math.min(root.outerRadius * 0.06, 2 * Math.PI * radius / count * 0.7)
        weight: 600
        label: i => String(i).padStart(2, "0")
    }
    Dial {
        id: secondsDial
        count: 60
        value: clock.date.getSeconds()
        radius: root.secondsRadius
        fontSize: Math.min(root.outerRadius * 0.045, 2 * Math.PI * radius / count * 0.6)
        weight: 450
        label: i => String(i).padStart(2, "0")
    }

    // The rims fade into the black above and below the line.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "black" }
            GradientStop { position: 0.30; color: "#00000000" }
            GradientStop { position: 0.70; color: "#00000000" }
            GradientStop { position: 1.0; color: "black" }
        }
    }

    Column {
        anchors {
            right: parent.right
            rightMargin: root.width * 0.06
            verticalCenter: parent.verticalCenter
        }
        spacing: root.outerRadius * 0.01
        // Only where the dials leave room for it.
        visible: root.width - (root.secondsRadius + secondsDial.fontSize * 2) > width + anchors.rightMargin

        Text {
            anchors.right: parent.right
            text: DateTime.dayNameLong
            color: root.litColor
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
            font.pixelSize: Math.round(root.outerRadius * 0.07)
        }
        Text {
            anchors.right: parent.right
            text: DateTime.dayOfMonth + " " + DateTime.monthNameLong + (root.twelveHour ? "  ·  " + DateTime.meridiem.toUpperCase() : "")
            color: root.dimColor
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
            font.pixelSize: Math.round(root.outerRadius * 0.045)
        }
    }

    // One dial: `count` labels around a circle of `radius` centred on the left edge,
    // turned so `value` points right. The turn only ever moves forward the short way,
    // so 59 -> 00 steps on instead of unwinding the whole dial.
    component Dial: Item {
        id: dial

        property int count: 60
        property int value: 0
        property real radius: 100
        property real fontSize: 20
        property int weight: 500
        property var label: i => String(i)

        readonly property real step: 360 / dial.count
        property int settled: 0
        property real turn: 0

        x: 0
        y: root.centerY
        rotation: dial.turn
        Behavior on rotation {
            enabled: root.running
            NumberAnimation {
                duration: 520
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }

        Component.onCompleted: {
            dial.settled = dial.value;
            dial.turn = -dial.value * dial.step;
        }
        onValueChanged: {
            let delta = (dial.value - dial.settled + dial.count) % dial.count;
            if (delta > dial.count / 2)
                delta -= dial.count;
            dial.settled = dial.value;
            dial.turn -= delta * dial.step;
        }
        onCountChanged: {
            dial.settled = dial.value;
            dial.turn = -dial.value * dial.step;
        }

        Repeater {
            model: dial.count
            delegate: Text {
                id: mark
                required property int index
                readonly property real angle: mark.index * dial.step
                readonly property bool lit: mark.index === dial.value

                x: Math.cos(mark.angle * Math.PI / 180) * dial.radius - width / 2
                y: Math.sin(mark.angle * Math.PI / 180) * dial.radius - height / 2
                rotation: mark.angle
                scale: mark.lit ? 1.3 : 1
                text: dial.label(mark.index)
                color: mark.lit ? root.litColor : root.dimColor
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": dial.weight, "wdth": 100, "ROND": 100 })
                font.pixelSize: Math.round(dial.fontSize)

                Behavior on scale {
                    enabled: root.running
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    enabled: root.running
                    ColorAnimation { duration: 300 }
                }
            }
        }
    }
}
