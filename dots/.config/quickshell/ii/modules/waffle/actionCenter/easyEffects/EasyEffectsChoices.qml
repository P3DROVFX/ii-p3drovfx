import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

/**
 * "Off", then the output device's presets, as one choice list: picking a preset turns
 * the effects back on with it. Shared by the EasyEffects page and the sound output page.
 */
ColumnLayout {
    id: root
    spacing: 4

    SectionText {
        text: EasyEffects.running || EasyEffects.starting
            ? Translation.tr("Presets for %1").arg(Audio.friendlyDeviceName(EasyEffects.outputDevice))
            : Translation.tr("EasyEffects presets")
    }

    WChoiceButton {
        text: Translation.tr("Off")
        checked: !EasyEffects.active
        onClicked: EasyEffects.disable()
    }

    Repeater {
        model: ScriptModel {
            values: EasyEffects.devicePresets
        }
        delegate: WChoiceButton {
            required property string modelData
            text: EasyEffects.shortName(modelData)
            checked: EasyEffects.active && EasyEffects.outputPreset === modelData
            onClicked: {
                if (EasyEffects.running && EasyEffects.bypassed)
                    EasyEffects.setBypass(false);
                EasyEffects.loadPreset(modelData, "output", true);
            }
        }
    }
}
