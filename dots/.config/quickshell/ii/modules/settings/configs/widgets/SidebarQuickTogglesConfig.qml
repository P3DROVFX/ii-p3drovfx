import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    RowLayout {
        visible: root.showBackButton
        spacing: 12

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

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Quick Toggles & Sliders")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Quick Toggles Layout & Style")
        icon: "tune"

        ContentSubsection {
            title: Translation.tr("Quick toggles style")
            icon: "apps"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.sidebar.quickToggles.style
                onSelected: (newValue) => {
                    Config.options.sidebar.quickToggles.style = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Classic"),
                    "icon": "grid_view",
                    "value": "classic"
                }, {
                    "displayName": Translation.tr("Android"),
                    "icon": "android",
                    "value": "android"
                }]
            }
        }

        ConfigSpinBox {
            visible: Config.options.sidebar.quickToggles.style === "android"
            icon: "view_column"
            text: Translation.tr("Android style Columns")
            // The family's own grid, not a shared one. See PanelFamily.quickToggleLayout.
            value: PanelFamily.quickToggleLayout()?.columns ?? 4
            from: 1
            to: 6
            stepSize: 1
            onValueChanged: {
                PanelFamily.quickToggleLayout().columns = value;
            }
        }

        ConfigSwitch {
            visible: Config.options.sidebar.quickToggles.style === "android"
            buttonIcon: "tune"
            text: Translation.tr("Use 2x1 Capsule Sliders for 3-State Toggles")
            checked: Config.options.sidebar.quickToggles.useThreeWaySliders
            onCheckedChanged: {
                Config.options.sidebar.quickToggles.useThreeWaySliders = checked;
            }
            StyledToolTip {
                text: Translation.tr("Convert compatible 3-state widgets (ANC, Power Profiles, Keyboard Light) into 2x1 slide/swipe toggles.")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Fixed Sliders Configuration")
        icon: "linear_scale"

        ConfigSwitch {
            buttonIcon: "linear_scale"
            text: Translation.tr("Enable fixed sliders")
            checked: Config.options.sidebar.quickSliders.enable
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Enabling this, the sliders will be fixed on top of the sidebar, disable this if you want sliders to be inside a page.")
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "brightness_high"
            text: Translation.tr("Show Brightness")
            checked: Config.options.sidebar.quickSliders.showBrightness
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showBrightness = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "contrast"
            text: Translation.tr("Show Gamma")
            checked: Config.options.sidebar.quickSliders.showGamma
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showGamma = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "volume_up"
            text: Translation.tr("Show Volume")
            checked: Config.options.sidebar.quickSliders.showVolume
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showVolume = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "mic"
            text: Translation.tr("Show Microphone")
            checked: Config.options.sidebar.quickSliders.showMic
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showMic = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "swap_vert"
            text: Translation.tr("Vertical layout for sliders")
            checked: Config.options.sidebar.quickSliders.vertical
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.vertical = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Volume & Media Dialog")
        icon: "volume_up"

        ConfigSwitch {
            buttonIcon: "music_note"
            text: Translation.tr("Show media player in volume dialog")
            checked: Config.options.sidebar.volumeDialogMediaWidget
            onCheckedChanged: {
                Config.options.sidebar.volumeDialogMediaWidget = checked;
            }
            StyledToolTip {
                text: Translation.tr("Displays the current media player widget inside the volume popup dialog.")
            }
        }
    }
}
