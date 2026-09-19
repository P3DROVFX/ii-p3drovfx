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
 * A variant of the `weather` group (see QuickToggleCatalog). The forecast rows need
 * height, so a short tile keeps the header alone and adds days as it grows.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property var current: Weather.data
    readonly property var forecast: Weather.forecastData ?? []
    readonly property var today: root.forecast.length > 0 ? root.forecast[0] : null
    readonly property color textColor: Appearance.colors.colOnLayer2
    /** Forecast rows that fit under the header at this height. */
    readonly property int dayRows: Math.max(0, Math.min(3, Math.floor((root.surface.height - 96) / 24)))

    function degrees(value) {
        return value !== undefined && value !== null && value !== "" ? value + "°" : "";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

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
                text: (root.current?.temp ?? "").replace("°C", "°").replace("°F", "°")
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
                    visible: root.today !== null
                    text: "H " + root.degrees(Weather.useUSCS ? root.today?.maxF : root.today?.maxC)
                        + "  L " + root.degrees(Weather.useUSCS ? root.today?.minF : root.today?.minC)
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
