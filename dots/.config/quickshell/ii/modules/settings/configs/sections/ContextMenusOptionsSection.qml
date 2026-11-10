import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for Background → Context menus: every option its stage, cards, segmented
// toggle and entry editor draw, as the original controls. SearchRegistry indexes this
// file (see SettingsPageRegistry `searchSources`) so they stay searchable, and its
// results open the sub-page (`searchSubPages`).
ColumnLayout {
    ContentSection {
        icon: "density_small"
        title: Translation.tr("Style")

        ConfigSelectionArray {
            currentValue: Config.options.contextMenu.style
            onSelected: newValue => Config.options.contextMenu.style = newValue
            options: [
                { displayName: Translation.tr("Comfortable"), icon: "view_agenda", value: "comfortable" },
                { displayName: Translation.tr("Compact"), icon: "density_small", value: "compact" }
            ]
        }

        ConfigSlider {
            buttonIcon: "zoom_in"
            text: Translation.tr("Menu size")
            from: 0.5
            to: 2
            stepSize: 0.05
            value: Config.options.contextMenu.scale
            onValueChanged: Config.options.contextMenu.scale = value
        }
    }

    ContentSection {
        icon: "subdirectory_arrow_right"
        title: Translation.tr("Submenus")

        ConfigSelectionArray {
            currentValue: Config.options.contextMenu.submenus
            onSelected: newValue => Config.options.contextMenu.submenus = newValue
            options: [
                { displayName: Translation.tr("Inside the menu"), icon: "low_priority", value: "inline" },
                { displayName: Translation.tr("Beside the menu"), icon: "splitscreen_right", value: "cascade" }
            ]
        }
    }

    ContentSection {
        icon: "format_list_bulleted"
        title: Translation.tr("Entries")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            text: Translation.tr("Reorder, hide or add entries, put them in the icon bar, and add custom commands to any right-click menu.")
        }
    }
}
