import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    title: Translation.tr("Water")

    ContentSection {
        title: Translation.tr("Goal")
        icon: "water_drop"
        tooltip: Translation.tr("Shared with the water reminder desktop widget")

        ConfigSpinBox {
            icon: "flag"
            text: Translation.tr("Glasses per day")
            value: Config.options.background.widgets.water_reminder.dailyGoal
            from: 1
            to: 30
            onValueChanged: Config.options.background.widgets.water_reminder.dailyGoal = value
        }
        ConfigSpinBox {
            icon: "local_drink"
            text: Translation.tr("Glass size (ml)")
            value: Config.options.dock.utilities.water.glassMl
            from: 50
            to: 1000
            stepSize: 50
            onValueChanged: Config.options.dock.utilities.water.glassMl = value
        }
    }
}
