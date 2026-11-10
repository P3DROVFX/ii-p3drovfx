import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("EasyEffects")
    statusText: {
        if (!EasyEffects.running)
            return EasyEffects.starting ? Translation.tr("Starting…") : Translation.tr("Off");
        if (EasyEffects.bypassed)
            return Translation.tr("Bypassed");
        return EasyEffects.outputPreset.length > 0 ? EasyEffects.shortName(EasyEffects.outputPreset) : Translation.tr("On");
    }

    available: EasyEffects.available
    toggled: EasyEffects.active
    icon: EasyEffects.active && EasyEffects.outputPreset.length > 0 ? EasyEffects.iconFor(EasyEffects.outputPreset) : "graphic_eq"
    hasMenu: true

    mainAction: () => {
        EasyEffects.toggle()
    }

    tooltipText: Translation.tr("EasyEffects | Right-click for presets")
}
