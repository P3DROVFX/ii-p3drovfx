pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets

AndroidQuickToggleButton {
    id: root

    toggleModel: NetworkToggle {}
    backgroundIcon: Network.ethernet ? "" : "wifi"
    expandedIconShape: "Cookie7Sided"
    centerExpandedIcon: true
    expandedStatusTransparency: 0.4

    // Tall sizes (1x2, 2x2, 4x2, 2x4 ...) get the expressive Wi-Fi / network face;
    // 1-row sizes (1x1, 2x1) keep the generic icon + label morph.
    wide2x2OverrideComponent: tallFace
    tall1x2OverrideComponent: tallFace

    Component {
        id: tallFace
        WifiEndpointPanel {
            anchors.fill: parent
            anchors.margins: root.scaled(12)
            tile: root
        }
    }
}
