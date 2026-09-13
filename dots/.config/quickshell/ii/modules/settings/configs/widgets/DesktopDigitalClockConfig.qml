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
            text: Translation.tr("Digital Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Digital Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_digital")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Digital Clock disabled")
                description: Translation.tr("Enable the Digital Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_digital")

            ContentSubsectionLabel {
                text: Translation.tr("Display")
            }

            ConfigSwitch {
                buttonIcon: "swap_vert"
                text: Translation.tr("Vertical")
                checked: Config.options.background.widgets.clock_digital.vertical
                onCheckedChanged: {
                    Config.options.background.widgets.clock_digital.vertical = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("Animate time change")
                checked: Config.options.background.widgets.clock_digital.animateChange
                onCheckedChanged: {
                    Config.options.background.widgets.clock_digital.animateChange = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Show date")
                checked: Config.options.background.widgets.clock_digital.showDate
                onCheckedChanged: {
                    Config.options.background.widgets.clock_digital.showDate = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "align_horizontal_center"
                text: Translation.tr("Use adaptive alignment")
                checked: Config.options.background.widgets.clock_digital.adaptiveAlignment
                onCheckedChanged: {
                    Config.options.background.widgets.clock_digital.adaptiveAlignment = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "more_vert"
                text: Translation.tr("Show colon")
                checked: Config.options.background.widgets.clock_digital.showColon
                onCheckedChanged: {
                    Config.options.background.widgets.clock_digital.showColon = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show seconds")
                checked: Config.options.bar.clock.showSeconds
                onCheckedChanged: {
                    Config.options.bar.clock.showSeconds = checked;
                }
            }

            Item { Layout.preferredHeight: 8 }

            ContentSubsectionLabel {
                text: Translation.tr("Typography")
            }

            ConfigSlider {
                buttonIcon: "format_bold"
                text: Translation.tr("Font weight")
                value: Config.options.background.widgets.clock_digital.font.weight
                from: 100
                to: 900
                stepSize: 100
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.weight = value;
                }
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Font size")
                value: Config.options.background.widgets.clock_digital.font.size
                from: 10
                to: 300
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.size = value;
                }
            }

            ConfigSlider {
                buttonIcon: "width_normal"
                text: Translation.tr("Font width")
                value: Config.options.background.widgets.clock_digital.font.width
                from: 10
                to: 200
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.width = value;
                }
            }

            ConfigSlider {
                buttonIcon: "rounded_corner"
                text: Translation.tr("Font roundness")
                value: Config.options.background.widgets.clock_digital.font.roundness
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.roundness = value;
                }
            }

            Item { Layout.preferredHeight: 8 }

            ContentSubsectionLabel {
                text: Translation.tr("Quote")
            }

            ConfigSwitch {
                buttonIcon: "format_quote"
                text: Translation.tr("Enable quote")
                checked: Config.options.background.widgets.clock_digital.quoteEnable
                onCheckedChanged: {
                    Config.options.background.widgets.clock_digital.quoteEnable = checked;
                }
            }

            ConfigTextField {
                enabled: Config.options.background.widgets.clock_digital.quoteEnable
                icon: "edit"
                text: Translation.tr("Quote text")
                inputText: Config.options.background.widgets.clock_digital.quoteText
                onInputTextChanged: {
                    Config.options.background.widgets.clock_digital.quoteText = inputText;
                }
            }

            Item { Layout.preferredHeight: 8 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
