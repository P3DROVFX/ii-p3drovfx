import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false
    property bool isMaterial: true // Forced expressive

    implicitWidth: vertical ? 40 : pill.implicitWidth + 8
    implicitHeight: vertical ? pill.implicitHeight + 8 : Appearance.sizes.barHeight
    width: implicitWidth
    height: implicitHeight
    visible: Battery.available
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Rectangle {
        id: pill
        anchors.centerIn: parent
        color: Appearance.colors.colSecondaryContainer
        radius: Appearance.rounding.full
        implicitWidth: vertical ? 34 : batteryIcon.implicitWidth
        implicitHeight: vertical ? (batteryIcon.implicitHeight > 0 ? batteryIcon.implicitHeight : 0) : 30

        Loader {
            id: batteryIcon
            anchors.centerIn: parent
            source: root.vertical ? "../verticalBar/BatteryIndicator.qml" : "BatteryIndicator.qml"
            onLoaded: {
                if (item) item.textColor = Appearance.colors.colPrimary
            }
        }
    }

    BatteryPopup {
        hoverTarget: root
    }
}
