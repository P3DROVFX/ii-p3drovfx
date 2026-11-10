pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.weather
import qs.modules.settings.configs.widgets

/*
 * One page for the expressive weather widgets - Monolith, Collage, Pattern
 * and Dial (1x1), Daylight, Ribbon and Strip (2x1), Ranges and Silhouette
 * (1x2). They read the shell's weather (Settings → Weather); here only
 * their size.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets

    WidgetPageHeader {
        title: Translation.tr("Expressive Weather Options")
        onBack: root.goBack()
    }

    // [ Ranges     ][ Daylight       ][ Monolith ]
    // [            ][ Ribbon         ][ Collage  ]
    // [ Silhouette ][ Strip          ][ Pattern  ]
    // [            ][ Dial ]
    WidgetPreviewStage {
        columns: 4
        rows: 4

        WidgetPreviewSlot {
            rowSpan: 2
            WeatherRangesWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }
        WidgetPreviewSlot {
            column: 1
            columnSpan: 2
            WeatherDaylightWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            WeatherMonolithWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 1
            columnSpan: 2
            WeatherRibbonWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            row: 1
            WeatherCollageWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            row: 2
            rowSpan: 2
            WeatherSilhouetteWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 2
            columnSpan: 2
            WeatherStripWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            row: 2
            WeatherPatternWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 3
            WeatherDialWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    component SizeSection: ContentSection {
        id: section
        property string widgetId
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: section.widgetId }
            WidgetSizeSlider { options: root.widgets[section.widgetId] }
        }
    }

    SizeSection { title: Translation.tr("Weather Monolith (1x1)"); icon: "format_size"; widgetId: "weather_monolith" }
    SizeSection { title: Translation.tr("Weather Collage (1x1)"); icon: "category"; widgetId: "weather_collage" }
    SizeSection { title: Translation.tr("Weather Daylight (2x1)"); icon: "wb_twilight"; widgetId: "weather_daylight" }
    SizeSection { title: Translation.tr("Weather Ribbon (2x1)"); icon: "show_chart"; widgetId: "weather_ribbon" }
    SizeSection { title: Translation.tr("Weather Ranges (1x2)"); icon: "align_horizontal_left"; widgetId: "weather_ranges" }
    SizeSection { title: Translation.tr("Weather Pattern (1x1)"); icon: "blur_on"; widgetId: "weather_pattern" }
    SizeSection { title: Translation.tr("Weather Silhouette (1x2)"); icon: "reorder"; widgetId: "weather_silhouette" }
    SizeSection { title: Translation.tr("Weather Strip (2x1)"); icon: "view_week"; widgetId: "weather_strip" }
    SizeSection { title: Translation.tr("Weather Dial (1x1)"); icon: "avg_pace"; widgetId: "weather_dial" }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
