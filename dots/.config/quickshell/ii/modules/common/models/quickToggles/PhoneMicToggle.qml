import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

/**
 * The phone's microphone as an input on this computer. Right-click opens its page.
 *
 * State comes from the flag the service publishes, so a tile sitting in the tray does
 * not construct the service; only a tap, or a stream already running, does.
 */
QuickToggleModel {
    id: root

    readonly property bool phoneEnabled: Config.ready && Config.options.policies.phone !== 0
    readonly property bool streaming: root.phoneEnabled && GlobalStates.phoneMicRunning
    readonly property bool muted: root.streaming && PhoneMicService.muted

    name: Translation.tr("Phone mic")
    available: root.phoneEnabled
    toggled: root.streaming
    icon: root.streaming && !root.muted ? "mic" : "mic_off"
    statusText: !root.phoneEnabled ? Translation.tr("Phone integration off")
        : root.muted ? Translation.tr("Muted")
        : (root.streaming ? Translation.tr("Streaming") : Translation.tr("Off"))
    tooltipText: Translation.tr("Use the phone's microphone as an input | Right-click for its settings")

    mainAction: () => {
        if (root.phoneEnabled)
            PhoneMicService.toggleMic();
    }
    altAction: () => {
        GlobalStates.phoneRequestSubPage = Qt.resolvedUrl(
            Quickshell.shellPath("modules/ii/sidebarPolicies/phone/PhoneMicPage.qml"));
        GlobalStates.policiesRequestTabIcon = "smartphone";
        GlobalStates.openLeftSidebar();
    }
}
