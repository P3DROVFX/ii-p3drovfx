pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

Item {
    id: sportsService

    property bool enabled: Config.options.bar.sports.enable
    property string teamFilter: Config.options.bar.sports.teamFilter
    property int updateInterval: Config.options.bar.sports.updateInterval

    property var allGames: []
    property int currentGameIndex: 0
    property var currentGame: allGames.length > 0 ? allGames[currentGameIndex] : null

    property bool loading: false
    property string error: ""

    function nextGame() {
        if (allGames.length > 1) {
            currentGameIndex = (currentGameIndex + 1) % allGames.length;
        }
    }

    function formatMatchTime(isoDate) {
        const date = new Date(isoDate);
        const format = Config.options.time.format;
        // format is "hh:mm", "h:mm ap", or "h:mm AP"
        // We want "ddd, at [Time]"
        let timePart = "";
        if (format.includes("ap") || format.includes("AP")) {
            // 12h
            timePart = Qt.formatDateTime(date, "h:mm ap");
        } else {
            // 24h
            timePart = Qt.formatDateTime(date, "hh:mm");
        }

        return Qt.formatDateTime(date, "ddd") + ", at " + timePart;
    }

    readonly property var leagueNames: ({
        "bra.1": "Brasileirão",
        "ger.1": "Bundesliga",
        "uefa.champions": "Champions League",
        "uefa.europa": "Europa League",
        "uefa.europa.conf": "Conference League",
        "conmebol.libertadores": "Libertadores",
        "eng.1": "Premier League",
        "esp.1": "LaLiga",
        "fra.1": "Ligue 1",
        "ita.1": "Serie A",
        "fifa.world": "World Cup",
        "fifa.wwc": "Women's World Cup"
    })

    function fetchGames() {
        if (!enabled) {
            allGames = [];
            return;
        }

        loading = true;
        error = "";

        let leaguesToFetch = [];
        if (Config.options.bar.sports.showBRA) leaguesToFetch.push("bra.1");
        if (Config.options.bar.sports.showBUND) leaguesToFetch.push("ger.1");
        if (Config.options.bar.sports.showCL) leaguesToFetch.push("uefa.champions");
        if (Config.options.bar.sports.showUEL) leaguesToFetch.push("uefa.europa");
        if (Config.options.bar.sports.showUECL) leaguesToFetch.push("uefa.europa.conf");
        if (Config.options.bar.sports.showCLA) leaguesToFetch.push("conmebol.libertadores");
        if (Config.options.bar.sports.showEPL) leaguesToFetch.push("eng.1");
        if (Config.options.bar.sports.showLIGA) leaguesToFetch.push("esp.1");
        if (Config.options.bar.sports.showLIG1) leaguesToFetch.push("fra.1");
        if (Config.options.bar.sports.showSERA) leaguesToFetch.push("ita.1");
        if (Config.options.bar.sports.showWC) leaguesToFetch.push("fifa.world");
        if (Config.options.bar.sports.showWWC) leaguesToFetch.push("fifa.wwc");

        if (leaguesToFetch.length === 0) {
            allGames = [];
            loading = false;
            return;
        }

        let pendingRequests = leaguesToFetch.length;
        let collectedEvents = [];

        for (let i = 0; i < leaguesToFetch.length; i++) {
            const leagueId = leaguesToFetch[i];
            const url = `http://site.api.espn.com/apis/site/v2/sports/soccer/${leagueId}/scoreboard`;
            const xhr = new XMLHttpRequest();
            xhr.open("GET", url);
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    pendingRequests--;
                    if (xhr.status === 200) {
                        try {
                            const response = JSON.parse(xhr.responseText);
                            const events = (response.events || []).map(e => {
                                e.leagueName = leagueNames[leagueId] || "";
                                return e;
                            });
                            collectedEvents = collectedEvents.concat(events);
                        } catch (e) {
                            error = "Parse error";
                        }
                    }
                    if (pendingRequests === 0) {
                        loading = false;
                        processGames(collectedEvents);
                    }
                }
            };
            xhr.send();
        }
    }

    function processGames(events) {
        let validGames = [];

        const filterStr = teamFilter.trim().toLowerCase();
        let teamsToMatch = [];
        if (filterStr !== "") {
            teamsToMatch = filterStr.split(',').map(t => t.trim()).filter(t => t.length > 0);
        }

        for (let i = 0; i < events.length; i++) {
            const event = events[i];
            if (!event.competitions || event.competitions.length === 0)
                continue;

            const eventDate = new Date(event.date);
            const now = new Date();
            const state = event.status.type.state;

            const hoursUntilStart = (eventDate - now) / (1000 * 60 * 60);
            if (state === "pre" && hoursUntilStart > Config.options.bar.sports.showBeforeHours)
                continue;

            const minsSinceStart = (now - eventDate) / (1000 * 60);
            if (state === "post" && minsSinceStart > Config.options.bar.sports.showAfterMinutes)
                continue;

            const comp = event.competitions[0];
            const homeTeam = (comp.competitors[0].team.shortDisplayName || comp.competitors[0].team.name || "").toLowerCase();
            const awayTeam = (comp.competitors[1].team.shortDisplayName || comp.competitors[1].team.name || "").toLowerCase();

            let matchesFilter = false;

            if (teamsToMatch.length > 0) {
                for (let j = 0; j < teamsToMatch.length; j++) {
                    const t = teamsToMatch[j];
                    if (homeTeam.includes(t) || awayTeam.includes(t)) {
                        matchesFilter = true;
                        break;
                    }
                }
            } else {
                matchesFilter = true;
            }

            if (matchesFilter) {
                const situation = comp.situation || null;
                const lastPlayText = situation && situation.lastPlay && situation.lastPlay.text ? situation.lastPlay.text : "";

                validGames.push({
                    id: event.id,
                    name: event.name,
                    league: event.leagueName,
                    status: state === "pre" ? formatMatchTime(event.date) : event.status.type.detail,
                    state: state,
                    lastPlay: lastPlayText,
                    home: {
                        name: comp.competitors[0].team.shortDisplayName,
                        score: comp.competitors[0].score || "0",
                        logo: comp.competitors[0].team.logo,
                        winner: comp.competitors[0].winner
                    },
                    away: {
                        name: comp.competitors[1].team.shortDisplayName,
                        score: comp.competitors[1].score || "0",
                        logo: comp.competitors[1].team.logo,
                        winner: comp.competitors[1].winner
                    }
                });
            }
        }

        validGames.sort((a, b) => {
            const order = { "in": 0, "pre": 1, "post": 2 };
            return (order[a.state] || 3) - (order[b.state] || 3);
        });

        allGames = validGames;
        if (currentGameIndex >= allGames.length) {
            currentGameIndex = 0;
        }
    }

    Timer {
        id: refreshTimer
        interval: updateInterval * 1000
        running: enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchGames()
    }

    onEnabledChanged: {
        if (enabled) {
            fetchGames();
        } else {
            allGames = [];
            currentGameIndex = 0;
        }
    }

    onTeamFilterChanged: if (enabled)
        fetchGames()

    Connections {
        target: Config.options.bar.sports
        function onShowBRAChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowBUNDChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowCLChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowUELChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowUECLChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowCLAChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowEPLChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowLIGAChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowLIG1Changed() {
            if (enabled)
                fetchGames();
        }
        function onShowSERAChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowWCChanged() {
            if (enabled)
                fetchGames();
        }
        function onShowWWCChanged() {
            if (enabled)
                fetchGames();
        }
    }
}
