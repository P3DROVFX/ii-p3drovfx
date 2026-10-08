pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "WorkspacesCatalog.js" as Catalog

/**
 * The compactor acted out: a row with gaps, then the occupied workspaces slide
 * left into 1..N and renumber, the empty outlines fading out, and back again.
 */
Item {
    id: root

    property bool running: true

    readonly property real cell: 36
    readonly property real gap: 8
    readonly property real cellRadius: Appearance.rounding.normal
    readonly property int holdBefore: 1400
    readonly property int holdAfter: 1800
    readonly property color colTile: Appearance.colors.colPrimaryContainer
    readonly property color colOnTile: Appearance.colors.colOnPrimaryContainer
    readonly property color colGap: Appearance.colors.colOutline

    readonly property var occupied: {
        const out = [];
        for (let i = 0; i < Catalog.COMPACT_BEFORE.length; i++)
            if (Catalog.COMPACT_BEFORE[i])
                out.push(i);
        return out;
    }

    property bool compacted: false

    implicitWidth: Catalog.COMPACT_BEFORE.length * (root.cell + root.gap) - root.gap
    implicitHeight: root.cell

    Timer {
        running: root.running && root.visible
        repeat: true
        interval: root.compacted ? root.holdAfter : root.holdBefore
        onTriggered: root.compacted = !root.compacted
    }

    Repeater {
        model: Catalog.COMPACT_BEFORE.length
        delegate: Rectangle {
            required property int index
            x: index * (root.cell + root.gap)
            width: root.cell
            height: root.cell
            radius: root.cellRadius
            color: "transparent"
            opacity: Catalog.COMPACT_BEFORE[index] ? 0 : (root.compacted ? 0 : 1)
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            DashedBorder {
                anchors.fill: parent
                color: ColorUtils.applyAlpha(root.colGap, 0.7)
                borderWidth: 1.5
                dashLength: 4
                gapLength: 3
                radius: root.cellRadius
            }
        }
    }

    Repeater {
        model: root.occupied
        delegate: Rectangle {
            id: tile
            required property int modelData
            required property int index
            readonly property int place: root.compacted ? tile.index : tile.modelData
            x: tile.place * (root.cell + root.gap)
            width: root.cell
            height: root.cell
            radius: root.compacted ? root.cell / 2 : root.cellRadius
            color: root.colTile
            Behavior on x {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on radius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            StyledText {
                anchors.centerIn: parent
                text: tile.place + 1
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: root.colOnTile
            }
        }
    }
}
