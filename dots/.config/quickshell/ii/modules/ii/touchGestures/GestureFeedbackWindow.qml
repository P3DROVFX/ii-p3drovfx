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
        id: feedbackLoader
        anchors.fill: parent
        active: (Config.options && Config.options.interactions && Config.options.interactions.touchGestures && Config.options.interactions.touchGestures.visualFeedback !== undefined)
            ? Config.options.interactions.touchGestures.visualFeedback
            : true
        sourceComponent: GestureFeedbackContent {
            screen: window.screen
        }
    }

    // The compositor pays fullscreen blur for every mapped Overlay surface,
    // gesturing or not. This one covers 1920x1080 per monitor and draws
    // nothing at rest: map it only while the content reports something on
    // screen (live gesture, its fade-out, or calibration). The surface never
    // takes keyboard focus, so unmapping it is safe (see "Superfície Efêmera
    // Não Pode Morrer com Foco de Teclado").
    visible: feedbackLoader.item ? feedbackLoader.item.overlayVisible : false
}
