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
    property var activeRun: null
    property bool hasPendingApproval: false

    readonly property bool active: !!root.activeRun && (root.activeRun?.state === "active" || root.activeRun?.state === "streaming" || root.activeRun?.state === "generating" || root.activeRun?.state === "thinking" || root.activeRun?.state === "followUp") || root.hasPendingApproval
    readonly property bool needsAction: root.hasPendingApproval || root.activeRun?.state === "needsAction" || root.lastEvent?.requiresAttention === true
    readonly property string priority: root.needsAction ? "needsAction" : (root.active ? "active" : "idle")
    readonly property string notificationPrivacy: String(Config.options?.notifications?.privacy ?? "redacted")
    readonly property bool notificationAllowed: {
        const options = Config.options?.ai?.notify;
        if (!(options?.whenDone ?? true) || Notifications.effectiveSilent)
            return false;
        return true;
    }

    signal changed(var snapshot)

    function activeRunOrLast(): var {
        return root.activeRun ?? root.lastEvent ?? null;
    }

    function deepLink(surface = "sidebar"): var {
        const run = root.activeRunOrLast();
        const sessionId = String(run?.sessionId ?? "");
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
            sessionId: String(run?.sessionId ?? ""),
            messageId: String(run?.responseMessageId ?? run?.messageId ?? ""),
            deepLink: root.deepLink("sidebar"),
            notificationAllowed: root.notificationAllowed,
            privacy: root.notificationPrivacy
        };
    }

    function open(surface = "sidebar"): string {
        return typeof Ai !== "undefined" ? Ai.surfaceRouter.open(root.deepLink(surface)) : "";
    }

    function mark(event): void {
        root.lastEvent = Object.assign({}, event ?? ({}), { at: Date.now() });
        root.changeSequence += 1;
        root.changed(root.snapshot());
    }

    function notifyRunStarted(run): void {
        root.activeRun = run;
        root.mark({ type: "runStarted", run: run });
    }

    function notifyRunActivity(run, event): void {
        root.activeRun = run;
        root.mark({ type: "runActivity", run: run, event: event });
    }

    function notifyRunFinished(run): void {
        root.activeRun = null;
        root.mark({ type: "runFinished", run: run, requiresAttention: run?.state === "needsInspection" });
    }

    function notifyBrokerApproval(pending): void {
        root.hasPendingApproval = !!pending && Object.keys(pending).some(key => String(pending[key]?.state ?? "") === "approval");
        root.mark({ type: "brokerApproval", pending: pending });
    }

    function notifyResponseFinished(result): void {
        root.mark(result);
    }
}
