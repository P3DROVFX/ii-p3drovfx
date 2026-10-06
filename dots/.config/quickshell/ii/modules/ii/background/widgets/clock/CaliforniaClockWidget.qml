pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "RoundedRectRay.js" as Ray

// Apple Watch "California" in its full-screen cut: Roman numerals across the
// top, Arabic below, all pushed out to hug the card's rounded outline, a minute
// track on the very edge and an accent second hand.
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_california"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    readonly property var opts: Config.options.background.widgets.clock_california
    readonly property bool showSeconds: opts?.showSeconds ?? true
    readonly property bool showDate: opts?.showDate ?? true
    readonly property real contentScale: (opts?.widgetSize ?? 100) / 100.0
    readonly property real designSize: 240
    implicitWidth: designSize * contentScale
    implicitHeight: designSize * contentScale

    // -- Colors (WidgetColorScheme) --
    property color colCardBg: WidgetColorScheme.cardBgColor
    property color colText: WidgetColorScheme.textColorOnBg
    property color colSubText: WidgetColorScheme.subtextColorOnBg
    property color colAccent: WidgetColorScheme.accentColor

    // -- Time --
    SystemClock {
        id: secondsClock
        enabled: root.showSeconds && root.visible && root.opacity > 0
        precision: SystemClock.Seconds
    }
    readonly property var now: secondsClock.enabled ? secondsClock.date : DateTime.clock.date
    readonly property real hourAngle: ((now.getHours() % 12) + now.getMinutes() / 60) * 30
    readonly property real minuteAngle: (now.getMinutes() + (secondsClock.enabled ? now.getSeconds() / 60 : 0)) * 6
    readonly property real secondAngle: now.getSeconds() * 6

    // -- Typography --
    // Tall, narrow numerals from the font's width axis.
    readonly property var numeralAxes: ({ "wdth": 25, "wght": 700 })
    readonly property real numeralPixelSize: 36
    readonly property var numerals: ["XII", "I", "II", "3", "4", "5", "6", "7", "8", "9", "X", "XI"]
    readonly property var dateAxes: ({ "wght": 600 })

    // -- Geometry (design units) --
    readonly property real trackInset: 8
    readonly property real trackMajorLength: 10
    readonly property real trackMinorLength: 6
    readonly property real trackMajorWidth: 2.5
    readonly property real trackMinorWidth: 1.5
    readonly property real numeralInset: 34
    readonly property real dateOffset: 46
    readonly property real dateSpacing: 4
    readonly property real handWidth: 9
    readonly property real handNeckWidth: 3
    readonly property real handNeckLength: 16
    readonly property real hourHandLength: 62
    readonly property real minuteHandLength: 98
    readonly property real handCoreShare: 0.3
    readonly property real secondHandLength: 106
    readonly property real secondHandTail: 22
    readonly property real secondHandWidth: 2
    readonly property real pivotSize: 12
    readonly property real pivotCoreShare: 0.36

    StyledDropShadow {
        target: card
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Item {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
        scale: root.contentScale

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.verylarge
            color: WidgetColorScheme.tintBackground(root.colCardBg)

            // Minute track on the outermost edge, following the outline.
            Repeater {
                model: 60

                Rectangle {
                    required property int index
                    readonly property bool major: index % 5 === 0
                    readonly property real angle: index * 6
                    readonly property real reach: Ray.distance(angle, root.designSize / 2 - root.trackInset, card.radius - root.trackInset)
                    readonly property real centreDist: reach - height / 2

                    width: major ? root.trackMajorWidth : root.trackMinorWidth
                    height: major ? root.trackMajorLength : root.trackMinorLength
                    radius: width / 2
                    antialiasing: true
                    color: major ? root.colText : root.colSubText
                    x: root.designSize / 2 + Math.sin(angle * Math.PI / 180) * centreDist - width / 2
                    y: root.designSize / 2 - Math.cos(angle * Math.PI / 180) * centreDist - height / 2
                    rotation: angle
                }
            }

            // Hour numerals, upright, centred on the inset outline.
            Repeater {
                model: 12

                StyledText {
                    required property int index
                    readonly property point spot: Ray.point(index * 30, root.designSize / 2 - root.numeralInset, card.radius - root.numeralInset, root.designSize / 2)

                    text: root.numerals[index]
                    color: root.colText
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.numeralPixelSize
                    font.variableAxes: root.numeralAxes
                    x: spot.x - width / 2
                    y: spot.y - height / 2
                }
            }

            // Date complication, between the pivot and the 6.
            Row {
                visible: root.showDate
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.dateOffset
                spacing: root.dateSpacing

                StyledText {
                    text: DateTime.dayNameShort.toUpperCase().replace(".", "")
                    color: root.colAccent
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: root.dateAxes
                }
                StyledText {
                    text: DateTime.dayOfMonth
                    color: root.colText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: root.dateAxes
                }
            }

            WatchHand {
                angle: root.hourAngle
                length: root.hourHandLength
            }

            WatchHand {
                angle: root.minuteAngle
                length: root.minuteHandLength
            }

            Item {
                visible: secondsClock.enabled
                anchors.fill: parent
                rotation: root.secondAngle
                // Clockwise, or 59 → 0 would sweep back around the dial.
                Behavior on rotation {
                    RotationAnimation {
                        direction: RotationAnimation.Clockwise
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Rectangle {
                    width: root.secondHandWidth
                    height: root.secondHandLength + root.secondHandTail
                    radius: width / 2
                    antialiasing: true
                    color: root.colAccent
                    x: root.designSize / 2 - width / 2
                    y: root.designSize / 2 - root.secondHandLength
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: root.pivotSize
                height: width
                radius: width / 2
                color: secondsClock.enabled ? root.colAccent : root.colText

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * root.pivotCoreShare
                    height: width
                    radius: width / 2
                    color: root.colCardBg
                }
            }
        }
    }

    // Apple Watch hand: hairline neck, then a wide capsule with a core line
    // in the card colour running down its middle.
    component WatchHand: Item {
        id: hand
        property real angle
        property real length

        anchors.fill: parent
        rotation: angle

        Rectangle {
            width: root.handNeckWidth
            height: root.handNeckLength + width
            radius: width / 2
            antialiasing: true
            color: root.colText
            x: root.designSize / 2 - width / 2
            y: root.designSize / 2 - root.handNeckLength
        }
        Rectangle {
            width: root.handWidth
            height: hand.length - root.handNeckLength
            radius: width / 2
            antialiasing: true
            color: root.colText
            x: root.designSize / 2 - width / 2
            y: root.designSize / 2 - hand.length

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: parent.width / 2
                width: parent.width * root.handCoreShare
                radius: width / 2
                color: root.colCardBg
            }
        }
    }
}
