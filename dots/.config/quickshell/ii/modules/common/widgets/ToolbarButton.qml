import QtQuick
import QtQuick.Layouts
import qs.modules.common

RippleButton {
    id: root
    Layout.fillHeight: true
    buttonRadius: Appearance.rounding.full

    // The hand, claimed by the button itself rather than left to whatever
    // happens to sit above it: a toolbar gaps-and-rules body that also asks
    // for a cursor would otherwise read as the button answering with the
    // arrow. Takes no buttons, so clicks, hover visuals and tooltips are
    // untouched; follows enabled so a disabled button never promises a click.
    HoverHandler {
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    scale: root.down ? 0.92 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }
}
