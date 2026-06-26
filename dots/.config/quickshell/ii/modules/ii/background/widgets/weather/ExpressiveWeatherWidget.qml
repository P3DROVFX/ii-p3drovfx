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

    configEntryName: "weather"

    readonly property string tempText: Weather.data?.temp ?? "20°C"

    readonly property color solidSurfaceHighest: {
        const c = Qt.color(Appearance.colors.colSurfaceContainerHighest);
        return Qt.rgba(c.r, c.g, c.b, 1.0);
    }

    implicitWidth: 200
    implicitHeight: 240

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        MaterialShape {
            id: weatherIconShape
            Layout.preferredWidth: 200
            Layout.preferredHeight: 200
            Layout.alignment: Qt.AlignHCenter
            shapeString: Config.options.background.widgets.weather.backgroundShape
            color: Appearance.colors.colPrimaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 120
                text: Icons.getWeatherIcon(Weather.data?.wCode) ?? "cloud"
                color: Appearance.colors.colOnSurfaceVariant
                fill: 1.0
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignHCenter
            color: root.solidSurfaceHighest
            radius: Appearance.rounding.small

            StyledText {
                anchors.centerIn: parent
                text: root.tempText
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: 42
                font.weight: Font.Bold
            }
        }
    }
}
