pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */
Singleton {
    id: root

    signal dismissed

    property list<var> persistent: []
    property list<var> dismissable: []

    function dismiss() {
        root.dismissable = [];
        root.dismissed();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            // Reassign instead of in-place push: the HyprlandFocusGrab windows binding
            // must re-evaluate when a window joins while the grab is already active
            // (e.g. a bar popup opening over an open sidebar).
            root.persistent = [...root.persistent, window];
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            root.persistent = root.persistent.filter((w, i) => i !== index);
        }
    }

    function addDismissable(window) {
        if (root.dismissable.indexOf(window) === -1) {
            root.dismissable = [...root.dismissable, window];
        }
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            root.dismissable = root.dismissable.filter((w, i) => i !== index);
        }
    }

    function hasActive(element) {
        return element?.activeFocus || Array.from(element?.children).some(child => hasActive(child));
    }

    HyprlandFocusGrab {
        id: grab
        windows: [...root.dismissable, ...root.persistent]
        active: root.dismissable.length > 0
        onCleared: () => {
            root.dismiss();
        }
    }
}
