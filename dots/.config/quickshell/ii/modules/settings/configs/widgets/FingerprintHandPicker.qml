pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Two stylized hands used to pick which finger to enroll.
 *
 * The hands are drawn from rounded rectangles in a fixed design space rather
 * than shipped as an asset, so they follow the color scheme and stay crisp at
 * any scale. The right hand is the left hand with every x coordinate mirrored
 * inside the design box — mirroring by coordinate instead of by a transform
 * keeps hit testing and tooltips trivial.
 *
 * Already-enrolled fingers stay selectable: re-enrolling one replaces the
 * stored print, which is the natural way to fix a bad scan.
 */
Item {
    id: root

    property string selectedFinger: ""
    signal fingerPicked(string finger)

    // The design box has to leave room for the thumb: it is rotated about its
    // own bottom edge, so it sweeps well past the rectangle it is declared
    // with. Sizing the box to the unrotated thumb is what made the two hands
    // collide in the middle.
    readonly property int handWidth: 160
    readonly property int handHeight: 172
    readonly property int digitWidth: 20
    readonly property int handSpacing: 32
    readonly property int palmDesignX: 12
    readonly property int palmDesignWidth: 108

    // The thumb sticks out on one side, so the hand's bounding box is not
    // centred on the hand itself. Labels line up with the palm instead.
    function palmCenterX(mirrored: bool): real {
        const x = mirrored ? (root.handWidth - root.palmDesignX - root.palmDesignWidth) : root.palmDesignX;
        return x + root.palmDesignWidth / 2;
    }

    implicitWidth: root.handWidth * 2 + root.handSpacing
    implicitHeight: root.handHeight + 24

    component Digit: Rectangle {
        id: digit

        required property string finger
        required property real designX
        required property real designY
        required property real designHeight
        property bool mirrored: false
        property real tilt: 0

        readonly property bool enrolled: Fingerprint.enrolled.indexOf(digit.finger) !== -1
        readonly property bool selected: root.selectedFinger === digit.finger
        readonly property color colContent: digit.selected ? Appearance.colors.colOnPrimary : digit.enrolled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2

        width: root.digitWidth
        height: digit.designHeight
        x: digit.mirrored ? (root.handWidth - digit.designX - width) : digit.designX
        y: digit.designY
        radius: Appearance.rounding.full
        rotation: digit.mirrored ? -digit.tilt : digit.tilt
        transformOrigin: Item.Bottom

        color: digit.selected ? Appearance.colors.colPrimary : digit.enrolled ? (digitMouse.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer) : (digitMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
        border.width: digit.selected ? 0 : 1
        border.color: digit.enrolled ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
            }
        }

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 5
            visible: digit.enrolled || digit.selected
            text: digit.selected && !digit.enrolled ? "add" : "fingerprint"
            iconSize: 15
            fill: 1
            color: digit.colContent
        }

        MouseArea {
            id: digitMouse
            anchors.fill: parent
            anchors.margins: -2
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.fingerPicked(digit.finger)
        }

        // A plain Rectangle has no `hovered`, which would leave the tooltip
        // permanently on screen — drive it from the MouseArea instead.
        StyledToolTip {
            extraVisibleCondition: digitMouse.containsMouse
            text: Fingerprint.labelFor(digit.finger) + (digit.enrolled ? " · " + Translation.tr("Enrolled") : "")
        }
    }

    component Hand: Item {
        id: hand

        required property bool mirrored
        required property string handId

        width: root.handWidth
        height: root.handHeight

        // Coordinates below describe a LEFT hand: little finger at the left
        // edge, thumb at the right. Mirroring turns it into the right hand.
        //
        // Laid out this way the thumbs face each other. That is the correct
        // handedness for how anyone actually looks at their own hands — palms
        // toward you, or flat on a desk seen from above — both of which put
        // the thumbs inward. Thumbs pointing outward only happens when the
        // backs of the hands face you with the palms turned away, which is
        // not how someone reads a finger picker.

        Digit {
            finger: hand.handId + "-little-finger"
            mirrored: hand.mirrored
            designX: 16
            designY: 58
            designHeight: 62
        }

        Digit {
            finger: hand.handId + "-ring-finger"
            mirrored: hand.mirrored
            designX: 40
            designY: 34
            designHeight: 86
        }

        Digit {
            finger: hand.handId + "-middle-finger"
            mirrored: hand.mirrored
            designX: 64
            designY: 24
            designHeight: 96
        }

        Digit {
            finger: hand.handId + "-index-finger"
            mirrored: hand.mirrored
            designX: 88
            designY: 34
            designHeight: 86
        }

        // Rooted deep enough that the palm hides its lower third, so it reads
        // as growing out of the hand. Every earlier attempt anchored it at or
        // outside the palm edge, which looked like a capsule stuck on beside
        // the hand no matter what angle it was given.
        Digit {
            finger: hand.handId + "-thumb"
            mirrored: hand.mirrored
            designX: 92
            designY: 84
            designHeight: 72
            tilt: 40
        }

        // Declared last so it paints over the roots of all five digits: the
        // hand then reads as one silhouette instead of six outlined shapes
        // overlapping each other. It takes no input, so clicks still reach the
        // digits underneath.
        Rectangle {
            x: hand.mirrored ? (root.handWidth - root.palmDesignX - width) : root.palmDesignX
            y: 96
            width: root.palmDesignWidth
            height: 68
            radius: 26
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
    }

    component HandColumn: ColumnLayout {
        id: handColumn

        required property bool mirrored
        required property string handId
        required property string label

        spacing: 4

        Hand {
            Layout.alignment: Qt.AlignHCenter
            mirrored: handColumn.mirrored
            handId: handColumn.handId
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: handLabel.implicitHeight

            StyledText {
                id: handLabel
                x: root.palmCenterX(handColumn.mirrored) - width / 2
                text: handColumn.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: root.handSpacing

        HandColumn {
            mirrored: false
            handId: "left"
            label: Translation.tr("Left")
        }

        HandColumn {
            mirrored: true
            handId: "right"
            label: Translation.tr("Right")
        }
    }
}
