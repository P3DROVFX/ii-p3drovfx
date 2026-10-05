import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    title: Translation.tr("Pomodoro")

    ContentSection {
        title: Translation.tr("Durations")
        icon: "target"
        tooltip: Translation.tr("Shared with the Clock app and the sidebar")

        ConfigSpinBox {
            icon: "target"
            text: Translation.tr("Focus (minutes)")
            value: Math.round(Config.options.time.pomodoro.focus / 60)
            from: 1
            to: 180
            onValueChanged: Config.options.time.pomodoro.focus = value * 60
        }
        ConfigSpinBox {
            icon: "coffee"
            text: Translation.tr("Break (minutes)")
            value: Math.round(Config.options.time.pomodoro.breakTime / 60)
            from: 1
            to: 60
            onValueChanged: Config.options.time.pomodoro.breakTime = value * 60
        }
        ConfigSpinBox {
            icon: "self_improvement"
            text: Translation.tr("Long break (minutes)")
            value: Math.round(Config.options.time.pomodoro.longBreak / 60)
            from: 1
            to: 120
            onValueChanged: Config.options.time.pomodoro.longBreak = value * 60
        }
        ConfigSpinBox {
            icon: "repeat"
            text: Translation.tr("Sessions per set")
            value: Config.options.time.pomodoro.cyclesBeforeLongBreak
            from: 2
            to: 8
            onValueChanged: Config.options.time.pomodoro.cyclesBeforeLongBreak = value
        }
    }

    ContentSection {
        title: Translation.tr("Square widget")
        icon: "crop_square"

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Click starts and pauses")
            checked: Config.options.dock.utilities.pomodoro.clickToggles
            onCheckedChanged: Config.options.dock.utilities.pomodoro.clickToggles = checked
            StyledToolTip {
                text: Translation.tr("Off: a click opens the pomodoro panel instead")
            }
        }
    }
}
