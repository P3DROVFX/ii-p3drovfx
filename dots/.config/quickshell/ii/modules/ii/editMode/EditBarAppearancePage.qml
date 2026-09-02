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

        // No standalone section heading above a group that already names
        // itself: "Placement" over "Position" was two labels two pixels apart
        // saying the same thing, and it read as one line drawn twice.
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

        EditOptionChips {
            Layout.topMargin: 10
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

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: Config.options.bar.cornerStyle === 1
            first: true
            last: true
            symbol: "shadow"
            title: Translation.tr("Shadow in Float style")
            trailingKind: "switch"
            switchChecked: Config.options.bar.floatStyleShadow ?? true
            onActivated: Config.options.bar.floatStyleShadow = !(Config.options.bar.floatStyleShadow ?? true)
        }

        EditOptionChips {
            Layout.topMargin: 10
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
            Layout.topMargin: 10
            label: Translation.tr("Widget groups")
            currentValue: Config.options.bar.barGroupStyle
            options: [
                { "displayName": Translation.tr("Pills"), "icon": "location_chip", "value": 0 },
                { "displayName": Translation.tr("Island"), "icon": "shadow", "value": 1 },
                { "displayName": Translation.tr("Transparent"), "icon": "opacity", "value": 2 }
            ]
            onSelected: value => Config.options.bar.barGroupStyle = value
        }

        EditPanelSectionLabel {
            text: Translation.tr("Effects")
        }

        EditPanelRow {
            Layout.fillWidth: true
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

        // The shell's fake screen corners. It is an `appearance` key rather
        // than a `bar` one, and it belongs on this page anyway: what it draws
        // is a frame around the bar, and choosing it anywhere else means
        // leaving the mode to see the two together.
        EditOptionChips {
            Layout.topMargin: 10
            label: Translation.tr("Fake screen rounding")
            currentValue: Config.options.appearance.fakeScreenRounding
            lockedNote: root.locked
                ? Translation.tr("Wrapped and Edge would be drawn over the Dynamic Island, so they are unavailable while it sits in the bar's centre.")
                : ""
            options: [
                { "displayName": Translation.tr("No"), "icon": "close", "value": 0 },
                { "displayName": Translation.tr("Yes"), "icon": "check", "value": 1 },
                { "displayName": Translation.tr("Not fullscreen"), "icon": "fullscreen_exit", "value": 2 },
                { "displayName": Translation.tr("Wrapped"), "icon": "capture", "value": 3, "enabled": !root.locked },
                { "displayName": Translation.tr("Edge"), "icon": "border_bottom", "value": 4, "enabled": !root.locked }
            ]
            onSelected: value => Config.options.appearance.fakeScreenRounding = value
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: Config.options.appearance.fakeScreenRounding === 3
            first: true
            last: true
            symbol: "line_weight"
            title: Translation.tr("Wrapped frame thickness")
            trailingKind: "stepper"
            valueText: Config.options.appearance.wrappedFrameThickness + " px"
            stepDownEnabled: Config.options.appearance.wrappedFrameThickness > 5
            stepUpEnabled: Config.options.appearance.wrappedFrameThickness < 25
            onStepDown: Config.options.appearance.wrappedFrameThickness =
                Math.max(5, Config.options.appearance.wrappedFrameThickness - 1)
            onStepUp: Config.options.appearance.wrappedFrameThickness =
                Math.min(25, Config.options.appearance.wrappedFrameThickness + 1)
        }

        // The shell's own corner radius, which every surface - the bar, its
        // widget groups, this panel - is a multiple of. It is the other half
        // of "how round is the bar", and changing it here shows the answer on
        // the bar being edited instead of behind a Settings page.
        //
        // `sharpMode` is written alongside it, the way Settings' own slider
        // does: several surfaces read that flag rather than the number.
        EditPanelRow {
            readonly property int radiusValue: Config.options.appearance.roundingValue >= 0
                ? Config.options.appearance.roundingValue : 24
            function setRadius(value) {
                const next = Math.max(0, Math.min(48, value));
                Config.options.appearance.roundingValue = next;
                Config.options.appearance.sharpMode = (next === 0);
            }

            Layout.fillWidth: true
            Layout.topMargin: 6
            symbol: "rounded_corner"
            title: Translation.tr("Shell corner radius")
            subtitle: Translation.tr("Every surface, this panel included")
            trailingKind: "stepper"
            valueText: radiusValue === 0 ? Translation.tr("Sharp") : radiusValue + " px"
            stepDownEnabled: radiusValue > 0
            stepUpEnabled: radiusValue < 48
            onStepDown: setRadius(radiusValue - 2)
            onStepUp: setRadius(radiusValue + 2)
        }

        // The rest - the expressive colour theme, the top-left brand icon -
        // is a page of forms rather than a handful of switches, and this page
        // is not the place to mirror it.
        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            symbol: "settings"
            title: Translation.tr("All bar settings")
            trailingKind: "chevron"
            onActivated: GlobalStates.openSettingsPage("bar")
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
