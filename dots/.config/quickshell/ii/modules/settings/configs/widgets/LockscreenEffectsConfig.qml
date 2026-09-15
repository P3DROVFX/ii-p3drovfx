import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
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
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Lock Screen Effects")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "blur_on"
            title: Translation.tr("Blur style")

            ConfigSwitch {
                buttonIcon: "lens_blur"
                text: Translation.tr("Enable blur")
                checked: Config.options.lock.blur.enable
                onCheckedChanged: Config.options.lock.blur.enable = checked
            }

            ConfigSlider {
                buttonIcon: "blur_circular"
                text: Translation.tr("Blur intensity")
                enabled: Config.options.lock.blur.enable
                from: 0
                to: 200
                stepSize: 5
                value: Config.options.lock.blur.radius
                usePercentTooltip: false
                onValueChanged: Config.options.lock.blur.radius = value
            }

            ConfigSpinBox {
                enabled: Config.options.lock.blur.enable
                icon: "zoom_in"
                text: Translation.tr("Extra wallpaper zoom (%)")
                value: Config.options.lock.blur.extraZoom * 100
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: Config.options.lock.blur.extraZoom = value / 100
            }
        }

        ContentSection {
            icon: "incomplete_circle"
            title: Translation.tr("Style: Desaturated")

            ConfigSwitch {
                buttonIcon: "deblur"
                text: Translation.tr("Desaturate wallpaper on lock")
                checked: Config.options.lock.desaturate.enable
                onCheckedChanged: Config.options.lock.desaturate.enable = checked
            }

            ConfigSlider {
                buttonIcon: "palette"
                text: Translation.tr("Desaturation amount")
                enabled: Config.options.lock.desaturate.enable
                from: 0
                to: 100
                stepSize: 5
                value: Config.options.lock.desaturate.amount * 100
                usePercentTooltip: true
                onValueChanged: Config.options.lock.desaturate.amount = value / 100
            }
        }

        ContentSection {
            icon: "palette"
            title: Translation.tr("Style: Color Wash")

            ConfigSwitch {
                buttonIcon: "format_color_fill"
                text: Translation.tr("Color wash overlay on lock")
                checked: Config.options.lock.colorWash.enable
                onCheckedChanged: Config.options.lock.colorWash.enable = checked
            }

            ConfigSlider {
                buttonIcon: "opacity"
                text: Translation.tr("Color wash intensity")
                enabled: Config.options.lock.colorWash.enable
                from: 0
                to: 100
                stepSize: 5
                value: Config.options.lock.colorWash.amount * 100
                usePercentTooltip: true
                onValueChanged: Config.options.lock.colorWash.amount = value / 100
            }
        }

        ContentSection {
            icon: "vignette"
            title: Translation.tr("Style: Vignette")

            ConfigSwitch {
                buttonIcon: "gradient"
                text: Translation.tr("Vignette effect on lock")
                checked: Config.options.lock.vignette.enable
                onCheckedChanged: Config.options.lock.vignette.enable = checked
            }

            ConfigSlider {
                buttonIcon: "dark_mode"
                text: Translation.tr("Vignette intensity")
                enabled: Config.options.lock.vignette.enable
                from: 0
                to: 100
                stepSize: 5
                value: Config.options.lock.vignette.amount * 100
                usePercentTooltip: true
                onValueChanged: Config.options.lock.vignette.amount = value / 100
            }
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "windows"
                    label: Translation.tr("Window blur")
                    sectionHighlight: Translation.tr("Transparency & Blur")
                }

                RelatedChip {
                    pageId: "wallpaper"
                    label: Translation.tr("Wallpaper blur")
                }
            }
        }
    }
}
