import QtQuick
import QtQuick.Layouts
import qs.services

/**
 * A page block that is only built once it is about to scroll into view.
 *
 * A Settings page is taller than its window, and everything below the fold used
 * to be built on open although most visits never scroll there. The block holds
 * `placeholderHeight` of space until `lookahead` px from the viewport edge, then
 * builds `content` and keeps it. A pending search/jump builds it at once so the
 * section it names exists to be found.
 *
 * The content is an inline Component, so it still sees the ids of the page file.
 * It must not be referenced from outside the block by id.
 */
Item {
    id: root

    default property Component content
    property real placeholderHeight: 240
    property real lookahead: 300
    property bool force: false

    readonly property bool built: loader.active
    property Flickable flickable: null

    Layout.fillWidth: true
    implicitHeight: loader.item ? loader.item.implicitHeight : root.placeholderHeight

    function findFlickable() {
        let p = parent;
        while (p) {
            if (p.flickableDirection !== undefined && p.contentY !== undefined) {
                root.flickable = p;
                return;
            }
            p = p.parent;
        }
        root.flickable = null;
    }

    function evaluate() {
        if (loader.active)
            return;
        if (root.force || SearchRegistry.currentSearch !== "" || !root.flickable) {
            loader.active = true;
            return;
        }
        // Not placed yet: a layout sets width and y together, in its polish.
        if (root.width <= 0)
            return;
        const top = root.mapToItem(root.flickable.contentItem, 0, 0).y;
        if (top < root.flickable.contentY + root.flickable.height + root.lookahead)
            loader.active = true;
    }

    Component.onCompleted: {
        findFlickable();
        settle.start();
    }
    onParentChanged: findFlickable()
    onYChanged: evaluate()
    onWidthChanged: evaluate()
    onForceChanged: evaluate()

    Timer {
        id: settle
        interval: 0
        onTriggered: root.evaluate()
    }

    Connections {
        target: loader.active ? null : root.flickable
        function onContentYChanged() { root.evaluate(); }
        function onHeightChanged() { root.evaluate(); }
    }
    Connections {
        target: loader.active ? null : SearchRegistry
        function onCurrentSearchChanged() { root.evaluate(); }
    }

    Loader {
        id: loader
        width: root.width
        active: false
        sourceComponent: root.content
    }
}
