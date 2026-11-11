pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.settings.configs.widgets

/*
 * One page for the card-less shape clocks - Hour Shape and Bloom (1x1),
 * Capsule and Dome (2x1), Totem (1x2). The hero is the five real clocks, live, as
 * the grid cells they take on the desktop.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets

    WidgetPageHeader {
        title: Translation.tr("Shape Clocks Options")
        onBack: root.goBack()
    }

    // [ Totem ][ Capsule        ][ Hour Shape ]
    // [       ][ Dome           ][ Bloom      ]
    WidgetPreviewStage {
        columns: 4
        rows: 2

        WidgetPreviewSlot {
            rowSpan: 2
            TotemClockWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }
        WidgetPreviewSlot {
            column: 1
            columnSpan: 2
            CapsuleClockWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            HourShapeClockWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 1
            columnSpan: 2
            DomeClockWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            row: 1
            BloomClockWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    // ── Hour Shape ──
    ContentSection {
        title: Translation.tr("Hour Shape Clock (1x1)")
        icon: "interests"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "clock_hour_shape" }
            WidgetSizeSlider { options: root.widgets.clock_hour_shape }
            ConfigSwitch {
                buttonIcon: "radio_button_checked"
                text: Translation.tr("Minutes moon")
                checked: root.widgets.clock_hour_shape.showMinutes ?? true
                onCheckedChanged: root.widgets.clock_hour_shape.showMinutes = checked
                StyledToolTip {
                    text: Translation.tr("A small moon carrying the minutes round the rim; off, the shape holds the hour alone.")
                }
            }
        }
    }

    // ── Bloom ──
    ContentSection {
        title: Translation.tr("Bloom Clock (1x1)")
        icon: "filter_vintage"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "clock_bloom" }
            WidgetSizeSlider { options: root.widgets.clock_bloom }
            ConfigSwitch {
                buttonIcon: "format_color_fill"
                text: Translation.tr("Filled")
                checked: root.widgets.clock_bloom.filled ?? false
                onCheckedChanged: root.widgets.clock_bloom.filled = checked
                StyledToolTip {
                    text: Translation.tr("Paint the shape in the accent colour instead of the widget surface.")
                }
            }
        }
    }

    // ── Capsule ──
    ContentSection {
        title: Translation.tr("Capsule Clock (2x1)")
        icon: "pill"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "clock_capsule" }
            WidgetSizeSlider { options: root.widgets.clock_capsule }
            ConfigSwitch {
                buttonIcon: "today"
                text: Translation.tr("Show date")
                checked: root.widgets.clock_capsule.showDate ?? true
                onCheckedChanged: root.widgets.clock_capsule.showDate = checked
                StyledToolTip {
                    text: Translation.tr("Weekday, day and month stacked beside the time.")
                }
            }
        }
    }

    // ── Dome ──
    ContentSection {
        title: Translation.tr("Dome Clock (2x1)")
        icon: "clock_loader_60"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "clock_dome" }
            WidgetSizeSlider { options: root.widgets.clock_dome }
            ConfigSwitch {
                buttonIcon: "today"
                text: Translation.tr("Show date")
                checked: root.widgets.clock_dome.showDate ?? true
                onCheckedChanged: root.widgets.clock_dome.showDate = checked
                StyledToolTip {
                    text: Translation.tr("The weekday and the date in the dome's two feet.")
                }
            }
        }
    }

    // ── Totem ──
    ContentSection {
        title: Translation.tr("Totem Clock (1x2)")
        icon: "view_agenda"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "clock_totem" }
            WidgetSizeSlider { options: root.widgets.clock_totem }
            ConfigSwitch {
                buttonIcon: "date_range"
                text: Translation.tr("Show week")
                checked: root.widgets.clock_totem.showWeek ?? true
                onCheckedChanged: root.widgets.clock_totem.showWeek = checked
                StyledToolTip {
                    text: Translation.tr("The date over a row of the week at the foot, today filled with its initial.")
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
