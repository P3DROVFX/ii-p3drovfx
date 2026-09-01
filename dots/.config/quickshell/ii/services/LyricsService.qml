pragma Singleton

import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.utils
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property bool lyricsEnabled: Config.options.lyricsService.enable
    readonly property bool geniusEnabled: Config.options.lyricsService.enableGenius
    readonly property bool lrclibEnabled: Config.options.lyricsService.enableLrclib
    readonly property bool ytmusicEnabled: Config.options.lyricsService.enableYtmusic
    readonly property string lyricsProvider: Config.options.lyricsService.lyricsProvider ?? "auto"
    
    property bool isInitialized: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string currentTrackId: root.activePlayer?.trackTitle ?? ""

    readonly property bool effectiveLrclibEnabled: lyricsEnabled && lrclibEnabled && isInitialized && (root.activePlayer?.trackTitle?.length > 0)
    readonly property bool effectiveGeniusEnabled: lyricsEnabled && geniusEnabled && isInitialized
    readonly property bool effectiveYtmusicEnabled: lyricsEnabled && ytmusicEnabled && isInitialized && (root.activePlayer?.trackTitle?.length > 0)

    readonly property alias syncedLines: lrclib.lines
    readonly property alias currentIndex: lrclib.currentIndex
    readonly property string statusText: lrclib.displayText
    readonly property bool hasSyncedLines: lrclib.lines.length > 0

    // Single source of truth for "where the lyrics think we are": player
    // position corrected by the user's sync offset. Used by the sync itself and
    // by anything that has to reason about gaps between lines.
    readonly property real syncPosition: Math.max(0,
        (root.activePlayer?.position ?? 0)
        + ((Config.options.background.mediaMode.lyricsOffsetMs ?? 0) / 1000))

    // LRCLib flags a track as instrumental. That is a real answer, not a
    // failure, and deserves its own UI state instead of "no lyrics found".
    readonly property bool instrumental: lrclib.instrumental && !root.hasSyncedLines
    readonly property bool hasPlainLyrics: root.plainLyrics.trim().length > 0
    readonly property bool hasAnyLyrics: root.hasSyncedLines || root.hasPlainLyrics
    readonly property bool usingCustomLyrics: lrclib.hasOverride

    // True while any provider still has a request in flight, plus a grace
    // window after a track change so the UI never flashes "not found" during
    // the fetch debounce.
    property bool searchGraceElapsed: false
    readonly property bool searching: root.isInitialized
        && (root.activePlayer?.trackTitle?.length > 0)
        && !root.usingCustomLyrics
        && (!root.searchGraceElapsed || lrclib.loading || genius.fetching || ytmusic.fetching)

    // Per-provider outcome, for the "nothing found" state to show what was tried.
    readonly property var providerStates: [
        {
            key: "lrclib",
            label: "LRCLib",
            icon: "timer",
            enabled: root.lrclibEnabled,
            searching: lrclib.loading,
            found: lrclib.lines.length > 0 || lrclib.plainLyricsText.length > 0
        },
        {
            key: "ytmusic",
            label: "YouTube Music",
            icon: "smart_display",
            enabled: root.ytmusicEnabled,
            searching: ytmusic.fetching,
            found: ytmusic.lyricsString.length > 0
        },
        {
            key: "genius",
            label: "Genius",
            icon: "music_note",
            enabled: root.geniusEnabled,
            searching: genius.fetching,
            found: genius.lyricsString.length > 0
        }
    ]

    Timer {
        id: searchGraceTimer
        interval: 1600
        onTriggered: root.searchGraceElapsed = true
    }

    function beginSearchGrace() {
        root.searchGraceElapsed = false;
        searchGraceTimer.restart();
    }

    // Hand-written LRC for the current track, applied on top of any fetch.
    function saveCustomLyrics(lrcText) {
        if (!root.activePlayer)
            return;
        CustomLyricsStore.set(root.activePlayer.trackTitle ?? "",
            root.activePlayer.trackArtist ?? "", lrcText);
    }

    function clearCustomLyrics() {
        if (!root.activePlayer)
            return;
        CustomLyricsStore.remove(root.activePlayer.trackTitle ?? "",
            root.activePlayer.trackArtist ?? "");
    }

    function retrySearch() {
        root.beginSearchGrace();
        lrclib.retryFetch();
        root.initiliazeLyrics();
    }

    readonly property alias geniusHasLyrics: genius.hasString

    // Resolved plain lyrics based on active provider setting:
    // "auto"   → lrclib plain → ytmusic → genius (first non-empty wins)
    // "lrclib" → lrclib plain only
    // "ytmusic"→ ytmusic only
    // "genius" → genius only
    readonly property string plainLyrics: {
        const provider = root.lyricsProvider;
        if (provider === "lrclib") return lrclib.plainLyricsText;
        if (provider === "ytmusic") return ytmusic.lyricsString;
        if (provider === "genius")  return genius.lyricsString;
        // auto fallback chain
        if (lrclib.plainLyricsText.length > 0)  return lrclib.plainLyricsText;
        if (ytmusic.lyricsString.length > 0)     return ytmusic.lyricsString;
        if (genius.lyricsString.length > 0)      return genius.lyricsString;
        return "";
    }

    property int mediaModeOpenCount: 0 // we increase this number when we enable the media mode and decrease it when we close it, we cant use a boolean because it doesnot work on multiple monitor toggle

    // We use this flag to change shell color just once, otherwise it will be called 3-4 times depending on the user's monitor count
    property bool shellColorChanged: false

    // Function to initialize the lyrics service, to prevent unnecessary API calls when no lyrics UI is being use
    // Its being called in LyricsStatic, LyricsScroller and LyricsFlickable files
    function initiliazeLyrics() {
        if (!root.isInitialized)
            root.beginSearchGrace();
        root.isInitialized = true
        if (root.activePlayer) {
            if (effectiveGeniusEnabled)
                genius.fetchLyrics(root.activePlayer?.trackArtist ?? "", root.activePlayer?.trackTitle ?? "")
            if (effectiveYtmusicEnabled)
                ytmusic.fetchLyrics(root.activePlayer?.trackArtist ?? "", root.activePlayer?.trackTitle ?? "")
        }
    }

    function filterLyricLines(lyrics) { // for clearing the metadata in genius lyrics
        return lyrics
            .split("\n")
            .filter(line => {
                const trimmed = line.trim()
                return !(trimmed.startsWith("[") && trimmed.endsWith("]"))
            })
            .slice(1)
            .join("\n")
    }

    function getLineDuration(index) { // for lrclib of to be used in syllable style
        if (!lrclib.lines || index < 0 || index >= lrclib.lines.length) 
            return 0;
        
        if (index === lrclib.lines.length - 1) {
            let total = lrclib.duration > 0 ? lrclib.duration : lrclib.lines[index].time + 5;
            return Math.max(0, total - lrclib.lines[index].time);
        }
        
        return lrclib.lines[index + 1].time - lrclib.lines[index].time;
    }

    function changeDurationToIndex(index) { // for lrclib, called by LyricsSyllable
        if (!hasSyncedLines) return;
        root.activePlayer.position = root.syncedLines[index].time
    }
    
    // https://quickshell.org/docs/master/types/Quickshell.Services.Mpris/MprisPlayer/#position
    Timer {
        running: root.activePlayer?.playbackState == MprisPlaybackState.Playing && root.hasSyncedLines && root.isInitialized
        interval: 250
        repeat: true
        onTriggered: root.activePlayer.positionChanged()
    }

    Component.onCompleted: firstFetchDelay.restart()
    Timer {
        id: firstFetchDelay
        running: false
        interval: 1000
        onTriggered: {
            if (root.activePlayer) {
                if (effectiveGeniusEnabled)
                    genius.fetchLyrics(root.activePlayer.trackArtist, root.activePlayer.trackTitle)
                if (effectiveYtmusicEnabled)
                    ytmusic.fetchLyrics(root.activePlayer.trackArtist, root.activePlayer.trackTitle)
            }
        }
    }

    LrclibLyrics {
        id: lrclib
        enabled: effectiveLrclibEnabled
        title: root.activePlayer?.trackTitle ?? ""
        artist: root.activePlayer?.trackArtist ?? ""
        duration: root.activePlayer?.length ?? 0
        position: root.syncPosition
        overrideLyrics: CustomLyricsStore.get(root.activePlayer?.trackTitle ?? "",
            root.activePlayer?.trackArtist ?? "")
    }

    GeniusLyrics {
        id: genius
        readonly property string trackTitle: root.activePlayer?.trackTitle ?? ""
        onTrackTitleChanged: {
            if (root.activePlayer) {
                if (!effectiveGeniusEnabled) return;
                genius.hasString = false
                genius.fetchLyrics(root.activePlayer.trackArtist, root.activePlayer.trackTitle)
            }
        }
        property string lyricsString: ""
        property bool hasString: false
        onLyricsUpdated: (lyrics) => {
            if (!effectiveGeniusEnabled) return
            genius.hasString = true
            genius.lyricsString = filterLyricLines(lyrics)
        }
    }

    onIsInitializedChanged: {
        if (isInitialized && root.activePlayer) {
            if (effectiveGeniusEnabled)
                genius.fetchLyrics(root.activePlayer?.trackArtist ?? "", root.activePlayer?.trackTitle ?? "")
            if (effectiveYtmusicEnabled)
                ytmusic.fetchLyrics(root.activePlayer?.trackArtist ?? "", root.activePlayer?.trackTitle ?? "")
        }
    }

    YTMusicLyrics {
        id: ytmusic
        readonly property string trackTitle: root.activePlayer?.trackTitle ?? ""
        onTrackTitleChanged: {
            if (root.activePlayer) {
                if (!effectiveYtmusicEnabled) return;
                ytmusic.lyricsString = ""
                ytmusic.fetchLyrics(root.activePlayer?.trackArtist ?? "", root.activePlayer?.trackTitle ?? "")
            }
        }
        property string lyricsString: ""
        onLyricsUpdated: (lyrics) => {
            if (!effectiveYtmusicEnabled) return
            ytmusic.lyricsString = lyrics
        }
    }
    
    onCurrentTrackIdChanged: {
        shellColorChanged = false // reseting at each track change
        root.beginSearchGrace();

        if (!currentTrackId) {
            genius.lyricsString = ""
            ytmusic.lyricsString = ""
            return;
        }

        if (effectiveGeniusEnabled)
            genius.fetchLyrics(root.activePlayer?.trackArtist ?? "", root.activePlayer?.trackTitle ?? "")
        if (effectiveYtmusicEnabled)
            ytmusic.fetchLyrics(root.activePlayer?.trackArtist ?? "", root.activePlayer?.trackTitle ?? "")
    }

    // I dont know if this is the correct place for this, but we only call this from MediaMode so it should be fine
    function changeShellColor(color, force = false) {
        // console.log("[Lyrics Service] Color change requested, is it changed: ", shellColorChanged)
        // console.log("[Lyrics Service] Is media mode open :  ", mediaModeOpenCount > 0)
        if (!mediaModeOpenCount > 0 || shellColorChanged && !force) return;
        // console.log("[Lyrics Service] Changing the shell color with color:   ", color)
        Quickshell.execDetached([`${Directories.wallpaperSwitchScriptPath}`, "--noswitch", "--color", color])
        shellColorChanged = true
    }
}