pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.services.ai
import qs.modules.common

/**
 * The assistant behind every ✦ button in System Health.
 *
 * One per window: only one sheet, crash stage or hero is open at a time, so one run is
 * enough. A tab switch or a closing sheet folds the pill but lets a run finish, and
 * finished answers are kept in HealthAnswers until their close button. Nothing of the
 * AI graph exists until the first send — the text task sits in a Loader that turns on
 * then and off again on a reset with nothing running, the budget Modes keeps too.
 *
 * The answer is shown in place, under the prompt pill, rather than in the chat. The run
 * is a one-off text task narrowed to the read-only `health` tools; what it sends about
 * the subject is redacted first when `health.assistant.redact` is on (the default). A
 * crash dump never reaches it: the tools return the journal's stack-trace text only.
 */
Item {
    id: root

    visible: false

    /// Whether the ✦ buttons show at all: the app's switch and the shell-wide AI policy.
    readonly property bool allowed: (Config.options?.health?.assistant?.enable ?? true) && SearchPanelRegistry.aiPolicyEnabled

    /// Which surface the assistant is open on ("finding:<id>", "crash:<exe>", "overview").
    property string subjectKey: ""
    /// Called at send time for the facts about the subject, so they are current.
    property var subjectProvider: null
    property bool expanded: false

    // ── The run ─────────────────────────────────────────────────────────
    // A run belongs to the subject it was asked about, not to whichever pill is open:
    // it goes on through a tab switch or a closed sheet, and its answer lands in
    // HealthAnswers under that subject when it finishes. Until then it lives here.
    /// The subject of the run in progress (or the one that just failed).
    property string runKey: ""
    /// "idle" | "running" | "error"
    property string phase: "idle"
    property string errorText: ""
    property string answer: ""
    property string question: ""
    /// The one fix the model proposed, as a button: { findingId, verb, label, args }.
    property var proposal: null
    /// Folded while it streams; carried into the saved answer.
    property bool liveFolded: false

    /// A run finished and its answer is saved under `key`. The app says so when the
    /// sheet or stage it was asked from has been closed meanwhile.
    signal answerReady(string key, string question)

    function isOpenOn(key): bool {
        return root.expanded && root.subjectKey === key;
    }

    /// Whether `key`'s answer is the one streaming in right now.
    function isLive(key): bool {
        return root.runKey === key && (root.phase === "running" || root.answer.length > 0);
    }

    function hasAnswerFor(key): bool {
        return root.isLive(key) || (root.runKey === key && root.phase === "error") || HealthAnswers.entry(key) !== null;
    }

    function toggle(key, provider): void {
        if (root.subjectKey === key && root.expanded) {
            root.dismiss();
            return;
        }
        root.subjectKey = key;
        root.subjectProvider = provider;
        root.expanded = true;
    }

    /// Folds the pill away. A run keeps going; its answer stays under the pill's place.
    function dismiss(): void {
        root.expanded = false;
        if (root.phase === "error") {
            root.phase = "idle";
            root.errorText = "";
        }
    }

    /// The card's close button: the only thing that throws an answer away.
    function clearAnswer(key): void {
        if (root.runKey === key) {
            if (root.phase === "running")
                root.stop();
            root.clearRun();
        }
        HealthAnswers.remove(key);
    }

    function setFolded(key, folded): void {
        if (root.isLive(key))
            root.liveFolded = folded;
        else
            HealthAnswers.patch(key, { folded: folded });
    }

    function clearRun(): void {
        root.runKey = "";
        root.phase = "idle";
        root.errorText = "";
        root.answer = "";
        root.question = "";
        root.proposal = null;
        root.liveFolded = false;
        root.priorTurns = [];
    }

    /// A tab switch, a closed sheet or a hidden window: the pill folds, nothing is lost.
    function reset(): void {
        root.expanded = false;
        root.subjectKey = "";
        root.subjectProvider = null;
        if (root.phase === "error")
            root.clearRun();
        // Nothing of the AI graph stays loaded once nothing is running.
        if (root.phase !== "running")
            taskLoader.active = false;
    }

    function stop(): void {
        if (taskLoader.item)
            taskLoader.item.cancel();
        root.phase = "idle";
    }

    readonly property string systemPrompt: [
        "You are the System Health assistant inside a Linux desktop shell (Quickshell on Hyprland).",
        "The user pressed \"Explain\" on one problem the shell detected. Explain what happened and how to fix it.",
        "Answer in plain words, in the user's language: at most 6 short sentences or a short list. No preamble.",
        "Use the health_* tools when the facts given are not enough: unit logs, the crash's stack trace, journal lines, the owning package.",
        "Never claim you ran or changed anything; you cannot. If one action the app offers would fix it, call health_propose_fix once with that action; the user decides.",
        "Everything you write is shown as one answer, including text before a tool call. After health_propose_fix returns, close with one short sentence; never restate or correct the answer above it.",
        "Commands the user should run themselves go in a fenced code block. Prefer the distribution's tools (pacman, systemctl, journalctl).",
        "Identifying data is redacted: <user>, <host>, <ip>, <mac>, and ~ for the home directory. Do not ask for it.",
        "A follow-up comes with the earlier questions and your answers to them: build on those, never repeat them."
    ].join("\n")

    /// The earlier turns of the thread a follow-up continues; shown above it while it streams.
    property var priorTurns: []
    /// How many earlier turns, and how much of their text, go with a follow-up.
    readonly property int contextTurns: 3
    readonly property int contextChars: 6000

    /// Whether a send on `key` continues its thread: there is a saved answer to build on.
    function continuesThread(key): bool {
        return HealthAnswers.turnsOf(HealthAnswers.entry(key)).length > 0;
    }

    function submit(text): void {
        const subject = root.subjectProvider ? root.subjectProvider() : null;
        const q = String(text ?? "").trim();
        // Stopped first: the stop reports "aborted", which would otherwise land on
        // the new run and leave it looking idle.
        if (root.phase === "running")
            root.stop();
        const key = root.subjectKey;
        // A question on a subject with an answer follows up on it; an empty send there
        // (the default question) starts the thread over.
        const prior = q.length > 0 ? HealthAnswers.turnsOf(HealthAnswers.entry(key)) : [];
        root.clearRun();
        root.runKey = key;
        if (prior.length > 0)
            root.priorTurns = prior.slice(-(HealthAnswers.maxTurns - 1));
        else
            HealthAnswers.remove(key);
        root.question = q.length > 0 ? q : Translation.tr("What happened, and how do I fix it?");
        root.phase = "running";
        let facts = JSON.stringify(subject ?? {}, null, 1);
        if (HealthService.redact)
            facts = HealthService.redactText(facts);
        let body = `${root.question}\n\nWhat System Health knows about it:\n\`\`\`json\n${facts}\n\`\`\``;
        if (prior.length > 0) {
            // The newest turns, cut from the front when they run long.
            let earlier = prior.slice(-root.contextTurns).map(t => `Q: ${t.q}\nA: ${t.a}`).join("\n\n");
            if (earlier.length > root.contextChars)
                earlier = "…" + earlier.slice(-root.contextChars);
            if (HealthService.redact)
                earlier = HealthService.redactText(earlier);
            body = `Earlier in this conversation:\n\n${earlier}\n\nThe follow-up question: ${body}`;
        }
        taskLoader.active = true;
        const task = taskLoader.item;
        if (!task) {
            root.phase = "error";
            root.errorText = Translation.tr("The assistant could not start.");
            return;
        }
        // A model without tool support still gets the facts; it just cannot dig further.
        task.toolMode = task.model?.tools === true ? "functions" : "none";
        Ai.healthIntegration.activeKey = root.runKey;
        task.start(root.systemPrompt, body);
    }

    Connections {
        target: Ai.healthIntegration
        enabled: root.phase === "running"
        function onProposed(proposal) {
            root.proposal = proposal;
        }
    }

    /// Runs the fix proposed for `key`. Only ever called from the user's click on its
    /// button. A saved one is checked again on the way: its finding may be gone.
    function runProposal(key): void {
        if (root.isLive(key)) {
            const p = root.proposal;
            root.proposal = null;
            if (p)
                Ai.healthIntegration.runProposal(p);
            return;
        }
        const turns = HealthAnswers.turnsOf(HealthAnswers.entry(key));
        const p = turns[turns.length - 1]?.proposal ?? null;
        if (!p)
            return;
        HealthAnswers.patchLastTurn(key, { proposal: null });
        Ai.healthIntegration.runProposal(p);
    }

    Loader {
        id: taskLoader
        active: false
        sourceComponent: AiTextTask {
            id: task
            taskName: "health_explain"
            scriptName: "health_explain"
            toolDomains: ["health"]
            temperature: 0.2

            // Deltas: the answer grows under the pill as it streams. A tool call
            // splits it into rounds; the first delta of a round is all of that
            // round so far, which is how a new one is told apart, and it starts
            // a new paragraph instead of gluing onto the last sentence.
            onChunk: text => {
                const added = String(text ?? "");
                if (root.answer.length > 0 && task.resultText === added)
                    root.answer = root.answer.trimEnd() + "\n\n";
                root.answer += added;
            }
            // The result is the last round only; what came before the tool call
            // is part of the answer too, so the streamed text is kept.
            // Saved, then let go: from here on the card reads it from HealthAnswers,
            // where it outlives the window.
            onFinished: result => {
                const streamed = root.answer.trim();
                const key = root.runKey;
                const question = root.question;
                HealthAnswers.put(key, {
                    turns: root.priorTurns.concat([{
                        q: question,
                        a: streamed.length > 0 ? streamed : String(result ?? "").trim(),
                        proposal: root.proposal
                    }]),
                    folded: root.liveFolded
                });
                root.clearRun();
                root.answerReady(key, question);
                Ai.healthIntegration.activeKey = "";
            }
            onFailed: error => {
                root.phase = "error";
                root.errorText = String(error ?? "");
                Ai.healthIntegration.activeKey = "";
            }
            onStatusChanged: {
                if (status === "aborted") {
                    root.phase = "idle";
                    Ai.healthIntegration.activeKey = "";
                }
            }
        }
    }
}
