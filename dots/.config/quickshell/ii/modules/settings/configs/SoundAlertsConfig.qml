import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Audio Controls")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }

        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "arrow_warm_up"
            text: Translation.tr("Max allowed volume increase")
            value: Config.options.audio.protection.maxAllowedIncrease
            from: 0
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowedIncrease = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "vertical_align_top"
            text: Translation.tr("Volume limit")
            value: Config.options.audio.protection.maxAllowed
            from: 0
            to: 154
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowed = value;
            }
        }
    }

    ContentSection {
        icon: "notifications_active"
        title: Translation.tr("Interactive Alerts")

        ConfigSwitch {
            buttonIcon: "battery_alert"
            text: Translation.tr("Battery sound toggle")
            checked: Config.options.sounds.battery
            onCheckedChanged: {
                Config.options.sounds.battery = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "av_timer"
            text: Translation.tr("Pomodoro sound toggle")
            checked: Config.options.sounds.pomodoro
            onCheckedChanged: {
                Config.options.sounds.pomodoro = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "alarm"
            text: Translation.tr("Alarm sound toggle")
            checked: Config.options.sounds.alarm
            onCheckedChanged: {
                Config.options.sounds.alarm = checked;
            }
        }
    }
}
