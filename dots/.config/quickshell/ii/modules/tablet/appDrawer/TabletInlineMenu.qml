pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.menu

/**
 * A menu drawn inside the surface that opened it, growing out of the item it belongs to.
 *
 * Deliberately not a PopupWindow. The drawer is an Overlay layer that holds exclusive
 * keyboard focus while it is open, and stacking a second surface with its own focus grab on
 * top of that is a fight over input for something Android draws in the launcher itself. An
 * in-surface menu also inherits the drawer's own dismissal, so there is one way out of the
 * drawer rather than two that can disagree.
 *
 * Serves both the sort control and the long-press app menu, which is why the actions are a
 * plain list of `{ symbol, label, checked, destructive, trigger }` rather than fixed rows.
 * The card itself is TabletMenuCard, shared with the dock's two menus so the same gesture on
 * two icons a centimetre apart cannot produce two different-looking menus.
 */
Item {
    id: root

    /// One entry per row: `{ symbol, label, checked, destructive, trigger }`.
    property var actions: []
    property string headerText: ""
    property string headerIconPath: ""
    property string headerSymbol: ""
    property bool opened: false

    /// Where the menu grows from, in this item's coordinates.
    property real originX: 0
    property real originY: 0

    readonly property real edgeMargin: Math.max(12, Appearance.sizes.elevationMargin)
    readonly property real cardPadding: Math.max(12, Appearance.sizes.elevationMargin)
    readonly property real rowSpacing: Math.max(4, Math.round(Appearance.sizes.elevationMargin * 0.45))
    readonly property real rowHeight: Math.max(Appearance.sizes.minimumTouchTarget,
        Math.min(72, Math.round(root.height * 0.072)))
    readonly property real menuWidth: Math.max(320, Math.min(420, Math.round(root.width * 0.27)))
    readonly property real headerHeight: root.headerText.length > 0 ? root.rowHeight : 0
    readonly property real maximumMenuHeight: Math.max(root.rowHeight * 2,
        root.height - root.edgeMargin * 2)

    visible: root.opened || card.opacity > 0.01
    enabled: root.opened

    function openAt(x, y, actionList, header, iconPath, symbol) {
        root.actions = actionList ?? [];
        root.headerText = header ?? "";
        root.headerIconPath = iconPath ?? "";
        root.headerSymbol = symbol ?? "";
        root.originX = x;
        root.originY = y;
        root.opened = true;
    }

    function close() {
        root.opened = false;
    }

    // Dismissal is a tap anywhere else, which is the only gesture available without a
    // second surface to grab focus with.
    MouseArea {
        anchors.fill: parent
        enabled: root.opened
        onClicked: root.close()
    }

    TabletMenuCard {
        id: card

        // Clamped so a tile near an edge still gets a whole menu rather than a clipped one.
        x: Math.max(root.edgeMargin,
            Math.min(root.width - card.width - root.edgeMargin, root.originX - card.width / 2))
        y: Math.max(root.edgeMargin,
            Math.min(root.height - card.height - root.edgeMargin, root.originY))

        actions: root.actions
        headerText: root.headerText
        headerIconPath: root.headerIconPath
        headerSymbol: root.headerSymbol

        // The drawer has a whole screen to size from; the dock's menus do not. The shape,
        // the spacing and the type come from the card either way.
        useDynamicRadius: true
        rowHeight: root.rowHeight
        menuWidth: root.menuWidth
        menuPadding: root.cardPadding
        rowSpacing: root.rowSpacing
        maximumHeight: root.maximumMenuHeight

        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.85
        // Grows out of the item that opened it, the way an Android long-press menu does.
        transformOrigin: Item.Top

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
        }

        onActionTriggered: root.close()
    }
}
