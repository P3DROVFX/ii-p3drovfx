import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../dock/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * What the dock carries besides apps: its widgets and its utility buttons.
 *
 * The catalogue could pin and unpin apps and nothing else, so the media card,
 * the weather card and the four buttons - everything the dock draws that is
 * not an app - could only be reached from Settings. They are switches, not
 * layout edits, so nothing here records a history entry.
 */
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    readonly property var widgetRows: [
        { "key": "enableMediaWidget", "symbol": "music_note", "title": Translation.tr("Media"),
            "subtitle": Translation.tr("Costs the most while it is on") },
        { "key": "enableWeatherWidget", "symbol": "cloud", "title": Translation.tr("Weather") },
        { "key": "enableSportsWidget", "symbol": "sports_soccer", "title": Translation.tr("Sports") },
        { "key": "enableLivePreviewWidget", "symbol": "preview", "title": Translation.tr("Live preview"),
            "subtitle": Translation.tr("A running window, drawn on the dock") },
        { "key": "enableTasksWidget", "symbol": "checklist", "title": Translation.tr("Tasks"),
            "subtitle": Translation.tr("Open tasks from your provider") },
        { "key": "showPhoneButton", "symbol": "smartphone", "title": Translation.tr("Phone mirror") }
    ]

    // What the widget stack may hold, in the order they are offered.
    readonly property var stackRows: [
        { "member": "media", "symbol": "music_note", "title": Translation.tr("Media") },
        { "member": "weather", "symbol": "cloud", "title": Translation.tr("Weather") },
        { "member": "tasks", "symbol": "checklist", "title": Translation.tr("Tasks") },
        { "member": "sports", "symbol": "sports_soccer", "title": Translation.tr("Sports") },
        { "member": "livePreview", "symbol": "preview", "title": Translation.tr("Live preview") }
    ]

    function toggleStackMember(member) {
        const items = Array.from(Config.options.dock.widgetStackItems ?? []);
        const index = items.indexOf(member);
        if (index >= 0)
            items.splice(index, 1);
        else
            items.push(member);
        Config.options.dock.widgetStackItems = items;
    }

    readonly property var buttonRows: [
        { "key": "showOverviewButton", "symbol": "apps", "title": Translation.tr("Overview") },
        { "key": "showPinButton", "symbol": "push_pin", "title": Translation.tr("Pin") },
        { "key": "showTrashButton", "symbol": "delete", "title": Translation.tr("Trash") },
        { "key": "showNotificationBadges", "symbol": "notifications", "title": Translation.tr("Notification badges") },
        { "key": "showDividers", "symbol": "more_vert", "title": Translation.tr("Dividers") }
    ]

    ColumnLayout {
        id: column
        width: root.width
        spacing: 4

        EditPanelSectionLabel {
            text: Translation.tr("Widgets")
        }

        EditPanelNotice {
            Layout.fillWidth: true
            symbol: "info"
            text: Translation.tr("Every widget the dock draws costs CPU while it is on. Media and Live preview cost the most.")
        }

        Repeater {
            model: root.widgetRows

            delegate: EditPanelRow {
                required property var modelData
                required property int index
                staggerIndex: index
                Layout.fillWidth: true
                Layout.topMargin: index === 0 ? 6 : 0
                first: index === 0
                last: index === root.widgetRows.length - 1
                symbol: modelData.symbol
                title: modelData.title
                subtitle: modelData.subtitle ?? ""
                trailingKind: "switch"
                switchChecked: Config.options.dock[modelData.key] ?? false
                onActivated: Config.options.dock[modelData.key] = !(Config.options.dock[modelData.key] ?? false)
            }
        }

        EditPanelSectionLabel {
            text: Translation.tr("Utility widgets")
        }

        // One switch per utility; size and options live on the widget's
        // right-click menu and in Settings.
        Repeater {
            model: DockUtilityCatalog.kinds

            delegate: EditPanelRow {
                required property var modelData
                required property int index
                readonly property bool added: DockUtilityCatalog.entryFor(Config.options.dock.utilityWidgets ?? [], modelData.kind) !== null
                staggerIndex: index
                Layout.fillWidth: true
                Layout.topMargin: index === 0 ? 6 : 0
                first: index === 0
                last: index === DockUtilityCatalog.kinds.length - 1
                symbol: modelData.symbol
                title: Translation.tr(modelData.title)
                subtitle: Translation.tr(modelData.description)
                trailingKind: "switch"
                switchChecked: added
                onActivated: Config.options.dock.utilityWidgets = added
                    ? DockUtilityCatalog.withoutKind(Config.options.dock.utilityWidgets ?? [], modelData.kind)
                    : DockUtilityCatalog.withKind(Config.options.dock.utilityWidgets ?? [], modelData.kind, false)
            }
        }

        EditPanelSectionLabel {
            text: Translation.tr("Widget stack")
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            first: true
            last: !(Config.options.dock.enableWidgetStack ?? false)
            symbol: "stacks"
            title: Translation.tr("Stack widgets")
            subtitle: Translation.tr("One slot, turned with the wheel")
            trailingKind: "switch"
            switchChecked: Config.options.dock.enableWidgetStack ?? false
            onActivated: Config.options.dock.enableWidgetStack = !(Config.options.dock.enableWidgetStack ?? false)
        }

        Repeater {
            model: (Config.options.dock.enableWidgetStack ?? false) ? root.stackRows : []

            delegate: EditPanelRow {
                required property var modelData
                required property int index
                staggerIndex: index
                Layout.fillWidth: true
                first: false
                last: index === root.stackRows.length - 1
                symbol: modelData.symbol
                title: modelData.title
                trailingKind: "switch"
                switchChecked: (Config.options.dock.widgetStackItems ?? []).indexOf(modelData.member) >= 0
                onActivated: root.toggleStackMember(modelData.member)
            }
        }

        EditPanelSectionLabel {
            text: Translation.tr("Buttons")
        }

        Repeater {
            model: root.buttonRows

            delegate: EditPanelRow {
                required property var modelData
                required property int index
                staggerIndex: index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.buttonRows.length - 1
                symbol: modelData.symbol
                title: modelData.title
                trailingKind: "switch"
                switchChecked: Config.options.dock[modelData.key] ?? false
                onActivated: Config.options.dock[modelData.key] = !(Config.options.dock[modelData.key] ?? false)
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
