import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        forceWidth: true

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Desktop")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
            }
        }

    ContentSection {
        icon: "wallpaper"
        title: Translation.tr("Desktop icons")

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Show desktop icons")
            checked: Config.options.akebono.desktop.enable
            onCheckedChanged: Config.options.akebono.desktop.enable = checked
        }
        ConfigSwitch {
            enabled: Config.options.akebono.desktop.enable
            buttonIcon: "visibility_off"
            text: Translation.tr("Show hidden files")
            checked: Config.options.akebono.desktop.showHidden
            onCheckedChanged: Config.options.akebono.desktop.showHidden = checked
        }
        ConfigSwitch {
            enabled: Config.options.akebono.desktop.enable
            buttonIcon: "label"
            text: Translation.tr("Show file extensions")
            checked: Config.options.akebono.desktop.showExtensions
            onCheckedChanged: Config.options.akebono.desktop.showExtensions = checked
        }

        ContentSubsection {
            title: Translation.tr("Icon size")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.desktop.iconSize
                onSelected: newValue => Config.options.akebono.desktop.iconSize = newValue
                options: [
                    { value: 48, displayName: Translation.tr("Small") },
                    { value: 64, displayName: Translation.tr("Medium") },
                    { value: 96, displayName: Translation.tr("Large") }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Sort by")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.desktop.sortBy
                onSelected: newValue => Config.options.akebono.desktop.sortBy = newValue
                options: [
                    { value: "name", displayName: Translation.tr("Name"), icon: "sort_by_alpha" },
                    { value: "date", displayName: Translation.tr("Date"), icon: "schedule" },
                    { value: "size", displayName: Translation.tr("Size"), icon: "straighten" },
                    { value: "type", displayName: Translation.tr("Type"), icon: "category" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Grid spacing")
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "swap_horiz"
                    text: Translation.tr("Horizontal")
                    value: Config.options.akebono.desktop.iconSpacingX
                    from: 0
                    to: 120
                    stepSize: 4
                    onValueChanged: Config.options.akebono.desktop.iconSpacingX = value
                }
                ConfigSpinBox {
                    icon: "swap_vert"
                    text: Translation.tr("Vertical")
                    value: Config.options.akebono.desktop.iconSpacingY
                    from: 0
                    to: 120
                    stepSize: 4
                    onValueChanged: Config.options.akebono.desktop.iconSpacingY = value
                }
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Desktop widgets")

        ConfigSwitch {
            buttonIcon: "dashboard"
            text: Translation.tr("Show widgets")
            checked: Config.options.akebono.desktop.showWidgets
            onCheckedChanged: Config.options.akebono.desktop.showWidgets = checked
        }
        ConfigSwitch {
            buttonIcon: "vibration"
            text: Translation.tr("Wobble while editing")
            checked: Config.options.akebono.desktop.widgetWobble
            onCheckedChanged: Config.options.akebono.desktop.widgetWobble = checked
        }
        ConfigSwitch {
            buttonIcon: "filter_drama"
            text: Translation.tr("Drop shadow")
            checked: Config.options.akebono.desktop.widgetShadow
            onCheckedChanged: Config.options.akebono.desktop.widgetShadow = checked
        }

        ConfigSpinBox {
            icon: "opacity"
            text: Translation.tr("Shadow strength (%)")
            enabled: Config.options.akebono.desktop.widgetShadow
            value: Math.round(Config.options.akebono.desktop.widgetShadowStrength * 100)
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: Config.options.akebono.desktop.widgetShadowStrength = value / 100
        }
    }
    }
}
