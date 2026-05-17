import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool showPing: false
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    visible: aiChatEnabled || translatorEnabled || animeEnabled

    implicitWidth: loader.implicitWidth
    implicitHeight: loader.implicitHeight

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }
    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: fabStyle // Forced expressive
    }

    Component {
        id: fabStyle
        Fab {
            baseSize: Appearance.sizes.barHeight - 8
            buttonRadius: Appearance.rounding.full
            colBackground: GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainer
            onClicked: {
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
            }

            CustomIcon {
                anchors.centerIn: parent
                width: parent.baseSize - 12
                height: parent.baseSize - 12
                source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
                colorize: true
                color: Appearance.colors.colOnPrimaryContainer

                Rectangle {
                    opacity: root.showPing ? 1 : 0
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
    }
}
