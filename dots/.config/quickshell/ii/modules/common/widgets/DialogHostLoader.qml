pragma ComponentBehavior: Bound

import QtQuick

/**
 * Shared host for WindowDialog instances.
 *
 * The owner supplies a boolean property (by name) that controls lazy loading.
 * Dismissal clears the owner's flag, unloads the Loader and returns focus to
 * the host after the dialog has gone away.
 */
Loader {
    id: root

    required property var owner
    required property string shownPropertyString
    property Item focusTarget: null
    property real dialogRadius: -1
    // Hosts on a full-screen surface (tablet shade) widen the dialog; -1 leaves the
    // dialog's own width alone, which is what the ii sidebar wants.
    property real dialogWidth: -1
    property bool closing: false
    property alias dialog: root.sourceComponent

    readonly property bool shown: root.owner ? Boolean(root.owner[root.shownPropertyString]) : false

    signal dialogClosed()

    anchors.fill: parent
    active: shown || closing

    function activateDialog() {
        if (!root.item)
            return;
        root.item.show = true;
        root.item.forceActiveFocus();
    }

    function dismissDialog() {
        if (root.item) {
            root.closing = true;
            root.item.show = false;
        }
        if (root.owner)
            root.owner[root.shownPropertyString] = false;
        Qt.callLater(() => {
            if (root.item && !root.item.visible && !root.shown)
                root.closing = false;
        });
    }

    function restoreFocus() {
        if (root.focusTarget)
            Qt.callLater(() => root.focusTarget.forceActiveFocus());
    }

    onActiveChanged: {
        if (active) {
            if (root.shown)
                root.activateDialog();
        } else {
            root.restoreFocus();
        }
    }

    onLoaded: root.activateDialog()

    Binding {
        target: root.item
        property: "radius"
        value: root.dialogRadius
        when: root.dialogRadius >= 0 && root.item && root.item.hasOwnProperty("radius")
    }

    Binding {
        target: root.item
        property: "preferredDialogWidth"
        value: root.dialogWidth
        when: root.dialogWidth >= 0 && root.item && root.item.hasOwnProperty("preferredDialogWidth")
    }

    Connections {
        target: root.item
        ignoreUnknownSignals: true

        function onDismiss() {
            root.dismissDialog();
        }

        function onDetailsRequested() {
            // Details opens the external system app, but the dialog itself is
            // still owned by this host and must not remain over the Welcome.
            // The dialog decides independently whether its owning Sidebar
            // should close (via closeOwningSidebarOnDetails).
            Qt.callLater(root.dismissDialog);
        }

        function onVisibleChanged() {
            if (!root.item || root.item.visible || root.shown)
                return;
            root.closing = false;
            root.restoreFocus();
            root.dialogClosed();
        }
    }
}
