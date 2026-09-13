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
        // pdeath: ytmusicapi can stall on a slow response, so even this
        // "one-shot" must die with the shell instead of orphaning (the script
        // also self-caps with SIGALRM, and the wrapper execs Python so the
        // signal reaches it).
        fetchLyricsProcess.command = ProcUtils.pdeath([Directories.ytmusicLyricsScriptPath, queryArtist, queryTitle])
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
