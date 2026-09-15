pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

import Qt5Compat.GraphicalEffects

Item {
    id: root

    required property int regionX
    required property int regionY
    required property int regionWidth
    required property int regionHeight

    property bool breathingBorderOnly: false

    property color borderColor: Appearance.colors.colPrimary
    property color overlayColor: ColorUtils.transparentize("#000000", 1)
    Component.onCompleted: overlayColor = ColorUtils.transparentize("#000000", 0.4)
    Behavior on overlayColor {
        ColorAnimation {
            duration: 150
            easing.type: Easing.InOutQuad
        }
    }

    Item {
        id: maskSourceItem
        anchors.fill: parent
        visible: false

        Rectangle {
            x: root.regionX
            y: root.regionY
            width: root.regionWidth
            height: root.regionHeight
            radius: Math.max(0, Appearance.rounding.small - 2)
            color: "black"
        }
    }

    Rectangle {
        id: fullScreenOverlay
        anchors.fill: parent
        color: root.overlayColor
        visible: false
    }

    OpacityMask {
        id: darkenOverlay
        anchors.fill: parent
        source: fullScreenOverlay
        maskSource: maskSourceItem
        invert: true
        visible: !root.breathingBorderOnly
        z: 1
    }

    Rectangle {
        id: selectionBorder
        z: 2
        visible: root.regionWidth > 0 && root.regionHeight > 0
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: Math.round(root.regionX - border.width)
            topMargin: Math.round(root.regionY - border.width)
        }
        width: Math.round(root.regionWidth + border.width * 2)
        height: Math.round(root.regionHeight + border.width * 2)
        color: "transparent"
        border.color: root.borderColor
        border.width: 2
        radius: Appearance.rounding.small

        opacity: 0.9
        SequentialAnimation on opacity {
            running: root.breathingBorderOnly
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 0.3; duration: 1200; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.3; to: 0.9; duration: 1200; easing.type: Easing.InOutQuad }
        }
    }

    Rectangle {
        z: 2
        visible: selectionBorder.visible && !root.breathingBorderOnly
        x: root.regionX
        y: root.regionY
        width: root.regionWidth
        height: root.regionHeight
        color: ColorUtils.transparentize(root.borderColor, 0.9)
        radius: Math.max(0, Appearance.rounding.small - 2)
    }
}
