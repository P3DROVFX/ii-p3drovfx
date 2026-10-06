import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for the Dock page: its look pane (edge, style, size) and its feature
// tiles. The page draws these as a live preview, style cards and tiles; SearchRegistry
// indexes this file (see SettingsPageRegistry `searchSources`) so they stay searchable.
ColumnLayout {
    ContentSection {
        icon: "dock_to_bottom"
        title: Translation.tr("Dock style")

        ContentSubsection {
            title: Translation.tr("Dock style")
            icon: "dock"
            ConfigSelectionArray {
                currentValue: Config.options.dock.dockStyle
                onSelected: newValue => {
                    Config.options.dock.dockStyle = newValue;
                    Config.options.dock.islandsStyle = (newValue === "islands");
                }
                options: [
                    { displayName: Translation.tr("Floating"), icon: "dock", value: "floating" },
                    { displayName: Translation.tr("Islands"), icon: "grid_view", value: "islands" },
                    { displayName: Translation.tr("Hug"), icon: "line_curve", value: "hug" },
                    { displayName: Translation.tr("Dynamic Island"), icon: "dock_to_bottom", value: "dynamic_island" },
                    { displayName: Translation.tr("Full width"), icon: "width_full", value: "full_width" },
                    { displayName: Translation.tr("Full width · rounded"), icon: "rounded_corner", value: "full_width_concave" },
                    { displayName: Translation.tr("Transparent"), icon: "opacity", value: "transparent" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Dock position")
            icon: "border_all"
            ConfigSelectionArray {
                currentValue: Config.options.dock.position
                onSelected: newValue => Config.options.dock.position = newValue
                options: [
                    { displayName: Translation.tr("Auto"), icon: "auto_awesome", value: "auto" },
                    { displayName: Translation.tr("Bottom"), icon: "border_bottom", value: "bottom" },
                    { displayName: Translation.tr("Top"), icon: "border_top", value: "top" },
                    { displayName: Translation.tr("Left"), icon: "border_left", value: "left" },
                    { displayName: Translation.tr("Right"), icon: "border_right", value: "right" }
                ]
            }
        }

        ConfigSlider {
            buttonIcon: "height"
            text: Translation.tr("Dock height")
            from: 30
            to: Math.max(120, Config.options.dock.height)
            stepSize: 1
            usePercentTooltip: false
            value: Config.options.dock.height
            onValueChanged: Config.options.dock.height = value
        }

        ConfigSlider {
            buttonIcon: "rounded_corner"
            text: Translation.tr("Corner radius")
            from: 0
            to: 40
            stepSize: 1
            usePercentTooltip: false
            value: Config.options.dock.dockRadius < 0 ? 0 : Config.options.dock.dockRadius
            onValueChanged: Config.options.dock.dockRadius = value === 0 ? -1 : value
        }

        ConfigSlider {
            buttonIcon: "space_bar"
            text: Translation.tr("Island spacing")
            from: 4
            to: 32
            stepSize: 1
            usePercentTooltip: false
            value: Config.options.dock.islandSpacing ?? 8
            onValueChanged: Config.options.dock.islandSpacing = value
        }
    }

    ContentSection {
        icon: "auto_awesome"
        title: Translation.tr("Dock features")

        ConfigSwitch {
            buttonIcon: "zoom_in"
            text: Translation.tr("Magnification")
            checked: Config.options.dock.enableMagnification ?? false
            onCheckedChanged: Config.options.dock.enableMagnification = checked
        }

        ContentSubsection {
            title: Translation.tr("Hover content")
            icon: "touch_app"
            ConfigSelectionArray {
                currentValue: Config.options.dock.enablePreview ? "preview" : (Config.options.dock.enableAppTooltip ? "tooltip" : "none")
                onSelected: newValue => {
                    Config.options.dock.enablePreview = (newValue === "preview");
                    Config.options.dock.enableAppTooltip = (newValue === "tooltip");
                }
                options: [
                    { displayName: Translation.tr("None"), icon: "block", value: "none" },
                    { displayName: Translation.tr("App Name"), icon: "subtitles", value: "tooltip" },
                    { displayName: Translation.tr("Window Preview"), icon: "preview", value: "preview" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "category"
            text: Translation.tr("Smart grouping")
            checked: Config.options.dock.smartGrouping
            onCheckedChanged: Config.options.dock.smartGrouping = checked
        }

        ConfigSwitch {
            buttonIcon: "stacks"
            text: Translation.tr("Widget stack")
            checked: Config.options.dock.enableWidgetStack ?? false
            onCheckedChanged: Config.options.dock.enableWidgetStack = checked
        }
    }
}
