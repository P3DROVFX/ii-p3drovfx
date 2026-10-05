import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    id: page
    title: Translation.tr("Search")

    readonly property var cfg: Config.options.dock.utilities.search

    ContentSection {
        title: Translation.tr("Square widget")
        icon: "crop_square"
        tooltip: Translation.tr("The shape behind the magnifier")

        ShapePicker {
            Layout.fillWidth: true
            current: page.cfg.squareShape
            onPicked: name => page.cfg.squareShape = name
        }
    }

    ContentSection {
        title: Translation.tr("Background")
        icon: "rounded_corner"

        ConfigSwitch {
            buttonIcon: "rounded_corner"
            text: Translation.tr("Show the background")
            checked: page.cfg.background
            onCheckedChanged: page.cfg.background = checked
            StyledToolTip {
                text: Translation.tr("Square and wide. Off: the magnifier's shape fills the widget's height, straight on the dock")
            }
        }
    }
}
