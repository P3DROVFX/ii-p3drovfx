pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions


Item {
    id: root
    visible: false

    signal lyricsUpdated(string lyrics)

    // Lets the UI tell "still searching" apart from "found nothing".
    readonly property alias fetching: fetchLyricsProcess.running

    property string _lastQueryKey: ""

    function fetchLyrics(artist, title) {
        if (!title && !artist) return;
        const queryArtist = artist ?? ""
        const queryTitle = title ?? ""
        const key = queryArtist + "::" + queryTitle
        if (key === _lastQueryKey && fetchLyricsProcess.running) return;
        _lastQueryKey = key
        console.log("[YTMusic Lyrics] Fetching lyrics for", queryArtist, "-", queryTitle)
        fetchLyricsProcess.running = false
        fetchLyricsProcess.command = [Directories.ytmusicLyricsScriptPath, queryArtist, queryTitle]
        fetchLyricsProcess.running = true
    }

    Process {
        id: fetchLyricsProcess
        running: false
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim()
                if (text.length > 0) {
                    lyricsUpdated(text)
                } else {
                    console.log("[YTMusic Lyrics] Empty response received")
                }
            }
        }
    }
}
