import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

/**
 * Dedicated Quick Toggle for Phone Screen Mirroring via scrcpy.
 */
QuickToggleModel {
    id: root

    readonly property bool phoneEnabled: Config.ready && Config.options.policies.phone !== 0
    readonly property bool mirrorRunning: PhoneScrcpyService.mirrorRunning
    readonly property bool mirrorLaunching: PhoneScrcpyService.mirrorLaunching

    name: Translation.tr("Phone mirror")
    available: root.phoneEnabled && PhoneScrcpyService.available
    toggled: root.mirrorRunning || root.mirrorLaunching
    icon: root.toggled ? "screen_share" : "smartphone"
    statusText: !root.phoneEnabled ? Translation.tr("Phone integration off")
        : !PhoneScrcpyService.available ? Translation.tr("scrcpy unavailable")
        : root.mirrorLaunching ? Translation.tr("Launching…")
        : root.mirrorRunning ? (Config.options?.phone?.scrcpy?.appMode?.flexDisplay ? Translation.tr("Flex Display") : Translation.tr("Mirroring"))
        : Translation.tr("Off")
    tooltipText: Translation.tr("Mirror phone screen to desktop via scrcpy | Right-click for phone settings")

    mainAction: () => {
        if (!root.phoneEnabled || !PhoneScrcpyService.available)
            return;
        if (root.mirrorRunning) {
            PhoneScrcpyService.stopMirror();
        } else {
            PhoneScrcpyService.launchMirror();
        }
    }
    altAction: () => {
        GlobalStates.phoneRequestSubPage = Qt.resolvedUrl(
            Quickshell.shellPath("modules/ii/sidebarPolicies/phone/PhoneScrcpyPage.qml"));
        GlobalStates.policiesRequestTabIcon = "smartphone";
        GlobalStates.openLeftSidebar();
    }
}
