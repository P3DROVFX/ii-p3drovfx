import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: false
    property bool isMaterial: true // Forced expressive

    readonly property real pillPadding: 4
    readonly property real contentW: tray.implicitWidth + pillPadding * 2
    readonly property real contentH: tray.implicitHeight + pillPadding * 2
    readonly property real pillW: vertical ? Appearance.sizes.verticalBarWidth - 8 : Math.max(Appearance.sizes.baseBarHeight - 8, contentW)
    readonly property real pillH: vertical ? Math.max(Appearance.sizes.verticalBarWidth - 8, contentH) : Appearance.sizes.baseBarHeight - 8

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (pill.visible ? pillW : 0)
    implicitHeight: vertical ? (pill.visible ? pillH : 0) : Appearance.sizes.baseBarHeight

    Rectangle {
        id: pill
        anchors.centerIn: parent
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.large
        width: root.pillW
        height: root.pillH
        visible: tray.implicitWidth > 0

        SysTray {
            id: tray
            anchors.centerIn: parent
            vertical: root.vertical
            circleItems: true
        }
    }
}
