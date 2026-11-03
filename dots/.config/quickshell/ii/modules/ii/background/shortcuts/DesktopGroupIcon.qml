import QtQuick
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects as GE
import qs.modules.common
import qs.services

/**
 * One member's icon inside an app group, clipped to `mask` so a full-bleed
 * square icon keeps its corners inside a round group.
 *
 * `mask` is one of none | rounded | squircle | circle. An icon that already
 * has its own shape loses nothing: the mask only cuts the corners.
 */
Item {
    id: root
    property var app: null
    property string mask: "none"

    IconImage {
        id: icon
        anchors.fill: parent
        visible: root.app !== null
        mipmap: true
        source: root.app ? DesktopShortcuts.iconSource(root.app.icon, "image-missing") : ""
        // Redrawn when the icon theme is recoloured in place (see the desktop tile).
        backer.cache: false
        backer.sourceSize: Qt.size(icon.actualSize + TaskbarApps.iconThemeRevision,
            icon.actualSize + TaskbarApps.iconThemeRevision)
        layer.enabled: root.mask !== "none" && root.app !== null
        layer.smooth: true
        layer.effect: GE.OpacityMask {
            maskSource: maskShape
        }
    }
    Rectangle {
        id: maskShape
        anchors.fill: parent
        visible: false
        antialiasing: true
        radius: root.mask === "circle" ? width / 2
            : root.mask === "squircle" ? width * 0.3 : width * 0.22
    }
}
