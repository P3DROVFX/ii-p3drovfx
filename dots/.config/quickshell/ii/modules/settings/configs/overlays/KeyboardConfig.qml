import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../.."
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.services

/** Overlays → On-screen keyboard: style, layout, size and the touch auto-show. */
Item {
    id: oskRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()
    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        ConfigSubPageHeader {
            visible: oskRoot.showBackButton
            title: Translation.tr("On-screen keyboard")
            onBack: oskRoot.goBack()
        }

        ContentSection {
            title: Translation.tr("On-screen keyboard")
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
                configPage: Qt.resolvedUrl("../widgets/OnScreenKeyboardConfig.qml")
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
