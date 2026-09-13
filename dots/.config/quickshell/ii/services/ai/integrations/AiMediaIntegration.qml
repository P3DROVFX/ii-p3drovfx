pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

/** Narrow adapter for the existing MPRIS, lyrics and SongRec services. */
QtObject {
    id: root

    function bounded(value, maximum = 6000): string {
        return String(value ?? "").trim().slice(0, maximum);
    }

    function playerName(player): string {
        return String(player?.identity ?? player?.desktopEntry ?? "").trim();
    }

    function status(): var {
        const player = MprisController.activePlayer;
        if (!player)
            return { available: false, playing: false, summary: Translation.tr("No media player is active") };
        return {
            available: true,
            player: root.playerName(player),
            title: root.bounded(player.trackTitle, 240),
            artist: root.bounded(player.trackArtist, 180),
            album: root.bounded(player.trackAlbum, 180),
            playing: player.isPlaying === true,
            position: Number(player.position ?? 0),
            duration: Number(player.length ?? 0),
            canPlayPause: MprisController.canTogglePlaying,
            canNext: MprisController.canGoNext,
            canPrevious: MprisController.canGoPrevious
        };
    }

    function previewControl(args): var {
        const action = String(args?.action ?? "").trim().toLowerCase();
        const allowed = ["play", "pause", "toggle", "next", "previous"];
        if (allowed.indexOf(action) < 0)
            return { ok: false, error: "unsupportedMediaAction" };
        const current = root.status();
        if (!current.available)
            return { ok: false, error: "noActiveMediaPlayer" };
        if (["play", "pause", "toggle"].indexOf(action) >= 0 && !current.canPlayPause)
            return { ok: false, error: "playPauseUnavailable" };
        if (action === "next" && !current.canNext)
            return { ok: false, error: "nextUnavailable" };
        if (action === "previous" && !current.canPrevious)
            return { ok: false, error: "previousUnavailable" };
        return {
            ok: true,
            action: action,
            player: current.player,
            current: current,
            summary: Translation.tr("%1 · %2").arg(action).arg(current.title || Translation.tr("unknown track"))
        };
    }

    function control(args): var {
        const preview = root.previewControl(args);
        if (!preview.ok)
            return preview;
        switch (preview.action) {
        case "play":
            if (!MprisController.isPlaying)
                MprisController.togglePlaying();
            break;
        case "pause":
            if (MprisController.isPlaying)
                MprisController.togglePlaying();
            break;
        case "toggle":
            MprisController.togglePlaying();
            break;
        case "next":
            MprisController.next();
            break;
        case "previous":
            MprisController.previous();
            break;
        }
        return { ok: true, action: preview.action, status: root.status() };
    }

    function lyrics(): var {
        const current = root.status();
        if (!current.available)
            return { ok: false, loading: false, error: "noActiveMediaPlayer", networkUsed: false };
        if (!LyricsService.isInitialized)
            LyricsService.initiliazeLyrics();
        const lyrics = root.bounded(LyricsService.plainLyrics, 6000);
        return {
            ok: lyrics.length > 0,
            loading: lyrics.length === 0,
            title: current.title,
            artist: current.artist,
            provider: String(LyricsService.lyricsProvider ?? "auto"),
            lyrics: lyrics,
            networkUsed: true
        };
    }

    function identify(): var {
        if (SongRec.running)
            return { ok: false, error: "songRecognitionAlreadyRunning" };
        SongRec.recognizedTrack = ({ title: "", subtitle: "", url: "" });
        SongRec.toggleRunning(true);
        return {
            ok: true,
            running: SongRec.running,
            monitorSource: String(SongRec.monitorSourceString ?? "monitor"),
            temporaryAudioDeleted: true,
            summary: Translation.tr("Listening for a song from %1").arg(String(SongRec.monitorSourceString ?? "monitor"))
        };
    }

    function stopIdentify(): var {
        if (!SongRec.running)
            return { ok: true, running: false };
        SongRec.toggleRunning(false);
        return { ok: true, running: SongRec.running };
    }
}
