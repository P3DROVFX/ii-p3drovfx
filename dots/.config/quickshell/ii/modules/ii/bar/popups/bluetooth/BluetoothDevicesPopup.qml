import qs
import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.bluetooth
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    stickyHover: true
    readonly property bool sidebarOccludesPopup:
        (root.notifIsLeft && GlobalStates.effectiveLeftOpen)
        || (root.notifIsRight && GlobalStates.effectiveRightOpen)

    active: !sidebarOccludesPopup && (_computedActive || _isClosing)


    readonly property bool notifIsLeft: (Config.options.notifications.position ?? "top_right").endsWith("left")
    readonly property bool notifIsRight: (Config.options.notifications.position ?? "top_right").endsWith("right")

    readonly property bool hasDevices: BluetoothStatus.connectedDevices.length > 0

    function getDeviceImageSource(device) {
        if (!device)
            return "";
        
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
            Layout.minimumWidth: 380
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

                            iconContainer.scale = 0.8;
                            iconContainer.opacity = 0.0;
                            iconContainerTrans.x = -20;

                            detailsCol.opacity = 0.0;
                            detailsColTrans.x = 20;
                            
                            Qt.callLater(function() {
                                deviceCardAnim.start();
                                iconContainerAnim.start();
                                detailsColAnim.start();
                            });
                        }
                    }

                    Connections {
                        target: root
                        function onPopupOpenProgressChanged() {
                            if (root && root.popupOpenProgress === 0.0) {
                                deviceCardAnim.stop();
                                iconContainerAnim.stop();
                                detailsColAnim.stop();

                                deviceCard.opacity = 0.0;
                                deviceCard.scale = 0.85;
                                deviceCardTranslate.y = 25;

                                iconContainer.scale = 0.8;
                                iconContainer.opacity = 0.0;
                                iconContainerTrans.x = -20;

                                detailsCol.opacity = 0.0;
                                detailsColTrans.x = 20;
                            }
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
                            id: iconContainer
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredHeight: 80
                            Layout.preferredWidth: 80

                            opacity: 0.0
                            scale: 0.8
                            transform: Translate {
                                id: iconContainerTrans
                                x: -20
                            }

                            SequentialAnimation {
                                id: iconContainerAnim
                                PauseAnimation { duration: 40 + index * 100 + 60 }
                                ParallelAnimation {
                                    NumberAnimation { target: iconContainer; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                    NumberAnimation { target: iconContainer; property: "opacity"; from: 0.0; to: 1.0; duration: 350 }
                                    NumberAnimation { target: iconContainerTrans; property: "x"; from: -20; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                }
                            }

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
                            id: detailsCol
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            opacity: 0.0
                            transform: Translate {
                                id: detailsColTrans
                                x: 20
                            }

                            SequentialAnimation {
                                id: detailsColAnim
                                PauseAnimation { duration: 40 + index * 100 + 120 }
                                ParallelAnimation {
                                    NumberAnimation { target: detailsCol; property: "opacity"; from: 0.0; to: 1.0; duration: 350 }
                                    NumberAnimation { target: detailsColTrans; property: "x"; from: 20; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                }
                            }

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

                            readonly property var devBattery: EarbudsControlService.batteryInfo(modelData)
                            readonly property var devNoise: EarbudsControlService.noiseControl(modelData)
                            readonly property var devCa: EarbudsControlService.conversationAwareness(modelData)

                            // Battery: Breakdown if multiple components, else single progress bar
                            BluetoothBatteryBreakdown {
                                visible: detailsCol.devBattery && detailsCol.devBattery.available && detailsCol.devBattery.components.length > 1
                                batteryInfo: detailsCol.devBattery
                                compact: true
                                showCase: true
                                Layout.alignment: Qt.AlignRight
                                Layout.topMargin: 8
                            }

                            // Single Battery Bar Fallback (StyledProgressBar)
                            RowLayout {
                                visible: (!detailsCol.devBattery || !detailsCol.devBattery.available || detailsCol.devBattery.components.length <= 1) && modelData.batteryAvailable
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

                            // Dynamic Noise Modes (via EarbudsControlService)
                            EarbudsNoiseControlSelector {
                                visible: detailsCol.devNoise && detailsCol.devNoise.available && detailsCol.devNoise.modes.length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 10
                                compact: true
                                modes: detailsCol.devNoise ? detailsCol.devNoise.modes : []
                                currentMode: detailsCol.devNoise ? detailsCol.devNoise.currentMode : "off"
                                onModeRequested: modeKey => {
                                    EarbudsControlService.setNoiseMode(modelData, modeKey);
                                }
                            }

                            // Conversation Awareness (Speak-to-Chat)
                            EarbudsConversationAwareness {
                                visible: detailsCol.devCa && detailsCol.devCa.available
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                compact: true
                                enabled: detailsCol.devCa ? detailsCol.devCa.enabled : false
                                available: detailsCol.devCa ? detailsCol.devCa.available : false
                                title: (detailsCol.devCa && detailsCol.devCa.title) ? detailsCol.devCa.title : Translation.tr("Conversation Awareness")
                                onToggled: en => {
                                    EarbudsControlService.setConversationAwareness(modelData, en);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
