import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Io

ContentPage {
    id: page
    readonly property int index: 4
    property bool register: parent.register ?? false
    forceWidth: true

    ContentSection {
        icon: "opacity"
        title: Translation.tr("Transparency")

        ConfigRow {
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
                text: Translation.tr("Automatic")
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
                text: Translation.tr("Popups")
                checked: Config.options.appearance.transparency.popups
                onCheckedChanged: {
                    Config.options.appearance.transparency.popups = checked;
                }
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
            from: 0.0
            to: 1.0
            stepSize: 0.05
            onValueChanged: {
                Config.options.appearance.ignoreAlpha = value;
            }
        }
    }

    ContentSection {
        icon: "border_outer"
        title: Translation.tr("Window Border")

        ContentSubsection {
            title: Translation.tr("Active border color")
            ConfigSelectionArray {
                currentValue: Config.options.appearance.borderColorType
                onSelected: newValue => {
                    Config.options.appearance.borderColorType = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Primary"),
                        value: "primary"
                    },
                    {
                        displayName: Translation.tr("Secondary"),
                        value: "secondary"
                    },
                    {
                        displayName: Translation.tr("Tertiary"),
                        value: "tertiary"
                    },
                    {
                        displayName: Translation.tr("Primary Container"),
                        value: "primaryContainer"
                    },
                    {
                        displayName: Translation.tr("Surface"),
                        value: "surface"
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "margin"
        title: Translation.tr("Gaps")

        ConfigSlider {
            buttonIcon: "padding"
            text: Translation.tr("Gaps In")
            usePercentTooltip: false
            from: 0
            to: 60
            stepSize: 1
            value: Config.options.appearance.gapsIn
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
            value: Config.options.appearance.gapsOut
            onValueChanged: {
                Config.options.appearance.gapsOut = Math.round(value);
            }
        }
    }
}
