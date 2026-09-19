pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Weather, as the background's "weather icon" widget: the current condition's icon in
 * a Material shape, and nothing else.
 *
 * A variant of the `weather` group (see QuickToggleCatalog). The shape follows the
 * background widget's own setting, so the two stay the same object; when the tile is
 * wider than it is tall, the temperature sits beside the shape instead of leaving the
 * width empty.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property string shapeString: Config.options.background.widgets.weather_icon?.backgroundShape ?? "Cookie12Sided"
    readonly property real shapeSize: Math.min(root.surface.width, root.surface.height) - 12
    readonly property bool wide: root.surface.width > root.surface.height * 1.3
    readonly property string temperature: {
        const temp = Weather.data?.temp ?? "";
        return temp.replace("°C", "°").replace("°F", "°");
    }

    Row {
        anchors.centerIn: parent
        spacing: 10

        MaterialShape {
            id: shape
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: root.shapeSize
            shapeString: root.shapeString
            color: Appearance.colors.colSecondaryContainer

            Image {
                anchors.centerIn: parent
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                width: Math.round(root.shapeSize * 0.56)
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectFit
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.wide && root.temperature !== ""
            text: root.temperature
            font.pixelSize: Math.round(root.shapeSize * 0.42)
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer2
        }
    }
}
