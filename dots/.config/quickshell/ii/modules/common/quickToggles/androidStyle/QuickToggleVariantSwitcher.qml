pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog

/**
 * The arrows that cycle a tray tile between the designs of its variant group.
 *
 * It lies over the tile, placed from the same packed geometry, and belongs to the
 * tray only: a tile on the grid is a plain type and never changes design. It takes no
 * pointer input itself - a hover handler only - so dragging and the add badge still
 * reach the tile underneath; just the two arrow buttons take clicks.
 *
 * Arrows show while the pointer is over the tile. Each is a filled circle in the
 * secondary container colour, so it reads against any tile, and large enough to hit
 * without aiming. A row of dots under the tile says which design is showing.
 */
Item {
    id: root

    /** The positioned tray record: { type, sizeW, sizeH, layoutX, layoutY, pixelWidth? }. */
    required property var item
    required property var panel
    required property real cellWidth
    required property real cellHeight
    required property real cellSpacing

    readonly property string group: QuickToggleCatalog.variantGroup(root.item.type)
    readonly property var variants: root.panel ? root.panel.trayVariants(root.group) : []
    readonly property int currentIndex: root.variants.indexOf(root.item.type)

    x: Number(root.item.layoutX ?? 0)
    y: Number(root.item.layoutY ?? 0)
    width: root.item.pixelWidth !== undefined ? Number(root.item.pixelWidth)
        : root.item.sizeW * root.cellWidth + Math.max(0, root.item.sizeW - 1) * root.cellSpacing
    height: root.item.sizeH * root.cellHeight + Math.max(0, root.item.sizeH - 1) * root.cellSpacing
    z: 30

    HoverHandler {
        id: hover
    }

    readonly property bool showing: hover.hovered || previous.hovered || next.hovered

    component Arrow: RippleButton {
        id: arrow
        required property string symbol
        readonly property real size: Math.min(32, Math.max(24, root.height * 0.42))
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: arrow.size
        implicitHeight: arrow.size
        buttonRadius: arrow.size / 2
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        opacity: root.showing ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(arrow)
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: arrow.symbol
            iconSize: Math.round(arrow.size * 0.62)
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    Arrow {
        id: previous
        anchors.left: parent.left
        anchors.leftMargin: 4
        symbol: "chevron_left"
        onClicked: root.panel.cycleTrayVariant(root.group, -1)
    }

    Arrow {
        id: next
        anchors.right: parent.right
        anchors.rightMargin: 4
        symbol: "chevron_right"
        onClicked: root.panel.cycleTrayVariant(root.group, 1)
    }

    // Which design is showing, of how many.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 4
        opacity: root.showing ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Repeater {
            model: root.variants.length
            delegate: Rectangle {
                required property int index
                width: index === root.currentIndex ? 12 : 6
                height: 6
                radius: 3
                color: index === root.currentIndex ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
            }
        }
    }
}
