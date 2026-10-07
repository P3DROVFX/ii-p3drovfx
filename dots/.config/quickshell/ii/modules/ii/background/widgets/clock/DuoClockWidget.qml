pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.background.widgets

/*
 * Duo Clock (2x1). Two sub-dials, as on a watch: hours on a cookie with a
 * thick pill hand and the four cardinal numerals, minutes on a circle wrapped
 * in the shell's wavy progress ring with a slim hand. The date stands between
 * them in monospace.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_duo"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "clock_duo")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.clock_duo ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool wavyRing: root.options?.wavyRing ?? true
    readonly property bool showNumerals: root.options?.showNumerals ?? true

    // -- Geometry (design units) --
    readonly property real designWidth: 492
    readonly property real designHeight: 240
    readonly property real padding: 16
    readonly property real dialSize: 208
    readonly property real middleWidth: root.designWidth - root.padding * 2 - root.dialSize * 2
    readonly property real ringThickness: 10
    readonly property real minuteFaceInset: 22

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    readonly property date now: DateTime.clock.date
    readonly property real hourAngle: ((root.now.getHours() % 12) + root.now.getMinutes() / 60) * 30
    readonly property real minuteAngle: root.now.getMinutes() * 6

    Item {
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        TypeClockFrame {
            id: frame
            anchors.fill: parent
            showBackground: root.options?.showBackground ?? true
            textShadow: root.options?.textShadow ?? true

            // -- Hours --
            Item {
                id: hourDial
                x: root.padding
                anchors.verticalCenter: parent.verticalCenter
                width: root.dialSize
                height: root.dialSize

                MaterialShape {
                    anchors.fill: parent
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: WidgetColorScheme.pillFillColor
                }

                Repeater {
                    model: root.showNumerals ? 4 : 0

                    delegate: Text {
                        required property int index
                        readonly property real angle: index * Math.PI / 2
                        readonly property real radius: root.dialSize / 2 - 30
                        x: hourDial.width / 2 + Math.sin(angle) * radius - width / 2
                        y: hourDial.height / 2 - Math.cos(angle) * radius - height / 2
                        text: String(index === 0 ? 12 : index * 3)
                        color: WidgetColorScheme.textColorOnPillFill
                        opacity: 0.75
                        font.family: Appearance.font.family.main
                        font.pixelSize: 22
                        font.variableAxes: ({ "wght": 700, "wdth": 70, "ROND": 100 })
                        renderType: Text.QtRendering
                    }
                }

                Hand {
                    length: root.dialSize * 0.3
                    thickness: 18
                    angle: root.hourAngle
                    color: WidgetColorScheme.accentColor
                }

                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: 26
                    shape: MaterialShape.Shape.Circle
                    color: WidgetColorScheme.accentColor
                }
            }

            // -- Date between the dials --
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Repeater {
                    model: [
                        Qt.locale().toString(root.now, "ddd").replace(".", "").toUpperCase(),
                        Qt.locale().toString(root.now, "dd"),
                        DateTime.use12HourClock ? DateTime.meridiem.toUpperCase() : ""
                    ]

                    delegate: StyledText {
                        required property string modelData
                        required property int index
                        visible: modelData !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData
                        color: index === 1 ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: index === 1 ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.smallest + 1
                        font.letterSpacing: 1
                    }
                }
            }

            // -- Minutes --
            Item {
                id: minuteDial
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter
                width: root.dialSize
                height: root.dialSize

                ClockProgressRing {
                    anchors.fill: parent
                    value: root.now.getMinutes() / 60
                    thickness: root.ringThickness
                    wavy: root.wavyRing
                    waves: 12
                    colIndicator: WidgetColorScheme.accentColor
                    colTrack: WidgetColorScheme.pillBgColor
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.minuteFaceInset
                    radius: width / 2
                    color: WidgetColorScheme.pillBgColor
                }

                Hand {
                    length: root.dialSize / 2 - root.minuteFaceInset - 12
                    thickness: 8
                    angle: root.minuteAngle
                    color: WidgetColorScheme.textColorOnBg
                }

                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: 22
                    shape: MaterialShape.Shape.Sunny
                    color: WidgetColorScheme.accentColor
                }
            }
        }
    }

    // A pill from the dial's centre, turning on the shortest arc.
    component Hand: Rectangle {
        id: hand
        property real length: 60
        property real thickness: 8
        property real angle: 0
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height + hand.thickness / 2
        width: hand.thickness
        height: hand.length + hand.thickness / 2
        radius: width / 2
        // The pill runs half a thickness past the centre, so it pivots on the
        // centre itself rather than on its own end.
        transform: Rotation {
            origin.x: hand.width / 2
            origin.y: hand.height - hand.thickness / 2
            angle: hand.angle

            Behavior on angle {
                enabled: !Appearance.reducedMotion
                RotationAnimation {
                    direction: RotationAnimation.Shortest
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
