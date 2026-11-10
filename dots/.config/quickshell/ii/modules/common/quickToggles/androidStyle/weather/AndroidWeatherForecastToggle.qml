pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Weather, as the desktop's "weather forecast" widget: a hero card with current weather
 * alongside multi-day forecast pills.
 *
 * Adaptive Freeform:
 * - Horizontal layouts (2x1, 3x1, 4x1, 4x2): Hero card on left, forecast pills in columns side-by-side.
 * - Vertical layouts (1x2, 1x3, 1x4, 2x3, 2x4): Hero card on top, forecast items in rows stacked vertically.
 * - Square layouts (1x1, 2x2, 3x3, 4x4): Hero section on top with responsive forecast rows beneath.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property var current: Weather.data
    readonly property var forecast: Weather.forecastData ?? []
    readonly property var today: root.forecast.length > 0 ? root.forecast[0] : null
    readonly property color textColor: Appearance.colors.colOnLayer2

    readonly property string tempString: (root.current?.temp ?? "").replace("°C", "°").replace("°F", "°")
    readonly property string highLowString: root.today !== null
        ? ("H " + (Weather.useUSCS ? root.today?.maxF : root.today?.maxC) + "°  L " + (Weather.useUSCS ? root.today?.minF : root.today?.minC) + "°")
        : ""

    readonly property bool is1Col: root.effectiveSizeW === 1 || root.surface.width < 110
    readonly property bool is1Row: root.effectiveSizeH === 1 || root.surface.height < 75
    readonly property bool isVertical: root.surface.height > root.surface.width * 1.05

    // ── 1. NARROW 1-COLUMN TILES (1x1, 1x2, 1x3, 1x4) ────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 8
        visible: root.is1Col

        // 1x1 Compact
        Column {
            anchors.centerIn: parent
            spacing: 2
            visible: root.is1Row

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                sourceSize: Qt.size(24, 24)
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.tempString
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
            }
        }

        // 1x2, 1x3, 1x4 Vertical
        ColumnLayout {
            anchors.fill: parent
            spacing: 4
            visible: !root.is1Row

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(80, parent.height * 0.45)
                radius: 12
                color: Appearance.colors.colSecondaryContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                        sourceSize: Qt.size(26, 26)
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.tempString
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.huge * 1.1
                        font.weight: Font.Bold
                    }
                }
            }

            Repeater {
                model: Math.max(0, Math.min(root.forecast.length, Math.floor((root.surface.height - 90) / 22)))

                delegate: RowLayout {
                    id: miniColDay
                    required property int index
                    readonly property var day: root.forecast.length > miniColDay.index ? root.forecast[miniColDay.index] : null

                    Layout.fillWidth: true
                    spacing: 2
                    visible: miniColDay.day !== null

                    StyledText {
                        text: miniColDay.day?.date ? new Date(miniColDay.day.date).toLocaleDateString(Qt.locale(), "ddd") : ""
                        color: root.textColor
                        font.pixelSize: Appearance.font.pixelSize.smallest * 0.85
                        font.weight: Font.Medium
                    }

                    Item { Layout.fillWidth: true }

                    Image {
                        source: WeatherIcons.getWeatherIcon(miniColDay.day?.code ?? 113, false)
                        sourceSize: Qt.size(14, 14)
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: miniColDay.day
                            ? (Weather.useUSCS ? miniColDay.day.maxF : miniColDay.day.maxC) + "°"
                            : ""
                        color: root.textColor
                        font.pixelSize: Appearance.font.pixelSize.smallest * 0.85
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }

    // ── 2. VERTICAL MULTI-COLUMN TILES (2x3, 2x4, 3x4, 4x4 vertical) ───────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6
        visible: !root.is1Col && !root.is1Row && root.isVertical

        // Top Hero Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(68, Math.min(96, parent.height * 0.32))
            radius: 14
            color: Appearance.colors.colSecondaryContainer

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Image {
                    source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                    readonly property real iconSize: Math.max(32, Math.min(46, parent.height * 0.70))
                    sourceSize: Qt.size(iconSize, iconSize)
                    Layout.preferredWidth: iconSize
                    Layout.preferredHeight: iconSize
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    StyledText {
                        text: root.tempString
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.huge * 1.35
                        font.weight: Font.Bold
                    }

                    StyledText {
                        text: root.current?.wDesc || ""
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        opacity: 0.9
                    }
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    visible: root.highLowString !== ""
                    text: root.highLowString
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                }
            }
        }

        // Daily Forecast Items in Rows
        Repeater {
            model: Math.max(0, Math.min(root.forecast.length, Math.floor((root.surface.height - 110) / 40)))

            delegate: Rectangle {
                id: forecastRow
                required property int index
                readonly property var day: root.forecast.length > forecastRow.index ? root.forecast[forecastRow.index] : null

                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(34, Math.min(44, Math.floor((root.surface.height - 110) / Math.max(1, root.forecast.length))))
                radius: 12
                color: Appearance.colors.colSurfaceContainerHigh ?? Appearance.colors.colLayer2
                visible: forecastRow.day !== null

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    StyledText {
                        text: forecastRow.day?.date ? new Date(forecastRow.day.date).toLocaleDateString(Qt.locale(), "ddd") : ""
                        color: root.textColor
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        Layout.preferredWidth: 44
                    }

                    Item { Layout.fillWidth: true }

                    Image {
                        source: WeatherIcons.getWeatherIcon(forecastRow.day?.code ?? 113, false)
                        sourceSize: Qt.size(22, 22)
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: forecastRow.day
                            ? (Weather.useUSCS ? forecastRow.day.minF : forecastRow.day.minC) + "°  " + (Weather.useUSCS ? forecastRow.day.maxF : forecastRow.day.maxC) + "°"
                            : ""
                        color: root.textColor
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // ── 3. HORIZONTAL & WIDE TILES (2x1, 3x1, 4x1, 2x2, 3x2, 4x2, 4x3) ───────
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8
        visible: !root.is1Col && !root.isVertical

        // Left Hero Card
        Rectangle {
            id: leftHeroCard
            Layout.fillHeight: true
            Layout.preferredWidth: Math.max(100, Math.min(180, parent.width * 0.42))
            radius: 14
            color: Appearance.colors.colSecondaryContainer

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Image {
                        source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                        readonly property real heroIconSize: Math.max(22, Math.min(32, parent.parent.height * 0.40))
                        sourceSize: Qt.size(heroIconSize, heroIconSize)
                        Layout.preferredWidth: heroIconSize
                        Layout.preferredHeight: heroIconSize
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        visible: root.surface.height >= 70 && root.highLowString !== ""
                        text: root.highLowString
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.smallest * 0.9
                        font.weight: Font.Medium
                        Layout.alignment: Qt.AlignRight
                    }
                }

                Item { Layout.fillHeight: true }

                StyledText {
                    visible: root.surface.height >= 85 && (root.current?.wDesc ?? "") !== ""
                    text: root.current?.wDesc || ""
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.tempString
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Math.max(16, Math.min(28, root.surface.height * 0.35))
                    font.weight: Font.Bold
                }
            }
        }

        // Right Daily Forecast Pills (Columns side-by-side)
        Repeater {
            model: Math.max(0, Math.min(3, Math.min(root.forecast.length, Math.floor((root.surface.width - 120) / 48))))

            delegate: Rectangle {
                id: dayPill
                required property int index
                readonly property var day: root.forecast.length > dayPill.index ? root.forecast[dayPill.index] : null

                Layout.fillHeight: true
                Layout.fillWidth: true
                radius: 12
                color: Appearance.colors.colSurfaceContainerHigh ?? Appearance.colors.colLayer2
                visible: dayPill.day !== null

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: dayPill.day?.date ? new Date(dayPill.day.date).toLocaleDateString(Qt.locale(), "ddd") : ""
                        color: root.textColor
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                    }

                    Item { Layout.fillHeight: true }

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        source: WeatherIcons.getWeatherIcon(dayPill.day?.code ?? 113, false)
                        readonly property real pillIconSize: Math.max(16, Math.min(24, parent.height * 0.35))
                        sourceSize: Qt.size(pillIconSize, pillIconSize)
                        Layout.preferredWidth: pillIconSize
                        Layout.preferredHeight: pillIconSize
                    }

                    Item { Layout.fillHeight: true }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: dayPill.day ? (Weather.useUSCS ? dayPill.day.maxF : dayPill.day.maxC) + "°" : ""
                        color: root.textColor
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }
}
