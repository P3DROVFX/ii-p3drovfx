import qs.modules.ii.bar.popups.battery
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

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth
    implicitHeight: vertical ? (batteryIcon.implicitHeight > 0 ? batteryIcon.implicitHeight : 0) + 8 : Appearance.sizes.baseBarHeight
    width: implicitWidth
    height: implicitHeight
    visible: Battery.available
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Component.onCompleted: {
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(Battery.available);
        }
    }

    Connections {
        target: Battery
        function onAvailableChanged() {
            if (typeof rootItem !== "undefined") {
                rootItem.toggleVisible(Battery.available);
            }
        }
    }

    Rectangle {
        id: pill
        anchors.centerIn: vertical ? undefined : parent
        anchors.fill: vertical ? parent : undefined
        color: Appearance.colors.colSecondaryContainer
        radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        implicitWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : batteryIcon.implicitWidth
        implicitHeight: vertical ? parent.height : Appearance.sizes.baseBarHeight - 8

        Loader {
            id: batteryIcon
            anchors.centerIn: parent
            source: root.vertical ? "../../../verticalBar/BatteryIndicator.qml" : "BatteryIndicator.qml"

            Binding {
                target: batteryIcon.item
                property: "textColor"
                value: Appearance.colors.colPrimary
            }

            Binding {
                target: batteryIcon.item
                property: "disablePopup"
                value: true
            }
        }
    }

    BatteryPopup {
        hoverTarget: root
    }
}
