pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Numeral Clock (1x1). An analog face with no hour hand: the twelve numerals
 * are the dial, and each one's weight and size follow how close the hour is
 * to it - the current hour heavy and large, its neighbours medium, the far
 * side hairline. The hour moves continuously, so the emphasis slides from one
 * numeral to the next through the hour. A slim pill is the minute hand.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_numeral"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "clock_numeral")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.clock_numeral ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool romanNumerals: root.options?.romanNumerals ?? false
    readonly property bool showDate: root.options?.showDate ?? true

    // -- Geometry (design units) --
    readonly property real designSize: 240
    readonly property real numeralRadius: 90
    readonly property real minNumeralSize: 17
    readonly property real maxNumeralSize: 40
    readonly property real lightWeight: 120
    readonly property real heavyWeight: 950
    // How many hours away a numeral still feels the hour's pull.
    readonly property real reach: 2.6
    readonly property real minuteHandLength: 60
    readonly property real minuteHandWidth: 7
    readonly property real capSize: 22

    implicitWidth: root.designSize * root.contentScale
    implicitHeight: root.designSize * root.contentScale

    readonly property date now: DateTime.clock.date
    // 0..12, continuous through the hour.
    readonly property real hourPosition: (root.now.getHours() % 12) + root.now.getMinutes() / 60
    property real easedHour: root.hourPosition
    Behavior on easedHour {
        enabled: !Appearance.reducedMotion
        // Midnight and noon wrap 12 -> 0; that jump is a reset, not motion.
        NumberAnimation {
            duration: Math.abs(root.easedHour - root.hourPosition) > 6 ? 0 : Appearance.animation.elementMove.duration
            easing.type: Easing.OutCubic
        }
    }

    readonly property var romans: ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]

    function closeness(index) {
        const raw = Math.abs(index - root.easedHour) % 12;
        const distance = Math.min(raw, 12 - raw);
        const t = Math.max(0, 1 - distance / root.reach);
        // Eased, so the pull falls off softly instead of in a cone.
        return t * t * (3 - 2 * t);
    }

    Item {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
        scale: root.contentScale

        TypeClockFrame {
            id: frame
            anchors.fill: parent
            showBackground: root.options?.showBackground ?? true
            textShadow: root.options?.textShadow ?? true

            Repeater {
                model: 12

                delegate: Text {
                    id: numeral
                    required property int index
                    readonly property real near: root.closeness(numeral.index)
                    readonly property real angle: numeral.index * Math.PI / 6
                    x: frame.width / 2 + Math.sin(numeral.angle) * root.numeralRadius - width / 2
                    y: frame.height / 2 - Math.cos(numeral.angle) * root.numeralRadius - height / 2
                    text: root.romanNumerals ? root.romans[numeral.index] : String(numeral.index === 0 ? 12 : numeral.index)
                    color: numeral.near > 0.55 ? WidgetColorScheme.accentColor
                        : (numeral.near > 0.05 ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg)
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.round(root.minNumeralSize + (root.maxNumeralSize - root.minNumeralSize) * numeral.near)
                    font.variableAxes: ({
                        "wght": Math.round(root.lightWeight + (root.heavyWeight - root.lightWeight) * numeral.near),
                        "wdth": root.romanNumerals ? 70 : 90,
                        "ROND": 100,
                        "opsz": 144
                    })
                    renderType: Text.QtRendering
                }
            }

            StyledText {
                visible: root.showDate
                // Always in the half the minute hand is not sweeping.
                readonly property bool handBelow: root.now.getMinutes() > 15 && root.now.getMinutes() < 45
                anchors.horizontalCenter: parent.horizontalCenter
                y: handBelow ? frame.height / 2 - 26 - height : frame.height / 2 + 26
                text: Qt.locale().toString(root.now, "ddd dd").replace(".", "").toUpperCase()
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest + 1
                font.letterSpacing: 1.5
            }

            // Minute hand
            Rectangle {
                x: frame.width / 2 - width / 2
                y: frame.height / 2 - height
                width: root.minuteHandWidth
                height: root.minuteHandLength
                radius: width / 2
                color: WidgetColorScheme.textColorOnBg
                transformOrigin: Item.Bottom
                rotation: root.now.getMinutes() * 6

                Behavior on rotation {
                    enabled: !Appearance.reducedMotion
                    RotationAnimation {
                        direction: RotationAnimation.Shortest
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MaterialShape {
                anchors.centerIn: parent
                implicitSize: root.capSize
                shape: MaterialShape.Shape.Sunny
                color: WidgetColorScheme.accentColor
            }
        }
    }
}
