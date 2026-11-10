import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Edit Mode's "Desktop icons" page: how the desktop's shortcut icons are
 * sized, laid out and drawn. Every control writes
 * Config.options.background.desktopIcons (and desktopIconScale); the icon
 * store re-lays the icons out when the cell size changes, so a new size or
 * spacing keeps the arrangement instead of piling it up.
 *
 * Order and one-shot arranging live in the desktop menu's own page, next to
 * the icons they move; this page is the look.
 */
StyledFlickable {
    id: root

    readonly property var options: Config.options.background.desktopIcons

    contentHeight: column.implicitHeight
    clip: true

    ColumnLayout {
        id: column
        width: root.width
        spacing: 6

        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Icon size")
            currentValue: Config.options.background.desktopIconScale ?? 1
            options: [
                { "displayName": "0.75×", "value": 0.75 },
                { "displayName": "1×", "value": 1 },
                { "displayName": "1.25×", "value": 1.25 },
                { "displayName": "1.5×", "value": 1.5 },
                { "displayName": "1.75×", "value": 1.75 },
                { "displayName": "2×", "value": 2 },
            ]
            onSelected: value => Config.options.background.desktopIconScale = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Spacing")
            currentValue: root.options.spacing
            options: [
                { "displayName": Translation.tr("Compact"), "value": "compact" },
                { "displayName": Translation.tr("Normal"), "value": "normal" },
                { "displayName": Translation.tr("Wide"), "value": "wide" },
            ]
            onSelected: value => Config.options.background.desktopIcons.spacing = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Start from")
            currentValue: root.options.origin
            options: [
                { "displayName": Translation.tr("Top left"), "value": "topLeft", "icon": "north_west" },
                { "displayName": Translation.tr("Top right"), "value": "topRight", "icon": "north_east" },
                { "displayName": Translation.tr("Bottom left"), "value": "bottomLeft", "icon": "south_west" },
                { "displayName": Translation.tr("Bottom right"), "value": "bottomRight", "icon": "south_east" },
            ]
            onSelected: value => Config.options.background.desktopIcons.origin = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Fill")
            currentValue: root.options.flow
            options: [
                { "displayName": Translation.tr("Columns"), "value": "columns", "icon": "view_column" },
                { "displayName": Translation.tr("Rows"), "value": "rows", "icon": "table_rows" },
            ]
            onSelected: value => Config.options.background.desktopIcons.flow = value
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 4
            first: true
            last: false
            symbol: "fit_screen"
            title: Translation.tr("Keep clear of bar and dock")
            trailingKind: "switch"
            switchChecked: root.options.avoidPanels
            onActivated: Config.options.background.desktopIcons.avoidPanels = !root.options.avoidPanels
        }
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "padding"
            title: Translation.tr("Edge margin")
            trailingKind: "stepper"
            valueText: `${root.options.margin} px`
            stepDownEnabled: root.options.margin > 0
            stepUpEnabled: root.options.margin < 120
            onStepUp: Config.options.background.desktopIcons.margin = Math.min(120, root.options.margin + 8)
            onStepDown: Config.options.background.desktopIcons.margin = Math.max(0, root.options.margin - 8)
        }

        EditOptionChips {
            Layout.fillWidth: true
            Layout.topMargin: 4
            label: Translation.tr("Labels")
            currentValue: root.options.labels
            options: [
                { "displayName": Translation.tr("Always"), "value": "always" },
                { "displayName": Translation.tr("On hover"), "value": "hover" },
                { "displayName": Translation.tr("Never"), "value": "never" },
            ]
            onSelected: value => Config.options.background.desktopIcons.labels = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            visible: root.options.labels !== "never"
            label: Translation.tr("Label lines")
            currentValue: root.options.labelLines
            options: [
                { "displayName": Translation.tr("One"), "value": 1 },
                { "displayName": Translation.tr("Two"), "value": 2 },
            ]
            onSelected: value => Config.options.background.desktopIcons.labelLines = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            visible: root.options.labels !== "never"
            label: Translation.tr("Label style")
            currentValue: root.options.labelStyle
            options: [
                { "displayName": Translation.tr("Auto"), "value": "auto" },
                { "displayName": Translation.tr("Shadow"), "value": "shadow" },
                { "displayName": Translation.tr("Pill"), "value": "pill" },
            ]
            onSelected: value => Config.options.background.desktopIcons.labelStyle = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Icon background")
            currentValue: root.options.iconBackground
            options: [
                { "displayName": Translation.tr("None"), "value": "none" },
                { "displayName": Translation.tr("Translucent"), "value": "translucent" },
                { "displayName": Translation.tr("Circle"), "value": "circle", "icon": "circle" },
                { "displayName": Translation.tr("Squircle"), "value": "squircle", "icon": "square" },
            ]
            onSelected: value => Config.options.background.desktopIcons.iconBackground = value
        }

        EditPanelSectionLabel {
            text: Translation.tr("App groups")
        }
        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Group shape")
            currentValue: root.options.groupShape ?? "auto"
            options: [
                { "displayName": Translation.tr("Auto"), "value": "auto" },
                { "displayName": Translation.tr("Rounded"), "value": "rounded", "icon": "rounded_corner" },
                { "displayName": Translation.tr("Squircle"), "value": "squircle", "icon": "square" },
                { "displayName": Translation.tr("Circle"), "value": "circle", "icon": "circle" },
                { "displayName": Translation.tr("Cookie"), "value": "cookie", "icon": "cookie" },
                { "displayName": Translation.tr("Clover"), "value": "clover", "icon": "filter_vintage" },
            ]
            onSelected: value => Config.options.background.desktopIcons.groupShape = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Group colour")
            currentValue: root.options.groupColor ?? "auto"
            options: [
                { "displayName": Translation.tr("Auto"), "value": "auto" },
                { "displayName": Translation.tr("Primary"), "value": "primary" },
                { "displayName": Translation.tr("Secondary"), "value": "secondary" },
                { "displayName": Translation.tr("Tertiary"), "value": "tertiary" },
                { "displayName": Translation.tr("Neutral"), "value": "neutral" },
                { "displayName": Translation.tr("Glass"), "value": "glass", "icon": "blur_on" },
            ]
            onSelected: value => Config.options.background.desktopIcons.groupColor = value
        }
        EditOptionChips {
            Layout.fillWidth: true
            label: Translation.tr("Icon mask")
            currentValue: root.options.groupIconMask ?? "auto"
            options: [
                { "displayName": Translation.tr("Auto"), "value": "auto" },
                { "displayName": Translation.tr("None"), "value": "none" },
                { "displayName": Translation.tr("Rounded"), "value": "rounded", "icon": "rounded_corner" },
                { "displayName": Translation.tr("Squircle"), "value": "squircle", "icon": "square" },
                { "displayName": Translation.tr("Circle"), "value": "circle", "icon": "circle" },
            ]
            onSelected: value => Config.options.background.desktopIcons.groupIconMask = value
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            text: Translation.tr("Extend a group from its right-click menu to show three apps big and the rest in a small group. A group can also keep its own shape, colour and icon mask there. Auto clips the icons to the group's shape.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 4
            first: true
            last: false
            symbol: "fiber_manual_record"
            title: Translation.tr("Running indicator")
            trailingKind: "switch"
            switchChecked: root.options.runningBadges
            onActivated: Config.options.background.desktopIcons.runningBadges = !root.options.runningBadges
        }
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "notifications"
            title: Translation.tr("Notification count")
            trailingKind: "switch"
            switchChecked: root.options.notificationBadges
            onActivated: Config.options.background.desktopIcons.notificationBadges = !root.options.notificationBadges
        }
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "arrow_outward"
            title: Translation.tr("Link badge")
            trailingKind: "switch"
            switchChecked: root.options.linkBadges ?? true
            onActivated: Config.options.background.desktopIcons.linkBadges = !(root.options.linkBadges ?? true)
        }
    }
}
