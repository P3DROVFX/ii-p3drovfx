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
                enabled: Config.options.overview.enable
                buttonIcon: "photo"
                text: Translation.tr("Show window previews (screencopy)")
                checked: Config.options.overview.showWindowPreviews
                onCheckedChanged: {
                    Config.options.overview.showWindowPreviews = checked;
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
                text: Translation.tr("Scale (%)")
                value: Config.options.overview.scale * 100
                from: 10
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.overview.scale = value / 100;
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
    
}
