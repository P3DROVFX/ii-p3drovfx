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

    readonly property var fontVariantOptions: [
        { displayName: Translation.tr("Ultralight"), icon: "waves", value: "ultralight" },
        { displayName: Translation.tr("Thin"), icon: "text_decrease", value: "thin" },
        { displayName: Translation.tr("Light"), icon: "remove", value: "light" },
        { displayName: Translation.tr("Regular"), icon: "text_fields", value: "regular" },
        { displayName: Translation.tr("Medium"), icon: "subject", value: "medium" },
        { displayName: Translation.tr("Semi Bold"), icon: "text_increase", value: "semibold" },
        { displayName: Translation.tr("Bold"), icon: "format_bold", value: "bold" },
        { displayName: Translation.tr("Heavy"), icon: "format_size", value: "heavy" },
        { displayName: Translation.tr("Black"), icon: "circle", value: "black" }
    ]

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
            text: Translation.tr("iOS Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("iOS Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_ios")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("iOS Clock disabled")
                description: Translation.tr("Enable the iOS Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_ios")

            ContentSubsectionLabel {
                text: Translation.tr("Display")
            }

            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Show date")
                checked: Config.options.background.widgets.clock_ios.showDate
                onCheckedChanged: {
                    Config.options.background.widgets.clock_ios.showDate = checked;
                }
            }

            ConfigSlider {
                buttonIcon: "unfold_less"
                text: Translation.tr("Date spacing")
                value: Config.options.background.widgets.clock_ios.dateSpacing
                from: -40
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock_ios.dateSpacing = value;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Time format (follows the shell-wide setting)")
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: DateTime.use12HourClock ? Translation.tr("12-hour clock (from Time settings)") : Translation.tr("24-hour clock (from Time settings)")
                checked: DateTime.use12HourClock
                enabled: false
            }

            ContentSubsectionLabel {
                text: Translation.tr("Clock font")
            }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_ios.clockFontVariant ?? "bold"
                onSelected: value => Config.options.background.widgets.clock_ios.clockFontVariant = value
                options: root.fontVariantOptions
            }

            ContentSubsectionLabel {
                text: Translation.tr("Date font")
            }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_ios.dateFontVariant ?? "medium"
                onSelected: value => Config.options.background.widgets.clock_ios.dateFontVariant = value
                options: root.fontVariantOptions
            }

            ContentSubsectionLabel {
                text: Translation.tr("Some weights ship only as an italic cut of SF Pro Display")
            }

            Item { Layout.preferredHeight: 8 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
