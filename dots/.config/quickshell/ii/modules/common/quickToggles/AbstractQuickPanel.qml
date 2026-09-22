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
    signal openKdeConnectDialog
    signal openDnsOverTlsDialog
    signal openIdleInhibitorDialog
    signal openScreenShaderDialog
    signal openModesDialog
    /** The tray pill tile asks for the tray surface: a dialog on the sidebar hosts,
     *  a page on the island. Emitted by the tile through `panel`. */
    signal openTrayDialog
}
