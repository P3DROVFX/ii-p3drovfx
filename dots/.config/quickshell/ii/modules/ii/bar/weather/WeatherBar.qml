pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../cards"

MouseArea {
    id: root
    property bool vertical: false
    property bool hovered: false
    implicitWidth: rowLayout.implicitWidth + 10 * 2.5
    implicitHeight: rowLayout.implicitHeight + 10 * 2

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    // Separate right-click-only area so a right click never latches root.containsMouse
    // (which would otherwise open the popup in click-to-show mode)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onPressed: {
            Weather.getData();
            Quickshell.execDetached(["notify-send",
                Translation.tr("Weather"),
                Translation.tr("Refreshing (manually triggered)")
                , "-a", "Shell"
            ])
        }
    }

    GridLayout {
        id: rowLayout
        anchors.centerIn: parent

        columns: root.vertical ? 1 : 2
        rows: root.vertical ? 2 : 1

        MaterialSymbol {
            fill: 0
            text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
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