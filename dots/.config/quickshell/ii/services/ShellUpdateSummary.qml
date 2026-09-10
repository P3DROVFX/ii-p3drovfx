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
 * tab's current model (a local one under the local-only policy). Optional: it
 * spends one request on the user's key, so it only runs by itself when the
 * user switched it on and the update is big enough to be worth condensing
 * (below that the grouped commit list reads fine on its own). A manual run is
 * always available.
 *
 * The request is an AiTextTask, the same one-shot helper the notes editor
 * uses; this service adds the gating, the range bookkeeping and the on-disk
 * cache. The cache is keyed by the commit range, so a shell reload, the
 * periodic re-check and a restart never re-run it; a new remote HEAD does.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.update?.aiSummary ?? false
    readonly property int minCommits: Math.max(1, Config.options?.update?.aiSummaryMinCommits ?? 10)

    // The model the task would use, and whether it can answer right now.
    readonly property var submitCheck: Ai.canSubmit(task.model?.id ?? "")
    readonly property bool available: (submitCheck?.allowed ?? false) && ShellUpdates.hasUpdate && ShellUpdates.commits.length > 0
    readonly property string unavailableReason: submitCheck?.reason ?? ""
    readonly property string modelId: task.model?.id ?? ""
    readonly property string modelTitle: task.model ? (task.model.title || task.model.name || root.modelId) : ""
    readonly property bool generating: task.running

    // What the cache holds. `text` is only meaningful when `current`.
    property string text: ""
    property string cachedFrom: ""
    property string cachedTo: ""
    property string cachedModel: ""
    property real generatedAt: 0
    readonly property bool current: text !== "" && ShellUpdates.hasUpdate && cachedFrom === ShellUpdates.activeCommit && cachedTo === ShellUpdates.remoteCommit

    property string error: ""
    property bool cacheLoaded: false

    // The range a request in flight was started for; a check that moves the
    // remote while it runs makes its answer stale on arrival.
    property string pendingFrom: ""
    property string pendingTo: ""
    // The range the automatic run last tried, whatever came of it. A failure
    // — a rejected key, an exhausted quota, a model refusing a parameter —
    // must not be retried on every check; the Redo button is the way to try
    // again.
    property string attemptedFrom: ""
    property string attemptedTo: ""
    // A QML reload tears this singleton down mid-request; whatever the task
    // reports on its way out must not be cached.
    property bool tearingDown: false

    // Bodies are only worth sending for a range small enough that the model
    // can use them; past that the subjects carry the meaning, and the whole
    // payload is capped so a main merge cannot blow the context window.
    readonly property int bodyCommitLimit: 50
    readonly property int payloadCharLimit: 60000

    readonly property string instruction: "You write release notes for end users of a Linux desktop shell (a Quickshell and Hyprland configuration called Illogical Impulse). You are given the commits between the version the user has installed and the latest one, newest first. Write a short Markdown summary: three to six bullet points grouped by what changes for the user — new features, fixes, visual changes, settings or configuration changes. Put anything that changes behaviour or configuration, or that needs action from the user, first. Plain language, no commit hashes, no file or code names unless they matter to the user, no code formatting or backticks, no links, no preamble and no heading. Answer with the bullets only."

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
    // One try per range: a summary that exists, or an attempt that already
    // failed, both leave it alone.
    function maybeAutoSummarize() {
        if (!root.enabled || !root.cacheLoaded) return;
        if (ShellUpdates.commitsBehind < root.minCommits) return;
        if (root.current) return;
        if (root.attemptedFrom === ShellUpdates.activeCommit && root.attemptedTo === ShellUpdates.remoteCommit) return;
        root.summarize(false);
    }

    function summarize(force = false): bool {
        if (root.generating || !root.available) return false;
        if (!force && root.current) return false;

        root.error = "";
        root.pendingFrom = ShellUpdates.activeCommit;
        root.pendingTo = ShellUpdates.remoteCommit;
        root.attemptedFrom = root.pendingFrom;
        root.attemptedTo = root.pendingTo;
        if (!task.start(root.instruction, root.buildPrompt()))
            return false;
        print(`[ShellUpdateSummary] summarising ${ShellUpdates.commits.length} commits with ${root.modelId}`);
        return true;
    }

    function _reject(reason: string) {
        if (root.tearingDown) return;
        root.error = reason;
        print(`[ShellUpdateSummary] failed: ${reason}`);
    }

    function _accept(result: string) {
        if (root.tearingDown) return;
        // Inline code renders in a monospace font that sits badly in a
        // release note; the words read fine without it.
        const answer = String(result ?? "").replace(/`+/g, "").trim();
        if (answer === "") {
            root._reject(Translation.tr("the model sent an empty answer"));
            return;
        }
        if (root.pendingFrom !== ShellUpdates.activeCommit || root.pendingTo !== ShellUpdates.remoteCommit) {
            print("[ShellUpdateSummary] range moved while summarising; answer dropped");
            return;
        }
        print(`[ShellUpdateSummary] done: ${answer.length} chars`);
        root.text = answer;
        root.cachedFrom = root.pendingFrom;
        root.cachedTo = root.pendingTo;
        root.cachedModel = root.modelId;
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

    AiTextTask {
        id: task
        taskName: "update-summary"
        scriptName: "update-summary"
        // Release notes are not worth paying for reasoning.
        thinkingLevel: "off"
        temperature: 0.2

        onFinished: result => root._accept(result)
        onFailed: reason => root._reject(reason)
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
