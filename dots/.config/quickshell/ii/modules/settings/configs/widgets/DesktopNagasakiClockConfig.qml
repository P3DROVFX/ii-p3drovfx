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
            text: Translation.tr("Nagasaki Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Nagasaki Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_nagasaki")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nagasaki Clock disabled")
                description: Translation.tr("Enable the Nagasaki Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_nagasaki")

            ContentSubsectionLabel {
                text: Translation.tr("Color")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Monochrome")
                checked: Config.options.background.widgets.clock_nagasaki.monochrome
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nagasaki.monochrome = checked;
                }
            }

            Item { Layout.preferredHeight: 8 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
