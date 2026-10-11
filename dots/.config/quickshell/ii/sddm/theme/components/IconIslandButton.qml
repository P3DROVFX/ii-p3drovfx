import QtQuick

// A square island button holding one filled icon, with an optional tooltip:
// the lock's sleep / power / reboot buttons.
IslandButton {
    id: root
    property string iconName
    property string tooltip: ""
    property real iconSize: Theme.pxHuge
    property color colText: root.toggled ? Theme.m3onPrimary : Theme.m3onSecondaryContainer

    implicitWidth: height
    colBackground: Theme.m3secondaryContainer
    colBackgroundHover: Theme.colSecondaryContainerHover
    colBackgroundActive: Theme.colSecondaryContainerActive
    colRipple: Theme.colSecondaryContainerActive

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        verticalAlignment: Text.AlignVCenter
        iconSize: root.iconSize
        text: root.iconName
        fill: 1
        color: root.colText
    }

    ToolTipContent {
        text: root.tooltip
        shown: root.hovered && root.tooltip !== ""
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        z: 100
    }
}
