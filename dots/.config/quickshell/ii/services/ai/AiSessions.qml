pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The store behind the chat list: one file per conversation, an index that
 * lists them, and every operation that touches the disk.
 *
 * Nothing here knows about messages, models or the request pipeline — it is
 * handed a finished session object and gives one back. `Ai` owns the
 * conversation and drives this; keeping the dependency one-way is what stops
 * the two from having to be loaded in a particular order.
 *
 * All file work goes through `ai_sessions.py`, which owns the index and writes
 * session files atomically. That is also why saving no longer blocks: the old
 * `blockLoading: true` save file was there to avoid a race this design does not
 * have.
 */
Scope {
    id: root

    /** Where sessions live, and where the pre-session chats were. */
    property string dir: ""
    property string legacyDir: ""
    property string scriptPath: ""
    property string exportDir: ""

    /** Index entries: {id, title, createdAt, updatedAt, pinned, modelId, messageCount, preview}. */
    property var index: []
    property string currentId: ""
    property bool loading: false
    property bool loaded: false
    property string lastError: ""

    /** Ids matching the running search, or null when nothing is being searched. */
    property var matchedIds: null
    property string query: ""

    /** The chat just deleted, kept until the undo offer goes away. */
    property var deletedEntry: null
    /** Trashed sessions are permanently removed after this configured window. */
    readonly property int retentionDays: Math.max(1, Math.min(3650, Number(Config.options.ai.sessions.retentionDays) || 30))

    readonly property var currentEntry: root.entryFor(root.currentId)

    /** A save is due. `Ai` answers by calling `commit()` with the session. */
    signal saveRequested
    /** A session came back from disk and should replace the conversation. */
    signal sessionOpened(var session)
    /** A queued save reached the helper and was made durable. */
    signal saveSucceeded(string operationId, string sessionId)
    /** A queued save could not be made durable. */
    signal saveFailed(string operationId, string sessionId, string reason)
    /** A background load completed without changing the visible session. */
    signal loadSucceeded(string operationId, string sessionId, var session)
    signal loadFailed(string operationId, string sessionId, string reason)
    signal openFailed(string sessionId, string reason)
    /** Atomic submission primitives used by the run coordinator. */
    signal stageSucceeded(string operationId, string sessionId)
    signal stageFailed(string operationId, string sessionId, string reason)
    signal commitSubmissionSucceeded(string operationId, string sessionId)
    signal commitSubmissionFailed(string operationId, string sessionId, string reason)
    signal abortSubmissionSucceeded(string operationId, string sessionId)
    signal abortSubmissionFailed(string operationId, string sessionId, string reason)
    /** A chat the user was reading was deleted elsewhere in the list. */
    signal currentDropped

    property int operationSequence: 0
    readonly property int schemaVersion: 3

    function operationId(prefix: string): string {
        root.operationSequence += 1;
        return `${prefix}-${Date.now()}-${root.operationSequence}`;
    }

    function newId(): string {
        // A v4-shaped id. Uniqueness is what matters here, not entropy quality.
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
            const random = Math.floor(Math.random() * 16);
            const value = c === "x" ? random : ((random & 0x3) | 0x8);
            return value.toString(16);
        });
    }

    function entryFor(id: string): var {
        return root.index.find(entry => entry.id === id) ?? null;
    }

    function titleFor(id: string): string {
        return root.entryFor(id)?.title ?? "";
    }

    function ensureLoaded() {
        if (root.loaded || root.loading || root.dir.length === 0)
            return;
        root.loading = true;
        root.enqueue({
            kind: "bootstrap",
            args: ["bootstrap", root.dir, root.legacyDir, String(root.retentionDays)]
        });
    }

    // ── Writing ───────────────────────────────────────────────────────────
    // Saves are debounced: a streamed answer changes the last message on every
    // frame, and none of those intermediate states is worth a file write.

    function scheduleSave() {
        if (root.dir.length === 0)
            return;
        saveTimer.restart();
    }

    function saveNow() {
        saveTimer.stop();
        root.saveRequested();
    }

    /**
     * Writes a session object. The caller owns the shape; only the id is
     * forced, so a fork cannot overwrite the chat it came from.
     */
    function commit(session, requestedOperationId = "", flushNow = false) {
        if (!session || root.dir.length === 0)
            return "";
        const id = session.id ?? root.currentId;
        if (!id || id.length === 0)
            return "";
        const operationId = requestedOperationId || root.operationId("save");
        if (flushNow)
            saveTimer.stop();
        root.enqueue({
            kind: "save",
            args: ["save", root.dir, id],
            stdin: JSON.stringify(session),
            operationId: operationId,
            sessionId: id
        });
        return operationId;
    }

    /** Stage a first-turn snapshot without making it visible to the index. */
    function stageSubmission(session, requestedOperationId = "") {
        if (!session || root.dir.length === 0)
            return "";
        const id = session.id ?? root.currentId;
        if (!id || id.length === 0)
            return "";
        const operationId = requestedOperationId || root.operationId("stage");
        root.enqueue({
            kind: "stage",
            args: ["stage", root.dir, id, operationId],
            stdin: JSON.stringify(session),
            operationId: operationId,
            sessionId: id
        });
        return operationId;
    }

    /** Commit a previously staged snapshot immediately before dispatch. */
    function commitSubmissionForDispatch(sessionId: string, stagingOperationId: string, requestedOperationId = ""): string {
        if (!sessionId || !stagingOperationId || root.dir.length === 0)
            return "";
        const operationId = requestedOperationId || root.operationId("commit");
        root.enqueue({
            kind: "commitSubmission",
            args: ["commit-staged", root.dir, sessionId, stagingOperationId],
            operationId: operationId,
            sessionId: sessionId
        });
        return operationId;
    }

    /** Remove a staged snapshot that never reached the network. */
    function abortSubmission(sessionId: string, stagingOperationId: string, requestedOperationId = ""): string {
        if (!sessionId || !stagingOperationId || root.dir.length === 0)
            return "";
        const operationId = requestedOperationId || root.operationId("abort");
        root.enqueue({
            kind: "abortSubmission",
            args: ["abort-staged", root.dir, sessionId, stagingOperationId],
            operationId: operationId,
            sessionId: sessionId
        });
        return operationId;
    }

    // ── Reading and editing ───────────────────────────────────────────────

    function openSession(id: string) {
        if (!id || id.length === 0)
            return;
        root.enqueue({
            kind: "open",
            args: ["open", root.dir, id],
            id: id,
            operationId: root.operationId("open"),
            sessionId: id
        });
    }

    /** Loads a session for a background repository record without selecting it. */
    function load(id, requestedOperationId = "") {
        if (!id || id.length === 0 || root.dir.length === 0)
            return "";
        const operationId = requestedOperationId || root.operationId("load");
        root.enqueue({
            kind: "load",
            args: ["open", root.dir, id],
            operationId: operationId,
            sessionId: id
        });
        return operationId;
    }

    function rename(id: string, title: string) {
        const trimmed = (title ?? "").trim();
        if (!id || trimmed.length === 0)
            return;
        root.enqueue({
            kind: "index",
            args: ["patch", root.dir, id, "--title", trimmed]
        });
    }

    /** Labels for a chat, as one comma-separated argument. */
    function setTags(id: string, tags: var) {
        if (!id)
            return;
        const list = Array.from(tags ?? []).map(tag => String(tag).trim()).filter(tag => tag.length > 0);
        root.enqueue({
            kind: "index",
            args: ["patch", root.dir, id, "--tags", list.join(",")]
        });
    }

    /** Which project a chat is filed under, "" for none. */
    function setProject(id: string, projectId: string) {
        if (!id)
            return;
        root.enqueue({
            kind: "index",
            args: ["patch", root.dir, id, "--project", String(projectId ?? "")]
        });
    }

    /** Every label in use, for the filter row. */
    readonly property var allTags: {
        const seen = [];
        const entries = root.index ?? [];
        for (let i = 0; i < entries.length; i++) {
            const tags = entries[i]?.tags ?? [];
            for (let at = 0; at < tags.length; at++) {
                const tag = String(tags[at]);
                if (tag.length > 0 && seen.indexOf(tag) < 0)
                    seen.push(tag);
            }
        }
        return seen.sort();
    }

    function setPinned(id: string, pinned: bool) {
        if (!id)
            return;
        root.enqueue({
            kind: "index",
            args: ["patch", root.dir, id, "--pinned", pinned ? "1" : "0"]
        });
    }

    function duplicate(id: string) {
        if (!id)
            return;
        root.enqueue({
            kind: "index",
            args: ["duplicate", root.dir, id, root.newId()]
        });
    }

    function remove(id: string) {
        if (!id)
            return;
        root.deletedEntry = root.entryFor(id);
        undoTimer.restart();
        root.enqueue({
            kind: "index",
            args: ["delete", root.dir, id]
        });
        if (root.currentId === id) {
            root.currentId = "";
            root.currentDropped();
        }
    }

    /** Explicit name for page hosts; the old remove() API remains compatible. */
    function trash(id: string) {
        root.remove(id);
    }

    function restore(id: string) {
        if (!id)
            return;
        root.enqueue({
            kind: "index",
            args: ["restore", root.dir, id]
        });
    }

    /** Permanently deletes only the already-trashed file for this id. */
    function purge(id: string) {
        if (!id)
            return;
        root.enqueue({
            kind: "index",
            args: ["purge", root.dir, id]
        });
    }

    function setRetentionDays(days: int) {
        Config.options.ai.sessions.retentionDays = Math.max(1, Math.min(3650, Number(days) || 30));
    }

    onRetentionDaysChanged: {
        // Bootstrap applies the same policy before exposing the index. Later
        // edits take effect immediately, so shortening retention is real and
        // does not wait for the next shell restart.
        if (root.loaded && root.dir.length > 0) {
            root.enqueue({
                kind: "retention",
                args: ["purge-expired", root.dir, String(root.retentionDays)]
            });
        }
    }

    function undoDelete() {
        const entry = root.deletedEntry;
        if (!entry)
            return;
        root.deletedEntry = null;
        undoTimer.stop();
        root.enqueue({
            kind: "index",
            args: ["restore", root.dir, entry.id]
        });
    }

    function exportMarkdown(id: string) {
        const entry = root.entryFor(id);
        if (!entry)
            return;
        const safeTitle = (entry.title || "chat").replace(/[^\w\- ]+/g, "").trim().replace(/\s+/g, "-");
        root.enqueue({
            kind: "export",
            args: ["export", root.dir, id, `${root.exportDir}/${safeTitle || "chat"}.md`]
        });
    }

    /**
     * Titles are matched in the index; message bodies need the files, so the
     * helper does that part. Both halves land in `matchedIds`.
     */
    function search(text: string) {
        root.query = (text ?? "").trim();
        if (root.query.length === 0) {
            root.matchedIds = null;
            searchProc.running = false;
            return;
        }
        searchProc.running = false;
        searchProc.query = root.query;
        searchProc.running = true;
    }

    // ── The queue ─────────────────────────────────────────────────────────
    // One helper process at a time, in the order the user asked for things.
    // Anything else would race the index against itself.

    property var pending: []

    function enqueue(op: var) {
        if (root.scriptPath.length === 0 || root.dir.length === 0)
            return;
        root.pending.push(op);
        if (!opProc.running)
            root.runNext();
    }

    function runNext() {
        if (opProc.running || root.pending.length === 0)
            return;
        const op = root.pending.shift();
        opProc.op = op;
        opProc.payload = op.stdin ?? "";
        opProc.command = ["python3", root.scriptPath, ...op.args];
        opProc.stdinEnabled = false;
        opProc.running = true;
    }

    function failOperation(op: var, reason: string) {
        if (!op || (op === opProc.op && opProc.operationAcknowledged))
            return;
        if (op === opProc.op)
            opProc.operationAcknowledged = true;
        const operationId = String(op.operationId ?? "");
        const sessionId = String(op.sessionId ?? op.id ?? "");
        if (op.kind === "save")
            root.saveFailed(operationId, sessionId, reason);
        else if (op.kind === "open")
            root.openFailed(sessionId, reason);
        else if (op.kind === "load")
            root.loadFailed(operationId, sessionId, reason);
        else if (op.kind === "stage")
            root.stageFailed(operationId, sessionId, reason);
        else if (op.kind === "commitSubmission")
            root.commitSubmissionFailed(operationId, sessionId, reason);
        else if (op.kind === "abortSubmission")
            root.abortSubmissionFailed(operationId, sessionId, reason);
    }

    function applyResult(op: var, raw: string) {
        if (op === opProc.op && opProc.operationAcknowledged)
            return;
        if (!op || raw.trim().length === 0) {
            root.failOperation(op, "The session helper returned no result");
            return;
        }
        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (error) {
            console.log("[AiSessions] Unreadable helper output:", error);
            root.failOperation(op, "The session helper returned invalid JSON");
            return;
        }
        if (parsed.error) {
            root.lastError = parsed.error;
            if (op.kind === "bootstrap")
                root.loading = false;
            root.failOperation(op, String(parsed.error));
            return;
        }
        if (op.kind === "bootstrap") {
            if (!Array.isArray(parsed.sessions)) {
                root.lastError = "Session bootstrap returned no index";
                root.loading = false;
                return;
            }
            root.loading = false;
            root.loaded = true;
        }
        root.lastError = "";
        if (op === opProc.op)
            opProc.operationAcknowledged = true;
        if (Array.isArray(parsed.sessions))
            root.index = parsed.sessions;
        if (op.kind === "open" && parsed.session) {
            root.currentId = parsed.session.id;
            root.sessionOpened(parsed.session);
        }
        if (op.kind === "save")
            root.saveSucceeded(String(op.operationId ?? ""), String(op.sessionId ?? ""));
        else if (op.kind === "load" && parsed.session)
            root.loadSucceeded(String(op.operationId ?? ""), String(op.sessionId ?? ""), parsed.session);
        else if (op.kind === "load")
            root.failOperation(op, "The session helper returned no session");
        else if (op.kind === "stage")
            root.stageSucceeded(String(op.operationId ?? ""), String(op.sessionId ?? ""));
        else if (op.kind === "commitSubmission")
            root.commitSubmissionSucceeded(String(op.operationId ?? ""), String(op.sessionId ?? ""));
        else if (op.kind === "abortSubmission")
            root.abortSubmissionSucceeded(String(op.operationId ?? ""), String(op.sessionId ?? ""));
    }

    Timer {
        id: saveTimer
        interval: 1200
        onTriggered: root.saveRequested()
    }

    Timer {
        // How long the undo offer stands. After that the chat is only in the
        // trash folder, which the user can still dig out by hand.
        id: undoTimer
        interval: 12000
        onTriggered: root.deletedEntry = null
    }

    Process {
        id: opProc
        property var op: null
        property string payload: ""
        property bool outputSeen: false
        property bool operationAcknowledged: false

        onRunningChanged: {
            if (opProc.running) {
                opProc.outputSeen = false;
                opProc.operationAcknowledged = false;
                // Closing stdin is what makes the helper read: it blocks until
                // the EOF arrives, so the channel is always opened and closed,
                // payload or not. Leaving it shut on an empty one hangs it.
                opProc.stdinEnabled = true;
                opProc.write(opProc.payload);
                opProc.stdinEnabled = false;
            }
        }

        stdout: StdioCollector {
            id: opCollector
            // `op` is left alone until the next one starts: whether this fires
            // before or after the process exits is not worth depending on.
            onStreamFinished: {
                opProc.outputSeen = true;
                root.applyResult(opProc.op, opCollector.text);
            }
        }

        onExited: {
            if (!opProc.outputSeen)
                root.failOperation(opProc.op, "The session helper exited without an acknowledgement");
            if (opProc.op?.kind === "bootstrap" && !root.loaded)
                root.loading = false;
            Qt.callLater(root.runNext);
        }
    }

    Process {
        id: searchProc
        property string query: ""
        command: ["python3", root.scriptPath, "search", root.dir, searchProc.query]

        stdout: StdioCollector {
            id: searchCollector
            onStreamFinished: {
                const raw = searchCollector.text.trim();
                if (raw.length === 0)
                    return;
                try {
                    const parsed = JSON.parse(raw);
                    // A slower search that finished after the user typed on is
                    // an answer to a question nobody is asking any more.
                    if (parsed.query === root.query.toLowerCase())
                        root.matchedIds = parsed.ids ?? [];
                } catch (error) {
                    console.log("[AiSessions] Unreadable search output:", error);
                }
            }
        }
    }
}
