pragma ComponentBehavior: Bound
import QtQuick

// Editor code, icon grids and conflict checks are paid for only when requested.
// Both keyboard maps and shortcut pages use the same existing sidebar.
Loader {
    id: root
    required property string pageId
    property Item keyNavTarget: null
    property string editorObjectName: ""
    readonly property bool isOpen: item?.isOpen ?? false
    readonly property bool isAnimating: item?.isAnimating ?? false
    active: false
    signal closeRequested

    function ensureEditor() {
        if (!item) {
            active = true;
            setSource(Qt.resolvedUrl("CheatsheetKeybindEditorSidebar.qml"), {
                pageId: root.pageId, keyNavTarget: root.keyNavTarget, objectName: root.editorObjectName
            });
        }
        return item;
    }
    function openCreate() { ensureEditor()?.openCreate(); }
    function openEdit(entry) { ensureEditor()?.openEdit(entry); }
    function openKeyboardKey(layer, index, entry) { ensureEditor()?.openKeyboardKey(layer, index, entry); }
    function close() { item?.close(); }
    function releaseClosedEditor() {
        if (!isOpen && !isAnimating) active = false;
    }

    Binding { target: root.item; property: "pageId"; value: root.pageId; when: root.item !== null }
    Binding { target: root.item; property: "keyNavTarget"; value: root.keyNavTarget; when: root.item !== null }
    Connections {
        target: root.item
        function onCloseRequested() {
            root.closeRequested();
            // The animation callback must finish before its owner is destroyed.
            Qt.callLater(root.releaseClosedEditor);
        }
    }
}
