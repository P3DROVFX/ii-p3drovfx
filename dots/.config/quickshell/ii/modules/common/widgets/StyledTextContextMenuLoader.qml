import QtQuick

/**
 * StyledTextContextMenu, built on the first right-click.
 *
 * The menu is seven items, a shadow and a background - about 4.5 ms per text
 * field on a downclocked CPU - and nearly every field lives and dies without
 * it ever opening. A settings page with a few dozen spin boxes paid for all of
 * them up front. Same `targetField` / `popup(x, y)` surface as the menu.
 */
Loader {
    id: root
    property Item targetField: null

    function popup(x, y) {
        root.active = true;
        root.item.popup(x, y);
    }

    active: false
    sourceComponent: StyledTextContextMenu {
        // Same coordinate space as the menu had when it was declared in place.
        parent: root.parent
        targetField: root.targetField
    }
}
