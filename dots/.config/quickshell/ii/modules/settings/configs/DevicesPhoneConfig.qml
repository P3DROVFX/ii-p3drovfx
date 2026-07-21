import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

    ContentSection {
        icon: "smartphone"
        title: Translation.tr("Phone & scrcpy Integration")
        visible: Config.options.policies.phone !== 0

        ContentSubsectionLabel { text: Translation.tr("Display") }

        ConfigSwitch {
            buttonIcon: "view_in_ar"
            text: Translation.tr("Show Mirror / Webcam / Microphone cards")
            checked: Config.options.phone.showPeripheralCards
            onCheckedChanged: {
                Config.options.phone.showPeripheralCards = checked;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Connection Settings") }

        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Use wireless debugging")
            checked: Config.options.phone.scrcpy.useWireless
            onCheckedChanged: {
                Config.options.phone.scrcpy.useWireless = checked;
            }
        }

        ConfigTextField {
            icon: "dns"
            text: Translation.tr("Wireless IP")
            placeholderText: Translation.tr("e.g. 192.168.1.50")
            inputText: Config.options.phone.scrcpy.wirelessIp
            textField.onTextChanged: {
                Config.options.phone.scrcpy.wirelessIp = textField.text;
            }
            enabled: Config.options.phone.scrcpy.useWireless
        }

        ConfigTextField {
            icon: "tag"
            text: Translation.tr("Wireless Port")
            placeholderText: Translation.tr("Default: 5555")
            inputText: Config.options.phone.scrcpy.wirelessPort
            textField.onTextChanged: {
                Config.options.phone.scrcpy.wirelessPort = textField.text;
            }
            enabled: Config.options.phone.scrcpy.useWireless
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Show terminal window")
            checked: Config.options.phone.scrcpy.showTerminal
            onCheckedChanged: {
                Config.options.phone.scrcpy.showTerminal = checked;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("scrcpy Options") }

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Stay awake")
            checked: Config.options.phone.scrcpy.stayAwake
            onCheckedChanged: {
                Config.options.phone.scrcpy.stayAwake = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "phone_android"
            text: Translation.tr("Turn screen off")
            checked: Config.options.phone.scrcpy.turnScreenOff
            onCheckedChanged: {
                Config.options.phone.scrcpy.turnScreenOff = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("No power on device")
            checked: Config.options.phone.scrcpy.noPowerOn
            onCheckedChanged: {
                Config.options.phone.scrcpy.noPowerOn = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "volume_off"
            text: Translation.tr("No audio forwarding")
            checked: Config.options.phone.scrcpy.noAudio
            onCheckedChanged: {
                Config.options.phone.scrcpy.noAudio = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "gesture"
            text: Translation.tr("Show touches")
            checked: Config.options.phone.scrcpy.showTouches
            onCheckedChanged: {
                Config.options.phone.scrcpy.showTouches = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Fullscreen")
            checked: Config.options.phone.scrcpy.fullscreen
            onCheckedChanged: {
                Config.options.phone.scrcpy.fullscreen = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "vertical_align_top"
            text: Translation.tr("Always on top")
            checked: Config.options.phone.scrcpy.alwaysOnTop
            onCheckedChanged: {
                Config.options.phone.scrcpy.alwaysOnTop = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Max FPS")
            value: Config.options.phone.scrcpy.maxFps
            from: 0
            to: 120
            stepSize: 5
            usePercentTooltip: false
            onValueChanged: {
                Config.options.phone.scrcpy.maxFps = value;
            }
        }

        ConfigTextField {
            icon: "wifi_tethering"
            text: Translation.tr("Bitrate")
            placeholderText: Translation.tr("e.g. 8M, 4M")
            inputText: Config.options.phone.scrcpy.bitRate
            textField.onTextChanged: {
                Config.options.phone.scrcpy.bitRate = textField.text;
            }
        }

        ConfigSlider {
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Max Size (0 for unrestricted)")
            value: Config.options.phone.scrcpy.maxSize
            from: 0
            to: 3840
            stepSize: 120
            usePercentTooltip: false
            onValueChanged: {
                Config.options.phone.scrcpy.maxSize = value;
            }
        }

        ConfigSlider {
            buttonIcon: "av_timer"
            text: Translation.tr("Video Buffer (ms)")
            value: Config.options.phone.scrcpy.videoBuffer
            from: 0
            to: 1000
            stepSize: 10
            usePercentTooltip: false
            onValueChanged: {
                Config.options.phone.scrcpy.videoBuffer = value;
            }
        }
    }

    ContentSection {
        id: btImagesSection
        icon: "bluetooth"
        title: Translation.tr("Bluetooth Device Images")

        property string pendingMac: ""
        readonly property string manageScript: Quickshell.shellPath("scripts/services/manage_device_image.sh")

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: btImagesSection.getAvailableDevices().length === 0 && btImagesSection.getDeviceImages().length === 0

            PagePlaceholder {
                anchors.fill: parent
                icon: "bluetooth_disabled"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("No Bluetooth devices")
                description: Translation.tr("Pair a Bluetooth device first to assign custom images.")
            }
        }

        function getDeviceImages() {
            let images = (Config.options.apps && Config.options.bluetoothDeviceImages) ? Config.options.bluetoothDeviceImages : [];
            return Array.from(images);
        }

        function getAvailableDevices() {
            let all = BluetoothStatus.friendlyDeviceList;
            let managed = getDeviceImages();
            let available = [];
            for (let i = 0; i < all.length; i++) {
                let isManaged = false;
                for (let j = 0; j < managed.length; j++) {
                    if (all[i].address === managed[j].mac) {
                        isManaged = true;
                        break;
                    }
                }
                if (!isManaged) {
                    available.push(all[i]);
                }
            }
            return available;
        }

        function getDeviceName(mac) {
            let all = BluetoothStatus.friendlyDeviceList;
            for (let i = 0; i < all.length; i++) {
                if (all[i].address === mac) {
                    return all[i].name || "Unknown Device";
                }
            }
            return "Unknown Device";
        }

        Process {
            id: pickerProc
            stdout: StdioCollector {
                onStreamFinished: {
                    let path = text.trim();
                    if (path.length > 0 && btImagesSection.pendingMac !== "") {
                        copyProc.exec([btImagesSection.manageScript, "copy", path, btImagesSection.pendingMac]);
                    }
                }
            }
        }

        Process {
            id: copyProc
            stdout: StdioCollector {
                onStreamFinished: {
                    let filename = text.trim();
                    if (filename.length > 0) {
                        let list = btImagesSection.getDeviceImages();
                        let idx = -1;
                        for (let i = 0; i < list.length; i++) {
                            if (list[i].mac === btImagesSection.pendingMac) {
                                idx = i;
                                break;
                            }
                        }
                        if (idx !== -1) {
                            list[idx] = { "mac": btImagesSection.pendingMac, "image": filename };
                        } else {
                            list.push({ "mac": btImagesSection.pendingMac, "image": filename });
                        }
                        Config.options.bluetoothDeviceImages = list;
                        btImagesSection.pendingMac = "";
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("1. Select a Device")
            visible: btImagesSection.getAvailableDevices().length > 0
            isFirst: true

            Flow {
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: btImagesSection.getAvailableDevices()
                    delegate: Rectangle {
                        width: 240
                        height: 76
                        radius: Appearance.rounding.normal
                        color: isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
                        border.width: 0

                        readonly property bool isSelected: btImagesSection.pendingMac === (modelData ? modelData.address : "")

                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            Item {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: 42
                                    color: isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest

                                    function rollShape() {
                                        const shapes = ["Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Clover8Leaf", "SoftBurst", "Circle", "Sunny"];
                                        shapeString = shapes[Math.floor(Math.random() * shapes.length)];
                                    }
                                    Component.onCompleted: rollShape()
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "bluetooth"
                                    iconSize: 22
                                    fill: 1
                                    color: isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    text: (modelData && modelData.name) ? modelData.name : "Unknown"
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                StyledText {
                                    text: (modelData && modelData.address) ? modelData.address : ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                    opacity: isSelected ? 0.9 : 0.7
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData) btImagesSection.pendingMac = modelData.address
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("2. Assign Image")
            visible: btImagesSection.pendingMac !== ""

            Rectangle {
                Layout.fillWidth: true
                height: 120
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer3
                border.width: 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Preparing to style: ") + btImagesSection.getDeviceName(btImagesSection.pendingMac)
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                            Layout.alignment: Qt.AlignHCenter
                        }
                        StyledText {
                            text: btImagesSection.pendingMac
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOutline
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignHCenter
                        materialIcon: "add_photo_alternate"
                        mainText: Translation.tr("Upload Artwork")
                        onClicked: pickerProc.exec([btImagesSection.manageScript, "pick"])
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Managed Devices")
            visible: btImagesSection.getDeviceImages().length > 0
            isLast: true

            Flow {
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: btImagesSection.getDeviceImages()
                    delegate: Rectangle {
                        width: 180
                        height: 220
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer3
                        border.width: 0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 110
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.normal
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    source: (modelData && modelData.image) ? "file://" + Directories.shellConfig + "/bluetooth_images/" + modelData.image : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: modelData ? btImagesSection.getDeviceName(modelData.mac) : ""
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSurface
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: modelData ? modelData.mac : ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.numbers
                                    color: Appearance.colors.colOnSurfaceVariant
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }

                                IconToolbarButton {
                                    text: "delete"
                                    onClicked: {
                                        let list = btImagesSection.getDeviceImages();
                                        list.splice(index, 1);
                                        Config.options.bluetoothDeviceImages = list;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "share"
        title: Translation.tr("LocalSend")

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Auto-start")
            checked: Config.options.localsend.autoStart
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.autoStart = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show notifications")
            checked: Config.options.localsend.showNotifications
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.showNotifications = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "branding_watermark"
            text: Translation.tr("Prefer popup over notification")
            checked: Config.options.localsend.preferPopupOverNotification
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.preferPopupOverNotification = checked;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download path")
            text: Config.options.localsend.downloadPath
            wrapMode: TextEdit.Wrap
            enabled: LocalSend.available
            onTextChanged: {
                Config.options.localsend.downloadPath = text;
            }
    }

}
}
