pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common

/**
 * AOD face: a big split-flap clock. One card per digit; when a digit changes its
 * top flap falls over the hinge onto the new digit, as on a mechanical flip clock.
 * Dark grey cards on black, so most of the panel stays off.
 */
Item {
    id: root

    property bool running: true

    readonly property color cardColor: "#141414"
    readonly property color hingeColor: "black"
    readonly property color digitColor: "#d6d6d6"
    readonly property color captionColor: "#8a8a8a"

    // Four cards and two gaps fit the width; the height leaves room for the date.
    readonly property real cardHeight: Math.min(root.height * 0.46, root.width / (4 * 0.7 + 0.5) )
    readonly property real cardWidth: root.cardHeight * 0.7
    readonly property real cardGap: root.cardHeight * 0.04
    readonly property real groupGap: root.cardHeight * 0.18

    readonly property string hours: DateTime.hours
    readonly property string minutes: DateTime.minutes

    Column {
        anchors.centerIn: parent
        spacing: root.cardHeight * 0.12

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.groupGap

            Row {
                spacing: root.cardGap
                FlipDigit { digit: root.hours.charAt(0) }
                FlipDigit { digit: root.hours.charAt(1) }
            }
            Row {
                spacing: root.cardGap
                FlipDigit { digit: root.minutes.charAt(0) }
                FlipDigit { digit: root.minutes.charAt(1) }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.use12HourClock
                ? DateTime.meridiem.toUpperCase() + "  ·  " + DateTime.longDate
                : DateTime.longDate
            color: root.captionColor
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
            font.pixelSize: Math.round(root.cardHeight * 0.085)
            font.letterSpacing: root.cardHeight * 0.004
        }
    }

    component FlipDigit: Item {
        id: card

        property string digit: "0"
        // What the card settles on, and what it is leaving.
        property string current: card.digit
        property string previous: card.digit
        // 0 = the old digit still up, 0.5 = flap edge on, 1 = settled on the new one.
        property real flip: 1

        width: root.cardWidth
        height: root.cardHeight

        onDigitChanged: {
            if (card.digit === card.current)
                return;
            card.previous = card.current;
            card.current = card.digit;
            if (!root.running) {
                card.flip = 1;
                return;
            }
            flipAnim.restart();
        }

        NumberAnimation {
            id: flipAnim
            target: card
            property: "flip"
            from: 0
            to: 1
            duration: 640
            easing.type: Easing.InOutQuad
        }

        // Behind the falling flap: the new digit's top half, the old digit's bottom half.
        Half { upper: true; value: card.current }
        Half { upper: false; value: card.flip < 1 ? card.previous : card.current }

        // The flap: the old digit's top falling to the hinge, then the new digit's
        // bottom landing from it.
        Half {
            upper: true
            value: card.previous
            visible: card.flip < 0.5
            shade: card.flip * 2
            transform: Rotation {
                origin.x: card.width / 2
                origin.y: card.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: -180 * card.flip
            }
        }
        Half {
            upper: false
            value: card.current
            visible: card.flip >= 0.5 && card.flip < 1
            shade: (1 - card.flip) * 2
            transform: Rotation {
                origin.x: card.width / 2
                origin.y: 0
                axis { x: 1; y: 0; z: 0 }
                angle: 180 * (1 - card.flip)
            }
        }

        // The hinge.
        Rectangle {
            width: parent.width
            height: Math.max(2, Math.round(card.height * 0.008))
            anchors.verticalCenter: parent.verticalCenter
            color: root.hingeColor
        }
    }

    // One half of a card, clipped from a whole one so the corners and the digit line up.
    component Half: Item {
        id: half

        property bool upper: true
        property string value: "0"
        // Darkens a flap as it turns away from the light.
        property real shade: 0

        width: root.cardWidth
        height: root.cardHeight / 2
        y: half.upper ? 0 : root.cardHeight / 2
        clip: true

        Rectangle {
            y: half.upper ? 0 : -root.cardHeight / 2
            width: root.cardWidth
            height: root.cardHeight
            radius: root.cardHeight * 0.09
            color: root.cardColor

            Text {
                anchors.centerIn: parent
                text: half.value
                color: root.digitColor
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 0 })
                font.pixelSize: Math.round(root.cardHeight * 0.78)
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "black"
                opacity: half.shade * 0.55
                visible: opacity > 0
            }
        }
    }
}
