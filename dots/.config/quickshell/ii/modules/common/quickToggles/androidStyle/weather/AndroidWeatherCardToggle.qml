pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Weather, as the background's "weather card": the city, the temperature with the
 * condition and the day's high and low, and the next days below.
 *
 * Adaptive Freeform:
 * - 1-Column Narrow (1x1, 1x2, 1x3, 1x4): Clean vertical stack without crowded side-by-side elements.
 * - 1-Row Horizontal (2x1, 3x1, 4x1): Weather icon + temperature on the left, city on the right.
 * - Grid & Multi-Row (2x2, 2x3, 2x4, 3x2, 3x3, 4x2, 4x4): The original clean card layout with city header,
 *   hero temperature + icon and daily forecast rows beneath.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property var current: Weather.data
    readonly property var forecast: Weather.forecastData ?? []
    readonly property var today: root.forecast.length > 0 ? root.forecast[0] : null
    readonly property color textColor: Appearance.colors.colOnLayer2

    readonly property bool is1Col: root.effectiveSizeW === 1 || root.surface.width < 110
    readonly property bool is1Row: root.effectiveSizeH === 1 || root.surface.height < 75
    readonly property bool isNarrow: root.is1Col
    readonly property bool isShort: root.is1Row

    /** Forecast rows that fit under the header at this height. */
    readonly property int dayRows: Math.max(0, Math.min(root.forecast.length, Math.floor((root.surface.height - 96) / 24)))

    function degrees(value) {
        return value !== undefined && value !== null && value !== "" ? value + "°" : "";
    }

    readonly property string tempString: (root.current?.temp ?? "").replace("°C", "°").replace("°F", "°")
    readonly property string highLowString: root.today !== null
        ? ("H " + root.degrees(Weather.useUSCS ? root.today?.maxF : root.today?.maxC)
           + "  L " + root.degrees(Weather.useUSCS ? root.today?.minF : root.today?.minC))
        : ""

    // ── 1. NARROW 1-COLUMN TILES (1x1, 1x2, 1x3, 1x4) ────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 8
        visible: root.is1Col

        // 1x1 Compact: Icon + Temperature
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

        // 1x2: Clean centered vertical stack (Icon, Temp, High/Low - no location)
        Column {
            anchors.centerIn: parent
            spacing: 4
            visible: !root.is1Row && root.effectiveSizeH === 2
            width: parent.width

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                sourceSize: Qt.size(32, 32)
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.tempString
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.huge * 1.3
                font.weight: Font.Bold
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.highLowString !== ""
                text: root.highLowString
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.smallest * 0.95
                font.weight: Font.Medium
            }
        }

        // 1x3, 1x4+: Extended vertical stack with H/L and mini-forecast rows
        ColumnLayout {
            anchors.fill: parent
            spacing: 4
            visible: !root.is1Row && root.effectiveSizeH > 2

            Image {
                Layout.alignment: Qt.AlignHCenter
                source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                sourceSize: Qt.size(30, 30)
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.tempString
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.huge * 1.2
                font.weight: Font.Bold
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width
                text: root.current?.city || ""
                elide: Text.ElideRight
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.highLowString
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.smallest * 0.9
                font.weight: Font.Medium
                visible: root.highLowString !== ""
            }

            Item { Layout.fillHeight: true }

            Repeater {
                model: Math.max(0, Math.min(root.forecast.length, Math.floor((root.surface.height - 120) / 22)))

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

    // ── 2. MULTI-COLUMN 1-ROW TILES (2x1, 3x1, 4x1) ───────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 8
        visible: !root.is1Col && root.is1Row

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            Image {
                Layout.alignment: Qt.AlignVCenter
                source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                sourceSize: Qt.size(28, 28)
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.tempString
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.huge * 1.3
                font.weight: Font.Bold
            }
        }

        Item { Layout.fillWidth: true }

        StyledText {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            visible: root.highLowString !== ""
            text: root.highLowString
            color: root.textColor
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
        }
    }

    // ── 3. STANDARD & MULTI-ROW TILES (2x2, 2x3, 2x4, 3x2, 3x3, 4x2, 4x4) ────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4
        visible: !root.is1Col && !root.is1Row

        StyledText {
            Layout.fillWidth: true
            text: root.current?.city || ""
            elide: Text.ElideRight
            color: root.textColor
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: root.tempString
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.huge * 1.6
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 0

                Image {
                    Layout.alignment: Qt.AlignRight
                    source: WeatherIcons.getWeatherIcon(root.current?.wCode ?? 113, false)
                    sourceSize: Qt.size(28, 28)
                }

                StyledText {
                    Layout.alignment: Qt.AlignRight
                    visible: root.highLowString !== ""
                    text: root.highLowString
                    color: root.textColor
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                }
            }
        }

        Item { Layout.fillHeight: true }

        Repeater {
            model: root.dayRows

            delegate: RowLayout {
                id: dayRow
                required property int index
                readonly property var day: root.forecast.length > dayRow.index ? root.forecast[dayRow.index] : null

                Layout.fillWidth: true
                spacing: 8
                visible: dayRow.day !== null

                StyledText {
                    Layout.preferredWidth: 40
                    text: dayRow.day?.date ? new Date(dayRow.day.date).toLocaleDateString(Qt.locale(), "ddd") : ""
                    color: root.textColor
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                }

                Item { Layout.fillWidth: true }

                Image {
                    source: WeatherIcons.getWeatherIcon(dayRow.day?.code ?? 113, false)
                    sourceSize: Qt.size(18, 18)
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: dayRow.day
                        ? root.degrees(Weather.useUSCS ? dayRow.day.minF : dayRow.day.minC)
                            + "  " + root.degrees(Weather.useUSCS ? dayRow.day.maxF : dayRow.day.maxC)
                        : ""
                    color: root.textColor
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                }
            }
        }
    }
}
