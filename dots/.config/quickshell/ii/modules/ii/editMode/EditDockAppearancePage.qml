import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The dock's own quick settings, as a page of Edit Mode's panel.
 *
 * The dock was the one panel the mode let you rearrange without letting you
 * say anything about how it is drawn: pinning was the whole vocabulary. These
 * are the keys from Settings' "Placement & Size" and "Dock appearance" that
 * change its shape - where it sits, how tall it is, which silhouette, how the
 * icons are treated - and nothing deeper.
 *
 * Preferences, not layout edits: no history entries, same as the bar's page.
 */
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    readonly property string dockStyle: {
        const stored = Config.options.dock.dockStyle;
        if (stored === "islands" || stored === "dynamic_island" || stored === "hug" || stored === "floating")
            return stored;
        return (Config.options.dock.islandsStyle ?? false) ? "islands" : "floating";
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: 4

        EditPanelSectionLabel {
            text: Translation.tr("Placement")
        }

        EditOptionChips {
            label: Translation.tr("Position")
            currentValue: Config.options.dock.position
            options: [
                { "displayName": Translation.tr("Auto"), "icon": "auto_awesome", "value": "auto" },
                { "displayName": Translation.tr("Bottom"), "icon": "border_bottom", "value": "bottom" },
                { "displayName": Translation.tr("Top"), "icon": "border_top", "value": "top" },
                { "displayName": Translation.tr("Left"), "icon": "border_left", "value": "left" },
                { "displayName": Translation.tr("Right"), "icon": "border_right", "value": "right" }
            ]
            onSelected: value => Config.options.dock.position = value
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            first: true
            last: true
            symbol: "height"
            title: Translation.tr("Dock height")
            trailingKind: "stepper"
            valueText: Config.options.dock.height + " px"
            stepDownEnabled: Config.options.dock.height > 20
            stepUpEnabled: Config.options.dock.height < 200
            onStepDown: Config.options.dock.height = Math.max(20, Config.options.dock.height - 2)
            onStepUp: Config.options.dock.height = Math.min(200, Config.options.dock.height + 2)
        }

        EditPanelSectionLabel {
            text: Translation.tr("Shape")
        }

        EditOptionChips {
            label: Translation.tr("Dock style")
            currentValue: root.dockStyle
            options: [
                { "displayName": Translation.tr("Floating"), "icon": "dock", "value": "floating" },
                { "displayName": Translation.tr("Islands"), "icon": "grid_view", "value": "islands" },
                { "displayName": Translation.tr("Hug"), "icon": "line_curve", "value": "hug" },
                { "displayName": Translation.tr("Island"), "icon": "dock_to_bottom", "value": "dynamic_island" }
            ]
            onSelected: value => {
                Config.options.dock.dockStyle = value;
                Config.options.dock.islandsStyle = (value === "islands");
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: root.dockStyle === "islands"
            first: true
            last: false
            symbol: "space_bar"
            title: Translation.tr("Island spacing")
            trailingKind: "stepper"
            valueText: String(Config.options.dock.islandSpacing ?? 8)
            stepDownEnabled: (Config.options.dock.islandSpacing ?? 8) > 4
            stepUpEnabled: (Config.options.dock.islandSpacing ?? 8) < 32
            onStepDown: Config.options.dock.islandSpacing = Math.max(4, (Config.options.dock.islandSpacing ?? 8) - 1)
            onStepUp: Config.options.dock.islandSpacing = Math.min(32, (Config.options.dock.islandSpacing ?? 8) + 1)
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: root.dockStyle === "islands" ? 0 : 6
            first: root.dockStyle !== "islands"
            last: false
            symbol: "rounded_corner"
            title: Translation.tr("Dock corner radius")
            trailingKind: "stepper"
            valueText: Config.options.dock.dockRadius < 0 ? Translation.tr("Auto") : String(Config.options.dock.dockRadius)
            stepDownEnabled: Config.options.dock.dockRadius > 0
            stepUpEnabled: Config.options.dock.dockRadius < 40
            onStepDown: {
                const next = (Config.options.dock.dockRadius < 0 ? 0 : Config.options.dock.dockRadius) - 2;
                Config.options.dock.dockRadius = next <= 0 ? -1 : next;
            }
            onStepUp: {
                const next = (Config.options.dock.dockRadius < 0 ? 0 : Config.options.dock.dockRadius) + 2;
                Config.options.dock.dockRadius = Math.min(40, next);
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "crop_square"
            title: Translation.tr("Widget corner radius")
            trailingKind: "stepper"
            valueText: Config.options.dock.widgetRadius < 0 ? Translation.tr("Auto") : String(Config.options.dock.widgetRadius)
            stepDownEnabled: Config.options.dock.widgetRadius > 0
            stepUpEnabled: Config.options.dock.widgetRadius < 30
            onStepDown: {
                const next = (Config.options.dock.widgetRadius < 0 ? 0 : Config.options.dock.widgetRadius) - 2;
                Config.options.dock.widgetRadius = next <= 0 ? -1 : next;
            }
            onStepUp: {
                const next = (Config.options.dock.widgetRadius < 0 ? 0 : Config.options.dock.widgetRadius) + 2;
                Config.options.dock.widgetRadius = Math.min(30, next);
            }
        }

        EditPanelSectionLabel {
            text: Translation.tr("Icons")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "invert_colors"
            title: Translation.tr("Tint dock icons")
            trailingKind: "switch"
            switchChecked: Config.options.dock.monochromeIcons
            onActivated: Config.options.dock.monochromeIcons = !Config.options.dock.monochromeIcons
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: !Config.options.dock.monochromeIcons
            symbol: "filter_b_and_w"
            title: Translation.tr("Dim inactive icons")
            subtitle: Translation.tr("Pinned apps that are not running")
            trailingKind: "switch"
            switchChecked: Config.options.dock.dimInactiveIcons
            onActivated: Config.options.dock.dimInactiveIcons = !Config.options.dock.dimInactiveIcons
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "shapes"
            title: Translation.tr("Adaptive icon shape")
            trailingKind: "switch"
            switchChecked: Config.options.dock.enableShapeMask
            onActivated: Config.options.dock.enableShapeMask = !Config.options.dock.enableShapeMask
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "zoom_out_map"
            title: Translation.tr("macOS magnification")
            trailingKind: "switch"
            switchChecked: Config.options.dock.enableMagnification ?? false
            onActivated: Config.options.dock.enableMagnification = !(Config.options.dock.enableMagnification ?? false)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "space_bar"
            title: Translation.tr("Icon spacing")
            trailingKind: "stepper"
            // Negative is the dock's own "work it out from the style", which
            // is what an untouched config holds - so it reads as Auto rather
            // than as a nonsensical -1.
            valueText: Config.options.dock.iconSpacing < 0
                ? Translation.tr("Auto") : String(Math.round(Config.options.dock.iconSpacing))
            stepDownEnabled: Config.options.dock.iconSpacing > 0
            stepUpEnabled: Config.options.dock.iconSpacing < 24
            onStepDown: {
                const next = (Config.options.dock.iconSpacing < 0 ? 0 : Config.options.dock.iconSpacing) - 1;
                Config.options.dock.iconSpacing = next < 0 ? -1 : next;
            }
            onStepUp: {
                const next = (Config.options.dock.iconSpacing < 0 ? 0 : Config.options.dock.iconSpacing) + 1;
                Config.options.dock.iconSpacing = Math.min(24, next);
            }
        }

        EditPanelSectionLabel {
            text: Translation.tr("Behaviour")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "push_pin"
            title: Translation.tr("Pinned on startup")
            subtitle: Translation.tr("Keep the dock out instead of hiding it")
            trailingKind: "switch"
            switchChecked: Config.options.dock.pinnedOnStartup
            onActivated: Config.options.dock.pinnedOnStartup = !Config.options.dock.pinnedOnStartup
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "highlight_mouse_cursor"
            title: Translation.tr("Hover to reveal")
            trailingKind: "switch"
            switchChecked: Config.options.dock.hoverToReveal
            onActivated: Config.options.dock.hoverToReveal = !Config.options.dock.hoverToReveal
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "group_work"
            title: Translation.tr("Smart auto-grouping")
            subtitle: Translation.tr("Arrange by category, keeping what you moved by hand")
            trailingKind: "switch"
            switchChecked: Config.options.dock.smartGrouping
            onActivated: Config.options.dock.smartGrouping = !Config.options.dock.smartGrouping
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
