import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    required property string icon
    property alias value: slider.value
    signal moved()

    implicitHeight: slider.implicitHeight

    MaterialSymbol {
        id: sliderIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        iconSize: 22
        color: Appearance.colors.colOnLayer1
    }

    StyledSlider {
        id: slider
        anchors {
            left: sliderIcon.right
            leftMargin: 8
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        configuration: StyledSlider.Configuration.M
        stopIndicatorValues: []
        onMoved: root.moved()
    }
}
