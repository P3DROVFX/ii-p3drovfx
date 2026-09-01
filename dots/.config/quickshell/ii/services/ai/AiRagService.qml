pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Opt-in local retrieval: folders the user named explicitly through
 * Settings, chunked and embedded with Ollama, searched later by the
 * assistant. This is the one place `ai_rag.py` runs from — the Settings
 * page (add/reindex/delete a collection, browse index stats) and the AI
 * tool adapter (`AiRagIntegration.qml`) both call into it, so there is one
 * index/status/delete process in flight at a time and one source of truth
 * for what is indexed.
 *
 * Nothing here reaches a folder the user did not name. `index` is the only
 * verb that leaves `indexDir`, and only under the collection's own `path` —
 * see `ai_rag.py` for the same home-directory and sensitive-path guards
 * `files_search` already trusts.
 */
Singleton {
    id: root

    // ── Config passthrough ─────────────────────────────────────────────────
    readonly property bool enabled: Config.options?.ai?.rag?.enabled ?? false
    readonly property string embeddingModel: Config.options?.ai?.rag?.embeddingModel ?? ""
    readonly property var collections: Config.options?.ai?.rag?.collections ?? []
    readonly property bool hasCollections: root.collections.length > 0
    /** Whether a search can actually be attempted right now. */
    readonly property bool ready: root.enabled && root.embeddingModel.length > 0 && root.hasCollections

    readonly property string indexDir: Directories.aiRagIndexDir
    readonly property string ollamaUrl: "http://127.0.0.1:11434"

    function collectionById(id: string): var {
        const wanted = String(id ?? "");
        return root.collections.find(entry => String(entry?.id ?? "") === wanted) ?? null;
    }

    function newCollectionId(): string {
        return `rag-${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`;
    }

    /** Adds a folder as a new collection. Returns its id, or "" if the path is empty. */
    function addCollection(name: string, path: string): string {
        const trimmedPath = String(path ?? "").trim();
        if (trimmedPath.length === 0)
            return "";
        const trimmedName = String(name ?? "").trim();
        const entry = {
            id: root.newCollectionId(),
            name: trimmedName.length > 0 ? trimmedName : (trimmedPath.split("/").filter(part => part.length > 0).pop() ?? trimmedPath),
            path: trimmedPath
        };
        Config.options.ai.rag.collections = [...root.collections, entry];
        return entry.id;
    }

    function renameCollection(id: string, name: string) {
        const trimmed = String(name ?? "").trim();
        if (trimmed.length === 0)
            return;
        Config.options.ai.rag.collections = root.collections.map(entry => String(entry?.id ?? "") === String(id) ? Object.assign({}, entry, { name: trimmed }) : entry);
    }

    /** Drops the collection and its index file. */
    function removeCollection(id: string) {
        const target = root.collectionById(id);
        if (!target)
            return;
        Config.options.ai.rag.collections = root.collections.filter(entry => String(entry?.id ?? "") !== String(id));
        root.deleteIndex(id);
        const stats = Object.assign({}, root.indexStats);
        delete stats[id];
        root.indexStats = stats;
    }

    function setEmbeddingModel(modelName: string) {
        Config.options.ai.rag.embeddingModel = String(modelName ?? "").trim();
    }

    // ── Embedding model detection ───────────────────────────────────────────
    // Ollama's /api/tags has no "this is an embedding model" flag, so
    // detection is a name heuristic over models already installed — never a
    // download triggered on the user's behalf.
    readonly property var embeddingModelHints: ["minilm", "nomic-embed", "mxbai-embed", "bge-", "gte-", "e5-", "embed"]
    property var installedModels: []
    readonly property var detectedEmbeddingModels: root.installedModels.filter(name => {
            const lower = String(name ?? "").toLowerCase();
            return root.embeddingModelHints.some(hint => lower.includes(hint));
        })
    property bool modelsChecked: false

    function refreshInstalledModels() {
        if (modelsProc.running)
            return;
        modelsProc.running = true;
    }

    Process {
        id: modelsProc
        command: ["curl", "-s", "--max-time", "5", `${root.ollamaUrl}/api/tags`]
        stdout: StdioCollector {
            id: modelsCollector
            onStreamFinished: {
                root.modelsChecked = true;
                try {
                    const data = JSON.parse(modelsCollector.text);
                    root.installedModels = Array.from(data?.models ?? []).map(entry => String(entry?.name ?? entry?.model ?? "")).filter(name => name.length > 0);
                } catch (e) {
                    root.installedModels = [];
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.modelsChecked = true;
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.indexDir]);
        root.refreshInstalledModels();
        if (root.hasCollections)
            root.refreshStatus();
    }

    // ── Index stats ──────────────────────────────────────────────────────
    /** collectionId -> {fileCount, chunkCount, sizeBytes, updatedAt, path, embeddingModel}. */
    property var indexStats: ({})
    property bool statusLoading: false

    function refreshStatus() {
        if (statusProc.running)
            return;
        if (!root.hasCollections) {
            root.indexStats = ({});
            return;
        }
        root.statusLoading = true;
        statusProc.command = ["python3", Directories.aiRagScriptPath, "status"];
        statusProc.stdinEnabled = true;
        statusProc.running = true;
        // ai_rag.py reads stdin to EOF, not to a newline; the pipe must be
        // closed after the write or the helper blocks forever waiting for
        // more input that will never come.
        statusProc.write(JSON.stringify({ indexDir: root.indexDir }) + "\n");
        statusProc.stdinEnabled = false;
    }

    Process {
        id: statusProc
        stdinEnabled: true
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: {
                root.statusLoading = false;
                let parsed = null;
                try {
                    parsed = JSON.parse(statusCollector.text);
                } catch (e) {
                    return;
                }
                if (!parsed?.ok)
                    return;
                const next = ({});
                for (const entry of Array.from(parsed.collections ?? [])) {
                    next[String(entry.collectionId ?? "")] = entry;
                }
                root.indexStats = next;
            }
        }
        onExited: exitCode => {
            root.statusLoading = false;
        }
    }

    // ── Indexing ─────────────────────────────────────────────────────────
    // Streamed rather than one final blob: embedding a few thousand chunks
    // takes real time, and Settings shows that as it happens rather than a
    // frozen button.
    property string indexingCollectionId: ""
    property var indexingProgress: ({})
    property string indexingError: ""
    readonly property bool indexing: root.indexingCollectionId.length > 0

    function reindex(id: string) {
        if (root.indexing)
            return;
        const collection = root.collectionById(id);
        if (!collection || root.embeddingModel.length === 0)
            return;
        root.indexingCollectionId = String(id);
        root.indexingProgress = ({});
        root.indexingError = "";
        indexProc.command = ["python3", Directories.aiRagScriptPath, "index"];
        indexProc.stdinEnabled = true;
        indexProc.running = true;
        indexProc.write(JSON.stringify({
            collectionId: collection.id,
            indexDir: root.indexDir,
            path: collection.path,
            embeddingModel: root.embeddingModel,
            ollamaUrl: root.ollamaUrl
        }) + "\n");
        indexProc.stdinEnabled = false;
    }

    /** Kills an index run in progress. The partial result is not written — only a completed pass replaces the index file. */
    function cancelIndexing() {
        if (!root.indexing)
            return;
        if (indexProc.running)
            indexProc.running = false;
        root.indexingError = Translation.tr("Stopped");
        root.indexingCollectionId = "";
    }

    Process {
        id: indexProc
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                const trimmed = String(line ?? "").trim();
                if (trimmed.length === 0)
                    return;
                let event = null;
                try {
                    event = JSON.parse(trimmed);
                } catch (e) {
                    return;
                }
                if (event.event === "progress") {
                    root.indexingProgress = event;
                    return;
                }
                if (event.event === "fatal") {
                    root.indexingError = String(event.error ?? Translation.tr("Indexing failed"));
                    root.indexingCollectionId = "";
                    return;
                }
                if (event.event === "done") {
                    root.indexingCollectionId = "";
                    root.indexingProgress = ({});
                    root.refreshStatus();
                }
            }
        }
        onExited: exitCode => {
            // A crash mid-stream (no "done"/"fatal" line reached) must not
            // leave the UI believing an index is still running forever.
            if (root.indexingCollectionId.length > 0 && exitCode !== 0) {
                root.indexingError = Translation.tr("Indexing stopped unexpectedly (exit code %1).").arg(exitCode);
                root.indexingCollectionId = "";
            }
        }
    }

    // ── Delete ───────────────────────────────────────────────────────────
    function deleteIndex(id: string) {
        if (deleteProc.running)
            return;
        deleteProc.command = ["python3", Directories.aiRagScriptPath, "delete"];
        deleteProc.stdinEnabled = true;
        deleteProc.running = true;
        deleteProc.write(JSON.stringify({ indexDir: root.indexDir, collectionId: String(id) }) + "\n");
        deleteProc.stdinEnabled = false;
    }

    Process {
        id: deleteProc
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: root.refreshStatus()
        }
    }
}
