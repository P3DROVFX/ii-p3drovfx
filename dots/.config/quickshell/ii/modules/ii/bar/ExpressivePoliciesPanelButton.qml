import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: false
    property bool showPing: false
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    visible: aiChatEnabled || translatorEnabled || animeEnabled

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : Appearance.sizes.baseBarHeight - 8
    implicitHeight: vertical ? Appearance.sizes.verticalBarWidth - 8 : Appearance.sizes.baseBarHeight - 8

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen)
                return;
            root.showPing = true;
        }
    }
    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen)
                return;
            root.showPing = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    RippleButton {
        id: button
        anchors.fill: parent
        buttonRadius: Appearance.rounding.full

        // Approach 1 Vibrant Dynamic Colors
        colBackground: GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimary : Appearance.colors.colTertiary
        colBackgroundHover: GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimaryHover : Appearance.colors.colTertiaryHover
        colRipple: GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimaryActive : Appearance.colors.colTertiaryActive

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

        MaterialShape {
            id: shapeContainer
            anchors.centerIn: parent
            implicitSize: 24

            // Morph shape based on panel state
            shape: GlobalStates.sidebarLeftOpen ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie12Sided

            // Contrast shape color with button background
            color: GlobalStates.sidebarLeftOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnTertiary

            // Rotate shape 90 degrees smoothly
            rotation: GlobalStates.sidebarLeftOpen ? 90 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(shapeContainer)
            }

            CustomIcon {
                id: distroIcon
                anchors.centerIn: parent
                width: 16
                height: 16
                visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon
                source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
                colorize: true
                color: GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimary : Appearance.colors.colTertiary

                // Negate rotation to keep the distro icon straight
                rotation: -shapeContainer.rotation
            }

            MaterialSymbol {
                id: materialIcon
                anchors.centerIn: parent
                visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
                text: Config.options.bar.topLeftIcon
                iconSize: 16
                fill: 1
                color: GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimary : Appearance.colors.colTertiary

                // Negate rotation to keep the distro icon straight
                rotation: -shapeContainer.rotation
            }

            Rectangle {
                id: pingBadge
                opacity: root.showPing ? 1 : 0
                visible: opacity > 0
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    bottomMargin: -1
                    rightMargin: -1
                }
                implicitWidth: 8
                implicitHeight: 8
                radius: Appearance.rounding.full
                color: Appearance.colors.colError
                border.width: 1.5
                border.color: GlobalStates.sidebarLeftOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnTertiary

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pingBadge)
                }
            }
        }
    }
}
