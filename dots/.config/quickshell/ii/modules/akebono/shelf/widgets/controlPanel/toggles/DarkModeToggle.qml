import qs.services
import qs.modules.common
import qs.modules.common.widgets

AkToggle {
    on: Appearance.m3colors.darkmode
    icon: "contrast"
    onClicked: MaterialThemeLoader.switchDarkLightMode(!Appearance.m3colors.darkmode)
    StyledToolTip {
        text: Translation.tr("Dark mode")
    }
}
