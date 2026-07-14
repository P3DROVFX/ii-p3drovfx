import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    stickyHover: true

    readonly property bool hasDevices: BluetoothStatus.connectedDevices.length > 0

    function getDeviceImageSource(device) {
        if (!device)
            return "";
        
        let custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
        if (custom) {
            return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        }
        return "";
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12

        // Empty state placeholder
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            Layout.minimumWidth: 380
            visible: !root.hasDevices

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                MaterialShape {
                    Layout.alignment: Qt.AlignHCenter
                    shapeString: "Cookie6Sided"
                    implicitSize: 64
                    color: Appearance.colors.colSurfaceContainerHighest

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "bluetooth_disabled"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No devices connected")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Connect a Bluetooth device to see it here")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOutline
                }
            }
        }

        // Scalable list of devices
        Item {
            Layout.fillWidth: true
            Layout.minimumWidth: 320
            visible: root.hasDevices

            // Calculate total height needed for the children + spacing
            implicitHeight: {
                var c = rep.count;
                var dummyTrigger = root.hoverTarget ? root.hoverTarget.deviceIndex : 0;
                let h = 0;
                for (let i = 0; i < c; i++) {
                    let child = rep.itemAt(i);
                    if (child) {
                        h += child.implicitHeight;
                    }
                }
                if (c > 0)
                    h += (c - 1) * 12;
                // Fallback while items are booting up
                if (h === 0 && c > 0)
                    return c * 108 + (c - 1) * 12;
                return h;
            }

            Repeater {
                id: rep
                model: BluetoothStatus.connectedDevices
                delegate: Rectangle {
                    id: deviceCard
                    width: parent.width
                    implicitHeight: layoutRow.implicitHeight + 28
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerHigh

                    // The logic to smoothly swap items
                    readonly property int totalCount: BluetoothStatus.connectedDevices.length
                    property int vIndex: {
                        if (totalCount === 0)
                            return index;
                        let dIdx = root.hoverTarget ? root.hoverTarget.deviceIndex : 0;
                        return (index - dIdx + totalCount) % totalCount;
                    }

                    y: {
                        var _c = rep.count;
                        var trigger = vIndex; // Force QML reactivity on position shift
                        let yPos = 0;
                        for (let i = 0; i < _c; i++) {
                            let other = rep.itemAt(i);
                            if (other && other !== deviceCard && other.vIndex < trigger) {
                                yPos += other.implicitHeight + 12;
                            }
                        }
                        return yPos;
                    }

                    readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
                    
                    onStartAnimChanged: {
                        if (startAnim) {
                            deviceCard.opacity = 0.0;
                            deviceCard.scale = 0.85;
                            deviceCardTranslate.y = 25;
                            
                            Qt.callLater(function() {
                                deviceCardAnim.start();
                            });
                        }
                    }
                    
                    opacity: 0.0
                    scale: 1.0
                    transform: Translate {
                        id: deviceCardTranslate
                        y: (root.opened && root.popupOpenProgress > 0.6) ? 0 : 25
                    }
                    
                    SequentialAnimation {
                        id: deviceCardAnim
                        PauseAnimation { duration: 40 + index * 100 }
                        ParallelAnimation {
                            NumberAnimation { target: deviceCard; property: "opacity"; to: 1.0; duration: 300 }
                            NumberAnimation { target: deviceCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: deviceCardTranslate; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        }
                    }

                    Behavior on y {
                        NumberAnimation {
                            duration: 400
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }

                    RowLayout {
                        id: layoutRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 14
                        }
                        spacing: 16

                        // Image / Icon inside MaterialCookie
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredHeight: 80
                            Layout.preferredWidth: 80

                            MaterialShape {
                                id: bgShape
                                anchors.centerIn: parent
                                implicitSize: 80
                                color: Appearance.colors.colPrimary

                                function rollShape() {
                                    const shapes = ["Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Clover8Leaf", "SoftBurst", "Circle", "Sunny"];
                                    shapeString = shapes[Math.floor(Math.random() * shapes.length)];
                                }

                                Component.onCompleted: rollShape()

                                Connections {
                                    target: root
                                    function onActiveChanged() {
                                        if (root.active)
                                            bgShape.rollShape();
                                    }
                                }

                                NumberAnimation on rotation {
                                    from: 0
                                    to: 360
                                    duration: 10000
                                    loops: Animation.Infinite
                                    running: root.active
                                }
                            }

                            Loader {
                                anchors.centerIn: parent
                                active: root.getDeviceImageSource(modelData) !== ""
                                sourceComponent: Image {
                                    source: root.getDeviceImageSource(modelData)
                                    width: 60
                                    height: 60
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                            }

                            Loader {
                                anchors.centerIn: parent
                                active: root.getDeviceImageSource(modelData) === ""
                                sourceComponent: MaterialSymbol {
                                    text: Icons.getBluetoothDeviceMaterialSymbol(modelData.icon || "")
                                    iconSize: 36
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }

                        // Details column (Right aligned as in mockup)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            // Name
                            StyledText {
                                text: modelData.name || Translation.tr("Unknown device")
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.title
                                color: Appearance.colors.colOnSurface
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignRight
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            // Status
                            StyledText {
                                text: Translation.tr("Connected")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: Appearance.font.family.main
                                color: Appearance.colors.colOnSurfaceVariant
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignRight
                                Layout.fillWidth: true
                            }

                            // Battery Bar (StyledProgressBar)
                            RowLayout {
                                visible: modelData.batteryAvailable
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignRight
                                spacing: 8
                                Layout.topMargin: 8

                                StyledProgressBar {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 8
                                    valueBarHeight: 8
                                    from: 0
                                    to: 1
                                    value: modelData.battery ?? 0
                                    highlightColor: {
                                        if (modelData.battery <= 0.15)
                                            return Appearance.m3colors.m3error;
                                        return Appearance.colors.colPrimary;
                                    }
                                    trackColor: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.7)
                                }

                                StyledText {
                                    text: Math.round((modelData.battery ?? 0) * 100) + "%"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: {
                                        if (modelData.battery <= 0.15)
                                            return Appearance.m3colors.m3error;
                                        return Appearance.colors.colOnSurface;
                                    }
                                }
                            }

                            // ANC Modes (Supported Headsets Only)
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                Layout.alignment: Qt.AlignRight
                                visible: SoundcoreService.isHeadsetSupported(modelData) || BudsService.isHeadsetSupported(modelData)
                                spacing: 0

                                readonly property var service: {
                                    if (SoundcoreService.isHeadsetSupported(modelData)) return SoundcoreService;
                                    if (BudsService.isHeadsetSupported(modelData)) return BudsService;
                                    return null;
                                }
                                readonly property string currentMode: service ? service.getModeForMac(modelData.address) : "Normal"
                                
                                // ANC (Noise Canceling)
                                RippleButton {
                                    id: ancBtn
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: 16
                                    colBackground: parent.currentMode === "NoiseCanceling" ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    colBackgroundHover: parent.currentMode === "NoiseCanceling" ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                                    onClicked: parent.service.setMode(modelData.address, "NoiseCanceling")

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "noise_control_off"
                                        iconSize: 18
                                        color: ancBtn.colBackground === Appearance.colors.colPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 2
                                    color: Appearance.colors.colSurfaceContainerHighest
                                }

                                // Normal
                                RippleButton {
                                    id: normalBtn
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: 16
                                    colBackground: parent.currentMode === "Normal" ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    colBackgroundHover: parent.currentMode === "Normal" ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                                    onClicked: parent.service.setMode(modelData.address, "Normal")

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "hearing"
                                        iconSize: 18
                                        color: normalBtn.colBackground === Appearance.colors.colPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 2
                                    color: Appearance.colors.colSurfaceContainerHighest
                                }

                                // Transparency
                                RippleButton {
                                    id: transBtn
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: 16
                                    colBackground: parent.currentMode === "Transparency" ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    colBackgroundHover: parent.currentMode === "Transparency" ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                                    onClicked: parent.service.setMode(modelData.address, "Transparency")

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "visibility"
                                        iconSize: 18
                                        color: transBtn.colBackground === Appearance.colors.colPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
