import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Bluetooth Device Images")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
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
}
