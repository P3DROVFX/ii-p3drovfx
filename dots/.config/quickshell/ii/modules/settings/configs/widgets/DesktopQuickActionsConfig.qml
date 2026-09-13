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

    readonly property var moduleOptions: [
        { "displayName": Translation.tr("Translator"), "icon": "translate", "value": "translator" },
        { "displayName": Translation.tr("Phone"), "icon": "smartphone", "value": "phone" },
        { "displayName": Translation.tr("Wallpapers"), "icon": "wallpaper", "value": "wallpapers" },
        { "displayName": Translation.tr("Media"), "icon": "play_circle", "value": "media" },
        { "displayName": Translation.tr("Dashboard"), "icon": "dashboard", "value": "sidebar_dashboard" },
        { "displayName": Translation.tr("Cheatsheet"), "icon": "keyboard", "value": "cheatsheet" },
        { "displayName": Translation.tr("Notes"), "icon": "sticky_note_2", "value": "notes" }
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
            text: Translation.tr("Quick Actions Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Quick Actions Widget Settings")
        icon: "widgets"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("quick_actions")

            PagePlaceholder {
                anchors.fill: parent
                icon: "widgets"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Quick Actions Widget disabled")
                description: Translation.tr("Enable the Quick Actions Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("quick_actions")

            ContentSubsectionLabel {
                text: Translation.tr("Bottom Button 1")
            }

            ConfigSelectionArray {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                currentValue: Config.options.background.widgets.quick_actions.bottomButton1 || "translator"
                options: root.moduleOptions
                onSelected: newValue => {
                    Config.options.background.widgets.quick_actions.bottomButton1 = newValue;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Bottom Button 2")
            }

            ConfigSelectionArray {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                currentValue: Config.options.background.widgets.quick_actions.bottomButton2 || "phone"
                options: root.moduleOptions
                onSelected: newValue => {
                    Config.options.background.widgets.quick_actions.bottomButton2 = newValue;
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
