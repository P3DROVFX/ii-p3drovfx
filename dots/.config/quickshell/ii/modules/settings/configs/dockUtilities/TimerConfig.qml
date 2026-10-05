import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    id: page
    title: Translation.tr("Timer")

    function setPreset(index, minutes) {
        const presets = Array.from(Config.options.dock.utilities.timer.presets ?? [1, 5, 10, 25]);
        while (presets.length < 4)
            presets.push(5);
        if (presets[index] === minutes)
            return;
        presets[index] = minutes;
        Config.options.dock.utilities.timer.presets = presets;
    }

    ContentSection {
        title: Translation.tr("Quick start")
        icon: "timer_play"
        tooltip: Translation.tr("The durations the widget offers when no timer is running")

        Repeater {
            model: 4
            delegate: ConfigSpinBox {
                required property int index
                icon: "timer"
                text: Translation.tr("Preset %1 (minutes)").arg(index + 1)
                value: (Config.options.dock.utilities.timer.presets ?? [])[index] ?? 5
                from: 1
                to: 600
                stepSize: 1
                onValueChanged: page.setPreset(index, value)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Square widget")
        icon: "crop_square"

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Click pauses and resumes")
            checked: Config.options.dock.utilities.timer.clickPauses
            onCheckedChanged: Config.options.dock.utilities.timer.clickPauses = checked
            StyledToolTip {
                text: Translation.tr("Off: a click opens the timer panel instead")
            }
        }
    }
}
