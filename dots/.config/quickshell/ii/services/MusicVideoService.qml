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
 * Searches YouTube for music videos via yt-dlp and plays them behind the media
 * mode overlay via mpvpaper (wlr_layer_shell).
 *
 * The mode is manual and lasts one Media Mode session: nothing is searched until
 * the user turns it on, and closing Media Mode turns it off again.
 *
 * Lifecycle:
 *   1. start() → search yt-dlp for the current track (async via Process)
 *   2. URL found → launch mpvpaper on the Top layer
 *   3. mpv reports a playback position → videoReady (Media Mode may now go transparent)
 *   4. No result, search error, mpvpaper exit or load timeout → stop and emit failed()
 *   5. While on, track changes search again; stop() / Media Mode closing → kill mpvpaper
 *
 * mpvpaper runs on the Top layer, above application windows and below the
 * Overlay-layer Media Mode surface. On the Background layer the video sat under
 * every window, so the transparent overlay showed the desktop's programs.
 */
Singleton {
    id: root

    // ── Public API ──────────────────────────────────────────────────────────

    /// The user has turned the music video background on for this Media Mode session.
    readonly property bool active: _active

    /// Searching or loading: the overlay must stay opaque until videoReady.
    readonly property bool searching: _active && !_videoReady

    /// True while the mpvpaper process is running.
    readonly property bool videoPlaying: mpvpaperProc.running

    /// mpv is actually playing frames; only then may Media Mode show the video.
    readonly property bool videoReady: _videoReady && mpvpaperProc.running

    /// Unique socket path for mpv IPC control.
    readonly property string ipcSocket: _ipcSocket
    readonly property string currentVideoUrl: _currentUrl

    /// The search query used for the last search.
    readonly property string lastSearchQuery: _lastQuery

    /// True if the last attempt failed.
    readonly property bool searchFailed: _searchFailed

    /// Emitted with a short, user-facing message when the mode turns itself off.
    signal failed(string message)

    // ── Internal state ──────────────────────────────────────────────────────

    property bool _active: false
    property bool _videoReady: false
    property string _currentUrl: ""
    property string _ipcSocket: ""
    property string _lastQuery: ""
    property string _cachedQuery: ""
    property string _cachedUrl: ""
    property bool _searchFailed: false
    property string _searchingForTrack: ""  // guards stale yt-dlp results after track skip
    // Incremented on every launch/stop so exits of a killed mpvpaper are not
    // mistaken for failures of the current one.
    property int _launchToken: 0
    // Same for searches: stopping a search for a newer track makes the old process
    // exit (SIGTERM) after _searchingForTrack already names the new track.
    property int _searchToken: 0
    property int _runningToken: -1

    readonly property string _socketPath: "/tmp/ii-musicvideo.sock"
    property int _mpvPid: 0

    // Kills only the mpvpaper this service launched. A `pkill -f` on a loose
    // pattern also matches any other command line that merely mentions it (a
    // shell running a script, an editor, grep) and killed those instead.
    function _killMpvpaper() {
        if (root._mpvPid > 0)
            Quickshell.execDetached(["kill", "-9", String(root._mpvPid)]);
        // mpvpaper does not always die with its Process; the pattern is anchored to
        // the start of the command line, so it can only match mpvpaper itself.
        Quickshell.execDetached(["pkill", "-9", "-f", "^(/usr/bin/)?mpvpaper .*ii-musicvideo"]);
        root._mpvPid = 0;
    }

    // ── Track change detection ──────────────────────────────────────────────

    readonly property var activePlayer: MprisController.activePlayer
    readonly property string currentTrackId: {
        const artist = activePlayer?.trackArtist ?? "";
        const title = activePlayer?.trackTitle ?? "";
        return artist + "|||" + title;
    }

    function _followTrack(trackId) {
        if (!root._active)
            return;
        if (trackId === "" || trackId === "|||" || trackId === root._lastQuery)
            return;
        root.searchAndPlay();
    }

    onCurrentTrackIdChanged: root._followTrack(root.currentTrackId)

    // activeTrack is reassigned on every track change, so this fires reliably even
    // when the binding chain through optional chaining misses an update.
    Connections {
        target: MprisController
        function onActiveTrackChanged() {
            const track = MprisController.activeTrack;
            if (!track)
                return;
            root._followTrack((track.artist || "") + "|||" + (track.title || ""));
        }
    }

    // ── Media mode state watcher ────────────────────────────────────────────

    Connections {
        target: GlobalStates
        function onMediaModeActiveChanged() {
            // Manual per session: never start on open, always end on close.
            if (!GlobalStates.mediaModeActive)
                root.stop();
        }
    }

    // ── Playback sync: pause / resume video with music ───────────────────────

    readonly property bool _playerIsPlaying: root.activePlayer ? (root.activePlayer.isPlaying
                                                                  || root.activePlayer.playbackState
                                                                  === MprisPlaybackState.Playing) : true

    on_PlayerIsPlayingChanged: {
        if (!root.videoPlaying || !root._ipcSocket)
            return;
        if (root._playerIsPlaying)
            root._resumeMpv();
        else
            root._pauseMpv();
    }

    // ── Public controls ─────────────────────────────────────────────────────

    /// Turns the music video background on and searches for the current track.
    function start() {
        if (!GlobalStates.mediaModeActive)
            return;
        if (!root.activePlayer?.trackTitle) {
            root._fail(Translation.tr("Music video not found"));
            return;
        }
        root._active = true;
        root._searchFailed = false;
        if (root.currentTrackId === root._cachedQuery && root._cachedUrl !== "") {
            root._lastQuery = root.currentTrackId;
            root._killVideo();
            root._searchingForTrack = root.currentTrackId;
            // The pkill in _killVideo runs asynchronously and matches the new process
            // too; give it time to finish before relaunching.
            cachedLaunchDelay.restart();
            return;
        }
        root.searchAndPlay();
    }

    /// Turns the music video background off and returns Media Mode to its normal look.
    function stop() {
        root._active = false;
        root._searchToken++;
        searchProc.running = false;
        root._killVideo();
    }

    function toggle() {
        if (root._active)
            root.stop();
        else
            root.start();
    }

    // Kept for existing callers.
    function tryPlayCurrent() {
        root.start();
    }
    function stopVideo() {
        root.stop();
    }

    // ── Core: search + play ─────────────────────────────────────────────────

    function searchAndPlay() {
        if (!root._active || !GlobalStates.mediaModeActive)
            return;

        const artist = root.activePlayer?.trackArtist ?? "";
        const title = root.activePlayer?.trackTitle ?? "";
        if (!title) {
            root._fail(Translation.tr("Music video not found"));
            return;
        }

        // Build search query with fallback if first search fails
        const suffix = Config.options.background.mediaMode.musicVideo.searchSuffix ?? "official music video";
        const primaryQuery = artist ? (artist + " - " + title + " " + suffix) : (title + " " + suffix);
        const fallbackQuery = artist ? (artist + " " + title) : title;

        root._lastQuery = root.currentTrackId;
        root._searchFailed = false;

        // Kill any currently playing video; the overlay goes opaque until the new one plays.
        root._killVideo();
        root._searchingForTrack = root.currentTrackId;

        const searchScript = `
            ID=$(yt-dlp ytsearch1:${_shellEscape(primaryQuery)} --get-id --no-playlist --socket-timeout 5 --no-warnings 2>/dev/null)
            if [ -z "$ID" ]; then
                ID=$(yt-dlp ytsearch1:${_shellEscape(fallbackQuery)} --get-id --no-playlist --socket-timeout 5 --no-warnings 2>/dev/null)
            fi
            echo "$ID"
        `;

        root._searchToken++;
        searchProc.running = false;
        searchProc.token = root._searchToken;
        searchProc.foundId = "";
        searchProc.command = ["bash", "-c", searchScript];
        searchProc.running = true;
    }

    function _shellEscape(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function _killVideo() {
        root._launchToken++;
        cachedLaunchDelay.stop();
        root._videoReady = false;
        readyTimeout.stop();
        readyPoll.stop();
        syncTimer.stop();
        if (mpvpaperProc.running)
            mpvpaperProc.running = false;
        root._killMpvpaper();
        root._currentUrl = "";
        root._searchingForTrack = "";
        if (root._ipcSocket) {
            Quickshell.execDetached(["rm", "-f", root._ipcSocket]);
            root._ipcSocket = "";
        }
    }

    function _fail(message) {
        const wasActive = root._active;
        root._searchFailed = true;
        root.stop();
        if (wasActive || message)
            root.failed(message);
    }

    Timer {
        id: cachedLaunchDelay
        interval: 350
        onTriggered: root._launchMpvpaper(root._cachedUrl)
    }

    // ── Process: yt-dlp search ──────────────────────────────────────────────

    Process {
        id: searchProc
        property string foundId: ""
        property int token: -1
        running: false

        stdout: SplitParser {
            onRead: function (data) {
                const videoId = String(data).trim();
                if (videoId.length >= 10)
                    searchProc.foundId = videoId;
            }
        }

        onExited: function (exitCode, exitStatus) {
            // Stale: a newer search replaced this one, the track changed, or the mode
            // was turned off while searching.
            if (searchProc.token !== root._searchToken || !root._active
                    || root._searchingForTrack !== root.currentTrackId)
                return;
            if (searchProc.foundId === "") {
                console.warn("[MusicVideo] no result for:", root._lastQuery, "exit", exitCode);
                root._fail(Translation.tr("Music video not found"));
                return;
            }
            const youtubeUrl = "https://www.youtube.com/watch?v=" + searchProc.foundId;
            root._cachedQuery = root._searchingForTrack;
            root._cachedUrl = youtubeUrl;
            root._launchMpvpaper(youtubeUrl);
        }
    }

    // ── Process: mpvpaper ───────────────────────────────────────────────────

    function _launchMpvpaper(url) {
        if (!root._active || root._searchingForTrack !== root.currentTrackId)
            return;

        const monitorName = _getActiveMonitorName();
        if (!monitorName) {
            console.warn("[MusicVideo] No active monitor found, cannot launch mpvpaper");
            root._fail(Translation.tr("Couldn't load the music video"));
            return;
        }

        const maxRes = Config.options.background.mediaMode.musicVideo.maxResolution ?? 1080;
        const ytdlFormat = "bestvideo[height<=" + maxRes + "][vcodec!=?none]+bestaudio/best[height<=" + maxRes
                + "]/best";
        const innerMpvOpts = ["--config=no", "aid=no", "no-border", "loop=inf", "no-terminal", "input-ipc-server="
                              + root._socketPath, "ytdl-format=" + ytdlFormat].join(" ");

        root._currentUrl = url;
        root._runningToken = root._launchToken;
        mpvpaperProc.command = ["mpvpaper", "-l", "top", "-o", innerMpvOpts, monitorName, url];
        mpvpaperProc.running = true;
        root._ipcSocket = root._socketPath;

        // Waits for mpv's file-loaded event and seeks to the player position.
        Quickshell.execDetached([Directories.scriptPath + "/music_video/sync.sh", root._socketPath]);

        readyPoll.restart();
        readyTimeout.restart();
    }

    Process {
        id: mpvpaperProc
        running: false
        onRunningChanged: if (running)
                              root._mpvPid = processId ?? 0

        onExited: function (exitCode, exitStatus) {
            // Killed on purpose (stop, next track): nothing to report.
            if (root._runningToken !== root._launchToken || !root._active)
                return;
            console.warn("[MusicVideo] mpvpaper exited with code:", exitCode);
            root._fail(Translation.tr("Couldn't load the music video"));
        }
    }

    // ── Readiness: wait for real playback before revealing the video ─────────

    Timer {
        id: readyPoll
        interval: 400
        repeat: true
        onTriggered: {
            if (!mpvpaperProc.running || readyProc.running)
                return;
            readyProc.command = ["bash", "-c", "echo '{\"command\":[\"get_property\",\"playback-time\"]}' | socat - UNIX-CONNECT:"
                                 + root._socketPath + " 2>/dev/null"];
            readyProc.running = true;
        }
    }

    Process {
        id: readyProc
        running: false
        stdout: SplitParser {
            onRead: function (data) {
                try {
                    const res = JSON.parse(String(data).trim());
                    if (res && res.error === "success" && typeof res.data === "number") {
                        readyPoll.stop();
                        readyTimeout.stop();
                        root._videoReady = true;
                        if (!root._playerIsPlaying)
                            root._pauseMpv();
                        syncTimer.restart();
                    }
                } catch (e) {}
            }
        }
    }

    // Resolving a YouTube stream can take a while, but not forever.
    Timer {
        id: readyTimeout
        interval: 30000
        onTriggered: {
            if (root._active && !root._videoReady)
                root._fail(Translation.tr("Couldn't load the music video"));
        }
    }

    // ── Track position seeking listener (when user seeks track) ────────────
    readonly property real _playerPositionSec: Math.floor((root.activePlayer?.position ?? 0) / 1000000)

    on_PlayerPositionSecChanged: {
        if (!root.videoReady || !root._ipcSocket)
            return;
        if (root._playerPositionSec < 0)
            return;
        root._sendMpvCommand('{"command":["seek","' + root._playerPositionSec + '","absolute"]}');
    }

    function _sendMpvCommand(jsonCmd) {
        if (!root._ipcSocket)
            return;
        const escaped = jsonCmd.replace(/'/g, "'\\''");
        Quickshell.execDetached(["bash", "-c", "echo '" + escaped + "' | socat - UNIX-CONNECT:" + root._ipcSocket
                                 + " 2>/dev/null"]);
    }

    function _pauseMpv() {
        _sendMpvCommand('{"command":["set_property","pause",true]}');
    }

    function _resumeMpv() {
        _sendMpvCommand('{"command":["set_property","pause",false]}');
    }

    // ── Periodic drift check sync ──────────────────────────────────────────
    // Every 8s, compare mpv's time-pos with the player and seek if drift > 3s.

    Process {
        id: driftCheckProc
        running: false
        stdout: SplitParser {
            onRead: function (data) {
                try {
                    const res = JSON.parse(String(data).trim());
                    if (res && typeof res.data === "number") {
                        const playerPos = Math.floor((MprisController.activePlayer?.position ?? 0) / 1000000);
                        if (Math.abs(res.data - playerPos) > 3 && playerPos >= 0)
                            root._sendMpvCommand('{"command":["seek","' + playerPos + '","absolute"]}');
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
            driftCheckProc.command = ["bash", "-c", "echo '{\"command\":[\"get_property\",\"time-pos\"]}' | socat - UNIX-CONNECT:"
                                      + root._ipcSocket + " 2>/dev/null"];
            driftCheckProc.running = true;
        }
    }

    function _getActiveMonitorName() {
        try {
            const focusedMonitor = Hyprland.focusedMonitor;
            if (focusedMonitor && focusedMonitor.name)
                return focusedMonitor.name;
        } catch (e) {}
        try {
            if (Quickshell.screens && Quickshell.screens.length > 0)
                return Quickshell.screens[0].name;
        } catch (e) {}
        return "";
    }

    // ── Cleanup ─────────────────────────────────────────────────────────────

    Component.onDestruction: {
        if (mpvpaperProc.running)
            root._killMpvpaper();
    }
}
