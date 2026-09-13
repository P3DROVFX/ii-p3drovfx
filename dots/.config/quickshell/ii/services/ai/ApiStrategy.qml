import QtQuick
import qs.modules.common

QtObject {
    function buildEndpoint(model: AiModel): string { throw new Error("Not implemented") }
    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>) { throw new Error("Not implemented") }
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string { throw new Error("Not implemented") }
    function parseResponseLine(line: string, message: AiMessageData) { throw new Error("Not implemented") }
    function onRequestFinished(message: AiMessageData): var { return {} } // Default: no special handling

    // ── Attachments ───────────────────────────────────────────────────────
    // A file never travels through the request body as it is built here: the
    // body carries a marker, and the file is written into it just before the
    // request goes out. Base64 of anything bigger than a thumbnail is well
    // past what a command line can hold, and this way nothing has to be
    // escaped twice.

    /** Files the request being built needs, as {marker, mode, path}. */
    property var attachmentInjections: []

    function beginAttachments() {
        attachmentInjections = [];
    }

    /**
     * Reserves a place in the body for one file. `mode` is "b64" for anything
     * the API takes as bytes, "text" for source and plain text, which is worth
     * far more to a model as itself than as base64.
     */
    function attachmentMarker(path: string, mode: string): string {
        const marker = `@@II_ATT_${attachmentInjections.length}@@`;
        attachmentInjections = [...attachmentInjections, {
                "marker": marker,
                "mode": mode,
                "path": path
            }];
        return marker;
    }

    /**
     * How a text part should be produced: read straight off disk, or run
     * through the extractor first because the file is a document.
     */
    function textModeFor(file: var): string {
        return file?.extracted === true ? "extract" : "text";
    }

    /** Attachments of a message, skipping any the model in use cannot read. */
    function attachmentsOf(message: AiMessageData, model: AiModel): var {
        const files = Array.from(message?.attachments ?? []);
        if (files.length === 0)
            return [];
        return files.filter(file => (file.kind === "context" && String(file.content ?? "").length > 0)
                            || file.kind === "text" || (model?.attachments ?? false));
    }

    /** Cleared before every request. Subclasses override this, not `reset()`. */
    function resetState() {}

    function reset() {
        thoughtOpen = false;
        resetState();
    }

    /**
     * Output cap for a request. The model's own limit is the default, so no
     * answer is cut short by a number that predates the model; the config
     * option lowers it (to save tokens, or to keep answers short) and is
     * clamped to what the model actually accepts.
     */
    /**
     * Forces the cap for one build, like `thinkingOverride`. Set around a call
     * whose answer nobody reads — testing that a key works.
     */
    property int outputOverride: 0

    function maxOutputTokens(model: AiModel): int {
        if (outputOverride > 0)
            return outputOverride;
        const configured = Config.options?.ai?.maxOutputTokens ?? 0;
        const supported = model?.maxOutput ?? 0;
        if (configured > 0)
            return supported > 0 ? Math.min(configured, supported) : configured;
        return supported > 0 ? supported : 4096;
    }

    // ── Reasoning ─────────────────────────────────────────────────────────
    // How hard a model is asked to think is one setting for the user, and a
    // different knob on every provider. The level is resolved here; each
    // strategy turns it into whatever its own API calls that knob.

    readonly property var thinkingBudgets: ({
            "off": 0,
            "low": 1024,
            "medium": 4096,
            "high": 16384
        })

    /**
     * Forces the level for one build, whatever the user picked. Set around a
     * housekeeping call — naming a chat — so it does not pay for reasoning.
     */
    property string thinkingOverride: ""
    /** The active chat's setting; empty keeps compatibility with old callers. */
    property string activeThinkingLevel: ""

    /** "off", "low", "medium" or "high", for what this model can actually do. */
    function thinkingLevel(model: AiModel): string {
        if (!model?.thinking)
            return "off";
        const requested = thinkingOverride.length > 0 ? thinkingOverride : (activeThinkingLevel.length > 0 ? activeThinkingLevel : (Persistent.states?.ai?.defaultThinkingLevel ?? Persistent.states?.ai?.thinkingLevel ?? "medium"));
        const level = (thinkingBudgets[requested] === undefined) ? "medium" : requested;
        // Some models reason no matter what is asked of them. Saying "off" to
        // one of those is rejected, so it gets the smallest budget instead.
        if (level === "off" && model.thinkingAlwaysOn)
            return "low";
        return level;
    }

    function thinkingOn(model: AiModel): bool {
        return thinkingLevel(model) !== "off";
    }

    /**
     * Tokens the model may spend reasoning. Drawn from the same allowance as
     * the answer, so it never takes all of it — a budget that meets the
     * output cap leaves nothing to answer with, and is refused.
     */
    function thinkingBudget(model: AiModel): int {
        const budget = thinkingBudgets[thinkingLevel(model)] ?? 0;
        if (budget === 0)
            return 0;
        const half = Math.floor(maxOutputTokens(model) / 2);
        return Math.max(1024, Math.min(budget, half));
    }

    // Every provider streams thought and answer as two interleaved streams and
    // only the wire format differs, so all of them push through here. The
    // thought is kept apart from the answer: it is not what the user asked
    // for, it is not what gets copied, and it is not sent back as text.

    property bool thoughtOpen: false

    function appendThought(message: AiMessageData, text: string) {
        if (!message || !text || text.length === 0)
            return;
        if (!thoughtOpen) {
            thoughtOpen = true;
            if (message.thoughtStartedAt === 0)
                message.thoughtStartedAt = Date.now();
        }
        message.thought += text;
    }

    function appendAnswer(message: AiMessageData, text: string) {
        if (!message || !text || text.length === 0)
            return;
        closeThought(message);
        message.content += text;
        message.rawContent += text;
    }

    function closeThought(message: AiMessageData) {
        if (!thoughtOpen || !message)
            return;
        thoughtOpen = false;
        if (message.thoughtStartedAt > 0)
            message.thoughtDurationMs = Date.now() - message.thoughtStartedAt;
    }
}
