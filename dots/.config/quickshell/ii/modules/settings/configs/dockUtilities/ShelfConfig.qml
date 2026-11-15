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

        ConfigSwitch {
            buttonIcon: "smartphone"
            text: Translation.tr("Show the phone's recent photos and videos")
            checked: Config.options.dock.utilities.shelf.phoneRecents
            onCheckedChanged: Config.options.dock.utilities.shelf.phoneRecents = checked
            StyledToolTip {
                text: Translation.tr("ii tools phone: its newest photos, screenshots and videos appear on the shelf with a preview and stay on the phone until you drag one out")
            }
        }
    }
}
