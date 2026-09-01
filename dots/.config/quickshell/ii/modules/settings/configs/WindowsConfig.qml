import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: page

    forceWidth: false

    ContentSection {
        title: Translation.tr("Transparency & Blur")
        icon: "opacity"

        WarningBox {
            Layout.fillWidth: true
            text: Translation.tr("Heavy blur effects can significantly impact battery life and performance on weaker GPUs.")
            isFirst: true
        }

        ConfigSwitch {
            buttonIcon: "ev_shadow"
            text: Translation.tr("Enable transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: {
                Config.options.appearance.transparency.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "magic_button"
            text: Translation.tr("Calculate transparency automatically")
            checked: Config.options.appearance.transparency.automatic
            onCheckedChanged: {
                Config.options.appearance.transparency.automatic = checked;
            }

            StyledToolTip {
                text: Translation.tr("Calculate transparency automatically based on wallpaper colors")
            }

        }

        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Transparency in popups")
            checked: Config.options.appearance.transparency.popups
            onCheckedChanged: {
                Config.options.appearance.transparency.popups = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "blur_on"
            text: Translation.tr("Background transparency")
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            value: Config.options.appearance.transparency.backgroundTransparency
            onValueChanged: {
                Config.options.appearance.transparency.backgroundTransparency = value;
            }
        }

        ConfigSlider {
            buttonIcon: "opacity"
            text: Translation.tr("Content transparency")
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            value: Config.options.appearance.transparency.contentTransparency
            onValueChanged: {
                Config.options.appearance.transparency.contentTransparency = value;
            }
        }

        ConfigSlider {
            buttonIcon: "lens_blur"
            text: Translation.tr("Blur Size")
            usePercentTooltip: false
            from: 0
            to: 30
            stepSize: 5
            snapMode: Slider.SnapAlways
            stopIndicatorValues: [0, 5, 10, 15, 20, 25, 30]
            value: Config.options.appearance.blurSize ?? 8
            onValueChanged: {
                Config.options.appearance.blurSize = Math.round(value);
            }
        }

        ConfigSlider {
            buttonIcon: "gradient"
            text: Translation.tr("Ignore Alpha")
            value: Config.options.appearance.ignoreAlpha ?? 0.2
            from: 0
            to: 1
            stepSize: 0.05
            onValueChanged: {
                Config.options.appearance.ignoreAlpha = value;
            }
        }

    }

    ContentSection {
        title: Translation.tr("Gaps")
        icon: "margin"

        ConfigSlider {
            buttonIcon: "padding"
            text: Translation.tr("Gaps In")
            usePercentTooltip: false
            from: 0
            to: 60
            stepSize: 1
            value: Config.options.appearance.gapsIn ?? 4
            onValueChanged: {
                Config.options.appearance.gapsIn = Math.round(value);
            }
        }

        ConfigSlider {
            buttonIcon: "fullscreen"
            text: Translation.tr("Gaps Out")
            usePercentTooltip: false
            from: 0
            to: 60
            stepSize: 1
            value: Config.options.appearance.gapsOut ?? 5
            onValueChanged: {
                Config.options.appearance.gapsOut = Math.round(value);
            }
        }

    }

    ContentSection {
        title: Translation.tr("Borders")
        icon: "border_outer"

        ConfigSwitch {
            buttonIcon: "border_clear"
            text: Translation.tr("Borderless windows")
            checked: Config.options.appearance.borderless
            onCheckedChanged: {
                Config.options.appearance.borderless = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "border_outer"
            text: Translation.tr("Border Width")
            usePercentTooltip: false
            enabled: !Config.options.appearance.borderless
            from: 0
            to: 20
            stepSize: 1
            value: Config.options.appearance.borderWidth ?? 2
            onValueChanged: {
                Config.options.appearance.borderWidth = Math.round(value);
            }
        }

        ContentSubsection {
            title: Translation.tr("Active Border Color Type")
            icon: "border_color"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.appearance.borderColorType
                onSelected: (newValue) => {
                    Config.options.appearance.borderColorType = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Primary"),
                    "value": "primary"
                }, {
                    "displayName": Translation.tr("Secondary"),
                    "value": "secondary"
                }, {
                    "displayName": Translation.tr("Tertiary"),
                    "value": "tertiary"
                }, {
                    "displayName": Translation.tr("Primary Container"),
                    "value": "primaryContainer"
                }, {
                    "displayName": Translation.tr("Surface"),
                    "value": "surface"
                }]
            }

        }

    }

    ContentSection {
        title: Translation.tr("Default layout")
        icon: "view_quilt"

        // This was a Default/Scrolling picker writing a setting nothing ever read, so choosing
        // either did nothing at all. The tiling engine is Hyprland's own general:layout, and the
        // Hyprland page sets it for real - along with the options that belong to each engine.
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Which engine arranges your windows - dwindle, master, scrolling or monocle - is a Hyprland setting. Its options, and a diagram of where the next window would land, are on the Hyprland page.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "hyprland"
                label: Translation.tr("Tiling engine")
                sectionHighlight: Translation.tr("Tiling engine")
            }
        }

    }


    ContentSection {
        title: Translation.tr("Window Animations")
        icon: "animation"

        ConfigSwitch {
            buttonIcon: "open_in_new"
            text: Translation.tr("App opening animation (Center zoom)")
            checked: Config.options.appearance.appLaunchAnimation.enable ?? true
            onCheckedChanged: {
                Config.options.appearance.appLaunchAnimation.enable = checked;
                HyprlandSettings.updateAppLaunchAnimation(
                    checked,
                    Config.options.appearance.appLaunchAnimation.startPercent,
                    Config.options.appearance.appLaunchAnimation.speed,
                    Config.options.appearance.appLaunchAnimation.curve
                );
            }
        }

        ConfigSlider {
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Opening initial scale")
            usePercentTooltip: true
            enabled: Config.options.appearance.appLaunchAnimation.enable ?? true
            from: 5
            to: 50
            stepSize: 5
            snapMode: Slider.SnapAlways
            stopIndicatorValues: [5, 10, 15, 20, 25, 30, 40, 50]
            value: Config.options.appearance.appLaunchAnimation.startPercent ?? 20
            onValueChanged: {
                const val = Math.round(value);
                Config.options.appearance.appLaunchAnimation.startPercent = val;
                HyprlandSettings.updateAppLaunchAnimation(
                    Config.options.appearance.appLaunchAnimation.enable ?? true,
                    val,
                    Config.options.appearance.appLaunchAnimation.speed,
                    Config.options.appearance.appLaunchAnimation.curve
                );
            }
        }

        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Opening animation speed")
            usePercentTooltip: false
            tooltipContent: `${value.toFixed(1)}x`
            enabled: Config.options.appearance.appLaunchAnimation.enable ?? true
            from: 1.0
            to: 6.0
            stepSize: 0.2
            value: Config.options.appearance.appLaunchAnimation.speed ?? 3.2
            onValueChanged: {
                Config.options.appearance.appLaunchAnimation.speed = value;
                HyprlandSettings.updateAppLaunchAnimation(
                    Config.options.appearance.appLaunchAnimation.enable ?? true,
                    Config.options.appearance.appLaunchAnimation.startPercent,
                    value,
                    Config.options.appearance.appLaunchAnimation.curve
                );
            }
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "wallpaper"
                label: Translation.tr("Wallpaper blur")
            }

            RelatedChip {
                pageId: "lockScreen"
                label: Translation.tr("Lock screen blur")
                sectionHighlight: Translation.tr("Blur style")
            }
        }
    }
}
