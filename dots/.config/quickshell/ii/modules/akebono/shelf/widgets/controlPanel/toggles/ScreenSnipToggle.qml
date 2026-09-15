import QtQuick
import Quickshell
import qs.services
import qs.modules.common.widgets

AkToggle {
    id: root
    icon: "screenshot_region"
    onClicked: {
        root.panel?.closeRequested();
        snipDelay.start();
    }
    Timer {
        id: snipDelay
        interval: 300
        onTriggered: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"])
    }
    StyledToolTip {
        text: Translation.tr("Screenshot region")
    }
}
