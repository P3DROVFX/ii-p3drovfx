pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

// iOS analog widget: a card, an inner dial, twelve bar indices and the Apple
// hands (thin neck, wide rounded body).
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_ios_analog"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    readonly property var opts: Config.options.background.widgets.clock_ios_analog
    readonly property bool showSeconds: opts?.showSeconds ?? true
    readonly property bool showDial: opts?.showDial ?? true
    readonly property real contentScale: (opts?.widgetSize ?? 100) / 100.0
    readonly property real designSize: 240
    implicitWidth: designSize * contentScale
    implicitHeight: designSize * contentScale

    // -- Colors (WidgetColorScheme) --
    property color colCardBg: WidgetColorScheme.cardBgColor
    property color colDial: WidgetColorScheme.innerShapeColor
    property color colHands: WidgetColorScheme.textColorOnBg
    property color colSeconds: WidgetColorScheme.accentColor

    // -- Time --
    // The shell clock ticks per minute unless the user asked for seconds, so
    // the second hand keeps its own clock — alive only while it is drawn.
    SystemClock {
        id: secondsClock
        enabled: root.showSeconds && root.live
        precision: SystemClock.Seconds
    }
    readonly property var now: secondsClock.enabled ? secondsClock.date : DateTime.clock.date
    readonly property real hourAngle: ((now.getHours() % 12) + now.getMinutes() / 60) * 30
    readonly property real minuteAngle: (now.getMinutes() + (secondsClock.enabled ? now.getSeconds() / 60 : 0)) * 6
    readonly property real secondAngle: now.getSeconds() * 6

    // -- Geometry (design units) --
    readonly property real dialInset: 16
    readonly property real indexDistance: 82
    readonly property real indexLength: 20
    readonly property real indexWidth: 7
    readonly property real handWidth: 8
    readonly property real handNeckWidth: 3
    readonly property real handNeckLength: 14
    readonly property real hourHandLength: 58
    readonly property real minuteHandLength: 88
    readonly property real secondHandLength: 96
    readonly property real secondHandTail: 18
    readonly property real secondHandWidth: 2
    readonly property real pivotSize: 11

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

            Rectangle {
                visible: root.showDial
                anchors.fill: parent
                anchors.margins: root.dialInset
                radius: width / 2
                color: WidgetColorScheme.tintBackground(root.colDial)
            }

            Repeater {
                model: 12

                Rectangle {
                    required property int index
                    readonly property real angle: index * 30

                    width: root.indexWidth
                    height: root.indexLength
                    radius: width / 2
                    antialiasing: true
                    color: root.colHands
                    x: root.designSize / 2 + Math.sin(angle * Math.PI / 180) * root.indexDistance - width / 2
                    y: root.designSize / 2 - Math.cos(angle * Math.PI / 180) * root.indexDistance - height / 2
                    rotation: angle
                }
            }

            AppleHand {
                angle: root.hourAngle
                length: root.hourHandLength
            }

            AppleHand {
                angle: root.minuteAngle
                length: root.minuteHandLength
            }

            Item {
                visible: secondsClock.enabled
                anchors.fill: parent
                rotation: root.secondAngle
                // Ticks like a quartz movement. A sweep animated every second kept this
                // full-screen layer rendering ~12 frames a second; a tick is one.

                Rectangle {
                    width: root.secondHandWidth
                    height: root.secondHandLength + root.secondHandTail
                    radius: width / 2
                    antialiasing: true
                    color: root.colSeconds
                    x: root.designSize / 2 - width / 2
                    y: root.designSize / 2 - root.secondHandLength
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: root.pivotSize
                height: width
                radius: width / 2
                color: secondsClock.enabled ? root.colSeconds : root.colHands
            }
        }
    }

    // A full-size rotor: a short neck from the pivot, then the rounded body.
    component AppleHand: Item {
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
            color: root.colHands
            x: root.designSize / 2 - width / 2
            y: root.designSize / 2 - root.handNeckLength
        }
        Rectangle {
            width: root.handWidth
            height: hand.length - root.handNeckLength
            radius: width / 2
            antialiasing: true
            color: root.colHands
            x: root.designSize / 2 - width / 2
            y: root.designSize / 2 - hand.length
        }
    }
}
