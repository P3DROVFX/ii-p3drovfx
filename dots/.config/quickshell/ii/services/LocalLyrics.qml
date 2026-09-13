pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Reads the sidecar lyric file selected by the local-media scanner.
 *
 * It has no network fallback and no persistence: `LyricsService` decides the
 * provider order. Keeping this reader separate makes a path change clear the
 * preceding track immediately, so an asynchronous FileView result can never
 * leave stale lyrics visible while the next local track is resolving.
 */
Singleton {
    id: root

    property string lyricsPath: ""
    property string lyricsText: ""
    property bool loading: false

    onLyricsPathChanged: {
        lyricsText = "";
        loading = lyricsPath.length > 0;
    }

    FileView {
        id: lyricsFile
        path: root.lyricsPath
        watchChanges: true
        printErrors: false

        onLoaded: {
            root.lyricsText = lyricsFile.text();
            root.loading = false;
        }
        onLoadFailed: error => {
            root.lyricsText = "";
            root.loading = false;
        }
    }
}
