pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.overlay
import "../../../common/plugins/bundled/discordVoice" as DiscordPackage

StyledOverlayWidget {
    id: root
    title: "Discord Voice"
    showCenterButton: true
    titleIconComponent: Component {
        DiscordPackage.DiscordGlyph {
            implicitSize: 20
            iconSize: 12
        }
    }
    // Widget.qml owns the tint opacity; do not stack the editor frame's opaque
    // fill behind it while Super+G is open.
    editorBackgroundOpacity: 0
    minimumWidth: overlayContent.implicitWidth
    minimumHeight: overlayContent.implicitHeight

    contentItem: DiscordPackage.Widget {
        id: overlayContent
        anchors.fill: parent
        namesOnLeft: root.parent
            ? root.x + root.width / 2 >= root.parent.width / 2
            : false
    }
}
