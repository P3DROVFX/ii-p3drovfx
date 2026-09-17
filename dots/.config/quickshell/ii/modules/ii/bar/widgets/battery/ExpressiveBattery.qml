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
    property bool popupActive: false

    implicitWidth: Battery.available ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: Battery.available ? (vertical ? (batteryIcon.implicitHeight > 0 ? batteryIcon.implicitHeight : 0) + 8 : Appearance.sizes.baseBarHeight) : 0
    width: implicitWidth
    height: implicitHeight
    visible: Battery.available
    hoverEnabled: !BarInteraction.clickToShow

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

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

    BarWidgetPalette {
        id: palette
        colorMode: Config.options.bar.battery.colorMode
    }

    Rectangle {
        id: pill
        anchors.centerIn: vertical ? undefined : parent
        anchors.fill: vertical ? parent : undefined
        color: root.containsMouse ? palette.colBackgroundHover : palette.colBackground
        radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        implicitWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : batteryIcon.implicitWidth
        implicitHeight: vertical ? parent.height : Appearance.sizes.baseBarHeight - 8

        Loader {
            id: batteryIcon
            anchors.centerIn: parent
            source: root.vertical ? "../../../verticalBar/BatteryIndicator.qml" : "BatteryIndicator.qml"

            Binding {
                target: batteryIcon.item
                property: "colText"
                value: palette.colOnBackground
            }

            Binding {
                target: batteryIcon.item
                property: "disablePopup"
                value: true
            }
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    Loader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || root.popupActive)
        sourceComponent: BatteryPopup {
            hoverTarget: root
            onActiveChanged: root.popupActive = active
            Component.onDestruction: root.popupActive = false
        }
    }
}
