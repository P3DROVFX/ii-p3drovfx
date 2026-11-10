import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    title: Translation.tr("Stopwatch")

    ContentSection {
        title: Translation.tr("Square widget")
        icon: "timer"

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Click starts and pauses")
            checked: Config.options.dock.utilities.stopwatch.clickToggles
            onCheckedChanged: Config.options.dock.utilities.stopwatch.clickToggles = checked
            StyledToolTip {
                text: Translation.tr("Off: a click opens the stopwatch panel instead")
            }
        }
    }
}
