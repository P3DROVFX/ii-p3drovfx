import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    property bool auto: Config.options.light.night.automatic

    name: Translation.tr("Night Light")
    statusText: (auto ? Translation.tr("Auto, ") : "") + (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))

    toggled: Hyprsunset.temperatureActive
    heroValue: toggled ? String(Hyprsunset.colorTemperature) : ""
    // Warmer is more filter: 6500 K (neutral) is empty, 1000 K is full.
    heroLevel: Math.max(0, Math.min(1, (6500 - Hyprsunset.colorTemperature) / 5500))
    heroUnit: toggled ? "K" : ""
    icon: auto ? "night_sight_auto" : "bedtime"
    
    mainAction: () => {
        Hyprsunset.toggleTemperature()
    }
    hasMenu: true

    Component.onCompleted: {
        Hyprsunset.fetchState()
    }
    
    tooltipText: Translation.tr("Night Light | Right-click to configure")
}
