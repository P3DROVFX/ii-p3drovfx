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
            text: Translation.tr("Quote Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Quote Widget Settings")
        icon: "format_quote"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("quote")

            PagePlaceholder {
                anchors.fill: parent
                icon: "format_quote"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Quote Widget disabled")
                description: Translation.tr("Enable the Quote Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("quote")

            ContentSubsectionLabel {
                text: Translation.tr("Quote Text")
            }

            ConfigTextField {
                id: quoteTextField
                Layout.fillWidth: true
                text: Translation.tr("Your quote")
                placeholderText: Translation.tr("Enter your favorite quote...")

                Component.onCompleted: {
                    quoteTextField.textField.text = Config.options.background.widgets.quote.quoteText || "";
                }

                Connections {
                    target: quoteTextField.textField
                    function onTextChanged() {
                        Config.options.background.widgets.quote.quoteText = quoteTextField.textField.text;
                    }
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Text Size")
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Quote Font Size")
                from: 10
                to: 32
                stepSize: 1
                value: Config.options.background.widgets.quote.fontSize || 16
                usePercentTooltip: false
                tooltipContent: `${Math.round(value)}px`
                onValueChanged: {
                    Config.options.background.widgets.quote.fontSize = value;
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
