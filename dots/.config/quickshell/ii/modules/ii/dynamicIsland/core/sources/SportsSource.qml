pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.ii.dynamicIsland.core

/**
 * A followed team is playing right now.
 *
 * "Followed" is the bar's sports team filter; with it empty there is nothing to follow
 * and the island asks SportsService for nothing at all. The glance - both crests and the
 * score - sits beside the clock for as long as the game is live, and a score change takes
 * the centre for a moment, which is the one thing worth interrupting for.
 *
 * SportsService refreshes on its own interval for as long as anyone subscribes, so the
 * island only subscribes when a game is on or about to be. Between games it checks the
 * schedule once, notes the next kickoff it can see, and comes back just before it (or in
 * half an hour when there is none in view) instead of fetching every minute all day.
 */
ContinuousSource {
    id: source

    activityId: "sports"

    readonly property string teamFilter: String(Config.options?.bar?.sports?.teamFilter ?? "").trim()
    readonly property bool wanted: source.allowed && source.teamFilter !== ""

    /** The first followed game in play, or null. */
    readonly property var liveGame: {
        const games = SportsService.allGames ?? [];
        for (let i = 0; i < games.length; i++) {
            if (games[i] && games[i].state === "in")
                return games[i];
        }
        return null;
    }

    condition: source.liveGame !== null
    payload: source.liveGame

    // ── The score change ───────────────────────────────────────────────────
    readonly property int announceMs: 6000
    property bool announcing: false
    readonly property string tierOverride: source.announcing ? "transient" : ""
    /** Scores last seen per game id, so only a change announces - never a first sight. */
    property var _scores: ({})

    onLiveGameChanged: {
        const game = source.liveGame;
        if (!game)
            return;
        const score = String(game.home?.score ?? "") + "-" + String(game.away?.score ?? "");
        const before = source._scores[game.id];
        const next = Object.assign({}, source._scores);
        next[game.id] = score;
        source._scores = next;
        if (before === undefined || before === score || IslandPolicy.quietWindowActive)
            return;
        source.revision += 1;
        source.announcing = true;
        source._announceTimer.restart();
    }

    property Timer _announceTimer: Timer {
        interval: source.announceMs
        onTriggered: {
            if (source.hovered)
                source._announceTimer.restart();
            else
                source.announcing = false;
        }
    }

    // ── Subscribing only when it matters ────────────────────────────────────
    property bool _subscribed: false

    function _subscribe(on) {
        if (on === source._subscribed)
            return;
        source._subscribed = on;
        if (on)
            SportsService.acquireWidgetSubscriber();
        else
            SportsService.releaseWidgetSubscriber();
    }

    /** Milliseconds until the nearest kickoff among the games in view, or -1. */
    function _nextKickoffIn() {
        const now = Date.now();
        let best = -1;
        for (const game of (SportsService.allGames ?? [])) {
            if (!game || game.state !== "pre")
                continue;
            const at = new Date(game.date).getTime();
            if (isNaN(at))
                continue;
            const wait = at - now;
            if (best < 0 || wait < best)
                best = Math.max(0, wait);
        }
        return best;
    }

    /** After a fetch: stay subscribed through a game, otherwise sleep until the next. */
    function _evaluate() {
        if (!source.wanted) {
            source._subscribe(false);
            source._wakeTimer.stop();
            return;
        }
        if (SportsService.loading)
            return;
        const kickoff = source._nextKickoffIn();
        const soon = kickoff >= 0 && kickoff < 10 * 60000;
        if (source.liveGame !== null || soon) {
            source._wakeTimer.stop();
            return;
        }
        source._subscribe(false);
        const halfHour = 30 * 60000;
        source._wakeTimer.interval = kickoff > 0 ? Math.min(halfHour, Math.max(60000, kickoff - 5 * 60000)) : halfHour;
        source._wakeTimer.restart();
    }

    property Timer _wakeTimer: Timer {
        repeat: false
        onTriggered: {
            if (source.wanted)
                source._subscribe(true);
        }
    }

    property Connections _service: Connections {
        target: SportsService
        function onLoadingChanged() {
            if (source._subscribed && !SportsService.loading)
                source._evaluate();
        }
    }

    onWantedChanged: source._subscribe(source.wanted)
    Component.onCompleted: source._subscribe(source.wanted)
    Component.onDestruction: source._subscribe(false)
}
