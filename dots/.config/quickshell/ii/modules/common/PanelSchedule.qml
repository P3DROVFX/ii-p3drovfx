pragma Singleton

import QtQuick
import Quickshell

/**
 * Hands out creation slots to shell panels, one per tick.
 *
 * Every panel is gated on the same `Config.ready`, so without this they are all built in
 * a single event loop pass — around forty subtrees, every module they import, once per
 * monitor — and nothing paints until the last one exists. That is the multi-second freeze
 * at startup, and a smaller one whenever a family is rebuilt.
 *
 * Panels are still built synchronously, one at a time. Quickshell's own asynchronous
 * incubation is not an option for them: an `IpcHandler` finalised from the incubation
 * controller crashes in post-reload registration, and most panels declare one. Yielding
 * between panels is what keeps the shell drawing; the work itself is unchanged.
 *
 * The order is set by each panel's `priority`, not by when it asked. Every panel asks
 * from the same `Config.ready` change, and QML notifies the last-declared loader first:
 * with a plain counter the bar, declared first, was built last, ~55 panels and ~6 s
 * after the family existed.
 */
Singleton {
    id: root

    /// Panels waiting for a slot, best first: higher `priority`, then the order they asked in.
    property var waiting: []

    /// Holds new panels back while a config change is still being applied in
    /// stages. A preset that swaps the bar for the vertical bar and the
    /// sidebars for the top layer lands across several frames, and building
    /// on each intermediate state created windows only to destroy them a few
    /// frames later — each costing a 40–100 ms first frame. A panel that stops
    /// being wanted while held gives its slot back and is never built.
    property bool hold: false

    /// Nothing queued and nothing held: every wanted panel exists.
    readonly property bool idle: !root.hold && root.waiting.length === 0

    function request(loader) {
        if (root.waiting.indexOf(loader) !== -1)
            return;
        const queue = root.waiting.slice();
        let i = queue.length;
        while (i > 0 && (queue[i - 1]?.priority ?? 0) < loader.priority)
            i--;
        queue.splice(i, 0, loader);
        root.waiting = queue;
    }

    function withdraw(loader) {
        const i = root.waiting.indexOf(loader);
        if (i === -1)
            return;
        const queue = root.waiting.slice();
        queue.splice(i, 1);
        root.waiting = queue;
    }

    Timer {
        // Not zero: the panel built on the previous tick still has a first frame to
        // render, and beating it to the next one puts the stall back.
        interval: 8
        repeat: true
        running: !root.hold && root.waiting.length > 0

        onTriggered: {
            const queue = root.waiting.slice();
            const loader = queue.shift();
            root.waiting = queue;
            if (loader && loader.wanted)
                loader.granted = true;
        }
    }
}
