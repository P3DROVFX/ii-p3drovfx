import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: page

    forceWidth: false

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("System sounds")

        ConfigSwitch {
            buttonIcon: "music_note"
            text: Translation.tr("Enable system sounds")
            checked: Config.options.sounds.enable
            onCheckedChanged: {
                Config.options.sounds.enable = checked;
            }

            StyledToolTip {
                text: Translation.tr("Master switch for shell event sounds. The alarm ring is not affected.")
            }

        }

        ConfigSlider {
            buttonIcon: "volume_up"
            text: Translation.tr("Sound volume")
            from: 0
            to: 100
            stepSize: 1
            value: Config.options.sounds.volume ?? 100
            onValueChanged: {
                if (Config.options.sounds.volume === Math.round(value))
                    return ;

                Config.options.sounds.volume = Math.round(value);
            }
            // Sample the new loudness when the slider is released
            onIsPressedChanged: {
                if (!isPressed)
                    SoundService.preview(Config.options.sounds.theme, ["audio-volume-change", "bell"]);

            }
        }

    }

    ContentSection {
        icon: "library_music"
        title: Translation.tr("Sound theme")
        tooltip: Translation.tr("Themes are discovered from /usr/share/sounds and ~/.local/share/sounds. Missing sounds fall back to the FreeDesktop theme.")

        Repeater {
            model: SoundService.themes

            ThemeCard {
            }

        }

        StyledText {
            visible: SoundService.themes.length === 0
            text: Translation.tr("No sound themes found")
            color: Appearance.colors.colSubtext
        }

    }

    ContentSection {
        icon: "notifications_active"
        title: Translation.tr("Events")

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Notifications")
            checked: Config.options.sounds.notifications
            onCheckedChanged: {
                Config.options.sounds.notifications = checked;
            }

            StyledToolTip {
                text: Translation.tr("Play a sound when a notification arrives. Muted in Do Not Disturb mode.")
            }

        }

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("Volume change")
            checked: Config.options.sounds.volumeChange
            onCheckedChanged: {
                Config.options.sounds.volumeChange = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "battery_alert"
            text: Translation.tr("Battery & power")
            checked: Config.options.sounds.battery
            onCheckedChanged: {
                Config.options.sounds.battery = checked;
            }

            StyledToolTip {
                text: Translation.tr("Charger plug/unplug, battery low and battery full.")
            }

        }

        ConfigSwitch {
            buttonIcon: "photo_camera"
            text: Translation.tr("Screenshot shutter")
            checked: Config.options.sounds.screenshot
            onCheckedChanged: {
                Config.options.sounds.screenshot = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "av_timer"
            text: Translation.tr("Pomodoro")
            checked: Config.options.sounds.pomodoro
            onCheckedChanged: {
                Config.options.sounds.pomodoro = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "alarm"
            text: Translation.tr("Alarm ring")
            checked: Config.options.sounds.alarm
            onCheckedChanged: {
                Config.options.sounds.alarm = checked;
            }

            StyledToolTip {
                text: Translation.tr("Rings even when system sounds are disabled, so the master switch can't silence your alarm.")
            }

        }

        ConfigSwitch {
            buttonIcon: "login"
            text: Translation.tr("Login")
            checked: Config.options.sounds.session
            onCheckedChanged: {
                Config.options.sounds.session = checked;
            }

            StyledToolTip {
                text: Translation.tr("Play a welcome sound when the shell starts.")
            }

        }

    }

    component PreviewButton: RippleButton {
        id: previewButton

        required property var modelData
        property string themeId

        implicitWidth: 34
        implicitHeight: 34
        topLeftRadius: Appearance.rounding.full
        topRightRadius: Appearance.rounding.full
        bottomLeftRadius: Appearance.rounding.full
        bottomRightRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: SoundService.preview(previewButton.themeId, previewButton.modelData.events)

        MaterialSymbol {
            anchors.centerIn: parent
            text: previewButton.modelData.icon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer3
        }

        StyledToolTip {
            text: previewButton.modelData.label
        }

    }

    component ThemeCard: Rectangle {
        id: card

        required property var modelData
        readonly property bool selected: Config.options.sounds.theme === modelData.id

        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight + 28
        radius: Appearance.rounding.normal
        color: selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2Base
        border.width: 1
        border.color: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            onClicked: Config.options.sounds.theme = card.modelData.id
        }

        ColumnLayout {
            id: cardLayout

            spacing: 10

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 14
            }

            RowLayout {
                spacing: 10

                MaterialSymbol {
                    text: card.selected ? "radio_button_checked" : "radio_button_unchecked"
                    iconSize: Appearance.font.pixelSize.huge
                    color: card.selected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: card.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: card.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        visible: card.modelData.comment !== ""
                        text: card.modelData.comment
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                }

            }

            RowLayout {
                spacing: 6

                StyledText {
                    text: Translation.tr("Preview:")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    Layout.rightMargin: 4
                }

                Repeater {
                    model: [{
                        "icon": "notifications",
                        "label": Translation.tr("Notification"),
                        "events": ["message-new-instant"]
                    }, {
                        "icon": "warning",
                        "label": Translation.tr("Warning"),
                        "events": ["dialog-warning"]
                    }, {
                        "icon": "error",
                        "label": Translation.tr("Error"),
                        "events": ["dialog-error"]
                    }, {
                        "icon": "volume_up",
                        "label": Translation.tr("Volume change"),
                        "events": ["audio-volume-change", "bell"]
                    }, {
                        "icon": "power",
                        "label": Translation.tr("Power plugged"),
                        "events": ["power-plug"]
                    }]

                    PreviewButton {
                        themeId: card.modelData.id
                    }

                }

                Item {
                    Layout.fillWidth: true
                }

            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 200
                easing.type: Easing.OutQuad
            }

        }

        Behavior on border.color {
            ColorAnimation {
                duration: 200
                easing.type: Easing.OutQuad
            }

        }

    }

}
