import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick

Squircle {
    id: root

    property real barHeight: 54

    implicitWidth: root.barHeight * 0.7
    implicitHeight: root.barHeight * 0.7
    radius: height / 2
    color: GlobalStates.sidebarLeftOpen ? Appearance.colors.colSecondaryContainer
        : sidebarMouse.containsMouse ? AkebonoAppearance.shelfPillHoverColor
        : AkebonoAppearance.shelfPillColor

    MaterialOrSvgIcon {
        anchors.centerIn: parent
        icon: Config.options.bar.topLeftIcon
        size: Math.round(root.barHeight * 0.4)
        color: GlobalStates.sidebarLeftOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
    }

    MouseArea {
        id: sidebarMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
    }

    StyledToolTip {
        extraVisibleCondition: sidebarMouse.containsMouse
        text: Translation.tr("Left sidebar")
    }
}
