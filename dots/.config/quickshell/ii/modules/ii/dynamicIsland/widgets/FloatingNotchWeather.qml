import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The weather activity when it takes the island's centre instead of sitting on the
 * resting face's end — which is what happens with the auxiliary bubble on. Same
 * glance, pill-sized: the bar's own weather icon and the temperature beside it.
 */
RowLayout {
    id: root
    anchors.fill: parent
    anchors.leftMargin: 14
    anchors.rightMargin: 14
    spacing: 8

    Item {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
    }

    Image {
        Layout.alignment: Qt.AlignVCenter
        source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
        sourceSize: Qt.size(18, 18)
        fillMode: Image.PreserveAspectFit
    }

    StyledText {
        Layout.alignment: Qt.AlignVCenter
        text: Weather.data?.temp ?? "--°"
        font.pixelSize: Appearance.font.pixelSize.small
        font.bold: true
        color: Appearance.colors.colOnSurface
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
    }
}
