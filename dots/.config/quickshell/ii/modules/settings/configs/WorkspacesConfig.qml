import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.services

Item {
    id: workspacesRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        property bool showBackButton: false
        signal goBack()

        RowLayout {
            spacing: 12
            visible: page.showBackButton

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: page.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Workspaces Settings")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Display Options")
            icon: "monitor"

            ConfigSwitch {
                buttonIcon: "map"
                text: Translation.tr("Use workspace map")
                checked: Config.options.bar.workspaces.useWorkspaceMap
                configPage: Qt.resolvedUrl("widgets/WorkspaceMapConfig.qml")
                onCheckedChanged: {
                    Config.options.bar.workspaces.useWorkspaceMap = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Isolate workspace ranges for multi-monitor setups. Click button text to configure monitor mapping.")
                }
            }

            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Always show numbers")
                checked: Config.options.bar.workspaces.alwaysShowNumbers
                onCheckedChanged: {
                    Config.options.bar.workspaces.alwaysShowNumbers = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "award_star"
                text: Translation.tr("Show app icons")
                checked: Config.options.bar.workspaces.showAppIcons
                onCheckedChanged: {
                    Config.options.bar.workspaces.showAppIcons = checked;
                }
            }

            ConfigSwitch {
                visible: Config.options.bar.workspaces.showAppIcons
                buttonIcon: "palette"
                text: Translation.tr("Tint workspaces icons")
                checked: Config.options.bar.workspaces.monochromeIcons
                onCheckedChanged: {
                    Config.options.bar.workspaces.monochromeIcons = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Applies monochrome tint to workspaces icons")
                }
            }

            ConfigSlider {
                visible: Config.options.bar.workspaces.showAppIcons
                buttonIcon: "humidity_percentage"
                text: Translation.tr("Tint (%)")
                value: Config.options.appearance.iconTintPercentage ?? 0.6
                onValueChanged: Config.options.appearance.iconTintPercentage = value
                enabled: Config.options.bar.workspaces.monochromeIcons
                opacity: enabled ? 1 : 0.5
            }

            ConfigSwitch {
                buttonIcon: "hdr_weak"
                text: Translation.tr("Dynamic workspaces")
                checked: Config.options.bar.workspaces.dynamicWorkspaces
                onCheckedChanged: {
                    Config.options.bar.workspaces.dynamicWorkspaces = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Hides the empty workspaces and only shows the ones with windows")
                }
            }

            ConfigSpinBox {
                enabled: !Config.options.bar.workspaces.dynamicWorkspaces
                icon: "view_column"
                text: Translation.tr("Workspaces shown")
                value: Config.options.bar.workspaces.shown
                from: 1
                to: 30
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.workspaces.shown = value;
                }
            }

            ConfigSpinBox {
                icon: "select_window"
                text: Translation.tr("Maximum window count per workspace")
                value: Config.options.bar.workspaces.maxWindowCount
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.workspaces.maxWindowCount = value;
                }
            }

            ConfigSpinBox {
                icon: "touch_long"
                text: Translation.tr("Number show delay when pressing Super (ms)")
                value: Config.options.bar.workspaces.showNumberDelay
                from: 0
                to: 1000
                stepSize: 50
                onValueChanged: {
                    Config.options.bar.workspaces.showNumberDelay = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("Number style")
                icon: "format_list_numbered"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
                    onSelected: (newValue) => {
                        Config.options.bar.workspaces.numberMap = JSON.parse(newValue);
                    }
                    options: [{
                        "displayName": Translation.tr("Normal"),
                        "icon": "timer_10",
                        "value": '[]'
                    }, {
                        "displayName": Translation.tr("Han chars"),
                        "icon": "square_dot",
                        "value": '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]'
                    }, {
                        "displayName": Translation.tr("Roman"),
                        "icon": "account_balance",
                        "value": '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]'
                    }]
                }
            }
        }

        ContentSection {
            title: Translation.tr("Shape Customization")
            icon: "category"

            ConfigSwitch {
                buttonIcon: "interests"
                text: Translation.tr("Apply shape mask to icons")
                checked: Config.options.appearance.icons.enableShapeMask
                onCheckedChanged: {
                    Config.options.appearance.icons.enableShapeMask = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Crops the icons using the selected material shape")
                }

                extraComponent: Component {
                    RippleButtonWithShape {
                        enabled: Config.options.appearance.icons.enableShapeMask
                        shapeString: Config.options.appearance.icons.shapeMask
                        implicitWidth: 60
                        extraIcon: "edit"
                        onClicked: {
                            iconsShapeMaskLoader.active = !iconsShapeMaskLoader.active;
                        }
                        StyledToolTip {
                            text: Translation.tr("Edit the material shape")
                        }
                    }
                }
            }

            Loader {
                id: iconsShapeMaskLoader
                active: false
                visible: active
                Layout.fillWidth: true

                sourceComponent: ContentSubsection {
                    title: Translation.tr("Mask shape")
                    icon: "shape_line"

                    ConfigSelectionArray {
                        currentValue: Config.options.appearance.icons.shapeMask
                        onSelected: (newValue) => {
                            Config.options.appearance.icons.shapeMask = newValue;
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

            ConfigSwitch {
                buttonIcon: "token"
                text: Translation.tr("Use Material Shape for active indicator")
                checked: Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                onCheckedChanged: {
                    Config.options.bar.workspaces.useMaterialShapeForActiveIndicator = checked;
                }

                extraComponent: Component {
                    RippleButtonWithShape {
                        enabled: Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                        shapeString: Config.options.bar.workspaces.activeIndicatorShape
                        implicitWidth: 60
                        extraIcon: "edit"
                        onClicked: {
                            activeIndicatorShapeLoader.active = !activeIndicatorShapeLoader.active;
                        }
                        StyledToolTip {
                            text: Translation.tr("Edit the material shape")
                        }
                    }
                }
            }

            Loader {
                id: activeIndicatorShapeLoader
                active: false
                visible: active
                Layout.fillWidth: true

                sourceComponent: ContentSubsection {
                    title: Translation.tr("Active indicator shape")
                    icon: "shape_line"

                    ConfigSelectionArray {
                        currentValue: Config.options.bar.workspaces.activeIndicatorShape
                        onSelected: (newValue) => {
                            Config.options.bar.workspaces.activeIndicatorShape = newValue;
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

            ConfigSwitch {
                enabled: !Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                buttonIcon: "shuffle"
                text: Translation.tr("Use random shape for active indicator")
                checked: Config.options.bar.workspaces.useRandomShapeForActiveIndicator
                onCheckedChanged: {
                    Config.options.bar.workspaces.useRandomShapeForActiveIndicator = checked;
                }
            }
        }

        ContentSection {
            visible: Config.options.bar.styles.workspaces === "dock"
            title: Translation.tr("Dock Workspace Style")
            icon: "dock"

            ConfigSwitch {
                buttonIcon: "dock"
                text: Translation.tr("Dock workspace style options")
                checked: Config.options.bar.workspaces.dockShowActiveIndicator
                configPage: Qt.resolvedUrl("widgets/DockWorkspaceConfig.qml")
                onCheckedChanged: {
                    Config.options.bar.workspaces.dockShowActiveIndicator = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Click button text to configure active indicator, window count dots, hover effects, and app icons in dock style.")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Workspace Compactor")
            icon: "compress"

            HelperCodeBox {
                Layout.fillWidth: true
                icon: "terminal"
                title: Translation.tr("Build it once")
                text: Translation.tr("Pulls the focused monitor's occupied workspaces down to 1..N with no gaps, keeping windows together and restoring their geometry. Rust is the only requirement.")
                codeSnippet: `cd ${Directories.scriptPath.replace(FileUtils.trimFileProtocol(Directories.home), "~")}/hyprland/workspace_compactor_src
cargo build --release
cp target/release/workspace_compactor ../`
                snippetWrapMode: Text.Wrap
            }

            KeyboardShortcutBox {
                Layout.fillWidth: true
                text: Translation.tr("Compact workspaces into 1..N")
                keys: ["Ctrl", "Super", "C"]
            }

            ConfigSwitch {
                buttonIcon: "autorenew"
                text: Translation.tr("Auto-Compact")
                checked: Config.options.bar.workspaces.autoCompact
                onCheckedChanged: {
                    Config.options.bar.workspaces.autoCompact = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Compact automatically whenever closing or moving a window leaves a gap on the focused monitor. The keybind above keeps working either way.")
                }
            }

            ConfigSpinBox {
                enabled: Config.options.bar.workspaces.autoCompact
                icon: "timer"
                text: Translation.tr("Auto-Compact delay (ms)")
                value: Config.options.bar.workspaces.autoCompactDelay
                from: 100
                to: 5000
                stepSize: 100
                onValueChanged: {
                    Config.options.bar.workspaces.autoCompactDelay = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("When the gap is the current workspace")
                icon: "conditions"
                Layout.fillWidth: true
                visible: Config.options.bar.workspaces.autoCompact

                ConfigSelectionArray {
                    currentValue: Config.options.bar.workspaces.autoCompactCurrentGap
                    onSelected: (newValue) => {
                        Config.options.bar.workspaces.autoCompactCurrentGap = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Compact on switch"),
                        "icon": "move_group",
                        "value": "onswitch"
                    }, {
                        "displayName": Translation.tr("Immediately"),
                        "icon": "bolt",
                        "value": "immediate"
                    }, {
                        "displayName": Translation.tr("Never"),
                        "icon": "block",
                        "value": "never"
                    }]
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
