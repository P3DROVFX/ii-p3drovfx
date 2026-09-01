import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.configs.widgets

ContentPage {
    id: root

    signal goBack()

    forceWidth: false

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
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

        }

        StyledText {
            text: Translation.tr("Nothing Weather Circle Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }

    }

    ContentSection {
        title: Translation.tr("Weather Settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("nothing_weather_circle")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nothing Weather Circle widget disabled")
                description: Translation.tr("Enable the Nothing Weather Circle widget in Desktop Widgets settings to use this page.")
            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("nothing_weather_circle")

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
