pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.utility
import qs.modules.settings.configs.widgets

/*
 * One page for the Drop Shelf widgets - 1x1, 2x1 and 1x2. They hold the same
 * files as the dock's Shelf and the island's (FileShelf), so the behaviour
 * switch here is the dock's own.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets

    WidgetPageHeader {
        title: Translation.tr("Drop Shelf Options")
        onBack: root.goBack()
    }

    // [ 1x2 ][ 2x1       ]
    // [     ][ 1x1 ]
    WidgetPreviewStage {
        columns: 3
        rows: 2

        WidgetPreviewSlot {
            rowSpan: 2
            ShelfWidget1x2 {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }
        WidgetPreviewSlot {
            column: 1
            columnSpan: 2
            ShelfWidget2x1 {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 1
            ShelfWidget1x1 {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Behavior")
        icon: "shelves"

        ConfigSwitch {
            buttonIcon: "move_item"
            text: Translation.tr("Take files off the shelf once dragged out")
            checked: Config.options.dock.utilities.shelf.removeAfterDrag
            onCheckedChanged: Config.options.dock.utilities.shelf.removeAfterDrag = checked
            StyledToolTip {
                text: Translation.tr("Shared with the dock's Shelf. Off: files stay until you remove them")
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Drop files anywhere on a shelf. Drag the stack to hand every file over at once, or a single file from the list; a click opens it.")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        title: Translation.tr("Drop Shelf (1x1)")
        icon: "inbox"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "shelf_1x1" }
            WidgetSizeSlider { options: root.widgets.shelf_1x1 }
        }
    }

    ContentSection {
        title: Translation.tr("Drop Shelf (2x1)")
        icon: "grid_view"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "shelf_2x1" }
            WidgetSizeSlider { options: root.widgets.shelf_2x1 }
        }
    }

    ContentSection {
        title: Translation.tr("Drop Shelf (1x2)")
        icon: "view_agenda"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "shelf_1x2" }
            WidgetSizeSlider { options: root.widgets.shelf_1x2 }
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
