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

    readonly property var opts: Config.options.background.widgets.clock_ios_tile

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
            text: Translation.tr("iOS Tile Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("iOS Tile Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_ios_tile")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("iOS Tile Clock disabled")
                description: Translation.tr("Enable the iOS Tile Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_ios_tile")

            ContentSubsectionLabel {
                text: Translation.tr("Display")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.opts.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    root.opts.widgetSize = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Show minute track")
                checked: root.opts.showTicks
                onCheckedChanged: {
                    root.opts.showTicks = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Sixty ticks that follow the rounded outline of the tile.")
                }
            }

            Item { Layout.preferredHeight: 8 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
