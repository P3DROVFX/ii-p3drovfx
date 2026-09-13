import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.services

AbstractBackgroundWidget {
    id: root

    readonly property color circleBgColor: WidgetColorScheme.cardBgColor
    readonly property color dotIconColor: WidgetColorScheme.textColorOnBg

    configEntryName: "nothing_weather_circle"
    implicitWidth: 240
    implicitHeight: 240

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
        color: WidgetColorScheme.tintBackground(root.circleBgColor)

        NothingWeatherIcon {
            id: weatherIcon

            anchors.centerIn: parent
            width: outerCircle.width * 0.55
            height: outerCircle.height * 0.55
            iconSize: Math.min(width, height)
            dotColor: root.dotIconColor
        }

    }

}
