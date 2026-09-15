import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common

PanelWindow {
    id: window

    property var screen: null

    WlrLayershell.namespace: "quickshell:gestureFeedback"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        item: null
    }

    Loader {
        anchors.fill: parent
        active: (Config.options && Config.options.interactions && Config.options.interactions.touchGestures && Config.options.interactions.touchGestures.visualFeedback !== undefined)
            ? Config.options.interactions.touchGestures.visualFeedback
            : true
        sourceComponent: GestureFeedbackContent {
            screen: window.screen
        }
    }
}
