import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: leftSidebarButton

    property bool showPing: false

    property real buttonPadding: 5
    implicitWidth: 42
    implicitHeight: 34

    property real startRadius: Appearance.rounding.full
    property real endRadius: Appearance.rounding.full

    topLeftRadius: startRadius
    bottomLeftRadius: startRadius
    topRightRadius: endRadius
    bottomRightRadius: endRadius

    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarLeftOpen

    onPressed: {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen)
                return;
            leftSidebarButton.showPing = true;
        }
    }

    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen)
                return;
            leftSidebarButton.showPing = true;
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            leftSidebarButton.showPing = false;
        }
    }

    CustomIcon {
        id: distroIcon
        anchors.centerIn: parent
        width: 16
        height: 16
        visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon
        source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
        colorize: true
        color: leftSidebarButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

        Rectangle {
            opacity: leftSidebarButton.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    MaterialSymbol {
        id: materialIcon
        anchors.centerIn: parent
        visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
        text: Config.options.bar.topLeftIcon
        iconSize: 16
        fill: 1
        color: leftSidebarButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

        Rectangle {
            opacity: leftSidebarButton.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
