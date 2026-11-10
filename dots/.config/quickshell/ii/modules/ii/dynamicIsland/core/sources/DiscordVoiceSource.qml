pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * In a Discord voice channel.
 *
 * A state for as long as the call lasts: beside the clock, or in a bubble, with whoever
 * is talking. Joining is also news once - the channel takes the centre for a moment and
 * folds back - but only a join that happens while the shell watches: a reload mid-call,
 * or the bridge reconnecting, reports the channel it finds and is not a join.
 *
 * DiscordVoice is a Python bridge that retries Discord's RPC socket every few seconds,
 * so merely reading it would start that for everyone with the island on, Discord or
 * not. The service is only touched once a Discord client has had a window this session;
 * after that it stays, as it does for the overlay.
 */
ContinuousSource {
    id: source

    activityId: "discordVoice"

    // ── Only once Discord is around ─────────────────────────────────────────
    readonly property bool armed: source.allowed && GlobalStates.discordClientSeen

    condition: source.armed && DiscordVoice.inVoice
    payload: source.armed ? DiscordVoice.channel : null

    // ── Joining is news once ────────────────────────────────────────────────
    /** How long "Joined General" holds the centre. */
    readonly property int announceMs: 3500
    property bool announcing: false
    readonly property string tierOverride: source.announcing ? "transient" : ""

    /**
     * The bridge reports the channel it finds right after it (re)authenticates. That is
     * the state it woke into, not a join, so channel changes this soon after are the
     * baseline and stay quiet.
     */
    readonly property int baselineMs: 3000
    property double _authenticatedAt: 0
    property string _channelId: ""

    readonly property string status: source.armed ? DiscordVoice.status : ""
    onStatusChanged: {
        if (source.status === "authenticated")
            source._authenticatedAt = Date.now();
    }

    onPayloadChanged: {
        const id = String(source.payload?.id ?? "");
        if (id === source._channelId)
            return;
        source._channelId = id;
        if (id === "" || !source.allowed || IslandPolicy.quietWindowActive)
            return;
        if (Date.now() - source._authenticatedAt < source.baselineMs)
            return;
        source.revision += 1;
        source.announcing = true;
        source._announceTimer.restart();
    }

    onActiveChanged: {
        if (source.active)
            return;
        source._announceTimer.stop();
        source.announcing = false;
    }

    property Timer _announceTimer: Timer {
        interval: source.announceMs
        onTriggered: {
            // Reading it is not a reason to take it away.
            if (source.hovered)
                source._announceTimer.restart();
            else
                source.announcing = false;
        }
    }
}
