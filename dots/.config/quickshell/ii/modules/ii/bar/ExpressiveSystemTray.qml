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

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.barHeight

    Rectangle {
        id: pill
        anchors.centerIn: parent
        color: Appearance.colors.colLayer1
        radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        implicitWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : (tray.implicitWidth > 0 ? tray.implicitWidth + 12 : 0)
        implicitHeight: vertical ? (tray.implicitHeight > 0 ? tray.implicitHeight + 12 : 0) : Appearance.sizes.barHeight - 8
        visible: tray.implicitWidth > 0

        SysTray {
            id: tray
            anchors.centerIn: parent
            vertical: root.vertical
        }
    }
}
