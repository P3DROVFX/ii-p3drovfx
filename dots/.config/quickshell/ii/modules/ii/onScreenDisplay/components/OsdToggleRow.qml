import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root

    property string currentIndicator: "volume"
    property real buttonHeight: 56
    property var rootOsd // Reference to OSD root to call triggerOsd()

    spacing: 8

    // The OSD wrapper allocates this ColumnLayout a height proportional to
    // `expandedProgress` (Layout.preferredHeight: (...) * expandedProgress).
    // Without `clip: true`, the inner toggle rows keep their natural height
    // (2 * osdButtonHeight + spacing ~ 120px) and overflow downward into the
    // collapse button below — which is the "toggles saindo para fora do osd"
    // bug during the expand/collapse animation.
    clip: true

    component OsdToggleIconButton: RippleButton {
        id: toggleButton
        property string iconText
        property string label

        Layout.fillWidth: true
        Layout.preferredHeight: buttonHeight
        buttonRadius: Appearance.rounding.normal
        rippleEnabled: true

        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        colRippleToggled: Appearance.colors.colPrimaryActive

        readonly property color contentColor: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

        contentItem: RowLayout {
            spacing: 8
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            MaterialSymbol {
                text: toggleButton.iconText
                iconSize: Appearance.font.pixelSize.normal
                color: toggleButton.contentColor
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: toggleButton.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: toggleButton.contentColor
                Layout.fillWidth: true
                elide: Text.ElideRight
                Layout.alignment: Qt.AlignVCenter
            }
        }

        StyledToolTip {
            text: toggleButton.label
            extraVisibleCondition: toggleButton.hovered
        }
    }

    // Volume options (Rows D & E)
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.currentIndicator === "volume"

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            OsdToggleIconButton {
                iconText: "graphic_eq"
                label: EasyEffects.active ? Translation.tr("Disable EasyEffects") : Translation.tr("Enable EasyEffects")
                toggled: EasyEffects.active
                onClicked: {
                    EasyEffects.toggle();
                    if (root.rootOsd) root.rootOsd.triggerOsd();
                }
            }

            OsdToggleIconButton {
                iconText: Config.options.sounds.monoAudio ? "hearing_disabled" : "surround_sound"
                label: Config.options.sounds.monoAudio ? Translation.tr("Mono") : Translation.tr("Stereo")
                toggled: Config.options.sounds.monoAudio
                onClicked: {
                    MonoAudioService.toggle();
                    if (root.rootOsd) root.rootOsd.triggerOsd();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            OsdToggleIconButton {
                iconText: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? "mic_off" : "mic"
                label: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? Translation.tr("Unmute mic") : Translation.tr("Mute mic")
                toggled: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? true : false
                onClicked: {
                    Audio.toggleMicMute();
                    if (root.rootOsd) root.rootOsd.triggerOsd();
                }
            }

            OsdToggleIconButton {
                iconText: Config.options.sounds.enable ? "pause_circle" : "play_circle"
                label: Config.options.sounds.enable ? Translation.tr("Disable system sounds") : Translation.tr("Enable system sounds")
                toggled: Config.options.sounds.enable
                onClicked: {
                    Config.options.sounds.enable = !Config.options.sounds.enable;
                    if (root.rootOsd) root.rootOsd.triggerOsd();
                }
            }
        }
    }

    // Brightness options
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.currentIndicator === "brightness"

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            OsdToggleIconButton {
                iconText: "wb_twilight"
                label: Hyprsunset.temperatureActive ? Translation.tr("Disable nightlight") : Translation.tr("Enable nightlight")
                toggled: Hyprsunset.temperatureActive
                onClicked: {
                    Hyprsunset.toggleTemperature();
                    if (root.rootOsd) root.rootOsd.triggerOsd();
                }
            }

            OsdToggleIconButton {
                iconText: "keyboard"
                label: KeyboardBacklight.currentValue > 0 ? Translation.tr("Keyboard backlight off") : Translation.tr("Keyboard backlight on")
                toggled: KeyboardBacklight.currentValue > 0
                onClicked: {
                    if (KeyboardBacklight.available && KeyboardBacklight.ready) {
                        KeyboardBacklight.setValue(KeyboardBacklight.currentValue > 0 ? 0 : KeyboardBacklight.maxValue);
                    }
                    if (root.rootOsd) root.rootOsd.triggerOsd();
                }
            }
        }
    }
}
