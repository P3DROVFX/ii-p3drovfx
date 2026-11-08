import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../.."
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.services

/** Overlays → On-screen display: indicators, style, position and timeout (moved off the main page). */
Item {
    id: osdRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()
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

        ConfigSubPageHeader {
            visible: osdRoot.showBackButton
            title: Translation.tr("On-screen display")
            onBack: osdRoot.goBack()
        }

        ContentSection {
            title: Translation.tr("On-screen display")
            icon: "desktop_windows"

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Enable OSD")
                description: Translation.tr("Choose which indicators show up")
                checked: Config.options.osd.enable
                configPage: Qt.resolvedUrl("../widgets/OsdIndicatorsConfig.qml")
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
                        osdRoot.triggerRealOsd();
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
                    }, {
                        "displayName": Translation.tr("Tuner"),
                        "icon": "straighten",
                        "tooltip": Translation.tr("Sliding ruler under a beam of light; lives in the Dynamic Island when it's on"),
                        "value": "tuner"
                    }]
                }
            }

            ConfigSwitch {
                visible: Config.options.osd.style === "tuner"
                enabled: Config.options.sidebar.sidebarStyle !== "connect"
                opacity: enabled ? 1.0 : 0.4
                buttonIcon: "straighten"
                text: Translation.tr("Ruler on on/off indicators")
                description: Translation.tr("Caps Lock, microphone and other on/off indicators slide along the ruler like the sliders")
                checked: Config.options.osd.tuner?.toggleRuler ?? false
                onCheckedChanged: {
                    if (Config.ready && Config.options.osd.tuner)
                        Config.options.osd.tuner.toggleRuler = checked;
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
                    // Only a real change shows the OSD: the switch also fires while the page builds
                    if (Config.options.osd.material.minimal === checked)
                        return;
                    Config.options.osd.material.minimal = checked;
                    osdRoot.triggerRealOsd();
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
                    // Only a real change shows the OSD: the switch also fires while the page builds
                    if (Config.options.osd.material.shapedValues === checked)
                        return;
                    Config.options.osd.material.shapedValues = checked;
                    osdRoot.triggerRealOsd();
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
                    // Only a real change shows the OSD: the switch also fires while the page builds
                    if (Config.options.osd.material.circledShapes === checked)
                        return;
                    Config.options.osd.material.circledShapes = checked;
                    osdRoot.triggerRealOsd();
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
                    // Only a real change shows the OSD: the switch also fires while the page builds
                    if (Config.options.osd.material.rotateShape === checked)
                        return;
                    Config.options.osd.material.rotateShape = checked;
                    osdRoot.triggerRealOsd();
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
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
