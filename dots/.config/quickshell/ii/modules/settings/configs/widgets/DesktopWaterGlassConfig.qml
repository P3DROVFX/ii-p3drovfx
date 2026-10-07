import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.productivity
import qs.modules.settings.configs.widgets

/*
 * The Water Glass widget (2x1). It counts on the Water Reminder's counter, so
 * the goal here is that widget's goal and the reminders stay on its page.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var options: Config.options.background.widgets.water_glass
    readonly property var water: Config.options.background.widgets.water_reminder

    WidgetPageHeader {
        title: Translation.tr("Water Glass Widget Options")
        onBack: root.goBack()
    }

    WidgetPreviewStage {
        columns: 2
        rows: 1

        WidgetPreviewSlot {
            columnSpan: 2
            WaterGlassWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Water Glass (2x1)")
        icon: "water_full"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "water_glass" }
            WidgetSizeSlider { options: root.options }

            ConfigSpinBox {
                icon: "flag"
                text: Translation.tr("Glasses per day")
                value: root.water.dailyGoal ?? 8
                from: 1
                to: 16
                stepSize: 1
                onValueChanged: root.water.dailyGoal = value
                StyledToolTip {
                    text: Translation.tr("Shared with the Water Reminder widget; its page also sets the reminders.")
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 40
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: WaterReminderService.resetCounter()

                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "restart_alt"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Reset today's count")
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
