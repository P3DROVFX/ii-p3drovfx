pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

/**
 * Segments utility buttons.
 *
 * The `default` style is a row of loose circles and the `expressive` one is a
 * filled pill with icons inside it. This is Material 3 Expressive's *connected
 * button group*: the buttons are joined shoulder to shoulder into one track, and
 * the corner radii carry every state.
 *
 *   at rest   square inner corners — the buttons read as one strip
 *   hover     the corners of that one segment lift; it starts to detach
 *   active    fully round and filled with the accent: it has popped out of the
 *             track, which is what "this toggle is on" looks like here
 *
 * These are *actions*, not statuses, so the state that matters is which one you
 * are about to press — and that is the one thing a filled pill full of icons
 * cannot say.
 *
 * Which buttons exist and what they do lives in `UtilButtonActions`.
 */
Item {
    id: root

    property bool vertical: BarPlacement.vertical

    readonly property real thickness: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8
    // Wide enough to count the buttons, narrow enough that the strip still
    // reads as one object.
    readonly property real seam: 2

    UtilButtonActions {
        id: actionSet
    }

    readonly property var actions: actionSet.actions

    visible: root.actions.length > 0
    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : strip.implicitWidth
    implicitHeight: root.vertical ? strip.implicitHeight : Appearance.sizes.baseBarHeight

    Grid {
        id: strip
        anchors.centerIn: parent
        columns: root.vertical ? 1 : root.actions.length
        rows: root.vertical ? root.actions.length : 1
        spacing: root.seam

        Repeater {
            model: root.actions

            delegate: UtilSegment {
                id: segment

                required property int index
                required property string modelData

                vertical: root.vertical
                thickness: root.thickness
                first: segment.index === 0
                last: segment.index === root.actions.length - 1
                iconText: actionSet.iconFor(segment.modelData)
                active: actionSet.activeFor(segment.modelData)
                altAction: actionSet.altFor(segment.modelData)

                onTriggered: actionSet.invoke(segment.modelData)

                StyledToolTip {
                    text: actionSet.tooltipFor(segment.modelData)
                    requireOverlay: false
                }
            }
        }
    }
}
