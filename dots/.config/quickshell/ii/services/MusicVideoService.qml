pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.modules.common

/**
 * Searches YouTube for music videos via yt-dlp and plays them as a background
 * layer via mpvpaper (wlr_layer_shell). The video appears behind the media mode
 * overlay, creating a "music video background" effect.
 *
 * Lifecycle:
 *   1. Track changes → search yt-dlp (async via Process)
 *   2. URL found → launch mpvpaper at Background layer
 *   3. Track changes / media mode closes → kill mpvpaper
 */
Singleton {
    id: root

    // ── Public API ──────────────────────────────────────────────────────────

    /// Whether the music video background is globally enabled.
    readonly property bool enabled: Config.options.background.mediaMode.musicVideo.enable

    /// True while a video is currently playing (mpvpaper process is running).
    readonly property bool videoPlaying: mpvpaperProc.running

    /// Unique socket path for mpv IPC control.
    readonly property string ipcSocket: _ipcSocket
    readonly property string currentVideoUrl: _currentUrl

    /// The search query used for the last successful search.
    readonly property string lastSearchQuery: _lastQuery

    /// True if the last search failed (shows fallback UI).
    readonly property bool searchFailed: _searchFailed

    // ── Internal state ──────────────────────────────────────────────────────

    property string _currentUrl: ""
    property string _ipcSocket: ""
    property string _lastQuery: ""
    property string _cachedUrl: ""       // persists across enable/disable cycles
    property bool _searchFailed: false
    property int _savedBlurSize: 0       // saved before disabling compositor blur
    property int _pendingSeek: 0         // seek target in seconds (IPC fallback)
    property string _pendingArtist: ""
    property string _pendingTitle: ""
    property bool _wasPlayingBefore: false
    property string _searchingForTrack: ""  // guards stale yt-dlp results after track skip
    property bool _syncInitial: true        // true → first sync uses longer delay for YouTube URL resolution

    // ── Track change detection ──────────────────────────────────────────────

    readonly property var activePlayer: MprisController.activePlayer
    readonly property string currentTrackId: {
        const artist = activePlayer?.trackArtist ?? "";
        const title = activePlayer?.trackTitle ?? "";
        return artist + "|||" + title;
    }

    onCurrentTrackIdChanged: {
        if (!root.enabled)
            return;
        if (currentTrackId === "" || currentTrackId === "|||")
            return;
        // Avoid re-searching the same track
        if (currentTrackId === root._lastQuery)
            return;
        root.searchAndPlay();
    }

    // ── Reliable track change detection ───────────────────────────────────────
    // activeTrack is a property var that gets reassigned on every track change,
    // so activeTrackChanged fires reliably even when the QML binding chain
    // through optional-chaining fails to detect the update.

    Connections {
        target: MprisController
        function onActiveTrackChanged() {
            if (!root.enabled)
                return;
            const track = MprisController.activeTrack;
            if (!track)
                return;
            const newId = (track.artist || "") + "|||" + (track.title || "");
            if (newId === "" || newId === "|||")
                return;
            if (newId === root._lastQuery)
                return;
            root.searchAndPlay();
        }
    }

    // ── Media mode state watcher ────────────────────────────────────────────

    Connections {
        target: GlobalStates
        function onMediaModeActiveChanged() {
            if (!GlobalStates.mediaModeActive) {
                // Media mode closed entirely — kill video
                root.stopVideo();
            } else if (root.enabled && root.currentTrackId !== "" && root.currentTrackId !== root._lastQuery && !root.videoPlaying) {
                // Media mode opened with a new track — search
                root.searchAndPlay();
            }
        }
    }

    // ── Playback sync: pause / resume video with music ───────────────────────

    readonly property bool _playerIsPlaying: root.activePlayer ? (root.activePlayer.isPlaying || root.activePlayer.playbackState === MprisPlaybackState.Playing) : true

    on_PlayerIsPlayingChanged: {
        if (!root.videoPlaying || !root._ipcSocket)
            return;
        if (root._playerIsPlaying) {
            root._resumeMpv();
        } else {
            root._pauseMpv();
        }
    }

    // ── Core: search + play ─────────────────────────────────────────────────

    function searchAndPlay() {
        if (!root.enabled)
            return;
        if (!GlobalStates.mediaModeActive)
            return;

        const artist = root.activePlayer?.trackArtist ?? "";
        const title = root.activePlayer?.trackTitle ?? "";
        if (!title)
            return;

        // Build search query with fallback if first search fails
        const suffix = Config.options.background.mediaMode.musicVideo.searchSuffix ?? "official music video";
        const primaryQuery = artist ? (artist + " - " + title + " " + suffix) : (title + " " + suffix);
        const fallbackQuery = artist ? (artist + " " + title) : title;

        root._lastQuery = root.currentTrackId;
        root._pendingArtist = artist;
        root._pendingTitle = title;
        root._searchFailed = false;

        // Kill any currently playing video + track stale guard
        root.stopVideo();
        root._searchingForTrack = root.currentTrackId;

        // Search yt-dlp asynchronously — try primary query, if empty fallback to artist + title
        const searchScript = `
            ID=$(yt-dlp ytsearch1:${_shellEscape(primaryQuery)} --get-id --no-playlist --socket-timeout 5 --no-warnings 2>/dev/null)
            if [ -z "$ID" ]; then
                ID=$(yt-dlp ytsearch1:${_shellEscape(fallbackQuery)} --get-id --no-playlist --socket-timeout 5 --no-warnings 2>/dev/null)
            fi
            echo "$ID"
        `;

        searchProc.command = ["bash", "-c", searchScript];
        searchProc.running = true;
    }

    function _shellEscape(s) {
        // Escape single quotes for bash -c
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function stopVideo() {
        if (mpvpaperProc.running) {
            mpvpaperProc.running = false;
        }
        // Stop sync timer immediately
        syncTimer.stop();
        // Force-kill immediately any mpvpaper processes using SIGKILL so video drops instantly
        Quickshell.execDetached(["pkill", "-9", "-f", "mpvpaper"]);
        root._currentUrl = "";
        root._searchingForTrack = "";
        // Clean up IPC socket
        if (root._ipcSocket) {
            Quickshell.execDetached(["rm", "-f", root._ipcSocket]);
            root._ipcSocket = "";
        }
    }

    // Used when user toggles the feature ON mid-session
    function tryPlayCurrent() {
        if (!root.enabled)
            return;
        if (!GlobalStates.mediaModeActive)
            return;
        if (root.videoPlaying)
            return;
        if (!root.currentTrackId || root.currentTrackId === "|||")
            return;

        // If we already have a cached URL for this track, reuse it
        if (root.currentTrackId === root._lastQuery && root._cachedUrl !== "") {
            root._searchingForTrack = root.currentTrackId;
            root._launchMpvpaper(root._cachedUrl);
            return;
        }

        root.searchAndPlay();
    }

    // ── Process: yt-dlp search ──────────────────────────────────────────────

    Process {
        id: searchProc
        running: false

        stdout: SplitParser {
            onRead: function (data) {
                // Guard: ignore stale results from a previous track's search
                if (root._searchingForTrack !== root.currentTrackId)
                    return;
                const videoId = String(data).trim();
                // Accept any non-empty video ID (11 chars for standard YT IDs)
                if (videoId.length >= 10) {
                    const youtubeUrl = "https://www.youtube.com/watch?v=" + videoId;
                    root._currentUrl = youtubeUrl;
                    root._cachedUrl = youtubeUrl;
                    root._launchMpvpaper(youtubeUrl);
                }
            }
        }

        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0 || root._currentUrl === "") {
                root._searchFailed = true;
                console.warn("[MusicVideo] yt-dlp search failed for:", root._lastQuery);
            }
        }
    }

    // ── Process: mpvpaper ───────────────────────────────────────────────────

    function _launchMpvpaper(url) {
        // Guard: user may have toggled the feature off while yt-dlp was searching
        if (!root.enabled)
            return;
        // Guard: track may have changed while yt-dlp was searching
        if (root._searchingForTrack !== root.currentTrackId)
            return;

        const monitorName = _getActiveMonitorName();
        if (!monitorName) {
            console.warn("[MusicVideo] No active monitor found, cannot launch mpvpaper");
            root._searchFailed = true;
            return;
        }

        // Unique IPC socket for pause/resume/seek control
        const socketPath = "/tmp/ii-musicvideo.sock";

        // Build mpvpaper command — high quality format & bitrate selection
        const maxRes = Config.options.background.mediaMode.musicVideo.maxResolution ?? 1080;
        const ytdlFormat = "bestvideo[height<=" + maxRes + "][vcodec!=?none]+bestaudio/best[height<=" + maxRes + "]/best";

        // Options passed inside mpvpaper's -o string to mpv:
        const innerMpvOpts = ["--config=no", "aid=no", "no-border", "loop=inf", "no-terminal", "input-ipc-server=" + socketPath, "ytdl-format=" + ytdlFormat].join(" ");

        mpvpaperProc.command = ["mpvpaper", "-l", "background", "-o", innerMpvOpts, monitorName, url];

        mpvpaperProc.running = true;
        root._ipcSocket = socketPath;

        // Launch async sync script (waits for mpv file-loaded event and seeks accurately)
        const scriptPath = Directories.scriptPath + "/music_video/sync.sh";
        Quickshell.execDetached([scriptPath, socketPath]);

        // Periodic sync timer: checks drift between mpv and player position
        syncTimer.interval = 8000;
        syncTimer.restart();

        // Apply pause state immediately (in case music was paused when search finished)
        if (!root._playerIsPlaying) {
            _pauseMpv();
        }
    }

    // ── Track position seeking listener (when user seeks track) ────────────
    readonly property real _playerPositionSec: Math.floor((root.activePlayer?.position ?? 0) / 1000000)

    on_PlayerPositionSecChanged: {
        if (!root.videoPlaying || !root._ipcSocket)
            return;
        // Ignore zero position ticks if player is settling
        if (root._playerPositionSec < 0)
            return;
        // Seek video immediately when user seeks in track
        root._sendMpvCommand('{"command":["seek","' + root._playerPositionSec + '","absolute"]}');
    }

    function _sendMpvCommand(jsonCmd) {
        if (!root._ipcSocket)
            return;
        const escaped = jsonCmd.replace(/'/g, "'\\''");
        Quickshell.execDetached(["bash", "-c", "echo '" + escaped + "' | socat - UNIX-CONNECT:" + root._ipcSocket + " 2>/dev/null"]);
    }

    function _pauseMpv() {
        _sendMpvCommand('{"command":["set_property","pause",true]}');
    }

    function _resumeMpv() {
        _sendMpvCommand('{"command":["set_property","pause",false]}');
    }

    // ── Periodic drift check sync ──────────────────────────────────────────
    // Every 8s, query mpv's time-pos via socat/IPC, calculate drift against player position,
    // and seek mpv if drift > 3 seconds.

    Process {
        id: driftCheckProc
        running: false
        stdout: SplitParser {
            onRead: function (data) {
                try {
                    const res = JSON.parse(String(data).trim());
                    if (res && typeof res.data === "number") {
                        const mpvPos = res.data;
                        const posUs = MprisController.activePlayer?.position ?? 0;
                        const playerPos = Math.floor(posUs / 1000000);
                        const drift = Math.abs(mpvPos - playerPos);

                        if (drift > 3 && playerPos >= 0) {
                            root._sendMpvCommand('{"command":["seek","' + playerPos + '","absolute"]}');
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        id: syncTimer
        interval: 8000
        repeat: true
        running: false
        onTriggered: {
            if (!root._ipcSocket || !root.videoPlaying) {
                syncTimer.stop();
                return;
            }
            if (!(MprisController.activePlayer?.isPlaying ?? false))
                return;

            // Query time-pos from mpv IPC
            const cmd = '{"command":["get_property","time-pos"]}';
            const escaped = cmd.replace(/'/g, "'\\''");
            driftCheckProc.command = ["bash", "-c", "echo '" + escaped + "' | socat - UNIX-CONNECT:" + root._ipcSocket + " 2>/dev/null"];
            driftCheckProc.running = true;
        }
    }

    function _getActiveMonitorName() {
        // Get the focused monitor name via hyprctl
        // This is called synchronously from QML, so we need a pure JS approach
        try {
            const focusedMonitor = Hyprland.focusedMonitor;
            if (focusedMonitor && focusedMonitor.name) {
                return focusedMonitor.name;
            }
        } catch (e) {}
        // Fallback: use first screen
        try {
            if (Quickshell.screens && Quickshell.screens.length > 0) {
                return Quickshell.screens[0].name;
            }
        } catch (e) {}
        return "";
    }

    Process {
        id: mpvpaperProc
        running: false

        onExited: function (exitCode, exitStatus) {
            root._currentUrl = "";
            if (exitCode !== 0 && !root._searchFailed) {
                console.warn("[MusicVideo] mpvpaper exited with code:", exitCode);
                root._searchFailed = true;
            }
        }
    }

    // ── Cleanup ─────────────────────────────────────────────────────────────

    Component.onDestruction: {
        if (mpvpaperProc.running) {
            // Force-kill mpvpaper since Process.stop() might not work on exit
            Quickshell.execDetached(["pkill", "-f", "mpvpaper.*" + (root._currentUrl ? root._currentUrl.substring(0, 30) : "")]);
        }
    }
}
