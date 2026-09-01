import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../.."
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.services

Item {
    id: overlaysConfigRoot

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function triggerRealOsd() {
        if (typeof GlobalStates !== "undefined") {
            GlobalStates.osdCurrentIndicator = "volume";
            GlobalStates.osdVolumeOpen = true;
            GlobalStates.osdInteraction();
        }
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "osd", "trigger"]);
    }

    ContentPage {
        id: page

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        ContentSection {
            title: Translation.tr("Game Overlays")
            icon: "sports_esports"
            tooltip: Translation.tr("In-game HUD widgets, crosshairs and media controls.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "sports_esports"
                    title: Translation.tr("Game Overlay Options")
                    description: Translation.tr("Crosshair, Media overlay, Notes, Discord voice & Floating image")
                    onClicked: overlaysConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/GameOverlayConfig.qml")
                }
            }
        }

        ContentSection {
            title: Translation.tr("On-Screen Display (OSD)")
            icon: "desktop_windows"

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Enable OSD")
                description: Translation.tr("Choose which indicators show up")
                checked: Config.options.osd.enable
                configPage: Qt.resolvedUrl("widgets/OsdIndicatorsConfig.qml")
                onCheckedChanged: {
                    Config.options.osd.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Display visual indicator when changing volume, brightness, or gamma")
                }
            }

            ConfigSwitch {
                buttonIcon: "fullscreen"
                text: Translation.tr("Hide OSD when fullscreen")
                checked: Config.options.osd.hideWhenFullscreen
                onCheckedChanged: {
                    Config.options.osd.hideWhenFullscreen = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Prevent OSD from appearing over fullscreen games and media players")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options.sidebar.sidebarStyle === "connect"
                materialIcon: "phone_android"
                text: Translation.tr("OSD customization is only available in Default shell mode. The Connect mode uses its own native OSD.")

                ShortcutBox {
                    targetPageId: "bar"
                    targetSectionTitle: Translation.tr("Shell mode")
                    materialIcon: "arrow_forward"
                    text: Translation.tr("Go to Shell mode settings")
                    linkText: Translation.tr("Go there")
                }
            }

            // Real OSD Live Preview Card
            OsdPreviewCard {
                Layout.fillWidth: true
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: Config.options.sidebar.sidebarStyle !== "connect" ? 1.0 : 0.4
            }

            // Android Style Exclusive: OSD Position (Moved ABOVE OSD Style as requested)
            ContentSubsection {
                title: Translation.tr("OSD Position")
                icon: "align_horizontal_right"
                Layout.fillWidth: true
                visible: (Config.options.osd.style ?? "default") === "default"
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: Config.options.sidebar.sidebarStyle !== "connect" ? 1.0 : 0.4

                OsdPositionPicker {
                    Layout.fillWidth: true
                    enabled: Config.options.sidebar.sidebarStyle !== "connect"
                }
            }

            // OSD Style Selector
            ContentSubsection {
                title: Translation.tr("OSD Style")
                icon: "tune"
                Layout.fillWidth: true
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: Config.options.sidebar.sidebarStyle !== "connect" ? 1.0 : 0.4

                ConfigSelectionArray {
                    enabled: Config.options.sidebar.sidebarStyle !== "connect"
                    currentValue: Config.options.osd.style ?? "default"
                    onSelected: (newValue) => {
                        Config.options.osd.style = newValue;
                        overlaysConfigRoot.triggerRealOsd();
                    }
                    options: [{
                        "displayName": Translation.tr("Android"),
                        "icon": "smartphone",
                        "tooltip": Translation.tr("Edge vertical slider bar"),
                        "value": "default"
                    }, {
                        "displayName": Translation.tr("Minimal"),
                        "icon": "horizontal_rule",
                        "tooltip": Translation.tr("Compact horizontal floating pill"),
                        "value": "minimalist"
                    }, {
                        "displayName": Translation.tr("Material"),
                        "icon": "interests",
                        "tooltip": Translation.tr("Expressive Material 3 card with shaped glyphs"),
                        "value": "material"
                    }]
                }
            }

            // Material 3 Exclusive Options
            ContentSubsectionLabel {
                text: Translation.tr("Material OSD Options")
                visible: Config.options.osd.style === "material"
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: enabled ? 1.0 : 0.4
                Layout.topMargin: 4
            }

            ConfigSwitch {
                visible: Config.options.osd.style === "material"
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: enabled ? 1.0 : 0.4
                buttonIcon: "compress"
                text: Translation.tr("Minimal variant")
                checked: Config.options.osd.material.minimal
                onCheckedChanged: {
                    Config.options.osd.material.minimal = checked;
                    overlaysConfigRoot.triggerRealOsd();
                }
                StyledToolTip {
                    text: Translation.tr("Compact single-line Material 3 slider layout")
                }
            }

            ConfigSwitch {
                visible: Config.options.osd.style === "material"
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: enabled ? 1.0 : 0.4
                buttonIcon: "shapes"
                text: Translation.tr("Shaped value labels")
                checked: Config.options.osd.material.shapedValues
                onCheckedChanged: {
                    Config.options.osd.material.shapedValues = checked;
                    overlaysConfigRoot.triggerRealOsd();
                }
                StyledToolTip {
                    text: Translation.tr("Use geometric shape background containers around icons")
                }
            }

            ConfigSwitch {
                visible: Config.options.osd.style === "material"
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: enabled ? 1.0 : 0.4
                buttonIcon: "circle"
                text: Translation.tr("Circled shapes")
                checked: Config.options.osd.material.circledShapes
                onCheckedChanged: {
                    Config.options.osd.material.circledShapes = checked;
                    overlaysConfigRoot.triggerRealOsd();
                }
                StyledToolTip {
                    text: Translation.tr("Force circular shape container instead of flower/star shapes")
                }
            }

            ConfigSwitch {
                visible: Config.options.osd.style === "material"
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: enabled ? 1.0 : 0.4
                buttonIcon: "rotate_right"
                text: Translation.tr("Rotate shapes when changing values")
                checked: Config.options.osd.material.rotateShape
                onCheckedChanged: {
                    Config.options.osd.material.rotateShape = checked;
                    overlaysConfigRoot.triggerRealOsd();
                }
                StyledToolTip {
                    text: Translation.tr("Rotate geometric shape glyph dynamically with value changes")
                }
            }

            // Common Options (Timeout)
            ConfigSlider {
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: Config.options.sidebar.sidebarStyle !== "connect" ? 1.0 : 0.4
                buttonIcon: "schedule"
                text: Translation.tr("OSD Timeout")
                usePercentTooltip: false
                tooltipContent: `${(value / 1000).toFixed(1)}s`
                from: 1000
                to: 5000
                stepSize: 500
                value: Config.options.osd.timeout ?? 3000
                onValueChanged: {
                    Config.options.osd.timeout = value;
                }
            }
        }

        ContentSection {
            title: Translation.tr("On-screen Keyboard")
            icon: "keyboard"

            KeyboardShortcutBox {
                Layout.fillWidth: true
                text: Translation.tr("Toggle On-Screen Keyboard")
                keys: ["Super", "K"]
            }

            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Show on-screen keyboard")
                checked: typeof GlobalStates !== "undefined" ? GlobalStates.oskOpen : false
                onCheckedChanged: {
                    if (typeof GlobalStates !== "undefined")
                        GlobalStates.oskOpen = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Open or close the virtual keyboard on screen")
                }
            }

            ContentSubsection {
                title: Translation.tr("Keyboard Style")
                icon: "keyboard"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.osk.style ?? "deck"
                    onSelected: (newValue) => {
                        Config.options.osk.style = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Deck"),
                        "icon": "keyboard",
                        "tooltip": Translation.tr("Spans the bottom of the screen"),
                        "value": "deck"
                    }, {
                        "displayName": Translation.tr("Classic"),
                        "icon": "keyboard_alt",
                        "tooltip": Translation.tr("Floats above the screen edge"),
                        "value": "classic"
                    }]
                }
            }

            ContentSubsection {
                title: Translation.tr("Layout")
                icon: "language"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.osk.layout ?? "auto"
                    onSelected: (newValue) => {
                        Config.options.osk.layout = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Auto"),
                        "icon": "autorenew",
                        "tooltip": Translation.tr("Follows the keyboard layout you are typing in"),
                        "value": "auto"
                    }, {
                        "displayName": Translation.tr("French"),
                        "value": "French"
                    }, {
                        "displayName": Translation.tr("English"),
                        "value": "English (US)"
                    }, {
                        "displayName": Translation.tr("German"),
                        "value": "German"
                    }, {
                        "displayName": Translation.tr("Russian"),
                        "value": "Russian"
                    }]
                }
            }

            ConfigSpinBox {
                enabled: (Config.options.osk.style ?? "deck") === "deck"
                opacity: enabled ? 1.0 : 0.4
                icon: "height"
                text: Translation.tr("Height (% of the screen)")
                value: Config.options.osk.heightPercent
                from: 15
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.osk.heightPercent = value;
                }
            }

            ConfigSwitch {
                enabled: (Config.options.osk.style ?? "deck") === "deck"
                opacity: enabled ? 1.0 : 0.4
                buttonIcon: "text_fields"
                text: Translation.tr("Show shift and AltGr glyphs")
                checked: Config.options.osk.secondaryGlyphs
                onCheckedChanged: {
                    Config.options.osk.secondaryGlyphs = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Display secondary key characters (Shift and AltGr) on keycaps")
                }
            }

            ConfigSwitch {
                buttonIcon: "touch_app"
                text: Translation.tr("Show automatically on touch")
                checked: Config.options.osk.autoShow.enable
                configPage: Qt.resolvedUrl("widgets/OnScreenKeyboardConfig.qml")
                onCheckedChanged: {
                    Config.options.osk.autoShow.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Configure automatic virtual keyboard popup behavior for touchscreen and pen input")
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
