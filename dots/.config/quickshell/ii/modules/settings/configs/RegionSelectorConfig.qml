import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    ContentSection {
        title: Translation.tr("General Behavior")
        icon: "settings"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "monitor"
                text: Translation.tr("Show only on focused monitor")
                checked: Config.options.regionSelector.showOnlyOnFocusedMonitor
                onCheckedChanged: {
                    Config.options.regionSelector.showOnlyOnFocusedMonitor = checked;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Hint Target Regions")
        icon: "center_focus_strong"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Windows")
                checked: Config.options.regionSelector.targetRegions.windows
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.windows = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "layers"
                text: Translation.tr("Layers")
                checked: Config.options.regionSelector.targetRegions.layers
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.layers = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "article"
                text: Translation.tr("Content")
                checked: Config.options.regionSelector.targetRegions.content
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.content = checked;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Google Lens Selection")
        icon: "search"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ContentSubsection {
                title: Translation.tr("Selection mode")
                icon: "highlight_alt"
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                    onSelected: newValue => {
                        Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                    }
                    options: [
                        { displayName: Translation.tr("Rectangular selection"), value: "rectangles", icon: "activity_zone" },
                        { displayName: Translation.tr("Circle to Search"), value: "circle", icon: "gesture" }
                    ]
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Screenshot Editor")
        icon: "transform"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "edit"
                text: Translation.tr("Enable screenshot editor")
                checked: Config.options.regionSelector.annotation.enableInlineEditor
                onCheckedChanged: {
                    Config.options.regionSelector.annotation.enableInlineEditor = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Enable this to have a print editor before copying it, also allows to save file directly.")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Rectangular Selection")
        icon: "crop_square"
        visible: !Config.options.search.imageSearch.useCircleSelection

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "border_inner"
                text: Translation.tr("Show aim lines")
                checked: Config.options.regionSelector.rect.showAimLines
                onCheckedChanged: {
                    Config.options.regionSelector.rect.showAimLines = checked;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Circle Selection")
        icon: "panorama_fish_eye"
        visible: Config.options.search.imageSearch.useCircleSelection

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSpinBox {
                icon: "line_weight"
                text: Translation.tr("Stroke width")
                value: Config.options.regionSelector.circle.strokeWidth
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.regionSelector.circle.strokeWidth = value;
                }
            }
            ConfigSpinBox {
                icon: "padding"
                text: Translation.tr("Padding")
                value: Config.options.regionSelector.circle.padding
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.options.regionSelector.circle.padding = value;
                }
            }
        }
    }
}
