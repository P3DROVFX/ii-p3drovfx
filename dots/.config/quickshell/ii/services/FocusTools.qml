pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

/**
 * What the focus actions of Modes & Routines run on, beyond the app/site blocks
 * (those live in ScreenTimeLimits):
 *
 *   - media guards: while one is set, any playing MPRIS player that is neither an
 *     allowed player nor the ambient sound is paused, with a notification;
 *   - the ambient sound, either a browser tab (handed to the default browser) or
 *     audio only (mpv + yt-dlp, outside the shell, tracked by a pid file so it
 *     survives a reload and is stopped by the mode's revert);
 *   - browser extensions: scripts/modes/browser_extension.py checks the default
 *     browser has one and offers a button that opens it (or its store page).
 *
 * Nothing here is persisted: the engine re-applies the volatile actions after a reload.
 */
Singleton {
    id: root

    /// id → { name, allowPlayers: [], allowTitles: [] }
    property var guards: ({})
    readonly property bool guarding: Object.keys(root.guards).length > 0
    /// id → track title of an ambient sound a mode started; never paused by a guard.
    property var ambientTitles: ({})
    /// Player key → epoch ms of the last "paused" notification, so a player that
    /// keeps restarting does not flood the list.
    property var warnedAt: ({})

    readonly property string helper: Quickshell.shellPath("scripts/modes/browser_extension.py")
    readonly property string pidFile: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/ii-ambient-sound.pid`

    // ── Media guard ─────────────────────────────────────────────────────
    function setGuard(id: string, guard): void {
        const next = Object.assign({}, root.guards);
        next[id] = guard;
        root.guards = next;
        Qt.callLater(root.checkPlayers);
    }

    function clearGuard(id: string): void {
        if (!(id in root.guards))
            return;
        const next = Object.assign({}, root.guards);
        delete next[id];
        root.guards = next;
    }

    function setAmbientTitle(id: string, title: string): void {
        const next = Object.assign({}, root.ambientTitles);
        if (title.length > 0)
            next[id] = title;
        else
            delete next[id];
        root.ambientTitles = next;
    }

    function includesAny(text: string, needles): bool {
        const hay = String(text ?? "").toLowerCase();
        if (!hay.length)
            return false;
        return needles.some(n => {
            const needle = String(n ?? "").trim().toLowerCase();
            return needle.length > 0 && hay.includes(needle);
        });
    }

    function playerAllowed(p): bool {
        const players = [];
        const titles = Object.values(root.ambientTitles);
        for (const g of Object.values(root.guards)) {
            players.push(...(g.allowPlayers ?? []));
            titles.push(...(g.allowTitles ?? []));
        }
        return root.includesAny(p.identity, players) || root.includesAny(p.desktopEntry, players)
            || root.includesAny(p.trackTitle, titles);
    }

    function checkPlayers(): void {
        if (!root.guarding)
            return;
        const now = Date.now();
        for (const p of Array.from(Mpris.players?.values ?? [])) {
            if (!p || !p.isPlaying || root.playerAllowed(p))
                continue;
            if (p.canPause)
                p.pause();
            const key = `${p.dbusName ?? ""}|${p.trackTitle ?? ""}`;
            if (now - (root.warnedAt[key] ?? 0) < 60000)
                continue;
            const warned = Object.assign({}, root.warnedAt);
            warned[key] = now;
            root.warnedAt = warned;
            const name = Object.values(root.guards)[0]?.name ?? Translation.tr("Focus mode");
            const what = String(p.trackTitle ?? "").length > 0 ? p.trackTitle : (p.identity ?? Translation.tr("Media"));
            Quickshell.execDetached(["notify-send", "-a", "Modes & Routines", "-i", "music_off",
                Translation.tr("%1 paused").arg(what),
                Translation.tr("%1 only lets ambient sounds and allowed players play.").arg(name)]);
        }
    }

    // A player starting is the moment that matters; the timer catches whatever
    // the signals miss (a browser tab reusing one MPRIS player).
    Timer {
        interval: 2000
        repeat: true
        running: root.guarding
        onTriggered: root.checkPlayers()
    }

    Instantiator {
        model: root.guarding ? Mpris.players : null
        delegate: Connections {
            required property MprisPlayer modelData
            target: modelData
            function onIsPlayingChanged() {
                if (modelData.isPlaying)
                    Qt.callLater(root.checkPlayers);
            }
        }
    }

    // ── Ambient sound ───────────────────────────────────────────────────
    function openAmbient(url: string): void {
        Qt.openUrlExternally(url);
    }

    /// Plays the URL's audio with mpv (yt-dlp resolves it), replacing any earlier one.
    function startAmbientAudio(url: string, title: string): void {
        Quickshell.execDetached(["sh", "-c",
            'f="$1"; old=$(cat "$f" 2>/dev/null); '
            + '[ -n "$old" ] && [ "$(cat /proc/$old/comm 2>/dev/null)" = mpv ] && kill "$old"; '
            + 'mpv --no-video --no-terminal --loop-file=inf --ytdl-format=bestaudio/best --force-media-title="$3" "$2" >/dev/null 2>&1 & '
            + 'echo $! > "$f"',
            "ii-ambient", root.pidFile, url, title]);
    }

    function stopAmbientAudio(): void {
        Quickshell.execDetached(["sh", "-c",
            'f="$1"; p=$(cat "$f" 2>/dev/null); '
            + '[ -n "$p" ] && [ "$(cat /proc/$p/comm 2>/dev/null)" = mpv ] && kill "$p"; rm -f "$f"',
            "ii-ambient", root.pidFile]);
    }

    /// Pauses the browser tab an ambient sound opened, found by its track title.
    function pauseAmbientTab(title: string): void {
        if (!title.length)
            return;
        for (const p of Array.from(Mpris.players?.values ?? [])) {
            if (p && p.isPlaying && p.canPause && root.includesAny(p.trackTitle, [title]))
                p.pause();
        }
    }

    // ── Browser extensions ──────────────────────────────────────────────
    /// Notification with a button: "Turn on" (opens the extension's page) when the
    /// default browser has it, "Install" (store page) when it does not.
    function promptExtension(ext, modeName: string): void {
        Quickshell.execDetached(["python3", root.helper, "prompt", JSON.stringify(ext), modeName]);
    }
}
