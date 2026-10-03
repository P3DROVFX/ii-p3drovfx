import qs
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

AndroidQuickToggleButton {
    id: root

    toggleModel: AudioToggle {}

    // Tall sizes (1x2, 2x2, 4x2, 2x4 ...) get the expressive volume face; 1-row sizes keep
    // the generic icon + label morph.
    wide2x2OverrideComponent: tallFace
    tall1x2OverrideComponent: tallFace

    Component {
        id: tallFace
        AudioEndpointPanel {
            anchors.fill: parent
            anchors.margins: root.scaled(12)
            tile: root
            isInput: false
        }
    }
}
