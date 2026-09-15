import QtQuick
import qs.modules.common

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    signal openAudioOutputDialog
    signal openAudioInputDialog
    signal openBluetoothDialog
    signal openNightLightDialog
    signal openWifiDialog
    signal openDarkModeDialog
    signal openLocalSendDialog
    signal openVpnDialog
    signal openTailscaleDialog
    signal openDnsOverTlsDialog
    signal openIdleInhibitorDialog
    signal openScreenShaderDialog
    signal openModesDialog
}
