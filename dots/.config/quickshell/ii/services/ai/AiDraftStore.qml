pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Durable composer drafts, separate from sessions/configuration.
 *
 * There is exactly one owner under Ai.qml. The helper writes an independent
 * schema-1 file atomically, so a truncated draft file can never overwrite a
 * transcript or a user setting. The in-memory map is still updated immediately
 * for responsive typing; only the debounced operation queue touches disk.
 */
Scope {
    id: root

    property string directory: ""
    property string scriptPath: ""
    property bool loaded: false
    property bool loading: false
    property bool writesBlocked: false
    property int retryCount: 0
    property var drafts: ({})
    property var dirty: ({})
    property var pending: []

    signal draftRestored(string sessionId, string text)
    signal storeReady
    signal storeError(string reason)
    signal saveSucceeded(string sessionId)
    signal saveFailed(string sessionId, string reason)

    function ensureLoaded() {
        if (root.loaded || root.loading || root.directory.length === 0 || root.scriptPath.length === 0)
            return;
        root.loading = true;
        root.enqueue({
            kind: "load",
            args: ["load", root.directory]
        });
    }

    function textFor(sessionId: string): string {
        return String(root.drafts[String(sessionId ?? "")]?.text ?? "");
    }

    function setDraft(sessionId: string, text: string) {
        const id = String(sessionId ?? "").trim();
        if (id.length === 0)
            return;
        const value = String(text ?? "");
        const next = Object.assign({}, root.drafts);
        if (value.trim().length === 0)
            delete next[id];
        else
            next[id] = { text: value, updatedAt: Date.now() };
        root.drafts = next;
        root.dirty = Object.assign({}, root.dirty, { [id]: value });
        root.writesBlocked = false;
        saveTimer.restart();
    }

    function clearDraft(sessionId: string, expectedText = "") {
        const id = String(sessionId ?? "").trim();
        if (id.length === 0)
            return false;
        const current = root.textFor(id);
        if (expectedText.length > 0 && current !== expectedText)
            return false;
        if (current.length === 0)
            return true;
        root.setDraft(id, "");
        return true;
    }

    function savePending() {
        if (!root.loaded || root.writesBlocked || root.drafts === undefined)
            return;
        const ids = Object.keys(root.dirty);
        // One complete snapshot per operation keeps concurrent edits ordered;
        // the queue naturally coalesces the debounce window.
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            root.enqueue({
                kind: "save",
                args: ["save", root.directory, id],
                stdin: String(root.dirty[id] ?? ""),
                text: String(root.dirty[id] ?? ""),
                sessionId: id
            });
        }
    }

    Timer {
        id: saveTimer
        interval: 350
        onTriggered: root.savePending()
    }

    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: {
            root.loading = false;
            root.ensureLoaded();
        }
    }

    function enqueue(operation: var) {
        root.pending = [...root.pending, operation];
        if (!operationProc.running)
            root.runNext();
    }

    function runNext() {
        if (operationProc.running || root.pending.length === 0)
            return;
        const operation = root.pending[0];
        root.pending = root.pending.slice(1);
        operationProc.operation = operation;
        operationProc.command = ["python3", root.scriptPath, ...operation.args];
        operationProc.stdinEnabled = false;
        operationProc.running = true;
    }

    function applyResult(operation: var, raw: string) {
        let parsed;
        try {
            parsed = JSON.parse(raw.trim());
        } catch (error) {
            root.handleFailure(operation, "Draft helper returned invalid JSON");
            return;
        }
        if (parsed.error) {
            root.handleFailure(operation, String(parsed.error));
            return;
        }
        if (operation.kind === "load") {
            const loadedDrafts = parsed.drafts ?? ({});
            root.drafts = loadedDrafts;
            root.loaded = true;
            root.loading = false;
            root.retryCount = 0;
            root.storeReady();
            Object.keys(loadedDrafts).forEach(id => root.draftRestored(id, String(loadedDrafts[id]?.text ?? "")));
        } else if (operation.kind === "save") {
            if (root.textFor(operation.sessionId) === operation.text) {
                const nextDirty = Object.assign({}, root.dirty);
                delete nextDirty[operation.sessionId];
                root.dirty = nextDirty;
            }
            root.saveSucceeded(operation.sessionId);
        }
    }

    function handleFailure(operation: var, reason: string) {
        if (operation.kind === "load" && root.retryCount < 3) {
            root.retryCount += 1;
            retryTimer.restart();
            return;
        }
        if (operation.kind === "load") {
            root.loading = false;
            root.loaded = true;
            root.writesBlocked = true;
            root.storeError(reason);
        } else {
            root.saveFailed(operation.sessionId, reason);
        }
    }

    Process {
        id: operationProc
        property var operation: null
        stdout: StdioCollector {
            id: output
            onStreamFinished: root.applyResult(operationProc.operation, output.text)
        }
        stdinEnabled: false
        onRunningChanged: {
            if (running) {
                // Switching stdin off is what sends the helper its EOF, and it
                // blocks on read() until that arrives. Skipping the toggle for
                // an empty draft left a clear hanging forever: the queue never
                // advanced again and the sent prompt stayed on disk.
                operationProc.stdinEnabled = true;
                operationProc.write(String(operationProc.operation?.stdin ?? ""));
                operationProc.stdinEnabled = false;
            } else {
                Qt.callLater(root.runNext);
            }
        }
        onExited: {
            if (operationProc.operation?.kind === "load" && output.text.trim().length === 0)
                root.handleFailure(operationProc.operation, "Draft helper returned no result");
        }
    }
}
