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

    /// Higher builds first. Only what the first paint shows (bar, background, island,
    /// dock) should set it; everything else keeps 0.
    property int priority: 0

    readonly property bool wanted: Config.ready && root.extraCondition

    /// Set by PanelSchedule when this panel's slot comes up. Cleared when the panel is no
    /// longer wanted, so an inactive panel family holds no place in the queue.
    property bool granted: false

    active: root.wanted && root.granted

    onWantedChanged: {
        if (root.wanted) {
            if (!root.granted)
                PanelSchedule.request(root);
        } else {
            root.granted = false;
            PanelSchedule.withdraw(root);
        }
    }
    Component.onCompleted: {
        if (root.wanted && !root.granted)
            PanelSchedule.request(root);
    }
    Component.onDestruction: PanelSchedule.withdraw(root)
}
