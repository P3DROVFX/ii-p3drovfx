import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: page

    forceWidth: false

    // ── Behavior ──────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Behavior")
        icon: "dock"

        ConfigSwitch {
            buttonIcon: "toggle_on"
            text: Translation.tr("Enable")
            checked: Config.options.dock.enable
            onCheckedChanged: {
                Config.options.dock.enable = checked;
            }

            ConfigSwitch {
                enabled: Config.options.dock.enable
                buttonIcon: "center_focus_strong"
                text: Translation.tr("Show only on focused monitor")
                checked: Config.options.dock.showOnlyOnFocusedMonitor
                onCheckedChanged: {
                    Config.options.dock.showOnlyOnFocusedMonitor = checked;
                }
                StyledToolTip {
                    text: Translation.tr("When workspace is empty, show the dock only on the focused monitor instead of all monitors")
                }
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "group_work"
            text: Translation.tr("Smart auto-grouping")
            checked: Config.options.dock.smartGrouping
            onCheckedChanged: {
                Config.options.dock.smartGrouping = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "monitor"
            text: Translation.tr("Isolate monitors")
            checked: Config.options.dock.isolateMonitors
            onCheckedChanged: {
                Config.options.dock.isolateMonitors = checked;
            }
        }

        Item {
            Layout.preferredHeight: 8
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "preview"
            text: Translation.tr("Enable windows preview")
            checked: Config.options.dock.enablePreview
            onCheckedChanged: {
                Config.options.dock.enablePreview = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "mouse"
            text: Translation.tr("Hover to reveal")
            checked: Config.options.dock.hoverToReveal
            onCheckedChanged: {
                Config.options.dock.hoverToReveal = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "push_pin"
            text: Translation.tr("Pinned on startup")
            checked: Config.options.dock.pinnedOnStartup
            onCheckedChanged: {
                Config.options.dock.pinnedOnStartup = checked;
            }
        }

    }

    // ── Content & buttons ─────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Content & buttons")
        icon: "widgets"

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "play_circle"
            text: Translation.tr("Enable media widget")
            checked: Config.options.dock.enableMediaWidget
            onCheckedChanged: {
                Config.options.dock.enableMediaWidget = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "cloud"
            text: Translation.tr("Enable weather widget")
            checked: Config.options.dock.enableWeatherWidget
            onCheckedChanged: {
                Config.options.dock.enableWeatherWidget = checked;
            }
        }

        Item {
            Layout.preferredHeight: 8
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "notifications"
            text: Translation.tr("Show notification badges")
            checked: Config.options.dock.showNotificationBadges
            onCheckedChanged: {
                Config.options.dock.showNotificationBadges = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "vertical_split"
            text: Translation.tr("Show dividers")
            checked: Config.options.dock.showDividers
            onCheckedChanged: {
                Config.options.dock.showDividers = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "grid_view"
            text: Translation.tr("Show overview button")
            checked: Config.options.dock.showOverviewButton
            onCheckedChanged: {
                Config.options.dock.showOverviewButton = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "keep"
            text: Translation.tr("Show pin button")
            checked: Config.options.dock.showPinButton
            onCheckedChanged: {
                Config.options.dock.showPinButton = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "delete"
            text: Translation.tr("Show trash button")
            checked: Config.options.dock.showTrashButton
            onCheckedChanged: {
                Config.options.dock.showTrashButton = checked;
            }
        }

    }

    // ── Appearance ────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Appearance")
        icon: "palette"

        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "palette"
            text: Translation.tr("Tint dock icons")
            checked: Config.options.dock.monochromeIcons
            onCheckedChanged: {
                Config.options.dock.monochromeIcons = checked;
            }

            StyledToolTip {
                text: Translation.tr("Applies monochrome tint to dock icons")
            }

        }

        ConfigSwitch {
            enabled: Config.options.dock.enable && !Config.options.dock.monochromeIcons
            buttonIcon: "tonality"
            text: Translation.tr("Dim inactive dock icons")
            checked: Config.options.dock.dimInactiveIcons
            onCheckedChanged: {
                Config.options.dock.dimInactiveIcons = checked;
            }

            StyledToolTip {
                text: Translation.tr("Greyscale icons for pinned apps that are not running.\nDisabled when 'Tint dock icons' is active.")
            }

        }

    }

    ContentSection {
        title: Translation.tr("Dock Shape Mask")
        icon: "category"

        ConfigSwitch {
            buttonIcon: "interests"
            text: Translation.tr("Adaptive icons")
            checked: Config.options.dock.enableShapeMask
            onCheckedChanged: {
                Config.options.dock.enableShapeMask = checked;
            }

            StyledToolTip {
                text: Translation.tr("Crops the icons using the selected material shape")
            }

            extraComponent: Component {
                RippleButtonWithShape {
                    enabled: Config.options.dock.enableShapeMask
                    shapeString: Config.options.dock.shapeMask
                    implicitWidth: 60
                    extraIcon: "edit"
                    onClicked: {
                        dockShapeMaskLoader.active = !dockShapeMaskLoader.active;
                    }

                    StyledToolTip {
                        text: Translation.tr("Edit the material shape")
                    }

                }

            }

        }

        Loader {
            id: dockShapeMaskLoader

            active: false
            visible: active
            Layout.fillWidth: true

            sourceComponent: ContentSubsection {
                title: Translation.tr("Mask shape")
                icon: "shape_line"

                ConfigSelectionArray {
                    currentValue: Config.options.dock.shapeMask
                    onSelected: (newValue) => {
                        Config.options.dock.shapeMask = newValue;
                    }
                    options: (["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map((icon) => {
                        return {
                            "displayName": "",
                            "shape": icon,
                            "value": icon
                        };
                    })
                }

            }

        }

    }

    // ── Position & size ───────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Position & size")
        icon: "open_in_full"

        ConfigSpinBox {
            enabled: Config.options.dock.enable
            icon: "height"
            text: Translation.tr("Dock height")
            value: Config.options.dock.height
            from: 20
            to: 200
            stepSize: 1
            onValueChanged: {
                Config.options.dock.height = value;
            }
        }

        ContentSubsection {
            visible: Config.options.dock.enable
            title: Translation.tr("Dock position")
            icon: "border_all"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.dock.position
                onSelected: (newValue) => {
                    Config.options.dock.position = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Auto"),
                    "icon": "auto_awesome",
                    "value": "auto"
                }, {
                    "displayName": Translation.tr("Bottom"),
                    "icon": "border_bottom",
                    "value": "bottom"
                }, {
                    "displayName": Translation.tr("Top"),
                    "icon": "border_top",
                    "value": "top"
                }, {
                    "displayName": Translation.tr("Left"),
                    "icon": "border_left",
                    "value": "left"
                }, {
                    "displayName": Translation.tr("Right"),
                    "icon": "border_right",
                    "value": "right"
                }]
            }

        }

    }

}
