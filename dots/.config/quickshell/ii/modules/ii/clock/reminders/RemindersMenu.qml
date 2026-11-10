pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The ⋮ options: Samsung Reminder's Sync now, sort order, Pin important to top, Show
 * completed, the card/list view, Manage categories, Recycle bin and Settings.
 *
 * A side sheet, not a menu floating over the page (guide §0.5, §7): it opens beside the
 * list it changes, so a new sort or view re-deals the reminders in sight while the sheet
 * stays open. Choices are the timetable's dashed chips, switches are ClockFormToggle rows,
 * places are ClockFormPicker rows; Sync and Settings sit as icon actions in the header.
 * Built on demand by ClockSidePanel and destroyed once it slides away.
 */
ClockSheet {
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

    readonly property bool syncEnabled: Config.options.clockApp.reminders.todoSync.enable
    readonly property var sorts: [
        { id: "alertTime", icon: "schedule", label: Translation.tr("Alert time") },
        { id: "modified", icon: "edit_calendar", label: Translation.tr("Date modified") },
        { id: "created", icon: "calendar_add_on", label: Translation.tr("Date created") },
        { id: "name", icon: "sort_by_alpha", label: Translation.tr("Name") },
        { id: "category", icon: "category", label: Translation.tr("Category") }
    ]
    readonly property var views: [
        { id: "card", icon: "view_agenda", label: Translation.tr("Cards") },
        { id: "list", icon: "view_list", label: Translation.tr("List") }
    ]

    title: Translation.tr("More options")
    subtitle: root.syncEnabled ? RemindersSync.statusText : ""

    headerActions: [
        ClockIconButton {
            visible: root.syncEnabled
            enabled: !RemindersSync.syncing
            symbol: RemindersSync.syncing ? "sync" : "cloud_sync"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            tooltip: RemindersSync.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
            onClicked: root.syncRequested()
        },
        ClockIconButton {
            symbol: "settings"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            tooltip: Translation.tr("Settings")
            onClicked: root.settingsRequested()
        }
    ]

    // ── Sort by ─────────────────────────────────────────────────────────
    Caption {
        text: Translation.tr("Sort by")
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.sorts

            ClockFormChip {
                required property var modelData
                symbol: modelData.icon
                label: modelData.label
                selected: root.sortBy === modelData.id
                onTriggered: root.optionChanged("sortBy", modelData.id)
            }
        }
    }

    // ── View ────────────────────────────────────────────────────────────
    Caption {
        text: Translation.tr("View")
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.views

            ClockFormChip {
                required property var modelData
                symbol: modelData.icon
                label: modelData.label
                selected: root.itemView === modelData.id
                onTriggered: root.optionChanged("view", modelData.id)
            }
        }
    }

    ClockFormToggle {
        Layout.topMargin: ClockStyle.gapSmall
        symbol: "keep"
        shapeKind: MaterialShape.Shape.Clover4Leaf
        label: Translation.tr("Pin important to top")
        checked: root.pinImportant
        onToggled: root.optionChanged("pinImportant", !root.pinImportant)
    }

    ClockFormToggle {
        symbol: "check_circle"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        label: Translation.tr("Show completed in categories")
        checked: root.showCompleted
        onToggled: root.optionChanged("showCompleted", !root.showCompleted)
    }

    // ── Places ──────────────────────────────────────────────────────────
    Caption {
        text: Translation.tr("Categories")
    }

    ClockFormPicker {
        visible: root.listId.startsWith("cat:")
        captionLeads: true
        symbol: "edit"
        shapeKind: MaterialShape.Shape.Gem
        caption: Translation.tr("Edit category")
        value: RemindersService.categoryName(root.listId.slice(4))
        onTriggered: root.editCategoryRequested()
    }

    ClockFormPicker {
        captionLeads: true
        symbol: "tune"
        shapeKind: MaterialShape.Shape.PuffyDiamond
        caption: Translation.tr("Manage categories")
        value: Translation.tr("Reorder, pin, edit or add")
        onTriggered: root.manageRequested()
    }

    ClockFormPicker {
        visible: !root.inTrash
        captionLeads: true
        symbol: "delete"
        shapeKind: MaterialShape.Shape.Cookie6Sided
        caption: Translation.tr("Recycle bin")
        value: RemindersService.trashed.length > 0
            ? RemindersStyle.countText(RemindersService.trashed.length) : Translation.tr("Empty")
        onTriggered: root.trashRequested()
    }

    /// A caption over the rows it names (guide §3: small, bold, on-surface-variant).
    component Caption: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: ClockStyle.gapTiny
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }
}
