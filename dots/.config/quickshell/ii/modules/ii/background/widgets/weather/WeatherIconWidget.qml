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

    readonly property bool expressive: Config.options.background.widgets.weather_icon.expressiveColors ?? false
    readonly property string shapeString: Config.options.background.widgets.weather_icon.backgroundShape ?? "Cookie12Sided"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    readonly property color iconColor: expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant

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
            color: root.cardBgColor
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

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: 110
            text: Icons.getWeatherIcon(Weather.data?.wCode) ?? "cloud"
            color: root.iconColor
            fill: 1.0
        }
    }
}
