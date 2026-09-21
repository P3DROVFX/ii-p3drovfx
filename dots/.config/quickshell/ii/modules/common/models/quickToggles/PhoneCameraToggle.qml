import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

/**
 * The phone's camera as this computer's webcam. Right-click opens its page.
 *
 * State comes from the flag the service publishes, so a tile sitting in the tray does
 * not construct the service; only a tap does.
 */
QuickToggleModel {
    id: root

    readonly property bool phoneEnabled: Config.ready && Config.options.policies.phone !== 0

    name: Translation.tr("Phone webcam")
    available: root.phoneEnabled
    toggled: root.phoneEnabled && GlobalStates.phoneCameraRunning
    icon: root.toggled ? "videocam" : "videocam_off"
    statusText: !root.phoneEnabled ? Translation.tr("Phone integration off")
        : (root.toggled ? Translation.tr("Streaming") : Translation.tr("Off"))
    tooltipText: Translation.tr("Use the phone's camera as a webcam | Right-click for its settings")

    mainAction: () => {
        if (root.phoneEnabled)
            PhoneCameraService.toggleCamera();
    }
    altAction: () => {
        GlobalStates.phoneRequestSubPage = Qt.resolvedUrl(
            Quickshell.shellPath("modules/ii/sidebarPolicies/phone/PhoneWebcamPage.qml"));
        GlobalStates.policiesRequestTabIcon = "smartphone";
        GlobalStates.openLeftSidebar();
    }
}
