pragma ComponentBehavior: Bound

import QtQuick

// Starts an animation controller after its Loader has finished incubating.
// A plain Qt.callLater() can run while controller.item is still null when the
// parent itself was created by an asynchronous Loader. In that case the visual
// properties have already been reset to their first frame, but the animation
// never receives restart().
Item {
    id: root

    required property var controller
    property bool pending: false
    property int _generation: 0

    function requestStart() {
        if (!root.enabled) {
            root.stop();
            return;
        }

        const generation = ++root._generation;
        root.pending = true;
        Qt.callLater(function() {
            root._flush(generation);
        });
    }

    function stop() {
        ++root._generation;
        root.pending = false;
        if (root.controller && root.controller.item)
            root.controller.item.stop();
    }

    function _flush(generation) {
        if (!root.pending || generation !== root._generation || !root.enabled)
            return;

        if (!root.controller || !root.controller.item)
            return;

        root.pending = false;
        root.controller.item.restart();
    }

    onEnabledChanged: {
        if (!enabled)
            root.stop();
    }

    Connections {
        target: root.controller
        function onLoaded() {
            root._flush(root._generation);
        }
    }
}
