pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.services.ai
import qs.services.ai.integrations

/**
 * Handles LLM chats: the conversation, the tools, and which model answers.
 *
 * Three wire formats are spoken, one strategy each: Google's Gemini API,
 * Anthropic's /v1/messages, and the OpenAI-compatible /v1/chat/completions
 * that OpenRouter, DeepSeek, Mistral and Ollama all serve. Which one a model
 * uses is its own `api_format`; nothing here tests provider names.
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openAiCompatStrategy: OpenAiCompatStrategy {}
    property Component anthropicApiStrategy: AnthropicApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    /** Structured terminal event consumed by sidebar, Search and background attention. */
    signal responseFinished(var result)
    signal submissionStateChanged(var submission)
    signal submissionStarted(string submissionId, string runId, string sessionId)
    signal submissionFailed(string submissionId, string operationId, string errorCode, var recoveryActionIds)
    signal submissionCancelled(string submissionId, string reason)
    readonly property bool isGenerating: requester.running || root.pendingSubmissionId.length > 0
    /** Central AI availability contract shared by every host. */
    readonly property int aiPolicy: Number(Config.options?.policies?.ai ?? 1)
    readonly property bool enabled: root.aiPolicy !== 0
    readonly property bool onlineAllowed: root.aiPolicy === 1
    readonly property bool localOnly: root.aiPolicy === 2
    readonly property bool hasSelectableModel: root.catalog.modelIds.length > 0

    function canSubmit(modelId = ""): var {
        if (!root.enabled)
            return {
                allowed: false,
                reason: "disabled",
                recoveryActionIds: ["open-ai-policy"]
            };

        const id = String(modelId ?? "").trim() || root.currentModelId;
        const model = root.catalog.models[id] ?? null;
        if (!model)
            return {
                allowed: false,
                reason: "model-unavailable",
                recoveryActionIds: ["open-models"]
            };

        if (root.localOnly && !root.catalog.isModelLocal(model))
            return {
                allowed: false,
                reason: "remote-model-blocked",
                recoveryActionIds: ["open-models"]
            };

        if (model.requires_key && !KeyringStorage.loaded)
            return {
                allowed: false,
                reason: "keyring-loading",
                recoveryActionIds: ["retry-submit"]
            };

        if (model.requires_key && !(root.apiKeys?.[model.key_id]?.length > 0))
            return {
                allowed: false,
                reason: "missing-key",
                recoveryActionIds: ["open-keys"]
            };

        return {
            allowed: true,
            reason: "",
            recoveryActionIds: []
        };
    }

    function enforcePolicy() {
        root.runCoordinator.cancelByPolicy(root.localOnly);
        const blocksTransport = transport => transport.running && (!root.enabled || (root.localOnly && transport.model && !root.catalog.isModelLocal(transport.model)));
        if (blocksTransport(requester))
            root.stopGeneration();
        if (blocksTransport(keyTester))
            keyTester.abort();
        if (blocksTransport(titleRequester))
            titleRequester.abort();
        if (!root.onlineAllowed && commandExecutionProc.running)
            commandExecutionProc.running = false;
        if (!root.onlineAllowed && root.toolOverride === "search")
            root.toolOverride = "";
    }

    onAiPolicyChanged: root.enforcePolicy()

    // These are singletons owned by the facade. Visual hosts only observe
    // their projections; they never create a second repository or run slot.
    readonly property AiConversationRepository conversations: AiConversationRepository {}
    readonly property AiSurfaceRouter surfaceRouter: AiSurfaceRouter {}
    readonly property AiDraftStore draftStore: AiDraftStore {
        directory: Directories.aiDrafts
        scriptPath: Directories.aiDraftsScriptPath
        onStoreReady: root.onDraftStoreReady()
        onStoreError: reason => root.submissionNotice = reason
    }
    readonly property AiRunCoordinator runCoordinator: AiRunCoordinator {
        onRunStarted: run => root.onRunStarted(run)
        onRunActivity: (run, event) => root.onRunActivity(run, event)
        onRunFinished: run => root.onRunFinished(run)
    }
    property string currentRunId: ""
    property string currentRunSessionId: ""
    property string currentRunRequestId: ""
    property string currentRunResponseId: ""
    property var runningMessageIDs: []
    property var runningMessageByID: ({})
    property var pendingRunJournal: null
    property int submissionSequence: 0
    property string pendingSubmissionId: ""
    property var pendingSubmission: null
    property string submissionNotice: ""
    property int draftRevision: 0
    property bool restoringDraft: false
    // Draft edits may happen before the isolated file has completed its first
    // asynchronous load. Keep those mutations (including a deliberate clear)
    // until the loaded snapshot is available, otherwise late hydration can
    // bring an already-sent prompt back into the composer.
    property var pendingDraftMutations: ({})

    onDraftChanged: {
        root.draftRevision += 1;
        if (!root.restoringDraft)
            root.writeOrStageDraft(root.sessionDraftId(), root.draft);
    }

    function submissionOperationId(prefix) {
        root.submissionSequence += 1;
        return `${prefix}-${Date.now()}-${root.submissionSequence}`;
    }

    function rejectSubmission(errorCode, userMessage, recoveryActionIds) {
        root.submissionNotice = userMessage;
        root.submissionFailed("", "", errorCode, recoveryActionIds ?? []);
        root.addMessage(userMessage, root.interfaceRole, {
            "notice": "submission",
            "errorKind": errorCode
        });
        return {
            accepted: false,
            state: "rejected",
            errorCode: errorCode,
            userMessage: userMessage,
            recoveryActionIds: recoveryActionIds ?? []
        };
    }

    /**
     * Clears a command draft only after the command itself was accepted.
     * Network submissions use the correlated submissionStarted signal instead;
     * this helper is intentionally for local slash actions with no run.
     */
    function clearDraftIfCurrent(expectedText = ""): bool {
        const expected = String(expectedText ?? "");
        if (expected.length > 0 && String(root.draft ?? "") !== expected)
            return false;
        root.draft = "";
        return true;
    }

    /**
     * Synchronous submit contract. It only validates immutable input and
     * reserves the one global pending slot; keyring and disk work continue
     * through correlated signals below.
     */
    function submit(text, context = null, source = "unknown") {
        const prompt = String(text ?? "");
        const files = Array.isArray(context?.attachments) ? context.attachments.slice() : root.attachments.slice();
        if (prompt.trim().length === 0 && files.length === 0)
            return root.rejectSubmission("empty-input", Translation.tr("Write a question or attach a file first."), ["focus-composer"]);
        if (root.pendingSubmissionId.length > 0 || requester.running || (root.runCoordinator.activeRunId.length > 0 && root.runCoordinator.activeStates.includes(root.runCoordinator.runFor(root.runCoordinator.activeRunId)?.state)))
            return root.rejectSubmission("busy", Translation.tr("AI is busy with another conversation. Open or stop the active run first."), ["open-active-run", "stop-active-run"]);

        const modelId = root.currentModelId;
        const model = root.catalog.models[modelId] ?? null;
        const profile = root.responseProfileForModel(modelId);
        const attachmentProblem = root.attachmentRejectionForModel(files, model);
        if (attachmentProblem.length > 0)
            return root.rejectSubmission("attachment-incompatible", attachmentProblem, ["open-models", "remove-attachment"]);
        const permission = root.canSubmit(modelId);
        const waitingForKeyring = !!model && model.requires_key && !KeyringStorage.loaded;
        if (!permission.allowed && !waitingForKeyring)
            return root.rejectSubmission(permission.reason || "unavailable", Translation.tr("This AI model is not ready to receive a message."), permission.recoveryActionIds ?? ["open-models"]);

        root.submissionSequence += 1;
        const submissionId = `submission-${Date.now()}-${root.submissionSequence}`;
        const pending = {
            submissionId: submissionId,
            operationId: root.submissionOperationId("submit"),
            source: String(source ?? "unknown"),
            text: prompt,
            attachments: files,
            modelId: modelId,
            responseMode: profile.responseMode,
            webMode: profile.webMode,
            functionExposure: profile.functionExposure,
            thinkingLevel: profile.thinkingLevel,
            temperature: root.temperature,
            systemPrompt: root.systemPrompt,
            toolOverride: profile.toolMode,
            profileFallback: profile.fallbackReason,
            profile: profile,
            draftRevisionAtSubmit: root.draftRevision,
            draftSessionId: root.sessionDraftId(),
            draftTextAtSubmit: root.draft,
            beforeSessionId: root.sessions.currentId,
            beforeSessionCreatedAt: root.sessionCreatedAt,
            baseMessageIDs: root.messageIDs.slice(),
            insertedIds: [],
            insertedObjects: ({}),
            state: waitingForKeyring ? "waitingKeyring" : "pending",
            cancelRequested: false,
            deferJournal: true
        };
        root.pendingSubmissionId = submissionId;
        root.pendingSubmission = pending;
        root.submissionStateChanged(pending);
        if (waitingForKeyring)
            KeyringStorage.fetchKeyringData();
        else
            Qt.callLater(root.resumePendingSubmission);
        return {
            accepted: true,
            submissionId: submissionId,
            operationId: pending.operationId,
            state: "pending"
        };
    }

    function resumePendingSubmission() {
        const pending = root.pendingSubmission;
        if (!pending || pending.submissionId !== root.pendingSubmissionId || pending.cancelRequested)
            return;
        if (pending.state === "preparing" || pending.state === "staging" || pending.state === "durableNotStarted" || pending.state === "networkStarting" || pending.state === "started")
            return;
        const model = root.catalog.models[pending.modelId] ?? null;
        const permission = root.canSubmit(pending.modelId);
        if (!permission.allowed) {
            if (permission.reason === "keyring-loading")
                return;
            root.failPendingSubmission(permission.reason || "unavailable", Translation.tr("This AI model is no longer available."), permission.recoveryActionIds ?? ["open-models"]);
            return;
        }
        if (!model || (root.sessions.currentId !== pending.beforeSessionId)) {
            root.failPendingSubmission("session-changed", Translation.tr("The chat changed while the request was preparing. Nothing was sent."), ["retry-submit"]);
            return;
        }
        for (let i = 0; i < pending.baseMessageIDs.length; i++) {
            if (root.messageIDs[i] !== pending.baseMessageIDs[i]) {
                root.failPendingSubmission("conversation-changed", Translation.tr("The conversation changed while the request was preparing. Nothing was sent."), ["retry-submit"]);
                return;
            }
        }
        pending.state = "preparing";
        root.submissionStateChanged(pending);
        Qt.callLater(() => {
            if (root.pendingSubmissionId === pending.submissionId)
                root.preparePendingSubmission(pending);
        });
    }

    function preparePendingSubmission(pending) {
        if (!pending || root.pendingSubmissionId !== pending.submissionId || pending.cancelRequested)
            return;
        if (root.sessions.currentId.length === 0) {
            root.sessions.currentId = root.sessions.newId();
            root.sessionCreatedAt = Date.now();
        }
        if (root.sessions.currentId !== pending.beforeSessionId && pending.beforeSessionId.length > 0) {
            root.failPendingSubmission("session-changed", Translation.tr("The chat changed while the request was preparing. Nothing was sent."), ["retry-submit"]);
            return;
        }
        pending.sessionId = root.sessions.currentId;
        const user = root.aiMessageComponent.createObject(root, {
            "role": "user",
            "createdAt": Date.now(),
            "completedAt": Date.now(),
            "content": pending.text.length > 0 ? pending.text : Translation.tr("(see attached)"),
            "rawContent": pending.text.length > 0 ? pending.text : Translation.tr("(see attached)"),
            "attachments": pending.attachments,
            "thinking": false,
            "done": true
        });
        const userId = root.idForMessage(user);
        pending.userMessageId = userId;
        pending.insertedIds = [userId];
        pending.insertedObjects[userId] = user;
        // The map is filled before the list is published: anything
        // watching `messageIDs` synchronously — the Search transcript
        // does — would otherwise look the new id up in a map that does
        // not hold it yet and drop the turn until something else
        // refreshed it.
        root.messageByID[userId] = user;
        root.messageIDs = [...root.messageIDs, userId];
        root.makeRequest(pending);
    }

    function rollbackPendingMessages(pending) {
        if (!pending)
            return;
        const removed = pending.insertedIds ?? [];
        for (let i = 0; i < removed.length; i++) {
            const id = removed[i];
            if (root.messageByID[id] !== pending.insertedObjects[id])
                continue;
            const message = root.messageByID[id];
            delete root.messageByID[id];
            root.messageIDs = root.messageIDs.filter(item => item !== id);
            message.destroy();
        }
        pending.insertedIds = [];
        if (pending.beforeSessionId.length === 0 && root.messageIDs.length === 0 && root.sessions.currentId === pending.sessionId) {
            root.sessions.currentId = "";
            root.sessionCreatedAt = pending.beforeSessionCreatedAt;
        }
    }

    function finishPendingSubmission(pending, cancelled, reason) {
        if (!pending || root.pendingSubmissionId !== pending.submissionId)
            return;
        compensationRetryTimer.stop();
        root.cancelContextCompaction();
        const run = pending.runId ? root.runCoordinator.runFor(pending.runId) : null;
        if (run && !root.runCoordinator.terminalStates.includes(run.state))
            root.runCoordinator.finish(pending.runId, "cancelled", cancelled ? "cancelled" : "submissionFailed");
        root.rollbackPendingMessages(pending);
        if (pending.beforeSessionId.length === 0 && root.sessions.currentId === pending.sessionId) {
            root.sessions.currentId = "";
            root.sessionCreatedAt = pending.beforeSessionCreatedAt;
        }
        root.pendingSubmission = null;
        root.pendingSubmissionId = "";
        root.restoreDraftAfterFailedSubmission(pending);
        root.submissionNotice = cancelled ? Translation.tr("Message cancelled before it was sent.") : (pending.errorMessage ?? Translation.tr("The message could not be sent."));
        root.submissionStateChanged({
            submissionId: pending.submissionId,
            state: cancelled ? "cancelled" : "failed",
            reason: reason
        });
        if (cancelled)
            root.submissionCancelled(pending.submissionId, reason);
        else
            root.submissionFailed(pending.submissionId, pending.operationId ?? "", reason, pending.recoveryActionIds ?? []);
    }

    /**
     * Puts a rolled-back prompt back in the composer.
     *
     * The draft is cleared once the request is on the wire, which is right —
     * up to the point where the submission fails *after* that and
     * `rollbackPendingMessages` takes the turn back out of the transcript.
     * What was left then was nothing at all: no message, no chat, and the
     * typed text gone with them. Restoring is only safe while the composer
     * is still empty; a prompt already being typed is newer than this one and
     * must never be overwritten by it.
     */
    function restoreDraftAfterFailedSubmission(pending) {
        const text = String(pending?.draftTextAtSubmit ?? "");
        if (text.length === 0 || root.draft.length > 0)
            return;
        root.draft = text;
        root.draftRestored(text);
    }

    function failPendingSubmission(errorCode, userMessage, recoveryActionIds) {
        const pending = root.pendingSubmission;
        if (!pending || pending.state === "compensating")
            return;
        pending.errorCode = errorCode;
        pending.errorMessage = userMessage;
        pending.recoveryActionIds = recoveryActionIds ?? [];
        pending.cancelRequested = true;
        pending.state = "compensating";
        pending.compensationAttempts = Number(pending.compensationAttempts ?? 0);
        root.submissionStateChanged(pending);
        const pendingRun = pending.runId ? root.runCoordinator.runFor(pending.runId) : null;
        if (pendingRun && !root.runCoordinator.terminalStates.includes(pendingRun.state))
            root.runCoordinator.finish(pending.runId, "cancelled", "submissionFailed");
        root.rollbackPendingMessages(pending);
        if (pending.stateBeforeCompensation === "durableNotStarted" || pending.stateBeforeCompensation === "networkStarting" || pending.stateBeforeCompensation === "started") {
            const snapshot = root.messageIDs.length > 0 ? root.sessionToJson() : null;
            if (snapshot) {
                pending.compensationSnapshot = snapshot;
                pending.compensationOperationId = root.sessions.commit(snapshot, root.submissionOperationId("compensate"), true);
                if (pending.compensationOperationId)
                    return;
            }
        }
        if (pending.stageOperationId) {
            pending.abortOperationId = root.sessions.abortSubmission(pending.sessionId, pending.stageOperationId, root.submissionOperationId("abort"));
            if (pending.abortOperationId)
                return;
        }
        root.finishPendingSubmission(pending, false, errorCode);
    }

    function cancelPendingSubmission(reason = "cancelled") {
        const pending = root.pendingSubmission;
        if (!pending)
            return false;
        pending.cancelRequested = true;
        pending.stateBeforeCompensation = pending.state;
        pending.cancelReason = reason;
        root.failPendingSubmission("cancelled", Translation.tr("Message cancelled before it was sent."), []);
        return true;
    }

    function handleSubmissionStageSucceeded(operationId, sessionId) {
        const pending = root.pendingSubmission;
        if (!pending || pending.stageOperationId !== operationId || pending.sessionId !== sessionId)
            return;
        if (pending.cancelRequested) {
            pending.stateBeforeCompensation = "durableNotStarted";
            root.failPendingSubmission("cancelled", Translation.tr("Message cancelled before it was sent."), []);
            return;
        }
        pending.state = "durableNotStarted";
        root.submissionStateChanged(pending);
        pending.commitOperationId = root.sessions.commitSubmissionForDispatch(sessionId, operationId, root.submissionOperationId("commit"));
    }

    function handleSubmissionCommitSucceeded(operationId, sessionId) {
        const pending = root.pendingSubmission;
        if (!pending || pending.commitOperationId !== operationId || pending.sessionId !== sessionId)
            return;
        if (pending.cancelRequested) {
            pending.stateBeforeCompensation = "durableNotStarted";
            root.failPendingSubmission("cancelled", Translation.tr("Message cancelled before it was sent."), []);
            return;
        }
        pending.state = "networkStarting";
        root.runCoordinator.transition(pending.runId, "thinking", "networkStarting", { "executionStarted": false });
        const snapshot = root.sessionToJson();
        pending.networkOperationId = root.sessions.commit(snapshot, root.submissionOperationId("network-start"), true);
        root.submissionStateChanged(pending);
    }

    function handleSubmissionSaveSucceeded(operationId, sessionId) {
        const pending = root.pendingSubmission;
        if (!pending || pending.networkOperationId !== operationId || pending.sessionId !== sessionId)
            if (!pending || pending.compensationOperationId !== operationId || pending.sessionId !== sessionId)
                return;
        if (pending.compensationOperationId === operationId) {
            pending.compensationOperationId = "";
            if (pending.stageOperationId) {
                pending.abortOperationId = root.sessions.abortSubmission(sessionId, pending.stageOperationId, root.submissionOperationId("abort"));
                if (pending.abortOperationId)
                    return;
            }
            root.finishPendingSubmission(pending, pending.cancelReason === "user", "compensated");
            return;
        }
        root.dispatchPendingSubmission(pending);
    }

    function dispatchPendingSubmission(pending) {
        if (!pending || root.pendingSubmissionId !== pending.submissionId)
            return;
        if (pending.cancelRequested || !root.canSubmit(pending.modelId).allowed) {
            pending.stateBeforeCompensation = "networkStarting";
            root.failPendingSubmission("cancelled", Translation.tr("Message cancelled before it was sent."), []);
            return;
        }
        pending.state = "started";
        pending.deferJournal = false;
        root.runCoordinator.transition(pending.runId, "thinking", "networkStarted", {
            // Network I/O is recoverable; only an acknowledged tool/config
            // checkpoint sets executionStarted and requires inspection after
            // a restart.
            "executionStarted": false,
            "networkStartedAt": Date.now()
        });
        const prepared = pending.prepared;
        requester.model = prepared.model;
        requester.strategy = prepared.strategy;
        requester.message = prepared.message;
        requester.endpoint = prepared.endpoint;
        requester.requestData = prepared.requestData;
        requester.apiKey = prepared.apiKey;
        requester.parsedAny = false;
        const started = requester.start();
        if (!started) {
            pending.stateBeforeCompensation = "networkStarting";
            root.failPendingSubmission("request-start-failed", Translation.tr("The request could not be started."), ["retry-submit"]);
            return;
        }

        if (root.draftRevision === pending.draftRevisionAtSubmit) {
            root.draft = "";
            root.clearDraftForSession(pending.draftSessionId, pending.draftTextAtSubmit);
        }
        root.clearAttachments();
        root.submissionStateChanged(pending);
        root.submissionStarted(pending.submissionId, pending.runId, pending.sessionId);

        // The durable submit transaction ends when the requester accepts the
        // run. From here on, the run coordinator owns lifecycle and the
        // session may be changed without rolling back the live response.
        root.pendingSubmission = null;
        root.pendingSubmissionId = "";
    }

    function handleSubmissionSaveFailed(operationId, sessionId, reason) {
        const pending = root.pendingSubmission;
        if (!pending)
            return;
        if (pending.compensationOperationId === operationId) {
            pending.compensationOperationId = "";
            pending.compensationAttempts = Number(pending.compensationAttempts ?? 0) + 1;
            pending.compensationLastError = reason;
            pending.state = "compensating";
            root.submissionNotice = Translation.tr("The failed message is being rolled back; retrying its local journal.");
            root.submissionStateChanged(pending);
            compensationRetryTimer.interval = Math.min(8000, 1000 * Math.pow(2, Math.max(0, pending.compensationAttempts - 1)));
            compensationRetryTimer.restart();
            return;
        }
        if (pending.networkOperationId === operationId || pending.stageOperationId === operationId) {
            pending.stateBeforeCompensation = pending.state;
            root.failPendingSubmission("save-failed", Translation.tr("The message was not saved, so it was not sent."), ["retry-submit"]);
        }
    }

    function handleSubmissionStageFailed(operationId, sessionId, reason) {
        const pending = root.pendingSubmission;
        if (!pending || pending.stageOperationId !== operationId || pending.sessionId !== sessionId)
            return;
        pending.stateBeforeCompensation = "staging";
        root.finishPendingSubmission(pending, pending.cancelRequested, reason);
    }

    function handleSubmissionCommitFailed(operationId, sessionId, reason) {
        const pending = root.pendingSubmission;
        if (!pending || pending.commitOperationId !== operationId || pending.sessionId !== sessionId)
            return;
        pending.stateBeforeCompensation = "durableNotStarted";
        root.failPendingSubmission("save-failed", Translation.tr("The message was not saved, so it was not sent."), ["retry-submit"]);
    }

    function handleSubmissionAbortFinished(operationId, sessionId, reason) {
        const pending = root.pendingSubmission;
        if (!pending || pending.abortOperationId !== operationId || pending.sessionId !== sessionId)
            return;
        root.finishPendingSubmission(pending, pending.cancelReason === "user", reason);
    }

    function retryCompensation() {
        const pending = root.pendingSubmission;
        if (!pending || pending.state !== "compensating" || pending.compensationOperationId || !pending.compensationSnapshot)
            return;
        pending.compensationOperationId = root.sessions.commit(
            pending.compensationSnapshot,
            root.submissionOperationId("compensate-retry"),
            true
        );
        if (!pending.compensationOperationId) {
            compensationRetryTimer.interval = Math.min(8000, Math.max(1000, compensationRetryTimer.interval * 2));
            compensationRetryTimer.restart();
        }
    }

    Timer {
        id: compensationRetryTimer
        interval: 1500
        repeat: false
        onTriggered: root.retryCompensation()
    }

    Connections {
        target: KeyringStorage
        function onLoadedChanged() {
            if (KeyringStorage.loaded)
                root.resumePendingSubmission();
        }
    }

    function journalRun(sessionId: string, run: var) {
        root.pendingRunJournal = {
            sessionId: sessionId,
            run: run
        };
        root.scheduleRunJournal();
    }

    // Journal at the leading edge, then at most once per interval while a
    // stream is active. A trailing-only debounce lost the whole run whenever
    // chunks arrived faster than the debounce window.
    function scheduleRunJournal() {
        if (runJournalTimer.running)
            return;
        root.flushRunJournal();
        runJournalTimer.start();
    }

    function flushRunJournal() {
        const pending = root.pendingRunJournal;
        root.pendingRunJournal = null;
        if (!pending)
            return "";
        return root.commitRunSession(pending.sessionId, false);
    }

    function onRunStarted(run: var) {
        root.conversations.setRun(run.sessionId, run);
        const pending = root.pendingSubmission;
        if (pending && pending.submissionId === root.pendingSubmissionId && pending.sessionId === run.sessionId && pending.deferJournal) {
            pending.runPreview = run;
            return;
        }
        root.pendingRunJournal = {
            sessionId: run.sessionId,
            run: run
        };
        root.scheduleRunJournal();
    }

    function onRunActivity(run: var, event: var) {
        root.conversations.setRun(run.sessionId, run);
        const pending = root.pendingSubmission;
        if (pending && pending.submissionId === root.pendingSubmissionId && pending.sessionId === run.sessionId && pending.deferJournal)
            return;
        if (run.sessionId === root.currentRunSessionId && root.runningMessageIDs.length > 0)
            root.conversations.capture(run.sessionId, root.runningSessionToJson());
        root.pendingRunJournal = {
            sessionId: run.sessionId,
            run: run
        };
        root.scheduleRunJournal();
    }

    function onRunFinished(run: var) {
        root.conversations.setRun(run.sessionId, run);
        const pending = root.pendingSubmission;
        // An approval card is shown after the provider round has ended. Keep
        // the run id attached to that card until the broker receives the
        // user's decision; otherwise the card's click cannot be journalled
        // back to the run that created it.
        const waitingOnApproval = root.broker.pendingCount > 0;
        if (pending && pending.submissionId === root.pendingSubmissionId && pending.sessionId === run.sessionId && pending.state !== "started") {
            root.pendingRunJournal = null;
            if (root.currentRunId === run.runId && !waitingOnApproval)
                root.currentRunId = "";
            if (run.resultReason === "cancelledByPolicy" || run.resultReason === "disabledByPolicy") {
                pending.stateBeforeCompensation = pending.state;
                root.failPendingSubmission("policy-changed", Translation.tr("The AI policy changed before this message was sent."), ["retry-submit"]);
            }
            return;
        }
        if (run.sessionId === root.currentRunSessionId && root.runningMessageIDs.length > 0)
            root.conversations.capture(run.sessionId, root.runningSessionToJson());
        root.pendingRunJournal = null;
        runJournalTimer.stop();
        root.commitRunSession(run.sessionId, true);
        if (root.currentRunId === run.runId && !waitingOnApproval)
            root.currentRunId = "";
        if (pending && pending.submissionId === root.pendingSubmissionId && pending.sessionId === run.sessionId) {
            root.pendingSubmission = null;
            root.pendingSubmissionId = "";
        }
    }

    function commitRunSession(sessionId: string, flushNow = false) {
        const id = String(sessionId ?? "");
        if (!id)
            return "";
        if (id === root.sessions.currentId) {
            return root.commitSession(flushNow);
        }
        if (id === root.currentRunSessionId && root.runningMessageIDs.length > 0)
            root.conversations.capture(id, root.runningSessionToJson());
        const snapshot = root.conversations.snapshot(id);
        if (snapshot)
            return root.sessions.commit(snapshot, "", flushNow);
        return "";
    }

    Timer {
        id: runJournalTimer
        interval: 700
        repeat: true
        onTriggered: {
            root.flushRunJournal();
            if (!root.pendingRunJournal)
                runJournalTimer.stop();
        }
    }

    // Set while a failed request waits to be sent again, so the UI can say so
    // instead of looking stuck.
    property string retryNotice: ""
    property string retryMessageId: ""
    property int retryAttempt: 0
    property int retryDelaySeconds: 0
    // A tool exchange asked for another turn while the current one was still
    // streaming. Sent as soon as it ends.
    property bool followUpQueued: false
    /** Tool calls returned in one assistant turn, waiting for their turn. */
    property var pendingToolCalls: []
    property string activeToolCallId: ""
    /** One irreversible tool effect may wait for a durable journal ACK. */
    property var pendingToolExecution: null
    /** SongRec stays in flight until it identifies a track or stops. */
    property var pendingSongIdentify: null
    property int toolExecutionSequence: 0
    // Session-owned metadata that survives a Search/sidebar handoff and a
    // restart. Message-level arrays remain the rich-rendering source.
    property list<string> sessionSearchQueries: []
    property var sessionSources: []
    property var sessionToolCheckpoints: []
    // Web reads are short-lived and keyed by request shape. Keeping this in
    // the facade avoids a second network request when the model asks to cite
    // the same result immediately after a search, without persisting web
    // content to disk.
    property var webCache: ({})
    readonly property int webCacheTtlMs: 120000
    readonly property int webCacheMaxEntries: 32

    function recordToolCheckpoint(entry: var) {
        if (!entry || entry.serial === undefined)
            return;
        const sessionId = root.currentRunSessionId || root.sessions.currentId;
        const visible = sessionId === root.sessions.currentId;
        const snapshot = visible ? null : root.conversations.snapshot(sessionId);
        const current = Array.from(visible ? (root.sessionToolCheckpoints ?? []) : (snapshot?.toolCheckpoints ?? []));
        const index = current.findIndex(item => item.serial === entry.serial);
        const nextEntry = Object.assign({}, entry, {
            sessionId: sessionId
        });
        if (index >= 0)
            current[index] = nextEntry;
        else
            current.push(nextEntry);
        const checkpoints = current.slice(-100);
        if (visible) {
            root.sessionToolCheckpoints = checkpoints;
            root.sessions.scheduleSave();
        } else if (snapshot) {
            root.conversations.capture(sessionId, Object.assign({}, snapshot, {
                toolCheckpoints: checkpoints,
                updatedAt: Date.now()
            }));
            root.commitRunSession(sessionId, false);
        }
    }

    function updateSessionGrounding(message: AiMessageData, sessionId = "") {
        if (!message)
            return;
        const targetSessionId = String(sessionId || root.currentRunSessionId || root.sessions.currentId);
        const visible = targetSessionId === root.sessions.currentId;
        const snapshot = visible ? null : root.conversations.snapshot(targetSessionId);
        let sessionQueries = Array.from(visible ? root.sessionSearchQueries : (snapshot?.searchQueries ?? []));
        let sessionSources = Array.from(visible ? root.sessionSources : (snapshot?.sources ?? []));
        const queries = Array.from(message.searchQueries ?? []).map(value => String(value)).filter(value => value.length > 0);
        if (queries.length > 0)
            sessionQueries = [...new Set([...sessionQueries, ...queries])].slice(-50);
        const incoming = Array.from(message.annotationSources ?? []);
        if (incoming.length > 0) {
            const byUrl = {};
            sessionSources.concat(incoming).forEach(source => {
                const url = String(source?.url ?? "");
                const key = url.length > 0 ? url : JSON.stringify(source);
                byUrl[key] = source;
            });
            sessionSources = Object.values(byUrl).slice(-100);
        }
        if (visible) {
            root.sessionSearchQueries = sessionQueries;
            root.sessionSources = sessionSources;
        } else if (snapshot) {
            root.conversations.capture(targetSessionId, Object.assign({}, snapshot, {
                searchQueries: sessionQueries,
                sources: sessionSources,
                updatedAt: Date.now()
            }));
            root.commitRunSession(targetSessionId, false);
        }
    }

    function webCacheKey(isSearch: bool, term: string, count: int): string {
        return (isSearch ? "search:" : "fetch:") + String(term).trim().toLowerCase() + (isSearch ? `:${count}` : "");
    }

    function cacheWebPayload(key: string, payload: var): var {
        const cached = Object.assign({}, payload, {
            freshness: "cached",
            cacheHit: true
        });
        if (Array.isArray(cached.results)) {
            cached.results = cached.results.map(result => Object.assign({}, result, {
                freshness: "cached",
                cacheHit: true,
                fetchedAt: result.fetchedAt ?? cached.fetchedAt
            }));
        }
        const next = Object.assign({}, root.webCache, {
            [key]: { createdAt: Date.now(), payload: cached }
        });
        const keys = Object.keys(next).sort((a, b) => next[a].createdAt - next[b].createdAt).slice(-root.webCacheMaxEntries);
        const bounded = ({});
        keys.forEach(entryKey => bounded[entryKey] = next[entryKey]);
        root.webCache = bounded;
        return cached;
    }

    function decorateWebPayload(payload: var, isSearch: bool): var {
        const observedAt = new Date().toISOString();
        const decorated = Object.assign({}, payload, {
            source: String(payload?.source ?? payload?.engine ?? "web"),
            fetchedAt: String(payload?.fetchedAt ?? observedAt),
            freshness: String(payload?.freshness ?? "live"),
            cacheHit: payload?.cacheHit === true
        });
        if (isSearch && Array.isArray(payload?.results)) {
            decorated.results = payload.results.map(result => Object.assign({}, result, {
                source: String(result?.source ?? payload?.engine ?? "web"),
                fetchedAt: String(result?.fetchedAt ?? decorated.fetchedAt),
                freshness: String(result?.freshness ?? decorated.freshness),
                cacheHit: result?.cacheHit === true || decorated.cacheHit === true
            }));
        } else if (!isSearch) {
            const url = String(payload?.url ?? "");
            const hostMatch = url.match(/^[a-z]+:\/\/([^/]+)/i);
            decorated.source = String(payload?.source ?? (hostMatch ? hostMatch[1] : "web"));
        }
        return decorated;
    }

    function freshWebCache(key: string): var {
        const entry = root.webCache[String(key)];
        if (!entry || Date.now() - Number(entry.createdAt ?? 0) > root.webCacheTtlMs)
            return null;
        return entry.payload ?? null;
    }

    function recordWebSources(payload: var): void {
        if (!payload)
            return;
        const entries = Array.isArray(payload.results) ? payload.results : [payload];
        const byUrl = ({});
        Array.from(root.sessionSources ?? []).forEach(source => {
            const url = String(source?.url ?? "");
            if (url.length > 0)
                byUrl[url] = source;
        });
        entries.forEach(source => {
            const url = String(source?.url ?? "");
            if (url.length === 0)
                return;
            byUrl[url] = {
                url: url,
                text: String(source.title ?? source.url ?? ""),
                source: String(source.source ?? payload.source ?? payload.engine ?? "web"),
                fetchedAt: String(source.fetchedAt ?? payload.fetchedAt ?? ""),
                freshness: String(source.freshness ?? payload.freshness ?? "live"),
                cacheHit: source.cacheHit === true || payload.cacheHit === true
            };
        });
        root.sessionSources = Object.values(byUrl).slice(-100);
    }

    /**
     * What the model is told before anything else, with the values filled in.
     *
     * Three places can hold a prompt and the nearest one wins: what this chat
     * was given, then the persona in force, then the one in the settings. A
     * chat that was opened with a prompt keeps answering the way it did, even
     * if the persona has moved on since.
     */
    readonly property string systemPrompt: {
        // Three things stack, in the order they were chosen: how it should
        // answer, what the project it belongs to is about, and what is
        // already known about the person asking.
        const parts = [root.substituted(root.basePrompt)];
        if (root.projectPrompt.length > 0)
            parts.push(root.projectPrompt);
        // Read defensively: the prompt is evaluated while the singletons are
        // still coming up, and one that is not ready yet is not an error.
        const remembered = String(AiMemory?.promptBlock ?? "");
        if (remembered.length > 0)
            parts.push(remembered);
        return parts.filter(part => String(part).trim().length > 0).join("\n\n");
    }

    readonly property string basePrompt: {
        if (root.promptOverride.length > 0)
            return root.promptOverride;
        const persona = root.personas.byId(root.sessionPersonaId);
        if (persona?.systemPrompt?.length > 0)
            return persona.systemPrompt;
        return Config.options?.ai?.systemPrompt ?? "";
    }

    // ── Projects ──────────────────────────────────────────────────────────
    // A project is a folder with an opinion: chats filed under it share a
    // prompt and, when set, the files that go with every one of them.
    readonly property var projects: Array.from(Config.options?.ai?.projects ?? [])

    function projectById(projectId: string): var {
        const id = String(projectId ?? "");
        if (id.length === 0)
            return null;
        return root.projects.find(project => String(project?.id ?? "") === id) ?? null;
    }

    readonly property var currentProject: root.projectById(root.sessionProjectId)

    readonly property string projectPrompt: {
        const project = root.currentProject;
        const prompt = String(project?.prompt ?? "").trim();
        if (prompt.length === 0)
            return "";
        return `## ${String(project.name ?? Translation.tr("This project"))}\n${root.substituted(prompt)}`;
    }

    function setProject(projectId: string) {
        root.sessionProjectId = String(projectId ?? "");
        if (root.sessions.currentId.length > 0)
            root.sessions.setProject(root.sessions.currentId, root.sessionProjectId);
        root.commitSession();
    }

    /** This chat's own prompt. Saved with it, and empty for most chats. */
    property string promptOverride: ""

    function substituted(text: string): string {
        let prompt = String(text ?? "");
        for (let key in root.promptSubstitutions) {
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})

    /**
     * The user's own prompts in this chat, oldest first — the shell-history
     * source composers read for arrow-key prompt recall (Up/Down from an
     * empty draft), so a question can be resent without retyping it or
     * scrolling back to copy it. Hidden carriers (tool-output turns, the
     * silent "continue" instruction) are not prompts anyone typed.
     */
    readonly property var ownPromptHistory: {
        const list = [];
        for (let i = 0; i < root.messageIDs.length; i++) {
            const message = root.messageByID[root.messageIDs[i]];
            if (message?.role !== "user" || message.visibleToUser === false)
                continue;
            const text = String(message.rawContent ?? message.content ?? "").trim();
            if (text.length > 0)
                list.push(text);
        }
        return list;
    }

    /**
     * A message nobody ever sees a row for: the carrier that hands a tool's
     * output back to the model. It is written with `role: "user"` because
     * that is what the wire format wants, which means plain adjacency in
     * `messageIDs` cannot tell a tool round-trip from a real question.
     */
    function isHiddenCarrier(id: string): bool {
        const message = root.messageByID[id];
        return !!message && message.visibleToUser === false;
    }

    /**
     * Ids of assistant messages followed by another assistant message — an
     * internal continuation mid-exchange (the model called a tool and kept
     * going once the result came back), not a turn of its own. The message
     * that actually answers renders every step that led to it in one
     * accordion; see `leadingActivityMessages()`. Recomputed only when the
     * id list itself changes (a new message arriving), never per streamed
     * token, since streaming mutates a message in place.
     *
     * Adjacency skips hidden carriers. Reading `ids[i + 1]` directly was
     * the bug behind a turn drawing one "Thought for …" row and one model
     * name per tool call: every round-trip puts a carrier between the two
     * assistant messages, so no continuation was ever recognised as one.
     */
    readonly property var nonTerminalRunMessageIds: {
        const ids = root.messageIDs;
        const hidden = {};
        for (let i = 0; i < ids.length; i++) {
            if (root.messageByID[ids[i]]?.role !== "assistant")
                continue;
            let next = i + 1;
            while (next < ids.length && root.isHiddenCarrier(ids[next]))
                next += 1;
            if (next < ids.length && root.messageByID[ids[next]]?.role === "assistant")
                hidden[ids[i]] = true;
        }
        return hidden;
    }

    /**
     * Whether a message gets its own row in the transcript. False for a
     * hidden carrier (`visibleToUser: false`) and for a non-terminal
     * assistant message in a tool round-trip (see above) — the single
     * predicate every transcript host filters `messageIDs` through, so
     * none of them can drift out of step with the others.
     */
    function isTranscriptEntry(id: string): bool {
        const message = root.messageByID[id];
        return !!message && message.visibleToUser !== false && !root.nonTerminalRunMessageIds[id];
    }

    /**
     * The earlier steps of the same exchange as `id`, oldest first — every
     * assistant message before it, for as long as they too are assistant
     * turns. Empty for a question answered in a single turn.
     *
     * Walks back over hidden carriers for the same reason
     * `nonTerminalRunMessageIds` looks past them: a tool round-trip leaves
     * one between every pair of assistant messages, and stopping at the
     * first one left the answering message folding nothing at all.
     */
    function leadingActivityMessages(id: string): var {
        const ids = root.messageIDs;
        const at = ids.indexOf(id);
        if (at <= 0)
            return [];
        const leading = [];
        let i = at - 1;
        while (i >= 0) {
            if (root.isHiddenCarrier(ids[i])) {
                i -= 1;
                continue;
            }
            if (root.messageByID[ids[i]]?.role !== "assistant")
                break;
            leading.unshift(root.messageByID[ids[i]]);
            i -= 1;
        }
        return leading;
    }

    /**
     * The turn that has just arrived, so a transcript can animate its entrance
     * without animating every delegate a ListView recycles while scrolling.
     * Only a list that grew by exactly one counts: loading a saved chat
     * replaces the whole list and is not an arrival.
     */
    property string lastAppendedId: ""
    property real lastAppendedAt: 0
    property int _knownMessageCount: 0
    onMessageIDsChanged: {
        const ids = root.messageIDs;
        const grewByOne = ids.length === root._knownMessageCount + 1;
        root._knownMessageCount = ids.length;
        if (ids.length > root.maxLiveMessages)
            Qt.callLater(root.trimMessageHistoryIfNeeded);
        if (!grewByOne)
            return;
        root.lastAppendedId = String(ids[ids.length - 1] ?? "");
        root.lastAppendedAt = Date.now();
    }

    /**
     * A conversation kept open for enough turns would otherwise grow forever:
     * nothing besides `clearMessages()`/`forkFrom()`/explicit removal ever
     * shrinks the live list, and those only run on a deliberate user action.
     * This is a backstop against a genuinely runaway session — `ai ask`
     * scripted in a loop for hours without ever starting a new chat — not a
     * performance tweak for ordinary use; reaching it already means
     * something unusual is going on. The persisted session file
     * (commitSession) already holds full history on disk, so trimming the
     * live list only frees RAM, never durable state.
     */
    readonly property int maxLiveMessages: 1000

    function trimMessageHistoryIfNeeded() {
        const overflow = root.messageIDs.length - root.maxLiveMessages;
        if (overflow <= 0)
            return;
        // Never trim a message still anchoring the run in flight.
        const keepIds = new Set([root.currentRunRequestId, root.currentRunResponseId].filter(id => id.length > 0));
        const drop = [];
        for (let i = 0; i < root.messageIDs.length && drop.length < overflow; i++) {
            const id = root.messageIDs[i];
            if (!keepIds.has(id))
                drop.push(id);
        }
        if (drop.length === 0)
            return;
        const dropSet = new Set(drop);
        root.messageIDs = root.messageIDs.filter(id => !dropSet.has(id));
        for (const id of drop) {
            const message = root.messageByID[id];
            delete root.messageByID[id];
            if (message)
                message.destroy();
        }
        console.log(`[Ai] Trimmed ${drop.length} old message(s) from a very long live conversation (kept the newest ${root.maxLiveMessages}); the full history remains saved on disk.`);
    }
    on_KnownMessageCountChanged: root.recomputeContextEstimate()

    /** Whether this turn arrived within the last moment, animation aside. */
    function isFreshMessage(messageId: string): bool {
        return String(messageId ?? "").length > 0 && messageId === root.lastAppendedId && (Date.now() - root.lastAppendedAt) < 1200;
    }
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = root.currentModelEntry;
        if (!model || !model.requires_key)
            return true;
        if (!apiKeysLoaded)
            return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook

    /**
     * What this chat has spent, whoever answered.
     *
     * Every turn records its own usage when it finishes, local models
     * included — Ollama reports prompt/eval counts the same way a paid API
     * reports input/output — so one sum covers both. `tokenCount` only ever
     * holds the last turn, which is the size of the context rather than what
     * the chat has cost, and is the fallback when nothing was recorded.
     */
    readonly property int sessionTokenTotal: {
        let total = 0;
        const ids = root.messageIDs;
        for (let i = 0; i < ids.length; i++) {
            const message = root.messageByID[ids[i]];
            if (!message)
                continue;
            if (message.totalTokens > 0) {
                total += message.totalTokens;
                continue;
            }
            const input = message.inputTokens > 0 ? message.inputTokens : 0;
            const output = message.outputTokens > 0 ? message.outputTokens : 0;
            total += input + output;
        }
        if (total > 0)
            return total;
        return Math.max(0, root.tokenCount.total);
    }

    /** Exact charges returned by OpenRouter's terminal usage frames. */
    readonly property real sessionOpenRouterCost: {
        let total = 0;
        let reported = false;
        const ids = root.messageIDs;
        for (let i = 0; i < ids.length; i++) {
            const message = root.messageByID[ids[i]];
            if (!message || !String(message.model ?? "").startsWith("openrouter:"))
                continue;
            const cost = Number(message.requestCost ?? -1);
            if (!isFinite(cost) || cost < 0)
                continue;
            total += cost;
            reported = true;
        }
        return reported ? total : -1;
    }

    // ── Context window ────────────────────────────────────────────────────
    // Nothing here asks a provider anything. A conversation that outgrows the
    // model's window used to be sent whole and refused whole; now the oldest
    // turns are left behind, the transcript says where the cut is, and what
    // was left behind can be replaced by a summary of itself.

    /** Roughly what a piece of text costs. Four characters to a token is the
     * ratio every major tokeniser lands near for prose, and the estimate is
     * only ever used to decide what to leave out. */
    function estimateTokens(text: string): int {
        const value = String(text ?? "");
        if (value.length === 0)
            return 0;
        return Math.ceil(value.length / 4);
    }

    function estimateMessageTokens(message): int {
        if (!message)
            return 0;
        // Reasoning is not resent, but attachments are, and a base64 image is
        // the one thing that dwarfs everything else in a request.
        let total = root.estimateTokens(message.content ?? message.rawContent ?? "");
        const files = Array.from(message.attachments ?? []);
        for (let i = 0; i < files.length; i++) {
            const file = files[i];
            if (file?.kind === "text")
                total += Math.ceil((file.bytes ?? 0) / 4);
            else {
                // Base64 expands bytes by 4/3 and the text heuristic is
                // roughly four characters per token. Keep the estimate
                // conservative; underestimating vision input is more harmful
                // than leaving a little unused context room.
                total += Math.ceil((file.bytes ?? 0) / 3);
            }
        }
        return total;
    }

    /** What the next request would carry, before anyone is charged for it. */
    property int estimatedContextTokens: 0
    property string contextSummary: ""
    /** Stable cut fingerprint for the summary currently in context. */
    property string contextSummaryKey: ""
    /** Id of the first turn that will actually be sent, "" when all of them are. */
    property string contextCutMessageId: ""
    property int prunedTurnCount: 0
    /** At most one compaction may be in flight; it is correlated to a session and cut. */
    property var pendingContextCompaction: null
    property int contextCompactionSequence: 0

    readonly property bool contextManaged: Config.options?.ai?.context?.manage ?? true
    readonly property bool contextSummarises: Config.options?.ai?.context?.summarise ?? true
    /** Room kept for the answer, so the cut is not made at the very edge. */
    readonly property int contextReserve: Math.max(512, Config.options?.ai?.context?.reserveTokens ?? 4096)

    function recomputeContextEstimate() {
        let total = root.estimateTokens(root.systemPrompt) + root.estimateTokens(root.contextSummary);
        const ids = root.messageIDs;
        for (let i = 0; i < ids.length; i++) {
            const message = root.messageByID[ids[i]];
            if (!message || message.role === root.interfaceRole)
                continue;
            total += root.estimateMessageTokens(message);
        }
        root.estimatedContextTokens = total;
    }

    function scheduleContextEstimate() {
        contextEstimateTimer.restart();
    }

    Timer {
        id: contextEstimateTimer
        interval: 120
        repeat: false
        onTriggered: root.recomputeContextEstimate()
    }

    onSystemPromptChanged: root.recomputeContextEstimate()

    onMessageByIDChanged: root.scheduleContextEstimate()

    Connections {
        // Use the singleton as a safe initial target. QML's Connections rejects
        // an undefined QObject target during startup; once a run response id
        // exists the binding switches to that message object.
        target: root.currentRunResponseId.length > 0 ? (root.messageByID[root.currentRunResponseId] ?? root) : root
        ignoreUnknownSignals: true
        function onContentChanged() { root.scheduleContextEstimate(); }
        function onRawContentChanged() { root.scheduleContextEstimate(); }
        function onAttachmentsChanged() { root.scheduleContextEstimate(); }
    }

    function messageIdForObject(message): string {
        if (!message)
            return "";
        const ids = root.messageIDs;
        for (let i = 0; i < ids.length; i++) {
            if (root.messageByID[ids[i]] === message)
                return String(ids[i]);
        }
        return "";
    }

    function contextCompactionKey(pruned: var, model, sessionId = ""): string {
        const ids = Array.from(pruned ?? []).map(message => root.messageIdForObject(message)).filter(id => id.length > 0);
        const fallback = Array.from(pruned ?? []).map(message => `${message?.role ?? ""}:${String(message?.content ?? "").slice(0, 160)}`).join("|");
        return [String(sessionId || root.sessions.currentId), String(model?.id ?? ""), ids.join(",") || fallback].join("|");
    }

    function createApiStrategy(format: string): var {
        const normalized = String(format ?? "openai").toLowerCase();
        if (normalized === "gemini")
            return root.geminiApiStrategy.createObject(root);
        if (normalized === "anthropic")
            return root.anthropicApiStrategy.createObject(root);
        return root.openAiCompatStrategy.createObject(root);
    }

    /**
     * Which turns fit, newest first. The cut always lands on a user turn so
     * the model never opens on an answer to a question it cannot see.
     */
    function historyWithinWindow(messages: var, model): var {
        const all = Array.from(messages ?? []);
        const window = Number(model?.contextWindow ?? 0);
        if (!root.contextManaged || window <= 0)
            return { messages: all, pruned: [], cutId: "", oversized: null };

        const budget = Math.max(1024, window - root.contextReserve - root.estimateTokens(root.systemPrompt) - root.estimateTokens(root.contextSummary));
        let used = 0;
        let firstKept = all.length;
        let oversized = null;
        for (let i = all.length - 1; i >= 0; i--) {
            const cost = root.estimateMessageTokens(all[i]);
            if (used === 0 && cost > budget) {
                oversized = all[i];
                firstKept = i + 1;
                break;
            }
            if (used + cost > budget && firstKept < all.length)
                break;
            used += cost;
            firstKept = i;
        }
        // Never open on an assistant turn: walk forward to the next question.
        while (firstKept > 0 && firstKept < all.length && all[firstKept].role !== "user")
            firstKept += 1;
        if (firstKept <= 0)
            return { messages: all, pruned: [], cutId: "", oversized: oversized };

        const kept = all.slice(firstKept);
        const pruned = all.slice(0, firstKept);
        const cutMessage = kept.length > 0 ? kept[0] : null;
        let cutId = "";
        for (let i = 0; i < root.messageIDs.length; i++) {
            if (root.messageByID[root.messageIDs[i]] === cutMessage) {
                cutId = root.messageIDs[i];
                break;
            }
        }
        return { messages: kept, pruned: pruned, cutId: cutId, oversized: oversized };
    }

    /**
     * Asks the model to fold what was dropped into a paragraph, once, and
     * keeps it with the session. Costs one small request the first time a
     * conversation outgrows its window, and nothing after that.
     */
    function fallbackContextSummary(pruned: var): string {
        return Array.from(pruned ?? [])
            .map(message => `${message?.role ?? "turn"}: ${String(message?.content ?? message?.rawContent ?? "").slice(0, 900)}`)
            .join("\n\n")
            .slice(0, 6000);
    }

    function summarisePruned(pruned: var, model, sessionId = ""): bool {
        if (!root.contextSummarises || summaryRequester.running || !model)
            return false;
        const turns = Array.from(pruned ?? []);
        if (turns.length === 0)
            return false;
        const previousSummary = root.contextSummary.length > 0
            ? `Earlier compacted context:\n${root.contextSummary}\n\n`
            : "";
        const transcript = previousSummary + turns.map(message => `${message.role}: ${String(message.content ?? "").slice(0, 2000)}`).join("\n\n");
        const key = root.contextCompactionKey(turns, model, sessionId);
        const strategy = root.createApiStrategy(model.api_format || "openai");
        if (!strategy)
            return false;
        root.contextCompactionSequence += 1;
        root.pendingContextCompaction = {
            key: key,
            sequence: root.contextCompactionSequence,
            sessionId: String(sessionId || root.sessions.currentId),
            submissionId: root.pendingSubmissionId,
            modelId: String(model.id ?? ""),
            fallback: root.fallbackContextSummary(turns)
        };
        root.summaryMessage.content = "";
        root.summaryMessage.rawContent = "";
        root.summaryMessage.thought = "";
        root.summaryMessage.done = false;
        const request = root.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `${root.summaryInstruction}\n\n---\n\n${transcript}`,
            "rawContent": ""
        });
        strategy.thinkingOverride = "off";
        strategy.activeThinkingLevel = "off";
        const data = strategy.buildRequestData(model, [request], root.summaryInstruction, 0.2, null);
        request.destroy();
        summaryRequester.model = model;
        summaryRequester.strategy = strategy;
        summaryRequester.message = root.summaryMessage;
        summaryRequester.endpoint = strategy.buildEndpoint(model);
        summaryRequester.requestData = data;
        summaryRequester.apiKey = model.requires_key ? (root.apiKeys?.[model.key_id] ?? "") : "";
        if (!summaryRequester.start()) {
            strategy.destroy();
            summaryRequester.strategy = null;
            root.pendingContextCompaction = null;
            return false;
        }
        return true;
    }

    function finishContextCompaction(success: bool): void {
        const job = root.pendingContextCompaction;
        if (!job)
            return;
        const strategy = summaryRequester.strategy;
        const sameSession = String(job.sessionId) === String(root.sessions.currentId);
        if (sameSession) {
            const summary = String(root.summaryMessage.content ?? "").trim();
            root.contextSummary = success && summary.length > 0 ? summary : String(job.fallback ?? "");
            root.contextSummaryKey = String(job.key ?? "");
            root.recomputeContextEstimate();
            root.commitSession();
        }
        root.pendingContextCompaction = null;
        summaryRequester.strategy = null;
        if (strategy && typeof strategy.destroy === "function")
            strategy.destroy();
        if (!sameSession)
            return;
        const pending = job.submissionId.length > 0 && job.submissionId === root.pendingSubmissionId
            ? root.pendingSubmission
            : null;
        if (pending)
            pending.state = "preparing";
        // The retry deliberately skips another compaction pass. The windowing
        // pass still trims the request, but one user turn cannot recursively
        // start a second summarizer because the summary itself consumed room.
        Qt.callLater(() => root.makeRequest(pending, { skipCompaction: true }));
    }

    function cancelContextCompaction() {
        const strategy = summaryRequester.strategy;
        root.pendingContextCompaction = null;
        // `running` on an AiRequest is read-only — assigning to it threw, and
        // since this is the first thing `applySession()` does, a restored chat
        // came back with no messages at all.
        summaryRequester.abort();
        summaryRequester.strategy = null;
        if (strategy && typeof strategy.destroy === "function")
            strategy.destroy();
    }

    readonly property string summaryInstruction: "Summarise the earlier part of this conversation in at most 150 words. Keep names, decisions, file paths and anything the assistant must remember. Answer with the summary only."
    property AiMessageData summaryMessage: AiMessageData {}

    AiRequest {
        id: summaryRequester
        apiKeyEnvVarName: root.apiKeyEnvVarName
        scriptPath: `/tmp/quickshell-${SystemInfo.username}/ai/summary.sh`

        onLine: data => {
            try {
                summaryRequester.strategy.parseResponseLine(data, root.summaryMessage);
            } catch (e) {
            // A summary is not worth a message in the chat.
            }
        }

        onFinished: reason => {
            root.finishContextCompaction(reason === "done");
        }
    }

    /** A count short enough for a chip: 940, 1.2k, 48k. */
    function shortTokenCount(count: int): string {
        const value = Math.max(0, Number(count ?? 0));
        if (value < 1000)
            return String(value);
        if (value < 10000)
            return `${(value / 1000).toFixed(1)}k`;
        return `${Math.round(value / 1000)}k`;
    }

    /** Formats the USD-denominated amount OpenRouter reports in `usage.cost`. */
    function formatOpenRouterCost(cost: real): string {
        const value = Number(cost ?? -1);
        if (!isFinite(value) || value < 0)
            return "—";
        if (value === 0)
            return "$0.00";
        if (value < 0.0001)
            return "$" + value.toFixed(6);
        if (value < 0.01)
            return "$" + value.toFixed(4);
        if (value < 1)
            return "$" + value.toFixed(3);
        return "$" + value.toFixed(2);
    }

    /**
     * Generation speed of the latest user-visible answer.
     *
     * The response's output tokens include the provider's generated stream
     * (including reasoning where the provider reports it that way). Input
     * context tokens are deliberately excluded: they describe request size,
     * not how quickly the model generated the answer.
     */
    readonly property real lastAnswerTokensPerSecond: {
        const ids = root.messageIDs;
        for (let i = ids.length - 1; i >= 0; i--) {
            const message = root.messageByID[ids[i]];
            if (!message || message.role !== "assistant" || !message.done)
                continue;
            if (Array.from(message.toolCalls ?? []).length > 0 || String(message.content ?? "").trim().length === 0)
                continue;
            const outputTokens = Number(message.outputTokens ?? -1);
            const elapsedMs = Number(message.completedAt ?? 0) - Number(message.createdAt ?? 0);
            if (outputTokens <= 0 || elapsedMs <= 0)
                continue;
            return outputTokens / (elapsedMs / 1000);
        }
        return 0;
    }

    function formatTokensPerSecond(rate: real): string {
        const value = Number(rate ?? 0);
        if (isNaN(value) || value <= 0)
            return "—";
        return (value < 10 ? value.toFixed(1) : String(Math.round(value))) + " tok/s";
    }

    property real temperature: 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        // Part of the output that was spent reasoning. -1 when the provider
        // does not break it out.
        property int thinking: -1
        property int total: -1
    }
    readonly property var thinkingLevels: ["off", "low", "medium", "high"]
    property string thinkingLevel: "medium"
    /** Session-scoped profile requests; empty response mode keeps legacy thinking levels. */
    property string sessionResponseMode: ""
    property string sessionWebMode: ""
    property string sessionFunctionExposure: ""
    readonly property string responseMode: sessionResponseMode.length > 0
        ? AiResponseProfiles.normalizeResponseMode(sessionResponseMode)
        : AiResponseProfiles.responseModeForThinking(thinkingLevel)
    readonly property var responseProfile: root.responseProfileForModel(root.currentModelId)
    readonly property string webMode: root.responseProfile.webMode
    readonly property string functionExposure: root.responseProfile.functionExposure
    readonly property bool canForceWeb: root.responseProfile.canForceWeb
    property string sessionModelId: ""
    property string sessionPersonaId: ""
    // Persistent is loaded asynchronously. Until its adapter is ready, the
    // values exposed below are only the QML defaults, not the user's saved
    // choices. Keep the startup restore separate from normal per-chat state.
    property bool persistentDefaultsRestored: false
    property string pendingPersistentModelId: ""
    readonly property string defaultModelId: {
        const explicit = Persistent.states?.ai?.defaultModelId ?? "";
        return explicit.length > 0 ? explicit : (Persistent.states?.ai?.modelId ?? "");
    }
    readonly property real defaultTemperature: {
        const explicit = Persistent.states?.ai?.defaultTemperature ?? -1;
        return explicit >= 0 ? explicit : (Persistent.states?.ai?.temperature ?? 0.5);
    }
    readonly property string defaultThinkingLevel: {
        const configured = String(Config.options?.sidebar?.ai?.thinkingDefault ?? "");
        if (root.thinkingLevels.indexOf(configured) >= 0)
            return configured;
        const explicit = Persistent.states?.ai?.defaultThinkingLevel ?? "";
        return explicit.length > 0 ? explicit : (Persistent.states?.ai?.thinkingLevel ?? "medium");
    }
    readonly property string defaultPersonaId: {
        const explicit = Persistent.states?.ai?.defaultPersonaId ?? "";
        return explicit.length > 0 ? explicit : (Persistent.states?.ai?.personaId ?? "");
    }
    // Whether the current model reasons at all, and whether it can be told
    // not to. The control bar reads both; nothing here tests provider names.
    readonly property bool currentModelThinks: root.currentModelEntry?.thinking ?? false
    readonly property bool currentModelAlwaysThinks: root.currentModelEntry?.thinkingAlwaysOn ?? false

    function responseProfileForModel(modelId) {
        const model = root.catalog.models[String(modelId ?? "")] ?? null;
        return AiResponseProfiles.reconcile(model, {
            responseMode: root.responseMode,
            thinkingLevel: root.sessionResponseMode.length === 0 ? root.thinkingLevel : "",
            webMode: root.sessionWebMode.length > 0 ? root.sessionWebMode : "auto",
            functionExposure: root.sessionFunctionExposure.length > 0 ? root.sessionFunctionExposure : "all"
        }, root.onlineAllowed, root.configuredTool);
    }

    /**
     * Ids are handed out once and kept: they are written to the session file
     * and read back with it, so a chat that has been reopened is still keyed
     * the way it was written. Everything that points at a message — deleting,
     * regenerating, forking — points at one of these.
     */
    function idForMessage(message) {
        return root.sessions.newId();
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    /** Path of the prompt file last loaded, so the picker can show which one won. */
    property string currentPromptFile: ""

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`
    }

    // Which tools exist, what they are allowed to do, and what they did is
    // all in AiTools. What is tracked here is only the mode in use, which is
    // the config's answer unless a turn borrowed another one — the search
    // dance does exactly that. Assigning the mode directly would break the
    // binding to the config, and the settings page would stop reaching the
    // chat for the rest of the session.
    property string toolOverride: ""
    readonly property string configuredTool: root.toolOverride.length > 0 ? root.toolOverride : (Config.options?.ai?.tools?.mode ?? "functions")
    readonly property string currentTool: !root.onlineAllowed && root.configuredTool === "search" ? "none" : root.configuredTool
    readonly property AiTools toolbox: AiTools {
        apiFormat: root.currentModelEntry?.api_format ?? "openai"
        searchAvailable: root.currentModelEntry?.builtinSearch ?? false
        functionExposure: root.responseProfile.functionExposure
        localOnly: root.localOnly
        perConversationScope: Config.options?.ai?.tools?.scopePerConversation ?? false
        conversationPermissions: root.sessionToolPermissions
        onConversationPermissionsCommitted: permissions => root.setSessionToolPermissions(permissions)
        // Whether the network may be reached at all, asked separately from
        // whether the model is local. A local model with policy Yes may still
        // search; a remote model under a local-only policy may not exist.
        online: root.onlineAllowed
        // What the model itself can do. Null while nothing has been resolved,
        // which the registry reads as "do not gate on it".
        webMode: root.webMode
        modelCapabilities: root.currentModelEntry ? ({
            tools: root.currentModelEntry.tools === true,
            vision: root.currentModelEntry.vision === true,
            builtinSearch: root.currentModelEntry.builtinSearch === true
        }) : null
        onCallCheckpointChanged: entry => root.recordToolCheckpoint(entry)
    }

    /**
     * The only thing that runs a tool the model asked for.
     *
     * It owns the road every call takes — schema check, a second look at the
     * policy, a deadline, a size limit, the record — and knows nothing about
     * what any individual tool does. The handlers below are where that lives,
     * next to the state each one has to touch.
     */
    readonly property AiToolBroker broker: AiToolBroker {
        host: root
        toolbox: root.toolbox
        handlers: root.toolHandlers
        onCallStarted: record => {
            if (root.currentRunId.length > 0)
                root.runCoordinator.activity(root.currentRunId, "tool", {
                    "tool": record.tool,
                    "serial": record.serial
                });
            root.noteToolCallState(record.message, record.callId, {
                state: "running",
                summary: ""
            });
        }
        onCallFinished: (record, envelope) => {
            root.noteToolCallState(record.message, record.callId, {
                state: envelope.status,
                summary: envelope.summary,
                durationMs: envelope.durationMs,
                networkUsed: envelope.networkUsed,
                truncated: envelope.truncated
            });
        }
    }
    /** Local Settings metadata and strict typed writes; never a config dump. */
    readonly property AiSettingsIntegration settingsIntegration: AiSettingsIntegration {}
    /** Explicit clipboard, launcher and active-window metadata for one turn. */
    readonly property AiShellContextIntegration shellContext: AiShellContextIntegration {}
    /** Local alarms, khal calendar and Weather DTOs; it owns no UI. */
    readonly property AiTimeIntegration timeIntegration: AiTimeIntegration {}
    /** Read-only live system and keybind DTOs; never a shell fallback. */
    readonly property AiSystemIntegration systemIntegration: AiSystemIntegration {}
    /** Parameterized ESPN reads; never touches the sports widget state. */
    readonly property AiSportsIntegration sportsIntegration: AiSportsIntegration {}
    /** Read-only Gmail metadata/body bridge with correlated helper calls. */
    readonly property AiGmailIntegration gmailIntegration: AiGmailIntegration {}
    /** Provider-neutral local/TickTick task contract. */
    readonly property AiTasksIntegration tasksIntegration: AiTasksIntegration {}
    /** The one path to the filesystem the assistant may use by itself. */
    readonly property AiFilesIntegration filesIntegration: AiFilesIntegration {}
    /** Local notes previews and reviewed append/create operations. */
    readonly property AiNotesIntegration notesIntegration: AiNotesIntegration {}
    /** Local retrieval over folders the user indexed for search. */
    readonly property AiRagIntegration ragIntegration: AiRagIntegration {}
    /** Typed previews and reversible writes to existing local system services. */
    readonly property AiSystemControlsIntegration systemControlsIntegration: AiSystemControlsIntegration {}
    /** Live Hyprland window/workspace references and reviewed movement. */
    readonly property AiWindowsIntegration windowsIntegration: AiWindowsIntegration {}
    /** Configured-local wallpaper search and reviewed reversible theme changes. */
    readonly property AiThemeIntegration themeIntegration: AiThemeIntegration {}
    /** Active MPRIS state, lyrics and reviewed SongRec identification. */
    readonly property AiMediaIntegration mediaIntegration: AiMediaIntegration {}
    /** Local speech-to-text: recording, detection and the review draft. */
    readonly property AiVoiceService voiceService: AiVoiceService {}
    /** Preview id → immutable proposed changes until the user decides. */
    property var settingsPreviews: ({})

    Connections {
        target: root.sportsIntegration
        function onResultReady(key, callId, sessionId, outcome) {
            const activeSession = String(root.currentRunSessionId || root.sessions.currentId || "");
            if (String(sessionId ?? "").length > 0 && String(sessionId) !== activeSession)
                return;
            if (root.broker.isPending(String(key)))
                root.broker.settle(String(key), outcome);
        }
    }

    Connections {
        target: root.gmailIntegration
        function onResultReady(key, callId, sessionId, outcome) {
            const activeSession = String(root.currentRunSessionId || root.sessions.currentId || "");
            if (String(sessionId ?? "").length > 0 && String(sessionId) !== activeSession)
                return;
            if (root.broker.isPending(String(key)))
                root.broker.settle(String(key), outcome);
        }
    }

    Connections {
        target: root.tasksIntegration
        function onResultReady(key, operationId, outcome) {
            const message = root.messageForToolKey(String(key));
            const record = root.broker.recordFor(String(key));
            if (message && record?.tool && ["tasks_list", "tasks_search"].indexOf(record.tool) >= 0
                    && outcome.status === "success" && outcome.data?.tasks) {
                root.addToolCard(message, {
                    callId: String(key),
                    tool: record.tool,
                    kind: "taskResults",
                    state: "done",
                    summary: String(outcome.summary ?? ""),
                    data: outcome.data
                });
            }
            if (message) {
                message.functionPending = false;
                root.updateToolCard(message, String(key), {
                    state: outcome.status === "success" ? "done" : String(outcome.status ?? "error"),
                    summary: String(outcome.summary ?? "")
                });
            }
            if (root.broker.isPending(String(key)))
                root.broker.settle(String(key), outcome);
        }
    }

    Connections {
        target: root.timeIntegration
        function onCalendarMutationFinished(key, operationId, outcome) {
            const message = root.messageForToolKey(String(key));
            if (message)
                root.finishCalendarMutation(message, outcome);
            if (root.broker.isPending(String(key)))
                root.broker.settle(String(key), outcome);
        }
    }

    Connections {
        target: SongRec
        function onRecognizedTrackChanged() {
            const track = SongRec.recognizedTrack ?? ({});
            if (root.pendingSongIdentify && String(track.title ?? "").trim().length > 0)
                root.finishSongIdentify("success", Translation.tr("Song identified"), { track: track, temporaryAudioDeleted: true });
        }
        function onRunningChanged() {
            if (!root.pendingSongIdentify || SongRec.running)
                return;
            Qt.callLater(function() {
                if (!root.pendingSongIdentify || SongRec.running)
                    return;
                root.finishSongIdentify("error", Translation.tr("No song was identified"), {
                    error: "songNotRecognized",
                    temporaryAudioDeleted: true
                });
            });
        }
    }

    /**
     * Writes how a call went onto the call itself.
     *
     * The transcript already lists what the model reached for; what it could
     * not say was whether any of it worked. The outcome belongs on the same
     * record as the request rather than in a second array that has to be kept
     * in step with the first.
     */
    function noteToolCallState(message, callId: string, changes: var): bool {
        if (!message)
            return false;
        const calls = Array.from(message.toolCalls ?? []);
        if (calls.length === 0)
            return false;
        let touched = false;
        const next = calls.map(call => {
            // An id is the reliable match; without one there is only ever a
            // single call in flight, so the running one is the right one.
            const matches = String(callId).length > 0
                ? String(call.id ?? "") === String(callId)
                : String(call.state ?? "") === "running" || call.state === undefined;
            if (!matches || touched)
                return call;
            touched = true;
            return Object.assign({}, call, changes ?? ({}));
        });
        if (touched)
            message.toolCalls = next;
        return touched;
    }

    /**
     * What each tool actually does.
     *
     * A handler gets the broker's record — `{tool, args, callId, key, serial,
     * message}` — and answers with the outcome, or says it will finish later.
     * Arguments have already been checked against the schema the model was
     * given, so nothing here re-reads `args.foo ?? ""` defensively.
     */
    readonly property var toolHandlers: ({
            "switch_to_search_mode": call => {
                root.toolOverride = "search";
                root.postResponseHook = () => {
                    root.toolOverride = "";
                };
                return {
                    status: "success",
                    summary: Translation.tr("Search on for one turn"),
                    data: "Switched to search mode. Continue with the user's request."
                };
            },
            "settings_find": call => root.toolSettingsFind(call),
            "settings_get": call => root.toolSettingsGetSemantic(call),
            "settings_search": call => root.toolSettingsSearch(call),
            "settings_open": call => root.toolSettingsOpen(call),
            "settings_propose_changes": call => root.toolSettingsProposeChanges(call),
            "settings_apply_changes": call => root.toolSettingsApplyChanges(call),
            "reminder_create": call => root.toolReminderCreate(call),
            "alarm_create": call => root.toolAlarmCreate(call),
            "alarms_list": call => root.toolAlarmsList(call),
            "timer_start": call => root.toolTimerStart(call),
            "timer_status": call => root.toolTimerStatus(call),
            "calendar_list_events": call => root.toolCalendarListEvents(call),
            "calendar_next_event": call => root.toolCalendarNextEvent(call),
            "calendar_create_event": call => root.toolCalendarCreateEvent(call),
            "calendar_move_event": call => root.toolCalendarMoveEvent(call),
            "calendar_delete_event": call => root.toolCalendarDeleteEvent(call),
            "weather_get": call => root.toolWeatherGet(call),
            "tasks_list": call => root.toolTasksList(call),
            "tasks_search": call => root.toolTasksSearch(call),
            "tasks_create": call => root.toolTasksCreate(call),
            "tasks_update": call => root.toolTasksUpdate(call),
            "tasks_complete": call => root.toolTasksComplete(call),
            "tasks_delete": call => root.toolTasksDelete(call),
            "notes_preview_append": call => root.toolNotesPreviewAppend(call),
            "notes_append": call => root.toolNotesAppend(call),
            "notes_create_from_answer": call => root.toolNotesCreate(call),
            "audio_set": call => root.toolSystemControl(call),
            "brightness_set": call => root.toolSystemControl(call),
            "dnd_set": call => root.toolSystemControl(call),
            "nightlight_set": call => root.toolSystemControl(call),
            "theme_set_mode": call => root.toolSystemControl(call),
            "windows_list": call => root.toolWindowsList(call),
            "window_focus": call => root.toolWindowFocus(call),
            "window_move_to_workspace": call => root.toolWindowMove(call),
            "workspace_switch": call => root.toolWorkspaceSwitch(call),
            "wallpaper_search": call => root.toolWallpaperSearch(call),
            "wallpaper_set": call => root.toolWallpaperSet(call),
            "media_status": call => root.toolMediaStatus(call),
            "media_control": call => root.toolMediaControl(call),
            "lyrics_get": call => root.toolLyricsGet(call),
            "song_identify": call => root.toolSongIdentify(call),
            "system_get_status": call => root.toolSystemGetStatus(call),
            "system_health": call => root.toolSystemHealth(call),
            "keybinds_search": call => root.toolKeybindsSearch(call),
            "sports_search_games": call => root.toolSports(call, false),
            "sports_refresh_games": call => root.toolSports(call, true),
            "gmail_search_messages": call => root.toolGmail(call, "search"),
            "gmail_get_message": call => root.toolGmail(call, "get"),
            "gmail_get_thread": call => root.toolGmail(call, "thread"),
            "gmail_open_in_client": call => root.toolGmailOpen(call),
            "files_search": call => root.toolFilesSearch(call),
            "files_preview": call => root.toolFilesPreview(call),
            "files_attach": call => root.toolFilesAttach(call),
            "files_open_location": call => root.toolFilesOpenLocation(call),
            "image_ocr": call => root.toolImageOcr(call),
            "set_shell_config": call => root.toolSetShellConfig(call),
            "remember_fact": call => root.toolRememberFact(call),
            "web_search": call => root.toolWeb(call, true),
            "fetch_url": call => root.toolWeb(call, false),
            "run_shell_command": call => root.toolShellCommand(call),
            "rag_search": call => root.toolRagSearch(call)
        })

    // ── Tool cards ────────────────────────────────────────────────────────
    // A card is how a tool shows something in the transcript: an approval, a
    // diff, a result with a shape. They live in one array on the message so a
    // new tool costs one entry rather than a property here, a branch in the
    // serializer and a branch in the transcript.

    function addToolCard(message, card): var {
        if (!message)
            return null;
        const entry = Object.assign({
            callId: "",
            tool: "",
            kind: "note",
            state: "pending",
            summary: "",
            data: null,
            createdAt: Date.now()
        }, card ?? ({}));
        message.toolCards = [...Array.from(message.toolCards ?? []), entry];
        return entry;
    }

    /** Changes one card in place, found by the call it belongs to. */
    function updateToolCard(message, callId: string, changes: var): bool {
        if (!message)
            return false;
        const cards = Array.from(message.toolCards ?? []);
        let touched = false;
        const next = cards.map(card => {
            if (String(card.callId) !== String(callId))
                return card;
            touched = true;
            return Object.assign({}, card, changes ?? ({}));
        });
        if (touched)
            message.toolCards = next;
        return touched;
    }

    function toolCardFor(message, callId: string): var {
        return Array.from(message?.toolCards ?? []).find(card => String(card.callId) === String(callId)) ?? null;
    }

    function messageForToolKey(key: string): var {
        const wanted = String(key ?? "");
        for (const id in root.messageByID) {
            const message = root.messageByID[id];
            if (root.toolCardFor(message, wanted))
                return message;
        }
        return null;
    }

    /** Cards still waiting on the user, which is what the transcript draws. */
    function pendingToolCards(message): var {
        return Array.from(message?.toolCards ?? []).filter(card => card.state === "pending");
    }

    /**
     * Cards the transcript keeps after the tool has returned. Most completed
     * approvals disappear, but a Settings result contains a live control and
     * must stay available for the user to inspect or change it.
     */
    // Kinds whose result is the point, not just a step on the way to a
    // pending approval: these stay in the transcript once done, the same way
    // a search engine's results page does not disappear once you have read
    // it.
    readonly property var resultCardKinds: ["settingsResults", "fileResults", "songIdentifyPreview", "taskResults", "ragResults"]
    // Approval bodies are actionable only while pending. Keeping their final
    // state in the model lets the transcript turn the card into one outcome
    // row instead of removing it from under the reader.
    readonly property var approvalCardKinds: ["settingsDiff", "reminderPreview", "memoryFact", "fileAttachPreview", "notesPreview", "systemControlPreview", "windowMovePreview", "wallpaperPreview", "mediaControlPreview", "songIdentifyPreview", "taskPreview", "taskMutationPreview", "calendarMutationPreview"]
    readonly property var resolvedApprovalStates: ["done", "denied", "failed", "needsInspection"]

    function visibleToolCards(message): var {
        return Array.from(message?.toolCards ?? []).filter(card => card.state === "pending"
            || (root.approvalCardKinds.indexOf(card.kind) >= 0
                && root.resolvedApprovalStates.indexOf(card.state) >= 0)
            || (root.resultCardKinds.indexOf(card.kind) >= 0 && (card.state === "done" || card.state === "running")));
    }

    /** The broker's key for the call a message is waiting on. */
    function toolKeyFor(message): string {
        const callId = String(message?.functionCallId ?? "");
        return callId.length > 0 ? callId : `#${Number(message?.toolCallSerial ?? -1)}`;
    }

    readonly property var availableTools: root.toolbox.availableModes.filter(mode => root.onlineAllowed || mode !== "search")
    readonly property var toolDescriptions: root.toolbox.modeDescriptions

    // Providers and models are described once, in the catalog. Nothing here
    // builds a model object or tests a provider name for substrings.
    readonly property ModelCatalog catalog: ModelCatalog {
        ollamaModelNames: root.ollamaModels
    }
    property var ollamaModels: []
    property bool ollamaRefreshPending: false

    /** Re-index after a user-initiated local pull, without duplicating jobs. */
    function refreshOllamaModels() {
        AiRagService.refreshInstalledModels();
        if (aiIndexProc.running) {
            root.ollamaRefreshPending = true;
            return;
        }
        aiIndexProc.running = true;
    }

    readonly property var providers: root.catalog.providers
    readonly property var providerIds: root.catalog.providerIds

    // The persisted id is validated on read: it can be stale (a renamed model,
    // a provider dropped by policy, a config the user edited). A stale id
    // falls back to its own provider's default before it falls back to the
    // first provider, so a model that disappeared keeps the account it was
    // billed to.
    readonly property string currentModelId: {
        const wanted = root.sessionModelId.length > 0 ? root.sessionModelId : root.defaultModelId;
        if (root.catalog.models[wanted])
            return wanted;
        const provider = root.providers[wanted.split(":")[0]] ?? root.providers[root.providerIds[0] ?? ""] ?? null;
        return provider?.defaultModel?.id ?? "";
    }
    // The two halves of the id, for the places that address one of them. A
    // model value can hold colons of its own (Ollama tags), the provider
    // cannot, so the split is at the first one only.
    readonly property string currentProvider: root.currentModelId.split(":")[0] ?? ""
    readonly property string currentModel: root.currentModelId.split(":").slice(1).join(":")
    readonly property AiModel currentModelEntry: root.catalog.models[root.currentModelId] ?? null

    /**
     * Every model by catalog id, plus one entry per provider id pointing at
     * that provider's current pick. Chats saved before ids became
     * "provider:model" stored the bare provider, so both shapes resolve.
     */
    readonly property var models: {
        const result = {};
        const catalogModels = root.catalog.models;
        for (const id in catalogModels) {
            result[id] = catalogModels[id];
        }
        const ids = root.providerIds;
        for (let i = 0; i < ids.length; i++) {
            const providerId = ids[i];
            const model = (providerId === root.currentProvider) ? root.currentModelEntry : root.providers[providerId].defaultModel;
            if (model)
                result[providerId] = model;
        }
        return result;
    }
    property var modelList: Object.keys(root.models)

    /** {providerId: [{title, value, modelProvider}, ...]}, for the pickers. */
    readonly property var modelsOfProviders: {
        const result = {};
        const ids = root.providerIds;
        for (let i = 0; i < ids.length; i++) {
            result[ids[i]] = root.catalog.selectionEntries(ids[i]);
        }
        return result;
    }

    function getModelProvider(providerKey, modelValue) {
        return root.catalog.resolve(providerKey, modelValue)?.modelProvider || null;
    }

    /**
     * Turns whatever the user typed into a catalog id: a full "provider:model"
     * id, a provider name (its default model), or a bare model name (looked up
     * in the current provider first, then anywhere).
     */
    function resolveModelId(query) {
        const wanted = String(query ?? "").trim();
        if (wanted.length === 0)
            return "";
        if (root.catalog.models[wanted])
            return wanted;
        const provider = root.providers[wanted.toLowerCase()];
        if (provider)
            return provider.defaultModel?.id ?? "";
        const inCurrentProvider = root.catalog.resolve(root.currentProvider, wanted);
        if (inCurrentProvider)
            return inCurrentProvider.id;
        const catalogModels = root.catalog.models;
        for (const id in catalogModels) {
            if (catalogModels[id].value === wanted)
                return id;
        }
        return "";
    }

    property var apiStrategies: {
        const openAiCompat = openAiCompatStrategy.createObject(this);
        return {
            "openai": openAiCompat,
            // Mistral speaks the same dialect. The name is kept because user
            // configs (and the shipped default) still ask for it.
            "mistral": openAiCompat,
            "gemini": geminiApiStrategy.createObject(this),
            "anthropic": anthropicApiStrategy.createObject(this)
        };
    }
    property ApiStrategy currentApiStrategy: apiStrategies[root.currentModelEntry?.api_format || "openai"]

    property string requestScriptFilePath: `/tmp/quickshell-${SystemInfo.username}/ai/request.sh`

    Component.onCompleted: {
        root.sessions.ensureLoaded();
        root.draftStore.ensureLoaded();
        root.restorePersistentDefaults();
    }

    Connections {
        target: Persistent

        function onReadyChanged() {
            // Let Persistent's own ready handler migrate the retired
            // provider/model pair before Ai consumes the unified model id.
            if (Persistent.ready)
                Qt.callLater(() => root.restorePersistentDefaults());
        }
    }

    Connections {
        target: Config

        function onReadyChanged() {
            // Tool permissions live in config.json, which can settle after
            // states.json does. Without this the split of `get_shell_config`
            // would be migrated only on the boot where Config happened to be
            // ready first.
            if (Config.ready)
                Qt.callLater(() => root.migrateToolPermissions());
        }
    }

    // Whether local OCR is available, checked once and cheaply: `which` exits
    // in a few milliseconds, and image_ocr's presence in the wire schema
    // depends on knowing the answer before the first turn, not after it.
    property bool tesseractPresent: false
    readonly property bool ocrAvailable: root.tesseractPresent && (Config.options?.ai?.vision?.ocrEnabled ?? true)
    Process {
        id: ocrCheckProc
        running: root.enabled
        command: ["bash", "-c", "command -v tesseract >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: root.tesseractPresent = text.trim() === "yes"
        }
    }

    // Boot-time index: Ollama models + default prompts + user prompts —
    // all in ONE Process spawn. Replaces four parallel
    // `Process { running: true }` invocations that fired on every boot
    // even if the user had never opened the AI panel.
    // Gated by Config.options.ai.indexAtStartup: when false, no fork happens
    // until the user opens the AI panel. Policy No also prevents indexing.
    // This is
    // particularly useful for users without ollama installed (the
    // previous incarnation spawned a script that blocked ~50ms probing
    // the daemon on every boot).
    Process {
        id: aiIndexProc
        running: root.enabled && (Config?.options?.ai?.indexAtStartup ?? true)
        command: [
            "python3",
            Directories.scriptPath + "/ai/ai_index.py".replace(/file:\/\//, ""),
            Directories.defaultAiPrompts.toString().replace(/file:\/\//, ""),
            Directories.userAiPrompts.toString().replace(/file:\/\//, "")
        ]
        stdout: StdioCollector {
            id: aiIndexCollector
            onStreamFinished: {
                const raw = aiIndexCollector.text.trim()
                if (raw.length === 0)
                    return
                let parsed
                try {
                    parsed = JSON.parse(raw)
                } catch (e) {
                    console.log("Ai index parse error:", e)
                    return
                }

                // Ollama models: handed to the catalog, which turns them into
                // the "ollama" provider's model list.
                if (Array.isArray(parsed.ollama_models))
                    root.ollamaModels = parsed.ollama_models

                // Prompts (already absolute, filtered by extension)
                if (Array.isArray(parsed.default_prompts))
                    root.defaultPrompts = parsed.default_prompts
                if (Array.isArray(parsed.user_prompts))
                    root.userPrompts = parsed.user_prompts
            }
        }
        onExited: {
            if (!root.ollamaRefreshPending)
                return;
            root.ollamaRefreshPending = false;
            Qt.callLater(root.refreshOllamaModels);
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false
        // The command prints the prompt it loaded; picking one from the
        // control bar does not, since the chip already shows which is active.
        property bool announce: true
        onLoadedChanged: {
            if (!promptLoader.loaded)
                return;
            // Loading a prompt gives it to this chat, not to every chat. The
            // one in the settings is what a chat falls back to, and it is not
            // rewritten from here any more.
            root.promptOverride = promptLoader.text();
            root.sessions.scheduleSave();
            if (promptLoader.announce)
                root.addMessage(Translation.tr("This chat now uses the prompt in %1.").arg(root.currentPromptFile), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(root.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath, feedback = true) {
        promptLoader.announce = feedback;
        root.currentPromptFile = filePath;
        promptLoader.path = ""; // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role, extra = null) {
        if (message.length === 0)
            return;
        const aiMessage = aiMessageComponent.createObject(root, Object.assign({
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
            "createdAt": Date.now(),
            "completedAt": Date.now()
        }, extra ?? ({})));
        const id = idForMessage(aiMessage);
        // The map is filled before the list is published: anything
        // watching `messageIDs` synchronously — the Search transcript
        // does — would otherwise look the new id up in a map that does
        // not hold it yet and drop the turn until something else
        // refreshed it.
        root.messageByID[id] = aiMessage;
        root.messageIDs = [...root.messageIDs, id];
    }

    function removeMessage(messageId: string) {
        if (!root.messageByID[messageId])
            return;
        root.messageIDs = root.messageIDs.filter(id => id !== messageId);
        delete root.messageByID[messageId];
        root.sessions.scheduleSave();
    }

    /**
     * Says a key is missing, as a card with a button rather than as a wall of
     * instructions. Nobody reads a paragraph telling them to type a command.
     */
    function addApiKeyAdvice(model) {
        root.addMessage(Translation.tr("%1 needs an API key.").arg(model.name), root.interfaceRole, {
            "notice": "apiKey"
        });
    }

    function getModel() {
        return root.currentModelEntry;
    }

    /** Selects a model, by catalog id, provider name or bare model name. */
    function setModel(modelId, feedback = true, setPersistentState = true) {
        const model = root.catalog.models[root.resolveModelId(modelId)] ?? null;
        if (!model) {
            if (feedback)
                root.addMessage(Translation.tr("Invalid model. Supported:\n\n- %1").arg(root.catalog.modelIds.join("\n- ")), root.interfaceRole);
            return false;
        }
        root.sessionModelId = model.id;
        root.thinkingLevel = root.responseProfileForModel(model.id).thinkingLevel;
        if (setPersistentState)
            root.persistDefaultModel(model.id);
        if (feedback)
            root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
        if (model.requires_key && root.apiKeysLoaded && !(root.apiKeys[model.key_id]?.length > 0))
            root.addApiKeyAdvice(model);
        return true;
    }

    /** Ids of models picked before, newest first, minus the one in use. */
    readonly property var recentModelIds: {
        const remembered = Array.from(Persistent.states?.ai?.recentModels ?? []);
        return remembered.filter(id => id !== root.currentModelId && root.catalog.models[id]);
    }

    /** Groups the model picker keeps folded, by provider id or "recent". */
    readonly property var collapsedModelGroups: Array.from(Persistent.states?.ai?.collapsedModelGroups ?? [])

    function toggleModelGroupCollapsed(groupId: string) {
        if (!Persistent.states?.ai)
            return;
        const folded = root.collapsedModelGroups;
        Persistent.states.ai.collapsedModelGroups = folded.includes(groupId) ? folded.filter(id => id !== groupId) : folded.concat([groupId]);
    }

    function rememberModel(modelId: string) {
        if (!Persistent.states?.ai)
            return;
        const remembered = Array.from(Persistent.states.ai.recentModels ?? []).filter(id => id !== modelId);
        remembered.unshift(modelId);
        Persistent.states.ai.recentModels = remembered.slice(0, 6);
    }

    /**
     * Makes an explicit model pick the default for future chats and future
     * shell sessions. A pick made during the short startup hydration window
     * is staged so the later disk load cannot overwrite it.
     */
    function persistDefaultModel(modelId: string) {
        const id = String(modelId ?? "");
        if (id.length === 0)
            return;
        if (!Persistent.ready) {
            root.pendingPersistentModelId = id;
            return;
        }
        const state = Persistent.states?.ai;
        if (!state)
            return;
        root.rememberModel(id);
        state.defaultModelId = id;
        state.modelId = id;
    }

    /** Switches provider, landing on that provider's first model. */
    function setProvider(providerId, feedback = true) {
        const provider = root.providers[String(providerId ?? "").trim().toLowerCase()] ?? null;
        if (!provider) {
            if (feedback)
                root.addMessage(Translation.tr("Invalid provider. Supported:\n\n- %1").arg(root.providerIds.join("\n- ")), root.interfaceRole);
            return false;
        }
        if (!provider.defaultModel) {
            if (feedback)
                root.addMessage(Translation.tr("%1 has no models yet. Add one in the AI settings page.").arg(provider.name), root.interfaceRole);
            return false;
        }
        return root.setModel(provider.defaultModel.id, feedback);
    }

    function setTool(tool) {
        if (Array.from(root.availableTools).indexOf(tool) === -1) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(Array.from(root.availableTools).join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tools.mode = tool;
        root.toolOverride = "";
        return true;
    }

    function getTemperature() {
        return root.temperature;
    }

    /** Top of the range the model in use accepts. Anthropic stops at 1. */
    readonly property real maxTemperature: root.currentModelEntry?.maxTemperature ?? 2.0

    function setTemperature(value, feedback = true) {
        const limit = root.maxTemperature;
        if (isNaN(value) || value < 0 || value > limit) {
            if (feedback)
                root.addMessage(Translation.tr("Temperature must be between 0 and %1").arg(limit), Ai.interfaceRole);
            return;
        }
        root.temperature = value;
        if (feedback)
            root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setThinkingLevel(level): bool {
        const value = String(level).trim().toLowerCase();
        if (root.thinkingLevels.indexOf(value) < 0) {
            root.addMessage(Translation.tr("Thinking level must be one of:\n- %1").arg(root.thinkingLevels.join("\n- ")), root.interfaceRole);
            return false;
        }
        root.sessionResponseMode = "";
        root.thinkingLevel = (root.currentModelAlwaysThinks && value === "off") ? "low" : value;
        root.sessions.scheduleSave();
        return true;
    }

    function setResponseMode(mode, feedback = true) {
        const value = AiResponseProfiles.normalizeResponseMode(mode);
        root.sessionResponseMode = value;
        const profile = root.responseProfileForModel(root.currentModelId);
        root.thinkingLevel = profile.thinkingLevel;
        root.sessions.scheduleSave();
        if (feedback)
            root.addMessage(Translation.tr("Response mode: %1").arg(value), root.interfaceRole);
        return true;
    }

    function setWebMode(mode, feedback = true) {
        const value = AiResponseProfiles.normalizeWebMode(mode);
        root.sessionWebMode = value;
        const profile = root.responseProfileForModel(root.currentModelId);
        root.sessions.scheduleSave();
        if (feedback && profile.webMode !== value)
            root.addMessage(Translation.tr("Web mode fell back to %1 for this model.").arg(profile.webMode), root.interfaceRole);
        return true;
    }

    function setFunctionExposure(exposure, feedback = true) {
        const value = AiResponseProfiles.normalizeFunctionExposure(exposure);
        root.sessionFunctionExposure = value;
        root.sessions.scheduleSave();
        if (feedback)
            root.addMessage(Translation.tr("Tool exposure: %1").arg(value), root.interfaceRole);
        return true;
    }

    function setApiKey(key) {
        const model = root.currentModelEntry;
        if (!model)
            return;
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            root.addApiKeyAdvice(model);
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    /**
     * Says whether a key is set. It never prints one: the chat is a visible,
     * screenshot-able, screen-shared surface, and a secret written into it
     * stays there.
     */
    function printApiKey() {
        const model = root.currentModelEntry;
        if (!model)
            return;
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), root.interfaceRole);
            return;
        }
        const key = root.apiKeys[model.key_id];
        if (!key) {
            root.addApiKeyAdvice(model);
            return;
        }
        root.addMessage(Translation.tr("A key is set for %1 (ending %2). Open the key panel to see or change it.").arg(model.name).arg(key.slice(-4)), root.interfaceRole, {
            "notice": "apiKey"
        });
    }

    /** Whether a provider has a key on file, for the key panel's state dots. */
    function hasApiKey(keyId: string): bool {
        return (root.apiKeys?.[keyId]?.length ?? 0) > 0;
    }

    function setApiKeyFor(keyId: string, key: string) {
        if (!keyId || keyId.length === 0)
            return;
        KeyringStorage.setNestedField(["apiKeys", keyId], String(key ?? "").trim());
    }

    // ── Does this key work? ───────────────────────────────────────────────
    // One very small request, whose answer nobody reads. The only thing worth
    // knowing is what the endpoint says about the key, in words rather than
    // as an HTTP number.

    property string keyTestId: ""
    /** "", "running", "ok" or "failed". */
    property string keyTestState: ""
    property string keyTestMessage: ""
    property AiMessageData keyTestMessageData: AiMessageData {}

    function testApiKey(keyId: string) {
        if (keyTester.running)
            return;
        const model = root.catalog.modelIds.map(id => root.catalog.models[id]).find(entry => entry.key_id === keyId && entry.requires_key);
        if (!model) {
            root.keyTestId = keyId;
            root.keyTestState = "failed";
            root.keyTestMessage = Translation.tr("No model uses this key.");
            return;
        }
        const permission = root.canSubmit(model.id);
        if (!permission.allowed) {
            root.keyTestId = keyId;
            root.keyTestState = "failed";
            root.keyTestMessage = Translation.tr("This model is unavailable under the current AI policy.");
            return;
        }
        const key = root.apiKeys?.[keyId] ?? "";
        if (key.length === 0) {
            root.keyTestId = keyId;
            root.keyTestState = "failed";
            root.keyTestMessage = Translation.tr("No key to test.");
            return;
        }
        const strategy = root.titleStrategyFor(model.api_format || "openai");
        const prompt = root.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": "Hi",
            "rawContent": "Hi",
            "thinking": false,
            "done": true
        });
        strategy.thinkingOverride = "off";
        strategy.outputOverride = 16;
        const data = strategy.buildRequestData(model, [prompt], "Reply with one word.", 0, null);
        strategy.thinkingOverride = "";
        strategy.outputOverride = 0;
        prompt.destroy();

        root.keyTestId = keyId;
        root.keyTestState = "running";
        root.keyTestMessage = "";
        keyTester.model = model;
        keyTester.strategy = strategy;
        keyTester.message = root.keyTestMessageData;
        keyTester.endpoint = strategy.buildEndpoint(model);
        keyTester.requestData = data;
        keyTester.apiKey = key;
        keyTester.start();
    }

    AiRequest {
        id: keyTester
        apiKeyEnvVarName: root.apiKeyEnvVarName
        scriptPath: `/tmp/quickshell-${SystemInfo.username}/ai/keytest.sh`
        // One attempt: a key that is refused is refused, and waiting through
        // two backoffs to be told so is not a test.
        maxRetries: 0

        onFinished: (reason, status, code) => {
            if (reason === "done") {
                root.keyTestState = "ok";
                root.keyTestMessage = Translation.tr("The key works.");
                return;
            }
            root.keyTestState = "failed";
            const kind = root.transportErrorKind(status, code);
            if (kind === "auth")
                root.keyTestMessage = Translation.tr("Refused: the key is wrong, or not allowed to use this model.");
            else if (kind === "quota")
                root.keyTestMessage = Translation.tr("The key is valid but out of quota for now.");
            else if (kind === "network" || kind === "timeout")
                root.keyTestMessage = Translation.tr("Could not reach the provider.");
            else if (status === 0)
                // Nothing answered because nothing was asked: the request
                // itself failed to run. "HTTP 0" said none of that.
                root.keyTestMessage = Translation.tr("The request could not be sent (exit code %1).").arg(code);
            else
                root.keyTestMessage = Translation.tr("The provider answered with HTTP %1.").arg(status);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.thinking = -1;
        root.tokenCount.total = -1;
    }

    function markDone(message: AiMessageData) {
        // A stream can say it is over more than once — a finish reason, then a
        // trailing usage frame, then the process exiting. The chat is only
        // saved, and the hook only run, for the first of them.
        if (!message || message.done)
            return;
        message.done = true;
        message.completedAt = Date.now();
        // The usage ledger counts every finished response; tokens only when
        // the provider actually reported them (total stayed -1 otherwise),
        // success only when nothing flagged the message with an error kind.
        AiUsage.recordResponse(message.model ?? root.currentModelId,
            message.inputTokens, message.outputTokens,
            message.thoughtTokens, message.totalTokens,
            (message.errorKind ?? "").length === 0,
            message.requestCost);
        // A message that just issued a tool call is not the end of the
        // exchange: `AiToolBroker.finish()` always asks for a follow-up
        // turn next, sync or async. Notifying here as well as for the
        // message that actually answers turned one finished exchange into
        // one notification per tool round-trip (a web search followed by
        // reading a page was three notifications for one answer).
        if ((message.toolCalls?.length ?? 0) === 0) {
            root.notifyResponseFinished(message);
            root.playAnswerSound(message);
            root.writeLastAnswerFile(message);
        }
        if (root.postResponseHook) {
            root.postResponseHook();
            root.postResponseHook = null; // Reset hook after use
        }
        const runSessionId = root.currentRunSessionId;
        if (Config.options?.ai?.autoTitle !== false && (!runSessionId || runSessionId === root.sessions.currentId))
            root.autoTitle(); // Names it first, so the write below carries the name
        root.commitRunSession(runSessionId || root.sessions.currentId, true);
        root.responseFinished({
            runId: root.currentRunId,
            sessionId: runSessionId || root.sessions.currentId,
            requestMessageId: root.currentRunRequestId,
            responseMessageId: root.currentRunResponseId,
            modelId: message.model ?? root.currentModelId,
            state: (message.errorKind ?? "").length > 0 ? "failed" : "completed",
            finishReason: message.finishReason ?? "",
            errorKind: message.errorKind ?? "",
            requiresAttention: (message.errorKind ?? "").length > 0
        });
    }

    /**
     * What went wrong, as something the transcript can act on rather than as
     * prose in the bubble: a 429 and an answer used to look the same.
     */
    // ── Telling someone it finished ───────────────────────────────────────
    /** Whether a chat surface is on screen, wherever it is. */
    readonly property bool chatOnScreen: GlobalStates.sidebarLeftOpen || GlobalStates.overviewOpen

    /**
     * A desktop notification when an answer lands.
     *
     * It goes through `notify-send`, so the shell's own notification service
     * shows it like any other — no separate path, and it obeys the user's
     * do-not-disturb. Nothing is sent while the chat is on screen: a model
     * that finishes in front of the reader has already told them.
     */
    /**
     * A name the icon theme actually has for the model that answered.
     *
     * The bundled provider logos are files in `assets/icons`, and a
     * notification icon is a *theme name* — handing the daemon a path (or the
     * name of a file that is not in the theme) is what drew the missing-texture
     * checkerboard. Candidates are derived from the model itself and each one
     * is checked before it is used; when none exists the field is left empty
     * on purpose, and the shell draws a Material symbol instead of a hole.
     */
    function notificationIconFor(model): string {
        const candidates = [];
        const icon = String(model?.icon ?? "");
        if (icon.length > 0) {
            const bare = icon.replace(/\.(svg|png)$/i, "");
            candidates.push(bare);
            candidates.push(bare.replace(/-symbolic$/, ""));
            candidates.push(bare.replace(/^bootstrap_/, "").replace(/-symbolic$/, ""));
            candidates.push(bare.replace(/^ai-/, "").replace(/-symbolic$/, ""));
        }
        const modelProvider = String(model?.modelProvider ?? "");
        if (modelProvider.length > 0)
            candidates.push(modelProvider);
        const providerId = String(model?.providerId ?? "");
        if (providerId.length > 0)
            candidates.push(providerId);
        for (let i = 0; i < candidates.length; i++) {
            const candidate = candidates[i];
            if (candidate.length > 0 && String(Quickshell.iconPath(candidate, true)).length > 0)
                return candidate;
        }
        return "";
    }

    function notifyResponseFinished(message: AiMessageData) {
        const options = Config.options?.ai?.notify;
        if (!(options?.whenDone ?? true) || !AiAttentionService.notificationAllowed)
            return;
        if ((options?.onlyWhenAway ?? true) && root.chatOnScreen)
            return;
        const started = Number(message?.createdAt ?? 0);
        const elapsed = started > 0 ? (Date.now() - started) / 1000 : 0;
        if (started > 0 && elapsed < Math.max(0, options?.minimumSeconds ?? 4))
            return;

        const failed = String(message?.errorKind ?? "").length > 0;
        const model = root.catalog.models[message?.model] ?? null;
        const modelName = model?.title ?? Translation.tr("The model");
        const chatName = root.sessionTitle.length > 0 ? root.sessionTitle : Translation.tr("this chat");
        const answer = String(message?.content ?? "").replace(/```[\s\S]*?```/g, " ").replace(/\s+/g, " ").trim();
        const summary = failed
            ? Translation.tr("%1 could not answer").arg(modelName)
            : Translation.tr("%1 answered").arg(modelName);
        const privacy = AiAttentionService.notificationPrivacy;
        const canShowContent = privacy === "full" && !GlobalStates.screenLocked;
        const body = failed
            ? (canShowContent ? String(message?.errorText ?? Translation.tr("The request failed.")) : Translation.tr("The AI request failed. Open the chat for details."))
            : (canShowContent
                ? (answer.length > 0 ? (answer.length > 160 ? `${answer.slice(0, 160)}…` : answer) : Translation.tr("Answer ready in %1").arg(chatName))
                : Translation.tr("The AI answer is ready. Open the chat to read it."));

        // The model's own logo when the theme has it, nothing when it does
        // not: an icon name the daemon cannot resolve renders as a broken
        // image, while no icon at all renders as a Material symbol.
        const iconName = failed ? "dialog-error" : root.notificationIconFor(model);
        const command = ["notify-send", summary, body, "--app-name=AI",
            failed ? "--urgency=normal" : "--urgency=low"];
        if (iconName.length > 0)
            command.push(`--icon=${iconName}`);
        Quickshell.execDetached(command);
    }

    function playAnswerSound(message: AiMessageData) {
        if (!Config.options?.sidebar?.ai?.soundOnAnswer)
            return;
        if (String(message?.errorKind ?? "").length > 0)
            return;
        SoundService.playEvent("notifications", ["message-new-instant"]);
    }

    // ── Answering from outside the UI ───────────────────────────────────
    /**
     * The last completed exchange, kept in memory and mirrored to
     * `Directories.aiLastAnswer` on disk, so a question that came in over
     * `qs -c ii ipc call ai ask` — never touching the transcript, no window,
     * nothing to look at — has somewhere to read the answer back from.
     * Whichever chat is active answers; there is only ever one running
     * exchange, on screen or not, so "the last one" is unambiguous.
     */
    property var lastAnswerRecord: null

    function writeLastAnswerFile(message: AiMessageData) {
        const request = root.messageByID[root.currentRunRequestId] ?? null;
        const failed = String(message?.errorKind ?? "").length > 0;
        const record = {
            "requestText": String(request?.rawContent ?? request?.content ?? ""),
            "answer": failed ? "" : String(message?.content ?? ""),
            "errorKind": String(message?.errorKind ?? ""),
            "errorText": String(message?.errorText ?? ""),
            "sessionId": root.currentRunSessionId || root.sessions.currentId,
            "sessionTitle": root.sessionTitle,
            "model": message?.model ?? root.currentModelId,
            "completedAt": Date.now()
        };
        root.lastAnswerRecord = record;
        lastAnswerFile.setText(JSON.stringify(record, null, 2));
    }

    // Write-only: nothing here ever reads this back into the shell, so
    // there is no adapter, no load guard, no retry-then-create dance —
    // just the one thing that matters for a file a stranger process polls,
    // atomic writes, so it is never caught half-written.
    FileView {
        id: lastAnswerFile
        path: Qt.resolvedUrl(Directories.aiLastAnswer)
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => console.log(`[Ai] Could not write the last-answer file: ${error}`)
    }

    /**
     * Lets a request that never touches the UI ask the model something,
     * from another shell over SSH, a script, whatever can reach the local
     * `qs` socket. `ask` runs exactly like a message typed into the
     * composer — same chat, same tools, same one-at-a-time rule — and its
     * return value is `sendUserMessage()`'s own accept/reject verdict as
     * JSON: busy, a missing key, a disabled policy, whatever it is, the
     * caller sees it at once. The answer is not in that return value — it
     * still has to be generated — so it lands later, in `lastAnswer()` or
     * the file at `Directories.aiLastAnswer`, once the model is done.
     *
     * One real limitation, not a bug: a tool call that needs approval —
     * `run_shell_command` always does, by design — has no deadline and
     * waits for a person to click it in the transcript. Asked this way,
     * with no window open to click anything, that wait never ends until
     * someone opens the chat and answers the card by hand.
     */
    IpcHandler {
        target: "ai"

        function ask(text: string): string {
            return JSON.stringify(root.sendUserMessage(text));
        }

        /** The last completed answer, whoever asked for it. */
        function lastAnswer(): string {
            return JSON.stringify(root.lastAnswerRecord ?? {});
        }

        /** DEBUG: trigger active-window capture; caller waits then calls ask(). */
        function debugCaptureActiveWindow(): string {
            const started = root.attachActiveWindowContext();
            return JSON.stringify({ started: started });
        }

        function debugAttachments(): string {
            return JSON.stringify(root.attachments.map(a => ({ kind: a.kind, name: a.name, bytes: a.bytes })));
        }

        function debugState(): string {
            return JSON.stringify({ requesterRunning: requester.running, activeRunId: root.runCoordinator.activeRunId });
        }

    }

    function transportErrorKind(status: int, code: int): string {
        if (status === 401 || status === 403)
            return "auth";
        if (status === 404)
            return "notFound";
        if (status === 429)
            return "quota";
        if (status >= 500)
            return "server";
        if (status >= 400)
            return "request";
        if (code === 28)
            return "timeout";
        if (code === 6 || code === 7)
            return "network";
        return "unknown";
    }

    /** What to try next, in one line, for the error card's second row. */
    function transportErrorAdvice(kind: string): string {
        const model = root.currentModelEntry;
        if (kind === "auth")
            return Translation.tr("Check the key for %1.").arg(model?.name ?? Translation.tr("this provider"));
        if (kind === "quota")
            return Translation.tr("Wait a moment, or use a model with room left.");
        if (kind === "notFound")
            return Translation.tr("The model name or endpoint is wrong. Pick another model.");
        if (kind === "server")
            return Translation.tr("The provider is having trouble. Sending it again usually works.");
        if (kind === "network")
            return Translation.tr("Nothing answered. Check the connection, or whether the local server is up.");
        if (kind === "timeout")
            return Translation.tr("No answer in time. A shorter question, or a longer timeout in settings.");
        return "";
    }

    function attachmentErrorText(raw: string): string {
        try {
            const result = JSON.parse(raw);
            if (Array.isArray(result.failed) && result.failed.length > 0)
                return Translation.tr("Could not attach: %1").arg(result.failed.join(", "));
            if (result.error)
                return Translation.tr("Could not attach the file: %1").arg(result.error);
        } catch (e) {
            // Keep a useful message even if a helper failure was not JSON.
        }
        return Translation.tr("Could not attach one or more files. Nothing was sent.");
    }

    /**
     * Sends the failed turn again. Nothing is forked: an answer that never
     * arrived is not a branch worth keeping.
     */
    function retryMessage(messageId: string) {
        const message = root.messageByID[messageId];
        if (!message || requester.running)
            return;
        const at = root.messageIDs.indexOf(messageId);
        if (at < 0)
            return;
        root.messageIDs = root.messageIDs.filter(id => id !== messageId);
        delete root.messageByID[messageId];
        root.makeRequest();
    }

    /**
     * Human-readable reason a request came back with nothing to show.
     */
    function transportErrorText(status: int, code: int): string {
        if (status === 401 || status === 403)
            return Translation.tr("**Request rejected** (HTTP %1). The API key is missing, wrong, or not allowed to use this model.").arg(status);
        if (status === 404)
            return Translation.tr("**Not found** (HTTP 404). The model name or the endpoint is wrong.");
        if (status === 429)
            return Translation.tr("**Rate limited** (HTTP 429). Too many requests, or the quota for this key is used up.");
        if (status >= 500)
            return Translation.tr("**The provider failed** (HTTP %1). Nothing to do but try again.").arg(status);
        if (status >= 400)
            return Translation.tr("**Request failed** (HTTP %1).").arg(status);
        if (code === 28)
            return Translation.tr("**Timed out.** No answer within %1 s.").arg(requester.requestTimeout);
        if (code === 6 || code === 7)
            return Translation.tr("**Could not reach the endpoint.** Check the connection, or whether the local server is running.");
        return Translation.tr("**Request failed** (exit code %1).").arg(code);
    }

    AiRequest {
        id: requester
        apiKeyEnvVarName: root.apiKeyEnvVarName
        scriptPath: root.requestScriptFilePath
        attachScriptPath: Directories.aiAttachScriptPath

        /**
         * Whether any line of this response parsed. curl reports the status
         * after the body, so a failing request looks exactly like a streaming
         * one until it ends: its error JSON goes through the parser, throws,
         * and lands in the bubble as text. Nothing having parsed by the end is
         * what says that text was never an answer.
         */
        onLine: data => {
            if (root.currentRunId.length > 0)
                root.runCoordinator.activity(root.currentRunId, "stream", { "bytes": String(data ?? "").length });
            if (requester.message.thinking)
                requester.message.thinking = false;
            // console.log("[Ai] Raw response line: ", data);

            try {
                const result = requester.strategy.parseResponseLine(data, requester.message);
                // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));
                requester.parsedAny = true;
                root.updateSessionGrounding(requester.message, root.currentRunSessionId);

                const functionCalls = Array.isArray(result.functionCalls) ? result.functionCalls : (result.functionCall ? [result.functionCall] : []);
                if (functionCalls.length > 0)
                    root.handleFunctionCalls(functionCalls, requester.message);
                if (result.tokenUsage) {
                    root.tokenCount.input = result.tokenUsage.input;
                    root.tokenCount.output = result.tokenUsage.output;
                    root.tokenCount.total = result.tokenUsage.total;
                    requester.message.inputTokens = result.tokenUsage.input;
                    requester.message.outputTokens = result.tokenUsage.output;
                    requester.message.totalTokens = result.tokenUsage.total;
                    if (result.tokenUsage.cost >= 0)
                        requester.message.requestCost = result.tokenUsage.cost;
                    const thinkingTokens = result.tokenUsage.thinking ?? -1;
                    root.tokenCount.thinking = thinkingTokens;
                    // Counted per message too: the think block says what this
                    // answer's reasoning cost, not what the chat has cost.
                    if (thinkingTokens >= 0)
                        requester.message.thoughtTokens = thinkingTokens;
                }
                // Some OpenAI-compatible services send their usage frame after
                // the finish reason.  Marking the message done here records a
                // zero-token response before that final frame arrives.  The
                // transport's `onFinished` below is the single terminal point
                // and runs after every streamed frame has been parsed.
            } catch (e) {
                console.log("[AI] Could not parse response: ", e);
                requester.message.rawContent += data;
                requester.message.content += data;
            }
        }

        onRetrying: (attempt, delaySeconds, status) => {
            // Whatever the failed attempt wrote has already been rolled back,
            // so the message goes back to looking like it is being thought
            // about — which it is.
            root.retryMessageId = root.messageIDs.find(id => root.messageByID[id] === requester.message) ?? "";
            root.retryAttempt = attempt;
            root.retryDelaySeconds = delaySeconds;
            root.retryNotice = Translation.tr("Retrying in %1 s (%2/%3)").arg(delaySeconds).arg(attempt).arg(requester.maxRetries);
        }

        onFinished: (reason, status, code) => {
            const message = requester.message;
            root.retryNotice = "";
            root.retryMessageId = "";
            root.retryAttempt = 0;
            root.retryDelaySeconds = 0;
            if (!message)
                return;

            if (reason === "attachmentError") {
                root.attachmentNotice = root.attachmentErrorText(requester.attachmentError);
                const messageId = root.messageIDs.find(id => root.messageByID[id] === message);
                if (messageId !== undefined) {
                    root.messageIDs = root.messageIDs.filter(id => id !== messageId);
                    delete root.messageByID[messageId];
                }
                message.destroy();
                root.sessions.scheduleSave();
                return;
            }

            if (reason === "aborted") {
                root.followUpQueued = false;
                const note = Translation.tr("\n\n*[Stopped]*");
                message.rawContent += note;
                message.content += note;
            } else {
                requester.strategy.onRequestFinished(message);
                // An error is put on the message as an error, not as text: the
                // transcript draws it as a card with a way to send it again.
                // Whatever the provider said about it stays as the body.
                if (reason === "error") {
                    message.errorKind = root.transportErrorKind(status, code);
                    message.errorStatus = status;
                    message.errorText = root.transportErrorText(status, code);
                    // Nothing parsed, so whatever is in the bubble is the
                    // provider's complaint, not an answer. It belongs to the
                    // card, where it can be unfolded, not to the transcript.
                    if (!requester.parsedAny && message.content.length > 0) {
                        message.errorDetails = message.content.trim();
                        message.content = "";
                        message.rawContent = "";
                    }
                }
            }

            message.thinking = false;
            if (!message.done)
                root.markDone(message);

            if (root.currentRunId.length > 0) {
                const finalState = reason === "done" ? "completed" : (reason === "aborted" ? "cancelled" : "failed");
                root.runCoordinator.finish(root.currentRunId, finalState, reason);
            }

            if (message.content.includes("API key not valid") || status === 401 || status === 403) {
                const model = root.models[message.model];
                if (model)
                    root.addApiKeyAdvice(model);
            }

            if (root.followUpQueued && reason === "done") {
                root.followUpQueued = false;
                // AiRequest emits this while Process.onExited is still
                // unwinding. Starting synchronously makes makeRequest see
                // the just-finished transport as running and reject the tool
                // continuation. Queue it for the next event turn, where
                // requestFollowUp also remains safe if another tool arrived.
                Qt.callLater(function() {
                    root.requestFollowUp();
                });
            } else {
                root.followUpQueued = false;
            }
        }
    }

    /**
     * Builds and sends a request for the conversation as it currently stands.
     */
    function makeRequest(submission = null, options = ({})) {
        const pending = submission;
        if (pending && root.pendingSubmissionId !== pending.submissionId)
            return;
        const candidate = pending ? (root.catalog.models[pending.modelId] ?? null) : root.currentModelEntry;
        if (!pending && candidate?.requires_key && !KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData();
        const permission = root.canSubmit(pending ? pending.modelId : root.currentModelId);
        if (!permission.allowed) {
            if (pending && permission.reason !== "keyring-loading") {
                root.failPendingSubmission(permission.reason || "unavailable", Translation.tr("This AI model is no longer available."), permission.recoveryActionIds ?? ["open-models"]);
                return;
            }
            const model = pending ? candidate : root.currentModelEntry;
            if (permission.reason === "missing-key" && model)
                root.addApiKeyAdvice(model);
            else if (permission.reason === "keyring-loading")
                root.addMessage(Translation.tr("The system keyring is still loading. Try sending again in a moment."), root.interfaceRole);
            else if (permission.reason === "disabled")
                root.addMessage(Translation.tr("AI is disabled by the current policy."), root.interfaceRole);
            else
                root.addMessage(Translation.tr("No usable AI model is available. Open Models or AI settings to configure one."), root.interfaceRole);
            return;
        }

        const model = candidate;
        if (!model) {
            if (pending)
                root.failPendingSubmission("model-unavailable", Translation.tr("This AI model is no longer available."), ["open-models"]);
            return;
        }
        if (!pending && requester.running) {
            root.addMessage(Translation.tr("Still answering. Stop the current response before sending another."), root.interfaceRole);
            return;
        }

        // Give the run a stable destination before creating its placeholder.
        // The first user turn may not have been flushed yet because it was
        // typed into a brand-new chat.
        if (!pending && root.sessions.currentId.length === 0)
            root.commitSession(true);
        let requestMessageId = "";
        for (let at = root.messageIDs.length - 1; at >= 0; at--) {
            const candidateMessage = root.messageByID[root.messageIDs[at]];
            if (candidateMessage?.role === "user") {
                requestMessageId = root.messageIDs[at];
                break;
            }
        }

        // Fetch API keys if needed
        if (!pending && model.requires_key && !KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData();

        const profile = pending ? (pending.profile ?? root.responseProfileForModel(model.id)) : root.responseProfileForModel(model.id);
        const strategy = pending ? root.apiStrategies[model.api_format || "openai"] : root.currentApiStrategy;
        strategy.activeThinkingLevel = profile.thinkingLevel;
        const messageArray = root.messageIDs.map(id => root.messageByID[id]);
        const filteredMessageArray = messageArray.filter(message => message.role !== root.interfaceRole);
        // Only what fits goes out. What does not is remembered as a summary
        // rather than dropped in silence, and the transcript is told where
        // the cut landed so it can say so.
        const windowed = root.historyWithinWindow(filteredMessageArray, model);
        root.contextCutMessageId = windowed.cutId;
        root.prunedTurnCount = windowed.pruned.length;
        if (windowed.oversized) {
            const oversizedName = String(windowed.oversized.content ?? Translation.tr("The latest message")).slice(0, 80);
            const message = Translation.tr("This message is too large for the selected model's context window. Shorten it or remove an attachment: %1").arg(oversizedName);
            if (pending)
                root.failPendingSubmission("context-too-large", message, ["shorten-prompt", "remove-attachment", "open-models"]);
            else
                root.addMessage(message, root.interfaceRole, { notice: "submission", errorKind: "context-too-large" });
            return;
        }
        const sessionIdForCompaction = pending?.sessionId || root.sessions.currentId;
        const compactionKey = windowed.pruned.length > 0
            ? root.contextCompactionKey(windowed.pruned, model, sessionIdForCompaction)
            : "";
        if (!options.skipCompaction && windowed.pruned.length > 0 && root.contextSummaryKey !== compactionKey) {
            if (root.pendingContextCompaction?.key === compactionKey)
                return;
            if (root.pendingContextCompaction)
                root.cancelContextCompaction();
            if (pending) {
                pending.state = "compacting";
                root.submissionStateChanged(pending);
            }
            if (root.summarisePruned(windowed.pruned, model, sessionIdForCompaction))
                return;
            // If a provider cannot summarize, preserve the old conversation in
            // a deterministic local fallback and continue with the request.
            root.contextSummary = root.fallbackContextSummary(windowed.pruned);
            root.contextSummaryKey = compactionKey;
        }
        const basePrompt = pending ? pending.systemPrompt : root.systemPrompt;
        const promptWithSummary = root.contextSummary.length > 0
            ? `${basePrompt}\n\n## Earlier in this conversation\n${root.contextSummary}`
            : basePrompt;
        // Tool support is a property of the model, not of its address. A
        // local model that can call functions keeps them; a remote one
        // that cannot does not get them handed over anyway.
        const toolOverride = profile.toolMode;
        const tools = model.tools && (root.onlineAllowed || toolOverride !== "search")
                ? root.toolbox.wireTools(model.api_format, toolOverride)
                : null;

        const data = strategy.buildRequestData(model, windowed.messages, promptWithSummary, pending ? pending.temperature : root.temperature, tools);
        // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

        // Fresh response, fresh counters: a dialect that never reports usage
        // must not inherit the previous answer's numbers — and the usage
        // ledger reads exactly these when the response finishes.
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.thinking = -1;
        root.tokenCount.total = -1;

        /* Create local message object */
        const message = root.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "model": model.id,
            "createdAt": Date.now(),
            "responseMode": profile.responseMode,
            "webMode": profile.webMode,
            "functionExposure": profile.functionExposure,
            "profileFallback": profile.fallbackReason,
            "content": "",
            "rawContent": "",
            "thinking": true,
            "done": false
        });
        const id = idForMessage(message);
        // The map is filled before the list is published: anything
        // watching `messageIDs` synchronously — the Search transcript
        // does — would otherwise look the new id up in a map that does
        // not hold it yet and drop the turn until something else
        // refreshed it.
        root.messageByID[id] = message;
        root.messageIDs = [...root.messageIDs, id];

        const runResult = root.runCoordinator.start(root.sessions.currentId, requestMessageId, id, model.id, "ai");
        if (!runResult.accepted) {
            root.messageIDs = root.messageIDs.filter(messageId => messageId !== id);
            delete root.messageByID[id];
            message.destroy();
            if (pending) {
                root.failPendingSubmission("busy", Translation.tr("AI is busy with another conversation. Open or stop the active run first."), ["open-active-run", "stop-active-run"]);
            } else {
                root.addMessage(Translation.tr("AI is busy with another conversation. Open or stop the active run first."), root.interfaceRole);
            }
            return;
        }
        root.currentRunId = runResult.runId;
        root.currentRunSessionId = runResult.sessionId;
        root.currentRunRequestId = requestMessageId;
        root.currentRunResponseId = id;
        root.runningMessageIDs = root.messageIDs.slice();
        root.runningMessageByID = Object.assign({}, root.messageByID);
        root.conversations.capture(root.currentRunSessionId, root.sessionToJson());
        if (pending) {
            pending.responseMessageId = id;
            pending.insertedIds = [...pending.insertedIds, id];
            pending.insertedObjects[id] = message;
            pending.runId = runResult.runId;
            pending.sessionId = runResult.sessionId;
            pending.prepared = {
                model: model,
                strategy: strategy,
                message: message,
                endpoint: strategy.buildEndpoint(model),
                requestData: data,
                apiKey: model.requires_key ? (root.apiKeys?.[model.key_id] ?? "") : ""
            };
            pending.state = "staging";
            pending.stageOperationId = root.sessions.stageSubmission(root.sessionToJson(), root.submissionOperationId("stage"));
            root.submissionStateChanged(pending);
            if (!pending.stageOperationId)
                root.failPendingSubmission("save-failed", Translation.tr("The message could not be staged, so it was not sent."), ["retry-submit"]);
            return;
        }

        // Internal continuations (tool follow-up, regenerate, continue,
        // edit-and-resend) skip the durable staging pipeline above, which is
        // the only place a run is otherwise moved out of "preparing". Left
        // there, the first `activity()`/`finish()` call this run receives
        // (`streaming`, then `completed`) is an illegal transition from
        // "preparing" and is silently rejected — the run never reaches a
        // terminal state, `activeRunId` never clears, and every later
        // submission anywhere (including a brand-new chat) is refused as
        // "busy" forever, until the shell restarts.
        root.runCoordinator.transition(runResult.runId, "thinking", "followUp", {
            "executionStarted": false,
            "networkStartedAt": Date.now()
        });
        root.commitSession(true);
        requester.model = model;
        requester.strategy = strategy;
        requester.message = message;
        requester.endpoint = strategy.buildEndpoint(model);
        requester.requestData = data;
        requester.apiKey = model.requires_key ? (root.apiKeys?.[model.key_id] ?? "") : "";
        requester.parsedAny = false;
        requester.start();
    }

    /**
     * Stops the answer being written, keeping whatever arrived so far.
     */
    function stopGeneration(): bool {
        root.followUpQueued = false;
        root.pendingToolCalls = [];
        root.activeToolCallId = "";
        // Nothing new starts, and whatever was waiting stops waiting. A
        // mutation already sent stays sent — the broker says so rather than
        // pretending it was undone.
        root.broker.cancelAll(Translation.tr("Stopped"));
        // The cancellation above is bookkeeping only — the broker has no
        // handle on an OS process a handler already started. Left alone,
        // each of these keeps running to completion after "Stop", wasting
        // the roundtrip and leaving a shared Process busy for whatever the
        // next run tries to use it for.
        if (commandExecutionProc.running)
            commandExecutionProc.running = false;
        if (filesToolProc.running)
            filesToolProc.running = false;
        if (ocrToolProc.running)
            ocrToolProc.running = false;
        if (webToolProc.running)
            webToolProc.running = false;
        if (ragToolProc.running)
            ragToolProc.running = false;
        if (root.pendingSongIdentify) {
            root.pendingSongIdentify = null;
            root.mediaIntegration.stopIdentify();
        }
        if (root.pendingSubmissionId.length > 0 && !requester.running)
            return root.cancelPendingSubmission("user");
        return requester.abort();
    }

    /**
     * Sends the next turn of a tool exchange. The call that asks for it is
     * answered from inside the stream that is still running, and a request
     * never replaces one in flight, so it waits for that stream to end.
     */
    function requestFollowUp() {
        if (root.pendingToolCalls.length > 0) {
            root.processNextToolCall();
            return;
        }
        if (requester.running) {
            root.followUpQueued = true;
            return;
        }
        root.makeRequest();
    }

    function sendUserMessage(message) {
        const files = root.attachments;
        if (root.pendingAttachmentCount > 0) {
            root.attachmentNotice = Translation.tr("Still checking attachments. Try sending again in a moment.");
            return {
                accepted: false,
                state: "rejected",
                errorCode: "attachments-pending"
            };
        }
        // The files go with the question, not the answer. `submit` keeps the
        // immutable copy until the durable checkpoint is acknowledged.
        return root.submit(message, {
            "attachments": files
        }, "chat");
    }

    /**
     * Attaches a region snip once the file exists.
     *
     * Called by RegionSelection.qml, whose own process is detached and whose
     * window is gone a moment later, so the waiting is done here: this is a
     * singleton and outlives the selector. What this replaced read the
     * clipboard after a fixed delay, and so attached the shot only when the
     * machine happened to be quick enough.
     */
    function attachSnip(path: string) {
        if (!path || path.length === 0)
            return;
        snipWaitProc.attachPath = path;
        snipWaitProc.running = false;
        snipWaitProc.running = true;
    }

    Process {
        id: snipWaitProc
        property string attachPath: ""
        // Four seconds at most: a crop of a screen takes a fraction of one,
        // and a wait that never ends would hold a stale path forever.
        command: ["bash", "-c", `for i in $(seq 1 40); do [ -s '${CF.StringUtils.shellSingleQuoteEscape(snipWaitProc.attachPath)}' ] && exit 0; sleep 0.1; done; exit 1`]
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("[Ai] Region snip never appeared at", snipWaitProc.attachPath);
                return;
            }
            root.attachFile(snipWaitProc.attachPath);
        }
    }

    /**
     * Asks for files with whatever portal-backed dialog the system has.
     *
     * It lives here rather than in the sidebar because the sidebar is
     * unloaded the moment it loses focus — which is exactly what opening a
     * file dialog does. The picker used to be a Process owned by the chat
     * panel, so the dialog was killed together with its owner and nothing
     * ever arrived in the tray.
     */
    readonly property bool pickingFiles: filePickerProc.running
    signal filePickerFinished(int count)

    function pickFiles() {
        if (filePickerProc.running)
            return;
        filePickerProc.running = true;
    }

    Process {
        id: filePickerProc
        running: false
        // `--separate-output` is what makes kdialog put one path per line;
        // without it several files come back on one line, quoted, and the
        // whole selection was handed to the prober as a single bad path.
        command: ["bash", "-c", "if command -v kdialog >/dev/null 2>&1; then " + "  kdialog --getopenfilename \"$HOME\" \"\" --multiple --separate-output 2>/dev/null; " + "elif command -v zenity >/dev/null 2>&1; then " + "  zenity --file-selection --multiple --separator='|' 2>/dev/null; " + "elif command -v yad >/dev/null 2>&1; then " + "  yad --file --multiple --separator='|' 2>/dev/null; " + "else " + "  echo '__no_picker__'; " + "fi"]

        stdout: StdioCollector {
            id: filePickerCollector

            onStreamFinished: {
                const raw = String(filePickerCollector.text ?? "").trim();
                if (raw === "__no_picker__") {
                    root.attachmentNotice = Translation.tr("No file dialog is installed. Install kdialog or zenity, or drag the file onto the composer.");
                    root.filePickerFinished(0);
                    return;
                }
                // Either separator survives: a picker that ignores the flag
                // still gets read rather than handing over one long path.
                const paths = raw.split(/[\n|]/).map(path => path.trim()).filter(path => path.length > 0);
                paths.forEach(path => root.attachFile(path));
                root.filePickerFinished(paths.length);
            }
        }
    }

    // ── Attachments ───────────────────────────────────────────────────────
    // Files waiting to go out with the next message. Each one is looked at
    // before it reaches the tray: what it is decides whether the model can
    // read it at all, and how big it is decides whether it may be sent.
    // Nothing is rejected silently — the old drop area simply ignored files
    // on any provider that was not Google, which reads as the drop not
    // registering.

    property var attachments: []
    /** Why the last file was turned away. The composer shows it and clears it. */
    property string attachmentNotice: ""

    readonly property int maxAttachments: Math.max(1, Config.options?.ai?.maxAttachments ?? 6)
    readonly property int maxAttachmentBytes: Math.max(1, Config.options?.ai?.maxAttachmentMib ?? 8) * 1024 * 1024
    // Text goes in as text, so the limit is about the context window rather
    // than about what the request can carry.
    readonly property int maxTextAttachmentBytes: 256 * 1024
    readonly property int maxContextAttachmentBytes: 16 * 1024

    /** Whether the model in use can take files at all, kinds aside. */
    readonly property bool currentModelTakesFiles: root.currentModelEntry?.attachments ?? false
    /** Whether the model in use can look at images at all. */
    readonly property bool currentModelSupportsVision: root.currentModelEntry?.vision ?? false

    function humanSize(bytes: int): string {
        if (bytes >= 1024 * 1024)
            return Translation.tr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1));
        if (bytes >= 1024)
            return Translation.tr("%1 kB").arg(Math.round(bytes / 1024));
        return Translation.tr("%1 B").arg(bytes);
    }

    /**
     * Whether the model in use can be handed this kind of file as a file.
     *
     * Only Gemini and Anthropic take documents in the request; the
     * OpenAI-compatible dialect has no block for one, and used to drop it on
     * the way out without saying so. Everything else that is not an image is
     * turned into text here first.
     */
    function modelTakesDocumentsFor(model): bool {
        const format = String(model?.api_format ?? "");
        return !!model?.attachments && (format === "gemini" || format === "anthropic");
    }

    function modelTakesDocuments(): bool {
        return root.modelTakesDocumentsFor(root.currentModelEntry);
    }

    /** Revalidates the immutable attachment snapshot at submit time. */
    function attachmentRejectionForModel(files: var, model): string {
        const list = Array.from(files ?? []);
        for (let i = 0; i < list.length; i++) {
            const file = list[i] ?? ({});
            const name = String(file.name ?? Translation.tr("That file"));
            const kind = String(file.kind ?? "");
            if (kind === "context") {
                if (String(file.content ?? "").length === 0)
                    return Translation.tr("%1 is no longer available. Attach it again if you still want to send it.").arg(name);
                if (Number(file.bytes ?? 0) > root.maxContextAttachmentBytes)
                    return Translation.tr("%1 is too large for one context attachment.").arg(name);
                continue;
            }
            if (kind === "text") {
                if (Number(file.bytes ?? 0) > root.maxTextAttachmentBytes)
                    return Translation.tr("%1 is too large for this message.").arg(name);
                continue;
            }
            if (kind === "image") {
                if (!model?.attachments || !model?.vision)
                    return Translation.tr("%1 cannot look at images with the selected model.").arg(name);
                if (Number(file.bytes ?? 0) > root.maxAttachmentBytes)
                    return Translation.tr("%1 is too large for the selected model.").arg(name);
                continue;
            }
            if (!file.extracted && !root.modelTakesDocumentsFor(model))
                return Translation.tr("%1 was attached for another model. Reattach it after choosing a document-capable model.").arg(name);
            if (Number(file.bytes ?? 0) > root.maxAttachmentBytes && !file.extracted)
                return Translation.tr("%1 is too large for the selected model.").arg(name);
        }
        return "";
    }

    /**
     * What should happen to a probed file: send it as it is, read it here
     * first, or turn it away with a reason. Nothing is ever accepted and then
     * quietly left out of the request.
     */
    function attachmentPlan(file: var): var {
        const modelName = root.currentModelEntry?.title ?? Translation.tr("This model");
        const kind = String(file?.kind ?? "");
        if (kind === "text") {
            if (file.bytes > root.maxTextAttachmentBytes)
                return { action: "reject", reason: Translation.tr("%1 is %2 of text — too much to put in one message.").arg(file.name).arg(root.humanSize(file.bytes)) };
            return { action: "send" };
        }
        if (kind === "image") {
            if (!root.currentModelTakesFiles || !root.currentModelSupportsVision)
                return { action: "reject", reason: Translation.tr("%1 cannot look at images.").arg(modelName) };
            if (file.bytes > root.maxAttachmentBytes)
                return { action: "reject", reason: Translation.tr("%1 is %2. The limit is %3.").arg(file.name).arg(root.humanSize(file.bytes)).arg(root.humanSize(root.maxAttachmentBytes)) };
            return { action: "send" };
        }
        // Documents, audio, video.
        const canExtract = (file?.extractable === true) && (Config.options?.ai?.extractDocuments ?? true);
        if (root.modelTakesDocuments() && file.bytes <= root.maxAttachmentBytes)
            return { action: "send" };
        if (canExtract)
            return { action: "extract" };
        if (!root.currentModelTakesFiles)
            return { action: "reject", reason: Translation.tr("%1 cannot read files, and this one cannot be turned into text here.").arg(modelName) };
        if (file.bytes > root.maxAttachmentBytes)
            return { action: "reject", reason: Translation.tr("%1 is %2. The limit is %3.").arg(file.name).arg(root.humanSize(file.bytes)).arg(root.humanSize(root.maxAttachmentBytes)) };
        return { action: "reject", reason: Translation.tr("%1 cannot read %2 files.").arg(modelName).arg(file.kind === "pdf" ? "PDF" : file.kind) };
    }

    /** Empty when the file may be sent, otherwise the reason it may not. */
    function attachmentRejection(file: var): string {
        const modelName = root.currentModelEntry?.title ?? Translation.tr("This model");
        if (file.kind === "text") {
            if (file.bytes > root.maxTextAttachmentBytes)
                return Translation.tr("%1 is %2 of text — too much to put in one message.").arg(file.name).arg(root.humanSize(file.bytes));
            return "";
        }
        if (!root.currentModelTakesFiles)
            return Translation.tr("%1 cannot read files. Pick a model that can, or paste the text in.").arg(modelName);
        if (file.kind === "image" && !root.currentModelSupportsVision)
            return Translation.tr("%1 cannot look at images.").arg(modelName);
        if (file.bytes > root.maxAttachmentBytes)
            return Translation.tr("%1 is %2. The limit is %3.").arg(file.name).arg(root.humanSize(file.bytes)).arg(root.humanSize(root.maxAttachmentBytes));
        return "";
    }

    /**
     * Adds a file to the next message. An empty path detaches everything,
     * which is what Escape in the composer and `/attach` with no argument
     * have always meant.
     */
    property int attachmentGeneration: 0
    property var probeQueue: []
    property var pendingAttachmentPaths: []
    property string activeProbePath: ""
    property int activeProbeGeneration: -1
    readonly property int pendingAttachmentCount: root.pendingAttachmentPaths.length

    function attachFile(filePath: string) {
        const path = CF.FileUtils.trimFileProtocol(String(filePath ?? "")).trim();
        if (path.length === 0) {
            root.clearAttachments();
            return;
        }
        if (root.attachments.some(file => file.path === path) || root.pendingAttachmentPaths.indexOf(path) >= 0)
            return;
        if (root.attachments.length + root.pendingAttachmentPaths.length >= root.maxAttachments) {
            root.attachmentNotice = Translation.tr("%1 files is as many as one message takes.").arg(root.maxAttachments);
            return;
        }
        root.pendingAttachmentPaths = [...root.pendingAttachmentPaths, path];
        root.probeQueue = [...root.probeQueue, {
                path: path,
                generation: root.attachmentGeneration
            }];
        root.runProbe();
    }

    function removeAttachment(index: int) {
        if (index < 0 || index >= root.attachments.length)
            return;
        root.attachments = root.attachments.filter((file, at) => at !== index);
    }

    function attachContext(context: var): bool {
        const candidate = context ?? ({});
        if (candidate.error) {
            root.attachmentNotice = String(candidate.error);
            return false;
        }
        if (String(candidate.kind ?? "") !== "context" || String(candidate.content ?? "").length === 0) {
            root.attachmentNotice = Translation.tr("This context could not be attached.");
            return false;
        }
        if (Number(candidate.bytes ?? 0) > root.maxContextAttachmentBytes) {
            root.attachmentNotice = Translation.tr("This context is too large to attach.");
            return false;
        }
        if (root.attachments.length + root.pendingAttachmentPaths.length >= root.maxAttachments) {
            root.attachmentNotice = Translation.tr("%1 files is as many as one message takes.").arg(root.maxAttachments);
            return false;
        }
        root.attachments = [...root.attachments, candidate];
        root.attachmentNotice = "";
        return true;
    }

    function attachClipboardContext(): bool {
        return root.attachContext(root.shellContext.clipboardContext());
    }

    function attachLauncherContext(): bool {
        return root.attachContext(root.shellContext.launcherContext());
    }

    /**
     * Attaches the active window: its name and title always ride along as
     * the caption, and either the window itself (a model that can look at
     * it) or what tesseract can read off it (a model that cannot) goes with
     * it. A model with neither capability still gets the metadata alone -
     * never worse than what this attached before screenshots existed here.
     */
    function attachActiveWindowContext(): bool {
        const toplevel = ToplevelManager.activeToplevel;
        const appId = String(toplevel?.appId ?? "");
        if (appId.length === 0) {
            root.attachmentNotice = Translation.tr("There is no active application to attach.");
            return false;
        }
        if (activeWindowCaptureProc.running || activeWindowOcrProc.running) {
            root.attachmentNotice = Translation.tr("Still capturing the active window. Try again in a moment.");
            return false;
        }
        if (!root.currentModelSupportsVision && !root.ocrAvailable)
            return root.attachContext(root.shellContext.activeWindowContext());
        const client = HyprlandData.clientForToplevel(toplevel);
        const at = Array.isArray(client?.at) ? client.at : null;
        const size = Array.isArray(client?.size) ? client.size : null;
        if (!at || !size || size[0] <= 0 || size[1] <= 0)
            // No Hyprland geometry for this toplevel (e.g. a layer-shell
            // surface) - the metadata-only path is all that is possible.
            return root.attachContext(root.shellContext.activeWindowContext());
        root.activeWindowCaptureLabel = root.shellContext.activeWindowLabel(toplevel);
        const dir = Directories.screenshotTemp;
        const path = `${dir}/ai-window-${Date.now()}.png`;
        root.activeWindowCapturePath = path;
        const geometry = `${at[0]},${at[1]} ${size[0]}x${size[1]}`;
        activeWindowCaptureProc.command = ["bash", "-c", `mkdir -p '${CF.StringUtils.shellSingleQuoteEscape(dir)}' && grim -g '${geometry}' '${CF.StringUtils.shellSingleQuoteEscape(path)}'`];
        activeWindowCaptureProc.running = true;
        return true;
    }

    property string activeWindowCapturePath: ""
    property string activeWindowCaptureLabel: ""

    Timer {
        id: activeWindowCaptureWatchdog
        interval: 10000
        repeat: false
        onTriggered: {
            if (!activeWindowCaptureProc.running)
                return;
            activeWindowCaptureProc.running = false;
            root.attachmentNotice = Translation.tr("Capturing the active window took too long, and was skipped.");
        }
    }

    Process {
        id: activeWindowCaptureProc
        onRunningChanged: {
            if (activeWindowCaptureProc.running)
                activeWindowCaptureWatchdog.restart();
            else
                activeWindowCaptureWatchdog.stop();
        }
        onExited: exitCode => {
            const path = root.activeWindowCapturePath;
            if (exitCode !== 0 || path.length === 0) {
                root.attachmentNotice = Translation.tr("Could not capture the active window.");
                return;
            }
            if (root.currentModelSupportsVision) {
                root.attachFile(path);
                return;
            }
            activeWindowOcrProc.capturePath = path;
            activeWindowOcrProc.command = ["tesseract", path, "stdout"];
            activeWindowOcrProc.running = true;
        }
    }

    Timer {
        id: activeWindowOcrWatchdog
        interval: 20000
        repeat: false
        onTriggered: {
            if (!activeWindowOcrProc.running)
                return;
            activeWindowOcrProc.running = false;
            root.attachmentNotice = Translation.tr("Reading the active window's screen text took too long, and was skipped.");
        }
    }

    Process {
        id: activeWindowOcrProc
        property string capturePath: ""
        onRunningChanged: {
            if (activeWindowOcrProc.running)
                activeWindowOcrWatchdog.restart();
            else
                activeWindowOcrWatchdog.stop();
        }
        stdout: StdioCollector {
            id: activeWindowOcrCollector
            onStreamFinished: {
                const path = activeWindowOcrProc.capturePath;
                if (path.length > 0)
                    Quickshell.execDetached(["rm", "-f", path]);
                const text = String(activeWindowOcrCollector.text ?? "").trim();
                if (text.length === 0) {
                    root.attachmentNotice = Translation.tr("No text was found on %1's screen.").arg(root.activeWindowCaptureLabel);
                    return;
                }
                const label = root.activeWindowCaptureLabel;
                root.attachContext(root.shellContext.makeContext("window", "active-window-ocr", Translation.tr("Active application (screen text)"), `${label}\n\n${text}`, true));
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && activeWindowOcrCollector.text.length === 0) {
                const path = activeWindowOcrProc.capturePath;
                if (path.length > 0)
                    Quickshell.execDetached(["rm", "-f", path]);
                root.attachmentNotice = Translation.tr("Could not read the active window's screen text.");
            }
        }
    }

    function clearAttachments() {
        root.attachmentGeneration += 1;
        root.probeQueue = [];
        root.extractQueue = [];
        root.activeExtract = null;
        root.pendingAttachmentPaths = [];
        root.activeProbePath = "";
        root.activeProbeGeneration = -1;
        if (probeProc.running)
            probeProc.running = false;
        if (activeWindowCaptureProc.running)
            activeWindowCaptureProc.running = false;
        if (activeWindowOcrProc.running)
            activeWindowOcrProc.running = false;
        root.attachments = [];
        root.attachmentNotice = "";
    }

    /**
     * Suggestions inserted by `@` in either composer. They describe only
     * context the user can already see or explicitly attached; resolving one
     * expands its marker in the outgoing message and never starts a tool.
     */
    function composerReferenceSources(): var {
        const list = [];
        const activeWindow = HyprlandData.activeWindow;
        if (activeWindow?.class) {
            list.push({
                token: "window",
                icon: "web_asset",
                label: Translation.tr("Window in front"),
                detail: String(activeWindow.title ?? activeWindow.class),
                resolve: () => `[[ ${Translation.tr("Window in front")} ]]\nclass: ${activeWindow.class}\ntitle: ${activeWindow.title ?? ""}`
            });
        }
        const clipboard = String(Quickshell.clipboardText ?? "");
        if (clipboard.length > 0) {
            list.push({
                token: "clipboard",
                icon: "content_paste",
                label: Translation.tr("Clipboard"),
                detail: clipboard.slice(0, 60).replace(/\n/g, " "),
                resolve: () => `[[ ${Translation.tr("Clipboard")} ]]\n${clipboard}`
            });
        }
        const attachments = Array.from(root.attachments ?? []);
        for (let index = 0; index < attachments.length; index++) {
            const file = attachments[index];
            list.push({
                token: `file:${index + 1}`,
                icon: "description",
                label: String(file?.name ?? Translation.tr("Attached file")),
                detail: Translation.tr("Attached file"),
                resolve: () => `[[ ${String(file?.name ?? Translation.tr("Attached file"))} ]]`
            });
        }
        const sessions = Array.from(root.sessions.index ?? []).slice(0, 8);
        for (let index = 0; index < sessions.length; index++) {
            const entry = sessions[index];
            if (!entry?.title || entry.id === root.sessions.currentId)
                continue;
            list.push({
                token: `chat:${index + 1}`,
                icon: "forum",
                label: String(entry.title),
                detail: Translation.tr("Earlier chat"),
                resolve: () => `[[ ${Translation.tr("From the chat “%1”").arg(String(entry.title))} ]]\n${String(entry.preview ?? "")}`
            });
        }
        return list;
    }

    function expandComposerReferences(text: string): string {
        let expanded = String(text ?? "");
        const sources = root.composerReferenceSources();
        for (let index = 0; index < sources.length; index++) {
            const source = sources[index];
            const marker = `@${source.token}`;
            if (expanded.indexOf(marker) >= 0)
                expanded = expanded.split(marker).join(`\n\n${source.resolve()}\n\n`);
        }
        return expanded.trim();
    }

    function runProbe() {
        if (probeProc.running || root.probeQueue.length === 0)
            return;
        const job = root.probeQueue[0];
        root.probeQueue = root.probeQueue.slice(1);
        root.activeProbePath = job.path;
        root.activeProbeGeneration = job.generation;
        probeProc.command = ["python3", Directories.aiAttachScriptPath, "probe", job.path];
        probeProc.running = true;
    }

    function acceptProbed(raw: string, path: string, generation: int) {
        if (generation !== root.attachmentGeneration || path !== root.activeProbePath)
            return;
        root.pendingAttachmentPaths = root.pendingAttachmentPaths.filter(item => item !== path);
        let file;
        try {
            file = JSON.parse(raw.trim());
        } catch (e) {
            root.attachmentNotice = Translation.tr("Could not read that file.");
            return;
        }
        if (file.error) {
            root.attachmentNotice = file.error;
            return;
        }
        const plan = root.attachmentPlan(file);
        if (plan.action === "reject") {
            root.attachmentNotice = plan.reason;
            return;
        }
        if (root.attachments.length >= root.maxAttachments)
            return;
        if (root.attachments.some(item => item.path === file.path))
            return;
        if (plan.action === "extract") {
            // Read here rather than sent: the chip stays in the tray with a
            // note saying so, instead of the file being silently left out.
            root.attachmentNotice = "";
            root.extractQueue = [...root.extractQueue, {
                    file: file,
                    generation: generation
                }];
            root.runExtract();
            return;
        }
        root.attachmentNotice = "";
        root.attachments = [...root.attachments, file];
    }

    // ── Reading a document here ───────────────────────────────────────────
    property var extractQueue: []
    property var activeExtract: null

    function runExtract() {
        if (extractProc.running || root.extractQueue.length === 0)
            return;
        const job = root.extractQueue[0];
        root.extractQueue = root.extractQueue.slice(1);
        root.activeExtract = job;
        extractProc.command = ["python3", Directories.aiAttachScriptPath, "extract", job.file.path];
        extractProc.running = true;
    }

    function acceptExtracted(raw: string, job: var) {
        if (!job || job.generation !== root.attachmentGeneration)
            return;
        let result;
        try {
            result = JSON.parse(raw.trim());
        } catch (e) {
            root.attachmentNotice = Translation.tr("Could not read %1 on this machine.").arg(job.file.name);
            return;
        }
        if (result.error || String(result.text ?? "").length === 0) {
            root.attachmentNotice = Translation.tr("Could not read %1 here: %2").arg(job.file.name).arg(result.error ?? Translation.tr("it came back empty"));
            return;
        }
        if (root.attachments.some(item => item.path === job.file.path))
            return;
        // The preview response necessarily exists briefly in the collector;
        // only metadata is retained in the session. The full text is read
        // again at send time, straight into the request body, and is never
        // persisted as chat content.
        root.attachments = [...root.attachments, {
                path: job.file.path,
                name: job.file.name,
                mime: "text/plain",
                kind: "text",
                bytes: Number(result.characters ?? 0),
                extracted: true,
                extractedFrom: job.file.mime,
                truncated: result.truncated === true
            }];
        root.attachmentNotice = result.truncated === true
            ? Translation.tr("%1 was read here as text, and is long enough that the end was left out.").arg(job.file.name)
            : "";
    }

    Timer {
        id: extractWatchdog
        interval: 75000
        repeat: false
        onTriggered: {
            if (!extractProc.running)
                return;
            // A hung `python3 ai_attach.py extract` would otherwise freeze
            // this job - and every job queued behind it - forever. Killing
            // it here lets the existing onExited handler self-heal the
            // queue exactly as it already does for a crash.
            extractProc.running = false;
            const job = root.activeExtract;
            if (job)
                root.attachmentNotice = Translation.tr("Reading %1 took too long, and was skipped.").arg(job.file.name);
        }
    }

    Process {
        id: extractProc
        stdout: StdioCollector {
            id: extractCollector
            onStreamFinished: root.acceptExtracted(extractCollector.text, extractProc.job)
        }
        property var job: null
        onRunningChanged: {
            if (extractProc.running) {
                extractProc.job = root.activeExtract;
                extractWatchdog.restart();
            } else {
                extractWatchdog.stop();
            }
        }
        onExited: {
            root.activeExtract = null;
            Qt.callLater(root.runExtract);
        }
    }

    Timer {
        id: probeWatchdog
        interval: 30000
        repeat: false
        onTriggered: {
            if (!probeProc.running)
                return;
            probeProc.running = false;
            root.attachmentNotice = Translation.tr("Reading that file took too long, and was skipped.");
        }
    }

    Process {
        id: probeProc
        stdout: StdioCollector {
            id: probeCollector
            onStreamFinished: root.acceptProbed(probeCollector.text, probeProc.probePath, probeProc.probeGeneration)
        }
        property string probePath: ""
        property int probeGeneration: -1
        onRunningChanged: {
            if (probeProc.running) {
                probeProc.probePath = root.activeProbePath;
                probeProc.probeGeneration = root.activeProbeGeneration;
                probeWatchdog.restart();
            } else {
                probeWatchdog.stop();
            }
        }
        onExited: {
            root.activeProbePath = "";
            root.activeProbeGeneration = -1;
            Qt.callLater(root.runProbe);
        }
    }

    /** Whether the provider stopped because the answer hit the output limit. */
    function wasTruncated(message): bool {
        const reason = String(message?.finishReason ?? "").toLowerCase();
        return reason === "length" || reason === "max_tokens" || reason === "maxtokens";
    }

    readonly property string continueInstruction: "Continue the previous answer from exactly where it stopped. Do not repeat anything you already wrote, and do not start over."

    /**
     * Picks a cut-off answer back up.
     *
     * The ask goes in as a turn the model can see and the reader cannot, so
     * the transcript stays a conversation rather than gaining an instruction
     * nobody wrote. Regenerating was the only way out before, and it paid for
     * the whole context again to get a different answer.
     */
    function continueMessage(messageId: string) {
        const message = root.messageByID[messageId];
        if (!message || message.role !== "assistant" || requester.running)
            return;
        root.addMessage(root.continueInstruction, "user", {
            "visibleToUser": false
        });
        root.makeRequest();
    }

    /**
     * Asks again for an answer. The old one is not thrown away: the chat is
     * forked first, so the branch that held it stays in the list.
     */
    function regenerate(messageId: string) {
        if (root.messageByID[messageId]?.role !== "assistant")
            return;
        if (!root.forkFrom(messageId, false))
            return;
        root.makeRequest();
    }

    /**
     * Asks again, with another model. The natural next move after a weak
     * answer, and one that used to take four steps.
     */
    function regenerateWith(messageId: string, modelId: string) {
        if (!root.setModel(modelId, false))
            return;
        root.regenerate(messageId);
    }

    /**
     * Rewrites a question and asks it again. Everything that followed it
     * belonged to the old wording, so it stays behind in its own chat.
     */
    function editAndResend(messageId: string, content: string) {
        const message = root.messageByID[messageId];
        if (!message || message.role !== "user")
            return;
        const text = String(content ?? "").trim();
        if (text.length === 0)
            return;
        if (!root.forkFrom(messageId, true))
            return;
        message.content = text;
        message.rawContent = text;
        root.commitSession();
        root.makeRequest();
    }

    /**
     * The turn that carries a tool's output back to the model.
     *
     * It is a real message — the providers read `functionResponse` out of it
     * to build the next request — but it is not something to read. It used to
     * be drawn in the transcript as a bubble from the user containing
     * `[[ Output of settings_search ]]` and a screenful of JSON. What the tool
     * did is already an activity row, and what it found is already a card.
     *
     * `visible` is for the one caller that wants the opposite: a shell command
     * streams its output into this message as it runs, and that is the whole
     * point of it being on screen.
     */
    function createFunctionOutputMessage(name, output, includeOutputInChat = true, callId = "", visible = false) {
        const resolvedCallId = callId || root.activeToolCallId;
        const body = `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`;
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": body,
            "rawContent": body,
            "functionName": name,
            "functionCallId": resolvedCallId,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            "visibleToUser": visible === true
        });
    }

    function addFunctionOutputMessage(name, output, callId = "", sessionId = "") {
        const aiMessage = createFunctionOutputMessage(name, output, true, callId);
        const id = idForMessage(aiMessage);
        const targetSessionId = String(sessionId || root.currentRunSessionId || root.sessions.currentId);
        const belongsToRun = targetSessionId.length > 0
            && targetSessionId === root.currentRunSessionId
            && root.runningMessageIDs.length > 0;
        if (belongsToRun) {
            root.runningMessageIDs = [...root.runningMessageIDs, id];
            root.runningMessageByID[id] = aiMessage;
            if (targetSessionId === root.sessions.currentId) {
                // The map is filled before the list is published: anything
                // watching `messageIDs` synchronously — the Search transcript
                // does — would otherwise look the new id up in a map that does
                // not hold it yet and drop the turn until something else
                // refreshed it.
                root.messageByID[id] = aiMessage;
                root.messageIDs = [...root.messageIDs, id];
            } else {
                root.conversations.capture(targetSessionId, root.runningSessionToJson());
                root.commitRunSession(targetSessionId, false);
            }
            return;
        }
        // The map is filled before the list is published: anything
        // watching `messageIDs` synchronously — the Search transcript
        // does — would otherwise look the new id up in a map that does
        // not hold it yet and drop the turn until something else
        // refreshed it.
        root.messageByID[id] = aiMessage;
        root.messageIDs = [...root.messageIDs, id];
    }

    // ── Tool calls ────────────────────────────────────────────────────────
    // A call either runs, asks first, or is refused, and which of the three
    // is the user's standing answer for that tool rather than a property of
    // the call. Everything the model asks for is written to the log either
    // way: a refusal that leaves no trace is indistinguishable from a tool
    // that was never offered.

    /** Writes the fact the model asked for, and tells it what happened. */
    function commitMemory(message: AiMessageData, factText = "") {
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const fact = String(factText.length > 0 ? factText : (card?.data?.fact ?? "")).trim();
        message.functionPending = false;
        if (fact.length === 0)
            return;
        const stored = AiMemory.remember(fact, "assistant");
        root.updateToolCard(message, key, {
            state: stored ? "done" : "failed",
            summary: stored ? Translation.tr("Remembered") : Translation.tr("Already known")
        });
        root.broker.settle(key, {
            status: stored ? "success" : "error",
            summary: stored ? fact : Translation.tr("Already known"),
            data: stored
                ? Translation.tr("Remembered: %1").arg(fact)
                : Translation.tr("That is already remembered.")
        });
    }

    function rejectMemory(message: AiMessageData) {
        if (!message.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, {
            state: "denied",
            summary: Translation.tr("Not kept")
        });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Not kept"),
            data: Translation.tr("The user chose not to remember that. Do not ask again in this conversation.")
        });
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending)
            return;
        message.functionPending = false; // User decided, no more "thinking"
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, {
            state: "denied",
            summary: Translation.tr("Rejected")
        });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Rejected"),
            data: Translation.tr("Command rejected by user")
        });
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending)
            return;
        // Keep the approval card alive until the journal ACK; the side effect
        // must not begin merely because the click handler ran.
        root.runShellCommand(message, message.functionCall?.args?.command ?? "");
    }

    function failToolExecution(message: AiMessageData, serial: int, reason: string, checkpointSerial = -1, sessionId = "") {
        if (!message)
            return;
        if (root.pendingToolExecution?.message === message)
            root.pendingToolExecution = null;
        message.functionPending = false;
        if (checkpointSerial >= 0 && checkpointSerial !== serial)
            root.recordToolCheckpoint({
                serial: checkpointSerial,
                id: String(message.functionName ?? "tool"),
                title: root.toolbox.titleFor(String(message.functionName ?? "tool")),
                icon: root.toolbox.definitionFor(String(message.functionName ?? "tool"))?.icon ?? "build",
                detail: Translation.tr("Execution was blocked before the side effect."),
                status: "failed",
                outcome: reason,
                at: Date.now()
            });
        root.broker.settle(root.toolKeyFor(message), {
            status: "error",
            summary: reason,
            data: reason,
            retryable: false
        });
    }

    /**
     * Writes an approved side-effect intent and waits for its ACK. The
     * operation itself is started only after a second checkpoint marks the
     * irreversible execution boundary.
     */
    /**
     * A stable fingerprint of what a call was asked to do.
     *
     * Two attempts at the same mutation hash the same, which is what makes it
     * possible to notice a repeat instead of performing it twice. Keys are
     * sorted so the order the model happened to write them in does not change
     * the answer.
     */
    function argsHash(args: var): string {
        const canonical = value => {
            if (value === null || value === undefined)
                return null;
            if (Array.isArray(value))
                return value.map(canonical);
            if (typeof value === "object") {
                const sorted = ({});
                for (const key of Object.keys(value).sort()) {
                    sorted[key] = canonical(value[key]);
                }
                return sorted;
            }
            return value;
        };
        const text = JSON.stringify(canonical(args ?? ({})));
        // Not cryptography: this only has to be stable and cheap, and it is
        // compared against another hash made the same way a moment earlier.
        let hash = 5381;
        for (let i = 0; i < text.length; i++) {
            hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0;
        }
        return `h${hash.toString(36)}${text.length.toString(36)}`;
    }

    /**
     * Writes an approved side effect down and waits for the disk to say so.
     *
     * Any tool that changes something goes through here: the intent is
     * journalled and acknowledged before the irreversible part starts, and a
     * second checkpoint marks the moment it did. If the shell dies between
     * the two, reopening the session finds a record that says the effect may
     * have happened — which is the honest answer, and the reason nothing here
     * retries on its own.
     *
     * `toolId` is the tool's registry id; `payload` is `{args, preview}`.
     */
    function beginToolExecution(message: AiMessageData, toolId: string, payload: var): bool {
        if (!message)
            return false;
        if (root.pendingToolExecution) {
            root.failToolExecution(message, message.toolCallSerial, Translation.tr("Another tool is already being prepared."));
            return false;
        }
        const runId = root.currentRunId;
        const run = root.runCoordinator.runFor(runId);
        const sessionId = root.currentRunSessionId || root.sessions.currentId;
        const approvalKey = root.toolKeyFor(message);
        const approvalIsPending = root.broker.isPending(approvalKey);
        const runIsActive = run && root.runCoordinator.activeStates.includes(run.state);
        const completedRunOwnsApproval = run && run.state === "completed" && approvalIsPending;
        if (!run || (!runIsActive && !completedRunOwnsApproval) || sessionId.length === 0) {
            root.failToolExecution(message, message.toolCallSerial, Translation.tr("This tool call is no longer attached to an active run."));
            return false;
        }
        const id = String(toolId.length > 0 ? toolId : (message.functionName ?? "tool"));
        const args = payload?.args ?? ({});
        const serial = Number(message.toolCallSerial ?? -1);
        const checkpointSerial = serial >= 0 ? serial : -(++root.toolExecutionSequence);
        const hash = root.argsHash(args);
        const entry = {
            serial: checkpointSerial,
            id: id,
            title: root.toolbox.titleFor(id),
            icon: root.toolbox.definitionFor(id)?.icon ?? "build",
            // Described by the registry rather than by a branch on the tool's
            // name, so a new tool gets a readable journal line for free.
            detail: root.toolbox.describeArgs(id, args),
            status: "approved",
            outcome: "",
            at: Date.now(),
            kind: id,
            argsHash: hash
        };
        root.recordToolCheckpoint(entry);
        const operationId = root.commitRunSession(sessionId, true);
        if (!operationId) {
            root.failToolExecution(message, serial, Translation.tr("The tool was not run because its approval could not be saved."), checkpointSerial);
            return false;
        }
        root.pendingToolExecution = {
            operationId: operationId,
            sessionId: sessionId,
            runId: runId,
            message: message,
            toolId: id,
            kind: id,
            args: args,
            argsHash: hash,
            serial: serial,
            checkpointSerial: checkpointSerial,
            phase: "approved"
        };
        return true;
    }

    /**
     * The effect was started and its outcome is unknown.
     *
     * Reached when the shell loses the thread after the irreversible boundary
     * — a request sent with no reply, a process that vanished. Retrying is the
     * one thing that must not happen, because "it might have worked" and "it
     * failed" look identical from here. The card offers to go and look
     * instead.
     */
    function markToolNeedsInspection(message: AiMessageData, reason: string) {
        const pending = root.pendingToolExecution;
        const toolId = String(pending?.toolId ?? message?.functionName ?? "tool");
        if (pending?.message === message)
            root.pendingToolExecution = null;
        if (message)
            message.functionPending = false;
        root.recordToolCheckpoint({
            serial: Number(pending?.checkpointSerial ?? message?.toolCallSerial ?? -1),
            id: toolId,
            title: root.toolbox.titleFor(toolId),
            icon: root.toolbox.definitionFor(toolId)?.icon ?? "build",
            detail: root.toolbox.describeArgs(toolId, pending?.args ?? ({})),
            status: "needsInspection",
            outcome: reason,
            at: Date.now(),
            kind: toolId,
            argsHash: String(pending?.argsHash ?? "")
        });
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, {
            state: "needsInspection",
            summary: reason
        });
        root.broker.settle(key, {
            status: "needsInspection",
            summary: reason,
            data: Translation.tr("This may or may not have taken effect. Do not try it again — check the result first."),
            retryable: false
        });
    }

    function handleToolJournalSaveSucceeded(operationId: string, sessionId: string): bool {
        const pending = root.pendingToolExecution;
        if (!pending || pending.operationId !== operationId || pending.sessionId !== sessionId)
            return false;
        if (pending.phase === "approved") {
            if (!root.runCoordinator.markExecutionStarted(pending.runId, {
                "tool": pending.toolId,
                "toolCallSerial": pending.serial
            })) {
                root.failToolExecution(pending.message, pending.serial, Translation.tr("The run ended before the tool could start."), pending.checkpointSerial, pending.sessionId);
                return true;
            }
            root.recordToolCheckpoint({
                serial: pending.checkpointSerial,
                id: pending.toolId,
                title: root.toolbox.titleFor(pending.toolId),
                icon: root.toolbox.definitionFor(pending.toolId)?.icon ?? "build",
                detail: root.toolbox.describeArgs(pending.toolId, pending.args),
                status: "executionStarted",
                outcome: "",
                at: Date.now(),
                kind: pending.toolId,
                argsHash: pending.argsHash
            });
            pending.phase = "executionStarted";
            pending.operationId = root.commitRunSession(pending.sessionId, true);
            if (!pending.operationId) {
                root.failToolExecution(pending.message, pending.serial, Translation.tr("The tool could not confirm its execution checkpoint."), pending.checkpointSerial);
            }
            return true;
        }
        root.pendingToolExecution = null;
        pending.message.functionPending = false;
        // Past the boundary: what runs here is the side effect itself, chosen
        // by the tool's id rather than by a category the journal invented.
        const starter = root.sideEffectStarters[pending.toolId];
        if (!starter) {
            root.markToolNeedsInspection(pending.message, Translation.tr("%1 was approved but has no way to run.").arg(pending.toolId));
            return true;
        }
        starter(pending);
        return true;
    }

    /**
     * What actually happens after a tool's approval has been journalled.
     *
     * Separate from the handlers above because these run on the far side of
     * the irreversible boundary, possibly a moment after the user clicked and
     * possibly into a session that is no longer the visible one.
     */
    readonly property var sideEffectStarters: ({
            "run_shell_command": pending => root.startShellCommand(pending.message, String(pending.args?.command ?? ""), pending.sessionId),
            "set_shell_config": pending => root.applyConfigChangesNow(pending.message, Array.from(pending.args?.changes ?? []), pending.sessionId),
            "settings_apply_changes": pending => root.applySettingsChangesNow(pending.message, Array.from(pending.args?.changes ?? []), pending.sessionId),
            "reminder_create": pending => root.createReminderNow(pending.message, pending.args, pending.sessionId),
            "alarm_create": pending => root.createAlarmNow(pending.message, pending.args, pending.sessionId),
            "timer_start": pending => root.startTimerNow(pending.message, pending.args, pending.sessionId),
            "calendar_create_event": pending => root.startCalendarMutation(pending),
            "calendar_move_event": pending => root.startCalendarMutation(pending),
            "calendar_delete_event": pending => root.startCalendarMutation(pending),
            "tasks_create": pending => root.startTaskCreate(pending),
            "tasks_update": pending => root.startTaskMutation(pending, "update"),
            "tasks_complete": pending => root.startTaskMutation(pending, "complete"),
            "tasks_delete": pending => root.startTaskMutation(pending, "delete"),
            "notes_append": pending => root.appendNoteNow(pending.message, pending.args),
            "notes_create_from_answer": pending => root.createNoteNow(pending.message, pending.args),
            "audio_set": pending => root.applySystemControl(pending.message, pending.args),
            "brightness_set": pending => root.applySystemControl(pending.message, pending.args),
            "dnd_set": pending => root.applySystemControl(pending.message, pending.args),
            "nightlight_set": pending => root.applySystemControl(pending.message, pending.args),
            "theme_set_mode": pending => root.applySystemControl(pending.message, pending.args),
            "window_move_to_workspace": pending => root.applyWindowMove(pending.message, pending.args),
            "wallpaper_set": pending => root.applyWallpaperSet(pending.message, pending.args),
            "media_control": pending => root.applyMediaControl(pending.message, pending.args),
            "song_identify": pending => root.startSongIdentify(pending.message, pending.args)
        })

    function handleToolJournalSaveFailed(operationId: string, sessionId: string, reason: string): bool {
        const pending = root.pendingToolExecution;
        if (!pending || pending.operationId !== operationId || pending.sessionId !== sessionId)
            return false;
        root.pendingToolExecution = null;
        root.failToolExecution(pending.message, pending.serial, Translation.tr("The tool was not run because its journal could not be saved: %1").arg(reason), pending.checkpointSerial, pending.sessionId);
        return true;
    }

    function runShellCommand(message: AiMessageData, command: string) {
        // Checked again at the moment of the side effect, not only when the
        // tool was offered: the policy can change while an approval card sits
        // on screen waiting for someone to come back to it.
        if (!root.toolbox.isAvailable("run_shell_command")) {
            message.functionPending = false;
            root.broker.settle(root.toolKeyFor(message), {
                status: "unavailable",
                summary: root.toolbox.unavailableReason("run_shell_command"),
                data: Translation.tr("Shell commands are not available under the current policy."),
                retryable: false
            });
            return;
        }
        root.beginToolExecution(message, "run_shell_command", { args: { command: command } });
    }

    function startShellCommand(message: AiMessageData, command: string, sessionId = "") {
        // Visible on purpose: the command's output arrives in this message
        // line by line, and watching it is the point.
        const responseMessage = createFunctionOutputMessage(message.functionName, "", false, message.functionCallId, true);
        const id = idForMessage(responseMessage);
        const targetSessionId = String(sessionId || root.currentRunSessionId || root.sessions.currentId);
        const belongsToRun = targetSessionId.length > 0
            && targetSessionId === root.currentRunSessionId
            && root.runningMessageIDs.length > 0;
        if (belongsToRun) {
            root.runningMessageIDs = [...root.runningMessageIDs, id];
            root.runningMessageByID[id] = responseMessage;
            if (targetSessionId === root.sessions.currentId) {
                // The map is filled before the list is published: anything
                // watching `messageIDs` synchronously — the Search transcript
                // does — would otherwise look the new id up in a map that does
                // not hold it yet and drop the turn until something else
                // refreshed it.
                root.messageByID[id] = responseMessage;
                root.messageIDs = [...root.messageIDs, id];
            } else {
                root.conversations.capture(targetSessionId, root.runningSessionToJson());
                root.commitRunSession(targetSessionId, false);
            }
        } else {
            // The map is filled before the list is published: anything
            // watching `messageIDs` synchronously — the Search transcript
            // does — would otherwise look the new id up in a map that does
            // not hold it yet and drop the turn until something else
            // refreshed it.
            root.messageByID[id] = responseMessage;
            root.messageIDs = [...root.messageIDs, id];
        }

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.serial = message.toolCallSerial;
        commandExecutionProc.toolKey = root.toolKeyFor(message);
        commandExecutionProc.shellCommand = command;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        property int serial: -1
        property string toolKey: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: output => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            // A command that was killed rather than finishing tells us nothing
            // about what it had already done. An exit code does; a crash does
            // not, and the difference decides whether trying again is safe.
            if (exitStatus !== 0) {
                root.markToolNeedsInspection(commandExecutionProc.message,
                    Translation.tr("The command was interrupted. Whatever it had already done is done."));
                return;
            }
            // Silent: the command has been streaming into its own message all
            // along, so the model already has the output.
            root.broker.settle(commandExecutionProc.toolKey, {
                status: exitCode === 0 ? "success" : "error",
                summary: Translation.tr("Exit code %1").arg(exitCode),
                data: null,
                silent: true,
                retryable: false
            });
        }
    }

    function describeConfigValue(value): string {
        if (value === undefined)
            return Translation.tr("not set");
        if (value === null)
            return "null";
        if (typeof value === "object") {
            try {
                return JSON.stringify(CF.ObjectUtils.toPlainObject(value));
            } catch (e) {
                return String(value);
            }
        }
        return String(value);
    }

    /**
     * Normalises a settings call into [{key, current, proposed}]. Two shapes
     * arrive: the `changes` list asked for now, and the single key/value pair
     * the older schemas asked for — which models still send from memory.
     * Each change carries the value it would replace, because a diff the user
     * cannot read against the current state is not a review.
     */
    function configChangeList(args: var): var {
        const incoming = [];
        const changes = args?.changes;
        if (changes && typeof changes.length === "number") {
            for (let i = 0; i < changes.length; i++) {
                incoming.push(changes[i]);
            }
        } else if (args?.key !== undefined) {
            incoming.push(args);
        }
        const result = [];
        for (let i = 0; i < incoming.length; i++) {
            const change = incoming[i];
            if (!change || change.key === undefined || change.value === undefined)
                continue;
            const key = String(change.key);
            // Checked here rather than at write time, because the point of the
            // card is to be a review: a key that does not exist, or a value the
            // option cannot take, has to be visible as such before anyone
            // presses Apply.
            const verdict = Config.validateNestedValue(key, change.value);
            result.push({
                key: key,
                current: root.describeConfigValue(Config.getNestedValue(Config.options, key.split("."))),
                proposed: String(change.value),
                valid: verdict.ok,
                reason: verdict.reason
            });
        }
        return result;
    }

    /** Writes the changes the user kept, and tells the model which those were. */
    function applyConfigChanges(message: AiMessageData, changes: var) {
        root.beginToolExecution(message, "set_shell_config", { args: { changes: Array.from(changes ?? []) } });
    }

    function applySettingsChanges(message: AiMessageData, changes: var) {
        const card = root.toolCardFor(message, root.toolKeyFor(message));
        const previewId = String(card?.data?.previewId ?? root.toolKeyFor(message));
        root.beginToolExecution(message, "settings_apply_changes", {
            args: { previewId: previewId, changes: Array.from(changes ?? []) }
        });
    }

    function applyConfigChangesNow(message: AiMessageData, changes: var, sessionId = "") {
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const proposed = Array.from(card?.data?.changes ?? changes ?? []).length;
        message.functionPending = false;
        const kept = Array.from(changes ?? []);
        const results = [];
        let applied = 0;
        for (let i = 0; i < kept.length; i++) {
            const change = kept[i];
            try {
                // Strict: the key came from a model, not from a switch that is
                // bound to it, so an unknown path must fail instead of adding
                // itself to the config.
                const written = Config.setNestedValue(change.key, change.proposed, true);
                results.push(`✓ ${change.key} = ${JSON.stringify(written)}`);
                applied += 1;
            } catch (e) {
                results.push(`❌ ${change.key}: ${e.message ?? e}`);
            }
        }
        if (results.length === 0)
            results.push(Translation.tr("The user kept every setting as it was."));
        root.updateToolCard(message, key, {
            state: applied > 0 ? "done" : "denied",
            summary: Translation.tr("%1 of %2 applied").arg(applied).arg(Math.max(proposed, applied))
        });
        root.broker.settle(key, {
            status: applied > 0 ? "success" : "denied",
            summary: Translation.tr("%1 of %2 applied").arg(applied).arg(Math.max(proposed, applied)),
            data: results.join("\n")
        });
    }

    function applySettingsChangesNow(message: AiMessageData, changes: var, sessionId = "") {
        const key = root.toolKeyFor(message);
        const result = root.settingsIntegration.apply(changes);
        message.functionPending = false;
        root.updateToolCard(message, key, {
            state: result.applied.length > 0 ? "done" : "denied",
            summary: Translation.tr("%1 applied, %2 skipped").arg(result.applied.length).arg(result.skipped.length)
        });
        root.broker.settle(key, {
            status: result.applied.length > 0 ? "success" : "denied",
            summary: Translation.tr("%1 applied, %2 skipped").arg(result.applied.length).arg(result.skipped.length),
            data: result,
            retryable: false
        });
    }

    function rejectConfigChanges(message: AiMessageData) {
        if (!message.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, {
            state: "denied",
            summary: Translation.tr("Rejected")
        });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Rejected"),
            data: Translation.tr("Settings change rejected by user")
        });
    }

    function approveReminder(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        const card = root.toolCardFor(message, root.toolKeyFor(message));
        const reminder = card?.data?.reminder;
        if (!reminder) {
            root.rejectReminder(message);
            return;
        }
        // Persist the absolute instant from the preview rather than the
        // original relative minutes: waiting for approval must not move it.
        root.beginToolExecution(message, "reminder_create", {
            args: { whenAbsolute: reminder.whenAbsolute, label: reminder.label }
        });
    }

    function createReminderNow(message: AiMessageData, args: var, sessionId = "") {
        const key = root.toolKeyFor(message);
        const result = root.timeIntegration.createReminder(args);
        message.functionPending = false;
        if (!result.ok) {
            const summary = Translation.tr("The reminder could not be created");
            root.updateToolCard(message, key, { state: "failed", summary: summary });
            root.broker.settle(key, {
                status: "error",
                summary: summary,
                data: { error: result.reason ?? "alarmCreateFailed" },
                retryable: false
            });
            return;
        }
        root.updateToolCard(message, key, {
            state: "done",
            summary: Translation.tr("Reminder created")
        });
        root.broker.settle(key, {
            status: "success",
            summary: Translation.tr("Reminder created"),
            data: { reminder: result.reminder },
            retryable: false
        });
    }

    function rejectReminder(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, {
            state: "denied",
            summary: Translation.tr("Reminder discarded")
        });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Reminder discarded"),
            data: Translation.tr("The user chose not to create that reminder.")
        });
    }

    function approveAlarm(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        const card = root.toolCardFor(message, root.toolKeyFor(message));
        const alarm = card?.data?.alarm;
        if (!alarm) {
            root.rejectAlarm(message);
            return;
        }
        root.beginToolExecution(message, "alarm_create", {
            args: {
                time: alarm.time,
                label: alarm.label,
                days: Array.from(alarm.days ?? []).map((enabled, index) => enabled ? ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][index] : "").filter(day => day.length > 0)
            }
        });
    }

    function createAlarmNow(message: AiMessageData, args: var, sessionId = "") {
        const key = root.toolKeyFor(message);
        const result = root.timeIntegration.createAlarm(args);
        message.functionPending = false;
        if (!result.ok) {
            const summary = Translation.tr("The recurring alarm could not be created");
            root.updateToolCard(message, key, { state: "failed", summary: summary });
            root.broker.settle(key, {
                status: "error",
                summary: summary,
                data: { error: result.reason ?? "alarmCreateFailed" },
                retryable: false
            });
            return;
        }
        root.updateToolCard(message, key, {
            state: "done",
            summary: Translation.tr("Recurring alarm created")
        });
        root.broker.settle(key, {
            status: "success",
            summary: Translation.tr("Recurring alarm created"),
            data: { alarm: result.alarm },
            retryable: false
        });
    }

    function rejectAlarm(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, {
            state: "denied",
            summary: Translation.tr("Recurring alarm discarded")
        });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Recurring alarm discarded"),
            data: Translation.tr("The user chose not to create that recurring alarm.")
        });
    }

    function approveTimer(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        const card = root.toolCardFor(message, root.toolKeyFor(message));
        const timer = card?.data?.timer;
        if (!timer?.kind) {
            root.rejectTimer(message);
            return;
        }
        root.beginToolExecution(message, "timer_start", { args: { kind: timer.kind } });
    }

    function startTimerNow(message: AiMessageData, args: var, sessionId = "") {
        const key = root.toolKeyFor(message);
        const result = root.timeIntegration.startTimer(args);
        message.functionPending = false;
        if (!result.ok) {
            const summary = Translation.tr("The timer could not be started");
            root.updateToolCard(message, key, { state: "failed", summary: summary });
            root.broker.settle(key, {
                status: "error",
                summary: summary,
                data: { error: result.reason ?? "timerStartFailed" },
                retryable: false
            });
            return;
        }
        const summary = result.alreadyRunning === true
            ? Translation.tr("Timer was already running") : Translation.tr("Timer started");
        root.updateToolCard(message, key, { state: "done", summary: summary });
        root.broker.settle(key, {
            status: "success",
            summary: summary,
            data: { timer: result.timer, alreadyRunning: result.alreadyRunning === true },
            retryable: false
        });
    }

    function rejectTimer(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, {
            state: "denied",
            summary: Translation.tr("Timer start discarded")
        });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Timer start discarded"),
            data: Translation.tr("The user chose not to start that timer.")
        });
    }

    function handleFunctionCalls(calls: var, message: AiMessageData) {
        const list = Array.from(calls ?? []).filter(call => call?.name);
        if (list.length === 0)
            return;
        const known = Array.from(message.toolCalls ?? []);
        const fresh = [];
        list.forEach(call => {
            const normalized = {
                name: String(call.name),
                args: call.args ?? ({}),
                id: String(call.id ?? "")
            };
            const key = normalized.id.length > 0 ? normalized.id : `${normalized.name}:${JSON.stringify(normalized.args)}`;
            const exists = known.some(item => {
                const itemKey = String(item.id ?? "").length > 0 ? String(item.id) : `${item.name}:${JSON.stringify(item.args ?? ({}))}`;
                return itemKey === key;
            });
            if (exists)
                return;
            known.push(normalized);
            fresh.push(normalized);
        });
        if (fresh.length === 0)
            return;
        message.toolCalls = known;
        message.functionCalls = known.map(call => ({
                    name: call.name,
                    args: call.args,
                    id: call.id
                }));
        const wasEmpty = root.pendingToolCalls.length === 0;
        root.pendingToolCalls = root.pendingToolCalls.concat(fresh.map(call => ({
                    call: call,
                    message: message
                })));
        if (wasEmpty)
            root.processNextToolCall();
    }

    function processNextToolCall() {
        if (root.pendingToolCalls.length === 0) {
            root.activeToolCallId = "";
            root.requestFollowUp();
            return;
        }
        const next = root.pendingToolCalls[0];
        root.pendingToolCalls = root.pendingToolCalls.slice(1);
        root.activeToolCallId = String(next.call.id ?? "");
        root.handleFunctionCall(next.call.name, next.call.args, next.message, root.activeToolCallId);
    }

    function handleFunctionCall(name, args: var, message: AiMessageData, callId = "") {
        message.functionName = name;
        message.functionCallId = callId;
        message.functionCall = {
            name: name,
            args: args,
            id: callId
        };
        root.broker.dispatch({
            name: name,
            args: args,
            id: callId
        }, message);
    }

    // ── Tool handlers ─────────────────────────────────────────────────────
    // One function per tool, each next to the state it touches. The broker
    // has already found the definition, checked the arguments against the
    // schema and asked the policy again, so what is left here is the work.

    function toolSettingsFind(call: var): var {
        const query = String(call.args.query ?? "").trim();
        const prefix = call.args.prefix;
        if (query.length === 0 && prefix === undefined)
            return {
                status: "error",
                summary: Translation.tr("Nothing to look for"),
                data: null,
                retryable: true
            };

        if (query.length > 0) {
            const found = Config.findKeys(query, 25);
            return {
                status: "success",
                summary: found.length === 1
                    ? Translation.tr("1 setting found")
                    : Translation.tr("%1 settings found").arg(found.length),
                data: found.length === 0 ? {
                    query: query,
                    matches: [],
                    hint: "No key path contains those words. Try one word, or a broader one, or list a group with `prefix`."
                } : {
                    query: query,
                    matches: found
                }
            };
        }

        const group = String(prefix ?? "").trim();
        const entries = Config.listGroup(group, 60);
        if (entries === null)
            return {
                status: "error",
                summary: Translation.tr("No such group"),
                data: {
                    prefix: group,
                    error: `\`${group}\` is not a group of settings.`,
                    hint: "Pass an empty prefix to see the top level."
                },
                retryable: true
            };
        return {
            status: "success",
            summary: Translation.tr("%1 entries under %2").arg(entries.length).arg(group.length > 0 ? group : "/"),
            data: {
                prefix: group,
                entries: entries,
                hint: "Entries of type `group` hold more options; pass one as `prefix` to open it."
            }
        };
    }

    function toolSettingsGet(call: var): var {
        const wanted = Array.from(call.args.keys ?? []).filter(key => String(key).length > 0);
        if (wanted.length === 0)
            return {
                status: "error",
                summary: Translation.tr("No keys given"),
                data: null,
                retryable: true
            };
        // A cap rather than an error: a model that asks for thirty keys wants
        // an answer, and the answer says which ones it got.
        const capped = wanted.slice(0, 10);
        const values = capped.map(key => {
            const raw = Config.getNestedValue(Config.options, String(key).split("."));
            if (raw === undefined)
                return { key: key, error: "no such setting" };
            const summary = Config.summariseValue(raw, 400);
            return { key: key, type: summary.kind, value: summary.value };
        });
        const missing = values.filter(entry => entry.error !== undefined).length;
        const payload = { settings: values };
        if (wanted.length > capped.length)
            payload.note = `Only the first ${capped.length} keys were read; ask again for the rest.`;
        return {
            status: missing === values.length ? "error" : "success",
            summary: missing > 0
                ? Translation.tr("%1 of %2 read").arg(values.length - missing).arg(values.length)
                : Translation.tr("%1 read").arg(values.length),
            data: payload,
            retryable: missing > 0
        };
    }

    function toolSettingsSearch(call: var): var {
        if (!root.settingsIntegration.ready) {
            root.settingsIntegration.ensureIndex();
            return {
                status: "error",
                summary: Translation.tr("Settings index is preparing"),
                data: { error: "indexPreparing", retryable: true },
                retryable: true
            };
        }
        const query = String(call.args.query ?? "").trim();
        const matches = root.settingsIntegration.search(query, Number(call.args.limit ?? 5));
        const summary = matches.length === 1 ? Translation.tr("1 setting found") : Translation.tr("%1 settings found").arg(matches.length);
        if (matches.length > 0) {
            // The card gets the full record, because it draws the control.
            root.addToolCard(call.message, {
                callId: call.key,
                tool: "settings_search",
                kind: "settingsResults",
                state: "done",
                summary: summary,
                data: { matches: matches }
            });
        }
        return {
            status: "success",
            summary: summary,
            // The model gets key, label, type and value — not the index record
            // with both languages, the synonym list and the byte offsets of
            // the QML it was parsed from.
            data: { query: query, matches: root.settingsIntegration.modelRefs(matches) }
        };
    }

    function toolSettingsGetSemantic(call: var): var {
        if (!root.settingsIntegration.ready) {
            root.settingsIntegration.ensureIndex();
            return { status: "error", summary: Translation.tr("Settings index is preparing"), data: { error: "indexPreparing" }, retryable: true };
        }
        const settings = root.settingsIntegration.get(call.args.keys);
        const missing = settings.filter(setting => setting.error !== undefined).length;
        return {
            status: missing === settings.length ? "error" : "success",
            summary: Translation.tr("%1 settings read").arg(settings.length - missing),
            data: {
                settings: settings.map(setting => setting.error !== undefined
                    ? { key: setting.key, error: setting.error }
                    : root.settingsIntegration.modelRef(setting))
            },
            retryable: missing > 0
        };
    }

    function toolSettingsOpen(call: var): var {
        const pageId = String(call.args.pageId ?? "");
        if (SettingsPageRegistry.pageIndexById(pageId) < 0)
            return { status: "error", summary: Translation.tr("Unknown Settings page"), data: { error: "unknownPage" }, retryable: true };
        GlobalStates.openSettingsPage(pageId, String(call.args.subPage ?? ""), String(call.args.sectionTitle ?? ""));
        return { status: "success", summary: Translation.tr("Opened Settings"), data: { opened: true, pageId: pageId } };
    }

    function rememberSettingsPreview(id: string, preview: var) {
        root.settingsPreviews = Object.assign({}, root.settingsPreviews, { [id]: preview });
    }

    function toolSettingsProposeChanges(call: var): var {
        const message = call.message;
        message.toolCallSerial = call.serial;
        const previewId = String(call.key);
        const preview = root.settingsIntegration.propose(call.args.changes);
        if (preview.changes.length === 0)
            return { status: "error", summary: Translation.tr("Nothing to change"), data: null, retryable: true };
        root.rememberSettingsPreview(previewId, preview);
        root.addToolCard(message, {
            callId: call.key,
            tool: "settings_propose_changes",
            kind: "settingsDiff",
            state: "pending",
            summary: Translation.tr("Settings changes need approval"),
            data: Object.assign({ previewId: previewId }, preview)
        });
        message.functionPending = true;
        return { status: "approval" };
    }

    function toolSettingsApplyChanges(call: var): var {
        const previewId = String(call.args.previewId ?? "");
        const preview = root.settingsPreviews[previewId];
        if (!preview)
            return { status: "error", summary: Translation.tr("That Settings preview is no longer available"), data: { error: "unknownPreview" }, retryable: false };
        const keep = Array.from(call.args.keep ?? []);
        const changes = keep.length === 0 ? preview.changes : preview.changes.filter(change => keep.indexOf(change.key) >= 0);
        return root.toolSettingsProposeChanges({
            message: call.message,
            serial: call.serial,
            key: call.key,
            args: { changes: changes.map(change => ({ key: change.key, value: change.proposed })) }
        });
    }

    function toolReminderCreate(call: var): var {
        const normalized = root.timeIntegration.normalizeReminder(call.args);
        if (!normalized.ok)
            return {
                status: "error",
                summary: Translation.tr("That reminder time is not valid"),
                data: { error: normalized.reason ?? "invalidReminder" },
                retryable: true
            };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "reminder_create",
            kind: "reminderPreview",
            state: "pending",
            summary: Translation.tr("Reminder needs approval"),
            data: { reminder: normalized.reminder }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function toolAlarmCreate(call: var): var {
        const normalized = root.timeIntegration.normalizeAlarm(call.args);
        if (!normalized.ok)
            return {
                status: "error",
                summary: Translation.tr("That recurring alarm is not valid"),
                data: { error: normalized.reason ?? "invalidAlarm" },
                retryable: true
            };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "alarm_create",
            kind: "alarmPreview",
            state: "pending",
            summary: Translation.tr("Recurring alarm needs approval"),
            data: { alarm: normalized.alarm }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function toolAlarmsList(call: var): var {
        const alarms = root.timeIntegration.alarms();
        return {
            status: "success",
            summary: alarms.length === 1 ? Translation.tr("1 active alarm") : Translation.tr("%1 active alarms").arg(alarms.length),
            data: { alarms: alarms }
        };
    }

    function toolTimerStart(call: var): var {
        const normalized = root.timeIntegration.normalizeTimer(call.args);
        if (!normalized.ok)
            return {
                status: "error",
                summary: Translation.tr("That timer is not available"),
                data: { error: normalized.reason ?? "invalidTimer" },
                retryable: true
            };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "timer_start",
            kind: "timerPreview",
            state: "pending",
            summary: normalized.timer.summary,
            data: { timer: normalized.timer }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function toolTimerStatus(call: var): var {
        return {
            status: "success",
            summary: Translation.tr("Timer status read"),
            data: root.timeIntegration.timerStatus()
        };
    }

    function toolCalendarListEvents(call: var): var {
        const result = root.timeIntegration.calendarEvents(call.args);
        if (result.error)
            return {
                status: "error",
                summary: Translation.tr("That calendar date range is not valid"),
                data: { error: result.error },
                retryable: true
            };
        if (!result.available)
            return {
                status: "unavailable",
                summary: Translation.tr("The khal calendar is not available"),
                data: { events: [] },
                retryable: false
            };
        return {
            status: "success",
            summary: result.events.length === 1 ? Translation.tr("1 calendar event") : Translation.tr("%1 calendar events").arg(result.events.length),
            data: { events: result.events }
        };
    }

    function toolCalendarNextEvent(call: var): var {
        const result = root.timeIntegration.nextCalendarEvent();
        if (!result.available)
            return {
                status: "unavailable",
                summary: Translation.tr("The khal calendar is not available"),
                data: { event: null },
                retryable: false
            };
        return {
            status: "success",
            summary: result.event
                ? (result.event.state === "inProgress" ? Translation.tr("Calendar event in progress") : Translation.tr("Next calendar event"))
                : Translation.tr("No upcoming calendar event"),
            data: { event: result.event }
        };
    }

    function calendarMutationTool(call: var, operation: string): var {
        const preview = root.timeIntegration.calendarMutationPreview(operation, call.args);
        if (!preview.ok)
            return {
                status: "error",
                summary: String(preview.error ?? Translation.tr("That calendar change is not valid")),
                data: preview,
                retryable: true
            };
        const toolId = "calendar_" + operation + "_event";
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: toolId,
            kind: "calendarMutationPreview",
            state: "pending",
            summary: operation === "delete" ? Translation.tr("Calendar deletion needs approval") : Translation.tr("Calendar change needs approval"),
            data: { operation: operation, preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function toolCalendarCreateEvent(call: var): var {
        return root.calendarMutationTool(call, "create");
    }

    function toolCalendarMoveEvent(call: var): var {
        return root.calendarMutationTool(call, "move");
    }

    function toolCalendarDeleteEvent(call: var): var {
        return root.calendarMutationTool(call, "delete");
    }

    function approveCalendarMutation(message: AiMessageData): void {
        if (!message?.functionPending || root.pendingToolExecution?.message === message)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const preview = card?.data?.preview;
        const operation = String(preview?.operation ?? "");
        if (!preview || ["create", "move", "delete"].indexOf(operation) < 0) {
            root.rejectCalendarMutation(message);
            return;
        }
        root.beginToolExecution(message, "calendar_" + operation + "_event", { args: preview });
    }

    function rejectCalendarMutation(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Calendar change discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Calendar change discarded"),
            data: Translation.tr("The user chose not to change the calendar."),
            retryable: false
        });
    }

    function finishCalendarMutation(message: AiMessageData, outcome): void {
        const key = root.toolKeyFor(message);
        message.functionPending = false;
        root.updateToolCard(message, key, {
            state: outcome.status === "success" ? "done" : String(outcome.status ?? "error"),
            summary: String(outcome.summary ?? "")
        });
        root.broker.settle(key, outcome);
    }

    function startCalendarMutation(pending): void {
        const outcome = root.timeIntegration.executeCalendarMutation(pending.args, root.toolKeyFor(pending.message), pending.operationId);
        if (outcome.status !== "pending")
            root.finishCalendarMutation(pending.message, outcome);
    }

    function toolWeatherGet(call: var): var {
        return {
            status: "success",
            summary: Translation.tr("Weather read"),
            data: root.timeIntegration.weather()
        };
    }

    function taskReadOutcome(call, outcome): var {
        if (outcome.status === "success" && outcome.data?.tasks) {
            root.addToolCard(call.message, {
                callId: call.key,
                tool: call.tool,
                kind: "taskResults",
                state: "done",
                summary: String(outcome.summary ?? ""),
                data: outcome.data
            });
        }
        return outcome;
    }

    function toolTasksList(call: var): var {
        return root.taskReadOutcome(call, root.tasksIntegration.listTasks(call.args, call.key));
    }

    function toolTasksSearch(call: var): var {
        return root.taskReadOutcome(call, root.tasksIntegration.searchTasks(call.args, call.key));
    }

    function toolTasksCreate(call: var): var {
        const preview = root.tasksIntegration.normalizeCreate(call.args);
        if (!preview.ok)
            return { status: "error", summary: preview.error, data: preview, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "tasks_create",
            kind: "taskPreview",
            state: "pending",
            summary: Translation.tr("Task needs approval"),
            data: { operation: "create", preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function taskMutationPreview(call, operation): var {
        const reference = root.tasksIntegration.normalizeRef(call.args);
        if (!reference.ok)
            return { status: "error", summary: reference.error, data: reference, retryable: true };
        const changes = {};
        if (operation === "update") {
            if (call.args.title !== undefined)
                changes.title = String(call.args.title).trim();
            if (call.args.notes !== undefined)
                changes.notes = String(call.args.notes);
            if (call.args.dueDate !== undefined) {
                const due = root.tasksIntegration.dueDate(call.args.dueDate);
                if (due.error)
                    return { status: "error", summary: due.error, data: due, retryable: true };
                changes.dueDate = due.value;
                changes.dueDateDisplay = due.display;
            }
            if (Object.keys(changes).length === 0)
                return { status: "error", summary: Translation.tr("No task changes were requested"), data: null, retryable: true };
            if (changes.title !== undefined && changes.title.length === 0)
                return { status: "error", summary: Translation.tr("A task needs a title"), data: null, retryable: true };
        }
        return {
            status: "approval",
            preview: {
                operation: operation,
                provider: reference.provider,
                providerId: reference.providerId,
                accountId: reference.accountId,
                listId: reference.listId,
                listName: reference.providerId === "ticktick" ? "TickTick Inbox" : Translation.tr("Local tasks"),
                taskId: reference.taskId,
                title: String(call.args.title ?? ""),
                changes: changes
            }
        };
    }

    function toolTasksUpdate(call: var): var {
        const prepared = root.taskMutationPreview(call, "update");
        if (prepared.status !== "approval")
            return prepared;
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "tasks_update",
            kind: "taskMutationPreview",
            state: "pending",
            summary: Translation.tr("Task update needs approval"),
            data: { operation: "update", preview: prepared.preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function toolTasksComplete(call: var): var {
        const prepared = root.taskMutationPreview(call, "complete");
        if (prepared.status !== "approval")
            return prepared;
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "tasks_complete",
            kind: "taskMutationPreview",
            state: "pending",
            summary: Translation.tr("Task completion needs approval"),
            data: { operation: "complete", preview: prepared.preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function toolTasksDelete(call: var): var {
        const prepared = root.taskMutationPreview(call, "delete");
        if (prepared.status !== "approval")
            return prepared;
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "tasks_delete",
            kind: "taskMutationPreview",
            state: "pending",
            summary: Translation.tr("Deletion always needs approval"),
            data: { operation: "delete", preview: prepared.preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function approveTask(message: AiMessageData): void {
        if (!message?.functionPending || root.pendingToolExecution?.message === message)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const preview = card?.data?.preview;
        if (!preview) {
            root.rejectTask(message);
            return;
        }
        root.beginToolExecution(message, "tasks_create", { args: preview });
    }

    function approveTaskMutation(message: AiMessageData): void {
        if (!message?.functionPending || root.pendingToolExecution?.message === message)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const preview = card?.data?.preview;
        const operation = String(preview?.operation ?? "");
        if (!preview || ["update", "complete", "delete"].indexOf(operation) < 0) {
            root.rejectTaskMutation(message);
            return;
        }
        const args = {
            provider: preview.providerId,
            listId: preview.listId,
            taskId: preview.taskId,
            title: preview.changes?.title,
            notes: preview.changes?.notes,
            dueDate: preview.changes?.dueDate
        };
        root.beginToolExecution(message, "tasks_" + operation, { args: args });
    }

    function rejectTask(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Task discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Task discarded"),
            data: Translation.tr("The user chose not to create that task."),
            retryable: false
        });
    }

    function rejectTaskMutation(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Task change discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Task change discarded"),
            data: Translation.tr("The user chose not to change that task."),
            retryable: false
        });
    }

    function finishTaskMutation(message: AiMessageData, outcome): void {
        const key = root.toolKeyFor(message);
        message.functionPending = false;
        root.updateToolCard(message, key, {
            state: outcome.status === "success" ? "done" : String(outcome.status ?? "error"),
            summary: String(outcome.summary ?? "")
        });
        root.broker.settle(key, outcome);
    }

    function startTaskCreate(pending): void {
        const outcome = root.tasksIntegration.createTask(pending.args, root.toolKeyFor(pending.message), pending.operationId);
        if (outcome.status !== "pending")
            root.finishTaskMutation(pending.message, outcome);
    }

    function startTaskMutation(pending, operation): void {
        let outcome = null;
        const key = root.toolKeyFor(pending.message);
        if (operation === "update")
            outcome = root.tasksIntegration.updateTask(pending.args, key, pending.operationId);
        else if (operation === "complete")
            outcome = root.tasksIntegration.completeTask(pending.args, key, pending.operationId);
        else
            outcome = root.tasksIntegration.deleteTask(pending.args, key, pending.operationId);
        if (outcome.status !== "pending")
            root.finishTaskMutation(pending.message, outcome);
    }

    function notesProvenance(call): var {
        return {
            sessionId: String(root.currentRunSessionId || root.sessions.currentId || ""),
            messageId: String(call?.message?.id ?? call?.message?.messageId ?? "")
        };
    }

    function toolNotesPreviewAppend(call: var): var {
        const args = Object.assign({}, call.args, { provenance: root.notesProvenance(call) });
        const preview = root.notesIntegration.previewAppend(args);
        if (!preview.ok)
            return { status: "error", summary: Translation.tr("That note append is not valid"), data: preview, retryable: true };
        return {
            status: "success",
            summary: Translation.tr("Note append preview ready"),
            data: { preview: preview, destination: preview.destination }
        };
    }

    function toolNotesAppend(call: var): var {
        const preview = root.notesIntegration.previewAppend(Object.assign({}, call.args, { provenance: root.notesProvenance(call) }));
        if (!preview.ok)
            return { status: "error", summary: Translation.tr("That note append is not valid"), data: preview, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "notes_append",
            kind: "notesPreview",
            state: "pending",
            summary: Translation.tr("Note append needs approval"),
            data: { operation: "append", preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function toolNotesCreate(call: var): var {
        const preview = root.notesIntegration.previewCreate(Object.assign({}, call.args, { provenance: root.notesProvenance(call) }));
        if (!preview.ok)
            return { status: "error", summary: Translation.tr("That note is not valid"), data: preview, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "notes_create_from_answer",
            kind: "notesPreview",
            state: "pending",
            summary: Translation.tr("New note needs approval"),
            data: { operation: "create", preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function approveNotes(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const preview = card?.data?.preview;
        if (!preview) {
            root.rejectNotes(message);
            return;
        }
        const args = preview.operation === "append"
            ? { tabIndex: preview.tabIndex, text: preview.text, provenance: preview.provenance }
            : { title: preview.title, text: preview.text, provenance: preview.provenance };
        root.beginToolExecution(message, preview.operation === "append" ? "notes_append" : "notes_create_from_answer", { args: args });
    }

    function rejectNotes(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Note change discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Note change discarded"),
            data: Translation.tr("The user chose not to change notes.")
        });
    }

    function appendNoteNow(message: AiMessageData, args: var): void {
        const result = root.notesIntegration.append(args);
        root.finishNoteAction(message, result, Translation.tr("Note updated"));
    }

    function createNoteNow(message: AiMessageData, args: var): void {
        const result = root.notesIntegration.create(args);
        root.finishNoteAction(message, result, Translation.tr("Note created"));
    }

    function finishNoteAction(message: AiMessageData, result: var, successSummary: string): void {
        const key = root.toolKeyFor(message);
        message.functionPending = false;
        const ok = result?.ok === true;
        const summary = ok ? successSummary : Translation.tr("The note could not be changed");
        root.updateToolCard(message, key, { state: ok ? "done" : "failed", summary: summary });
        root.broker.settle(key, {
            status: ok ? "success" : "error",
            summary: summary,
            data: ok ? { title: result.title, index: result.index, provenance: result.provenance } : result,
            retryable: !ok
        });
    }

    function toolSystemControl(call: var): var {
        const toolId = String(call.tool ?? call.name ?? "");
        const preview = root.systemControlsIntegration.preview(toolId, call.args);
        if (!preview.ok)
            return { status: "error", summary: Translation.tr("That system value is not valid"), data: preview, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: toolId,
            kind: "systemControlPreview",
            state: "pending",
            summary: Translation.tr("System change needs approval"),
            data: { preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function approveSystemControl(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const preview = card?.data?.preview;
        if (!preview) {
            root.rejectSystemControl(message);
            return;
        }
        root.beginToolExecution(message, String(preview.toolId), {
            args: { toolId: preview.toolId, value: preview.value, undo: preview.undo }
        });
    }

    function rejectSystemControl(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("System change discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("System change discarded"),
            data: Translation.tr("The user chose not to change the system.")
        });
    }

    function applySystemControl(message: AiMessageData, args: var): void {
        const result = root.systemControlsIntegration.apply(args);
        const key = root.toolKeyFor(message);
        message.functionPending = false;
        const ok = result?.ok === true;
        const summary = ok ? Translation.tr("System changed") : Translation.tr("The system change failed");
        root.updateToolCard(message, key, { state: ok ? "done" : "failed", summary: summary });
        root.broker.settle(key, {
            status: ok ? "success" : "error",
            summary: summary,
            data: result,
            retryable: !ok
        });
    }

    function toolWindowsList(call: var): var {
        const windows = root.windowsIntegration.list();
        return {
            status: "success",
            summary: windows.length === 1 ? Translation.tr("1 window") : Translation.tr("%1 windows").arg(windows.length),
            data: { windows: windows }
        };
    }

    function toolWindowFocus(call: var): var {
        const result = root.windowsIntegration.focus(call.args);
        return {
            status: result.ok ? "success" : "error",
            summary: result.ok ? Translation.tr("Window focused") : Translation.tr("That window is no longer available"),
            data: result,
            retryable: !result.ok
        };
    }

    function toolWindowMove(call: var): var {
        const preview = root.windowsIntegration.previewMove(call.args);
        if (!preview.ok)
            return { status: "error", summary: Translation.tr("That window move is not valid"), data: preview, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "window_move_to_workspace",
            kind: "windowMovePreview",
            state: "pending",
            summary: Translation.tr("Window move needs approval"),
            data: { preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function approveWindowMove(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const preview = card?.data?.preview;
        if (!preview) {
            root.rejectWindowMove(message);
            return;
        }
        root.beginToolExecution(message, "window_move_to_workspace", {
            args: { address: preview.address, workspace: preview.workspace, fromWorkspace: preview.fromWorkspace }
        });
    }

    function rejectWindowMove(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Window move discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Window move discarded"),
            data: Translation.tr("The user chose not to move that window.")
        });
    }

    function applyWindowMove(message: AiMessageData, args: var): void {
        const result = root.windowsIntegration.move(args);
        const key = root.toolKeyFor(message);
        message.functionPending = false;
        const ok = result?.ok === true;
        const summary = ok ? Translation.tr("Window moved") : Translation.tr("The window could not be moved");
        root.updateToolCard(message, key, { state: ok ? "done" : "failed", summary: summary });
        root.broker.settle(key, { status: ok ? "success" : "error", summary: summary, data: result, retryable: !ok });
    }

    function toolWorkspaceSwitch(call: var): var {
        const result = root.windowsIntegration.switchWorkspace(call.args);
        return {
            status: result.ok ? "success" : "error",
            summary: result.ok ? Translation.tr("Workspace switched") : Translation.tr("That workspace is not valid"),
            data: result,
            retryable: !result.ok
        };
    }

    function toolWallpaperSearch(call: var): var {
        const result = root.themeIntegration.search(call.args.query ?? "", call.args.limit ?? 8);
        return {
            status: "success",
            summary: result.results.length === 1 ? Translation.tr("1 wallpaper found") : Translation.tr("%1 wallpapers found").arg(result.results.length),
            data: result,
            networkUsed: result.networkUsed === true
        };
    }

    function toolWallpaperSet(call: var): var {
        const preview = root.themeIntegration.previewSet(call.args);
        if (!preview.ok)
            return { status: "error", summary: Translation.tr("That wallpaper is not from the configured source"), data: preview, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "wallpaper_set",
            kind: "wallpaperPreview",
            state: "pending",
            summary: Translation.tr("Wallpaper change needs approval"),
            data: { preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function approveWallpaperSet(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const preview = card?.data?.preview;
        if (!preview) {
            root.rejectWallpaperSet(message);
            return;
        }
        root.beginToolExecution(message, "wallpaper_set", {
            args: {
                ref: preview.ref,
                thumbnail: preview.thumbnail,
                previousRef: preview.previousRef,
                undo: preview.undo
            }
        });
    }

    function rejectWallpaperSet(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Wallpaper change discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Wallpaper change discarded"),
            data: Translation.tr("The user chose not to change the wallpaper.")
        });
    }

    function applyWallpaperSet(message: AiMessageData, args: var): void {
        const result = root.themeIntegration.apply(args);
        const key = root.toolKeyFor(message);
        message.functionPending = false;
        const ok = result?.ok === true;
        const summary = ok ? Translation.tr("Wallpaper changed") : Translation.tr("The wallpaper could not be changed");
        root.updateToolCard(message, key, { state: ok ? "done" : "failed", summary: summary });
        root.broker.settle(key, {
            status: ok ? "success" : "error",
            summary: summary,
            data: result,
            retryable: !ok
        });
    }

    function toolMediaStatus(call: var): var {
        const result = root.mediaIntegration.status();
        return {
            status: "success",
            summary: result.available ? Translation.tr("Media status read") : Translation.tr("No active media player"),
            data: result
        };
    }

    function toolMediaControl(call: var): var {
        const preview = root.mediaIntegration.previewControl(call.args);
        if (!preview.ok)
            return { status: "error", summary: Translation.tr("That media action is not available"), data: preview, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "media_control",
            kind: "mediaControlPreview",
            state: "pending",
            summary: Translation.tr("Media change needs approval"),
            data: { preview: preview }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function approveMediaControl(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        const key = root.toolKeyFor(message);
        const preview = root.toolCardFor(message, key)?.data?.preview;
        if (!preview) {
            root.rejectMediaControl(message);
            return;
        }
        root.beginToolExecution(message, "media_control", { args: { action: preview.action } });
    }

    function rejectMediaControl(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Media change discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Media change discarded"),
            data: Translation.tr("The user chose not to change playback.")
        });
    }

    function applyMediaControl(message: AiMessageData, args: var): void {
        const result = root.mediaIntegration.control(args);
        const key = root.toolKeyFor(message);
        message.functionPending = false;
        const ok = result?.ok === true;
        const summary = ok ? Translation.tr("Media changed") : Translation.tr("The media action failed");
        root.updateToolCard(message, key, { state: ok ? "done" : "failed", summary: summary });
        root.broker.settle(key, { status: ok ? "success" : "error", summary: summary, data: result, retryable: !ok });
    }

    function toolLyricsGet(call: var): var {
        const result = root.mediaIntegration.lyrics();
        return {
            status: result.ok ? "success" : (result.loading ? "unavailable" : "error"),
            summary: result.ok ? Translation.tr("Lyrics read") : (result.loading ? Translation.tr("Lyrics are still loading") : Translation.tr("Lyrics are unavailable")),
            data: result,
            networkUsed: result.networkUsed === true,
            retryable: result.loading === true
        };
    }

    function toolSongIdentify(call: var): var {
        if (SongRec.running)
            return { status: "error", summary: Translation.tr("Song identification is already running"), data: { running: true }, retryable: true };
        call.message.toolCallSerial = call.serial;
        root.addToolCard(call.message, {
            callId: call.key,
            tool: "song_identify",
            kind: "songIdentifyPreview",
            state: "pending",
            summary: Translation.tr("Song identification needs approval"),
            data: { preview: { monitorSource: SongRec.monitorSourceString, temporaryAudioDeleted: true } }
        });
        call.message.functionPending = true;
        return { status: "approval" };
    }

    function approveSongIdentify(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        const key = root.toolKeyFor(message);
        const preview = root.toolCardFor(message, key)?.data?.preview;
        if (!preview) {
            root.rejectSongIdentify(message);
            return;
        }
        root.beginToolExecution(message, "song_identify", { args: { monitorSource: preview.monitorSource } });
    }

    function rejectSongIdentify(message: AiMessageData): void {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Song identification discarded") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Song identification discarded"),
            data: Translation.tr("The user chose not to listen to the audio source.")
        });
    }

    function startSongIdentify(message: AiMessageData, args: var): void {
        root.pendingSongIdentify = { message: message, key: root.toolKeyFor(message) };
        const result = root.mediaIntegration.identify(args);
        message.functionPending = false;
        const ok = result?.ok === true;
        if (!ok) {
            root.finishSongIdentify("error", Translation.tr("Song identification could not start"), result);
            return;
        }
        root.updateToolCard(message, root.pendingSongIdentify.key, { state: "running", summary: Translation.tr("Listening for a song"), data: { preview: result } });
    }

    function finishSongIdentify(status: string, summary: string, data: var): void {
        const pending = root.pendingSongIdentify;
        if (!pending)
            return;
        root.pendingSongIdentify = null;
        const message = pending.message;
        const key = pending.key;
        if (message)
            message.functionPending = false;
        const ok = status === "success";
        root.updateToolCard(message, key, { state: ok ? "done" : "failed", summary: summary, data: { result: data } });
        root.broker.settle(key, {
            status: status,
            summary: summary,
            data: data,
            retryable: !ok
        });
    }

    function stopSongIdentify(message: AiMessageData): void {
        const pending = root.pendingSongIdentify;
        if (pending && pending.message === message) {
            root.pendingSongIdentify = null;
            root.mediaIntegration.stopIdentify();
            message.functionPending = false;
            root.updateToolCard(message, pending.key, { state: "done", summary: Translation.tr("Listening stopped") });
            root.broker.settle(pending.key, {
                status: "cancelled",
                summary: Translation.tr("Listening stopped"),
                data: { cancelled: true, temporaryAudioDeleted: true },
                retryable: false
            });
            return;
        }
        const result = root.mediaIntegration.stopIdentify();
        if (!message)
            return;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { summary: result.ok ? Translation.tr("Listening stopped") : Translation.tr("Could not stop listening") });
    }

    function toolSystemGetStatus(call: var): var {
        return {
            status: "success",
            summary: Translation.tr("System status read"),
            data: root.systemIntegration.status()
        };
    }

    function toolSystemHealth(call: var): var {
        return {
            status: "success",
            summary: Translation.tr("System health read"),
            data: root.systemIntegration.health()
        };
    }

    function toolKeybindsSearch(call: var): var {
        const query = String(call.args.query ?? "").trim();
        const matches = root.systemIntegration.keybinds(query, Number(call.args.limit ?? 12));
        return {
            status: "success",
            summary: matches.length === 1 ? Translation.tr("1 shortcut found") : Translation.tr("%1 shortcuts found").arg(matches.length),
            data: { query: query, matches: matches }
        };
    }

    function toolSetShellConfig(call: var): var {
        const message = call.message;
        message.toolCallSerial = call.serial;
        const changes = root.configChangeList(call.args);
        if (changes.length === 0)
            return {
                status: "error",
                summary: Translation.tr("Nothing to change"),
                data: null,
                retryable: true
            };
        // Permission says whether the tool may be used at all; the review
        // switch says whether its work is shown first. Only a tool that is
        // allowed outright, with review off, writes unannounced.
        if (root.toolbox.permission("set_shell_config") === "allow" && !root.toolbox.reviewsConfigChanges) {
            root.applyConfigChanges(message, changes);
            return { status: "pending" };
        }
        root.addToolCard(message, {
            callId: call.key,
            tool: "set_shell_config",
            kind: "settingsDiff",
            state: "pending",
            summary: changes.length === 1
                ? Translation.tr("It wants to change one setting")
                : Translation.tr("It wants to change %1 settings").arg(changes.length),
            data: { changes: changes }
        });
        message.functionPending = true;
        return { status: "approval" };
    }

    function toolRememberFact(call: var): var {
        const message = call.message;
        message.toolCallSerial = call.serial;
        const fact = String(call.args.fact ?? "").trim();
        if (fact.length === 0)
            return {
                status: "error",
                summary: Translation.tr("Nothing to remember"),
                data: null,
                retryable: true
            };
        // Permission decides whether it may write at all; the default is to
        // ask, and asking happens on the turn itself rather than in a dialog
        // over the chat.
        if (root.toolbox.permission("remember_fact") === "allow") {
            root.commitMemory(message, fact);
            return { status: "pending" };
        }
        root.addToolCard(message, {
            callId: call.key,
            tool: "remember_fact",
            kind: "memoryFact",
            state: "pending",
            summary: Translation.tr("It wants to remember something"),
            data: { fact: fact }
        });
        message.functionPending = true;
        return { status: "approval" };
    }

    function toolWeb(call: var, isSearch: bool): var {
        if (root.webMode === "off")
            return {
                status: "unavailable",
                summary: Translation.tr("Web access is turned off for this chat."),
                data: null,
                retryable: false
            };
        if (webToolProc.running)
            return {
                status: "error",
                summary: Translation.tr("Another lookup is already running."),
                data: null,
                retryable: true
            };
        const term = isSearch ? String(call.args.query ?? "") : String(call.args.url ?? "");
        if (term.length === 0)
            return {
                status: "error",
                summary: isSearch ? Translation.tr("Nothing to look up") : Translation.tr("No address given"),
                data: null,
                retryable: true
            };
        const count = Math.max(1, Math.min(10, Number(call.args.count ?? 5)));
        const cacheKey = root.webCacheKey(isSearch, term, count);
        const cached = root.freshWebCache(cacheKey);
        if (cached) {
            if (isSearch)
                call.message.searchQueries = [...Array.from(call.message.searchQueries ?? []), term];
            root.recordWebSources(cached);
            return {
                status: "success",
                summary: Translation.tr("Fresh result from the short web cache"),
                data: JSON.stringify(cached)
            };
        }
        webToolProc.toolKey = call.key;
        webToolProc.isSearch = isSearch;
        webToolProc.term = term;
        webToolProc.cacheKey = cacheKey;
        webToolProc.command = isSearch
            ? ["python3", Directories.aiWebScriptPath, "search", term, String(count)]
            : ["python3", Directories.aiWebScriptPath, "fetch", term];
        webToolProc.running = true;
        // What it looked up belongs with the answer, the same way the
        // providers' own search results do.
        if (isSearch)
            call.message.searchQueries = [...Array.from(call.message.searchQueries ?? []), term];
        return { status: "pending" };
    }

    function toolSports(call: var, force: bool): var {
        const sessionId = String(root.currentRunSessionId || root.sessions.currentId || "");
        return root.sportsIntegration.query(call.key, call.callId, sessionId, call.args, force);
    }

    function toolGmail(call: var, operation: string): var {
        const sessionId = String(root.currentRunSessionId || root.sessions.currentId || "");
        if (operation === "search")
            return root.gmailIntegration.search(call.key, call.callId, sessionId, call.args);
        if (operation === "get")
            return root.gmailIntegration.getMessage(call.key, call.callId, sessionId, call.args);
        return root.gmailIntegration.getThread(call.key, call.callId, sessionId, call.args);
    }

    function toolGmailOpen(call: var): var {
        return root.gmailIntegration.openInClient(call.args);
    }

    // ── Files ─────────────────────────────────────────────────────────────
    // The one path by which the assistant reaches the filesystem by itself.
    // Every call is checked against `filesIntegration.pathAllowed` again here
    // — the registry's `requiredServices: ["files"]` only gates whether the
    // tool is offered at all, not which path a particular call names.

    function refusedFilePath(path: string): var {
        if (root.filesIntegration.pathAllowed(path))
            return null;
        return {
            status: "denied",
            summary: Translation.tr("That path is outside the configured folders"),
            data: { error: "pathNotAllowed" },
            retryable: false
        };
    }

    function toolFilesSearch(call: var): var {
        if (filesToolProc.running)
            return { status: "error", summary: Translation.tr("Another file lookup is already running."), data: null, retryable: true };
        const query = String(call.args.query ?? "").trim();
        if (query.length === 0)
            return { status: "error", summary: Translation.tr("Nothing to search for"), data: null, retryable: true };
        const limit = Math.max(1, Math.min(20, Number(call.args.limit ?? 20)));
        const kinds = Array.from(call.args.kinds ?? []);
        filesToolProc.op = "search";
        filesToolProc.toolKey = call.key;
        filesToolProc.command = ["python3", root.filesIntegration.scriptPath, "search",
            JSON.stringify(root.filesIntegration.roots), query, String(limit), JSON.stringify(kinds)];
        filesToolProc.running = true;
        return { status: "pending" };
    }

    function toolFilesPreview(call: var): var {
        const path = String(call.args.path ?? "").trim();
        const refusal = root.refusedFilePath(path);
        if (refusal)
            return refusal;
        if (filesToolProc.running)
            return { status: "error", summary: Translation.tr("Another file lookup is already running."), data: null, retryable: true };
        filesToolProc.op = "preview";
        filesToolProc.toolKey = call.key;
        filesToolProc.command = ["python3", root.filesIntegration.scriptPath, "peek", path,
            String(root.filesIntegration.maxPreviewCharacters)];
        filesToolProc.running = true;
        return { status: "pending" };
    }

    function toolFilesAttach(call: var): var {
        const message = call.message;
        message.toolCallSerial = call.serial;
        const path = String(call.args.path ?? "").trim();
        const refusal = root.refusedFilePath(path);
        if (refusal)
            return refusal;
        root.addToolCard(message, {
            callId: call.key,
            tool: "files_attach",
            kind: "fileAttachPreview",
            state: "pending",
            summary: Translation.tr("It wants to read a file"),
            data: { path: path, name: path.split("/").pop() }
        });
        message.functionPending = true;
        return { status: "approval" };
    }

    function approveFileAttach(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        const key = root.toolKeyFor(message);
        const card = root.toolCardFor(message, key);
        const path = String(card?.data?.path ?? "");
        message.functionPending = false;
        if (path.length === 0 || filesToolProc.running) {
            root.updateToolCard(message, key, { state: "failed", summary: Translation.tr("Could not read the file") });
            root.broker.settle(key, { status: "error", summary: Translation.tr("Could not read the file"), data: null, retryable: true });
            return;
        }
        root.updateToolCard(message, key, { state: "done", summary: Translation.tr("Reading…") });
        filesToolProc.op = "attach";
        filesToolProc.toolKey = key;
        filesToolProc.attachMessage = message;
        filesToolProc.command = ["python3", root.filesIntegration.scriptPath, "peek", path,
            String(root.filesIntegration.maxAttachCharacters)];
        filesToolProc.running = true;
    }

    function rejectFileAttach(message: AiMessageData) {
        if (!message?.functionPending)
            return;
        message.functionPending = false;
        const key = root.toolKeyFor(message);
        root.updateToolCard(message, key, { state: "denied", summary: Translation.tr("Not read") });
        root.broker.settle(key, {
            status: "denied",
            summary: Translation.tr("Not read"),
            data: Translation.tr("The user chose not to have that file read.")
        });
    }

    function toolFilesOpenLocation(call: var): var {
        const path = String(call.args.path ?? "").trim();
        const refusal = root.refusedFilePath(path);
        if (refusal)
            return refusal;
        const lastSlash = path.lastIndexOf("/");
        const dir = lastSlash > 0 ? path.slice(0, lastSlash) : path;
        Quickshell.execDetached(["xdg-open", dir]);
        return { status: "success", summary: Translation.tr("Opened the folder"), data: { opened: true } };
    }

    /**
     * Search, preview and attach share one Process: only one file operation
     * is ever worth having in flight, the same restriction the web tools use.
     */
    property Process filesToolProc: Process {
        id: filesToolProc
        property string op: ""
        property string toolKey: ""
        property var attachMessage: null

        stdout: StdioCollector {
            id: filesToolCollector
            onStreamFinished: {
                const raw = String(text ?? "").trim();
                let parsed = null;
                try {
                    parsed = JSON.parse(raw);
                } catch (e) {
                    parsed = null;
                }
                if (filesToolProc.op === "search") {
                    if (!parsed || parsed.error) {
                        root.broker.settle(filesToolProc.toolKey, {
                            status: "error",
                            summary: String(parsed?.error ?? Translation.tr("The search failed")),
                            data: null,
                            retryable: true
                        });
                        return;
                    }
                    const results = Array.from(parsed.results ?? []);
                    const summary = results.length === 1 ? Translation.tr("1 file found") : Translation.tr("%1 files found").arg(results.length);
                    // The card carries the full FileRef (path included) so its
                    // buttons can act on it directly; the model only ever sees
                    // the smaller projection below.
                    if (results.length > 0) {
                        const record = root.broker.recordFor(filesToolProc.toolKey);
                        if (record?.message)
                            root.addToolCard(record.message, {
                                callId: filesToolProc.toolKey,
                                tool: "files_search",
                                kind: "fileResults",
                                state: "done",
                                summary: summary,
                                data: { files: results }
                            });
                    }
                    root.broker.settle(filesToolProc.toolKey, {
                        status: "success",
                        summary: summary,
                        data: { query: parsed.query, files: results.map(entry => root.filesIntegration.modelRef(entry)) }
                    });
                    return;
                }
                if (filesToolProc.op === "preview") {
                    if (!parsed || parsed.error) {
                        root.broker.settle(filesToolProc.toolKey, {
                            status: parsed?.sensitive === true ? "denied" : "error",
                            summary: String(parsed?.error ?? Translation.tr("Could not read that file")),
                            data: null,
                            retryable: parsed?.sensitive !== true
                        });
                        return;
                    }
                    root.broker.settle(filesToolProc.toolKey, {
                        status: "success",
                        summary: parsed.truncated ? Translation.tr("Preview (truncated)") : Translation.tr("Preview"),
                        data: { name: parsed.name, mime: parsed.mime, text: parsed.text, truncated: parsed.truncated === true }
                    });
                    return;
                }
                // attach
                const message = filesToolProc.attachMessage;
                filesToolProc.attachMessage = null;
                if (!parsed || parsed.error || !parsed.text) {
                    const reason = String(parsed?.error ?? Translation.tr("Nothing could be read from that file"));
                    if (message)
                        root.updateToolCard(message, filesToolProc.toolKey, { state: "failed", summary: reason });
                    root.broker.settle(filesToolProc.toolKey, {
                        status: parsed?.sensitive === true ? "denied" : "error",
                        summary: reason,
                        data: null,
                        retryable: parsed?.sensitive !== true
                    });
                    return;
                }
                if (message)
                    root.updateToolCard(message, filesToolProc.toolKey, { state: "done", summary: parsed.truncated ? Translation.tr("Read (truncated)") : Translation.tr("Read") });
                root.broker.settle(filesToolProc.toolKey, {
                    status: "success",
                    summary: parsed.truncated ? Translation.tr("%1 (truncated)").arg(parsed.name) : String(parsed.name),
                    data: parsed.text
                });
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.broker.isPending(filesToolProc.toolKey))
                root.broker.settle(filesToolProc.toolKey, {
                    status: "error",
                    summary: Translation.tr("The file helper stopped with code %1.").arg(exitCode),
                    data: null,
                    retryable: true
                });
        }
    }

    // ── Vision: OCR ───────────────────────────────────────────────────────

    function toolImageOcr(call: var): var {
        const path = String(call.args.path ?? "").trim();
        const refusal = root.refusedFilePath(path);
        if (refusal)
            return refusal;
        if (ocrToolProc.running)
            return { status: "error", summary: Translation.tr("Another OCR run is already in progress."), data: null, retryable: true };
        const lang = String(call.args.lang ?? "").trim() || "eng";
        ocrToolProc.toolKey = call.key;
        // `stdout` as the output target ("-") keeps this to one process and
        // one temp-free round trip; tesseract's own file-based mode would
        // leave a `.txt` next to a possibly read-only source directory.
        ocrToolProc.command = ["tesseract", path, "stdout", "-l", lang];
        ocrToolProc.running = true;
        return { status: "pending" };
    }

    property Process ocrToolProc: Process {
        id: ocrToolProc
        property string toolKey: ""

        stdout: StdioCollector {
            id: ocrCollector
            onStreamFinished: {
                const trimmed = String(text ?? "").trim();
                if (trimmed.length === 0) {
                    root.broker.settle(ocrToolProc.toolKey, {
                        status: "success",
                        summary: Translation.tr("No text found in the image"),
                        data: ""
                    });
                    return;
                }
                root.broker.settle(ocrToolProc.toolKey, {
                    status: "success",
                    summary: Translation.tr("Text extracted"),
                    data: trimmed
                });
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.broker.isPending(ocrToolProc.toolKey))
                root.broker.settle(ocrToolProc.toolKey, {
                    status: "error",
                    summary: Translation.tr("OCR failed (exit code %1). Check the language code.").arg(exitCode),
                    data: null,
                    retryable: true
                });
        }
    }

    function toolShellCommand(call: var): var {
        const message = call.message;
        message.toolCallSerial = call.serial;
        const command = String(call.args.command ?? "");
        if (command.length === 0)
            return {
                status: "error",
                summary: Translation.tr("No command given"),
                data: null,
                retryable: true
            };
        const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${command}\n\`\`\``;
        message.rawContent += contentToAppend;
        message.content += contentToAppend;
        if (root.toolbox.permission("run_shell_command") === "allow") {
            root.runShellCommand(message, command);
            return { status: "pending" };
        }
        // Thinking indicates the command is waiting for approval.
        message.functionPending = true;
        return { status: "approval" };
    }

    /**
     * The web tools. They only read: a search returns titles and snippets, a
     * fetch returns one page as text. Both run out of process so a slow site
     * never blocks the shell, and both hand their result back to the broker,
     * which is what decides how much of it the model gets to see.
     */
    Process {
        id: webToolProc
        property string toolKey: ""
        property bool isSearch: false
        property string term: ""
        property string cacheKey: ""

        stdout: StdioCollector {
            id: webToolCollector
            onStreamFinished: {
                const raw = String(webToolCollector.text ?? "").trim();
                let parsed = null;
                try {
                    parsed = JSON.parse(raw);
                } catch (e) {
                    parsed = null;
                }
                if (!parsed || parsed.error) {
                    const reason = parsed?.error ?? Translation.tr("nothing came back");
                    root.broker.settle(webToolProc.toolKey, {
                        status: parsed?.blocked === true ? "denied" : "error",
                        summary: reason,
                        data: null,
                        // A refused address is not worth trying again; a site
                        // that did not answer might be.
                        retryable: parsed?.blocked !== true
                    });
                    return;
                }
                parsed = root.decorateWebPayload(parsed, webToolProc.isSearch);
                parsed = root.cacheWebPayload(webToolProc.cacheKey, parsed);
                root.recordWebSources(parsed);
                if (webToolProc.isSearch) {
                    const results = Array.from(parsed.results ?? []);
                    root.broker.settle(webToolProc.toolKey, {
                        status: "success",
                        summary: Translation.tr("%1 results from %2").arg(results.length).arg(parsed.engine ?? "web"),
                        data: JSON.stringify(parsed)
                    });
                    return;
                }
                root.broker.settle(webToolProc.toolKey, {
                    status: "success",
                    summary: String(parsed.title ?? webToolProc.term),
                    data: JSON.stringify(parsed)
                });
            }
        }

        onExited: (exitCode, exitStatus) => {
            // A helper that died without writing anything would otherwise
            // leave the call waiting until its deadline.
            if (exitCode !== 0 && root.broker.isPending(webToolProc.toolKey))
                root.broker.settle(webToolProc.toolKey, {
                    status: "error",
                    summary: Translation.tr("The web helper stopped with code %1.").arg(exitCode),
                    data: null,
                    retryable: true
                });
        }
    }

    // ── Local retrieval (RAG) ────────────────────────────────────────────
    // Read-only, and only over folders the user indexed explicitly through
    // Settings. `AiRagIntegration` validates the call and shapes the
    // request; `AiRagService` owns the collections and the index files
    // themselves, since Settings drives the same state.

    function toolRagSearch(call: var): var {
        const built = root.ragIntegration.buildSearchRequest(call.args);
        if (built.error)
            return { status: "unavailable", summary: built.error, data: null, retryable: false };
        if (ragToolProc.running)
            return { status: "error", summary: Translation.tr("Another search is already running."), data: null, retryable: true };
        ragToolProc.toolKey = call.key;
        ragToolProc.query = built.query;
        ragToolProc.command = ["python3", Directories.aiRagScriptPath, "search"];
        ragToolProc.stdinEnabled = true;
        ragToolProc.running = true;
        // ai_rag.py reads stdin to EOF, not to a newline; the pipe must be
        // closed after the write or the helper blocks forever waiting for
        // more input that will never come.
        ragToolProc.write(JSON.stringify(built.request) + "\n");
        ragToolProc.stdinEnabled = false;
        return { status: "pending" };
    }

    Process {
        id: ragToolProc
        stdinEnabled: true
        property string toolKey: ""
        property string query: ""

        stdout: StdioCollector {
            id: ragToolCollector
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(ragToolCollector.text);
                } catch (e) {
                    parsed = null;
                }
                if (!parsed?.ok) {
                    root.broker.settle(ragToolProc.toolKey, {
                        status: "error",
                        summary: String(parsed?.error ?? Translation.tr("The search failed")),
                        data: null,
                        retryable: true
                    });
                    return;
                }
                const rawResults = Array.from(parsed.results ?? []);
                const summary = rawResults.length === 1 ? Translation.tr("1 result found") : Translation.tr("%1 results found").arg(rawResults.length);
                if (rawResults.length > 0) {
                    const record = root.broker.recordFor(ragToolProc.toolKey);
                    if (record?.message)
                        root.addToolCard(record.message, {
                            callId: ragToolProc.toolKey,
                            tool: "rag_search",
                            kind: "ragResults",
                            state: "done",
                            summary: summary,
                            data: { query: ragToolProc.query, results: rawResults.map(hit => root.ragIntegration.resultRef(hit)) }
                        });
                }
                root.broker.settle(ragToolProc.toolKey, {
                    status: "success",
                    summary: summary,
                    data: { query: ragToolProc.query, results: rawResults.map(hit => root.ragIntegration.resultRef(hit)) }
                });
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.broker.isPending(ragToolProc.toolKey))
                root.broker.settle(ragToolProc.toolKey, {
                    status: "error",
                    summary: Translation.tr("The retrieval helper stopped with code %1.").arg(exitCode),
                    data: null,
                    retryable: true
                });
        }
    }

    // ── Sessions ──────────────────────────────────────────────────────────
    // A conversation is a file, and the one on screen is one of them. The
    // store does the disk work; what lives here is the shape of a session,
    // how it becomes messages, and when it is worth writing.

    readonly property AiSessions sessions: AiSessions {
        dir: Directories.aiSessions
        legacyDir: Directories.aiChats
        scriptPath: Directories.aiSessionsScriptPath
        exportDir: Directories.aiExports
        onSaveRequested: root.commitSession()
        onSessionOpened: session => root.applySession(session)
        onSaveSucceeded: (operationId, sessionId) => {
            root.conversations.markSaveAcknowledged(sessionId);
            if (root.handleToolJournalSaveSucceeded(operationId, sessionId))
                return;
            root.handleSubmissionSaveSucceeded(operationId, sessionId);
        }
        onSaveFailed: (operationId, sessionId, reason) => {
            root.conversations.markSavePending(sessionId, true);
            if (root.handleToolJournalSaveFailed(operationId, sessionId, reason))
                return;
            root.handleSubmissionSaveFailed(operationId, sessionId, reason);
        }
        onStageSucceeded: (operationId, sessionId) => root.handleSubmissionStageSucceeded(operationId, sessionId)
        onStageFailed: (operationId, sessionId, reason) => root.handleSubmissionStageFailed(operationId, sessionId, reason)
        onCommitSubmissionSucceeded: (operationId, sessionId) => root.handleSubmissionCommitSucceeded(operationId, sessionId)
        onCommitSubmissionFailed: (operationId, sessionId, reason) => root.handleSubmissionCommitFailed(operationId, sessionId, reason)
        onAbortSubmissionSucceeded: (operationId, sessionId) => root.handleSubmissionAbortFinished(operationId, sessionId, "aborted")
        onAbortSubmissionFailed: (operationId, sessionId, reason) => root.handleSubmissionAbortFinished(operationId, sessionId, reason)
        onCurrentDropped: root.newChat()
    }

    // ── Personas ──────────────────────────────────────────────────────────
    // A persona is a prompt and the settings that go with it. Picking one
    // sets all of them; a chat remembers which one it was held with.

    readonly property AiPersonas personas: AiPersonas {}
    readonly property var currentPersona: root.personas.byId(root.sessionPersonaId)
    readonly property bool personaModified: root.personas.modified(root.currentPersona, root.currentModelId, root.thinkingLevel, root.temperature)

    /**
     * Puts a persona in force. Everything it names is applied at once — that
     * is the whole point of it being one thing instead of four settings.
     */
    function setPersona(personaId: string, feedback = true) {
        const persona = root.personas.byId(personaId);
        if (!persona && personaId.length > 0) {
            if (feedback)
                root.addMessage(Translation.tr("No persona called “%1”").arg(personaId), root.interfaceRole);
            return false;
        }
        root.sessionPersonaId = persona?.id ?? "";
        // A chat's own prompt was written for this chat, not for the persona
        // that happens to be picked now, so it goes when the persona changes.
        root.promptOverride = "";
        root.currentPromptFile = "";
        if (persona?.modelId && root.catalog.models[persona.modelId])
            root.setModel(persona.modelId, false);
        if (persona?.thinking && root.thinkingLevels.indexOf(persona.thinking) >= 0)
            root.setThinkingLevel(persona.thinking);
        if (typeof persona?.temperature === "number")
            root.setTemperature(persona.temperature, false);
        if (feedback)
            root.addMessage(persona ? Translation.tr("Persona: %1").arg(persona.name) : Translation.tr("Persona cleared"), root.interfaceRole);
        root.sessions.scheduleSave();
        return true;
    }

    /** Opening lines offered on an empty chat, from the persona in force. */
    readonly property var starters: {
        const own = root.currentPersona?.starters;
        if (own?.length > 0)
            return Array.from(own);
        return [Translation.tr("Explain what this command does"), Translation.tr("Summarise this in three points"), Translation.tr("What is wrong with this code?"), Translation.tr("Help me word this")];
    }

    /** Sets this chat's own prompt, leaving every other chat alone. */
    function setPromptOverride(text: string, feedback = true) {
        root.promptOverride = String(text ?? "").trim();
        if (root.promptOverride.length === 0)
            root.currentPromptFile = "";
        root.sessions.scheduleSave();
        if (feedback)
            root.addMessage(root.promptOverride.length > 0 ? Translation.tr("This chat now has a prompt of its own.") : Translation.tr("Back to the usual prompt."), root.interfaceRole);
    }

    // ── The composer's draft ──────────────────────────────────────────────
    // Half-typed text belongs to the chat it was being typed into, not to the
    // sidebar, so switching chats does not throw it away.

    property var drafts: ({})
    property string draft: ""
    signal draftRestored(string text)

    readonly property string newDraftId: "__new__"

    function sessionDraftId(sessionId = null) {
        if (sessionId !== null)
            return String(sessionId).length > 0 ? String(sessionId) : root.newDraftId;
        return root.sessions.currentId.length > 0 ? root.sessions.currentId : root.newDraftId;
    }

    function writeOrStageDraft(sessionId: string, text: string) {
        const id = String(sessionId ?? "").trim();
        if (id.length === 0)
            return;
        const value = String(text ?? "");
        if (root.draftStore.loaded) {
            root.draftStore.setDraft(id, value);
            return;
        }
        root.pendingDraftMutations = Object.assign({}, root.pendingDraftMutations, {
            [id]: value
        });
    }

    function hasPendingDraftMutation(sessionId: string): bool {
        const id = String(sessionId ?? "").trim();
        return id.length > 0 && Object.prototype.hasOwnProperty.call(root.pendingDraftMutations, id);
    }

    function clearDraftForSession(sessionId: string, expectedText = ""): bool {
        const id = String(sessionId ?? "").trim();
        if (id.length === 0)
            return false;
        if (root.draftStore.loaded)
            return root.draftStore.clearDraft(id, expectedText);
        if (root.hasPendingDraftMutation(id) && expectedText.length > 0 && String(root.pendingDraftMutations[id]) !== expectedText)
            return false;
        root.writeOrStageDraft(id, "");
        return true;
    }

    function flushPendingDraftMutations() {
        const mutations = root.pendingDraftMutations;
        root.pendingDraftMutations = ({});
        Object.keys(mutations).forEach(id => root.draftStore.setDraft(id, String(mutations[id] ?? "")));
    }

    function onDraftStoreReady() {
        const currentSessionId = root.sessionDraftId();
        const hasCurrentMutation = root.hasPendingDraftMutation(currentSessionId);
        root.flushPendingDraftMutations();
        if (!hasCurrentMutation)
            root.restoreDraft();
    }

    function keepDraft() {
        root.writeOrStageDraft(root.sessionDraftId(), root.draft);
    }

    function restoreDraft() {
        const id = root.sessionDraftId();
        root.restoringDraft = true;
        root.draft = root.draftStore.loaded ? root.draftStore.textFor(id) : "";
        root.restoringDraft = false;
        root.draftRestored(root.draft);
    }

    /** The key panel was asked for, from a command or from a card in the chat. */
    signal keyManagerRequested

    readonly property int sessionSchema: 3
    /** Name of the conversation on screen. Empty until it earns one. */
    property string sessionTitle: ""
    property real sessionCreatedAt: 0
    /**
     * Where this chat came from. A fork and a rewritten question both leave a
     * branch behind; without these two the old answer became a chat with no
     * relation to the one on screen, and there was no way back to it.
     */
    property string sessionParentId: ""
    property string sessionBranchMessageId: ""
    /** Per-chat tool decisions, used only when the global scope toggle is on. */
    property var sessionToolPermissions: ({ "alwaysAllow": [], "alwaysDeny": [] })
    /** Free-form labels, and the project this chat belongs to. */
    property var sessionTags: []
    property string sessionProjectId: ""
    /** Whether the model has already been asked to name this one. */
    property bool sessionTitleAsked: false
    property int titleRevision: 0
    property bool isProvisionalTitle: true
    property string titleRequestSessionId: ""
    property int titleRequestRevision: -1

    /**
     * Session ids that hold alternate answers for a branch point. The trunk
     * is always position one; forks are ordered by creation time so the
     * compact <2/3> control stays stable while the index refreshes.
     */
    function answerVariantSessionIds(messageId: string): var {
        const currentId = String(root.sessions.currentId ?? "");
        if (currentId.length === 0)
            return [];
        const child = root.sessionParentId.length > 0;
        const parentId = child ? root.sessionParentId : currentId;
        const branchMessageId = child ? root.sessionBranchMessageId : String(messageId ?? "");
        if (branchMessageId.length === 0)
            return [];
        const forks = Array.from(root.sessions.index ?? []).filter(entry => String(entry?.parentId ?? "") === parentId
            && String(entry?.branchMessageId ?? "") === branchMessageId)
            .sort((left, right) => Number(left?.createdAt ?? 0) - Number(right?.createdAt ?? 0));
        if (forks.length === 0)
            return [];
        const ids = [parentId, ...forks.map(entry => String(entry.id ?? ""))];
        return ids.filter((id, index) => id.length > 0 && ids.indexOf(id) === index);
    }

    function latestVisibleAssistantMessageId(): string {
        for (let index = root.messageIDs.length - 1; index >= 0; index--) {
            const id = root.messageIDs[index];
            const message = root.messageByID[id];
            if (message?.role === "assistant" && message.visibleToUser !== false)
                return id;
        }
        return "";
    }

    function shouldShowAnswerVariants(messageId: string): bool {
        return String(messageId ?? "") === root.latestVisibleAssistantMessageId()
            && root.answerVariantSessionIds(messageId).length > 1;
    }

    function openAnswerVariant(messageId: string, offset: int) {
        if (root.isGenerating)
            return;
        const ids = root.answerVariantSessionIds(messageId);
        const current = ids.indexOf(root.sessions.currentId);
        if (ids.length < 2 || current < 0)
            return;
        const target = ids[(current + offset + ids.length) % ids.length];
        if (target && target !== root.sessions.currentId)
            root.openSession(target);
    }

    function normalizedSessionToolPermissions(value): var {
        const raw = value && typeof value === "object" ? value : ({});
        const allow = Array.from(raw.alwaysAllow ?? []).map(id => String(id)).filter(id => id.length > 0);
        const deny = Array.from(raw.alwaysDeny ?? []).map(id => String(id)).filter(id => id.length > 0 && allow.indexOf(id) < 0);
        return {
            "alwaysAllow": allow.filter((id, index) => allow.indexOf(id) === index),
            "alwaysDeny": deny.filter((id, index) => deny.indexOf(id) === index)
        };
    }

    function setSessionToolPermissions(value): void {
        root.sessionToolPermissions = root.normalizedSessionToolPermissions(value);
        root.sessions.scheduleSave();
    }

    function serializeMessageFrom(id, source) {
        const message = source?.[id];
        if (!message)
            return null;
        return ({
                "id": id,
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                // Context content is deliberately ephemeral. The chip's safe
                // metadata remains in the transcript, while copied clipboard
                // text can never be recovered from a saved session.
                "attachments": Array.from(message.attachments ?? []).map(attachment => {
                    if (attachment?.kind !== "context")
                        return attachment;
                    return {
                        id: attachment.id,
                        kind: attachment.kind,
                        contextKind: attachment.contextKind,
                        source: attachment.source,
                        name: attachment.name,
                        bytes: attachment.bytes,
                        sensitive: attachment.sensitive === true,
                        retention: attachment.retention,
                        destination: attachment.destination,
                        truncated: attachment.truncated === true,
                        redacted: true
                    };
                }),
                "model": message.model,
                "responseMode": message.responseMode,
                "webMode": message.webMode,
                "functionExposure": message.functionExposure,
                "profileFallback": message.profileFallback,
                "thought": message.thought,
                "thoughtSignature": message.thoughtSignature,
                "thinkingBlocks": message.thinkingBlocks,
                "thoughtDurationMs": message.thoughtDurationMs,
                "thoughtTokens": message.thoughtTokens,
                "inputTokens": message.inputTokens,
                "outputTokens": message.outputTokens,
                "totalTokens": message.totalTokens,
                "requestCost": message.requestCost,
                "thinking": false,
                "done": true,
                "finishReason": message.finishReason,
                "createdAt": message.createdAt,
                "completedAt": message.completedAt,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "searchQueries": message.searchQueries,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionCalls": message.functionCalls,
                "toolCalls": message.toolCalls,
                "functionCallId": message.functionCallId,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
                "errorKind": message.errorKind,
                "errorDetails": message.errorDetails,
                "errorText": message.errorText,
                "errorStatus": message.errorStatus,
                "notice": message.notice,
                "toolCards": JSON.parse(JSON.stringify(Array.from(message.toolCards ?? [])))
            });
    }

    function serializeMessage(id) {
        return root.serializeMessageFrom(id, root.messageByID);
    }

    function chatToJson() {
        const omitInterfaceMessages = Config.options?.ai?.ephemeralInterfaceMessages === true;
        return root.messageIDs.map(id => root.serializeMessage(id)).filter(message => message !== null
            && (!omitInterfaceMessages || message.role !== root.interfaceRole));
    }

    function runningChatToJson() {
        return root.runningMessageIDs.map(id => root.serializeMessageFrom(id, root.runningMessageByID)).filter(message => message !== null);
    }

    /**
     * The cards a saved message carries.
     *
     * A session written before cards existed kept the settings diff and the
     * remembered fact in fields of their own. They are turned into cards on
     * the way in, so an old conversation reopens showing what it showed then
     * rather than losing the card entirely.
     */
    function toolCardsFromJson(data: var): var {
        const stored = Array.from(data?.toolCards ?? []);
        if (stored.length > 0)
            return stored;
        const migrated = [];
        const callId = String(data?.functionCallId ?? "");
        const changes = Array.from(data?.pendingChanges ?? []);
        if (changes.length > 0)
            migrated.push({
                callId: callId,
                tool: "set_shell_config",
                kind: "settingsDiff",
                state: data?.functionPending ? "pending" : "done",
                summary: "",
                data: { changes: changes },
                createdAt: Number(data?.createdAt ?? 0)
            });
        const fact = String(data?.pendingMemory ?? "");
        if (fact.length > 0)
            migrated.push({
                callId: callId,
                tool: "remember_fact",
                kind: "memoryFact",
                state: data?.functionPending ? "pending" : "done",
                summary: "",
                data: { fact: fact },
                createdAt: Number(data?.createdAt ?? 0)
            });
        return migrated;
    }

    function messageFromJson(data: var): AiMessageData {
        // Sessions written by the first chat implementation used `content`,
        // while current snapshots use `rawContent`. Hydration must understand
        // both formats or a valid old chat turns into blank delegates.
        const persistedRaw = String(data?.rawContent ?? "");
        const rawContent = persistedRaw.length > 0
            ? persistedRaw
            : String(data?.content ?? "");
        return root.aiMessageComponent.createObject(root, {
            "role": String(data?.role ?? "assistant"),
            "rawContent": rawContent,
            "content": rawContent,
            "fileMimeType": data?.fileMimeType ?? "",
            "fileUri": data?.fileUri ?? "",
            "localFilePath": data?.localFilePath ?? "",
            "attachments": data?.attachments ?? [],
            "finishReason": data.finishReason ?? "",
            "toolCards": root.toolCardsFromJson(data),
            "createdAt": data.createdAt ?? 0,
            "completedAt": data.completedAt ?? 0,
            "model": data.model,
            "responseMode": data.responseMode ?? "balanced",
            "webMode": data.webMode ?? "off",
            "functionExposure": data.functionExposure ?? "all",
            "profileFallback": data.profileFallback ?? "",
            "thought": data.thought ?? "",
            "thoughtSignature": data.thoughtSignature ?? "",
            "thinkingBlocks": data.thinkingBlocks ?? [],
            "thoughtDurationMs": data.thoughtDurationMs ?? 0,
            "thoughtTokens": data.thoughtTokens ?? -1,
            "inputTokens": data.inputTokens ?? -1,
            "outputTokens": data.outputTokens ?? -1,
            "totalTokens": data.totalTokens ?? -1,
            "requestCost": data.requestCost ?? -1,
            "thinking": data.thinking ?? false,
            "done": data.done ?? true,
            "annotations": data.annotations ?? [],
            "annotationSources": data.annotationSources ?? [],
            "searchQueries": data.searchQueries ?? [],
            "functionName": data.functionName ?? "",
            "functionCall": data.functionCall,
            "functionCalls": data.functionCalls ?? [],
            "toolCalls": data.toolCalls ?? data.functionCalls ?? [],
            "functionCallId": data.functionCallId ?? "",
            "functionResponse": data.functionResponse ?? "",
            "visibleToUser": data.visibleToUser ?? true,
            "errorKind": data.errorKind ?? "",
            "errorText": data.errorText ?? "",
            "errorStatus": data.errorStatus ?? 0,
            "errorDetails": data.errorDetails ?? "",
            "notice": data.notice ?? ""
        });
    }

    // A session may have been saved while its provider process was still
    // streaming. There is no process to resume after a restart or when an old
    // chat is opened, so restoring `done: false` would create an immortal
    // loading row. Convert only unfinished assistant turns to a terminal,
    // retryable message; completed history remains byte-for-byte intact.
    /**
     * Checkpoints left mid-flight by a shell that stopped.
     *
     * `executionStarted` with nothing after it means the side effect had begun
     * and its outcome was never written down. Reopening the session says so
     * rather than quietly showing an approved-looking card, because the one
     * unsafe thing to do here is to offer to try again.
     */
    function recoverInterruptedCheckpoints(checkpoints: var): var {
        return Array.from(checkpoints ?? []).map(entry => {
            if (String(entry?.status ?? "") !== "executionStarted")
                return entry;
            return Object.assign({}, entry, {
                status: "needsInspection",
                outcome: Translation.tr("The shell stopped while this was running. Check the result before trying it again.")
            });
        });
    }

    function recoverInterruptedMessages(messages: var, run: var): var {
        const source = Array.isArray(messages) ? messages : [];
        const hasUnfinishedRun = !!run && !root.runCoordinator.terminalStates.includes(String(run.state ?? ""));
        return source.map(data => {
            const value = Object.assign({}, data ?? ({}));
            if (value.role === "assistant" && (value.done !== true || value.thinking === true) && (hasUnfinishedRun || value.done !== true)) {
                value.done = true;
                value.thinking = false;
                if (String(value.errorKind ?? "").length === 0)
                    value.errorKind = "interrupted";
                if (String(value.errorText ?? "").length === 0)
                    value.errorText = Translation.tr("This response was interrupted. You can retry it.");
            }
            return value;
        });
    }

    function sessionToJson(): var {
        return ({
                "schema": root.sessionSchema,
                "id": root.sessions.currentId,
                "title": root.sessionTitle,
                "titleRevision": root.titleRevision,
                "isProvisionalTitle": root.isProvisionalTitle,
                "createdAt": root.sessionCreatedAt > 0 ? root.sessionCreatedAt : Date.now(),
                "updatedAt": Date.now(),
                "pinned": root.sessions.currentEntry?.pinned ?? false,
                "modelId": root.currentModelId,
                "thinking": root.thinkingLevel,
                "responseMode": root.responseMode,
                "webMode": root.webMode,
                "functionExposure": root.functionExposure,
                "temperature": root.temperature,
                "promptFile": root.currentPromptFile,
                "personaId": root.sessionPersonaId,
                "promptOverride": root.promptOverride,
                "parentId": root.sessionParentId,
                "branchMessageId": root.sessionBranchMessageId,
                "toolPermissions": root.sessionToolPermissions,
                "tags": root.sessionTags,
                "projectId": root.sessionProjectId,
                "messages": root.chatToJson(),
                "run": root.conversations.records[root.sessions.currentId]?.run ?? null,
                "searchQueries": root.sessionSearchQueries,
                "sources": root.sessionSources,
                "toolCheckpoints": root.sessionToolCheckpoints,
                "contextSummary": root.contextSummary,
                "contextSummaryKey": root.contextSummaryKey,
                "activityEvents": root.conversations.records[root.sessions.currentId]?.run?.activityEvents ?? []
            });
    }

    function runningSessionToJson(): var {
        const sessionId = root.currentRunSessionId;
        const base = root.conversations.snapshot(sessionId) ?? ({
                "schema": root.sessionSchema,
                "id": sessionId,
                "title": "",
                "createdAt": Date.now(),
                "pinned": true,
                "modelId": root.currentModelId,
                "thinking": root.thinkingLevel,
                "responseMode": root.responseMode,
                "webMode": root.webMode,
                "functionExposure": root.functionExposure,
                "temperature": root.temperature,
                "promptFile": "",
                "personaId": "",
                "promptOverride": ""
            });
        return Object.assign({}, base, {
            schema: root.sessionSchema,
            id: sessionId,
            titleRevision: base.titleRevision ?? root.titleRevision,
            isProvisionalTitle: base.isProvisionalTitle ?? root.isProvisionalTitle,
            modelId: root.currentRunId.length > 0 ? (root.runCoordinator.runFor(root.currentRunId)?.modelId ?? base.modelId) : base.modelId,
            responseMode: root.responseMode,
            webMode: root.webMode,
            functionExposure: root.functionExposure,
            toolPermissions: root.sessionToolPermissions,
            messages: root.runningChatToJson(),
            run: root.conversations.records[sessionId]?.run ?? null,
            searchQueries: sessionId === root.sessions.currentId ? root.sessionSearchQueries : (base.searchQueries ?? []),
            sources: sessionId === root.sessions.currentId ? root.sessionSources : (base.sources ?? []),
            toolCheckpoints: sessionId === root.sessions.currentId ? root.sessionToolCheckpoints : (base.toolCheckpoints ?? []),
            contextSummary: sessionId === root.sessions.currentId ? root.contextSummary : (base.contextSummary ?? ""),
            contextSummaryKey: sessionId === root.sessions.currentId ? root.contextSummaryKey : (base.contextSummaryKey ?? ""),
            activityEvents: root.conversations.records[sessionId]?.run?.activityEvents ?? [],
            updatedAt: Date.now()
        });
    }

    /**
     * Writes the conversation on screen. An empty chat is not a session: one
     * is only started once there is something in it.
     */
    function commitSession(flushNow = false) {
        if (root.messageIDs.length === 0)
            return "";
        if (root.sessions.currentId.length === 0) {
            root.sessions.currentId = root.sessions.newId();
            root.sessionCreatedAt = Date.now();
        }
        const snapshot = root.sessionToJson();
        root.conversations.capture(root.sessions.currentId, snapshot);
        root.conversations.markSavePending(root.sessions.currentId, true);
        return root.sessions.commit(snapshot, "", flushNow);
    }

    /** Puts the conversation away and starts an empty one. */
    function newChat() {
        if (root.pendingToolExecution || commandExecutionProc.running) {
            root.addMessage(Translation.tr("Wait for the active tool to finish before switching chats."), root.interfaceRole, {
                "notice": "submission"
            });
            return;
        }
        const pending = root.pendingSubmission;
        const activeRun = root.currentRunId.length > 0 && root.runCoordinator.activeStates.includes(root.runCoordinator.runFor(root.currentRunId)?.state);
        if (pending && !activeRun && !requester.running) {
            root.cancelPendingSubmission("new-chat");
            return;
        }
        root.commitSession();
        root.keepDraft();
        root.clearMessages();
        root.clearAttachments();
        root.sessions.currentId = "";
        root.sessionTitle = "";
        root.sessionCreatedAt = 0;
        root.sessionParentId = "";
        root.sessionBranchMessageId = "";
        root.sessionToolPermissions = ({ "alwaysAllow": [], "alwaysDeny": [] });
        root.sessionTags = [];
        root.contextSummary = "";
        root.contextSummaryKey = "";
        root.contextCutMessageId = "";
        root.prunedTurnCount = 0;
        root.sessionTitleAsked = false;
        root.titleRevision = 0;
        root.isProvisionalTitle = true;
        root.titleRequestSessionId = "";
        root.titleRequestRevision = -1;
        root.sessionSearchQueries = [];
        root.sessionSources = [];
        root.sessionToolCheckpoints = [];
        root.promptOverride = "";
        root.currentPromptFile = "";
        root.resetSessionSettings();
        root.restoreDraft();
        root.sessions.ensureLoaded();
    }

    function openSession(sessionId: string) {
        if (sessionId.length === 0)
            return;
        // Always reload the selected file. `currentId` is updated by the
        // repository before `sessionOpened` is emitted, so using it as a
        // dedupe key can leave a stale/empty in-memory transcript looking like
        // an already restored chat (especially after switching hosts).
        if (root.pendingToolExecution || commandExecutionProc.running) {
            root.addMessage(Translation.tr("Wait for the active tool to finish before switching chats."), root.interfaceRole, {
                "notice": "submission"
            });
            return;
        }
        const pending = root.pendingSubmission;
        const activeRun = root.currentRunId.length > 0 && root.runCoordinator.activeStates.includes(root.runCoordinator.runFor(root.currentRunId)?.state);
        if (pending && !activeRun && !requester.running) {
            root.addMessage(Translation.tr("Wait for this message to finish saving, or stop it before switching chats."), root.interfaceRole, {
                "notice": "submission"
            });
            return;
        }
        // Never overwrite a file while explicitly reloading that same id:
        // the in-memory transcript may be stale/empty after a host handoff.
        // Other chats still get their pending snapshot before we switch.
        if (sessionId !== root.sessions.currentId)
            root.commitSession();
        root.keepDraft();
        root.sessions.openSession(sessionId);
    }

    /**
     * Replaces the conversation with one read from disk, settings included:
     * a chat is remembered as it was held, not as the sidebar happens to be
     * set right now.
     */
    function applySession(session: var) {
        root.cancelContextCompaction();
        const sessionId = root.sessions.currentId;
        if (sessionId.length > 0) {
            let restoredRun = session.run ?? root.conversations.records[sessionId]?.run ?? null;
            if (restoredRun && (!root.runCoordinator.terminalStates.includes(restoredRun.state) || restoredRun.executionStarted === true)) {
                restoredRun = root.runCoordinator.restore(restoredRun);
                session.run = restoredRun;
            }
            root.conversations.capture(sessionId, session);
        }
        root.clearMessages();
        const ids = [];
        const byId = ({});
        const originalMessages = Array.isArray(session.messages) ? session.messages : [];
        const messages = root.recoverInterruptedMessages(originalMessages, session.run ?? null);
        const recoveredMessages = messages.some((value, index) => {
            const original = originalMessages[index] ?? ({});
            return value.done !== original.done || value.thinking !== original.thinking || value.errorKind !== original.errorKind || value.errorText !== original.errorText;
        });
        for (let i = 0; i < messages.length; i++) {
            const data = messages[i];
            const id = (data.id && String(data.id).length > 0) ? String(data.id) : root.sessions.newId();
            byId[id] = root.messageFromJson(data);
            ids.push(id);
        }
        root.messageByID = byId;
        root.messageIDs = ids;
        root.sessionTitle = session.title ?? "";
        root.sessionCreatedAt = session.createdAt ?? Date.now();
        root.sessionTitleAsked = root.sessionTitle.length > 0;
        root.titleRevision = Number(session.titleRevision ?? 0);
        root.isProvisionalTitle = session.isProvisionalTitle === true || (session.isProvisionalTitle === undefined && root.sessionTitle.length === 0);
        root.sessionSearchQueries = Array.from(session.searchQueries ?? []).map(value => String(value)).slice(-50);
        root.sessionSources = Array.from(session.sources ?? []).slice(-100);
        root.sessionToolCheckpoints = root.recoverInterruptedCheckpoints(Array.from(session.toolCheckpoints ?? []).slice(-100));
        root.contextSummary = String(session.contextSummary ?? "");
        root.contextSummaryKey = String(session.contextSummaryKey ?? "");
        root.contextCutMessageId = "";
        root.prunedTurnCount = 0;
        root.sessionModelId = session.modelId ?? root.defaultModelId;
        root.temperature = typeof session.temperature === "number" ? session.temperature : root.defaultTemperature;
        root.thinkingLevel = root.thinkingLevels.indexOf(session.thinking) >= 0 ? session.thinking : root.defaultThinkingLevel;
        root.sessionResponseMode = AiResponseProfiles.responseModes.indexOf(String(session.responseMode ?? "")) >= 0 ? String(session.responseMode) : "";
        root.sessionWebMode = AiResponseProfiles.webModes.indexOf(String(session.webMode ?? "")) >= 0 ? String(session.webMode) : "";
        root.sessionFunctionExposure = AiResponseProfiles.functionExposures.indexOf(String(session.functionExposure ?? "")) >= 0 ? String(session.functionExposure) : "";
        const restoredProfile = root.responseProfileForModel(root.sessionModelId);
        root.thinkingLevel = restoredProfile.thinkingLevel;
        root.currentPromptFile = session.promptFile ?? "";
        root.promptOverride = session.promptOverride ?? "";
        root.sessionPersonaId = session.personaId ?? root.defaultPersonaId;
        root.sessionParentId = String(session.parentId ?? "");
        root.sessionBranchMessageId = String(session.branchMessageId ?? "");
        root.sessionToolPermissions = root.normalizedSessionToolPermissions(session.toolPermissions);
        root.sessionTags = Array.from(session.tags ?? []).map(tag => String(tag));
        root.sessionProjectId = String(session.projectId ?? "");
        root.clearAttachments();
        root.restoreDraft();
        if (recoveredMessages)
            root.commitSession(true);
    }

    function migrateAiDefaults() {
        root.migrateToolPermissions();
        const state = Persistent.states?.ai;
        if (!state)
            return;
        if (state.defaultModelId.length === 0)
            state.defaultModelId = state.modelId;
        if (state.defaultTemperature < 0)
            state.defaultTemperature = state.temperature;
        if (state.defaultThinkingLevel.length === 0)
            state.defaultThinkingLevel = state.thinkingLevel;
        if (state.defaultPersonaId.length === 0)
            state.defaultPersonaId = state.personaId;
    }

    /**
     * Carries a standing permission across the split of one tool into two.
     *
     * `get_shell_config` read the whole configuration and was allowed outright
     * because reading is harmless; `settings_find` and `settings_get` read the
     * part that was asked for and are no less harmless. Someone who had said
     * yes to the first should not be asked again for the two that replaced it.
     */
    function migrateToolPermissions() {
        if (!Config.ready)
            return;
        const tools = Config.options?.ai?.tools;
        if (!tools)
            return;
        const allow = Array.from(tools.alwaysAllow ?? []);
        if (allow.indexOf("get_shell_config") === -1)
            return;
        const migrated = allow.filter(entry => entry !== "get_shell_config");
        for (const replacement of ["settings_search", "settings_get"]) {
            if (migrated.indexOf(replacement) === -1 && Array.from(tools.alwaysDeny ?? []).indexOf(replacement) === -1)
                migrated.push(replacement);
        }
        tools.alwaysAllow = migrated;
    }

    /**
     * Hydrates new-chat defaults only after states.json has actually loaded.
     * Previously Component.onCompleted copied the compiled fallback into
     * sessionModelId first; because session state has priority, the saved
     * model arriving a moment later could never become current after boot.
     */
    function restorePersistentDefaults() {
        if (!Persistent.ready || root.persistentDefaultsRestored)
            return;
        root.migrateAiDefaults();
        const pendingModelId = root.pendingPersistentModelId;
        root.pendingPersistentModelId = "";
        if (pendingModelId.length > 0) {
            root.persistDefaultModel(pendingModelId);
        } else if (root.sessions.currentId.length === 0 && root.messageIDs.length === 0) {
            root.resetSessionSettings();
        }
        root.persistentDefaultsRestored = true;
    }

    function resetSessionSettings() {
        root.sessionModelId = root.defaultModelId;
        root.sessionPersonaId = root.defaultPersonaId;
        root.temperature = root.defaultTemperature;
        root.thinkingLevel = root.defaultThinkingLevel;
        root.sessionResponseMode = "";
        root.sessionWebMode = "";
        root.sessionFunctionExposure = "";
        root.sessionToolPermissions = ({ "alwaysAllow": [], "alwaysDeny": [] });
    }

    /**
     * Splits the conversation at a message. What came before becomes a new
     * chat and stays on screen; the chat it was split off keeps every message
     * it had, in its own file.
     */
    function forkFrom(messageId: string, keepMessage = true): bool {
        const cut = root.messageIDs.indexOf(messageId);
        if (cut < 0)
            return false;
        root.commitSession();
        const kept = root.messageIDs.slice(0, keepMessage ? cut + 1 : cut);
        for (let i = kept.length; i < root.messageIDs.length; i++) {
            delete root.messageByID[root.messageIDs[i]];
        }
        root.messageIDs = kept;
        const previousSessionId = root.sessions.currentId;
        root.cancelContextCompaction();
        root.sessions.currentId = root.sessions.newId();
        root.sessionCreatedAt = Date.now();
        // The branch remembers its trunk, so the transcript can offer the
        // answer this one replaced instead of losing it in the chat list.
        root.sessionParentId = previousSessionId;
        root.sessionBranchMessageId = messageId;
        root.sessionToolPermissions = ({ "alwaysAllow": [], "alwaysDeny": [] });
        root.contextSummary = "";
        root.contextSummaryKey = "";
        root.contextCutMessageId = "";
        root.prunedTurnCount = 0;
        if (root.sessionTitle.length > 0)
            root.sessionTitle = Translation.tr("%1 (fork)").arg(root.sessionTitle);
        root.sessionTitleAsked = root.sessionTitle.length > 0;
        root.titleRevision += 1;
        root.isProvisionalTitle = false;
        root.commitSession();
        return true;
    }

    /** Renames the conversation on screen, starting a session if there is none. */
    function nameCurrentChat(title: string) {
        const trimmed = String(title ?? "").trim();
        if (trimmed.length === 0)
            return;
        root.sessionTitle = trimmed;
        root.sessionTitleAsked = true;
        root.titleRevision += 1;
        root.isProvisionalTitle = false;
        if (root.messageIDs.length === 0) {
            root.addMessage(Translation.tr("Nothing to name yet — this chat is empty."), root.interfaceRole);
            return;
        }
        root.commitSession();
        root.addMessage(Translation.tr("Chat named “%1”").arg(trimmed), root.interfaceRole);
    }

    /** Opens a saved chat by title, for the %1load command. */
    function openChatByName(title: string): bool {
        const wanted = String(title ?? "").trim().toLowerCase();
        if (wanted.length === 0)
            return false;
        const match = root.sessions.index.find(entry => entry.title.toLowerCase() === wanted) ?? root.sessions.index.find(entry => entry.title.toLowerCase().includes(wanted));
        if (!match) {
            root.addMessage(Translation.tr("No saved chat called “%1”").arg(title), root.interfaceRole);
            return false;
        }
        root.openSession(match.id);
        return true;
    }

    // ── Naming a chat ─────────────────────────────────────────────────────
    // The first answer is followed by one small call asking the model what to
    // call the conversation. A truncation of the first message is written
    // first, so a chat is never nameless; the model's answer only replaces it
    // if one arrives. Nothing waits for either.

    property AiMessageData titleMessage: AiMessageData {}
    property var titleStrategies: ({})

    function titleStrategyFor(format: string): ApiStrategy {
        if (!root.titleStrategies[format]) {
            // Its own instance: strategies carry per-request state, and this
            // call must never be able to disturb an answer being streamed.
            const component = (format === "gemini") ? root.geminiApiStrategy : ((format === "anthropic") ? root.anthropicApiStrategy : root.openAiCompatStrategy);
            root.titleStrategies[format] = component.createObject(root);
        }
        return root.titleStrategies[format];
    }

    function shortTitle(text: string): string {
        const oneLine = String(text ?? "").replace(/[\r\n]+/g, " ").replace(/["'#*`_>]/g, "").replace(/\s+/g, " ").trim();
        if (oneLine.length <= 42)
            return oneLine;
        return oneLine.slice(0, 41).trim() + "…";
    }

    function firstTextOfRole(role: string): string {
        for (let i = 0; i < root.messageIDs.length; i++) {
            const message = root.messageByID[root.messageIDs[i]];
            if (message?.role === role)
                return String(message.rawContent ?? "").trim();
        }
        return "";
    }

    function autoTitle() {
        if (root.sessionTitleAsked || root.sessionTitle.length > 0)
            return;
        const opening = root.firstTextOfRole("user");
        if (opening.length === 0)
            return;
        root.sessionTitleAsked = true;
        root.sessionTitle = root.shortTitle(opening);
        root.titleRevision += 1;
        root.isProvisionalTitle = true;
        root.titleRequestSessionId = root.sessions.currentId;
        root.titleRequestRevision = root.titleRevision;
        root.requestTitle(opening, root.titleRequestSessionId, root.titleRequestRevision);
    }

    function requestTitle(opening: string, sessionId: string, expectedRevision: int) {
        const model = root.currentModelEntry;
        if (!model || titleRequester.running)
            return;
        if (!root.canSubmit(model.id).allowed)
            return;
        const strategy = root.titleStrategyFor(model.api_format || "openai");
        const answer = root.firstTextOfRole("assistant");
        const prompt = root.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `${opening.slice(0, 600)}\n\n---\n\n${answer.slice(0, 400)}`,
            "rawContent": "",
            "thinking": false,
            "done": true
        });
        strategy.thinkingOverride = "off";
        const data = strategy.buildRequestData(model, [prompt], root.titleInstruction, 0.2, null);
        strategy.thinkingOverride = "";
        prompt.destroy();

        root.titleMessage.content = "";
        root.titleMessage.rawContent = "";
        root.titleMessage.thought = "";
        titleRequester.model = model;
        titleRequester.strategy = strategy;
        titleRequester.message = root.titleMessage;
        titleRequester.endpoint = strategy.buildEndpoint(model);
        titleRequester.requestData = data;
        titleRequester.apiKey = model.requires_key ? (root.apiKeys?.[model.key_id] ?? "") : "";
        titleRequester.start();
    }

    readonly property string titleInstruction: "Name this conversation in at most six words. Answer with the name only: no quotes, no trailing punctuation, no explanation."

    AiRequest {
        id: titleRequester
        apiKeyEnvVarName: root.apiKeyEnvVarName
        scriptPath: `/tmp/quickshell-${SystemInfo.username}/ai/title.sh`

        onLine: data => {
            try {
                titleRequester.strategy.parseResponseLine(data, root.titleMessage);
            } catch (e) {
                // A name is not worth a message in the chat.
            }
        }

        onFinished: reason => {
            if (reason !== "done")
                return;
            const suggested = root.shortTitle(root.titleMessage.content);
            if (suggested.length === 0 || suggested.length > 60)
                return;
            if (root.sessions.currentId !== root.titleRequestSessionId || root.titleRevision !== root.titleRequestRevision || !root.isProvisionalTitle)
                return;
            root.sessionTitle = suggested;
            root.isProvisionalTitle = false;
            root.titleRevision += 1;
            root.commitSession();
        }
    }
}
