import QtQuick
import "GroupLayout.js" as GroupLayout

/**
 * Where a rounded settings row sits among its rounded siblings.
 *
 * Filled in by GroupLayout.js, one pass per container. The row declares
 * `readonly property GroupPosition groupPosition: GroupPosition { item: root }`
 * and reads index/count/neighbours from it.
 */
QtObject {
    id: position

    property Item item: null
    property bool enabled: true

    property int index: 0
    property int count: 1
    property Item previous: null
    property Item next: null
    // False until the first deferred pass has run. Gate radius animations on
    // it, or a row animates from its default corners to its real ones on first
    // show.
    property bool settled: false

    readonly property bool isFirst: position.index === 0
    readonly property bool isLast: position.index === position.count - 1
    readonly property bool previousPressed: position.pressed(position.previous)
    readonly property bool nextPressed: position.pressed(position.next)

    function pressed(row) {
        if (!row)
            return false;
        return row.isPressed === true || row.down === true;
    }

    function request() {
        if (position.enabled && position.item)
            GroupLayout.schedule(position.item.parent);
    }

    onEnabledChanged: position.request()

    Component.onCompleted: {
        if (position.enabled && position.item)
            GroupLayout.refresh(position.item.parent);
    }

    property Connections _itemConnections: Connections {
        target: position.enabled ? position.item : null

        function onParentChanged() {
            position.request();
        }

        function onVisibleChanged() {
            position.request();
        }
    }

    property Connections _containerConnections: Connections {
        target: position.enabled && position.item ? position.item.parent : null

        function onChildrenChanged() {
            position.request();
        }
    }
}
