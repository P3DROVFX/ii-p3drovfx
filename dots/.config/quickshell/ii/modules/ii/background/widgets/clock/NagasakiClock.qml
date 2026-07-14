pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property int implicitSize: 240
    width: implicitSize
    height: implicitSize

    FontLoader {
        id: nagasakiFont
        source: "file://" + Directories.assetsPath + "/fonts/nagasaki.ttf"
    }

    Rectangle {
        id: mainRect
        anchors.fill: parent
        color: Appearance.colors.colPrimaryContainer
        radius: Appearance.rounding.large
        clip: true

        readonly property string hour: DateTime.time.split(":")[0].padStart(2, "0")
        readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")

        readonly property real v_val: Appearance.m3colors.darkmode ? 0.95 : 0.8
        readonly property real v_sat: Appearance.m3colors.darkmode ? 0.7 : 0.9
        
        readonly property color color1: Appearance.colors.colOnSecondaryContainer
        readonly property color color2: Appearance.colors.colPrimary
        readonly property color color3: Qt.hsva(Appearance.colors.colPrimary.hsvHue, v_sat, v_val, 1.0)
        readonly property color color4: Qt.hsva(Appearance.colors.colTertiary.hsvHue, v_sat, v_val, 1.0)

        Row {
            id: contentRow
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.implicitSize * 0.12
            spacing: 4

            Text {
                text: mainRect.hour[0]
                font.family: nagasakiFont.name
                font.pixelSize: root.implicitSize * 0.8
                color: mainRect.color1
                height: contentHeight
                verticalAlignment: Text.AlignTop
            }

            Text {
                text: mainRect.hour[1]
                font.family: nagasakiFont.name
                font.pixelSize: root.implicitSize * 0.8
                color: mainRect.color2
                height: contentHeight
                verticalAlignment: Text.AlignTop
            }

            Text {
                text: mainRect.minute[0]
                font.family: nagasakiFont.name
                font.pixelSize: root.implicitSize * 0.8
                color: mainRect.color3
                height: contentHeight
                verticalAlignment: Text.AlignTop
            }

            Text {
                text: mainRect.minute[1]
                font.family: nagasakiFont.name
                font.pixelSize: root.implicitSize * 0.8
                color: mainRect.color4
                height: contentHeight
                verticalAlignment: Text.AlignTop
            }
        }
    }
}
