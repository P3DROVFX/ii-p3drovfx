pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Curated local-model catalogue, a bounded community index and the one owner
 * of an Ollama pull.
 *
 * The catalogue never downloads anything by itself. A model is transferred
 * only after the user explicitly chooses Pull; then the request stays on the
 * loopback daemon and mirrors its streamed progress into the sidebar.
 */
Singleton {
    id: root

    readonly property string endpoint: "http://127.0.0.1:11434/api/pull"
    readonly property string communityEndpoint: "https://huggingface.co/api/models"
    // A page is deliberately small: opening the picker must not enumerate the
    // entire Hub, and each extra page remains an explicit user action.
    readonly property int communityPageSize: 12
    readonly property int communityRequestTimeoutMs: 15000
    readonly property int notificationUpdateIntervalMs: 400
    readonly property int notificationTimeoutMs: 7000

    // These are useful starting points, not a claim that they are installed
    // or that every tag exposes the same capabilities. The daemon resolves
    // the real capabilities after a successful pull.
    readonly property var models: [
        {
            name: "qwen3.5:9b",
            title: "Qwen 3.5 · 9B",
            description: Translation.tr("Balanced local assistant for chat, reasoning and shell tools"),
            category: Translation.tr("Assistant"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "gemma3:4b",
            title: "Gemma 3 · 4B",
            description: Translation.tr("Compact general-purpose model for a lighter local setup"),
            category: Translation.tr("Assistant"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "llama3.2:3b",
            title: "Llama 3.2 · 3B",
            description: Translation.tr("Fast, small model for everyday local chat"),
            category: Translation.tr("Lightweight"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "qwen2.5-coder:7b",
            title: "Qwen 2.5 Coder · 7B",
            description: Translation.tr("Local coding and terminal-oriented conversations"),
            category: Translation.tr("Coding"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "nomic-embed-text",
            title: "Nomic Embed Text",
            description: Translation.tr("Embedding model for local retrieval, not chat"),
            category: Translation.tr("Local retrieval"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "qwen3.5:4b",
            title: "Qwen 3.5 · 4B",
            description: Translation.tr("Smaller Qwen option for a compact local assistant"),
            category: Translation.tr("Lightweight"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "gemma3:12b",
            title: "Gemma 3 · 12B",
            description: Translation.tr("Higher-capacity general assistant for local chat"),
            category: Translation.tr("Assistant"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "llama3.2:1b",
            title: "Llama 3.2 · 1B",
            description: Translation.tr("Minimal local chat model for constrained hardware"),
            category: Translation.tr("Lightweight"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "deepseek-r1:8b",
            title: "DeepSeek R1 · 8B",
            description: Translation.tr("Reasoning-focused local model"),
            category: Translation.tr("Reasoning"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "mistral:7b",
            title: "Mistral · 7B",
            description: Translation.tr("Versatile local model for everyday work"),
            category: Translation.tr("Assistant"),
            provider: Translation.tr("Ollama")
        },
        {
            name: "bge-m3",
            title: "BGE M3",
            description: Translation.tr("Multilingual embeddings for local retrieval"),
            category: Translation.tr("Local retrieval"),
            provider: Translation.tr("Ollama")
        }
    ]

    property list<var> communityModels: []
    property bool communityLoading: false
    property bool communityLoaded: false
    property string communityError: ""
    property string communitySearch: ""
    property string communityNextUrl: ""
    property string pendingCommunitySearch: ""
    property bool hasPendingCommunitySearch: false
    property var activeCommunityRequest: null

    property string pullingModel: ""
    property string pullStatus: ""
    property string pullError: ""
    property real pullProgress: -1
    property string pullState: "idle" // idle | pulling | succeeded | failed | cancelled

    property int downloadNotificationId: 0
    property string downloadNotificationModel: ""
    property string downloadNotificationState: "idle"
    property int downloadNotificationProgress: -1
    property bool downloadNotificationPending: false

    readonly property bool pulling: root.pullingModel.length > 0

    signal pullSucceeded(string modelName)

    function normalizeModelName(modelName): string {
        const normalized = String(modelName ?? "").trim();
        // Ollama names may have a namespace and tag, but are never URLs,
        // whitespace, shell syntax or a path beginning with a slash.
        if (!/^[A-Za-z0-9][A-Za-z0-9._/-]*(?::[A-Za-z0-9][A-Za-z0-9._/-]*)?$/.test(normalized))
            return "";
        const repository = normalized.split(":")[0];
        const unsafeSegment = repository.split("/").some(segment => segment.length === 0 || segment === "." || segment === "..");
        return unsafeSegment ? "" : normalized;
    }

    function communityUrl(searchTerm = ""): string {
        let url = root.communityEndpoint
            + "?filter=gguf"
            + "&sort=downloads"
            + "&direction=-1"
            + "&limit=" + String(root.communityPageSize);
        const normalizedSearch = String(searchTerm ?? "").trim();
        if (normalizedSearch.length > 0)
            url += "&search=" + encodeURIComponent(normalizedSearch);
        return url;
    }

    function isCommunityUrl(url): bool {
        return String(url ?? "").startsWith(root.communityEndpoint + "?");
    }

    function nextCommunityUrl(linkHeader): string {
        const match = /<([^>]+)>;\s*rel="next"/.exec(String(linkHeader ?? ""));
        const nextUrl = match?.[1] ?? "";
        return root.isCommunityUrl(nextUrl) ? nextUrl : "";
    }

    function formatDownloads(value): string {
        const downloads = Number(value ?? 0);
        if (!isFinite(downloads) || downloads <= 0)
            return Translation.tr("popular");
        if (downloads >= 1000000)
            return (downloads / 1000000).toFixed(1).replace(".0", "") + "M";
        if (downloads >= 1000)
            return (downloads / 1000).toFixed(1).replace(".0", "") + "K";
        return String(Math.round(downloads));
    }

    function normalizeCommunityModel(raw): var {
        const repositoryId = String(raw?.id ?? raw?.modelId ?? "").trim();
        const name = root.normalizeModelName("hf.co/" + repositoryId);
        if (repositoryId.length === 0 || name.length === 0)
            return null;
        return {
            name: name,
            title: repositoryId,
            description: Translation.tr("Community GGUF · %1 downloads").arg(root.formatDownloads(raw?.downloads)),
            category: Translation.tr("Community"),
            provider: Translation.tr("Hugging Face")
        };
    }

    function setCommunityModels(source, append: bool) {
        const existing = append ? [...root.communityModels] : [];
        const names = new Set(existing.map(model => model.name));
        for (let i = 0; i < source.length; i++) {
            const model = root.normalizeCommunityModel(source[i]);
            if (!model || names.has(model.name))
                continue;
            names.add(model.name);
            existing.push(model);
        }
        root.communityModels = existing;
    }

    function finishCommunityRequest() {
        communityRequestTimeout.stop();
        root.activeCommunityRequest = null;
        root.communityLoading = false;
        const pending = root.pendingCommunitySearch;
        const hasPending = root.hasPendingCommunitySearch;
        root.pendingCommunitySearch = "";
        root.hasPendingCommunitySearch = false;
        if (hasPending && pending !== root.communitySearch)
            root.loadCommunityModels(pending);
    }

    function requestCommunityPage(url, append: bool, searchTerm: string) {
        if (!root.isCommunityUrl(url) || root.communityLoading)
            return;

        root.communityLoading = true;
        root.communityError = "";
        const xhr = new XMLHttpRequest();
        root.activeCommunityRequest = xhr;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.activeCommunityRequest !== xhr)
                return;

            if (xhr.status !== 200) {
                root.communityError = xhr.status > 0
                    ? Translation.tr("Hugging Face returned HTTP %1.").arg(String(xhr.status))
                    : Translation.tr("Hugging Face could not be reached.");
                root.finishCommunityRequest();
                return;
            }

            try {
                const payload = JSON.parse(xhr.responseText ?? "[]");
                if (!Array.isArray(payload))
                    throw new Error("Expected an array");
                root.setCommunityModels(payload, append);
                root.communityLoaded = true;
                root.communitySearch = searchTerm;
                root.communityNextUrl = root.nextCommunityUrl(xhr.getResponseHeader("Link"));
            } catch (error) {
                root.communityError = Translation.tr("Hugging Face returned an invalid model list.");
                console.warn("[OllamaCatalog] Failed to parse community model list:", error);
            }
            root.finishCommunityRequest();
        };
        xhr.open("GET", url);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.send();
        communityRequestTimeout.restart();
    }

    function loadCommunityModels(searchTerm = "") {
        if (!Ai.onlineAllowed) {
            root.communityError = Translation.tr("Online AI is disabled by the current policy.");
            return;
        }

        const normalizedSearch = String(searchTerm ?? "").trim();
        if (root.communityLoading) {
            root.pendingCommunitySearch = normalizedSearch;
            root.hasPendingCommunitySearch = true;
            return;
        }
        if (root.communityLoaded && root.communitySearch === normalizedSearch)
            return;

        root.communityNextUrl = "";
        root.requestCommunityPage(root.communityUrl(normalizedSearch), false, normalizedSearch);
    }

    function loadMoreCommunityModels() {
        if (root.communityLoading || root.communityNextUrl.length === 0)
            return;
        root.requestCommunityPage(root.communityNextUrl, true, root.communitySearch);
    }

    function pull(modelName): bool {
        if (root.pulling)
            return false;

        const normalized = root.normalizeModelName(modelName);
        if (normalized.length === 0) {
            root.pullState = "failed";
            root.pullError = Translation.tr("Enter a valid Ollama model name, for example qwen3.5:9b.");
            return false;
        }

        root.pullingModel = normalized;
        root.pullStatus = Translation.tr("Preparing download…");
        root.pullError = "";
        root.pullProgress = -1;
        root.pullState = "pulling";
        root.downloadNotificationId = 0;
        root.downloadNotificationModel = normalized;
        root.downloadNotificationState = "pulling";
        root.downloadNotificationProgress = -1;
        root.queueDownloadNotification("pulling", true);
        pullProc.modelName = normalized;
        pullProc.succeeded = false;
        pullProc.cancelled = false;
        pullProc.stderrText = "";
        pullProc.stdinEnabled = true;
        pullProc.running = true;
        // /api/pull is NDJSON. Closing stdin matters: otherwise curl waits
        // for more request data and the daemon never begins the transfer.
        pullProc.write(JSON.stringify({ model: normalized, stream: true }) + "\n");
        pullProc.stdinEnabled = false;
        return true;
    }

    function cancelPull() {
        if (!root.pulling)
            return;
        pullProc.cancelled = true;
        if (pullProc.running)
            pullProc.running = false;
        root.pullingModel = "";
        root.pullStatus = Translation.tr("Download stopped");
        root.pullState = "cancelled";
        root.pullProgress = -1;
        root.queueDownloadNotification("cancelled", true);
    }

    function acceptProgress(event) {
        if (!root.pulling || !event)
            return;

        const reportedError = String(event.error ?? "").trim();
        if (reportedError.length > 0) {
            root.pullError = reportedError;
            return;
        }

        const status = String(event.status ?? "").trim();
        if (status.length > 0)
            root.pullStatus = status;
        const total = Number(event.total ?? 0);
        const completed = Number(event.completed ?? 0);
        if (isFinite(total) && total > 0 && isFinite(completed))
            root.pullProgress = Math.max(0, Math.min(1, completed / total));
        root.queueDownloadNotification("pulling");
        if (status.toLowerCase() === "success") {
            pullProc.succeeded = true;
            root.pullProgress = 1;
        }
    }

    function notificationProgressPercent(): int {
        return root.pullProgress >= 0 ? Math.round(root.pullProgress * 100) : 0;
    }

    function downloadNotificationCopy(state: string, percent: int): var {
        const model = root.downloadNotificationModel;
        if (state === "succeeded") {
            return {
                summary: Translation.tr("Model ready"),
                body: Translation.tr("%1 downloaded and ready to use.").arg(model),
                icon: "emblem-ok",
                urgency: "low"
            };
        }
        if (state === "failed") {
            return {
                summary: Translation.tr("Model download failed"),
                body: root.pullError.length > 0 ? root.pullError : model,
                icon: "dialog-error",
                urgency: "normal"
            };
        }
        if (state === "cancelled") {
            return {
                summary: Translation.tr("Model download stopped"),
                body: model,
                icon: "download",
                urgency: "low"
            };
        }
        return {
            summary: Translation.tr("Downloading %1").arg(model),
            body: root.pullStatus + " · " + String(percent) + "%",
            icon: "folder-download",
            urgency: "low"
        };
    }

    function queueDownloadNotification(state = "pulling", immediate = false) {
        if (root.downloadNotificationModel.length === 0)
            return;
        root.downloadNotificationState = state;
        root.downloadNotificationProgress = root.notificationProgressPercent();
        root.downloadNotificationPending = true;
        if (immediate || state !== "pulling") {
            downloadNotificationTimer.stop();
            root.dispatchDownloadNotification();
        } else if (!downloadNotificationTimer.running && !downloadNotificationProc.running) {
            downloadNotificationTimer.restart();
        }
    }

    function dispatchDownloadNotification() {
        if (!root.downloadNotificationPending || downloadNotificationProc.running)
            return;

        root.downloadNotificationPending = false;
        const percent = root.downloadNotificationProgress;
        const copy = root.downloadNotificationCopy(root.downloadNotificationState, percent);
        const command = [
            "notify-send",
            "--app-name=AI",
            "--icon=" + copy.icon,
            "--urgency=" + copy.urgency,
            "--expire-time=" + String(root.notificationTimeoutMs),
            "--print-id",
            "--hint=int:value:" + String(percent)
        ];
        if (root.downloadNotificationId > 0)
            command.push("--replace-id=" + String(root.downloadNotificationId));
        command.push(copy.summary, copy.body);
        downloadNotificationProc.command = command;
        downloadNotificationProc.running = true;
    }

    Timer {
        id: communityRequestTimeout
        interval: root.communityRequestTimeoutMs
        repeat: false
        onTriggered: {
            const xhr = root.activeCommunityRequest;
            if (!xhr)
                return;
            root.activeCommunityRequest = null;
            root.communityLoading = false;
            root.communityError = Translation.tr("Hugging Face request timed out.");
            xhr.abort();
            const pending = root.pendingCommunitySearch;
            const hasPending = root.hasPendingCommunitySearch;
            root.pendingCommunitySearch = "";
            root.hasPendingCommunitySearch = false;
            if (hasPending && pending !== root.communitySearch)
                root.loadCommunityModels(pending);
        }
    }

    Timer {
        id: downloadNotificationTimer
        interval: root.notificationUpdateIntervalMs
        repeat: false
        onTriggered: root.dispatchDownloadNotification()
    }

    Process {
        id: downloadNotificationProc

        stdout: SplitParser {
            onRead: line => {
                const id = Number(String(line ?? "").trim());
                if (isFinite(id) && id > 0)
                    root.downloadNotificationId = Math.round(id);
            }
        }

        onExited: {
            if (root.downloadNotificationPending)
                root.dispatchDownloadNotification();
        }
    }

    Process {
        id: pullProc

        property string modelName: ""
        property bool succeeded: false
        property bool cancelled: false
        property string stderrText: ""

        // Keep this request argv-only. The selected name is sent as JSON to
        // stdin, so no user string can become shell or curl syntax.
        command: [
            "curl", "--no-buffer", "--silent", "--show-error",
            "--connect-timeout", "5",
            "--request", "POST", root.endpoint,
            "--header", "Content-Type: application/json",
            "--data-binary", "@-"
        ]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                const trimmed = String(line ?? "").trim();
                if (trimmed.length === 0)
                    return;
                try {
                    root.acceptProgress(JSON.parse(trimmed));
                } catch (error) {
                    // A non-JSON response is handled through curl's exit code
                    // and stderr below; never make parser noise a QML error.
                }
            }
        }

        stderr: SplitParser {
            onRead: line => {
                const trimmed = String(line ?? "").trim();
                if (trimmed.length === 0)
                    return;
                pullProc.stderrText = (pullProc.stderrText + " " + trimmed).trim().slice(0, 400);
            }
        }

        onExited: exitCode => {
            if (pullProc.cancelled)
                return;

            const modelName = pullProc.modelName;
            root.pullingModel = "";
            if (pullProc.succeeded) {
                root.pullState = "succeeded";
                root.pullStatus = Translation.tr("Ready to use");
                root.pullProgress = 1;
                root.queueDownloadNotification("succeeded", true);
                root.pullSucceeded(modelName);
                return;
            }

            root.pullState = "failed";
            root.pullProgress = -1;
            if (root.pullError.length === 0) {
                root.pullError = pullProc.stderrText.length > 0
                    ? pullProc.stderrText
                    : exitCode === 0
                        ? Translation.tr("Ollama did not confirm that the model was pulled.")
                        : Translation.tr("Could not reach Ollama. Start its local service and try again.");
            }
            root.queueDownloadNotification("failed", true);
        }
    }
}
