pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common

/**
 * Service that fetches OpenGraph/Twitter card/oEmbed metadata and thumbnail previews for web URLs.
 *
 * Runs `scripts/notes/link_preview.py` as an external process with queueing, watchdog timeouts,
 * and graceful fallback.
 * Respects Persistent.states.notes.linkPreviews: if disabled, passes --no-network to ensure
 * no external requests are made.
 */
Singleton {
    id: root

    readonly property string scriptPath: `${Directories.scriptPath}/notes/link_preview.py`
    readonly property string cacheDir: Directories.notesLinkPreviewsCacheDir

    signal previewReady(string url, var data)

    /// In-memory cache for fast lookups.
    property var memoryCache: ({})
    property var taskQueue: []
    property var currentTask: null

    function invalidate(url: string): void {
        const rawUrl = String(url ?? "").trim();
        if (rawUrl.length === 0) {
            root.memoryCache = ({});
        } else if (root.memoryCache.hasOwnProperty(rawUrl)) {
            const next = Object.assign({}, root.memoryCache);
            delete next[rawUrl];
            root.memoryCache = next;
        }
    }

    function fetchPreview(url: string, callback: var, refresh = false): void {
        const rawUrl = String(url ?? "").trim();
        if (rawUrl.length === 0)
            return;

        if (!refresh && root.memoryCache.hasOwnProperty(rawUrl)) {
            const cached = root.memoryCache[rawUrl];
            if (callback)
                Qt.callLater(() => callback(cached));
            root.previewReady(rawUrl, cached);
            return;
        }

        // If currently fetching this URL, attach callback
        if (root.currentTask && root.currentTask.url === rawUrl) {
            if (callback)
                root.currentTask.callbacks.push(callback);
            return;
        }

        // If already queued, attach callback
        for (let i = 0; i < root.taskQueue.length; i++) {
            if (root.taskQueue[i].url === rawUrl) {
                if (callback)
                    root.taskQueue[i].callbacks.push(callback);
                return;
            }
        }

        root.taskQueue.push({
            url: rawUrl,
            refresh: refresh === true,
            callbacks: callback ? [callback] : []
        });

        root.processQueue();
    }

    function processQueue(): void {
        if (root.currentTask !== null || root.taskQueue.length === 0)
            return;

        const task = root.taskQueue.shift();
        root.currentTask = task;

        const allowNetwork = Persistent.states.notes.linkPreviews !== false;
        const args = [root.scriptPath, task.url, "--cache-dir", root.cacheDir];
        if (!allowNetwork)
            args.push("--no-network");
        if (task.refresh)
            args.push("--refresh");

        previewProc.command = ["python3"].concat(args);
        previewProc.running = true;
        watchdogTimer.restart();
    }

    function finishTask(result): void {
        watchdogTimer.stop();
        previewProc.running = false;

        const task = root.currentTask;
        root.currentTask = null;

        if (task) {
            if (result && result.ok) {
                const nextCache = Object.assign({}, root.memoryCache);
                nextCache[task.url] = result;
                root.memoryCache = nextCache;
            }
            for (let i = 0; i < task.callbacks.length; i++) {
                try {
                    task.callbacks[i](result);
                } catch (e) {
                    console.warn("[NotesLinkPreview] Callback invocation failed:", e);
                }
            }
            root.previewReady(task.url, result);
        }

        Qt.callLater(() => root.processQueue());
    }

    Timer {
        id: watchdogTimer
        interval: 10000
        repeat: false
        onTriggered: {
            console.warn("[NotesLinkPreview] Preview fetch timed out for URL:", root.currentTask ? root.currentTask.url : "");
            root.finishTask({
                ok: false,
                url: root.currentTask ? root.currentTask.url : "",
                error: "Timeout"
            });
        }
    }

    Process {
        id: previewProc
        running: false

        stdout: StdioCollector {
            id: outCollector
        }

        stderr: StdioCollector {
            id: errCollector
        }

        onExited: (exitCode, exitStatus) => {
            if (root.currentTask === null)
                return;

            let result = null;
            const text = (outCollector.text || "").trim();
            if (text.length > 0) {
                try {
                    result = JSON.parse(text);
                } catch (e) {
                    console.warn("[NotesLinkPreview] Output parse error:", e, text);
                    result = {
                        ok: false,
                        url: root.currentTask.url,
                        error: "Parse error: " + e.message
                    };
                }
            } else {
                result = {
                    ok: false,
                    url: root.currentTask.url,
                    error: (errCollector.text || "").trim() || "Empty process output"
                };
            }

            root.finishTask(result);
        }
    }
}
