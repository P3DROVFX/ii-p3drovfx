import QtQuick

/**
 * Lazy host for WorkspaceProfileForm.
 *
 * The snapshot/edit form is ~1.3k lines and used to be built eagerly whenever
 * the Workspaces tab loaded — and because the cheatsheet only keeps the last
 * tab, switching *to* Workspaces rebuilds it every time, so that construction
 * landed as a stutter on each switch. The form is only ever shown after the
 * user hits "new snapshot" or "edit".
 *
 * Presents the same interface CheatsheetWorkspaces uses (id workspaceProfileForm,
 * isOpen/isAnimating, openForAdd/openForEdit/startClose) but builds the real
 * form on the first open and keeps it for the rest of that tab's life. Same
 * idiom as DeferredEventSidebar / DeferredKeybindEditor. Methods forward with
 * .apply(item, arguments) so their arity can't drift.
 */
Item {
    id: root

    readonly property bool isOpen: loader.item ? loader.item.isOpen : false
    readonly property bool isAnimating: loader.item ? loader.item.isAnimating : false

    visible: root.isOpen || root.isAnimating

    function ensure() {
        if (!loader.active)
            loader.active = true;
        return loader.item;
    }

    function openForAdd() { const it = ensure(); return it.openForAdd.apply(it, arguments); }
    function openForEdit() { const it = ensure(); return it.openForEdit.apply(it, arguments); }
    function startClose() { if (loader.item) return loader.item.startClose.apply(loader.item, arguments); }

    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: WorkspaceProfileForm {
            anchors.fill: parent
        }
    }
}
