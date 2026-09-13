pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/** One global, session-bound run state machine for the MVP. */
Scope {
    id: root

    readonly property var states: ["idle", "preparing", "thinking", "searching", "toolRunning", "needsAction", "streaming", "completed", "failed", "cancelled", "interrupted", "needsInspection"]
    readonly property var terminalStates: ["completed", "failed", "cancelled", "interrupted", "needsInspection"]
    readonly property var activeStates: ["preparing", "thinking", "searching", "toolRunning", "needsAction", "streaming"]
    // A run is intentionally not an unconstrained bag of labels.  Keeping
    // the legal edges here prevents a late stream/tool callback from moving a
    // finished run back into an active state.
    readonly property var transitionGraph: ({
        idle: ["preparing"],
        preparing: ["preparing", "thinking", "failed", "cancelled", "interrupted", "needsInspection"],
        thinking: ["thinking", "searching", "toolRunning", "needsAction", "streaming", "completed", "failed", "cancelled", "interrupted", "needsInspection"],
        searching: ["searching", "thinking", "toolRunning", "needsAction", "streaming", "completed", "failed", "cancelled", "interrupted", "needsInspection"],
        toolRunning: ["toolRunning", "thinking", "searching", "needsAction", "streaming", "completed", "failed", "cancelled", "interrupted", "needsInspection"],
        needsAction: ["needsAction", "thinking", "searching", "toolRunning", "streaming", "completed", "failed", "cancelled", "interrupted", "needsInspection"],
        streaming: ["streaming", "thinking", "searching", "toolRunning", "needsAction", "completed", "failed", "cancelled", "interrupted", "needsInspection"]
    })
    property var runs: ({})
    property string activeRunId: ""

    signal runStarted(var run)
    signal runActivity(var run, var event)
    signal runFinished(var run)
    signal runRejected(string reason)

    function newId(): string {
        return `run-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }

    function runFor(runId: string): var {
        return root.runs[String(runId ?? "")] ?? null;
    }

    function start(sessionId: string, requestMessageId: string, responseMessageId: string, modelId: string, surface = "unknown"): var {
        const current = root.runFor(root.activeRunId);
        if (current && root.activeStates.includes(current.state)) {
            root.runRejected("busy");
            return {
                accepted: false,
                reason: "busy",
                runId: current.runId,
                sessionId: current.sessionId
            };
        }
        const run = {
            runId: root.newId(),
            sessionId: String(sessionId ?? ""),
            requestMessageId: String(requestMessageId ?? ""),
            responseMessageId: String(responseMessageId ?? ""),
            modelId: String(modelId ?? ""),
            state: "preparing",
            startedAt: Date.now(),
            finishedAt: 0,
            resultReason: "",
            surfaceAtStart: String(surface ?? "unknown"),
            isSeen: true,
            notificationEmitted: false,
            executionStarted: false,
            executionStartedAt: 0,
            networkStartedAt: 0,
            activityEvents: []
        };
        root.runs = Object.assign({}, root.runs, {
            [run.runId]: run
        });
        root.activeRunId = run.runId;
        root.runStarted(run);
        return {
            accepted: true,
            runId: run.runId,
            sessionId: run.sessionId,
            state: run.state
        };
    }

    function transition(runId: string, state: string, reason = "", extra = null) {
        const run = root.runFor(runId);
        if (!run || !root.states.includes(state)) {
            console.warn("[AiRunCoordinator] Invalid transition", runId, state);
            return false;
        }
        if (root.terminalStates.includes(run.state))
            return false;
        const allowed = root.transitionGraph[run.state] ?? [];
        if (!allowed.includes(state)) {
            console.warn("[AiRunCoordinator] Illegal transition", run.state, "->", state, runId);
            root.runRejected("illegal-transition");
            return false;
        }
        const next = Object.assign({}, run, extra ?? ({}), {
            state: state,
            resultReason: reason || run.resultReason,
            finishedAt: root.terminalStates.includes(state) ? Date.now() : run.finishedAt
        });
        root.runs = Object.assign({}, root.runs, {
            [runId]: next
        });
        if (root.terminalStates.includes(state)) {
            if (root.activeRunId === runId)
                root.activeRunId = "";
            root.runFinished(next);
            root.pruneTerminalRuns();
        } else {
            root.runActivity(next, {
                type: "state",
                state: state,
                at: Date.now(),
                reason: reason
            });
        }
        return true;
    }

    /**
     * Nothing ever looks a run up by id once a newer one has replaced it as
     * `activeRunId` - every caller keys off `currentRunId`, which moves on
     * to the next run. Without this, `root.runs` would grow by one entry
     * per exchange for the life of the process. A small tail is kept rather
     * than dropping immediately, in case something is mid-lookup on the run
     * that only just finished.
     */
    readonly property int maxTerminalRuns: 50

    function pruneTerminalRuns() {
        const entries = Object.entries(root.runs);
        const terminal = entries.filter(([, run]) => root.terminalStates.includes(run.state));
        if (terminal.length <= root.maxTerminalRuns)
            return;
        terminal.sort((a, b) => (a[1].finishedAt || 0) - (b[1].finishedAt || 0));
        const dropCount = terminal.length - root.maxTerminalRuns;
        const next = Object.assign({}, root.runs);
        for (let i = 0; i < dropCount; i++) {
            delete next[terminal[i][0]];
        }
        root.runs = next;
    }

    function activity(runId: string, type: string, data = null) {
        const run = root.runFor(runId);
        if (!run || root.terminalStates.includes(run.state))
            return false;
        const event = Object.assign({}, data ?? ({}), {
            type: String(type ?? "activity"),
            at: Date.now()
        });
        const nextState = type === "search" ? "searching" : (type === "tool" ? "toolRunning" : "streaming");
        const allowed = root.transitionGraph[run.state] ?? [];
        if (!allowed.includes(nextState)) {
            console.warn("[AiRunCoordinator] Illegal activity transition", run.state, "->", nextState, runId);
            root.runRejected("illegal-transition");
            return false;
        }
        const next = Object.assign({}, run, {
            state: nextState,
            activityEvents: [...(run.activityEvents ?? []), event].slice(-100)
        });
        root.runs = Object.assign({}, root.runs, {
            [runId]: next
        });
        root.runActivity(next, event);
        return true;
    }

    /** Mark an irreversible tool/config execution only after its journal ACK. */
    function markExecutionStarted(runId: string, extra = null): bool {
        const run = root.runFor(runId);
        // A provider may finish the assistant stream before the journal
        // helper ACKs. A completed run can still own the approved tool call;
        // failed/cancelled runs cannot.
        if (!run || (root.terminalStates.includes(run.state) && run.state !== "completed"))
            return false;
        const next = Object.assign({}, run, extra ?? ({}), {
            executionStarted: true,
            executionStartedAt: Date.now()
        });
        root.runs = Object.assign({}, root.runs, {
            [runId]: next
        });
        root.runActivity(next, {
            type: "executionStarted",
            at: Date.now(),
            tool: String(extra?.tool ?? "")
        });
        return true;
    }

    function finish(runId: string, state = "completed", reason = "done"): bool {
        return root.transition(runId, root.terminalStates.includes(state) ? state : "completed", reason);
    }

    function cancelByPolicy(localOnly = false): int {
        let count = 0;
        Object.keys(root.runs).forEach(runId => {
            const run = root.runs[runId];
            if (!run || !root.activeStates.includes(run.state))
                return;
            root.finish(runId, "cancelled", localOnly ? "cancelledByPolicy" : "disabledByPolicy");
            count += 1;
        });
        return count;
    }

    function restore(run: var): var {
        if (!run || !run.runId)
            return null;
        const restored = Object.assign({}, run, {
            state: run.executionStarted === true ? "needsInspection" : "interrupted",
            resultReason: "restart",
            finishedAt: Date.now(),
            isSeen: false
        });
        root.runs = Object.assign({}, root.runs, {
            [restored.runId]: restored
        });
        root.pruneTerminalRuns();
        return restored;
    }
}
