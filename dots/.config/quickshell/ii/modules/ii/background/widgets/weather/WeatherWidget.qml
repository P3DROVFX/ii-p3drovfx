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

    configEntryName: "weather"

    readonly property bool expressive: Config.options.background.widgets.weather.expressiveColors ?? false

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    readonly property color iconColor: expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant

    StyledDropShadow {
        id: shadowEffect
        target: mainShape
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    MaterialShape {
        id: mainShape
        anchors.centerIn: parent
        implicitSize: Math.min(root.width, root.height)
        shape: MaterialShape.Shape.Pill
        color: "transparent"

        MaterialShape {
            id: bgShape
            anchors.fill: parent
            shape: parent.shape
            color: WidgetColorScheme.tintBackground(root.cardBgColor)
            visible: !(Config.options.background.widgets.enableInnerShadow ?? true)
        }

        InnerShadow {
            id: innerShadow
            anchors.fill: parent
            radius: 24
            samples: 49
            color: Qt.rgba(0, 0, 0, 0.35)
            source: bgShape
            visible: Config.options.background.widgets.enableInnerShadow ?? true
        }

        Item {
            anchors.fill: parent

            StyledText {
                font.pixelSize: 88
                font.family: Appearance.font.family.main
                font.weight: Font.Black
                color: Appearance.colors.colPrimary
                text: Weather.data?.temp ? Weather.data.temp.replace("°C", "°").replace("°F", "°") : ""
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 28
                anchors.topMargin: 36
                z: 1
            }

            Image {
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(130, 130)
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 18
                anchors.bottomMargin: 18
                z: 2
            }
        }
    }
}
