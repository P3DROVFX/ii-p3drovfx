pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Weather, as the desktop's "weather circle" widget: an outer circle containing
 * an inner Cookie12Sided shape with the weather condition icon, temperature, and city.
 *
 * Freeform adaptive: centered circular shape scaled smoothly to the tile's shortest dimension.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    readonly property string temperature: {
        const temp = Weather.data?.temp ?? "";
        return temp.replace("°C", "°").replace("°F", "°");
    }

    readonly property real circleSize: Math.max(20, Math.min(root.surface.width, root.surface.height) - 12)

    Rectangle {
        id: outerCircle
        anchors.centerIn: parent
        width: root.circleSize
        height: width
        radius: width / 2
        color: Appearance.colors.colSecondaryContainer

        MaterialShape {
            id: innerCookie
            anchors.centerIn: parent
            implicitSize: outerCircle.width * 0.90
            shapeString: "Cookie12Sided"
            color: Appearance.colors.colLayer2

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                    readonly property real iconDimension: Math.max(14, Math.round(innerCookie.implicitSize * 0.42))
                    sourceSize: Qt.size(iconDimension * 2, iconDimension * 2)
                    Layout.preferredWidth: iconDimension
                    Layout.preferredHeight: iconDimension
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    StyledText {
                        text: root.temperature
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Math.max(10, Math.round(innerCookie.implicitSize * 0.16))
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        visible: root.effectiveSizeW >= 2 && (Weather.data?.city ?? "") !== ""
                        text: Weather.data?.city || ""
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Math.max(10, Math.round(innerCookie.implicitSize * 0.16))
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.maximumWidth: Math.max(40, innerCookie.implicitSize * 0.40)
                    }
                }
            }
        }
    }
}
