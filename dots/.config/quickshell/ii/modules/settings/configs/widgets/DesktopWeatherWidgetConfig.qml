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
            text: Translation.tr("Weather Widget Options")
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
            visible: !Config.isWidgetActive("weather_default") && !Config.isWidgetActive("weather_expressive")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Weather widget disabled")
                description: Translation.tr("Enable a weather widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("weather_default") || Config.isWidgetActive("weather_expressive")

            ContentSubsection {
                visible: Config.isWidgetActive("weather_expressive")
                title: Translation.tr("Background shape")
                icon: "category"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.weather.backgroundShape
                    onSelected: newValue => {
                        Config.options.background.widgets.weather.backgroundShape = newValue;
                    }
                    options: ["Circle", "Pill", "Oval", "SemiCircle", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Puffy", "PuffyDiamond", "Bun", "SoftBurst", "Sunny", "VerySunny"].map(icon => {
                        return {
                            displayName: "",
                            shape: icon,
                            value: icon
                        };
                    })
                }
            }
            
            ContentSubsectionLabel {
                visible: !Config.isWidgetActive("weather_expressive") && Config.isWidgetActive("weather_default")
                text: Translation.tr("No custom settings available for the Default style.")
            }
            Item {
                Layout.preferredHeight: 16
            }

            // Visual Options (Shadows)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel {
                    text: Translation.tr("Visual Options")
                }

                ConfigSwitch {

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
