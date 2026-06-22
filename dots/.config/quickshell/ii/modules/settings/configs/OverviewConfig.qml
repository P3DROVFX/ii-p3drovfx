import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    KeyboardShortcutBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        text: Translation.tr("Toggle the Overview screen")
        keys: ["Super", "Tab"]
    }

    ContentSection {
        title: Translation.tr("Overview Configuration")
        icon: "dashboard"

        // Group 1: General Options
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "toggle_on"
                text: Translation.tr("Enable")
                checked: Config.options.overview.enable
                onCheckedChanged: {
                    Config.options.overview.enable = checked;
                }
            }

            ConfigSwitch {
                enabled: Config.options.overview.enable
                buttonIcon: "apps"
                text: Translation.tr("Show icons")
                checked: Config.options.overview.showIcons
                onCheckedChanged: {
                    Config.options.overview.showIcons = checked;
                }
            }

            ConfigSwitch {
                enabled: Config.options.overview.enable && Config.options.overview.showIcons
                buttonIcon: "vertical_align_center"
                text: Translation.tr("Center icons")
                checked: Config.options.overview.centerIcons
                onCheckedChanged: {
                    Config.options.overview.centerIcons = checked;
                }
            }

        }

        Item { Layout.preferredHeight: 16 }

        // Group 2: Behaviors
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSpinBox {
                enabled: Config.options.overview.enable
                icon: "aspect_ratio"
                text: Translation.tr("Scale %")
                value: Config.options.overview.scale * 100
                from: 10
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.overview.scale = value / 100;
                }
            }

            ConfigSwitch {
                enabled: Config.options.overview.enable
                buttonIcon: "animation"
                text: Translation.tr("Enable zoom animation")
                checked: Config.options.overview.showOpeningAnimation
                onCheckedChanged: {
                    Config.options.overview.showOpeningAnimation = checked;
                }
            }

            ContentSubsection {
                visible: Config.options.overview.enable && Config.options.overview.showOpeningAnimation
                title: Translation.tr("Zoom style")
                icon: "zoom_in"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.overview.scrollingStyle.zoomStyle
                    onSelected: newValue => {
                        Config.options.overview.scrollingStyle.zoomStyle = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("In"), icon: "zoom_in", value: "in" },
                        { displayName: Translation.tr("Out"), icon: "zoom_out", value: "out" }
                    ]
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Classic Style")
        icon: "grid_view"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSpinBox {
                icon: "view_agenda"
                text: Translation.tr("Rows")
                value: Config.options.overview.rows
                from: 1
                to: 10
                stepSize: 1
                onValueChanged: {
                    Config.options.overview.rows = value;
                }
            }

            ConfigSpinBox {
                icon: "view_column"
                text: Translation.tr("Columns")
                value: Config.options.overview.columns
                from: 1
                to: 10
                stepSize: 1
                onValueChanged: {
                    Config.options.overview.columns = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("Horizontal direction")
                icon: "swap_horiz"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.overview.orderRightLeft
                    onSelected: newValue => {
                        Config.options.overview.orderRightLeft = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Left to right"), icon: "arrow_forward", value: false },
                        { displayName: Translation.tr("Right to left"), icon: "arrow_back", value: true }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Vertical direction")
                icon: "swap_vert"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.overview.orderBottomUp
                    onSelected: newValue => {
                        Config.options.overview.orderBottomUp = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Top-down"), icon: "arrow_downward", value: false },
                        { displayName: Translation.tr("Bottom-up"), icon: "arrow_upward", value: true }
                    ]
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Background Style")
        icon: "wallpaper"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ContentSubsection {
                title: Translation.tr("Background style")
                icon: "style"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.overview.scrollingStyle.backgroundStyle
                    onSelected: newValue => {
                        Config.options.overview.scrollingStyle.backgroundStyle = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Blur"), icon: "blur_on", value: "blur" },
                        { displayName: Translation.tr("Dim"), icon: "brightness_medium", value: "dim" },
                        { displayName: Translation.tr("Transparent"), icon: "visibility_off", value: "transparent" }
                    ]
                }
            }

            ConfigSpinBox {
                enabled: Config.options.overview.scrollingStyle.backgroundStyle === "dim"
                icon: "contrast"
                text: Translation.tr("Dim percentage")
                value: Config.options.overview.scrollingStyle.dimPercentage
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.overview.scrollingStyle.dimPercentage = value;
                }
            }
        }
    }
}
