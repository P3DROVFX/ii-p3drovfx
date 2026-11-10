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
 * mode overlay via mpvpaper (wlr_layer_shell), kept in sync with the music.
 *
 * The mode is manual and lasts one Media Mode session: nothing is searched until
 * the user turns it on, and closing Media Mode turns it off again.
 *
 * Lifecycle:
 *   1. start() → search yt-dlp for the current track (async via Process)
 *   2. URL found → launch mpvpaper on the Top layer, paused
 *   3. Pre-roll: seek ahead of the music, wait for the seek to land, unpause at
 *      the exact moment the music reaches that position → videoReady
 *   4. While playing: nudge playback speed for small drift, pre-roll again for big jumps
 *   5. No result, search error, mpvpaper exit or load timeout → stop and emit failed()
 *   6. While on, track changes search again; stop() / Media Mode closing → kill mpvpaper
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

    /// The video is playing in sync with the music; only then may Media Mode show it.
    readonly property bool videoReady: _videoReady && mpvpaperProc.running

    /// Unique socket path for mpv IPC control.
    readonly property string ipcSocket: _ipcSocket
    readonly property string currentVideoUrl: _currentUrl

    /// The search query used for the last search.
    readonly property string lastSearchQuery: _lastQuery

    /// True if the last attempt failed.
    readonly property bool searchFailed: _searchFailed

    /// Last measured video − music offset in seconds (positive: video ahead).
    readonly property real drift: _drift

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
    property int _runningToken: -1
    // Same for searches: stopping a search for a newer track makes the old process
    // exit (SIGTERM) after _searchingForTrack already names the new track.
    property int _searchToken: 0

    readonly property string _socketPath: "/tmp/ii-musicvideo.sock"
    property int _mpvPid: 0

    // ── Sync state ──────────────────────────────────────────────────────────
    // "idle" → "loading" (waiting for the stream) → "seeking" (pre-roll seek in
    // flight) → "waiting" (parked ahead of the music) → "playing".
    property string _syncPhase: "idle"
    /// How far ahead of the music a pre-roll seek aims. Learned from how long
    /// seeks actually take on this stream, so each retry lands closer.
    // Measured on YouTube streams with hr-seek: ~0.3 s once the stream has loaded.
    property real _seekLead: 0.8
    property real _prerollTarget: 0
    property int _prerollAttempts: 0
    property real _videoDuration: 0
    property real _drift: 0
    property real _speed: 1
    property int _requestId: 0
    property var _pending: ({})
    // Music clock: music position = wall clock + _clockOffset, measured by
    // _calibrate(). Unset while paused or after a seek/track change.
    property bool _clockValid: false
    property real _clockOffset: 0
    /// mpv needs a moment to produce frames after unpausing; learned from the first
    /// drift sample after each pre-roll and subtracted from the unpause wait.
    property real _unpauseLag: 0.15
    property bool _awaitLagSample: false

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

    // ── Music clock ─────────────────────────────────────────────────────────

    readonly property bool _playerIsPlaying: root.activePlayer ? (root.activePlayer.isPlaying
                                                                  || root.activePlayer.playbackState
                                                                  === MprisPlaybackState.Playing) : true

    /// Quickshell's own estimate. MprisPlayer.position is only refreshed when
    /// positionChanged() is emitted, so every read asks for a fresh value. It lags
    /// the real position by ~0.2 s and inherits the player's whole-second steps.
    function _playerEstimate() {
        const player = root.activePlayer;
        if (!player)
            return 0;
        player.positionChanged();
        return Math.max(0, Number(player.position) || 0);
    }

    /// Current music position in seconds: the calibrated clock while it is valid,
    /// Quickshell's estimate otherwise.
    function _musicNow() {
        if (root._clockValid && root._playerIsPlaying)
            return Math.max(0, Date.now() / 1000 + root._clockOffset);
        return root._playerEstimate();
    }

    // ── Clock calibration ───────────────────────────────────────────────────
    // YouTube Music (like most browser players) publishes its MPRIS position in
    // whole seconds, updated at uneven moments, so any single reading is up to a
    // second off. A short burst polls the position every ~40 ms and records the
    // wall-clock instant each new second appears; the median of (value − instant)
    // across those steps gives the offset to within a few tens of milliseconds.

    function _calibrate() {
        const busName = String(root.activePlayer?.dbusName ?? "").replace(/^org\.mpris\.MediaPlayer2\./, "");
        if (!root._playerIsPlaying || busName === "") {
            root._clockValid = false;
            return;
        }
        clockProc.running = false;
        clockProc.offsets = [];
        clockProc.command = ["bash", "-c", `
            end=$(( $(date +%s%3N) + 2600 )); last=""
            while [ $(date +%s%3N) -lt $end ]; do
                v=$(playerctl -p "$1" position 2>/dev/null); now=$(date +%s%3N); iv=\${v%%.*}
                if [ -n "$v" ] && [ "$iv" != "$last" ]; then
                    [ -n "$last" ] && echo "$now $v"
                    last=$iv
                fi
                sleep 0.04
            done`, "calibrate", busName];
        clockProc.running = true;
    }

    Process {
        id: clockProc
        property var offsets: []
        stdout: SplitParser {
            onRead: data => {
                const parts = String(data).trim().split(" ");
                if (parts.length === 2)
                    clockProc.offsets.push(Number(parts[1]) - Number(parts[0]) / 1000);
            }
        }
        onExited: {
            const offsets = clockProc.offsets.filter(value => isFinite(value)).sort((a, b) => a - b);
            if (offsets.length > 0 && root._playerIsPlaying) {
                const median = offsets[Math.floor(offsets.length / 2)];
                // A seek or track change during the burst makes the steps disagree with
                // the player; keep the previous state rather than a wrong offset.
                if (Math.abs(Date.now() / 1000 + median - root._playerEstimate()) < 2.5) {
                    root._clockOffset = median;
                    root._clockValid = true;
                }
            }
            if (root._syncPhase === "calibrating")
                root._preroll();
        }
    }

    // Long songs: the player's clock and the wall clock slowly part ways.
    Timer {
        id: recalibrateTimer
        interval: 20000
        repeat: true
        running: root._syncPhase === "playing" && root._playerIsPlaying
        onTriggered: root._calibrate()
    }

    on_PlayerIsPlayingChanged: {
        // The clock is only valid while the music moves.
        root._clockValid = false;
        if (!root.mpvSocket?.connected)
            return;
        if (!root._playerIsPlaying) {
            unpauseTimer.stop();
            root._mpvSet("pause", true);
            root._setSpeed(1);
            if (root._syncPhase === "waiting")
                root._syncPhase = "playing";
            return;
        }
        if (root._syncPhase === "playing") {
            // Both were parked at the same spot: resume together without a frozen
            // frame, and let the drift loop refine once the clock is measured again.
            root._mpvSet("pause", false);
            root._calibrate();
        }
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
            // The kill in _killVideo runs asynchronously; give it time to finish
            // before relaunching.
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

    /// One-line sync diagnostics (for IPC).
    function debugStatus() {
        return `active=${root._active} phase=${root._syncPhase} ready=${root.videoReady} drift=${root._drift.toFixed(3)} speed=${root._speed.toFixed(3)} lead=${root._seekLead.toFixed(2)} lag=${root._unpauseLag.toFixed(2)} clock=${root._clockValid} music=${root._musicNow().toFixed(2)} duration=${root._videoDuration.toFixed(1)}`;
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

        // Six flat results (~2 s, no per-video page fetch) for each query; the best
        // match is chosen in _pickVideo(). Taking only the first result picked lyric
        // videos, live cuts and other tracks by the same artist.
        const printFormat = "%(id)s\t%(duration)s\t%(title)s";
        const searchScript = `
            yt-dlp ytsearch6:${_shellEscape(primaryQuery)} --flat-playlist --print ${_shellEscape(printFormat)} --socket-timeout 5 --no-warnings 2>/dev/null
            echo "@@fallback"
            yt-dlp ytsearch6:${_shellEscape(fallbackQuery)} --flat-playlist --print ${_shellEscape(printFormat)} --socket-timeout 5 --no-warnings 2>/dev/null
        `;

        root._searchToken++;
        searchProc.running = false;
        searchProc.token = root._searchToken;
        searchProc.candidates = [];
        searchProc.fallbackCandidates = [];
        searchProc.inFallback = false;
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
        root._resetSync();
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

    function _normalize(text) {
        return String(text ?? "").toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
            .replace(/\([^)]*\)|\[[^\]]*\]/g, " ").replace(/[^a-z0-9]+/g, "");
    }

    /// Scores search results against the playing track and returns the best id.
    function _pickVideo(candidates, fallbackCandidates) {
        const title = root._normalize(root.activePlayer?.trackTitle);
        const artist = root._normalize((root.activePlayer?.trackArtist ?? "").split(/,|&| feat| ft\.| x /i)[0]);
        const length = Number(root.activePlayer?.length) || 0;
        const seen = {};
        let best = null;
        const all = candidates.concat(fallbackCandidates);
        for (const c of all) {
            if (seen[c.id])
                continue;
            seen[c.id] = true;
            const rawTitle = c.title.toLowerCase();
            const flat = root._normalize(c.title);
            // Must be this song: other results are often the artist's other tracks.
            if (title.length > 0 && !flat.includes(title))
                continue;
            let score = 0;
            if (artist.length > 0 && flat.includes(artist))
                score += 3;
            if (/official (music )?video|\bmusic video\b|\bofficial mv\b|\bm\/?v\b/.test(rawTitle))
                score += 6;
            else if (/\bofficial\b/.test(rawTitle))
                score += 1;
            if (/lyric|letra|audio|visuali[sz]er|karaoke/.test(rawTitle))
                score -= 4;
            if (/\blive\b|concert|festival|glastonbury|session|tour|\bstage\b/.test(rawTitle))
                score -= 5;
            if (/remix|\bedit\b|slowed|sped|reverb|nightcore|8d|cover|reaction|tutorial|instrumental|extended|loop/.test(rawTitle))
                score -= 5;
            if (length > 0 && c.duration > 0) {
                const delta = Math.abs(c.duration - length);
                score += delta <= 8 ? 2 : (delta <= 45 ? 1 : (delta > 150 ? -3 : 0));
            }
            // Earlier results are what YouTube itself ranks higher.
            score -= c.rank * 0.25;
            if (!best || score > best.score)
                best = {
                    id: c.id,
                    score: score,
                    title: c.title
                };
        }
        if (best) {
            console.info("[MusicVideo] picked:", best.title, "score", best.score.toFixed(2));
            return best.id;
        }
        // Nothing matched the title (romanised or stylised names): trust YouTube's order.
        return all.length > 0 ? all[0].id : "";
    }

    Process {
        id: searchProc
        property var candidates: []
        property var fallbackCandidates: []
        property bool inFallback: false
        property int token: -1
        running: false

        stdout: SplitParser {
            onRead: function (data) {
                const line = String(data).trim();
                if (line === "@@fallback") {
                    searchProc.inFallback = true;
                    return;
                }
                const parts = line.split("\t");
                if (parts.length < 3 || parts[0].length < 10)
                    return;
                const list = searchProc.inFallback ? searchProc.fallbackCandidates : searchProc.candidates;
                list.push({
                    id: parts[0],
                    duration: Number(parts[1]) || 0,
                    title: parts.slice(2).join("\t"),
                    rank: list.length
                });
            }
        }

        onExited: function (exitCode, exitStatus) {
            // Stale: a newer search replaced this one, the track changed, or the mode
            // was turned off while searching.
            if (searchProc.token !== root._searchToken || !root._active
                    || root._searchingForTrack !== root.currentTrackId)
                return;
            const videoId = root._pickVideo(searchProc.candidates, searchProc.fallbackCandidates);
            if (videoId === "") {
                console.warn("[MusicVideo] no result for:", root._lastQuery, "exit", exitCode);
                root._fail(Translation.tr("Music video not found"));
                return;
            }
            const youtubeUrl = "https://www.youtube.com/watch?v=" + videoId;
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
        // Starts paused: the pre-roll decides when the first frame may move.
        // hr-seek makes seeks land on the requested time, not the nearest keyframe,
        // and the demuxer cache keeps later corrective seeks local.
        const innerMpvOpts = ["--config=no", "aid=no", "no-border", "loop=inf", "no-terminal", "pause=yes",
                              "hr-seek=yes", "cache=yes", "demuxer-readahead-secs=30", "demuxer-max-back-bytes=64MiB",
                              "input-ipc-server=" + root._socketPath, "ytdl-format=" + ytdlFormat].join(" ");

        root._currentUrl = url;
        root._runningToken = root._launchToken;
        mpvpaperProc.command = ["mpvpaper", "-l", "top", "-o", innerMpvOpts, monitorName, url];
        mpvpaperProc.running = true;
        root._ipcSocket = root._socketPath;

        root._resetSync();
        root._syncPhase = "loading";
        socketRetry.restart();
        readyTimeout.restart();
        // Measure the music clock while the stream loads; both take a few seconds.
        root._calibrate();
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

    // Resolving a YouTube stream can take a while, but not forever.
    Timer {
        id: readyTimeout
        interval: 40000
        onTriggered: {
            if (root._active && !root._videoReady)
                root._fail(Translation.tr("Couldn't load the music video"));
        }
    }

    // ── mpv IPC ─────────────────────────────────────────────────────────────
    // One persistent JSON IPC connection: replies carry request ids, and mpv's
    // own events (playback-restart) say exactly when a seek has landed.

    // A Quickshell Socket that fails to connect (the file does not exist yet) does
    // not retry when `connected` is set again, so the service waits for the socket
    // file and only then creates a fresh Socket that connects on creation.
    property var mpvSocket: null

    Component {
        id: mpvSocketComponent
        Socket {
            parser: SplitParser {
                onRead: data => root._onMpvMessage(data)
            }
            onConnectedChanged: {
                if (connected) {
                    loadPoll.restart();
                } else if (root.mpvSocket === this) {
                    // Lost the connection (mpv restarted or crashed): start over.
                    root._dropSocket();
                    if (root._syncPhase !== "idle")
                        socketRetry.restart();
                }
            }
        }
    }

    function _dropSocket() {
        const socket = root.mpvSocket;
        root.mpvSocket = null;
        if (socket)
            socket.destroy();
    }

    Timer {
        id: socketRetry
        interval: 200
        repeat: true
        onTriggered: {
            if (!mpvpaperProc.running || root.mpvSocket) {
                socketRetry.stop();
                return;
            }
            if (!socketProbe.running)
                socketProbe.running = true;
        }
    }

    Process {
        id: socketProbe
        command: ["test", "-S", root._socketPath]
        onExited: exitCode => {
            if (exitCode !== 0 || root.mpvSocket || !mpvpaperProc.running || root._syncPhase === "idle")
                return;
            socketRetry.stop();
            root.mpvSocket = mpvSocketComponent.createObject(root, {
                path: root._socketPath,
                connected: true
            });
        }
    }

    function _mpvRequest(command, callback) {
        const socket = root.mpvSocket;
        if (!socket || !socket.connected)
            return;
        const id = ++root._requestId;
        if (callback)
            root._pending[id] = callback;
        socket.write(JSON.stringify({
            command: command,
            request_id: id
        }) + "\n");
        socket.flush();
    }

    function _mpvSet(name, value) {
        root._mpvRequest(["set_property", name, value], null);
    }

    function _setSpeed(speed) {
        if (Math.abs(speed - root._speed) < 0.001)
            return;
        root._speed = speed;
        root._mpvSet("speed", speed);
    }

    function _onMpvMessage(line) {
        let message;
        try {
            message = JSON.parse(String(line));
        } catch (e) {
            return;
        }
        if (message.request_id !== undefined && root._pending[message.request_id]) {
            const callback = root._pending[message.request_id];
            delete root._pending[message.request_id];
            callback(message);
            return;
        }
        if (message.event === "playback-restart")
            root._onSeekLanded();
    }

    function _resetSync() {
        root._syncPhase = "idle";
        root._prerollAttempts = 0;
        root._videoDuration = 0;
        root._drift = 0;
        root._speed = 1;
        root._pending = ({});
        root._clockValid = false;
        root._awaitLagSample = false;
        clockProc.running = false;
        socketRetry.stop();
        loadPoll.stop();
        unpauseTimer.stop();
        driftTimer.stop();
        readyTimeout.stop();
        root._dropSocket();
    }

    // Waits until the stream has a duration, i.e. mpv can seek in it.
    Timer {
        id: loadPoll
        interval: 250
        repeat: true
        onTriggered: {
            if (root._syncPhase !== "loading") {
                loadPoll.stop();
                return;
            }
            root._mpvRequest(["get_property", "duration"], reply => {
                if (root._syncPhase !== "loading" || reply.error !== "success" || typeof reply.data !== "number")
                    return;
                loadPoll.stop();
                root._videoDuration = reply.data;
                if (clockProc.running && root._playerIsPlaying)
                    root._syncPhase = "calibrating"; // clockProc.onExited pre-rolls
                else
                    root._preroll();
            });
        }
    }

    // ── Pre-roll: land exactly on the music's clock ─────────────────────────

    function _targetFor(musicPosition) {
        // A video shorter than the song loops (loop=inf); follow it around.
        if (root._videoDuration > 1 && musicPosition >= root._videoDuration)
            return musicPosition % root._videoDuration;
        return musicPosition;
    }

    function _preroll() {
        unpauseTimer.stop();
        driftTimer.stop();
        root._setSpeed(1);
        root._mpvSet("pause", true);
        const music = root._musicNow();
        // Music paused: just match it and wait for playback to resume.
        root._prerollTarget = root._targetFor(root._playerIsPlaying ? music + root._seekLead : music);
        root._syncPhase = "seeking";
        root._mpvRequest(["seek", root._prerollTarget, "absolute+exact"], null);
    }

    function _onSeekLanded() {
        if (root._syncPhase !== "seeking")
            return;
        if (!root._playerIsPlaying) {
            // Parked on the music's paused position; reveal the frame.
            root._syncPhase = "playing";
            root._reveal();
            return;
        }
        const music = root._targetFor(root._musicNow());
        const wait = root._prerollTarget - music;
        // Learn the real seek latency: it took (lead − wait) seconds this time.
        const latency = Math.max(0, root._seekLead - wait);
        if (wait >= 0.02) {
            root._seekLead = Math.max(0.4, Math.min(8, latency * 1.25 + 0.25));
            const unpauseIn = wait - root._unpauseLag;
            if (unpauseIn <= 0.01) {
                root._startPlaying();
                return;
            }
            root._syncPhase = "waiting";
            unpauseTimer.interval = Math.round(unpauseIn * 1000);
            unpauseTimer.restart();
            return;
        }
        // Landed behind the music: aim further ahead and try again.
        root._seekLead = Math.max(0.4, Math.min(8, latency * 1.5 + 0.5));
        root._prerollAttempts++;
        if (root._prerollAttempts > 4) {
            // Keep going; the drift loop finishes the job with speed changes.
            root._startPlaying();
            return;
        }
        root._preroll();
    }

    Timer {
        id: unpauseTimer
        onTriggered: root._startPlaying()
    }

    function _startPlaying() {
        root._prerollAttempts = 0;
        root._syncPhase = "playing";
        root._awaitLagSample = root._playerIsPlaying && root._clockValid;
        if (root._playerIsPlaying)
            root._mpvSet("pause", false);
        root._reveal();
        driftTimer.restart();
    }

    function _reveal() {
        readyTimeout.stop();
        root._videoReady = true;
    }

    // ── Continuous correction ───────────────────────────────────────────────
    // Small drift is absorbed by a gentle speed change, so the picture never
    // jumps; a big one (the user seeked in the music) pre-rolls again.

    Timer {
        id: driftTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root._syncPhase !== "playing" || !root._playerIsPlaying)
                return;
            // A seek in the music moves the player away from the calibrated clock.
            if (root._clockValid && Math.abs(root._musicNow() - root._playerEstimate()) > 2) {
                root._clockValid = false;
                root._calibrate();
            }
            // Without a measured clock, corrections would chase the player's
            // whole-second steps; wait for the calibration to finish.
            if (!root._clockValid)
                return;
            root._mpvRequest(["get_property", "time-pos"], reply => {
                if (root._syncPhase !== "playing" || reply.error !== "success" || typeof reply.data !== "number")
                    return;
                const music = root._targetFor(root._musicNow());
                let drift = reply.data - music;
                // Around the loop point both clocks wrap at different moments.
                if (root._videoDuration > 1 && Math.abs(drift) > root._videoDuration / 2)
                    drift -= Math.sign(drift) * root._videoDuration;
                root._drift = drift;
                if (root._awaitLagSample) {
                    // Behind right after a pre-roll: unpause that much earlier next time.
                    root._awaitLagSample = false;
                    if (Math.abs(drift) < 1)
                        root._unpauseLag = Math.max(0, Math.min(0.8, root._unpauseLag - drift * 0.8));
                }
                if (Math.abs(drift) > 1.5) {
                    root._preroll();
                } else if (Math.abs(drift) > 0.06) {
                    // Close ~40% of the gap per second, never faster than ±15%.
                    root._setSpeed(Math.max(0.85, Math.min(1.15, 1 - drift * 0.4)));
                } else {
                    root._setSpeed(1);
                }
            });
        }
    }

    function _pauseMpv() {
        root._mpvSet("pause", true);
    }

    function _resumeMpv() {
        root._mpvSet("pause", false);
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
