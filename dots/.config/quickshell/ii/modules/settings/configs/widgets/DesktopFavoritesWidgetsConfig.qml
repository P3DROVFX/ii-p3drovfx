pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.utility
import qs.modules.settings.configs.widgets

/*
 * One page for the Favorites widgets - 1x1 grid and 1x0.5 row. The sites are
 * the dock's Favorites list, edited on its own page.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets

    WidgetPageHeader {
        title: Translation.tr("Favorites Widgets Options")
        onBack: root.goBack()
    }

    WidgetPreviewStage {
        columns: 2
        rows: 1

        WidgetPreviewSlot {
            FavoritesGridWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            FavoritesRowWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Sites")
        icon: "bookmarks"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The widgets show the first four of the dock's Favorites. Dropping a link from the browser on a widget adds it to the list.")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        RippleButtonWithIcon {
            materialIcon: "edit"
            mainText: Translation.tr("Edit favorites")
            onClicked: GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml")
        }
    }

    ContentSection {
        title: Translation.tr("Favorites (1x1)")
        icon: "apps"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "favorites_1x1" }
            WidgetSizeSlider { options: root.widgets.favorites_1x1 }
            ConfigSwitch {
                buttonIcon: "label"
                text: Translation.tr("Show site names")
                checked: root.widgets.favorites_1x1.showLabels
                onCheckedChanged: root.widgets.favorites_1x1.showLabels = checked
            }
        }
    }

    ContentSection {
        title: Translation.tr("Favorites (1x0.5)")
        icon: "view_week"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "favorites_row" }
            WidgetSizeSlider { options: root.widgets.favorites_row }
            ConfigSwitch {
                buttonIcon: "label"
                text: Translation.tr("Show site names")
                checked: root.widgets.favorites_row.showLabels
                onCheckedChanged: root.widgets.favorites_row.showLabels = checked
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
