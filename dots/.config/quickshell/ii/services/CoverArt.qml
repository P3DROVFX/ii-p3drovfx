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
        if (downloader.url === url && downloader.running)
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

    function _pump(): void {
        if (downloader.running || root._queue.length === 0)
            return;
        const url = root._queue.shift();
        if (root._ready[url])
            return root._pump();
        downloader.url = url;
        downloader.path = root.cachePath(url);
        downloader.running = true;
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
        property string url: ""
        property string path: ""
        command: ["bash", "-c",
            "test -s \"$2\" && exit 0; mkdir -p \"$(dirname \"$2\")\"; t=$(mktemp \"$2.XXXXXX\") || exit 1; "
            + "if curl -fLsS -4 --connect-timeout 8 --max-time 30 -o \"$t\" -- \"$1\" && test -s \"$t\"; then mv -f -- \"$t\" \"$2\"; else rm -f -- \"$t\"; exit 1; fi",
            "cover-art", url, path]
        onExited: exitCode => {
            const url = downloader.url;
            if (exitCode === 0) {
                const ready = Object.assign({}, root._ready);
                ready[url] = true;
                root._ready = ready;
                delete root._failedAt[url];
                root.revision++;
            } else {
                root._failedAt[url] = Date.now();
                console.warn(`[CoverArt] download failed (${exitCode}): ${url}`);
                retryTimer.restart();
            }
            Qt.callLater(root._pump);
        }
    }
}
