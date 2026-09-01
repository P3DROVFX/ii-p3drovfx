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
            text: Translation.tr("Water Reminder Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Water Reminder Settings")
        icon: "water_drop"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("water_reminder")

            PagePlaceholder {
                anchors.fill: parent
                icon: "water_drop"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Water Reminder Widget disabled")
                description: Translation.tr("Enable the Water Reminder Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("water_reminder")

            ContentSubsectionLabel {
                text: Translation.tr("Reminders")
            }

            ConfigSwitch {
                buttonIcon: "notifications_active"
                text: Translation.tr("Enable Water Reminders")
                checked: Config.options.background.widgets.water_reminder.enable ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.water_reminder.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.widgets.water_reminder.enable ?? false
                icon: "av_timer"
                text: Translation.tr("Reminder interval (hours)")
                value: Config.options.background.widgets.water_reminder.intervalHours ?? 2
                from: 1
                to: 12
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.water_reminder.intervalHours = value;
                }
                StyledToolTip {
                    text: Translation.tr("How often to send a hydration notification while the daily goal is not reached.")
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Daily Goal")
            }

            ConfigSpinBox {
                icon: "flag"
                text: Translation.tr("Glasses per day")
                value: Config.options.background.widgets.water_reminder.dailyGoal ?? 8
                from: 1
                to: 12
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.water_reminder.dailyGoal = value;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Reminder Message")
            }

            ConfigTextField {
                id: reminderTextField
                Layout.fillWidth: true
                text: Translation.tr("Water reminder")
                placeholderText: Translation.tr("e.g. Time to hydrate! 💧")

                Component.onCompleted: {
                    reminderTextField.textField.text = Config.options.background.widgets.water_reminder.reminderText || "";
                }

                Connections {
                    target: reminderTextField.textField
                    function onTextChanged() {
                        Config.options.background.widgets.water_reminder.reminderText = reminderTextField.textField.text;
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 44

                RippleButton {
                    id: resetTodayBtn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: "restart_alt"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            text: Translation.tr("Reset today's count")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    onClicked: WaterReminderService.resetCounter()
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
