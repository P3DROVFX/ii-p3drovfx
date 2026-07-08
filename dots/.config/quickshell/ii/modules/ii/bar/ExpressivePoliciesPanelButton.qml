import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: false
    property bool showPing: false
    visible: true

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

    // Phone integration in-use state (scrcpy mirror, phone webcam or phone mic).
    // While any of these is running, the button switches to the error container
    // palette as a recording/broadcast indicator (colErrorContainer /
    // colOnErrorContainer), mirroring the RecordIndicator convention.
    //
    // We also include the "connecting"/"launching" states so the colour flips
    // instantly when the user clicks — otherwise the button would wait 5-6s
    // for the verify timers to confirm the process is alive before changing
    // colour, which feels broken.
    //
    // Gated by Config.options.policies.phone: when Phone integration is
    // disabled, this binding short-circuits to false without ever
    // referencing the singletons, which prevents QML from instantiating
    // KdeConnectService / PhoneCameraService / PhoneMicService on boot.
    readonly property bool phoneIntegrationActive:
        Config.options.policies.phone !== 0
        && (KdeConnectService.scrcpyRunning
            || KdeConnectService.scrcpyLaunching
            || PhoneCameraService.connecting
            || PhoneCameraService.running
            || PhoneMicService.connecting
            || PhoneMicService.running)

    RippleButton {
        id: button
        anchors.fill: parent
        buttonRadius: Appearance.rounding.full

        // Approach 1 Vibrant Dynamic Colors
        colBackground: root.phoneIntegrationActive
            ? Appearance.colors.colErrorContainer
            : (GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimary : Appearance.colors.colTertiary)
        colBackgroundHover: root.phoneIntegrationActive
            ? Appearance.colors.colErrorContainerHover ?? Appearance.colors.colErrorContainer
            : (GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimaryHover : Appearance.colors.colTertiaryHover)
        colRipple: root.phoneIntegrationActive
            ? Appearance.colors.colErrorContainerActive ?? Appearance.colors.colErrorContainer
            : (GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimaryActive : Appearance.colors.colTertiaryActive)

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

        MaterialShape {
            id: shapeContainer
            anchors.centerIn: parent
            implicitSize: root.vertical ? 28 : 22

            // Morph shape based on panel state
            shape: GlobalStates.sidebarLeftOpen ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie9Sided

            // Contrast shape color with button background
            color: root.phoneIntegrationActive
                ? Appearance.colors.colOnErrorContainer
                : (GlobalStates.sidebarLeftOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnTertiary)

            // Rotate shape 90 degrees smoothly
            rotation: GlobalStates.sidebarLeftOpen ? 90 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(shapeContainer)
            }

            CustomIcon {
                id: distroIcon
                anchors.centerIn: parent
                width: root.vertical ? 16 : 14
                height: root.vertical ? 16 : 14
                visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon
                source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
                colorize: true
                color: root.phoneIntegrationActive
                    ? Appearance.colors.colErrorContainer
                    : (GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimary : Appearance.colors.colTertiary)

                // Negate rotation to keep the distro icon straight
                rotation: -shapeContainer.rotation
            }

            MaterialSymbol {
                id: materialIcon
                anchors.centerIn: parent
                visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
                text: Config.options.bar.topLeftIcon
                iconSize: root.vertical ? 18 : 16
                fill: 1
                color: root.phoneIntegrationActive
                    ? Appearance.colors.colErrorContainer
                    : (GlobalStates.sidebarLeftOpen ? Appearance.colors.colPrimary : Appearance.colors.colTertiary)

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
                border.color: root.phoneIntegrationActive
                    ? Appearance.colors.colOnErrorContainer
                    : (GlobalStates.sidebarLeftOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnTertiary)

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pingBadge)
                }
            }
        }
    }
}
