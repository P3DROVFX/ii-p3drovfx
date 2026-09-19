import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import qs.services
import "./widgets"

DockContextMenuBase {
    id: root

    readonly property string deviceId: KdeConnectService.activeDeviceId
    readonly property bool hasDevice: root.anchorItem?.hasDevice ?? false
    readonly property bool isRunning: root.anchorItem?.isRunning ?? false

    headerText: {
        const name = root.anchorItem?.deviceName ?? "";
        const charge = root.anchorItem?.deviceCharge ?? -1;
        return charge >= 0 ? name + " · " + String(charge) + "%" : name;
    }
    headerIcon: Component {
        Item {
            implicitWidth: 22
            implicitHeight: 22

            Image {
                anchors.fill: parent
                source: root.anchorItem?.deviceImageSource ?? ""
                sourceSize: Qt.size(44, 44)
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }
    }

    contentComponent: ColumnLayout {
        spacing: 0

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: root.isRunning ? "open_in_new" : "cast"
            labelText: root.isRunning ? qsTr("Focus mirror") : qsTr("Open mirror")
            enabled: root.hasDevice
            onTriggered: {
                root.anchorItem?.openMirror();
                root.close();
            }
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "stop_circle"
            labelText: qsTr("Stop mirror")
            visible: root.isRunning
            onTriggered: {
                PhoneScrcpyService.stopMirror();
                if (KdeConnectService.scrcpyRunning)
                    KdeConnectService.killScrcpy();
                root.close();
            }
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "upload_file"
            labelText: qsTr("Send file…")
            enabled: root.hasDevice
            onTriggered: {
                KdeConnectService.sendFile(root.deviceId);
                root.close();
            }
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "content_paste"
            labelText: qsTr("Send clipboard")
            enabled: root.hasDevice
            onTriggered: {
                KdeConnectService.sendClipboard(root.deviceId);
                root.close();
            }
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "folder_open"
            labelText: qsTr("Browse files")
            enabled: root.hasDevice
            onTriggered: {
                KdeConnectService.browseFiles(root.deviceId);
                root.close();
            }
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "ring_volume"
            labelText: qsTr("Ring phone")
            enabled: root.hasDevice
            onTriggered: {
                KdeConnectService.findMyPhone(root.deviceId);
                root.close();
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "do_not_disturb_on"
            labelText: qsTr("Remove from dock")
            isDestructive: true
            onTriggered: {
                root.close();
                Config.options.dock.showPhoneButton = false;
            }
        }
    }
}
