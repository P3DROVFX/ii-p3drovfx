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

    readonly property bool monochrome: Config.options.background.widgets.clock_nagasaki.monochrome

    FontLoader {
        id: nagasakiFont
        source: "file://" + Directories.assetsPath + "/fonts/nagasaki.ttf"
    }

    Rectangle {
        id: mainRect
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
        radius: Appearance.rounding.large
        clip: true

        readonly property string hour: DateTime.time.split(":")[0].padStart(2, "0")
        readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")

        readonly property color color1: WidgetColorScheme.textColorOnBg
        readonly property color color2: root.monochrome ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.accentColor
        readonly property color color3: root.monochrome ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
        readonly property color color4: root.monochrome ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.onAccentColor

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
