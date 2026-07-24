import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import Qt5Compat.GraphicalEffects

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather"

    readonly property string tempText: Weather.data?.temp ?? "20°C"
    readonly property color expressiveTempRect: WidgetColorScheme.innerShapeColor

    readonly property color solidSurfaceHighest: {
        const c = Qt.color(Appearance.colors.colSurfaceContainerHighest);
        return Qt.rgba(c.r, c.g, c.b, 1.0);
    }

    implicitWidth: 200
    implicitHeight: 240

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        Item {
            Layout.preferredWidth: 200
            Layout.preferredHeight: 200
            Layout.alignment: Qt.AlignHCenter

            StyledDropShadow {
                id: weatherShadow
                target: weatherIconShape
                visible: Config.options.background.widgets.enableShadows ?? true
            }

            MaterialShape {
                id: weatherIconShape
                anchors.fill: parent
                shapeString: Config.options.background.widgets.weather.backgroundShape
                color: "transparent"

                // Background shape matching main shape to serve as source for InnerShadow
                MaterialShape {
                    id: bgShape
                    anchors.fill: parent
                    shapeString: parent.shapeString
                    color: root.expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                    visible: !(Config.options.background.widgets.enableInnerShadow ?? true)
                }

                InnerShadow {
                    id: innerShadow
                    anchors.fill: parent
                    radius: 24 // balanced radius for expressive shape
                    samples: 49
                    color: Qt.rgba(0, 0, 0, 0.35) // deep soft shadow
                    source: bgShape
                    visible: Config.options.background.widgets.enableInnerShadow ?? true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 120
                    text: Icons.getWeatherIcon(Weather.data?.wCode) ?? "cloud"
                    color: root.expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                    fill: 1.0
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignHCenter
            color: root.expressive ? root.expressiveTempRect : root.solidSurfaceHighest
            radius: Appearance.rounding.small

            StyledText {
                anchors.centerIn: parent
                text: root.tempText
                color: root.expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                font.pixelSize: 42
                font.weight: Font.Bold
            }
        }
    }
}
