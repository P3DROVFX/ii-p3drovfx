pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * The last few seconds of traffic as bars.
 *
 * With both directions the plot is mirrored around its centre line — download
 * grows up, upload grows down, upload in a lighter tint — so a burst in one
 * direction never hides the other. With one direction the bars rise from the
 * bottom edge. Heights are square-rooted, so a trickle is still visible next to
 * a burst, and the scale floors at 64 KB/s so an idle line does not stretch its
 * own noise to full height.
 */
Item {
    id: root

    property var net
    property color barColor: Appearance.colors.colOnLayer1

    property real slotWidth: 5
    property real barWidth: 3
    readonly property int slots: Math.max(4, Math.floor(root.width / root.slotWidth))
    readonly property real half: root.height / 2
    readonly property real minBar: 2

    function windowOf(history: var): var {
        const start = history.length - root.slots;
        const out = [];
        for (let i = 0; i < root.slots; i++)
            out.push(start + i >= 0 ? history[start + i] : 0);
        return out;
    }

    readonly property var downWindow: root.windowOf(root.net.downHistory)
    readonly property var upWindow: root.windowOf(root.net.upHistory)
    readonly property real scale: Math.max(65536,
        root.net.showDown ? Math.max.apply(null, root.downWindow) : 0,
        root.net.showUp ? Math.max.apply(null, root.upWindow) : 0)

    Repeater {
        model: root.slots

        delegate: Item {
            id: slot

            required property int index

            x: slot.index * root.slotWidth
            width: root.slotWidth
            height: root.height

            Rectangle {
                id: downBar

                readonly property real value: root.downWindow[slot.index] ?? 0

                visible: root.net.showDown
                x: (slot.width - width) / 2
                y: root.net.showBoth ? root.half - height : root.height - height
                width: root.barWidth
                height: Math.max(root.minBar, Math.sqrt(downBar.value / root.scale) * (root.net.showBoth ? root.half : root.height))
                radius: width / 2
                color: root.barColor
                opacity: downBar.value > 0 ? 1 : 0.35

                Behavior on height {
                    NumberAnimation {
                        duration: Math.round(280 * Appearance.animMultiplier)
                        easing.type: Easing.OutQuint
                    }
                }
            }

            Rectangle {
                id: upBar

                readonly property real value: root.upWindow[slot.index] ?? 0

                visible: root.net.showUp
                x: (slot.width - width) / 2
                y: root.net.showBoth ? root.half : root.height - height
                width: root.barWidth
                height: Math.max(root.minBar, Math.sqrt(upBar.value / root.scale) * (root.net.showBoth ? root.half : root.height))
                radius: width / 2
                color: root.net.showBoth ? ColorUtils.transparentize(root.barColor, 0.45) : root.barColor
                opacity: upBar.value > 0 ? 1 : 0.35

                Behavior on height {
                    NumberAnimation {
                        duration: Math.round(280 * Appearance.animMultiplier)
                        easing.type: Easing.OutQuint
                    }
                }
            }
        }
    }
}
