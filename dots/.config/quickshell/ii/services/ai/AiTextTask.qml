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

        root.resultText = "";
        root.errorText = "";
        root.status = "running";

        const format = activeModel.api_format || "gemini";
        try {
            root._strategy = Ai.titleStrategyFor(format);
            root._strategy.reset();
        } catch (e) {
            console.warn("[AiTextTask] Error getting strategy:", e);
        }

        if (!root._strategy) {
            root.status = "error";
            root.errorText = Translation.tr("Failed to initialize model strategy.");
            root.failed(root.errorText);
            return false;
        }

        root._message.content = "";
        root._message.rawContent = "";

        const messages = [
            { role: "user", content: root.userText }
        ];

        let reqData;
        try {
            reqData = root._strategy.buildRequestData(
                activeModel,
                messages,
                root.systemPrompt,
                0.3,
                []
            );
        } catch (e) {
            root.status = "error";
            root.errorText = Translation.tr("Failed to build request data: ") + e.message;
            root.failed(root.errorText);
            return false;
        }

        requester.model = activeModel;
        requester.strategy = root._strategy;
        requester.message = root._message;
        requester.endpoint = root._strategy.buildEndpoint(activeModel);
        requester.requestData = reqData;
        requester.apiKey = activeModel.requires_key ? (Ai.apiKeys?.[activeModel.key_id] ?? "") : "";

        return requester.start();
    }

    function cancel(): void {
        if (requester.running) {
            requester.abort();
        }
        root.status = "aborted";
    }

    property AiRequest requester: AiRequest {
        id: requester
        apiKeyEnvVarName: Ai.apiKeyEnvVarName
        scriptPath: `/tmp/quickshell-${SystemInfo.username}/ai/text_task.sh`
        maxRetries: 1

        onLine: data => {
            if (!root.running)
                return;
            try {
                requester.strategy.parseResponseLine(data, root._message);
                const currentContent = root._message.content;
                if (currentContent.length > root.resultText.length) {
                    const added = currentContent.slice(root.resultText.length);
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
                return;
            }
            if (reason === "done" && root._message.content.length > 0) {
                root.resultText = root._message.content.trim();
                root.status = "done";
                root.finished(root.resultText);
                return;
            }

            root.status = "error";
            if (httpStatus === 401 || httpStatus === 403) {
                root.errorText = Translation.tr("API key rejected or unauthorized.");
            } else if (httpStatus === 429) {
                root.errorText = Translation.tr("Rate limit or quota exceeded.");
            } else if (code === 6 || code === 7) {
                root.errorText = Translation.tr("Could not connect to model endpoint.");
            } else {
                root.errorText = Translation.tr("AI request failed (status: %1, code: %2).").arg(httpStatus).arg(code);
            }
            root.failed(root.errorText);
        }
    }
}
