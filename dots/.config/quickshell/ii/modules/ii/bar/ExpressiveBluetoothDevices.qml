import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

MouseArea {
    id: root
    property bool vertical: false
    property bool isMaterial: true // Forced expressive

    readonly property var activeDevices: BluetoothStatus.connectedDevices
    property int deviceIndex: 0
    readonly property var primaryDevice: activeDevices.length > 0 ? activeDevices[deviceIndex % activeDevices.length] : null
    readonly property bool hasDevices: activeDevices.length > 0
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : layout.implicitWidth + 8

    implicitHeight: vertical ? layoutVert.implicitHeight + 8 : Appearance.sizes.barHeight
    width: implicitWidth
    height: implicitHeight
    visible: hasDevices
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor

    Connections {
        target: BluetoothStatus
        function onConnectedDevicesChanged() {
            if (typeof rootItem !== "undefined")
                rootItem.toggleVisible(BluetoothStatus.connectedDevices.length > 0)
        }
    }

    Component.onCompleted: {
        if (typeof rootItem !== "undefined")
            rootItem.toggleVisible(hasDevices)
    }

    onClicked: {
        if (activeDevices.length > 1) {
            deviceIndex = (deviceIndex + 1) % activeDevices.length
        }
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 4
        visible: !root.vertical

        MaterialShape {
            shapeString: "Cookie7Sided"
            color: Appearance.colors.colPrimary
            implicitSize: Appearance.sizes.barHeight - 8
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.normal
                text: root.hasDevices ? Icons.getBluetoothDeviceMaterialSymbol(root.primaryDevice.icon) : "bluetooth"
                color: Appearance.colors.colOnPrimary
            }
        }

        Rectangle {
            color: Appearance.colors.colSecondaryContainer
            radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
            implicitWidth: content.implicitWidth + 24
            implicitHeight: Appearance.sizes.barHeight - 8
            
            RowLayout {
                id: content
                anchors.centerIn: parent
                spacing: 10
                
                StyledText {
                    text: root.primaryDevice ? root.primaryDevice.name : ""
                    font.pixelSize: 10
                    font.weight: Font.Black
                    color: Appearance.colors.colPrimary
                    Layout.maximumWidth: 60
                    elide: Text.ElideRight
                }

                // Progress Bar (Battery)
                StyledProgressBar {
                    id: batteryContainer
                    visible: root.primaryDevice ? root.primaryDevice.batteryAvailable : false
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 8
                    Layout.preferredWidth: 42
                    valueBarWidth: 42
                    valueBarHeight: 8
                    from: 0
                    to: 1
                    value: root.primaryDevice?.battery ?? 0
                    highlightColor: {
                        if (!root.primaryDevice) return Appearance.colors.colPrimary;
                        if (root.primaryDevice.battery <= 0.15) return Appearance.m3colors.m3error;
                        return Appearance.colors.colPrimary;
                    }
                    trackColor: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2)
                }
            }
        }
    }

    ColumnLayout {
        id: layoutVert
        anchors.centerIn: parent
        spacing: 4
        visible: root.vertical

        MaterialShape {
            Layout.alignment: Qt.AlignHCenter
            shapeString: "Cookie7Sided"
            color: Appearance.colors.colPrimary
            implicitSize: Appearance.sizes.verticalBarWidth - 8
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.normal
                text: root.hasDevices ? Icons.getBluetoothDeviceMaterialSymbol(root.primaryDevice.icon) : "bluetooth"
                color: Appearance.colors.colOnPrimary
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            color: Appearance.colors.colSecondaryContainer
            radius: Appearance.rounding.small
            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            implicitHeight: contentVert.implicitHeight + 14
            
            ColumnLayout {
                id: contentVert
                anchors.centerIn: parent
                spacing: 6
                
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.primaryDevice ? root.primaryDevice.name.slice(0, 2).toUpperCase() : ""
                    font.pixelSize: 9
                    font.weight: Font.Black
                    color: Appearance.colors.colPrimary
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.primaryDevice && root.primaryDevice.batteryAvailable
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 32
                    radius: Appearance.rounding.full
                    color: Appearance.m3colors.m3secondaryContainer
                    
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * (root.primaryDevice ? root.primaryDevice.battery : 0)
                        radius: Appearance.rounding.full
                        color: {
                            if (!root.primaryDevice) return Appearance.colors.colPrimary;
                            if (root.primaryDevice.battery <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colPrimary;
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: popupLoader
        source: Config.options.bar.bluetoothDevicesLayout === "expressive" ? "ExpressiveBluetoothDevicesPopup.qml" : "BluetoothDevicesPopup.qml"
        onLoaded: {
            item.hoverTarget = root;
        }
    }
}
