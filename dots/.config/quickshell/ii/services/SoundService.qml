pragma Singleton
pragma ComponentBehavior: Bound

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
 *    Config.options.sounds[category], rate-limited per category.
 *  - preview(themeId, events): ungated, for the settings page.
 *  - startLoop/stopLoop: continuous ring (alarms); ignores the master switch,
 *    the caller checks its own category toggle.
 */
Singleton {
    id: root

    // [{id, dir, name, comment, inherits}]
    property list<var> themes: []
    property bool indexReady: false
    property var _soundFiles: ({})
    property var _lastPlayed: ({})
    readonly property var _minIntervalMs: ({
        notifications: 500,
        volumeChange: 150,
        screenshot: 300
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
     * `events` is a name or a list of names ordered by preference; each is tried
     * against the theme chain (selected theme, its Inherits, freedesktop).
     */
    function resolve(events, themeId) {
        const names = Array.isArray(events) ? events : [events];
        const chain = root._themeChain(themeId ?? Config.options.sounds.theme);
        for (const name of names) {
            for (const dir of chain) {
                for (const ext of root._extensions) {
                    const path = `${dir}/stereo/${name}.${ext}`;
                    if (root._soundFiles[path]) return "file://" + path;
                }
            }
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

    function playEvent(category, events) {
        if (!Config.options.sounds.enable) return;
        if (!Config.options.sounds[category]) return;

        const now = Date.now();
        const minInterval = root._minIntervalMs[category] ?? 0;
        if (minInterval > 0 && now - (root._lastPlayed[category] ?? 0) < minInterval) return;

        const url = root.resolve(events);
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
        const url = root.resolve(events, themeId);
        if (url !== "") root._playUrl(url);
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
    function startLoop(events) {
        const url = root.resolve(events);
        if (url === "") return;
        loopPlayer.stop();
        loopPlayer.source = url;
        loopPlayer.play();
    }

    function stopLoop() {
        loopPlayer.stop();
    }

    component EventPlayer: MediaPlayer {
        audioOutput: AudioOutput {
            volume: root.volume
        }
    }

    readonly property list<MediaPlayer> playerPool: [player0, player1, player2]
    EventPlayer { id: player0 }
    EventPlayer { id: player1 }
    EventPlayer { id: player2 }

    EventPlayer { id: blipPlayer }

    EventPlayer {
        id: loopPlayer
        loops: MediaPlayer.Infinite
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
