pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Weather, as the background's "weather icon" widget: the current condition's icon in
 * a Material shape, and the temperature when space allows.
 *
 * Adaptive Freeform:
 * - Square / Near-square (1x1, 2x2, 3x3, 4x4): Centered MaterialShape with weather icon.
 * - Horizontal (2x1, 3x1, 4x1, 4x2): MaterialShape on left, bold temperature on right.
 * - Vertical (1x2, 1x3, 1x4, 2x3, 2x4): MaterialShape on top, bold temperature below.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property string shapeString: Config.options.background.widgets.weather_icon?.backgroundShape ?? "Cookie12Sided"
    readonly property string temperature: {
        const temp = Weather.data?.temp ?? "";
        return temp.replace("°C", "°").replace("°F", "°");
    }

    readonly property bool isHorizontal: root.surface.width > root.surface.height * 1.25
    readonly property bool isVertical: root.surface.height > root.surface.width * 1.25
    readonly property bool isSquare: !isHorizontal && !isVertical

    // ── 1. SQUARE / NEAR-SQUARE (1x1, 2x2, 3x3, 4x4) ─────────────────────────
    Item {
        anchors.fill: parent
        visible: root.isSquare

        readonly property real shapeSize: Math.max(20, Math.min(root.surface.width, root.surface.height) - 16)

        MaterialShape {
            anchors.centerIn: parent
            implicitSize: parent.shapeSize
            shapeString: root.shapeString
            color: Appearance.colors.colSecondaryContainer

            Image {
                anchors.centerIn: parent
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                width: Math.round(parent.implicitSize * 0.58)
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectFit
            }
        }
    }

    // ── 2. HORIZONTAL (2x1, 3x1, 4x1, 4x2) ───────────────────────────────────
    Row {
        anchors.centerIn: parent
        spacing: Math.max(6, Math.round(root.surface.height * 0.10))
        visible: root.isHorizontal

        readonly property real shapeSize: Math.max(20, Math.min(root.surface.height - 16, root.surface.width * 0.42))

        MaterialShape {
            id: horiShape
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: parent.shapeSize
            shapeString: root.shapeString
            color: Appearance.colors.colSecondaryContainer

            Image {
                anchors.centerIn: parent
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                width: Math.round(parent.implicitSize * 0.58)
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectFit
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.temperature !== ""
            text: root.temperature
            font.pixelSize: Math.max(16, Math.min(root.surface.height * 0.45, (root.surface.width - parent.shapeSize - 24) * 0.50))
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer2
        }
    }

    // ── 3. VERTICAL (1x2, 1x3, 1x4, 2x3, 2x4) ─────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: Math.max(4, Math.round(root.surface.width * 0.08))
        visible: root.isVertical

        readonly property real shapeSize: Math.max(20, Math.min(root.surface.width - 16, root.surface.height * 0.45))

        MaterialShape {
            id: vertShape
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: parent.shapeSize
            shapeString: root.shapeString
            color: Appearance.colors.colSecondaryContainer

            Image {
                anchors.centerIn: parent
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                width: Math.round(parent.implicitSize * 0.58)
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectFit
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.temperature !== ""
            text: root.temperature
            font.pixelSize: Math.max(14, Math.min(root.surface.width * 0.38, (root.surface.height - parent.shapeSize - 20) * 0.45))
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer2
        }
    }
}
