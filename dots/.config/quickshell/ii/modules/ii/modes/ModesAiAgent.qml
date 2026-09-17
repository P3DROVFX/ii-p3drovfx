pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

/**
 * The run itself: one request into the sidebar AiChat session, watched to
 * its terminal beat.
 *
 * This is the only file in the Modes module that touches `Ai`, and it is
 * only alive after the user has actually sent something — the overlay
 * creates it on first submit and destroys it when the bar folds. Before
 * that first touch, opening Modes constructs no AI graph at all: no toolbox,
 * no integrations, no model catalog (docs/memory-audit-2026-09-15.md §17
 * is the budget this obeys).
 *
 * The request goes through `Ai.submit` — the same durable submission
 * pipeline the composer uses — with two differences the surface needs:
 * `toolDomains: ["modes"]` narrows the offer to the modes tools, so the
 * agent can neither see nor (via the broker's execution re-check) run
 * anything outside them; and the task system prompt replaces the persona
 * for this turn only, while the user's sentence itself lands in the normal
 * transcript, which is where the user goes to read the request, the tool
 * steps and any error afterwards.
 *
 * Correlation: submit answers synchronously with acceptance or a refusal;
 * the accepted path is followed by `submissionStarted` (submissionId →
 * runId/sessionId), terminal states by `runFinished` on the coordinator,
 * failures before the run by `submissionFailed`/`submissionCancelled`. The
 * created definition arrives from the integration, mid-run, as soon as the
 * engine has it — that is the moment the overlay opens the editor, without
 * waiting for the model to finish its sentence.
 */
Scope {
    id: root

    signal accepted()
    signal rejected(string reason)
    /// Terminal: the run ended; `created` says whether a definition landed.
    signal finished(string state, string errorText, bool created, string kind, string id, string name)

    property string submissionId: ""
    property string runId: ""
    property string sessionId: ""
    property bool awaiting: false
    property var creation: null

    function submit(text) {
        if (root.awaiting)
            root.cancel();
        root.creation = null;
        root.submissionId = "";
        root.runId = "";
        root.sessionId = "";
        // First touch of the AI graph: the persona prompt, the toolbox and
        // the modes adapter are read here, not at construction.
        const result = Ai.submit(String(text ?? ""), {
            systemPrompt: Ai.modesIntegration.agentPrompt(),
            toolDomains: ["modes"],
        }, "modes");
        if (result?.accepted !== true) {
            root.awaiting = false;
            root.rejected(String(result?.userMessage ?? Translation.tr("The request could not be sent.")));
            return;
        }
        root.awaiting = true;
        root.submissionId = String(result.submissionId ?? "");
        root.accepted();
    }

    function cancel(): void {
        if (!root.awaiting)
            return;
        Ai.stopGeneration();
    }

    function _mine(submissionId): bool {
        return root.submissionId.length > 0 && String(submissionId ?? "") === root.submissionId;
    }

    function _end(state, errorText): void {
        if (!root.awaiting)
            return;
        root.awaiting = false;
        const made = root.creation;
        root.finished(
            String(state ?? ""),
            String(errorText ?? ""),
            made !== null,
            String(made?.kind ?? ""),
            String(made?.id ?? ""),
            String(made?.name ?? ""));
    }

    Connections {
        target: Ai

        function onSubmissionStarted(submissionId, runId, sessionId) {
            if (!root._mine(submissionId))
                return;
            root.runId = String(runId ?? "");
            root.sessionId = String(sessionId ?? "");
        }

        function onSubmissionFailed(submissionId, operationId, errorCode, recoveryActionIds) {
            // Empty submissionId: rejected before the slot was claimed. The
            // bar already heard about that synchronously; a pre-run failure
            // carries the id and ends the watch here.
            if (!root._mine(submissionId))
                return;
            root._end("failed", Translation.tr("The message was not sent. Open the chat to see why."));
        }

        function onSubmissionCancelled(submissionId, reason) {
            if (!root._mine(submissionId))
                return;
            root._end("cancelled", String(reason ?? ""));
        }

        function onResponseFinished(result) {
            // Not the terminal edge — rounds over tool calls fire this too —
            // but it carries the model's own error kind, and that is the
            // text worth showing the moment the run stops.
            if (!root.awaiting || root.runId.length === 0)
                return;
            if (String(result?.runId ?? "") !== root.runId)
                return;
            if (String(result?.errorKind ?? "").length > 0)
                root._lastError = Translation.tr("The model could not finish. Open the chat to see why.");
        }
    }

    property string _lastError: ""

    Connections {
        target: Ai.runCoordinator

        function onRunFinished(run) {
            if (!root.awaiting || root.runId.length === 0)
                return;
            if (String(run?.runId ?? "") !== root.runId)
                return;
            const state = String(run?.state ?? "");
            if (state === "completed") {
                root._end("completed", root._lastError);
                return;
            }
            root._end(state, state === "cancelled" ? "" : Translation.tr("The run stopped before answering. Open the chat to see why."));
        }
    }

    Connections {
        target: Ai.modesIntegration

        function onCreated(kind, id, name, sessionId) {
            // Global single-run invariant (submit refuses while a run or a
            // shared task is alive) makes a signal arriving while awaiting
            // ours; the session id is recorded as belt and braces.
            if (!root.awaiting)
                return;
            if (root.sessionId.length > 0 && String(sessionId ?? "").length > 0 && String(sessionId) !== root.sessionId)
                return;
            root.creation = { kind: String(kind), id: String(id), name: String(name) };
        }
    }

    /**
     * The hop to the transcript holding this request: the overlay closes
     * (it sits above everything) and the router opens the chat on the run's
     * own session. It lives here because this file is the only place in the
     * Modes module allowed to read `Ai`.
     */
    function openChat(): void {
        GlobalStates.modesOpen = false;
        Ai.surfaceRouter.open({
            surface: "sidebar",
            sessionId: root.sessionId,
            focusIntent: "transcript",
        });
    }
}
