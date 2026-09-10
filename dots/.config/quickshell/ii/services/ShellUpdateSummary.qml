pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.services.ai
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Plain-language summary of the commits ShellUpdates found, written by the AI
 * tab's current model. Optional: it spends one request on the user's key, so
 * it only runs by itself when the user switched it on and the update is big
 * enough to be worth condensing (below that the grouped commit list reads
 * fine on its own). A manual run is always available.
 *
 * The result is cached on disk keyed by the commit range and model, so a
 * shell reload, the periodic re-check and a restart never re-run it; a new
 * remote HEAD does.
 *
 * Mirrors the AI tab's context compaction: one AiRequest of its own, a
 * strategy built for the model, thinking off, low temperature, and no chat
 * session is touched.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.update?.aiSummary ?? false
    readonly property int minCommits: Math.max(1, Config.options?.update?.aiSummaryMinCommits ?? 10)

    readonly property var submitCheck: Ai.canSubmit()
    // A model that can answer right now, plus something to summarise.
    readonly property bool available: (submitCheck?.allowed ?? false) && ShellUpdates.hasUpdate && ShellUpdates.commits.length > 0
    readonly property string unavailableReason: submitCheck?.reason ?? ""
    readonly property string modelId: Ai.currentModelEntry?.id ?? ""
    readonly property string modelTitle: Ai.currentModelEntry?.title ?? Ai.currentModelEntry?.name ?? root.modelId

    // What the cache holds. `text` is only meaningful when `current`.
    property string text: ""
    property string cachedFrom: ""
    property string cachedTo: ""
    property string cachedModel: ""
    property real generatedAt: 0
    readonly property bool current: text !== "" && ShellUpdates.hasUpdate && cachedFrom === ShellUpdates.activeCommit && cachedTo === ShellUpdates.remoteCommit

    property bool generating: false
    property string error: ""
    property bool cacheLoaded: false

    // The range a request in flight was started for; a check that moves the
    // remote while it runs makes its answer stale on arrival.
    property string pendingFrom: ""
    property string pendingTo: ""
    // The last line the provider sent; on failure it usually holds the
    // error JSON, which says far more than the status code.
    property string lastRawLine: ""
    // A QML reload tears this singleton down mid-request: curl is killed, yet
    // the process still reports a clean exit with the 200 it already saw, and
    // the half-written answer would be cached as though it were whole.
    property bool tearingDown: false

    // Bodies are only worth sending for a range small enough that the model
    // can use them; past that the subjects carry the meaning, and the whole
    // payload is capped so a main merge cannot blow the context window.
    readonly property int bodyCommitLimit: 50
    readonly property int payloadCharLimit: 60000

    readonly property string instruction: "You write release notes for end users of a Linux desktop shell (a Quickshell and Hyprland configuration called Illogical Impulse). You are given the commits between the version the user has installed and the latest one, newest first. Write a short Markdown summary: three to six bullet points grouped by what changes for the user — new features, fixes, visual changes, settings or configuration changes. Put anything that changes behaviour or configuration, or that needs action from the user, first. Plain language, no commit hashes, no file or code names unless they matter to the user, no code formatting or backticks, no preamble and no heading. Answer with the bullets only."

    property AiMessageData message: AiMessageData {}

    function load() {}

    function buildPrompt(): string {
        const commits = Array.from(ShellUpdates.commits ?? []);
        const withBodies = commits.length <= root.bodyCommitLimit;
        const lines = commits.map(commit => {
            const subject = String(commit.subject ?? "").trim();
            const body = withBodies ? String(commit.body ?? "").trim() : "";
            if (body === "") return `- ${subject}`;
            return `- ${subject}\n${body.split("\n").map(line => `    ${line}`).join("\n")}`;
        });
        const header = [
            `Installed: ${ShellUpdates.activeCommit.substring(0, 7)}`,
            `Latest: ${ShellUpdates.remoteCommit.substring(0, 7)}`,
            `${ShellUpdates.commitsBehind} commits${ShellUpdates.commitsTruncated ? " (only the newest are listed)" : ""}`
        ].join("\n");
        let body = lines.join("\n");
        if (body.length > root.payloadCharLimit)
            body = body.slice(0, root.payloadCharLimit) + "\n- … (list cut here)";
        return `${header}\n\n${body}`;
    }

    // Runs after a check when the user opted in and the update is big enough.
    function maybeAutoSummarize() {
        if (!root.enabled || !root.cacheLoaded) return;
        if (ShellUpdates.commitsBehind < root.minCommits) return;
        root.summarize(false);
    }

    function summarize(force = false): bool {
        if (root.generating || !root.available) return false;
        if (!force && root.current && root.cachedModel === root.modelId) return false;
        const model = Ai.currentModelEntry;
        if (!model) return false;
        const strategy = Ai.createApiStrategy(model.api_format || "openai");
        if (!strategy) return false;

        root.error = "";
        root.lastRawLine = "";
        root.message.content = "";
        root.message.rawContent = "";
        root.message.thought = "";
        root.message.finishReason = "";
        root.message.done = false;

        const request = Ai.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": root.buildPrompt(),
            "rawContent": ""
        });
        strategy.thinkingOverride = "off";
        strategy.activeThinkingLevel = "off";
        const data = strategy.buildRequestData(model, [request], root.instruction, 0.2, null);
        request.destroy();

        requester.model = model;
        requester.strategy = strategy;
        requester.message = root.message;
        requester.endpoint = strategy.buildEndpoint(model);
        requester.requestData = data;
        requester.apiKey = model.requires_key ? (Ai.apiKeys?.[model.key_id] ?? "") : "";
        root.pendingFrom = ShellUpdates.activeCommit;
        root.pendingTo = ShellUpdates.remoteCommit;
        if (!requester.start()) {
            root._releaseStrategy();
            return false;
        }
        root.generating = true;
        print(`[ShellUpdateSummary] summarising ${ShellUpdates.commits.length} commits with ${model.id}`);
        return true;
    }

    function _describeFailure(reason: string, status: int): string {
        const base = status > 0 ? `${reason} (${status})` : reason;
        const raw = root.lastRawLine.trim().replace(/^data:\s*/, "");
        try {
            const parsed = JSON.parse(raw);
            const message = parsed?.error?.message ?? parsed?.[0]?.error?.message ?? "";
            if (message) return `${base}: ${String(message).slice(0, 300)}`;
        } catch (e) {
            // Not JSON; fall through to the bare status.
        }
        return base;
    }

    function _releaseStrategy() {
        const strategy = requester.strategy;
        requester.strategy = null;
        if (strategy && typeof strategy.destroy === "function")
            strategy.destroy();
    }

    function _finish(reason: string, status: int) {
        root.generating = false;
        // Inline code renders in a monospace font that sits badly in a
        // release note; the words read fine without it.
        const answer = String(root.message.content ?? "").replace(/`+/g, "").trim();
        const stillWanted = root.pendingFrom === ShellUpdates.activeCommit && root.pendingTo === ShellUpdates.remoteCommit;
        root._releaseStrategy();
        if (root.tearingDown) return;
        if (reason !== "done" || answer === "") {
            root.error = root._describeFailure(reason, status);
            print(`[ShellUpdateSummary] failed: ${root.error}`);
            return;
        }
        // Every strategy records the provider's stop reason on the last
        // frame; none means the stream was cut before it — a shell reload, a
        // dropped connection — and what arrived is not a summary.
        if (root.message.finishReason === "") {
            root.error = Translation.tr("interrupted before the answer was complete");
            print(`[ShellUpdateSummary] failed: ${root.error} (${answer.length} chars received)`);
            return;
        }
        if (!stillWanted) {
            print("[ShellUpdateSummary] range moved while summarising; answer dropped");
            return;
        }
        print(`[ShellUpdateSummary] done: ${answer.length} chars, finish reason ${root.message.finishReason}`);
        root.text = answer;
        root.cachedFrom = root.pendingFrom;
        root.cachedTo = root.pendingTo;
        root.cachedModel = String(requester.model?.id ?? root.modelId);
        root.generatedAt = Date.now();
        root.save();
    }

    function save() {
        cacheFile.setText(JSON.stringify({
            schema: 1,
            from: root.cachedFrom,
            to: root.cachedTo,
            model: root.cachedModel,
            generatedAt: root.generatedAt,
            text: root.text
        }, null, 2));
    }

    function clear() {
        root.text = "";
        root.cachedFrom = "";
        root.cachedTo = "";
        root.cachedModel = "";
        root.generatedAt = 0;
        root.error = "";
        root.save();
    }

    AiRequest {
        id: requester
        apiKeyEnvVarName: Ai.apiKeyEnvVarName
        scriptPath: `/tmp/quickshell-${SystemInfo.username}/ai/update-summary.sh`

        onLine: data => {
            root.lastRawLine = data;
            try {
                requester.strategy.parseResponseLine(data, root.message);
            } catch (e) {
                // A malformed line costs at most part of the summary.
            }
        }

        onFinished: (reason, status, code) => root._finish(reason, status)
    }

    FileView {
        id: cacheFile
        path: Directories.shellUpdateSummaryPath
        // Nothing but this service writes the file.
        watchChanges: false
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(cacheFile.text());
                if (parsed?.schema === 1) {
                    root.text = String(parsed.text ?? "");
                    root.cachedFrom = String(parsed.from ?? "");
                    root.cachedTo = String(parsed.to ?? "");
                    root.cachedModel = String(parsed.model ?? "");
                    root.generatedAt = Number(parsed.generatedAt ?? 0);
                }
            } catch (e) {
                // Unreadable cache: behave as though there was none.
            }
            root.cacheLoaded = true;
            root.maybeAutoSummarize();
        }
        onLoadFailed: {
            root.cacheLoaded = true;
            root.maybeAutoSummarize();
        }
    }

    Component.onDestruction: root.tearingDown = true

    Connections {
        target: ShellUpdates
        function onCheckFinished() {
            root.maybeAutoSummarize();
        }
    }

    // Switching the option on with an update already waiting should not need
    // another check to act.
    onEnabledChanged: if (root.enabled) root.maybeAutoSummarize()
}
