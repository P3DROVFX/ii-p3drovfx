import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

    RowLayout {
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
            text: Translation.tr("Game Overlay Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    KeyboardShortcutBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        text: Translation.tr("Toggle Game Overlay")
        keys: ["Super", "G"]
    }

    ContentSection {
        title: Translation.tr("General")
        icon: "tune"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "high_density"
                text: Translation.tr("Enable opening zoom animation")
                checked: Config.options.overlay.openingZoomAnimation
                onCheckedChanged: {
                    Config.options.overlay.openingZoomAnimation = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "texture"
                text: Translation.tr("Darken screen")
                checked: Config.options.overlay.darkenScreen
                onCheckedChanged: {
                    Config.options.overlay.darkenScreen = checked;
                }
            }
            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("On-screen display timeout (ms)")
                value: Config.options.osd.timeout
                from: 500
                to: 10000
                stepSize: 100
                onValueChanged: {
                    Config.options.osd.timeout = value;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Crosshair")
        icon: "point_scan"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                text: Config.options.crosshair.code
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.crosshair.code = text;
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.leftMargin: 10
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    text: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
                }
                Item { Layout.fillWidth: true }
                RippleButtonWithIcon {
                    buttonRadius: Appearance.rounding.full
                    materialIcon: "open_in_new"
                    mainText: Translation.tr("Open editor")
                    onClicked: {
                        Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                    }
                    StyledToolTip {
                        text: "www.vcrdb.net"
                    }
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Floating Image")
        icon: "image"

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Image source")
            text: Config.options.overlay.floatingImage.imageSource
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.overlay.floatingImage.imageSource = text;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Notes")
        icon: "sticky_note_2"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "tab"
                text: Translation.tr("Show tabs")
                checked: Config.options.overlay.notes.showTabs
                onCheckedChanged: {
                    Config.options.overlay.notes.showTabs = checked;
                }
            }
            ConfigSwitch {
                enabled: Config.options.overlay.notes.showTabs
                buttonIcon: "edit_note"
                text: Translation.tr("Allow editing the icon")
                checked: Config.options.overlay.notes.allowEditingIcon
                onCheckedChanged: {
                    Config.options.overlay.notes.allowEditingIcon = checked;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Discord Voice")
        icon: "record_voice_over"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSpinBox {
                icon: "groups"
                text: Translation.tr("Maximum avatars")
                value: Config.options.overlay.discordVoice.maxAvatars
                from: 1
                to: 12
                stepSize: 1
                onValueChanged: {
                    Config.options.overlay.discordVoice.maxAvatars = value;
                }
            }

            ConfigSpinBox {
                icon: "account_circle"
                text: Translation.tr("Avatar size")
                value: Config.options.overlay.discordVoice.avatarSize
                from: 32
                to: 80
                stepSize: 2
                onValueChanged: {
                    Config.options.overlay.discordVoice.avatarSize = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("Layout")
                icon: "view_agenda"

                ConfigSelectionArray {
                    currentValue: Config.options.overlay.discordVoice.layoutMode
                    onSelected: newValue => { Config.options.overlay.discordVoice.layoutMode = newValue; }
                    options: [
                        { displayName: Translation.tr("Row"),    icon: "view_week", value: "row" },
                        { displayName: Translation.tr("Column"), icon: "view_agenda", value: "column" }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Participant background")
                icon: "background_dot_small"

                ConfigSelectionArray {
                    currentValue: Config.options.overlay.discordVoice.participantBackground
                    onSelected: newValue => { Config.options.overlay.discordVoice.participantBackground = newValue; }
                    options: [
                        { displayName: Translation.tr("None"),         icon: "block",          value: "none" },
                        { displayName: Translation.tr("Avatar + name"), icon: "badge",          value: "card" },
                        { displayName: Translation.tr("Name only"),     icon: "text_fields",    value: "name" }
                    ]
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Background opacity %")
                value: Math.round(Config.options.overlay.discordVoice.participantBackgroundOpacity * 100)
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.overlay.discordVoice.participantBackgroundOpacity = value / 100;
                }
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Blur background")
                checked: Config.options.overlay.discordVoice.blurEnabled
                onCheckedChanged: {
                    Config.options.overlay.discordVoice.blurEnabled = checked;
                }
            }
        }
    }
}
