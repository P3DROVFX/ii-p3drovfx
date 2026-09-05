import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: leftSidebarButton

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    property bool showPing: false

    property real buttonPadding: 5
    // Fixed 42x34 before: this one did not follow the bar even on the outside, so a
    // touch-first bar left it stranded at desktop size in the middle of taller neighbours.
    // No vertical variant of this one: it is only ever placed in a horizontal bar.
    readonly property real contentScale: Appearance.sizes.barContentScale

    implicitWidth: Math.round(42 * leftSidebarButton.contentScale)
    implicitHeight: Math.round(34 * leftSidebarButton.contentScale)

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
        GlobalStates.toggleLeftSidebar(screenName);
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
        // The Material symbol below is the alternative to this icon, not an
        // addition to it: without this guard both were drawn on top of each
        // other whenever the option was on.
        visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon
        width: 16
        height: 16
        source: {
            const icon = Config.options.bar.topLeftIcon;
            if (icon === 'distro') return SystemInfo.distroIcon;
            if (icon === 'docker') return 'docker.svg';
            if (icon.endsWith('.svg') || icon.endsWith('.png')) return icon;
            return `${icon}-symbolic`;
        }
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
            implicitWidth: Math.round(8 * leftSidebarButton.contentScale)
            implicitHeight: Math.round(8 * leftSidebarButton.contentScale)
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
        iconSize: Math.round(16 * leftSidebarButton.contentScale)
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
            implicitWidth: Math.round(8 * leftSidebarButton.contentScale)
            implicitHeight: Math.round(8 * leftSidebarButton.contentScale)
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
