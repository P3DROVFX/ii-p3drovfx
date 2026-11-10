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

    readonly property var opts: Config.options.background.widgets.clock_ios_analog

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
            text: Translation.tr("iOS Analog Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("iOS Analog Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_ios_analog")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("iOS Analog Clock disabled")
                description: Translation.tr("Enable the iOS Analog Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_ios_analog")

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
                buttonIcon: "radio_button_unchecked"
                text: Translation.tr("Show dial")
                checked: root.opts.showDial
                onCheckedChanged: {
                    root.opts.showDial = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A slightly lighter disc behind the indices.")
                }
            }

            Item { Layout.preferredHeight: 8 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
