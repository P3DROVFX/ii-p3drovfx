import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentSection {
    icon: "nightlight"
    title: Translation.tr("Scheduling (Dark Mode & Night Light)")

    ConfigSwitch {
        buttonIcon: "dark_mode"
        text: Translation.tr("Automatic Dark Mode")
        checked: Config.options.light.darkMode.automatic
        onCheckedChanged: Config.options.light.darkMode.automatic = checked
    }

    MaterialTextArea {
        enabled: Config.options.light.darkMode.automatic
        Layout.fillWidth: true
        placeholderText: Translation.tr("Dark Mode start time (e.g. 18:00)")
        text: Config.options.light.darkMode.from
        wrapMode: TextEdit.NoWrap
        onTextChanged: Config.options.light.darkMode.from = text
    }

    MaterialTextArea {
        enabled: Config.options.light.darkMode.automatic
        Layout.fillWidth: true
        placeholderText: Translation.tr("Dark Mode end time (e.g. 06:00)")
        text: Config.options.light.darkMode.to
        wrapMode: TextEdit.NoWrap
        onTextChanged: Config.options.light.darkMode.to = text
    }

    ConfigSwitch {
        buttonIcon: "nightlight_round"
        text: Translation.tr("Automatic Night Light")
        checked: Config.options.light.night.automatic
        onCheckedChanged: Config.options.light.night.automatic = checked
    }

    MaterialTextArea {
        enabled: Config.options.light.night.automatic
        Layout.fillWidth: true
        placeholderText: Translation.tr("Night Light start time (e.g. 19:00)")
        text: Config.options.light.night.from
        wrapMode: TextEdit.NoWrap
        onTextChanged: Config.options.light.night.from = text
    }

    MaterialTextArea {
        enabled: Config.options.light.night.automatic
        Layout.fillWidth: true
        placeholderText: Translation.tr("Night Light end time (e.g. 06:00)")
        text: Config.options.light.night.to
        wrapMode: TextEdit.NoWrap
        onTextChanged: Config.options.light.night.to = text
    }

    ConfigSlider {
        buttonIcon: "wb_twilight"
        text: Translation.tr("Night Light Color Temperature")
        usePercentTooltip: false
        from: 1000
        to: 10000
        stepSize: 100
        value: Config.options.light.night.colorTemperature ?? 5000
        onValueChanged: Config.options.light.night.colorTemperature = Math.round(value)
    }

    ContentSubsection {
        title: Translation.tr("Remember Night Light")
        icon: "history"
        tooltip: Translation.tr("Restores the Night Light toggle and gamma level after a restart. With automatic mode on, a restored toggle still gives way at the next start or end time.")
        Layout.fillWidth: true

        ConfigSelectionArray {
            currentValue: Config.options.light.night.persistManual
            onSelected: newValue => Config.options.light.night.persistManual = newValue
            options: [
                { displayName: Translation.tr("Never"), icon: "block", value: "never" },
                { displayName: Translation.tr("Until reboot"), icon: "restart_alt", value: "session" },
                { displayName: Translation.tr("Always"), icon: "all_inclusive", value: "always" }
            ]
        }
    }

    ConfigSwitch {
        buttonIcon: "wb_twilight"
        text: Translation.tr("Dim below minimum brightness with gamma")
        description: Translation.tr("Brightness keys and the combined slider keep dimming with gamma once the backlight is at 0%. Turn off to control the backlight only.")
        checked: Config.options.light.gamma.dimBelowMinimum
        onCheckedChanged: {
            Config.options.light.gamma.dimBelowMinimum = checked;
            // Nothing would raise a leftover dim gamma anymore
            if (!checked && Hyprsunset.gamma !== 100)
                Hyprsunset.setGamma(100);
        }
    }

    ConfigSwitch {
        buttonIcon: "flash_off"
        text: Translation.tr("Anti-flashbang light filter")
        checked: Config.options.light.antiFlashbang.enable
        onCheckedChanged: Config.options.light.antiFlashbang.enable = checked
    }
}
