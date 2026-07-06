#pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool hovered: false
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: true

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (isMaterial ? materialPill.implicitWidth : defaultRow.implicitWidth + 6)
    implicitHeight: vertical ? (isMaterial ? materialPillVert.implicitHeight : defaultCol.implicitHeight + 6) : Appearance.sizes.baseBarHeight
    
    width: implicitWidth
    height: implicitHeight

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
                Translation.tr("Refreshing (manually triggered)"),
                "-a", "Shell"
            ])
        }
    }

    // Default Row (Non-Material)
    RowLayout {
        id: defaultRow
        anchors.centerIn: parent
        visible: !root.vertical && !root.isMaterial
        MaterialSymbol {
            fill: 0
            text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
            Layout.alignment: Qt.AlignVCenter
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: Weather.data?.temp ?? "--°"
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // Default Col (Non-Material Vertical)
    ColumnLayout {
        id: defaultCol
        anchors.centerIn: parent
        visible: root.vertical && !root.isMaterial
        MaterialSymbol {
            fill: 0
            text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
            text: (Weather.data?.temp ?? "--°").replace(/[CF]$/, "")
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // Material Pill (Horizontal)
    Rectangle {
        id: materialPill
        visible: !root.vertical && root.isMaterial
        anchors.centerIn: parent
        color: Appearance.colors.colPrimaryContainer
        radius: Appearance.rounding.full
        implicitHeight: Appearance.sizes.baseBarHeight - 8
        height: implicitHeight
        implicitWidth: tempText.implicitWidth + iconCircle.width + 20
        width: implicitWidth

        StyledText {
            id: tempText
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnPrimaryContainer
            text: Weather.data?.temp ?? "--°"
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            id: iconCircle
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height - 8
            height: width
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                fill: 0
                text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    // Material Pill (Vertical)
    Rectangle {
        id: materialPillVert
        visible: root.vertical && root.isMaterial
        anchors.centerIn: parent
        color: Appearance.colors.colPrimaryContainer
        radius: Appearance.rounding.full
        implicitWidth: Appearance.sizes.verticalBarWidth - 8
        width: implicitWidth
        implicitHeight: tempTextVert.implicitHeight + iconCircleVert.height + 16
        height: implicitHeight

        StyledText {
            id: tempTextVert
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnPrimaryContainer
            text: (Weather.data?.temp ?? "--°").replace(/[CF]$/, "")
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            id: iconCircleVert
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 4
            height: width
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    WeatherPopup {
        compact: Config.options.bar.tooltips.compactPopups
        hoverTarget: root
    }
}