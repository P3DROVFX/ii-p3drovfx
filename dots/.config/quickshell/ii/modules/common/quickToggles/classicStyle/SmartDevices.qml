import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell.Io

QuickToggleButton {
    id: smartDevicesButton
    toggled: SmartDevicesService.anyDeviceOn
    buttonIcon: SmartDevicesService.anyDeviceOn ? "home_iot_device" : "home"
    onClicked: {
        SmartDevicesService.toggleAll();
    }

    StyledToolTip {
        text: Translation.tr("Smart Devices | Right-click to configure")
    }
}
