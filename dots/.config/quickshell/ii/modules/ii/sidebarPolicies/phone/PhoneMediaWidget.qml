pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles
import "../../../common/quickToggles/androidStyle"

/**
 * The dashboard's 4x2 media tile, pinned to the phone's media session.
 *
 * The KDE Connect daemon mirrors the phone's playback on the session bus as
 * `org.mpris.MediaPlayer2.kdeconnect` and only publishes it while the phone
 * actually has media — the host uses that as the visibility gate. All metrics
 * mirror AndroidQuickPanel's grid (56px cell, 6px spacing) so the content
 * renders in its full 4x2 "wide" state exactly like in the dashboard.
 */
Item {
    id: root

    required property var player

    // Grid metrics mirrored from AndroidQuickPanel (desktop sidebar defaults).
    readonly property real cellSpacing: 6
    readonly property real baseCellHeight: 56
    readonly property real baseCellWidth: Math.max(1, (width - cellSpacing * 3) / 4)

    implicitHeight: baseCellHeight * 2 + cellSpacing

    opacity: 0.0
    scale: 0.98
    Component.onCompleted: {
        opacity = 1.0
        scale = 1.0
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    // QuickToggleMediaContent derives its morph state from a tile contract;
    // a static one at exactly the 4x2 footprint pins it fully expanded.
    QtObject {
        id: mediaTile
        readonly property real baseCellWidth: root.baseCellWidth
        readonly property real baseCellHeight: root.baseCellHeight
        readonly property real cellSpacing: root.cellSpacing
        property real resizeDirectionX: 0
        property real resizeDirectionY: 0
        function scaled(value) {
            return QuickToggleMetrics.scaled(root.baseCellHeight, value);
        }
    }

    QuickToggleMediaContent {
        anchors.fill: parent
        tile: mediaTile
        playerOverride: root.player
    }
}
