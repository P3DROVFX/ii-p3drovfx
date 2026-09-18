pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import "IslandLayout.js" as IslandLayout
import "sources"

/**
 * What the island is showing, and where.
 *
 * Deliberately not a singleton: the island is per-surface, and a global here would make
 * two styles or two monitors fight over one piece of state. The owning style instantiates
 * exactly one.
 *
 * It knows nothing about any particular activity. Sources report presence, IslandRegistry
 * describes shape and priority, IslandLayout decides slots. That separation is the whole
 * point: the previous panel mixed detection, arbitration, geometry and rendering in one
 * 1900-line file, so every new activity risked all four.
 */
Item {
    id: controller

    visible: false

    /** 1 collapses the cluster to a single surface, which is what the notch style is. */
    property int maxIslands: 3

    /** The activity the pointer has expanded, and the slot it sits in. */
    property string expandedId: ""
    property bool dashboardOpen: false

    readonly property alias sources: sourceSet
    IslandSources {
        id: sourceSet
    }

    /**
     * The resting face. It is not a source: there is no event that makes a clock
     * happen, it is simply what the centre shows when nothing else needs it.
     */
    readonly property var clockActivity: ({
        id: "clock",
        tier: "idle",
        preferredSide: "right",
        canDetach: false,
        settleMs: 0,
        arrivedAt: 0
    })

    /**
     * Everything currently present, as IslandLayout wants it.
     *
     * Reading each source's `active` inside this binding is what subscribes the island to
     * them, so a source appearing or leaving recomputes the layout on its own.
     */
    readonly property var activities: {
        const list = [];
        const all = sourceSet.all;
        for (let i = 0; i < all.length; i++) {
            const source = all[i];
            if (!source.active)
                continue;
            const descriptor = IslandRegistry.byId(source.activityId);
            if (!descriptor)
                continue;
            list.push({
                id: descriptor.id,
                // A source may raise its own urgency: an agent waiting for approval is
                // an interrupt, the same agent working is not.
                tier: (source.tierOverride !== undefined && source.tierOverride !== "")
                    ? source.tierOverride : descriptor.tier,
                preferredSide: descriptor.preferredSide,
                canDetach: descriptor.canDetach,
                settleMs: descriptor.settleMs,
                arrivedAt: source.arrivedAt,
                revision: source.revision
            });
        }
        list.push(controller.clockActivity);
        return list;
    }

    property var assignment: ({
        left: null,
        center: "clock",
        right: null,
        overflow: []
    })

    readonly property string centerId: controller.assignment.center ?? ""
    readonly property string leftId: controller.assignment.left ?? ""
    readonly property string rightId: controller.assignment.right ?? ""
    readonly property var overflowIds: controller.assignment.overflow ?? []

    function slotOf(activityId) {
        return IslandLayout.slotOf(controller.assignment, activityId) ?? "";
    }

    function presentationFor(activityId) {
        if (activityId === "" )
            return "";
        if (controller.expandedId === activityId)
            return "expanded";
        return controller.slotOf(activityId) === "center" ? "compact" : "orb";
    }

    function recompute() {
        const next = IslandLayout.assignSlots(controller.activities, {
            now: Date.now(),
            maxIslands: controller.maxIslands,
            // An expanded island must not be moved out from under the pointer.
            pinnedId: controller.expandedId,
            pinnedSlot: controller.expandedId !== "" ? controller.slotOf(controller.expandedId) : "",
            previous: controller.assignment
        });
        const moves = IslandLayout.transitions(controller.assignment, next, IslandRegistry.ids);
        controller.assignment = next;
        if (moves.length > 0)
            controller.slotsChanged(moves);
    }

    /** Emitted with the slot changes the surface has to animate (detach, absorb, swap). */
    signal slotsChanged(var moves)

    onActivitiesChanged: {
        controller.recompute();
        controller.armSettleTimer();
    }
    onMaxIslandsChanged: controller.recompute()
    /**
     * Deferred, because the owner derives `expandedId` from `centerId`.
     *
     * The notch binds `expandedId: expanded ? pagedId : ""` and `pagedId` falls back to
     * `centerId`, so recomputing synchronously here reassigned `centerId` while the
     * binding that read it was still being evaluated - a binding loop Qt logged and
     * broke at an arbitrary point, which could leave the centre on a stale activity for
     * a frame and flick it back on the next. One turn of the event loop later the
     * dependency is a plain sequence, and repeated changes in one turn collapse into a
     * single recompute.
     */
    onExpandedIdChanged: Qt.callLater(controller.recompute)

    /**
     * An arriving activity holds the centre for its settle window and then detaches, so
     * the layout has to be re-asked when that window closes.
     *
     * This is a function and not a binding: it reads `Date.now()`, which no binding can
     * depend on, so a `readonly property bool` version stayed true forever and left the
     * timer below running for the rest of the session. The timer is armed when an
     * activity arrives and disarms itself the moment nothing is settling any more.
     */
    function anySettling() {
        const now = Date.now();
        const list = controller.activities;
        for (let i = 0; i < list.length; i++) {
            if (list[i].canDetach && list[i].settleMs > 0 && (now - list[i].arrivedAt) < list[i].settleMs)
                return true;
        }
        return false;
    }

    function armSettleTimer() {
        if (controller.anySettling())
            settleTimer.start();
    }

    property Timer settleTimer: Timer {
        id: settleTimer
        interval: 120
        repeat: true
        running: false
        onTriggered: {
            controller.recompute();
            if (!controller.anySettling())
                settleTimer.stop();
        }
    }

    Component.onCompleted: {
        controller.recompute();
        controller.armSettleTimer();
    }
}
