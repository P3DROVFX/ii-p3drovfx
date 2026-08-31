import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Dock Appearance & Style")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Dock Style & Geometry ─────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Dock Style & Geometry")
            icon: "view_quilt"
            tooltip: Translation.tr("Choose between a floating pill dock, separated island surfaces, a hug dock attached to the screen edge, or a dynamic island with concave corners.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Dock style")
                    icon: "view_quilt"
                    Layout.fillWidth: true
                    tooltip: Translation.tr("Choose between a floating pill dock, separated island surfaces, a hug dock attached to the screen edge, or a dynamic island with concave corners.")

                    ConfigSelectionArray {
                        currentValue: {
                            const st = Config.options.dock.dockStyle;
                            if (st === "islands" || st === "dynamic_island" || st === "hug" || st === "floating")
                                return st;
                            return (Config.options.dock.islandsStyle ?? false) ? "islands" : "floating";
                        }
                        onSelected: newValue => {
                            Config.options.dock.dockStyle = newValue;
                            Config.options.dock.islandsStyle = (newValue === "islands");
                        }
                        options: [
                            { displayName: Translation.tr("Floating"), icon: "dock", value: "floating" },
                            { displayName: Translation.tr("Islands"), icon: "grid_view", value: "islands" },
                            { displayName: Translation.tr("Hug"), icon: "line_curve", value: "hug" },
                            { displayName: Translation.tr("Dynamic Island"), icon: "dock_to_bottom", value: "dynamic_island" }
                        ]
                    }
                }

                ConfigSlider {
                    visible: {
                        const st = Config.options.dock.dockStyle;
                        if (st === "islands" || st === "dynamic_island" || st === "hug" || st === "floating")
                            return st === "islands";
                        return Config.options.dock.islandsStyle ?? false;
                    }
                    Layout.fillWidth: true
                    text: Translation.tr("Island spacing")
                    value: Config.options.dock.islandSpacing ?? 8
                    from: 4
                    to: 32
                    stepSize: 1
                    usePercentTooltip: false
                    onValueChanged: {
                        Config.options.dock.islandSpacing = value;
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Corner Radius")
                    Layout.topMargin: 4
                }

                ConfigSlider {
                    Layout.fillWidth: true
                    text: Translation.tr("Dock corner radius") + (Config.options.dock.dockRadius < 0 ? " (" + Translation.tr("Auto") + ")" : "")
                    value: Config.options.dock.dockRadius < 0 ? 0 : Config.options.dock.dockRadius
                    from: 0
                    to: 40
                    stepSize: 1
                    onValueChanged: {
                        Config.options.dock.dockRadius = value === 0 ? -1 : value;
                    }
                }

                ConfigSlider {
                    Layout.fillWidth: true
                    text: Translation.tr("Widget corner radius") + (Config.options.dock.widgetRadius < 0 ? " (" + Translation.tr("Auto") + ")" : "")
                    value: Config.options.dock.widgetRadius < 0 ? 0 : Config.options.dock.widgetRadius
                    from: 0
                    to: 30
                    stepSize: 1
                    onValueChanged: {
                        Config.options.dock.widgetRadius = value === 0 ? -1 : value;
                    }
                }
            }
        }

        // ── Icons & Tinting ───────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Icons & Tinting")
            icon: "palette"
            tooltip: Translation.tr("Customize dock icon spacing, monochrome tinting, and inactive app dimming.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
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
                    enabled: !Config.options.dock.monochromeIcons
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

                ConfigSlider {
                    Layout.fillWidth: true
                    text: Translation.tr("Icon spacing")
                    value: Config.options.dock.iconSpacing
                    from: -4
                    to: 16
                    stepSize: 1
                    onValueChanged: {
                        Config.options.dock.iconSpacing = value;
                    }
                }
            }
        }

        // ── Effects & Magnification ───────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Effects & Magnification")
            icon: "zoom_in"
            tooltip: Translation.tr("Configure hover magnification and icon animation physics.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "zoom_in"
                    text: Translation.tr("macOS icon magnification")
                    checked: Config.options.dock.enableMagnification ?? false
                    configPage: Qt.resolvedUrl("DockMagnificationConfig.qml")
                    onCheckedChanged: {
                        Config.options.dock.enableMagnification = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Magnifies icons on hover. Click button text to configure intensity, influence radius, and motion styles.")
                    }
                }
            }
        }

        // ── Dock Shape Mask ───────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Dock Shape Mask")
            icon: "category"
            tooltip: Translation.tr("Crops dock icons using Material Design shapes.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

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
        }
    }
}
