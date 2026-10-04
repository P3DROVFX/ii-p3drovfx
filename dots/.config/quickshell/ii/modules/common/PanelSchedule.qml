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
 */
Singleton {
    id: root

    /// Slots handed out so far. A panel takes one when it first wants to exist, so the
    /// order is the order they were declared in.
    property int issued: 0

    /// Slots cleared for creation. A panel builds once its own number comes up.
    property int released: 0

    /// Holds new panels back while a config change is still being applied in
    /// stages. A preset that swaps the bar for the vertical bar and the
    /// sidebars for the top layer lands across several frames, and building
    /// on each intermediate state created windows only to destroy them a few
    /// frames later — each costing a 40–100 ms first frame. A panel that stops
    /// being wanted while held gives its slot back and is never built.
    property bool hold: false

    /// Nothing queued and nothing held: every wanted panel exists.
    readonly property bool idle: !root.hold && root.released >= root.issued

    function take(): int {
        return ++root.issued;
    }

    Timer {
        // Not zero: the panel built on the previous tick still has a first frame to
        // render, and beating it to the next one puts the stall back.
        interval: 8
        repeat: true
        running: !root.hold && root.released < root.issued

        onTriggered: root.released++
    }
}
