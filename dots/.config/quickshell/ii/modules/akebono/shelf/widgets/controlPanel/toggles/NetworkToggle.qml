import qs.services
import qs.modules.common.widgets

AkToggle {
    on: Network.wifiStatus !== "disabled"
    icon: Network.materialSymbol
    onClicked: Network.toggleWifi()
    StyledToolTip {
        text: Translation.tr("%1 | Right-click to configure").arg(Network.networkName)
    }
}
