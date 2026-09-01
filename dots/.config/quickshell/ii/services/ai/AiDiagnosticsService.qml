pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import qs.services.ai

/**
 * One page that answers "why didn't the chat respond?".
 *
 * The diagnosis used to be scattered: voice and OCR live in the Advanced
 * settings, keys in their own popover, RAG in its own settings page, and
 * nothing anywhere said whether the Ollama daemon or a search backend was
 * reachable at all. This service is the one owner of the remaining probes
 * (Ollama reachability, tesseract, a live web search, one guarded page
 * fetch) and reads the rest from the singletons that already detect them
 * (`AiVoiceService`, `AiRagService`, the keyring, the policy).
 *
 * Everything is a check with an id, a state of idle | running | ok | warn |
 * fail, and one sentence saying what is missing. Process-backed probes keep
 * their last outcome here; checks that are already reactive elsewhere are
 * derived on demand, so this page can never disagree with the view they
 * belong to. No probe sends conversation content anywhere: the search term
 * and fetched address are fixed literals, and key tests reuse the same
 * one-word request the Keys popover runs through `Ai.testApiKey`.
 */
Singleton {
    id: root

    readonly property var staticChecks: [
        { id: "policy", group: "chat", icon: "policy", title: Translation.tr("AI policy") },
        { id: "model", group: "chat", icon: "smart_toy", title: Translation.tr("Current model") },
        { id: "ollama", group: "local", icon: "deployed_code", title: Translation.tr("Ollama daemon") },
        { id: "ocr", group: "local", icon: "text_snippet", title: Translation.tr("Text recognition (OCR)") },
        { id: "voice", group: "local", icon: "mic", title: Translation.tr("Voice input") },
        { id: "rag", group: "local", icon: "manage_search", title: Translation.tr("Local retrieval (RAG)") },
        { id: "search", group: "web", icon: "search", title: Translation.tr("Web search") },
        { id: "fetch", group: "web", icon: "travel_explore", title: Translation.tr("Read a web page") }
    ]

    readonly property var groupTitles: ({
            "chat": Translation.tr("Conversation"),
            "providers": Translation.tr("Provider keys"),
            "local": Translation.tr("Local engine"),
            "web": Translation.tr("Web access")
        })

    /** One row per key id, not per provider — several providers can share one. */
    readonly property var keyChecks: {
        const seen = ({});
        const result = [];
        const ids = Ai.providerIds ?? [];
        for (let i = 0; i < ids.length; i++) {
            const provider = Ai.providers[ids[i]];
            if (!provider?.requires_key)
                continue;
            const keyId = String(provider.key_id ?? "");
            if (keyId.length === 0 || seen[keyId])
                continue;
            seen[keyId] = true;
            result.push({
                id: "keys:" + keyId,
                keyId: keyId,
                group: "providers",
                icon: provider.materialIcon ?? "",
                customIcon: provider.icon ?? "",
                title: provider.name
            });
        }
        return result;
    }

    // ── Process-backed probe outcomes ──────────────────────────────────────
    /** id -> {state, detail} for ollama / ocr / search / fetch. */
    property var probeResults: ({})
    property real lastRunAt: 0

    function setProbeResult(id, state, detail) {
        const next = Object.assign({}, root.probeResults);
        next[id] = {
            "state": state,
            "detail": detail
        };
        root.probeResults = next;
    }

    // ── Derived checks (reactive elsewhere; never stored stale) ───────────

    function policyResult(): var {
        if (!Ai.enabled)
            return {
                "state": "fail",
                "detail": Translation.tr("AI is switched off by policy. Turn it back on in Settings › Privacy.")
            };
        if (Ai.localOnly)
            return {
                "state": "warn",
                "detail": Translation.tr("Local only — online providers and web access stay off.")
            };
        return {
            "state": "ok",
            "detail": Translation.tr("Full access — local and online models are allowed.")
        };
    }

    function modelResult(): var {
        const model = Ai.currentModelEntry;
        if (!Ai.hasSelectableModel || !model)
            return {
                "state": "fail",
                "detail": Translation.tr("The catalog has no models. Add one under Settings › AI Assistant.")
            };
        const permission = Ai.canSubmit(Ai.currentModelId);
        if (!permission.allowed) {
            switch (permission.reason) {
            case "keyring-loading":
                return {
                    "state": "running",
                    "detail": Translation.tr("Still reading the system keyring…")
                };
            case "missing-key":
                return {
                    "state": "fail",
                    "detail": Translation.tr("%1 needs an API key.").arg(model.title)
                };
            case "remote-model-blocked":
                return {
                    "state": "fail",
                    "detail": Translation.tr("%1 is an online model and the policy is Local only.").arg(model.title)
                };
            case "disabled":
                return root.policyResult();
            default:
                return {
                    "state": "fail",
                    "detail": Translation.tr("The selected model is not available right now.")
                };
            }
        }
        const providerName = Ai.providers[model.providerId]?.name ?? model.providerId;
        return {
            "state": "ok",
            "detail": Translation.tr("%1 · %2 is ready to answer.").arg(String(model.title)).arg(String(providerName))
        };
    }

    function keyResult(keyId): var {
        const entry = Array.from(root.keyChecks).find(check => check.keyId === keyId);
        const name = entry?.title ?? keyId;
        if (!Ai.enabled)
            return {
                "state": "warn",
                "detail": Translation.tr("AI is switched off by policy.")
            };
        if (!KeyringStorage.loaded)
            return {
                "state": "running",
                "detail": Translation.tr("Reading the system keyring…")
            };
        if ((Ai.apiKeys?.[keyId] ?? "").length === 0)
            return {
                "state": "fail",
                "detail": Translation.tr("No %1 key stored. Add one in the API keys view.").arg(String(name))
            };
        if (Ai.keyTestId === keyId && Ai.keyTestState === "running")
            return {
                "state": "running",
                "detail": Translation.tr("Asking the provider for a one-word answer…")
            };
        if (Ai.keyTestId === keyId && Ai.keyTestState === "ok")
            return {
                "state": "ok",
                "detail": Ai.keyTestMessage
            };
        if (Ai.keyTestId === keyId && Ai.keyTestState === "failed")
            return {
                "state": "fail",
                "detail": Ai.keyTestMessage
            };
        return {
            "state": "idle",
            "detail": Translation.tr("A key is stored. Run the test to confirm the provider accepts it.")
        };
    }

    function voiceResult(): var {
        const voice = Ai.voiceService;
        if (!(Config.options?.ai?.voice?.enabled ?? true))
            return {
                "state": "warn",
                "detail": Translation.tr("Voice input is turned off in settings.")
            };
        if (!voice.detectionSettled) {
            voice.ensureDetected();
            return {
                "state": "running",
                "detail": Translation.tr("Checking for a recorder and a transcription engine…")
            };
        }
        if (!voice.recorderAvailable && !voice.backendAvailable)
            return {
                "state": "fail",
                "detail": Translation.tr("Neither pw-record nor a whisper.cpp CLI was found.")
            };
        if (!voice.recorderAvailable)
            return {
                "state": "fail",
                "detail": Translation.tr("pw-record is missing, so there is nothing to transcribe.")
            };
        if (!voice.backendAvailable)
            return {
                "state": "fail",
                "detail": Translation.tr("No whisper.cpp CLI found — recordings cannot become text.")
            };
        return {
            "state": "ok",
            "detail": Translation.tr("%1 and %2 are ready.").arg(String("pw-record")).arg(String(voice.backendName))
        };
    }

    function ragResult(): var {
        const rag = AiRagService;
        if (!rag.enabled)
            return {
                "state": "warn",
                "detail": Translation.tr("Turned off in settings — the chat searches nothing locally.")
            };
        const embedding = String(rag.embeddingModel ?? "");
        if (embedding.length === 0)
            return {
                "state": "fail",
                "detail": Translation.tr("No embedding model chosen for retrieval.")
            };
        if (!rag.modelsChecked) {
            rag.refreshInstalledModels();
            return {
                "state": "running",
                "detail": Translation.tr("Checking which embedding models are pulled…")
            };
        }
        if (Array.from(rag.installedModels).indexOf(embedding) < 0)
            return {
                "state": "fail",
                "detail": Translation.tr("%1 is not pulled yet — pull it from the Ollama catalog.").arg(embedding)
            };
        const collections = Array.from(rag.collections ?? []);
        if (collections.length === 0)
            return {
                "state": "warn",
                "detail": Translation.tr("The embedding model is ready, but no collection is configured.")
            };
        let indexedChunks = 0;
        let indexedCount = 0;
        const stats = rag.indexStats ?? {};
        for (let i = 0; i < collections.length; i++) {
            const stat = stats[String(collections[i].id ?? "")];
            const chunks = Number(stat?.chunkCount ?? 0);
            if (chunks > 0) {
                indexedCount++;
                indexedChunks += chunks;
            }
        }
        if (indexedCount === 0)
            return {
                "state": "warn",
                "detail": Translation.tr("%1 collections configured, none indexed yet.").arg(String(collections.length))
            };
        return {
            "state": "ok",
            "detail": Translation.tr("%1 of %2 collections indexed · %3 chunks.").arg(String(indexedCount)).arg(String(collections.length)).arg(String(indexedChunks))
        };
    }

    /** Uniform accessor for the page: every check reads as {state, detail}. */
    function resultFor(id): var {
        const text = String(id ?? "");
        if (text === "policy")
            return root.policyResult();
        if (text === "model")
            return root.modelResult();
        if (text === "voice")
            return root.voiceResult();
        if (text === "rag")
            return root.ragResult();
        if (text.startsWith("keys:"))
            return root.keyResult(text.slice(5));
        return root.probeResults[text] ?? {
            "state": "idle",
            "detail": Translation.tr("Not tested yet.")
        };
    }

    function runningFor(id): bool {
        const text = String(id ?? "");
        if (text === "ollama")
            return ollamaProbeProc.running;
        if (text === "ocr")
            return ocrProbeProc.running;
        if (text === "search")
            return searchProbeProc.running;
        if (text === "fetch")
            return fetchProbeProc.running;
        if (text.startsWith("keys:"))
            return Ai.keyTestId === text.slice(5) && Ai.keyTestState === "running";
        return root.resultFor(text).state === "running";
    }

    readonly property bool anyRunning: {
        const checks = root.staticChecks.concat(root.keyChecks);
        for (let i = 0; i < checks.length; i++)
            if (root.runningFor(checks[i].id))
                return true;
        return false;
    }

    /** {failing, warning, ok, total} over everything that is not idle/running. */
    readonly property var summary: {
        const counts = {
            "failing": 0,
            "warning": 0,
            "ok": 0,
            "total": 0
        };
        const checks = root.staticChecks.concat(root.keyChecks);
        for (let i = 0; i < checks.length; i++) {
            const state = root.resultFor(checks[i].id).state;
            if (state === "fail") {
                counts.failing++;
                counts.total++;
            } else if (state === "warn") {
                counts.warning++;
                counts.total++;
            } else if (state === "ok") {
                counts.ok++;
                counts.total++;
            }
        }
        return counts;
    }

    // ── Probes ─────────────────────────────────────────────────────────────

    /**
     * Cheap, always-safe refreshes: instant re-derivation plus the boot-time
     * detections that may simply not have run yet. Called when the page opens.
     */
    function open() {
        root.refreshInstalledDetections();
        root.retest("ollama");
    }

    function refreshInstalledDetections() {
        Ai.voiceService.ensureDetected();
        AiRagService.refreshInstalledModels();
        if (AiRagService.hasCollections)
            AiRagService.refreshStatus();
    }

    function retest(id): bool {
        const text = String(id ?? "");
        if (text === "ollama")
            return root.probeOllama();
        if (text === "ocr")
            return root.probeOcr();
        if (text === "search")
            return root.probeSearch();
        if (text === "fetch")
            return root.probeFetch();
        if (text === "voice") {
            Ai.voiceService.redetect();
            return true;
        }
        if (text === "rag") {
            AiRagService.modelsChecked = false;
            root.ragResult();
            root.refreshInstalledDetections();
            return true;
        }
        if (text.startsWith("keys:")) {
            root.testKeyNow(text.slice(5));
            return true;
        }
        // policy and model derive live; a retest only confirms.
        return true;
    }

    /** Runs every check: probes immediately, key tests queued one by one. */
    function runAll() {
        const order = ["ollama", "ocr", "voice", "rag", "search", "fetch"];
        for (let i = 0; i < order.length; i++)
            root.retest(order[i]);
        root.keyQueue = Array.from(root.keyChecks).map(check => check.keyId);
        Qt.callLater(root.drainKeyQueue);
    }

    property var keyQueue: []

    function testKeyNow(keyId) {
        root.keyQueue = [];
        Ai.testApiKey(String(keyId ?? ""));
    }

    function drainKeyQueue() {
        if (root.keyQueue.length === 0)
            return;
        if (Ai.keyTestState === "running")
            return;
        const next = root.keyQueue[0];
        root.keyQueue = root.keyQueue.slice(1);
        Ai.testApiKey(next);
        // A short-circuited test (no model for the key, no key stored) never
        // reaches "running"; schedule another pass so the queue still drains.
        Qt.callLater(root.drainKeyQueue);
    }

    Connections {
        target: Ai

        function onKeyTestStateChanged() {
            if (root.keyQueue.length > 0)
                Qt.callLater(root.drainKeyQueue);
        }
    }

    function markRun() {
        root.lastRunAt = Date.now();
    }

    // One curl against the daemon's own tag list. `-f` turns an HTTP error
    // into an exit code, so "reachable" means "answered like Ollama".
    function probeOllama(): bool {
        if (ollamaProbeProc.running)
            return false;
        ollamaProbeProc.startedAt = Date.now();
        ollamaProbeProc.running = true;
        return true;
    }

    property Process ollamaProbeProc: Process {
        id: ollamaProbeProc

        property real startedAt: 0
        property string payload: ""

        command: ["curl", "-sf", "--max-time", "4", "http://127.0.0.1:11434/api/tags"]

        stdout: StdioCollector {
            onStreamFinished: ollamaProbeProc.payload = String(text ?? "").trim()
        }

        onExited: (exitCode, exitStatus) => {
            root.markRun();
            if (exitCode !== 0) {
                root.setProbeResult("ollama", "warn", Translation.tr("Not reachable — local models, vision tagging and retrieval embeddings all need this daemon."));
                return;
            }
            let count = -1;
            try {
                count = Array.from(JSON.parse(ollamaProbeProc.payload)?.models ?? []).length;
            } catch (error) {
                count = -1;
            }
            const seconds = ((Date.now() - ollamaProbeProc.startedAt) / 1000).toFixed(1);
            if (count < 0) {
                root.setProbeResult("ollama", "warn", Translation.tr("Answered in %1 s, but not with a model list.").arg(seconds));
                return;
            }
            if (count === 0) {
                root.setProbeResult("ollama", "warn", Translation.tr("Reachable in %1 s, but no model is installed yet.").arg(seconds));
                return;
            }
            root.setProbeResult("ollama", "ok", Translation.tr("Reachable in %1 s · %2 models installed.").arg(seconds).arg(String(count)));
        }
    }

    function probeOcr(): bool {
        if (ocrProbeProc.running)
            return false;
        ocrProbeProc.running = true;
        return true;
    }

    property Process ocrProbeProc: Process {
        id: ocrProbeProc

        command: ["bash", "-c", "command -v tesseract >/dev/null 2>&1 && echo yes || echo no"]

        stdout: StdioCollector {
            onStreamFinished: ocrProbeProc.found = String(text ?? "").trim() === "yes"
        }

        property bool found: false

        onExited: exitCode => {
            root.markRun();
            if (exitCode !== 0) {
                root.setProbeResult("ocr", "warn", Translation.tr("The check itself failed to run."));
                return;
            }
            if (!ocrProbeProc.found) {
                root.setProbeResult("ocr", "warn", Translation.tr("tesseract is not installed — images cannot be read as text. Install guide lives in Settings › AI."));
                return;
            }
            if (!(Config.options?.ai?.vision?.ocrEnabled ?? true)) {
                root.setProbeResult("ocr", "warn", Translation.tr("tesseract is installed, but OCR is switched off in settings."));
                return;
            }
            root.setProbeResult("ocr", "ok", Translation.tr("tesseract is installed and OCR is on."));
        }
    }

    // Fixed literals below: a diagnostic must not turn a probe into a way to
    // send arbitrary text somewhere. The wrapper caps the helper, whose own
    // fallback chain can otherwise stack three 20-second timeouts.
    function probeSearch(): bool {
        if (searchProbeProc.running)
            return false;
        if (!Ai.onlineAllowed) {
            root.setProbeResult("search", "warn", Translation.tr("Web access stays off under the Local-only policy."));
            return true;
        }
        searchProbeProc.startedAt = Date.now();
        searchProbeProc.running = true;
        return true;
    }

    property Process searchProbeProc: Process {
        id: searchProbeProc

        property real startedAt: 0
        property string payload: ""

        // This machine's `timeout` is the minimal Rust build: duration only,
        // no --kill-after. 30 s still caps the helper's own fallback chain.
        command: ["timeout", "30", "python3", Directories.aiWebScriptPath, "search", "quickshell", "3"]

        stdout: StdioCollector {
            onStreamFinished: searchProbeProc.payload = String(text ?? "").trim()
        }

        onExited: (exitCode, exitStatus) => {
            root.markRun();
            const elapsed = Math.round(Date.now() - searchProbeProc.startedAt);
            // 124 = timeout's own code, 137/143 = the child killed by signal.
            if (exitCode === 124 || exitCode === 137 || exitCode === 143) {
                root.setProbeResult("search", "fail", Translation.tr("No backend answered within 30 s. Run a local SearXNG or set BRAVE_SEARCH_KEY."));
                return;
            }
            let parsed = null;
            try {
                parsed = JSON.parse(searchProbeProc.payload);
            } catch (error) {
                parsed = null;
            }
            if (!parsed) {
                root.setProbeResult("search", "fail", Translation.tr("The web helper returned nothing readable."));
                return;
            }
            if (parsed.error) {
                root.setProbeResult("search", "fail", String(parsed.error).slice(0, 220));
                return;
            }
            const results = Array.from(parsed.results ?? []).length;
            root.setProbeResult("search", "ok", Translation.tr("%1 answered in %2 ms · %3 results.").arg(String(parsed.engine ?? "web")).arg(String(elapsed)).arg(String(results)));
        }
    }

    // The agent's browser, exercised end to end: the same guarded fetch the
    // model gets, against a fixed address that should always resolve.
    function probeFetch(): bool {
        if (fetchProbeProc.running)
            return false;
        if (!Ai.onlineAllowed) {
            root.setProbeResult("fetch", "warn", Translation.tr("Page reading stays off under the Local-only policy."));
            return true;
        }
        fetchProbeProc.startedAt = Date.now();
        fetchProbeProc.running = true;
        return true;
    }

    property Process fetchProbeProc: Process {
        id: fetchProbeProc

        property real startedAt: 0
        property string payload: ""

        command: ["timeout", "30", "python3", Directories.aiWebScriptPath, "fetch", "https://example.com"]

        stdout: StdioCollector {
            onStreamFinished: fetchProbeProc.payload = String(text ?? "").trim()
        }

        onExited: (exitCode, exitStatus) => {
            root.markRun();
            const elapsed = Math.round(Date.now() - fetchProbeProc.startedAt);
            if (exitCode === 124 || exitCode === 137 || exitCode === 143) {
                root.setProbeResult("fetch", "fail", Translation.tr("example.com did not answer within 30 s — the network or its filtering is in the way."));
                return;
            }
            let parsed = null;
            try {
                parsed = JSON.parse(fetchProbeProc.payload);
            } catch (error) {
                parsed = null;
            }
            if (!parsed) {
                root.setProbeResult("fetch", "fail", Translation.tr("The web helper returned nothing readable."));
                return;
            }
            if (parsed.error) {
                root.setProbeResult("fetch", "fail", String(parsed.error).slice(0, 220));
                return;
            }
            // The helper's field is `text`, not `content`; an empty page is
            // still a page the agent read, so the count is honest either way.
            const chars = String(parsed.text ?? "").length;
            root.setProbeResult("fetch", "ok", Translation.tr("Read “%1” (%2 characters) in %3 ms.").arg(String(parsed.title ?? "the page")).arg(String(chars)).arg(String(elapsed)));
        }
    }
}
