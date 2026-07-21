pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property var device
    signal dismissed()
    signal disconnectRequested()

    readonly property bool isHovered: backgroundMa.containsMouse

    onDeviceChanged: {
        dismissTimer.restart();
    }

    onIsHoveredChanged: {
        if (isHovered) {
            dismissTimer.stop();
        } else {
            dismissTimer.restart();
        }
    }

    Component.onCompleted: {
        if (!isHovered) dismissTimer.start();
    }

    // Auto-dismiss timer — stays open while hovered, or it should be
    Timer {
        id: dismissTimer
        interval: 5000
        repeat: false
        onTriggered: root.dismissed()
    }

    // Expose contentBackground for mask in parent PanelWindow
    property alias contentBackground: contentBackground

    function getDeviceImageSource(device) {
        if (!device) return "";
        let custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
        if (custom) {
            return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        }
        return "";
    }

    readonly property string deviceName: device?.name ?? Translation.tr("Unknown Device")
    readonly property string deviceIcon: device ? Icons.getBluetoothDeviceMaterialSymbol(device.icon || "") : "headphones"
    readonly property string deviceImageSource: getDeviceImageSource(device)
    readonly property bool hasCustomImage: deviceImageSource !== ""

    // Sizing
    property real popupWidth: 300
    property real horizontalPadding: 20
    property real verticalPadding: 20

    implicitWidth: popupWidth + 2 * Appearance.sizes.elevationMargin
    implicitHeight: contentLayout.implicitHeight + verticalPadding * 2 + 2 * Appearance.sizes.elevationMargin

    // Expose a static, unscaled item for the window input mask to prevent coordinate bugs during scale
    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
    }


    Rectangle {
        id: contentBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        radius: Appearance.rounding.large
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Animations applied on the card itself to keep root window input mapping clean
        opacity: 0
        scale: 0.85
        transformOrigin: Item.TopRight

        Component.onCompleted: {
            entranceAnim.start()
        }

        ParallelAnimation {
            id: entranceAnim
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                from: 0; to: 1
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: contentBackground
                property: "scale"
                from: 0.85; to: 1
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        // Prevent click-throughs to backgroundMa and dismissals when clicking inside the card
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => mouse.accepted = true
            onPressed: mouse => mouse.accepted = true
            onReleased: mouse => mouse.accepted = true
        }

        ColumnLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.horizontalPadding
                topMargin: root.verticalPadding
                bottomMargin: root.verticalPadding
            }
            spacing: 12

            // === DEVICE NAME ===
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignLeft
                text: root.deviceName
                font.pixelSize: 26
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }

            // === STATUS TEXT ===
            StyledText {
                Layout.topMargin: -8
                horizontalAlignment: Text.AlignLeft
                text: Translation.tr("Connected")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.main
                color: Appearance.colors.colOnSurfaceVariant
            }

            // === DEVICE IMAGE / ICON AREA ===
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                implicitHeight: 160
                Layout.topMargin: 4

                // Cookie shape background (centered)
                MaterialCookie {
                    id: cookieShape
                    anchors.centerIn: parent
                    implicitSize: 150
                    color: Appearance.colors.colPrimaryContainer

                    RotationAnimation on rotation {
                        from: 0; to: 360
                        duration: 15000
                        loops: Animation.Infinite
                        running: true
                    }

                    NumberAnimation on scale {
                        from: 0; to: 1
                        duration: 650
                        easing.type: Easing.OutBack
                        easing.overshoot: 2.5
                    }
                }

                // Device image or icon on top of the cookie shape
                Loader {
                    anchors.centerIn: parent
                    active: root.hasCustomImage
                    sourceComponent: Image {
                        source: root.deviceImageSource
                        width: 110
                        height: 110
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        
                        NumberAnimation on scale {
                            from: 0; to: 1
                            duration: 750
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.5
                        }
                    }
                }

                // Fallback MaterialSymbol icon when no custom image
                Loader {
                    anchors.centerIn: parent
                    active: !root.hasCustomImage
                    sourceComponent: MaterialSymbol {
                        text: root.deviceIcon
                        iconSize: 64
                        color: Appearance.colors.colOnPrimaryContainer

                        NumberAnimation on scale {
                            from: 0; to: 1
                            duration: 750
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.5
                        }
                    }
                }
            }

            // === BATTERY INDICATOR (M3 Expressive StyledProgressBar) ===
            RowLayout {
                visible: root.device?.batteryAvailable ?? false
                Layout.fillWidth: true
                spacing: 12

                StyledProgressBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10
                    valueBarHeight: 10
                    from: 0
                    to: 1
                    value: root.device?.battery ?? 0
                    highlightColor: {
                        const battery = root.device?.battery ?? 0;
                        if (battery <= 0.15) return Appearance.m3colors.m3error;
                        return Appearance.colors.colPrimary;
                    }
                    trackColor: Appearance.colors.colSurfaceContainerHighest
                }

                StyledText {
                    text: Math.round((root.device?.battery ?? 0) * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: {
                        const battery = root.device?.battery ?? 0;
                        if (battery <= 0.15) return Appearance.m3colors.m3error;
                        return Appearance.colors.colOnSurface;
                    }
                }
            }

            // === HEADPHONE ANC MODE INDICATOR ===
            Loader {
                active: SoundcoreService.isHeadsetSupported(root.device) || BudsService.isHeadsetSupported(root.device)
                Layout.fillWidth: true
                Layout.topMargin: 4
                sourceComponent: RowLayout {
                    spacing: 8

                    readonly property var service: {
                        if (SoundcoreService.isHeadsetSupported(root.device)) return SoundcoreService;
                        if (BudsService.isHeadsetSupported(root.device)) return BudsService;
                        return null;
                    }

                    MaterialSymbol {
                        text: {
                            let mode = parent.service ? parent.service.getModeForMac(root.device?.address) : "Normal";
                            if (mode === "Normal") return "hearing";
                            if (mode === "Transparency") return "visibility";
                            if (mode === "NoiseCanceling") return "noise_control_off";
                            return "hearing";
                        }
                        iconSize: 18
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: {
                            let mode = parent.service ? parent.service.getModeForMac(root.device?.address) : "Normal";
                            if (mode === "Normal") return Translation.tr("Normal");
                            if (mode === "Transparency") return Translation.tr("Transparency");
                            if (mode === "NoiseCanceling") return Translation.tr("ANC");
                            return Translation.tr("Normal");
                        }
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            // === ACTION BUTTONS ===
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                // Disconnect button
                Rectangle {
                    id: disconnectBtnRect
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 40
                    implicitWidth: 80
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: disconnectMa.containsMouse
                        ? Appearance.colors.colErrorContainerHover
                        : Appearance.m3colors.m3errorContainer

                    scale: disconnectMa.pressed ? 0.92 : (disconnectMa.containsMouse ? 1.05 : 1.0)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "bluetooth_disabled"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.m3colors.m3onErrorContainer
                    }

                    MouseArea {
                        id: disconnectMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.disconnectRequested()
                    }
                }

                // Settings / Open BT settings button
                Rectangle {
                    id: settingsBtnRect
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: settingsMa.containsMouse
                        ? Appearance.colors.colSurfaceContainerHighestHover
                        : Appearance.colors.colSurfaceContainerHighest

                    scale: settingsMa.pressed ? 0.96 : (settingsMa.containsMouse ? 1.02 : 1.0)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "settings"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            text: Translation.tr("Settings")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    MouseArea {
                        id: settingsMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            root.dismissed();
                            Quickshell.execDetached(["blueman-manager"]);
                        }
                    }
                }
            }
        }

        // backgroundMa moved to root for better detection
    }

    // Click anywhere on the card/margins to dismiss
    MouseArea {
        id: backgroundMa
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        onWheel: wheel => wheel.accepted = true
        onClicked: root.dismissed()
        onPressed: mouse => mouse.accepted = true
        onReleased: mouse => mouse.accepted = true
    }
}
