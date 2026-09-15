pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.services
import qs.services.ai
import qs.modules.common

/**
 * Executes a single-turn, out-of-band LLM task (such as rewriting, summarizing,
 * title generation or code explanation) without creating a chat session or
 * polluting conversation transcripts.
 *
 * Strictly respects Config.options.policies.ai:
 * - 0: disabled completely.
 * - 2: restricts to local models (Ollama).
 */
QtObject {
    id: root

    property string taskName: ""
    property string systemPrompt: ""
    property string userText: ""
    property string targetModelId: ""
    // Forces the strategy's thinking level for this task ("off" for
    // housekeeping that should not pay for reasoning); empty keeps the
    // user's setting.
    property string thinkingLevel: ""
    property real temperature: 0.3
    // Script name under /tmp/quickshell-<user>/ai/. Two tasks that can run
    // at the same time must not share a body file.
    property string scriptName: "text_task"
    // "none" keeps the historical single-turn behaviour. Hosts that need the
    // same capabilities as AIChat set this to the effective chat mode.
    property string toolMode: "none"
    readonly property string sharedTaskKey: "notes:" + (root.taskName || root.scriptName)

    readonly property int policy: Number(Config.options?.policies?.ai ?? 1)
    readonly property bool allowed: root.policy !== 0
    readonly property bool localOnly: root.policy === 2

    // Resolve active model honoring privacy policy
    readonly property AiModel model: {
        if (!root.allowed)
            return null;
        if (root.targetModelId && Ai.catalog.models[root.targetModelId]) {
            const m = Ai.catalog.models[root.targetModelId];
            if (root.localOnly && !Ai.catalog.isModelLocal(m))
                return null;
            return m;
        }
        const current = Ai.currentModelEntry;
        if (root.localOnly) {
            if (current && Ai.catalog.isModelLocal(current))
                return current;
            for (let i = 0; i < Ai.catalog.modelIds.length; i++) {
                const cand = Ai.catalog.models[Ai.catalog.modelIds[i]];
                if (cand && Ai.catalog.isModelLocal(cand))
                    return cand;
            }
            return null;
        }
        return current;
    }

    readonly property string modelName: root.model ? (root.model.title || root.model.name) : (root.localOnly ? Translation.tr("A local model is required") : Translation.tr("No model"))
    readonly property bool isLocal: root.model ? Ai.catalog.isModelLocal(root.model) : false
    readonly property int charCount: (root.systemPrompt.length + root.userText.length)

    property string status: "idle" // "idle" | "running" | "done" | "error" | "aborted"
    property string resultText: ""
    property string errorText: ""
    readonly property bool running: root.status === "running"

    signal chunk(string text)
    signal finished(string result)
    signal failed(string error)

    property var _strategy: null
    property AiMessageData _message: AiMessageData {}
    property var _history: []
    property var _pendingToolCalls: []
    property bool _followUpQueued: false
    property int _roundContentLength: 0
    property bool _sharedTaskClaimed: false
    // What the provider sent outside the stream frames; on failure that is
    // its error JSON, which says far more than the status code.
    property string _rawTail: ""

    function start(sysPrompt, text, modelId): bool {
        if (root.running)
            root.cancel();

        if (sysPrompt !== undefined)
            root.systemPrompt = String(sysPrompt);
        if (text !== undefined)
            root.userText = String(text);
        if (modelId)
            root.targetModelId = String(modelId);

        if (!root.allowed) {
            root.status = "error";
            root.errorText = Translation.tr("The AI features are switched off in the shell's settings.");
            root.failed(root.errorText);
            return false;
        }

        const activeModel = root.model;
        if (!activeModel) {
            root.status = "error";
            root.errorText = root.localOnly
                ? Translation.tr("Only a model running on this machine may be used, and none is set up.")
                : Translation.tr("No AI model is set up yet.");
            root.failed(root.errorText);
            return false;
        }

        // Tool-capable tasks share the AIChat transport and broker. Refusing
        // to overlap keeps one tool call from being attributed to the wrong
        // host while the visible chat is already in flight.
        if (root.toolMode !== "none" && (Ai.isGenerating || Ai.broker.pendingCount > 0)) {
            root.status = "error";
            root.errorText = Translation.tr("AI is busy with another conversation. Stop it before starting this task.");
            root.failed(root.errorText);
            return false;
        }

        if (root.toolMode !== "none") {
            if (activeModel.tools !== true) {
                root.status = "error";
                root.errorText = Translation.tr("The selected AI model does not support the Notes tools needed for this request.");
                root.failed(root.errorText);
                return false;
            }
            if (!Ai.beginSharedTask(root.sharedTaskKey)) {
                root.status = "error";
                root.errorText = Translation.tr("AI is busy with another conversation. Stop it before starting this task.");
                root.failed(root.errorText);
                return false;
            }
            root._sharedTaskClaimed = true;
        }

        root.resultText = "";
        root.errorText = "";
        root.status = "running";
        root._history = [];
        root._pendingToolCalls = [];
        root._followUpQueued = false;
        root._roundContentLength = 0;
        root._rawTail = "";

        try {
            if (root._strategy && typeof root._strategy.destroy === "function")
                root._strategy.destroy();
            root._strategy = Ai.createApiStrategy(activeModel.api_format || "gemini", root);
            root._strategy.reset();
        } catch (e) {
            console.warn("[AiTextTask] Error getting strategy:", e);
        }

        if (!root._strategy) {
            root.status = "error";
            root.errorText = Translation.tr("Failed to initialize model strategy.");
            root.releaseSharedTask();
            root.failed(root.errorText);
            return false;
        }

        // A real message object: the strategies read rawContent, attachments
        // and the function-call fields off it, none of which a bare
        // {role, content} literal has.
        const prompt = Ai.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": root.userText,
            "rawContent": root.userText
        });
        root._history = [prompt];
        return root.startRound(activeModel);
    }

    /**
     * Starts one model round. A tool result is another message in the same
     * ephemeral history, so the next round is built by the exact same provider
     * strategy that AIChat uses.
     */
    function startRound(activeModel): bool {
        const model = activeModel ?? root.model;
        if (!model || root.status !== "running") {
            root.releaseSharedTask();
            return false;
        }

        root._followUpQueued = false;
        const profile = Ai.responseProfileForModel(model.id);
        root._strategy.activeThinkingLevel = profile.thinkingLevel;
        root._message = Ai.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "model": model.id,
            "responseMode": profile.responseMode,
            "webMode": profile.webMode,
            "functionExposure": profile.functionExposure,
            "profileFallback": profile.fallbackReason,
            "content": "",
            "rawContent": "",
            "thinking": true,
            "done": false,
            "createdAt": Date.now()
        });
        root._roundContentLength = 0;
        root._rawTail = "";

        const tools = root.toolMode !== "none" && model.tools === true
            ? Ai.toolbox.wireTools(model.api_format || "gemini", root.toolMode)
            : [];
        let reqData;
        root._strategy.thinkingOverride = root.thinkingLevel;
        try {
            reqData = root._strategy.buildRequestData(
                model,
                root._history,
                root.systemPrompt,
                root.temperature,
                tools
            );
        } catch (e) {
            root.status = "error";
            root.errorText = Translation.tr("Failed to build request data: ") + e.message;
            root.releaseSharedTask();
            root.failed(root.errorText);
            return false;
        } finally {
            root._strategy.thinkingOverride = "";
        }

        requester.model = model;
        requester.strategy = root._strategy;
        requester.message = root._message;
        requester.endpoint = root._strategy.buildEndpoint(model);
        requester.requestData = reqData;
        requester.apiKey = model.requires_key ? (Ai.apiKeys?.[model.key_id] ?? "") : "";
        const started = requester.start();
        if (!started) {
            root.status = "error";
            root.errorText = Translation.tr("Could not start the AI request.");
            root.releaseSharedTask();
            root.failed(root.errorText);
        }
        return started;
    }

    function ensureAssistantInHistory(message): void {
        if (!message || root._history.indexOf(message) >= 0)
            return;
        root._history = root._history.concat([message]);
    }

    function handleFunctionCalls(calls, message): void {
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
            const key = normalized.id.length > 0
                ? normalized.id
                : normalized.name + ":" + JSON.stringify(normalized.args);
            const exists = known.some(item => {
                const itemKey = String(item.id ?? "").length > 0
                    ? String(item.id)
                    : String(item.name ?? "") + ":" + JSON.stringify(item.args ?? ({}));
                return itemKey === key;
            });
            if (exists)
                return;
            known.push(normalized);
            fresh.push(normalized);
        });
        if (fresh.length === 0)
            return;
        ensureAssistantInHistory(message);
        message.toolCalls = known;
        message.functionCalls = known.map(call => ({
                    name: call.name,
                    args: call.args,
                    id: call.id
                }));
        root._pendingToolCalls = root._pendingToolCalls.concat(fresh.map(call => ({
                    call: call,
                    message: message
                })));
        if (root._pendingToolCalls.length === fresh.length)
            root.processNextToolCall();
    }

    function processNextToolCall(): void {
        if (root._pendingToolCalls.length === 0) {
            root.requestFollowUp();
            return;
        }
        const next = root._pendingToolCalls[0];
        root._pendingToolCalls = root._pendingToolCalls.slice(1);
        Ai.broker.dispatch({
            name: next.call.name,
            args: next.call.args,
            id: next.call.id
        }, next.message, root);
    }

    function requestFollowUp(): void {
        if (root._pendingToolCalls.length > 0) {
            root.processNextToolCall();
            return;
        }
        if (requester.running) {
            root._followUpQueued = true;
            return;
        }
        Qt.callLater(() => root.startRound(root.model));
    }

    function addFunctionOutputMessage(name, output, callId = "", sessionId = ""): void {
        const message = Ai.createFunctionOutputMessage(name, output, true, callId, false);
        root._history = root._history.concat([message]);
    }

    function releaseSharedTask(): void {
        if (!root._sharedTaskClaimed)
            return;
        Ai.endSharedTask(root.sharedTaskKey);
        root._sharedTaskClaimed = false;
    }

    // The provider's own words for a failure, when what it sent outside the
    // stream frames holds an error message; "" otherwise. Error bodies come
    // pretty-printed across many lines, so this is a search, not a parse.
    function providerError(): string {
        const found = root._rawTail.match(/"message"\s*:\s*"((?:[^"\\]|\\.)*)"/);
        if (!found)
            return "";
        try {
            return String(JSON.parse(`"${found[1]}"`)).slice(0, 300);
        } catch (e) {
            return found[1].slice(0, 300);
        }
    }

    function cancel(): void {
        if (root.toolMode !== "none")
            Ai.broker.cancelAll(Translation.tr("Stopped"));
        if (requester.running) {
            requester.abort();
        }
        root.status = "aborted";
        root.releaseSharedTask();
    }

    function estimateTokens(text): int {
        return Ai.estimateTokens(String(text ?? ""));
    }

    property AiRequest requester: AiRequest {
        id: requester
        apiKeyEnvVarName: Ai.apiKeyEnvVarName
        scriptPath: `/tmp/quickshell-${SystemInfo.username}/ai/${root.scriptName}.sh`
        maxRetries: 1

        onLine: data => {
            if (!root.running)
                return;
            if (!data.startsWith("data:"))
                root._rawTail = (root._rawTail + data + "\n").slice(-4000);
            try {
                const result = requester.strategy.parseResponseLine(data, root._message);
                const functionCalls = Array.isArray(result?.functionCalls)
                    ? result.functionCalls
                    : (result?.functionCall ? [result.functionCall] : []);
                if (functionCalls.length > 0)
                    root.handleFunctionCalls(functionCalls, root._message);
                const currentContent = root._message.content;
                if (currentContent.length > root._roundContentLength) {
                    const added = currentContent.slice(root._roundContentLength);
                    root._roundContentLength = currentContent.length;
                    root.resultText = currentContent;
                    root.chunk(added);
                }
            } catch (e) {
                // Ignore parse errors on individual stream lines
            }
        }

        onFinished: (reason, httpStatus, code) => {
            if (reason === "aborted") {
                root.status = "aborted";
                root.releaseSharedTask();
                return;
            }

            let trailingCalls = [];
            if (reason === "done") {
                try {
                    const result = requester.strategy.onRequestFinished(root._message) ?? ({});
                    trailingCalls = Array.isArray(result.functionCalls)
                        ? result.functionCalls
                        : (result.functionCall ? [result.functionCall] : []);
                    if (trailingCalls.length > 0)
                        root.handleFunctionCalls(trailingCalls, root._message);
                } catch (e) {
                    console.log("[AiTextTask] Could not finish response:", e);
                }
            }

            const toolCalls = Array.from(root._message.toolCalls ?? []);
            if (reason === "done" && toolCalls.length > 0) {
                root.ensureAssistantInHistory(root._message);
                root._message.thinking = false;
                root._message.done = true;
                root._message.completedAt = Date.now();
                if (root._followUpQueued) {
                    root._followUpQueued = false;
                    Qt.callLater(() => root.requestFollowUp());
                }
                return;
            }

            // Every strategy records the provider's stop reason on the last
            // frame; none means the stream was cut before it — a shell
            // reload, a dropped connection — and what arrived is not an
            // answer, however clean the exit looks.
            if (reason === "done" && root._message.content.length > 0 && root._message.finishReason !== "") {
                root.resultText = root._message.content.trim();
                root.status = "done";
                root.finished(root.resultText);
                root.releaseSharedTask();
                return;
            }

            root.status = "error";
            if (reason === "done" && root._message.content.length > 0) {
                root.errorText = Translation.tr("The answer was cut off before it was complete.");
            } else if (httpStatus === 401 || httpStatus === 403) {
                root.errorText = Translation.tr("API key rejected or unauthorized.");
            } else if (httpStatus === 429) {
                root.errorText = Translation.tr("Rate limit or quota exceeded.");
            } else if (code === 6 || code === 7) {
                root.errorText = Translation.tr("Could not connect to model endpoint.");
            } else {
                root.errorText = Translation.tr("AI request failed (status: %1, code: %2).").arg(httpStatus).arg(code);
            }
            const detail = root.providerError();
            if (detail !== "")
                root.errorText += " " + detail;
            root.failed(root.errorText);
            root.releaseSharedTask();
        }
    }
}
