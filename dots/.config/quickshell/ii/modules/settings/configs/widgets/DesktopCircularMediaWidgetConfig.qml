import QtQuick
import QtQuick.Layouts
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
            text: Translation.tr("Circular Media (Watch) Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Media Settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("circular_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Media widget disabled")
                description: Translation.tr("Enable the Circular Media (Watch) widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("circular_media")

            ConfigSwitch {
                buttonIcon: "color_lens"
                text: Translation.tr("Use album colors (Dynamic Theme)")
                checked: Config.options.background.widgets.circular_media.useAlbumColors
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.useAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Visual Options (Shadows)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel {
                    text: Translation.tr("Visual Options")
                }

                ConfigSwitch {
                    buttonIcon: "wb_sunny"
                    text: Translation.tr("Enable Shadows")
                    checked: Config.options.background.widgets.enableShadows ?? true
                    onCheckedChanged: {
                        Config.options.background.widgets.enableShadows = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr("Enable Inner Shadows")
                    checked: Config.options.background.widgets.enableInnerShadow ?? true
                    onCheckedChanged: {
                        Config.options.background.widgets.enableInnerShadow = checked;
                    }
                }
            }
        }
    }
}
