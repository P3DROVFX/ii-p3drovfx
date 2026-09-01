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
            text: Translation.tr("Nagasaki Text Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Nagasaki Text Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("nagasaki_text")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nagasaki Text Clock disabled")
                description: Translation.tr("Enable the Nagasaki Text Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("nagasaki_text")

            ContentSubsectionLabel {
                text: Translation.tr("Typography")
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Font Size")
                from: 100
                to: 400
                stepSize: 10
                value: Config.options.background.widgets.nagasaki_text.size ?? 200
                onValueChanged: {
                    Config.options.background.widgets.nagasaki_text.size = Math.round(value);
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
