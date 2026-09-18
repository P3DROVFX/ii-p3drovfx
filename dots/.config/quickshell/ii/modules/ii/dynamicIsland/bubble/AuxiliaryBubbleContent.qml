pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.media

/**
 * What the auxiliary bubble shows: a glance at an activity, never the activity itself.
 *
 * Media is the bar's ring widget in its vertical form - the cover cut to a scalloped
 * shape inside a rim that sweeps with the track position - scaled to the bubble.
 * Workspaces is only the active-workspace indicator. Hovering the bubble opens the
 * activity in the island itself, so nothing here is interactive.
 */
Item {
    id: root

    /** "media" or "workspaces". */
    required property string activityId
    /** The bubble's settled diameter; the contents are sized for it. */
    required property real diameter

    width: root.diameter
    height: root.diameter

    Loader {
        anchors.centerIn: parent
        active: root.activityId === "media"
        visible: active
        sourceComponent: Item {
            id: mediaGlance
            // The ring is the bubble's own inset circle, with a little air around it.
            readonly property real ringSize: root.diameter - 6
            width: ring.width
            height: ring.height

            RingMedia {
                id: ring
                anchors.centerIn: parent
                vertical: true
                // Outside the bar: must not move the media popup's anchor or open it.
                previewMode: true
                // The vertical ring is drawn for a bar column; scale it to the bubble.
                // Its item is centred on the ring, so scaling about the centre keeps it
                // centred.
                scale: ring.ringSize > 0 ? mediaGlance.ringSize / ring.ringSize : 1
            }
        }
    }

    Loader {
        anchors.centerIn: parent
        active: root.activityId === "workspaces"
        visible: active
        sourceComponent: Rectangle {
            readonly property int workspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
            readonly property var numberMap: Config.options.bar.workspaces.numberMap ?? []

            width: root.diameter - 8
            height: width
            radius: width / 2
            color: Appearance.colors.colPrimary

            StyledText {
                anchors.centerIn: parent
                text: String(parent.numberMap[parent.workspaceId - 1] || parent.workspaceId)
                font.pixelSize: Math.max(10, Math.round(parent.height * 0.5))
                font.weight: Font.Bold
                font.family: Appearance.font.family.numbers
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
