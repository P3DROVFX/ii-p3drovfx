pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.wellbeing
import qs.modules.settings.configs.widgets

/*
 * One page for the Wellbeing widgets. They read what the shell already
 * tracks - screen time (Usage), daily limits, Bedtime (Clock) and water - so
 * besides their size there is only the break interval here, and links to
 * where the rest is set.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets

    WidgetPageHeader {
        title: Translation.tr("Wellbeing Widgets Options")
        onBack: root.goBack()
    }

    // [ Day ][ Limits         ][ Ring  ]
    // [     ][ Bedtime        ][ Break ]
    WidgetPreviewStage {
        columns: 4
        rows: 2

        WidgetPreviewSlot {
            rowSpan: 2
            DayBalanceWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }
        WidgetPreviewSlot {
            column: 1
            columnSpan: 2
            ScreenTimeLimitsWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            ScreenTimeRingWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 1
            columnSpan: 2
            BedtimeWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            row: 1
            BreakWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Where the data comes from")
        icon: "self_improvement"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Screen time needs app tracking on (Usage). Limits are set in Usage → Daily limits, bedtime in Clock → Bedtime, water in the Water Reminder widget.")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
        RowLayout {
            spacing: 8
            RippleButtonWithIcon {
                materialIcon: "hourglass_top"
                mainText: Translation.tr("Daily limits")
                onClicked: GlobalStates.openUsageApp("limits")
            }
            RippleButtonWithIcon {
                materialIcon: "bedtime"
                mainText: Translation.tr("Bedtime")
                onClicked: GlobalStates.openClockApp("bedtime")
            }
        }
    }

    component SizeSection: ContentSection {
        id: section
        property string widgetId
        default property alias extra: extraBox.data
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: section.widgetId }
            WidgetSizeSlider { options: root.widgets[section.widgetId] }
            ColumnLayout {
                id: extraBox
                Layout.fillWidth: true
                spacing: 4
            }
        }
    }

    SizeSection { title: Translation.tr("Screen Time (1x1)"); icon: "donut_large"; widgetId: "wellbeing_screen_ring" }
    SizeSection { title: Translation.tr("Daily Limits (2x1)"); icon: "hourglass_top"; widgetId: "wellbeing_limits" }
    SizeSection { title: Translation.tr("Bedtime (2x1)"); icon: "bedtime"; widgetId: "wellbeing_bedtime" }
    SizeSection {
        title: Translation.tr("Take a Break (1x1)")
        icon: "self_improvement"
        widgetId: "wellbeing_break"

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Break every (minutes)")
            value: root.widgets.wellbeing_break.breakEveryMinutes
            from: 10
            to: 180
            stepSize: 5
            onValueChanged: root.widgets.wellbeing_break.breakEveryMinutes = value
        }
    }
    SizeSection { title: Translation.tr("Your Day (1x2)"); icon: "view_day"; widgetId: "wellbeing_day" }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
