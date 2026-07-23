import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather_circle"

    readonly property bool expressive: Config.options.background.widgets.weather_circle.expressiveColors ?? false

    implicitWidth: 240
    implicitHeight: 240

    readonly property color outerCircleColor: Appearance.colors.colPrimary
    readonly property color cookieBgColor: expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    readonly property color textColorOnCookie: expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant

    StyledDropShadow {
        id: shadowEffect
        target: outerCircle
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: outerCircle
        anchors.centerIn: parent
        width: Math.min(root.width, root.height)
        height: width
        radius: width / 2
        color: root.outerCircleColor

        MaterialShape {
            id: innerCookie
            anchors.centerIn: parent
            implicitSize: outerCircle.width * 0.90
            shapeString: "Cookie12Sided"
            color: "transparent"

            MaterialShape {
                id: cookieBg
                anchors.fill: parent
                shapeString: parent.shapeString
                color: root.cookieBgColor
                visible: !(Config.options.background.widgets.enableInnerShadow ?? true)
            }

            InnerShadow {
                id: innerShadow
                anchors.fill: parent
                radius: 20
                samples: 41
                color: Qt.rgba(0, 0, 0, 0.40)
                source: cookieBg
                visible: Config.options.background.widgets.enableInnerShadow ?? true
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 76
                    text: Icons.getWeatherIcon(Weather.data?.wCode) ?? "partly_cloudy_day"
                    color: Appearance.colors.colPrimary
                    fill: 1.0
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    StyledText {
                        text: Weather.data?.temp ? Weather.data.temp.replace("°C", "°").replace("°F", "°") : ""
                        color: root.textColorOnCookie
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        text: Weather.data?.city || ""
                        color: root.textColorOnCookie
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.maximumWidth: 100
                    }
                }
            }
        }
    }
}
