import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather_pill"

    implicitWidth: 240
    implicitHeight: 120

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

    StyledDropShadow {
        id: shadowEffect
        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        anchors.margins: 10
        radius: Appearance.rounding.full
        color: root.cardBgColor

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 36
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                iconSize: 78
                text: Icons.getWeatherIcon(Weather.data?.wCode) ?? "partly_cloudy_day"
                color: Appearance.colors.colPrimary
                fill: 1.0
            }

            Item { Layout.fillWidth: true }

            StyledText {
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                text: Weather.data?.temp ? Weather.data.temp.replace("°C", "°").replace("°F", "°") : ""
                color: root.textColorOnBg
                font.pixelSize: Appearance.font.pixelSize.huge * 1.9
                font.weight: Font.Bold
            }
        }
    }
}
