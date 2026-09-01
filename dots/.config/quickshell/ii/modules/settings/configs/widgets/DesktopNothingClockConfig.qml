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
            text: Translation.tr("Nothing Digital Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Nothing Digital Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_nothing")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Nothing Clock disabled")
                description: Translation.tr("Enable the Nothing Digital Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_nothing")

            ContentSubsectionLabel {
                text: Translation.tr("Display Options")
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Use 24-Hour Format")
                checked: Config.options.background.widgets.clock_nothing.use24h ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.use24h = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "label"
                text: Translation.tr("Show AM/PM Chip (12-Hour Mode)")
                checked: Config.options.background.widgets.clock_nothing.showAmPmChip ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.showAmPmChip = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "short_text"
                text: Translation.tr("Show 'TIME' Top Header")
                checked: Config.options.background.widgets.clock_nothing.showTopLabel ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.showTopLabel = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "today"
                text: Translation.tr("Show Date at Bottom")
                checked: Config.options.background.widgets.clock_nothing.showDate ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.showDate = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Use Accent Color on Hours")
                checked: Config.options.background.widgets.clock_nothing.useAccentColor ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.clock_nothing.useAccentColor = checked;
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
