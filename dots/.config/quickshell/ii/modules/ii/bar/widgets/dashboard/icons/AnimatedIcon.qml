pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Base for the dashboard's animated icons.
 *
 * Every icon is drawn in a 24×24 design grid — the same grid Material Symbols
 * use — and scaled from there, so the geometry inside each icon can be written
 * in whole numbers and stays comparable between icons.
 *
 * The rule these icons follow: **the primary animation is always a part of the
 * glyph moving.** An arc travels outward, a wing rotates, a clapper swings, a
 * slash draws itself endpoint-first. Opacity and scale exist only to support a
 * movement that is already happening; nothing here animates by pulsing alone.
 */
Item {
    id: root

    property real iconSize: 22
    property color color: "white"
    /** Which cue channel this icon answers to. Empty = not driven by the bus. */
    property string cueChannel: ""
    /** Stroke weight in design-grid units, matched to Material Symbols' 200wt. */
    property real stroke: 2.1

    readonly property real unit: root.iconSize / 24

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    default property alias designContent: grid.data

    // Overridden by every icon. Kept here so the bus can call it blindly.
    function play(cue: string): void {}

    Item {
        id: grid
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.unit
        antialiasing: true
    }

    Connections {
        target: DashboardIconCues
        function onCue(channel, name) {
            if (root.cueChannel.length > 0 && channel === root.cueChannel)
                root.play(name);
        }
    }
}
