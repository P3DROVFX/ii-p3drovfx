pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The one cover-art cache every media surface reads.
 *
 * Each widget used to run its own curl into the same `<md5>.tmp`: on a track
 * change a dozen of them raced, the losers' `mv` failed and they marked the
 * cover missing, and a curl with no timeout left its downloader `running`
 * forever, so every later track was ignored until a restart.
 *
 * Here a URL is fetched once, one at a time, into a private temp file with
 * timeouts, and `source(url)` is a binding-friendly lookup.
 */
Singleton {
    id: root

    // Bumped whenever a download lands; `source()` reads it so bindings re-run.
    property int revision: 0
    property var _ready: ({})
    property var _failedAt: ({})
    property var _queue: []
    readonly property int retryAfterMs: 15000

    function isLocal(url: string): bool {
        return url.startsWith("file://") || url.startsWith("/");
    }

    function cachePath(url: string): string {
        return `${Directories.coverArt}/${Qt.md5(url)}`;
    }

    // A loadable source for `url`, or "" until its download finishes.
    function source(url: string): string {
        root.revision;
        if (!url)
            return "";
        if (root.isLocal(url))
            return url.startsWith("/") ? `file://${url}` : url;
        if (root._ready[url])
            return Qt.resolvedUrl(root.cachePath(url));
        root.request(url);
        return "";
    }

    // The same, as a filesystem path, for consumers that read the file itself.
    function localPath(url: string): string {
        const src = root.source(url);
        return src === "" ? "" : FileUtils.trimFileProtocol(src);
    }

    function request(url: string): void {
        if (!url || root.isLocal(url) || root._ready[url])
            return;
        const failed = root._failedAt[url];
        if (failed && Date.now() - failed < root.retryAfterMs)
            return;
        if (root._busy && root._current === url)
            return;
        if (!root._queue.includes(url))
            root._queue.push(url);
        Qt.callLater(root._pump);
    }

    // A user-asked retry skips the wait after a failure.
    function retry(url: string): void {
        delete root._failedAt[url];
        root.request(url);
    }

    // The URL the running job is fetching, and whether one is running.
    property string _current: ""
    readonly property bool _busy: downloader.running || decoder.running

    // Logs never carry a whole `data:` URI (hundreds of KB each).
    function _short(url: string): string {
        return url.length > 120 ? `${url.slice(0, 120)}… (${url.length} chars)` : url;
    }

    function _pump(): void {
        if (root._busy || root._queue.length === 0)
            return;
        const url = root._queue.shift();
        if (root._ready[url])
            return root._pump();
        root._current = url;
        // Players like browsers and some local-file players hand MPRIS the
        // cover inline as a `data:` URI. curl can't fetch it, and as a process
        // argument it trips the kernel's 128 KiB per-argument limit, so the
        // process never starts and never reports an exit. Decode it from
        // stdin instead.
        const job = url.startsWith("data:") ? decoder : downloader;
        job.path = root.cachePath(url);
        job.exited = false;
        job.running = true;
    }

    function _finish(url: string, ok: bool, why: string): void {
        if (ok) {
            const ready = Object.assign({}, root._ready);
            ready[url] = true;
            root._ready = ready;
            delete root._failedAt[url];
            root.revision++;
        } else {
            root._failedAt[url] = Date.now();
            console.warn(`[CoverArt] download failed (${why}): ${root._short(url)}`);
            retryTimer.restart();
        }
        Qt.callLater(root._pump);
    }

    // A failed cover gets asked for again once its wait is over, through the
    // bindings still showing it.
    Timer {
        id: retryTimer
        interval: root.retryAfterMs + 100
        onTriggered: root.revision++
    }

    Process {
        id: downloader
        property string path: ""
        property bool exited: false
        command: ["bash", "-c",
            "test -s \"$2\" && exit 0; mkdir -p \"$(dirname \"$2\")\"; t=$(mktemp \"$2.XXXXXX\") || exit 1; "
            + "if curl -fLsS -4 --connect-timeout 8 --max-time 30 -o \"$t\" -- \"$1\" && test -s \"$t\"; then mv -f -- \"$t\" \"$2\"; else rm -f -- \"$t\"; exit 1; fi",
            "cover-art", root._current, path]
        onExited: exitCode => {
            exited = true;
            root._finish(root._current, exitCode === 0, `${exitCode}`);
        }
        // A process that fails to start stops running without `exited`; left
        // unhandled, every binding re-queued the URL at once, forever.
        onRunningChanged: if (!running && !exited) {
            exited = true;
            root._finish(root._current, false, "failed to start");
        }
    }

    Process {
        id: decoder
        property string path: ""
        property bool exited: false
        stdinEnabled: true
        command: ["bash", "-c",
            "test -s \"$1\" && { cat >/dev/null; exit 0; }; mkdir -p \"$(dirname \"$1\")\"; t=$(mktemp \"$1.XXXXXX\") || exit 1; "
            + "if base64 -d > \"$t\" && test -s \"$t\"; then mv -f -- \"$t\" \"$1\"; else rm -f -- \"$t\"; exit 1; fi",
            "cover-art", path]
        onStarted: {
            const url = root._current;
            const comma = url.indexOf(",");
            // Only base64 payloads are images worth decoding.
            if (comma > 0 && url.slice(0, comma).endsWith(";base64"))
                write(url.slice(comma + 1));
            stdinEnabled = false;
        }
        onExited: exitCode => {
            exited = true;
            stdinEnabled = true;
            root._finish(root._current, exitCode === 0, `${exitCode}`);
        }
        onRunningChanged: if (!running && !exited) {
            exited = true;
            stdinEnabled = true;
            root._finish(root._current, false, "failed to start");
        }
    }
}
