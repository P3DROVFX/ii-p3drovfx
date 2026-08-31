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

    readonly property var geniusApiKey: KeyringStorage.keyringData?.apiKeys?.genius

    property string _lastQueryKey: ""

    function fetchLyrics(artist, title) {
        if (!title && !artist) return;
        const queryArtist = artist ?? ""
        const queryTitle = title ?? ""
        const key = queryArtist + "::" + queryTitle
        if (key === _lastQueryKey && fetchLyricsProcess.running) return;
        _lastQueryKey = key
        console.log("[Genius Lyrics] Fetching lyrics for", queryArtist, "-", queryTitle)
        fetchLyricsProcess.running = false
        fetchLyricsProcess.command = ["node", Directories.geniusLyricsScriptPath, root.geniusApiKey, queryArtist, queryTitle]
        fetchLyricsProcess.running = true
    }

    Process {
        id: fetchLyricsProcess
        running: false
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                lyricsUpdated(this.text)
            }   
        }
    }   
}