pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Live projections for every conversation known to the AI facade.
 *
 * The visible transcript is still owned by Ai.qml for now, but persistence,
 * run state and protection decisions are keyed by sessionId here. This keeps
 * a background run attached to its origin when the user selects another chat.
 */
Scope {
    id: root

    property var records: ({})
    readonly property var protectedSessionIds: Object.keys(root.records).filter(id => {
        const record = root.records[id];
        return !!record && (record.run?.state && !["idle", "completed", "failed", "cancelled"].includes(record.run.state)
                            || record.dirty === true || record.savePending === true || record.needsAction === true || record.needsInspection === true);
    })

    signal recordChanged(string sessionId)
    signal runChanged(string sessionId, var run)

    function ensure(sessionId: string): var {
        const id = String(sessionId ?? "").trim();
        if (!id)
            return null;
        if (!root.records[id]) {
            root.records = Object.assign({}, root.records, {
                [id]: {
                    sessionId: id,
                    snapshot: null,
                    run: null,
                    dirty: false,
                    savePending: false,
                    needsAction: false,
                    needsInspection: false,
                    seen: true
                }
            });
        }
        return root.records[id];
    }

    function capture(sessionId: string, snapshot: var): var {
        const record = root.ensure(sessionId);
        if (!record)
            return null;
        const next = Object.assign({}, record, {
            snapshot: snapshot,
            dirty: false
        });
        root.records = Object.assign({}, root.records, {
            [sessionId]: next
        });
        root.recordChanged(sessionId);
        return next;
    }

    function snapshot(sessionId: string): var {
        return root.records[String(sessionId ?? "")]?.snapshot ?? null;
    }

    function setRun(sessionId: string, run: var): var {
        const record = root.ensure(sessionId);
        if (!record)
            return null;
        const next = Object.assign({}, record, {
            run: run,
            dirty: true,
            savePending: true,
            needsAction: run?.state === "needsAction",
            needsInspection: run?.state === "needsInspection"
        });
        root.records = Object.assign({}, root.records, {
            [sessionId]: next
        });
        root.runChanged(sessionId, run);
        return next;
    }

    function markSaveAcknowledged(sessionId: string) {
        const record = root.records[String(sessionId ?? "")];
        if (!record)
            return;
        root.records = Object.assign({}, root.records, {
            [sessionId]: Object.assign({}, record, {
                dirty: false,
                savePending: false
            })
        });
        root.recordChanged(sessionId);
    }

    function markSavePending(sessionId: string, pending = true) {
        const record = root.ensure(sessionId);
        if (!record)
            return;
        root.records = Object.assign({}, root.records, {
            [sessionId]: Object.assign({}, record, {
                savePending: pending,
                dirty: pending || record.dirty
            })
        });
        root.recordChanged(sessionId);
    }

    function markSeen(sessionId: string, seen = true) {
        const record = root.ensure(sessionId);
        if (!record)
            return;
        root.records = Object.assign({}, root.records, {
            [sessionId]: Object.assign({}, record, { seen: seen })
        });
        root.recordChanged(sessionId);
    }

    function canMutate(sessionId: string): bool {
        const record = root.records[String(sessionId ?? "")];
        if (!record)
            return true;
        return !root.protectedSessionIds.includes(String(sessionId));
    }

    function restoreRun(sessionId: string, run: var): var {
        if (!run || !run.state || ["idle", "completed", "failed", "cancelled"].includes(run.state))
            return run;
        const restored = Object.assign({}, run, {
            state: run.state === "toolRunning" || run.executionStarted ? "needsInspection" : "interrupted",
            resultReason: "restart",
            finishedAt: Date.now(),
            isSeen: false
        });
        root.setRun(sessionId, restored);
        return restored;
    }
}
