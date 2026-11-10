import qs.modules.common.widgets
import qs
import qs.services
import QtQuick
import Quickshell

QuickToggleButton {
    id: root
    available: EasyEffects.available
    toggled: EasyEffects.active
    buttonIcon: "instant_mix"

    onClicked: {
        EasyEffects.toggle()
    }

    // The panel hands this the presets dialog; on its own it opens the app.
    altAction: () => {
        GlobalStates.openEasyEffectsApp("presets")
        GlobalStates.sidebarRightOpen = false
    }

    StyledToolTip {
        text: EasyEffects.running && EasyEffects.outputPreset.length > 0
            ? Translation.tr("EasyEffects: %1 | Right-click for presets").arg(EasyEffects.outputPreset)
            : Translation.tr("EasyEffects | Right-click for presets")
    }
}
