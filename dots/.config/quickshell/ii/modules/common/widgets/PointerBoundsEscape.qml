import QtQuick

/**
 * Keeps Qt from skipping pointer delivery into its parent's subtree.
 *
 * Since 6.8, the first event that reaches an item caches whether all of its
 * pointer-handling descendants fit inside it, and outside points then skip the
 * whole subtree. That cache only gets cleared when an item moves out of its
 * parent, and the walk up stops at the first ancestor that still fits. Items
 * loaded later never clear it. A card that grows past its ancestors (the Edit
 * Mode counter-scaled desktop menus) then loses every click out there.
 *
 * Declare one as a direct child of EVERY ancestor that the overflowing content
 * crosses, Loaders included: a 1 px pointer item that is always outside the
 * parent makes that level's answer "no" for good. It never takes an event
 * (no buttons, no hover).
 */
MouseArea {
    x: -1
    y: -1
    width: 1
    height: 1
    acceptedButtons: Qt.NoButton
    hoverEnabled: false
}
