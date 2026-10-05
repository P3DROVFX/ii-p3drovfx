import QtQuick
import Quickshell.Io
import Qt.labs.folderlistmodel
import "UtilityFiles.js" as UtilityFiles

/**
 * The newest files of a folder and how many arrived after `seenAfter` (ms).
 * Unfinished downloads and hidden files are left out. Not visual; Files and
 * Screenshots each own one.
 *
 * FolderListModel only watches: its `fileModified` role comes back as an
 * invalid date on this Qt, so the listing itself is one `find -printf`
 * (mtime + path, newest first), run after each burst of folder changes.
 */
Item {
    id: feed

    property string folder: ""
    property real seenAfter: 0
    property int limit: 12
    property bool active: true
    // Extensions to keep (lower case, no dot); empty keeps everything.
    property var extensions: []

    property var recent: []
    property int newCount: 0
    property var _all: []

    function _apply() {
        const out = [];
        let fresh = 0;
        for (const entry of feed._all) {
            if (entry.modified > feed.seenAfter)
                fresh++;
            if (out.length < feed.limit)
                out.push(entry);
        }
        feed.recent = out;
        feed.newCount = feed.seenAfter > 0 ? fresh : 0;
    }

    function rebuild() {
        if (!feed.active || feed.folder.length === 0)
            return;
        lister.running = false;
        lister.running = true;
    }

    onSeenAfterChanged: feed._apply()
    onLimitChanged: feed._apply()
    onFolderChanged: rebuildTimer.restart()
    Component.onCompleted: rebuildTimer.restart()

    Process {
        id: lister
        command: ["sh", "-c",
            'find "$1" -maxdepth 1 -type f ! -name ".*" -printf "%T@\\t%p\\n" 2>/dev/null | sort -rn | head -n 400',
            "sh", feed.folder]
        stdout: StdioCollector {
            onStreamFinished: {
                const partial = /\.(part|crdownload|download|tmp|partial)$/i;
                const keep = (feed.extensions ?? []).map(ext => String(ext).toLowerCase());
                const all = [];
                for (const line of this.text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab <= 0)
                        continue;
                    const path = line.slice(tab + 1);
                    const name = UtilityFiles.baseName(path);
                    if (partial.test(name))
                        continue;
                    if (keep.length > 0) {
                        const dot = name.lastIndexOf(".");
                        if (dot < 0 || keep.indexOf(name.slice(dot + 1).toLowerCase()) < 0)
                            continue;
                    }
                    all.push({ path: path, name: name, modified: Math.round(Number(line.slice(0, tab)) * 1000) });
                }
                feed._all = all;
                feed._apply();
            }
        }
    }

    // The folder's own watcher: any change schedules one listing.
    FolderListModel {
        folder: feed.active && feed.folder ? UtilityFiles.fileUri(feed.folder) : ""
        showDirs: false
        showHidden: false
        showDotAndDotDot: false
        onCountChanged: rebuildTimer.restart()
        onRowsInserted: rebuildTimer.restart()
        onRowsRemoved: rebuildTimer.restart()
        onDataChanged: rebuildTimer.restart()
    }

    // A download landing fires a burst of changes; list once after it.
    Timer {
        id: rebuildTimer
        interval: 250
        onTriggered: feed.rebuild()
    }
}
