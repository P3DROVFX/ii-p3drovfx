import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for Dock → Widgets & buttons: the dock's own widgets and buttons,
// which that page draws as cards; SearchRegistry indexes this file (see
// SettingsPageRegistry `searchSources`) so they stay searchable.
ColumnLayout {
    ContentSection {
        icon: "widgets"
        title: Translation.tr("Dock widgets")

        ConfigSwitch {
            buttonIcon: "play_circle"
            text: Translation.tr("Media")
            checked: Config.options.dock.enableMediaWidget
            onCheckedChanged: Config.options.dock.enableMediaWidget = checked
        }
        ConfigSwitch {
            buttonIcon: "cloud"
            text: Translation.tr("Weather")
            checked: Config.options.dock.enableWeatherWidget
            onCheckedChanged: Config.options.dock.enableWeatherWidget = checked
        }
        ConfigSwitch {
            buttonIcon: "checklist"
            text: Translation.tr("Tasks")
            checked: Config.options.dock.enableTasksWidget ?? false
            onCheckedChanged: Config.options.dock.enableTasksWidget = checked
        }
        ConfigSwitch {
            buttonIcon: "sports_soccer"
            text: Translation.tr("Sports")
            checked: Config.options.dock.enableSportsWidget ?? true
            onCheckedChanged: Config.options.dock.enableSportsWidget = checked
        }
        ConfigSwitch {
            buttonIcon: "live_tv"
            text: Translation.tr("Live Preview")
            checked: Config.options.dock.enableLivePreviewWidget ?? false
            onCheckedChanged: Config.options.dock.enableLivePreviewWidget = checked
        }
        ConfigSwitch {
            buttonIcon: "smartphone"
            text: Translation.tr("Phone mirror")
            checked: Config.options.dock.showPhoneButton ?? true
            onCheckedChanged: Config.options.dock.showPhoneButton = checked
        }
    }

    ContentSection {
        icon: "smart_button"
        title: Translation.tr("Dock buttons")

        ConfigSwitch {
            buttonIcon: "apps"
            text: Translation.tr("Overview button")
            checked: Config.options.dock.showOverviewButton
            onCheckedChanged: Config.options.dock.showOverviewButton = checked
        }
        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr("Pin button")
            checked: Config.options.dock.showPinButton
            onCheckedChanged: Config.options.dock.showPinButton = checked
        }
        ConfigSwitch {
            buttonIcon: "delete"
            text: Translation.tr("Trash button")
            checked: Config.options.dock.showTrashButton
            onCheckedChanged: Config.options.dock.showTrashButton = checked
        }
    }
}
