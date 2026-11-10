pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Weather, as the desktop's default "weather widget": a Material Pill shape
 * featuring prominent temperature typography at the top-right and a large
 * condition icon at the bottom-left.
 *
 * Freeform adaptive: centered Material Shape scaled smoothly to the tile's shortest dimension.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property string temperature: {
        const temp = Weather.data?.temp ?? "";
        return temp.replace("°C", "°").replace("°F", "°");
    }

    readonly property real shapeSize: Math.max(20, Math.min(root.surface.width, root.surface.height) - 12)

    MaterialShape {
        id: pillShape
        anchors.centerIn: parent
        implicitSize: root.shapeSize
        shape: MaterialShape.Shape.Pill
        color: Appearance.colors.colSecondaryContainer

        Item {
            anchors.fill: parent

            StyledText {
                font.pixelSize: Math.max(12, Math.round(parent.width * 0.36))
                font.family: Appearance.font.family.main
                font.weight: Font.Black
                color: Appearance.colors.colPrimary
                text: root.temperature
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: Math.round(parent.width * 0.12)
                anchors.topMargin: Math.round(parent.height * 0.15)
                z: 1
            }

            Image {
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                width: Math.round(parent.width * 0.54)
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectFit
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: Math.round(parent.width * 0.08)
                anchors.bottomMargin: Math.round(parent.height * 0.08)
                z: 2
            }
        }
    }
}
