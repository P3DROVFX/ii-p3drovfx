pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell

/** One attention projection shared by the Island, bar-facing status and notifications. */
Singleton {
    id: root

    property var lastEvent: null
    property int changeSequence: 0

    readonly property var activeRun: {
        if (typeof Ai === "undefined" || !Ai.runCoordinator)
            return null;
        return Ai.runCoordinator.runFor(Ai.runCoordinator.activeRunId);
    }
    readonly property bool hasPendingApproval: {
        if (typeof Ai === "undefined" || !Ai.broker)
            return false;
        const pending = Ai.broker.pending ?? ({});
        return Object.keys(pending).some(key => String(pending[key]?.state ?? "") === "approval");
    }
    readonly property bool active: !!root.activeRun && Ai.runCoordinator.activeStates.includes(root.activeRun.state) || root.hasPendingApproval
    readonly property bool needsAction: root.hasPendingApproval || root.activeRun?.state === "needsAction" || root.lastEvent?.requiresAttention === true
    readonly property string priority: root.needsAction ? "needsAction" : (root.active ? "active" : "idle")
    readonly property string notificationPrivacy: String(Config.options?.notifications?.privacy ?? "redacted")
    readonly property bool notificationAllowed: {
        const options = Config.options?.ai?.notify;
        if (!(options?.whenDone ?? true) || Notifications.effectiveSilent)
            return false;
        if ((options?.onlyWhenAway ?? true) && Ai.chatOnScreen)
            return false;
        return true;
    }

    signal changed(var snapshot)

    function activeRunOrLast(): var {
        return root.activeRun ?? root.lastEvent ?? null;
    }

    function deepLink(surface = "sidebar"): var {
        const run = root.activeRunOrLast();
        const sessionId = String(run?.sessionId ?? Ai.sessions.currentId ?? "");
        const messageId = String(run?.responseMessageId ?? run?.messageId ?? "");
        return {
            surface: surface === "search" ? "search" : "sidebar",
            sessionId: sessionId,
            runId: String(run?.runId ?? ""),
            messageId: messageId,
            focusIntent: root.needsAction ? "tool" : "answer",
            scrollAnchor: { messageId: messageId, blockId: "", offset: 0, following: false }
        };
    }

    function snapshot(): var {
        const run = root.activeRunOrLast();
        return {
            active: root.active,
            needsAction: root.needsAction,
            priority: root.priority,
            state: String(run?.state ?? "idle"),
            runId: String(run?.runId ?? ""),
            sessionId: String(run?.sessionId ?? Ai.sessions.currentId ?? ""),
            messageId: String(run?.responseMessageId ?? run?.messageId ?? ""),
            deepLink: root.deepLink("sidebar"),
            notificationAllowed: root.notificationAllowed,
            privacy: root.notificationPrivacy
        };
    }

    function open(surface = "sidebar"): string {
        return Ai.surfaceRouter.open(root.deepLink(surface));
    }

    function mark(event): void {
        root.lastEvent = Object.assign({}, event ?? ({}), { at: Date.now() });
        root.changeSequence += 1;
        root.changed(root.snapshot());
    }

    Connections {
        target: Ai.runCoordinator
        function onRunStarted(run) { root.mark({ type: "runStarted", run: run }); }
        function onRunActivity(run, event) { root.mark({ type: "runActivity", run: run, event: event }); }
        function onRunFinished(run) { root.mark({ type: "runFinished", run: run, requiresAttention: run.state === "needsInspection" }); }
    }

    Connections {
        target: Ai
        function onResponseFinished(result) { root.mark(result); }
    }
}
