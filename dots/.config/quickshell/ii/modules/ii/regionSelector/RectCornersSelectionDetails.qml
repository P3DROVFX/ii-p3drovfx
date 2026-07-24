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

    StyledText {
        z: 2
        visible: root.showDimensions && !root.breathingBorderOnly
        color: root.color
        text: `${Math.round(root.regionWidth)} x ${Math.round(root.regionHeight)}`

        anchors {
            top: selectionBorder.bottom
            right: selectionBorder.right
            margins: 8
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
