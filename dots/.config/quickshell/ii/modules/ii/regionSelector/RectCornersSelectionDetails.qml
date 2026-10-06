import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    required property real regionX
    required property real regionY
    required property real regionWidth
    required property real regionHeight
    required property real mouseX
    required property real mouseY
    required property color color
    required property color overlayColor
    property bool showAimLines: Config.options.regionSelector.rect.showAimLines
    property bool breathingBorderOnly: false
    property bool showDimensions: true

    // Overlay to darken screen
    // Base dark overlay around region
    Rectangle {
        id: darkenOverlay

        z: 1
        visible: !root.breathingBorderOnly
        width: root.regionWidth + darkenOverlay.border.width * 2
        height: root.regionHeight + darkenOverlay.border.width * 2
        color: "transparent"
        border.color: root.overlayColor
        border.width: Math.max(root.width, root.height)

        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.regionX - darkenOverlay.border.width
            topMargin: root.regionY - darkenOverlay.border.width
        }

    }

    DashedBorder {
        id: selectionBorder

        z: 9
        width: Math.round(root.regionWidth) + (borderWidth + 5) * 2
        height: Math.round(root.regionHeight) + (borderWidth + 5) * 2
        color: root.color
        dashLength: 8
        gapLength: 4
        borderWidth: 1
        // Breathing
        opacity: 0.9

        anchors {
            left: parent.left
            top: parent.top
            leftMargin: Math.round(root.regionX) - borderWidth - 5
            topMargin: Math.round(root.regionY) - borderWidth - 5
        }

        SequentialAnimation on opacity {
            running: root.breathingBorderOnly
            loops: Animation.Infinite

            NumberAnimation {
                from: 0.9
                to: 0.3
                duration: 1200
                easing.type: Easing.InOutQuad
            }

            NumberAnimation {
                from: 0.3
                to: 0.9
                duration: 1200
                easing.type: Easing.InOutQuad
            }

        }

    }

    // Size chip: hangs off the bottom-left corner of the selection, its
    // corner nearest the selection pinched so it reads as attached to it.
    // Flips above / inside when the selection runs into a screen edge.
    Rectangle {
        id: sizeChip

        readonly property real gap: 8
        readonly property bool fitsBelow: selectionBorder.y + selectionBorder.height + gap + height <= root.height - gap
        readonly property real pinched: Appearance.rounding.scale === 0 ? 0 : 4
        readonly property real round: Appearance.rounding.scale === 0 ? 0 : height / 2

        z: 2
        visible: root.showDimensions && !root.breathingBorderOnly && root.regionWidth > 0 && root.regionHeight > 0
        implicitWidth: sizeLabel.implicitWidth + 24
        implicitHeight: 34
        width: implicitWidth
        height: implicitHeight
        color: Appearance.colors.colPrimary
        topLeftRadius: fitsBelow ? pinched : round
        bottomLeftRadius: fitsBelow ? round : pinched
        topRightRadius: round
        bottomRightRadius: round
        x: Math.max(gap, Math.min(selectionBorder.x, root.width - width - gap))
        y: {
            if (fitsBelow)
                return selectionBorder.y + selectionBorder.height + gap;
            var above = selectionBorder.y - height - gap;
            return above >= gap ? above : Math.max(gap, root.height - height - gap * 2);
        }

        RegionSizeLabel {
            id: sizeLabel

            anchors.centerIn: parent
            sizeW: Math.round(root.regionWidth)
            sizeH: Math.round(root.regionHeight)
            digitSize: 20
            colDigits: Appearance.colors.colOnPrimary
        }

    }

    // Coord lines
    Rectangle {
        // Vertical
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        x: root.mouseX
        width: 1
        color: root.color

        anchors {
            top: parent.top
            bottom: parent.bottom
        }

    }

    // Horizontal
    Rectangle {
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        y: root.mouseY
        height: 1
        color: root.color

        anchors {
            left: parent.left
            right: parent.right
        }

    }

}
