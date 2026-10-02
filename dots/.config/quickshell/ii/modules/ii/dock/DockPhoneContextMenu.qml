import QtQuick
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

    headerText: root.anchorItem?.deviceName ?? ""
    headerSubtitle: {
        const charge = root.anchorItem?.deviceCharge ?? -1;
        return charge >= 0 ? Translation.tr("Battery %1%").arg(charge) : "";
    }
    headerIcon: Component {
        Image {
            source: root.anchorItem?.deviceImageSource ?? ""
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    menuGroups: root.menuOpen ? [
        [
            {
                id: "mirror",
                icon: root.isRunning ? "open_in_new" : "cast",
                text: root.isRunning ? Translation.tr("Focus mirror") : Translation.tr("Open mirror"),
                enabled: root.hasDevice
            },
            { id: "stop", icon: "stop_circle", text: Translation.tr("Stop mirror"), visible: root.isRunning }
        ],
        [
            { id: "sendFile", icon: "upload_file", text: Translation.tr("Send file…"), enabled: root.hasDevice },
            { id: "sendClipboard", icon: "content_paste", text: Translation.tr("Send clipboard"), enabled: root.hasDevice },
            { id: "browse", icon: "folder_open", text: Translation.tr("Browse files"), enabled: root.hasDevice },
            { id: "ring", icon: "ring_volume", text: Translation.tr("Ring phone"), enabled: root.hasDevice }
        ],
        [
            { id: "remove", icon: "do_not_disturb_on", text: Translation.tr("Remove from dock"), destructive: true }
        ]
    ] : []

    onActionTriggered: actionId => {
        switch (actionId) {
        case "mirror": root.anchorItem?.openMirror(); break;
        case "stop": PhoneScrcpyService.stopMirroring(); break;
        case "sendFile": KdeConnectService.sendFile(root.deviceId); break;
        case "sendClipboard": KdeConnectService.sendClipboard(root.deviceId); break;
        case "browse": KdeConnectService.browseFiles(root.deviceId); break;
        case "ring": KdeConnectService.findMyPhone(root.deviceId); break;
        case "remove":
            root.close();
            Config.options.dock.showPhoneButton = false;
            return;
        }
        root.close();
    }
}
