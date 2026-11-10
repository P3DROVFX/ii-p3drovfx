import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    title: Translation.tr("Shelf")

    ContentSection {
        title: Translation.tr("Behavior")
        icon: "shelves"

        ConfigSwitch {
            buttonIcon: "move_item"
            text: Translation.tr("Take files off the shelf once dragged out")
            checked: Config.options.dock.utilities.shelf.removeAfterDrag
            onCheckedChanged: Config.options.dock.utilities.shelf.removeAfterDrag = checked
            StyledToolTip {
                text: Translation.tr("Applies to drags from the shelf panel. Off: files stay until you remove them")
            }
        }
    }
}
