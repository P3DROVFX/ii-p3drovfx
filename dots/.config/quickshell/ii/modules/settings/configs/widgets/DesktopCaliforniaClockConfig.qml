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

    readonly property var opts: Config.options.background.widgets.clock_california

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
            text: Translation.tr("California Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("California Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_california")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("California Clock disabled")
                description: Translation.tr("Enable the California Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_california")

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
                text: Translation.tr("Show second hand")
                checked: root.opts.showSeconds
                onCheckedChanged: {
                    root.opts.showSeconds = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Ticks every second while the widget is visible.")
                }
            }

            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Show date")
                checked: root.opts.showDate
                onCheckedChanged: {
                    root.opts.showDate = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Day and date between the pivot and the 6.")
                }
            }

            Item { Layout.preferredHeight: 8 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
