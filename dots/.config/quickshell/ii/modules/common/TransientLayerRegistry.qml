pragma Singleton

import QtQuick
import Quickshell

/**
 * Things that Back should dismiss before it dismisses anything structural.
 *
 * "Back" walks a stack, and the stack is deeper than the list of shell surfaces. A quick
 * toggle's dialog, a long-press menu, the keyboard — each of them is on top of whatever
 * surface opened it, and pressing Back with one of them up has to close *it*, not the shade
 * underneath it. Without this the shade would vanish out from under an open dialog, which
 * is not going back, it is going two steps back and losing the first one.
 *
 * The pieces that need to be dismissed are local state inside their own surfaces — twelve
 * `showXDialog` booleans on the shade's content item, an `open` on a menu card — so there is
 * nothing global to inspect. Each one registers a token and a way to close itself instead,
 * and the family's Back asks this for the topmost.
 *
 * Registration is by token rather than by object so a surface that is destroyed while
 * registered (a menu inside a closing drawer) cannot leave a callback pointing at a dead
 * item: re-registering the same token replaces the old entry, and the closer is called
 * inside a try, because one broken layer must not stop Back from working.
 */
Singleton {
    id: root

    /// [{ token, close }], most recently pushed last.
    property var layers: []

    readonly property bool hasAny: root.layers.length > 0

    function push(token, closeFunction) {
        if (!token || typeof closeFunction !== "function")
            return;
        root.layers = root.layers.filter(layer => layer.token !== token)
            .concat([{ token: token, close: closeFunction }]);
    }

    function remove(token) {
        if (!token)
            return;
        root.layers = root.layers.filter(layer => layer.token !== token);
    }

    /// Sets or clears a layer from one boolean, which is what almost every caller wants.
    function set(token, shown, closeFunction) {
        if (shown)
            root.push(token, closeFunction);
        else
            root.remove(token);
    }

    /// Closes the topmost layer. True when there was one, so Back knows to stop here.
    function closeTop() {
        if (root.layers.length === 0)
            return false;
        const top = root.layers[root.layers.length - 1];
        root.layers = root.layers.slice(0, -1);
        try {
            top.close();
        } catch (error) {
            console.log("[TransientLayerRegistry] closing", top.token, "failed:", error);
        }
        return true;
    }
}
