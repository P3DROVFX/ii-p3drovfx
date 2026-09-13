import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The tablet dock's own quick settings, as a page of Edit Mode's panel.
 *
 * Dedicated to the Tablet panel family's taskbar (modules/tablet/dock and
 * Config.options.tablet.dock). Replaces the desktop ii dock's appearance and
 * widget settings when editing under touch-first / tablet mode.
 */
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight + 16
    clip: true

    ColumnLayout {
        id: column
        width: root.width
        spacing: 4

        EditPanelSectionLabel {
            text: Translation.tr("Dimensions & reservation")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "height"
            title: Translation.tr("Taskbar height")
            trailingKind: "stepper"
            valueText: (Config.options.tablet.dock.height ?? 96) + " px"
            stepDownEnabled: (Config.options.tablet.dock.height ?? 96) > 54
            stepUpEnabled: (Config.options.tablet.dock.height ?? 96) < 160
            onStepDown: Config.options.tablet.dock.height = Math.max(54, (Config.options.tablet.dock.height ?? 96) - 4)
            onStepUp: Config.options.tablet.dock.height = Math.min(160, (Config.options.tablet.dock.height ?? 96) + 4)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "photo_size_select_small"
            title: Translation.tr("App icon size")
            trailingKind: "stepper"
            valueText: (Config.options.tablet.dock.iconSize ?? 48) + " px"
            stepDownEnabled: (Config.options.tablet.dock.iconSize ?? 48) > 32
            stepUpEnabled: (Config.options.tablet.dock.iconSize ?? 48) < 80
            onStepDown: Config.options.tablet.dock.iconSize = Math.max(32, (Config.options.tablet.dock.iconSize ?? 48) - 4)
            onStepUp: Config.options.tablet.dock.iconSize = Math.min(80, (Config.options.tablet.dock.iconSize ?? 48) + 4)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "space_bar"
            title: Translation.tr("Reserve screen space")
            subtitle: Translation.tr("Keep real work area for tiled apps")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.reserveSpace ?? true
            onActivated: Config.options.tablet.dock.reserveSpace = !(Config.options.tablet.dock.reserveSpace ?? true)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "push_pin"
            title: Translation.tr("Keep app row pinned")
            subtitle: Translation.tr("Keep launcher icons always visible")
            trailingKind: "switch"
            switchChecked: Config.options.dock.pinnedOnStartup ?? false
            onActivated: Config.options.dock.pinnedOnStartup = !(Config.options.dock.pinnedOnStartup ?? false)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "visibility_off"
            title: Translation.tr("Hide app row on occupied workspaces")
            subtitle: Translation.tr("Keep the home screen clean when windows are open")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.autoHideOnOccupiedWorkspace ?? true
            onActivated: Config.options.tablet.dock.autoHideOnOccupiedWorkspace = !(Config.options.tablet.dock.autoHideOnOccupiedWorkspace ?? true)
        }

        EditPanelSectionLabel {
            Layout.topMargin: 6
            text: Translation.tr("Search pill")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "search"
            title: Translation.tr("Show search pill")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.showSearchBar ?? true
            onActivated: Config.options.tablet.dock.showSearchBar = !(Config.options.tablet.dock.showSearchBar ?? true)
        }

        EditOptionChips {
            Layout.topMargin: 2
            visible: Config.options.tablet.dock.showSearchBar ?? true
            label: Translation.tr("Search bar style")
            currentValue: Config.options.tablet.dock.searchBarStyle ?? "extended"
            options: [
                { "displayName": Translation.tr("Extended"), "icon": "pill", "value": "extended" },
                { "displayName": Translation.tr("Compact"), "icon": "search", "value": "compact" }
            ]
            onSelected: value => Config.options.tablet.dock.searchBarStyle = value
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: (Config.options.tablet.dock.showSearchBar ?? true) && (Config.options.tablet.dock.searchBarStyle ?? "extended") === "extended"
            first: false
            last: true
            symbol: "straighten"
            title: Translation.tr("Search pill width")
            trailingKind: "stepper"
            valueText: (Config.options.tablet.dock.searchBarWidth ?? 320) + " px"
            stepDownEnabled: (Config.options.tablet.dock.searchBarWidth ?? 320) > 180
            stepUpEnabled: (Config.options.tablet.dock.searchBarWidth ?? 320) < 560
            onStepDown: Config.options.tablet.dock.searchBarWidth = Math.max(180, (Config.options.tablet.dock.searchBarWidth ?? 320) - 20)
            onStepUp: Config.options.tablet.dock.searchBarWidth = Math.min(560, (Config.options.tablet.dock.searchBarWidth ?? 320) + 20)
        }

        EditPanelSectionLabel {
            Layout.topMargin: 6
            text: Translation.tr("Navigation & recents")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "navigation"
            title: Translation.tr("Show navigation pill")
            subtitle: Translation.tr("Back, Home and Recents buttons")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.showNavigation ?? true
            onActivated: Config.options.tablet.dock.showNavigation = !(Config.options.tablet.dock.showNavigation ?? true)
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: Config.options.tablet.dock.showNavigation ?? true
            first: false
            last: false
            symbol: "visibility"
            title: Translation.tr("Keep navigation visible")
            subtitle: Translation.tr("Even when launcher app row is hidden")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.keepNavigationVisible ?? true
            onActivated: Config.options.tablet.dock.keepNavigationVisible = !(Config.options.tablet.dock.keepNavigationVisible ?? true)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "running_with_errors"
            title: Translation.tr("Show running apps")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.showRunningApps ?? true
            onActivated: Config.options.tablet.dock.showRunningApps = !(Config.options.tablet.dock.showRunningApps ?? true)
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: Config.options.tablet.dock.showRunningApps ?? true
            first: false
            last: true
            symbol: "apps"
            title: Translation.tr("Running apps limit")
            trailingKind: "stepper"
            valueText: (Config.options.tablet.dock.maximumRecents ?? 0) === 0 ? Translation.tr("Auto-fit") : `${Config.options.tablet.dock.maximumRecents}`
            stepDownEnabled: (Config.options.tablet.dock.maximumRecents ?? 0) > 0
            stepUpEnabled: (Config.options.tablet.dock.maximumRecents ?? 0) < 16
            onStepDown: Config.options.tablet.dock.maximumRecents = Math.max(0, (Config.options.tablet.dock.maximumRecents ?? 0) - 1)
            onStepUp: Config.options.tablet.dock.maximumRecents = Math.min(16, (Config.options.tablet.dock.maximumRecents ?? 0) + 1)
        }

        EditPanelSectionLabel {
            Layout.topMargin: 6
            text: Translation.tr("Dock elements & controls")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "apps_outage"
            title: Translation.tr("Show app drawer button")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.showAppDrawerButton ?? true
            onActivated: Config.options.tablet.dock.showAppDrawerButton = !(Config.options.tablet.dock.showAppDrawerButton ?? true)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "vertical_split"
            title: Translation.tr("Show app dividers")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.showAppDividers ?? true
            onActivated: Config.options.tablet.dock.showAppDividers = !(Config.options.tablet.dock.showAppDividers ?? true)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "swap_horiz"
            title: Translation.tr("Show workspace arrows")
            subtitle: Translation.tr("Navigate between home screens")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.showWorkspaceArrows ?? true
            onActivated: Config.options.tablet.dock.showWorkspaceArrows = !(Config.options.tablet.dock.showWorkspaceArrows ?? true)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "linear_scale"
            title: Translation.tr("Show home-screen page counter")
            trailingKind: "switch"
            switchChecked: Config.options.tablet.dock.showPageCounter ?? true
            onActivated: Config.options.tablet.dock.showPageCounter = !(Config.options.tablet.dock.showPageCounter ?? true)
        }
    }
}
