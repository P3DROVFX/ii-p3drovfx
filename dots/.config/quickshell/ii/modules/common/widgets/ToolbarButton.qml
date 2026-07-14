import QtQuick
import QtQuick.Layouts
import qs.modules.common

RippleButton {
    id: root
    Layout.fillHeight: true
    buttonRadius: Appearance.rounding.full

    scale: root.down ? 0.92 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }
}
