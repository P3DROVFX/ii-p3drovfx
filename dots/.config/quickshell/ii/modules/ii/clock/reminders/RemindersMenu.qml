pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The ⋮ menu: Samsung Reminder's Sync now, sort order, Pin important to top, Show
 * completed, the card/list view, Manage categories, Recycle bin and Settings. Built only
 * while open (RemindersTab's Loader).
 */
Rectangle {
    id: root

    property string sortBy: "alertTime"
    property bool pinImportant: true
    property bool showCompleted: false
    property string itemView: "card"
    property string listId: ""
    property bool inTrash: false

    signal optionChanged(string key, var value)
    signal manageRequested()
    signal trashRequested()
    signal settingsRequested()
    signal syncRequested()
    signal editCategoryRequested()
    signal closed()

    readonly property var sorts: [
        { id: "alertTime", label: Translation.tr("Alert time") },
        { id: "modified", label: Translation.tr("Date modified") },
        { id: "created", label: Translation.tr("Date created") },
        { id: "name", label: Translation.tr("Name") },
        { id: "category", label: Translation.tr("Category") }
    ]

    implicitWidth: 260
    implicitHeight: column.implicitHeight + 16
    radius: ClockStyle.radiusLarge
    color: ClockStyle.colSurfaceHigh

    StyledRectangularShadow {
        target: root
        z: -1
    }

    // Swallow clicks so the dismiss area underneath doesn't close the menu.
    MouseArea {
        anchors.fill: parent
    }

    Keys.onEscapePressed: root.closed()

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 8
        spacing: 0

        MenuRow {
            visible: Config.options.clockApp.reminders.todoSync.enable
            symbol: RemindersSync.syncing ? "sync" : "cloud_sync"
            label: RemindersSync.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
            detail: RemindersSync.statusText
            onClicked: root.syncRequested()
        }

        MenuRow {
            visible: root.listId.startsWith("cat:")
            symbol: "edit"
            label: Translation.tr("Edit category")
            onClicked: root.editCategoryRequested()
        }

        Caption {
            text: Translation.tr("Sort by")
        }

        Repeater {
            model: root.sorts

            MenuRow {
                required property var modelData
                symbol: root.sortBy === modelData.id ? "radio_button_checked" : "radio_button_unchecked"
                label: modelData.label
                onClicked: root.optionChanged("sortBy", modelData.id)
            }
        }

        Divider {}

        MenuRow {
            symbol: root.pinImportant ? "check_box" : "check_box_outline_blank"
            label: Translation.tr("Pin important to top")
            onClicked: root.optionChanged("pinImportant", !root.pinImportant)
        }

        MenuRow {
            symbol: root.showCompleted ? "check_box" : "check_box_outline_blank"
            label: Translation.tr("Show completed in categories")
            onClicked: root.optionChanged("showCompleted", !root.showCompleted)
        }

        MenuRow {
            symbol: root.itemView === "card" ? "view_agenda" : "view_list"
            label: root.itemView === "card" ? Translation.tr("View as list") : Translation.tr("View as cards")
            onClicked: root.optionChanged("view", root.itemView === "card" ? "list" : "card")
        }

        Divider {}

        MenuRow {
            symbol: "tune"
            label: Translation.tr("Manage categories")
            onClicked: root.manageRequested()
        }

        MenuRow {
            visible: !root.inTrash
            symbol: "delete"
            label: Translation.tr("Recycle bin")
            detail: RemindersService.trashed.length > 0 ? String(RemindersService.trashed.length) : ""
            onClicked: root.trashRequested()
        }

        MenuRow {
            symbol: "settings"
            label: Translation.tr("Settings")
            onClicked: root.settingsRequested()
        }
    }

    component Caption: StyledText {
        Layout.topMargin: 6
        Layout.leftMargin: 12
        Layout.bottomMargin: 2
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Bold
        color: ClockStyle.colSubtext
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 1
        color: ClockStyle.colOutline
    }

    component MenuRow: RippleButton {
        id: menuRow
        property string symbol: ""
        property string label: ""
        property string detail: ""

        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: ClockStyle.radiusSmall
        colBackground: "transparent"
        colBackgroundHover: ClockStyle.colSurfaceHover
        colRipple: ClockStyle.colSurfaceActive

        contentItem: RowLayout {
            spacing: 10

            MaterialSymbol {
                Layout.leftMargin: 10
                text: menuRow.symbol
                iconSize: ClockStyle.iconSmall + 2
                color: ClockStyle.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: menuRow.label
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                color: ClockStyle.colOnSurface
            }

            StyledText {
                Layout.rightMargin: 10
                Layout.maximumWidth: 110
                visible: menuRow.detail.length > 0
                text: menuRow.detail
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }
}
