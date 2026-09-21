import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import QtQuick

QuickToggleButton {
    id: root

    readonly property bool phoneEnabled: Config.ready && Config.options.policies.phone !== 0
    readonly property bool mirrorRunning: PhoneScrcpyService.mirrorRunning
    readonly property bool mirrorLaunching: PhoneScrcpyService.mirrorLaunching

    interactive: root.phoneEnabled && PhoneScrcpyService.available
    toggled: root.mirrorRunning || root.mirrorLaunching
    buttonIcon: root.toggled ? "screen_share" : "smartphone"
    onClicked: {
        if (root.mirrorRunning) {
            PhoneScrcpyService.stopMirror();
        } else {
            PhoneScrcpyService.launchMirror();
        }
    }
    StyledToolTip {
        text: Translation.tr("Mirror phone screen to desktop via scrcpy | Right-click for phone settings")
    }
}
