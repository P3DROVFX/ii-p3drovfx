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

    configEntryName: "weather_icon"

    readonly property string shapeString: Config.options.background.widgets.weather_icon.backgroundShape ?? "Cookie12Sided"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color iconColor: WidgetColorScheme.textColorOnBg

    StyledDropShadow {
        id: shadowEffect
        target: weatherShape
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    MaterialShape {
        id: weatherShape
        anchors.centerIn: parent
        implicitSize: Math.min(root.width, root.height)
        shapeString: root.shapeString
        color: "transparent"

        MaterialShape {
            id: bgShape
            anchors.fill: parent
            shapeString: parent.shapeString
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

        Image {
            anchors.centerIn: parent
            source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
            sourceSize: Qt.size(110, 110)
        }
    }
}
