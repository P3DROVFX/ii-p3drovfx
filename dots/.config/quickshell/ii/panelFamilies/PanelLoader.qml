import QtQuick
import Quickshell

import qs.modules.common

/**
 * A shell panel, created in its own turn of the event loop.
 *
 * The panel itself is built synchronously, exactly as it always was. What changed is
 * only when: a panel takes a slot from `PanelSchedule` the moment it first wants to
 * exist, and waits for that slot to come up instead of racing every other panel into
 * one pass. See PanelSchedule for why this is a queue and not asynchronous loading.
 */
LazyLoader {
    id: root

    property bool extraCondition: true

    /// Built on the first tick, ahead of the queue: what the user sees at login
    /// (bar, wallpaper, lock). Tickets are taken from Component.onCompleted, which
    /// QML runs for siblings in reverse declaration order, so without this the bar,
    /// declared first, was built last, seconds after everything else.
    property bool priority: false

    readonly property bool wanted: Config.ready && root.extraCondition

    /// Zero until this panel has asked for a slot. It is released when the panel is no
    /// longer wanted so inactive panel families do not retain a schedule ticket.
    property int ticket: 0

    function takeTicket() {
        if (!root.wanted || root.ticket !== 0 || root.priority)
            return;
        root.ticket = PanelSchedule.take();
    }

    active: root.wanted && (root.priority || (root.ticket > 0 && PanelSchedule.released >= root.ticket))

    onWantedChanged: {
        if (root.wanted)
            root.takeTicket();
        else
            root.ticket = 0;
    }
    Component.onCompleted: root.takeTicket()
}
