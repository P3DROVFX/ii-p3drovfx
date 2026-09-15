import qs.services
import qs.modules.common
import qs.modules.common.widgets

AkToggle {
    on: Hyprsunset.temperatureActive
    icon: Config.options.light.night.automatic ? "night_sight_auto" : "bedtime"
    onClicked: Hyprsunset.toggleTemperature()
    StyledToolTip {
        text: Translation.tr("Night Light | Right-click to configure")
    }
}
