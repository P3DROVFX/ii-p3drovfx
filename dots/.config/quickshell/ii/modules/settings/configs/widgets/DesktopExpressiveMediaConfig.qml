import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

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
            text: Translation.tr("Expressive Media Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Expressive Media Settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("media_expressive")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Expressive Media disabled")
                description: Translation.tr("Enable the Expressive Media widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("media_expressive")

            ContentSubsectionLabel {
                text: Translation.tr("Display")
            }

            ConfigSwitch {
                buttonIcon: "autorenew"
                text: Translation.tr("Rotate album art")
                checked: Config.options.background.widgets.media.rotateAlbumArt ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.rotateAlbumArt = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show time info")
                checked: Config.options.background.widgets.media.showTimeInfo ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.showTimeInfo = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "person"
                text: Translation.tr("Show artist")
                checked: Config.options.background.widgets.media.showArtist ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.showArtist = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "linear_scale"
                text: Translation.tr("Show progress slider")
                checked: Config.options.background.widgets.media.showProgressSlider ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.showProgressSlider = checked;
                }
            }

            Item { Layout.preferredHeight: 8 }

            ContentSubsectionLabel {
                text: Translation.tr("Colors")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Dynamic album colors")
                checked: Config.options.background.widgets.media.dynamicAlbumColors ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.media.dynamicAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 8 }

            // Visual Options (Shadows)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                DesktopWidgetVisualOptions {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
