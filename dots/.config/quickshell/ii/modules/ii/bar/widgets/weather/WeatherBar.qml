pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "../../shared/cards"
import qs.modules.ii.bar.popups.weather

MouseArea {
    id: root
    property bool vertical: false
    property bool hovered: false
    implicitWidth: rowLayout.implicitWidth + 10 * 2.5
    implicitHeight: rowLayout.implicitHeight + 10 * 2

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onPressed: Weather.refreshManually()
    }

    GridLayout {
        id: rowLayout
        anchors.centerIn: parent

        columns: root.vertical ? 1 : 2
        rows: root.vertical ? 2 : 1

        Image {
            source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
            sourceSize: Qt.size(Appearance.font.pixelSize.large, Appearance.font.pixelSize.large)
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }

        StyledText {
            visible: true
            font.pixelSize: root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: Weather.data?.temp ?? "--°"
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }
    }

    WeatherPopup {
        compact: Config.options.bar.tooltips.compactPopups
        hoverTarget: root
    }
}