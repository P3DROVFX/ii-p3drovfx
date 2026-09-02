import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The bar's own quick settings, as a page of Edit Mode's panel.
 *
 * The keys are the handful from Settings' "Bar basics & placement" and "Bar
 * appearance" that change what the bar LOOKS like - position, size, corner,
 * background, group - and nothing else. Everything deeper stays in Settings:
 * the point of this page is that arranging a bar and choosing how it is drawn
 * are the same task, and leaving the mode to do half of it is the thing that
 * made the mode feel unfinished.
 *
 * These are preferences, not layout edits, so nothing here records a history
 * entry - the same rule the snap toggle on the toolbar already follows.
 */
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    readonly property bool locked: ShellModePolicy.barPositionLocked

    ColumnLayout {
        id: column
        width: root.width
        spacing: 4

        EditPanelSectionLabel {
            text: Translation.tr("Placement")
        }

        EditOptionChips {
            label: Translation.tr("Position")
            currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
            lockedNote: root.locked ? ShellModePolicy.barPositionBlockedReasonKey : ""
            options: [
                { "displayName": Translation.tr("Top"), "icon": "arrow_upward", "value": 0 },
                { "displayName": Translation.tr("Left"), "icon": "arrow_back", "value": 2, "enabled": !root.locked },
                { "displayName": Translation.tr("Bottom"), "icon": "arrow_downward", "value": 1, "enabled": !root.locked },
                { "displayName": Translation.tr("Right"), "icon": "arrow_forward", "value": 3, "enabled": !root.locked }
            ]
            onSelected: value => ShellModePolicy.setBarPosition(value)
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            first: true
            last: !Config.options.bar.vertical
            symbol: "height"
            title: Translation.tr("Bar height")
            trailingKind: "stepper"
            valueText: Config.options.bar.sizes.height + " px"
            stepDownEnabled: Config.options.bar.sizes.height > 30
            stepUpEnabled: Config.options.bar.sizes.height < 50
            onStepDown: Config.options.bar.sizes.height = Math.max(30, Config.options.bar.sizes.height - 1)
            onStepUp: Config.options.bar.sizes.height = Math.min(50, Config.options.bar.sizes.height + 1)
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: Config.options.bar.vertical
            first: false
            last: true
            symbol: "straighten"
            title: Translation.tr("Bar width")
            trailingKind: "stepper"
            valueText: Config.options.bar.sizes.width + " px"
            stepDownEnabled: Config.options.bar.sizes.width > 30
            stepUpEnabled: Config.options.bar.sizes.width < 50
            onStepDown: Config.options.bar.sizes.width = Math.max(30, Config.options.bar.sizes.width - 1)
            onStepUp: Config.options.bar.sizes.width = Math.min(50, Config.options.bar.sizes.width + 1)
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            first: true
            last: true
            rowEnabled: !root.locked
            symbol: "visibility_off"
            title: Translation.tr("Automatically hide")
            subtitle: Translation.tr("Reveal the bar by touching the screen edge")
            trailingKind: "switch"
            switchChecked: Config.options.bar.autoHide.enable
            onActivated: Config.options.bar.autoHide.enable = !Config.options.bar.autoHide.enable
        }

        EditPanelSectionLabel {
            text: Translation.tr("Style")
        }

        EditOptionChips {
            label: Translation.tr("Corner style")
            currentValue: Config.options.bar.cornerStyle
            options: {
                const islands = Config.options.bar.barBackgroundStyle === 3;
                return [
                    { "displayName": Translation.tr("Hug"), "icon": "line_curve", "value": 0 },
                    { "displayName": Translation.tr("Float"), "icon": "page_header", "value": 1 },
                    { "displayName": Translation.tr("Rect"), "icon": "toolbar", "value": 2, "enabled": !islands },
                    { "displayName": Translation.tr("Island"), "icon": "water_drop", "value": 3, "enabled": !islands }
                ];
            }
            onSelected: value => {
                if (value === 3 && !Config.options.bar.vertical && Config.options.sidebar.sidebarStyle === "connect")
                    Config.options.sidebar.sidebarStyle = "default";
                Config.options.bar.cornerStyle = value;
            }
        }

        EditOptionChips {
            Layout.topMargin: 6
            label: Translation.tr("Background")
            currentValue: Config.options.bar.barBackgroundStyle
            lockedNote: root.locked
                ? Translation.tr("Visible and Adaptive are unavailable while the Dynamic Island sits in the bar's centre.")
                : ""
            options: [
                { "displayName": Translation.tr("Transparent"), "icon": "opacity", "value": 0 },
                { "displayName": Translation.tr("Visible"), "icon": "visibility", "value": 1, "enabled": !root.locked },
                { "displayName": Translation.tr("Adaptive"), "icon": "masked_transitions", "value": 2, "enabled": !root.locked },
                { "displayName": Translation.tr("Islands"), "icon": "grid_view", "value": 3 }
            ]
            onSelected: value => {
                Config.options.bar.barBackgroundStyle = value;
                // Settings does the same two repairs on this write; without
                // them Islands leaves an incompatible corner style and a
                // centred entry that no longer means anything.
                if (value === 3 && (Config.options.bar.cornerStyle === 2 || Config.options.bar.cornerStyle === 3))
                    Config.options.bar.cornerStyle = 0;
                if (value !== 3)
                    return;
                const centre = Config.options.bar.layouts.center;
                if (centre.some(entry => entry && entry.centered))
                    Config.options.bar.layouts.center = centre.map(entry => ({
                        "id": entry.id, "centered": false, "visible": entry.visible
                    }));
            }
        }

        EditOptionChips {
            Layout.topMargin: 6
            label: Translation.tr("Widget groups")
            currentValue: Config.options.bar.barGroupStyle
            options: [
                { "displayName": Translation.tr("Pills"), "icon": "location_chip", "value": 0 },
                { "displayName": Translation.tr("Island"), "icon": "shadow", "value": 1 },
                { "displayName": Translation.tr("Transparent"), "icon": "opacity", "value": 2 }
            ]
            onSelected: value => Config.options.bar.barGroupStyle = value
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: Config.options.bar.barGroupStyle !== 2
            first: true
            last: false
            symbol: "colorize"
            title: Translation.tr("Expressive group colour")
            trailingKind: "switch"
            switchChecked: Config.options.bar.expressiveGroupColor
            onActivated: Config.options.bar.expressiveGroupColor = !Config.options.bar.expressiveGroupColor
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: Config.options.bar.barGroupStyle !== 2 ? 0 : 6
            first: Config.options.bar.barGroupStyle === 2
            last: Config.options.bar.barBackgroundStyle !== 0
            symbol: "format_color_fill"
            title: Translation.tr("Expressive solid colours")
            trailingKind: "switch"
            switchChecked: Config.options.bar.expressiveColors
            onActivated: Config.options.bar.expressiveColors = !Config.options.bar.expressiveColors
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: Config.options.bar.barBackgroundStyle === 0
            first: false
            last: true
            symbol: "blur_on"
            title: Translation.tr("Transparent blur & dim")
            trailingKind: "switch"
            switchChecked: Config.options.bar.transparentGlow
            onActivated: Config.options.bar.transparentGlow = !Config.options.bar.transparentGlow
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            first: true
            last: true
            rowEnabled: !ShellModePolicy.barDropShadowBlocked
            symbol: "filter_drama"
            title: Translation.tr("Drop shadow")
            trailingKind: "switch"
            switchChecked: Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
            onActivated: Config.options.bar.dropShadow = !Config.options.bar.dropShadow
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
