pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.bluetooth
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
        if (Config.options && Config.options.bluetoothDeviceImages) {
            let custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
            if (custom && custom.image) {
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
            }
        }

        const mac = (device.address || "").replace(/:/g, "_").toUpperCase();
        const name = (device.name || device.alias || "").toLowerCase();
        const basePath = Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/") : "";

        if (mac === "E8_EE_CC_96_31_3A" || name.includes("q30") || name.includes("soundcore life q30") || name.includes("soundcore")) {
            return basePath + "anker_q30_.png";
        }
        if (mac === "68_7D_6B_94_0B_C2" || name.includes("buds 3 pro") || name.includes("buds3 pro") || name.includes("galaxy buds 3 pro")) {
            return basePath + "galaxy_buds_3_pro.png";
        }
        if (name.includes("galaxy buds 3") || name.includes("buds 3") || name.includes("buds3")) {
            return basePath + "galaxy_buds_3.png";
        }
        if (mac === "64_1B_2F_9B_95_CE" || name.includes("s23")) {
            return basePath + "samsung_s23.png";
        }
        if (name.includes("s24")) {
            return basePath + "samsung_s24_ultra.png";
        }
        if (name.includes("pixel buds") || name.includes("buds pro") || name.includes("buds fe") || name.includes("buds")) {
            return basePath + "pixel_buds.png";
        }
        if (name.includes("xbox") || name.includes("elite")) {
            return basePath + "xbox_elite_series_2.png";
        }

        return "";
    }

    readonly property string deviceName: device?.name ?? Translation.tr("Unknown Device")
    readonly property string deviceIcon: device ? Icons.getBluetoothDeviceMaterialSymbol(device.icon || "") : "headphones"
    readonly property string deviceImageSource: getDeviceImageSource(device)
    readonly property bool hasCustomImage: deviceImageSource !== ""

    readonly property var devBattery: EarbudsControlService.batteryInfo(root.device)
    readonly property var devNoise: EarbudsControlService.noiseControl(root.device)
    readonly property var devCa: EarbudsControlService.conversationAwareness(root.device)

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

            // === BATTERY INDICATOR (Multi-component breakdown or single progress bar) ===
            BluetoothBatteryBreakdown {
                visible: root.devBattery && root.devBattery.available && root.devBattery.components.length > 1
                batteryInfo: root.devBattery
                compact: false
                showLabels: true
                showCase: true
                horizontal: true
                Layout.fillWidth: true
            }

            RowLayout {
                visible: (!root.devBattery || !root.devBattery.available || root.devBattery.components.length <= 1) && (root.device?.batteryAvailable ?? false)
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

            // === HEADPHONE ANC & CONVERSATION AWARENESS STATUS ===
            RowLayout {
                visible: (root.devNoise && root.devNoise.available) || (root.devCa && root.devCa.available && root.devCa.enabled)
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12

                RowLayout {
                    visible: root.devNoise && root.devNoise.available
                    spacing: 6

                    MaterialSymbol {
                        text: root.devNoise ? root.devNoise.currentModeIcon : "tune"
                        iconSize: 18
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        text: root.devNoise ? root.devNoise.currentModeLabel : ""
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    visible: root.devCa && root.devCa.available && root.devCa.enabled
                    spacing: 4

                    MaterialSymbol {
                        text: "record_voice_over"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        text: Translation.tr("Speak-to-Chat")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
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
