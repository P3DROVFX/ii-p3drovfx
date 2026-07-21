pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

/**
 * XDG sound theme event player (freedesktop sound theme & naming specs, simplified).
 *
 * Discovers themes from /usr/share/sounds and ~/.local/share/sounds, resolves
 * event names against the configured theme with fallback to inherited themes
 * and freedesktop, and plays them in-process through Qt Multimedia.
 *
 * Playback entry points:
 *  - playEvent(category, events): gated by Config.options.sounds.enable and
 *    Config.options.sounds[category], rate-limited per category, honors
 *    per-event custom file overrides (Config.options.sounds.custom).
 *  - preview(themeId, events): ungated, for the settings page. Resolves
 *    theme-first so each card demos its own sounds, and repeats very short
 *    samples so they're actually audible.
 *  - startLoop/stopLoop: continuous ring (alarms); ignores the master switch,
 *    the caller checks its own category toggle. Supports gentle fade-in.
 */
Singleton {
    id: root

    // [{id, dir, name, comment, inherits}]
    property list<var> themes: []
    property bool indexReady: false
    property var _soundFiles: ({})
    property var _lastPlayed: ({})
    readonly property real _initTime: Date.now()
    readonly property var _minIntervalMs: ({
        notifications: 500,
        volumeChange: 150,
        screenshot: 300,
        devices: 1000
    })
    // Suppress categories that misfire while services settle on startup:
    // UPower flips isPluggedIn once real values arrive, Bluetooth/KDE Connect
    // report already-connected devices as "new", lock-on-startup engages late.
    readonly property var _startupGraceMs: ({
        battery: 5000,
        devices: 10000,
        lock: 10000
    })

    readonly property real volume: (Config.options.sounds.volume ?? 100) / 100
    readonly property list<string> _extensions: ["oga", "ogg", "wav"]

    function rescan() {
        root.indexReady = false;
        themeScanProc.running = true;
        fileScanProc.running = true;
    }

    Component.onCompleted: rescan()

    /**
     * Resolve event names to a playable file url.
     * `events` is a name or a list of names ordered by preference.
     * Default order tries each event name across the whole theme chain
     * (selected theme, its Inherits, freedesktop) — right for real playback
     * where the event's meaning matters most. With themeFirst, each theme is
     * exhausted before falling back — right for previews, where hearing the
     * card's own theme matters most.
     */
    // Lists that cross the QML boundary (Repeater models, list properties)
    // arrive as QVariantList sequences where Array.isArray is false, so
    // normalize by shape instead.
    function _toNames(events) {
        return typeof events === "string" ? [events] : Array.from(events);
    }

    function resolve(events, themeId, themeFirst) {
        const names = root._toNames(events);
        const chain = root._themeChain(themeId ?? Config.options.sounds.theme);
        if (themeFirst) {
            for (const dir of chain) {
                for (const name of names) {
                    const url = root._fileUrl(dir, name);
                    if (url !== "") return url;
                }
            }
        } else {
            for (const name of names) {
                for (const dir of chain) {
                    const url = root._fileUrl(dir, name);
                    if (url !== "") return url;
                }
            }
        }
        return "";
    }

    function _fileUrl(dir, name) {
        for (const ext of root._extensions) {
            const path = `${dir}/stereo/${name}.${ext}`;
            if (root._soundFiles[path]) return "file://" + path;
        }
        return "";
    }

    function _themeChain(themeId) {
        const dirs = [];
        const visited = {};
        const queue = [themeId];
        while (queue.length > 0) {
            const id = queue.shift();
            if (!id || visited[id]) continue;
            visited[id] = true;
            const theme = root.themes.find(t => t.id === id);
            dirs.push(theme?.dir ?? `/usr/share/sounds/${id}`);
            if (theme?.inherits) queue.push(...theme.inherits.split(",").map(s => s.trim()));
        }
        if (!visited["freedesktop"]) dirs.push("/usr/share/sounds/freedesktop");
        return dirs;
    }

    /** True if the theme itself ships any of these event sounds (no fallback). */
    function hasOwnSound(themeId, events) {
        const names = root._toNames(events);
        const theme = root.themes.find(t => t.id === themeId);
        const dir = theme?.dir ?? `/usr/share/sounds/${themeId}`;
        return names.some(name => root._fileUrl(dir, name) !== "");
    }

    /** Number of sound files a theme ships. */
    function soundCount(themeId) {
        const theme = root.themes.find(t => t.id === themeId);
        const dir = (theme?.dir ?? `/usr/share/sounds/${themeId}`) + "/";
        return Object.keys(root._soundFiles).filter(path => path.startsWith(dir)).length;
    }

    function _customUrl(category) {
        const custom = Config.options.sounds.custom[category] ?? "";
        if (custom === "") return "";
        return custom.startsWith("file://") ? custom : "file://" + custom;
    }

    function playEvent(category, events) {
        if (!Config.options.sounds.enable) return;
        if (!Config.options.sounds[category]) return;

        const now = Date.now();
        if (now - root._initTime < (root._startupGraceMs[category] ?? 0)) return;
        const minInterval = root._minIntervalMs[category] ?? 0;
        if (minInterval > 0 && now - (root._lastPlayed[category] ?? 0) < minInterval) return;

        const url = root._customUrl(category) || root.resolve(events);
        if (url === "") return;
        root._lastPlayed[category] = now;
        // Volume blips restart a dedicated player: rapid changes cut the
        // previous tick short instead of stacking overlapping ones.
        root._playUrl(url, category === "volumeChange" ? blipPlayer : null);
    }

    function playEventFile(category, path) {
        if (!Config.options.sounds.enable) return;
        if (!Config.options.sounds[category]) return;
        root._playUrl(path.startsWith("file://") ? path : "file://" + path);
    }

    function preview(themeId, events) {
        const url = root.resolve(events, themeId, true);
        if (url !== "") root._playUrl(url, previewPlayer);
    }

    function previewFile(path) {
        if (!path) return;
        root._playUrl(path.startsWith("file://") ? path : "file://" + path, previewPlayer);
    }

    property int _poolIndex: 0
    function _playUrl(url, dedicatedPlayer) {
        let player = dedicatedPlayer;
        if (!player) {
            player = playerPool[root._poolIndex];
            root._poolIndex = (root._poolIndex + 1) % playerPool.length;
        }
        player.stop();
        player.source = url;
        player.play();
    }

    // Continuous ring for alarms; bypasses the master switch on purpose:
    // disabling UI blips shouldn't silence a wake-up alarm.
    // fadeSeconds > 0 ramps the volume from silent for a gentle wake.
    function startLoop(category, events, fadeSeconds) {
        const url = root._customUrl(category) || root.resolve(events);
        if (url === "") return;
        loopFadeAnim.stop();
        loopPlayer.stop();
        loopPlayer.volumeScale = 1;
        if (fadeSeconds > 0) {
            loopPlayer.volumeScale = 0;
            loopFadeAnim.duration = fadeSeconds * 1000;
            loopFadeAnim.start();
        }
        loopPlayer.source = url;
        loopPlayer.play();
    }

    function stopLoop() {
        loopFadeAnim.stop();
        loopPlayer.stop();
    }

    MediaDevices {
        id: mediaDevices
    }

    component EventPlayer: MediaPlayer {
        id: eventPlayer

        property real volumeScale: 1

        audioOutput: AudioOutput {
            // Explicitly follow the system default so event sounds move with
            // output switches instead of sticking to the device at creation.
            device: mediaDevices.defaultAudioOutput
            volume: root.volume * eventPlayer.volumeScale
        }
    }

    readonly property list<MediaPlayer> playerPool: [player0, player1, player2]
    EventPlayer { id: player0 }
    EventPlayer { id: player1 }
    EventPlayer { id: player2 }

    EventPlayer { id: blipPlayer }

    EventPlayer {
        id: previewPlayer

        // Sub-150ms samples (like FreeDesktop's 67ms volume tick) are nearly
        // imperceptible as a one-shot preview — repeat them a few times.
        onDurationChanged: loops = (duration > 0 && duration < 150) ? 3 : 1
    }

    EventPlayer {
        id: loopPlayer
        loops: MediaPlayer.Infinite
    }

    NumberAnimation {
        id: loopFadeAnim
        target: loopPlayer
        property: "volumeScale"
        from: 0
        to: 1
        easing.type: Easing.InQuad
    }

    // Screen lock/unlock. No mainstream theme ships screen-locked/unlocked
    // sounds, so the service login/logout pair acts as the audible fallback.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            root.playEvent("lock", GlobalStates.screenLocked
                ? ["screen-locked", "service-logout"]
                : ["screen-unlocked", "service-login"]);
        }
    }

    // Login sound: PersistentProperties survives QML live-reloads within the
    // same process, so this only fires once per shell process (= per session).
    PersistentProperties {
        id: session
        reloadableId: "soundServiceSession"
        property bool loginSoundPlayed: false
    }

    function _maybePlayLoginSound() {
        if (session.loginSoundPlayed || !root.indexReady || !Config.ready) return;
        session.loginSoundPlayed = true;
        root.playEvent("session", ["desktop-login", "service-login"]);
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root._maybePlayLoginSound();
        }
    }

    // ── Theme installation ────────────────────────────────────────────────
    signal installFinished(bool success, string message)

    function installFromArchive(archivePath) {
        if (installProc.running) return;
        installProc.archivePath = archivePath.startsWith("file://") ? archivePath.substring(7) : archivePath;
        installProc.running = true;
    }

    Process {
        id: installProc
        property string archivePath: ""
        command: ["bash", "-c", `
            set -e
            dest="$HOME/.local/share/sounds"
            mkdir -p "$dest"
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            bsdtar -xf "$1" -C "$tmp"
            found=""
            if [ -f "$tmp/index.theme" ]; then
                name=$(basename "$1"); name="\${name%%.tar*}"; name="\${name%.zip}"
                mkdir -p "$dest/$name"
                cp -a "$tmp"/. "$dest/$name/"
                found="$name"
            else
                for d in "$tmp"/*/; do
                    [ -f "$d/index.theme" ] || continue
                    cp -a "$d" "$dest/"
                    found="$found $(basename "$d")"
                done
            fi
            [ -n "$found" ] || { echo "NO_THEME"; exit 1; }
            echo "OK$found"
        `, "--", installProc.archivePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out.startsWith("OK")) {
                    root.rescan();
                    root.installFinished(true, Translation.tr("Installed: %1").arg(out.substring(2).trim()));
                } else {
                    root.installFinished(false, Translation.tr("No sound theme (index.theme) found in archive"));
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.installFinished(false, Translation.tr("Extraction failed — is the archive valid?"));
            }
        }
    }

    // ── Theme discovery ───────────────────────────────────────────────────
    Process {
        id: themeScanProc
        command: ["bash", "-c", `
            for dir in /usr/share/sounds/* "$HOME/.local/share/sounds"/*; do
                [ -f "$dir/index.theme" ] || continue
                grep -q '^Hidden=true' "$dir/index.theme" && continue
                jq -n --arg id "$(basename "$dir")" --arg dir "$dir" \
                    --arg name "$(sed -n 's/^Name=//p' "$dir/index.theme" | head -1)" \
                    --arg comment "$(sed -n 's/^Comment=//p' "$dir/index.theme" | head -1)" \
                    --arg inherits "$(sed -n 's/^Inherits=//p' "$dir/index.theme" | head -1)" \
                    '{id: $id, dir: $dir, name: (if $name == "" then $id else $name end), comment: $comment, inherits: $inherits}'
            done | jq -s 'sort_by(.name)'
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // The freedesktop index.theme just says "Name=Default"; label
                    // it like KDE does so users recognize it as the fallback theme.
                    root.themes = JSON.parse(text).map(t => t.id === "freedesktop" ? Object.assign({}, t, {
                        name: "FreeDesktop",
                        comment: Translation.tr("Fallback sound theme from freedesktop.org")
                    }) : t);
                } catch (e) {
                    console.warn("[SoundService] Failed to parse theme list:", e);
                }
            }
        }
    }

    Process {
        id: fileScanProc
        command: ["bash", "-c", `find -L /usr/share/sounds "$HOME/.local/share/sounds" -maxdepth 3 -type f \\( -name '*.oga' -o -name '*.ogg' -o -name '*.wav' \\) 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const files = {};
                for (const line of text.split("\n")) {
                    if (line !== "") files[line] = true;
                }
                root._soundFiles = files;
                root.indexReady = true;
                root._maybePlayLoginSound();
            }
        }
    }
}
