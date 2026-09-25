pragma Singleton
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "SportsServiceHelpers.js" as SportsCache

Item {
    id: root

    // Fetch sports data while either consumer is enabled. The dock and bar
    // controls stay independent, but share this single data source.
    readonly property bool barEnabled: Config.options?.bar?.sports?.enable ?? false
    readonly property bool dockEnabled: Config.options?.dock?.enableSportsWidget ?? false
    // Lock-screen sports is a real consumer only while the lock surface is
    // active. The old config-only gate fetched ESPN continuously on idle.
    readonly property bool lockEnabled: (Config.options?.lock?.sports ?? true)
        && (GlobalStates?.lockLookActive ?? false)
    property int widgetSubscribers: 0
    readonly property bool enabled: barEnabled || dockEnabled || lockEnabled || widgetSubscribers > 0
    // AI consumers are counted separately from the visual widgets. They may
    // query a league that is not monitored by the bar, but must never cause a
    // visual selection or a Config write as a side effect.
    property int aiSubscribers: 0
    // Search is a visible consumer with a short lifetime. Its dedicated daily
    // request must not start the compact bar/dock polling loop.
    property int searchSubscribers: 0
    property var searchGames: []
    property bool searchLoading: false
    property string searchError: ""
    // The timetable is loaded only while its cheatsheet tab exists. Its
    // subscriber keeps a weekly scoreboard warm without making the sports bar
    // a prerequisite for calendar-only users.
    property int timetableSubscribers: 0
    readonly property bool timetableActive: timetableSubscribers > 0
    property string teamFilter: Config.options.bar.sports.teamFilter
    property int updateInterval: Config.options.bar.sports.updateInterval

    property var allGames: []
    property var customOrder: Config.options.bar.sports.customOrder
    onCustomOrderChanged: {
        if (JSON.stringify(Config.options.bar.sports.customOrder) !== JSON.stringify(customOrder)) {
            Config.options.bar.sports.customOrder = customOrder;
        }
    }
    property int currentGameIndex: 0
    property var currentGame: null
    onCurrentGameChanged: {
        if (currentGame) {
            Config.options.bar.sports.activeGameId = currentGame.id;
        } else {
            Config.options.bar.sports.activeGameId = "";
        }
    }

    property bool loading: false
    property string error: ""

    // Timetable projection. These objects deliberately look event-like, but
    // never carry a khal UID and never enter CalendarService.
    property var timetableGames: []
    property string timetableRangeStart: ""
    property string timetableRangeEnd: ""
    readonly property bool timetableRangeCoversToday: {
        const today = root.dayKey(DateTime.clock.date);
        return today.length > 0 && root.timetableRangeStart <= today && today <= root.timetableRangeEnd;
    }
    property bool timetableLoading: false
    property string timetableError: ""
    property string focusedGameId: ""
    property var timetableProjectionSource: []
    property var timetableProjectionCompactEvents: []
    property var timetableProjectionGames: []
    property int timetableProjectionIndex: 0
    property int timetableProjectionEventIndex: 0
    property var timetableProjectionSeen: ({})
    property bool timetableProjecting: false
    // Paired with the projection timer's interval below: eight milliseconds of
    // work per four idle keeps a real yield between batches while spending most
    // of the wall clock on the projection. The previous four-per-sixteen split
    // meant three quarters of the delay before games appeared was waiting.
    readonly property int timetableProjectionBudgetMs: 8

    // Persistent ESPN cache. Timetable ranges retain compact response DTOs so
    // a team-filter change can be projected again without a network request.
    property var scheduleCache: ({})
    property bool scheduleCacheLoaded: false
    property var detailsCache: ({})
    property bool detailsCacheLoaded: false
    property var scheduleRequests: ({})
    property var detailsRequests: ({})
    property var detailsErrors: ({})
    property var _compactRequests: []
    property int _compactRequestGeneration: 0
    property var _searchRequests: []
    property int _searchRequestGeneration: 0
    property int detailsRevision: 0
    property bool cacheReady: false
    property bool pendingRangeRequest: false
    property bool pendingRangeForce: false
    readonly property int scheduleCacheTtlMs: 30 * 60 * 1000
    readonly property int detailsCacheTtlMs: 6 * 60 * 60 * 1000
    readonly property int pregameDetailsCacheTtlMs: 15 * 60 * 1000
    readonly property int liveDetailsCacheTtlMs: Math.max(10, root.updateInterval) * 1000
    readonly property int maximumScheduleEntries: 32
    readonly property int maximumDetailsEntries: 16
    readonly property int maximumDetailsCacheBytes: 2 * 1024 * 1024
    readonly property list<string> apiHosts: ["site.web.api.espn.com", "site.api.espn.com"]

    function acquireAiSubscriber() {
        aiSubscribers += 1;
    }

    function releaseAiSubscriber() {
        aiSubscribers = Math.max(0, aiSubscribers - 1);
    }

    function acquireSearchSubscriber() {
        const wasInactive = searchSubscribers === 0;
        searchSubscribers += 1;
        if (wasInactive)
            root.fetchSearchGamesForToday();
    }

    function releaseSearchSubscriber() {
        searchSubscribers = Math.max(0, searchSubscribers - 1);
        if (searchSubscribers === 0) {
            root.cancelSearchRequests();
            root.searchGames = [];
            root.searchLoading = false;
        }
    }

    function acquireTimetableSubscriber() {
        timetableSubscribers += 1;
        if (root.cacheReady && (!root.scheduleCacheLoaded || !root.detailsCacheLoaded))
            root.loadDetailsCacheFromDisk();
    }

    function releaseTimetableSubscriber() {
        const wasLastSubscriber = root.timetableSubscribers === 1;
        if (wasLastSubscriber && root.cacheReady && cacheSaveDebounce.running) {
            // Flush a just-fetched range before dropping the FileView path.
            // Otherwise closing the timetable during the debounce window could
            // discard the only in-memory copy before it reaches disk.
            cacheSaveDebounce.stop();
            root.saveCache();
        }
        timetableSubscribers = Math.max(0, timetableSubscribers - 1);
        if (timetableSubscribers === 0) {
            root.cancelTimetableRequests();
            cacheRetryTimer.stop();
            timetableProjectionTimer.stop();
            timetableProjectionSource = [];
            timetableProjectionCompactEvents = [];
            timetableProjectionGames = [];
            timetableProjectionIndex = 0;
            timetableProjectionEventIndex = 0;
            timetableProjectionSeen = ({});
            timetableProjecting = false;
            timetableGames = [];
            // The index and the input signature describe the dropped
            // projection; keeping either would let the next open skip the
            // rebuild it needs.
            timetableGamesByDay = ({});
            timetableProjectionSignature = "";
            timetableRangeStart = "";
            timetableRangeEnd = "";
            pendingRangeRequest = false;
            pendingRangeForce = false;
            focusedGameId = "";
            // The bar/dock never read the weekly schedule cache. Drop the
            // timetable projection and stop holding the raw file, but keep the
            // two *parsed* projections: they are bounded by construction
            // (`compactScheduleCache` / `prunedDetailsCache` cap entries and
            // bytes), and re-parsing the multi-megabyte file cost a measured
            // 95 ms of the next open's click burst — on the main thread, in
            // QV4 — for a graph that was already in memory.
            root.detailsErrors = ({});
            root.detailsRevision += 1;
            root.cacheReady = false;
        }
    }

    function acquireWidgetSubscriber() {
        const wasInactive = !root.enabled;
        widgetSubscribers += 1;
        if (wasInactive && !root.timetableActive)
            root.fetchGames();
    }

    function releaseWidgetSubscriber() {
        widgetSubscribers = Math.max(0, widgetSubscribers - 1);
        if (!root.enabled) {
            root.cancelCompactRequests();
            allGames = [];
            currentGameIndex = 0;
            currentGame = null;
        }
    }

    function abortRequestList(requests) {
        const list = Array.isArray(requests) ? requests : Object.values(requests ?? ({}));
        for (let i = 0; i < list.length; i++) {
            const xhr = list[i]?.xhr ?? list[i];
            if (!xhr || xhr.readyState === XMLHttpRequest.DONE)
                continue;
            try {
                xhr.abort();
            } catch (error) {
                // The request may have completed between the state check and
                // abort(). Its completion callback is already harmless.
            }
        }
    }

    function cancelCompactRequests() {
        root._compactRequestGeneration += 1;
        const requests = root._compactRequests;
        root._compactRequests = [];
        root.abortRequestList(requests);
        root.loading = false;
    }

    function cancelSearchRequests() {
        root._searchRequestGeneration += 1;
        const requests = root._searchRequests;
        root._searchRequests = [];
        root.abortRequestList(requests);
        root.searchLoading = false;
    }

    function cancelTimetableRequests() {
        const scheduleRequests = root.scheduleRequests;
        const detailsRequests = root.detailsRequests;
        root.scheduleRequests = ({});
        root.detailsRequests = ({});
        root.timetableLoading = false;
        root.detailsRevision += 1;
        root.abortRequestList(scheduleRequests);
        root.abortRequestList(detailsRequests);
    }

    function nextGame() {
        if (allGames.length > 1) {
            currentGameIndex = (currentGameIndex + 1) % allGames.length;
            currentGame = allGames[currentGameIndex];
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

    function monitoredLeagueEntries() {
        const result = [];
        const monitored = Config.options.bar.sports.monitoredLeagues;
        // An explicitly empty list means "track nothing". Only old configs
        // without the new list property use the legacy show* migration path.
        if (monitored !== undefined && monitored !== null) {
            for (let i = 0; i < monitored.length; i++) {
                const item = monitored[i];
                if (!item?.enabled)
                    continue;
                result.push({
                    sport: String(item.sport ?? ""),
                    league: String(item.league ?? ""),
                    name: String(item.name || root.leagueNames[String(item.league)] || item.league || "")
                });
            }
            return result.filter(item => item.sport.length > 0 && item.league.length > 0);
        }

        if (Config.options.bar.sports.showBRA) result.push({ sport: "soccer", league: "bra.1", name: "Brasileirão" });
        if (Config.options.bar.sports.showBUND) result.push({ sport: "soccer", league: "ger.1", name: "Bundesliga" });
        if (Config.options.bar.sports.showCL) result.push({ sport: "soccer", league: "uefa.champions", name: "Champions League" });
        if (Config.options.bar.sports.showUEL) result.push({ sport: "soccer", league: "uefa.europa", name: "Europa League" });
        if (Config.options.bar.sports.showUECL) result.push({ sport: "soccer", league: "uefa.europa.conf", name: "Conference League" });
        if (Config.options.bar.sports.showCLA) result.push({ sport: "soccer", league: "conmebol.libertadores", name: "Libertadores" });
        if (Config.options.bar.sports.showEPL) result.push({ sport: "soccer", league: "eng.1", name: "Premier League" });
        if (Config.options.bar.sports.showLIGA) result.push({ sport: "soccer", league: "esp.1", name: "LaLiga" });
        if (Config.options.bar.sports.showLIG1) result.push({ sport: "soccer", league: "fra.1", name: "Ligue 1" });
        if (Config.options.bar.sports.showSERA) result.push({ sport: "soccer", league: "ita.1", name: "Serie A" });
        if (Config.options.bar.sports.showWC) result.push({ sport: "soccer", league: "fifa.world", name: "World Cup" });
        if (Config.options.bar.sports.showWWC) result.push({ sport: "soccer", league: "fifa.wwc", name: "Women's World Cup" });
        return result;
    }

    function searchLeagueEntries() {
        const selected = Array.from(Config.options.search.modules.sports.leagues ?? [])
            .map(value => String(value ?? "").trim())
            .filter(Boolean);
        if (selected.length === 0)
            return root.monitoredLeagueEntries();

        // Search league ids are a subset of the user's tracker catalog. Keep
        // their sport/name metadata even when a league is disabled for the
        // compact bar, because the Search selection is an independent filter.
        const tracked = Array.from(Config.options.bar.sports.monitoredLeagues ?? []);
        return selected.map(leagueId => {
            const match = tracked.find(item => String(item?.league ?? "") === leagueId);
            if (!match)
                return null;
            return {
                sport: String(match.sport ?? ""),
                league: leagueId,
                name: String(match.name || root.leagueNames[leagueId] || leagueId)
            };
        }).filter(item => item && item.sport.length > 0);
    }

    function compactMatchStatus(status, state) {
        const text = String(status ?? "");
        if (state !== "in")
            return text;

        const clockMatch = text.match(/(\d{1,3}):\d{2}/);
        if (clockMatch)
            return clockMatch[1] + "'";

        const minuteMatch = text.match(/(\d{1,3})\s*'/);
        return minuteMatch ? minuteMatch[1] + "'" : text;
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
        root.cancelCompactRequests();
        if (!enabled) {
            allGames = [];
            return;
        }

        loading = true;
        error = "";

        const leaguesToFetch = root.monitoredLeagueEntries();

        if (leaguesToFetch.length === 0) {
            allGames = [];
            loading = false;
            return;
        }

        let pendingRequests = leaguesToFetch.length;
        let collectedEvents = [];
        const generation = root._compactRequestGeneration;

        for (let i = 0; i < leaguesToFetch.length; i++) {
            const entry = leaguesToFetch[i];
            const url = `https://${root.apiHosts[0]}/apis/site/v2/sports/${encodeURIComponent(entry.sport)}/${encodeURIComponent(entry.league)}/scoreboard`;
            const xhr = new XMLHttpRequest();
            const request = { xhr: xhr, generation: generation };
            root._compactRequests = root._compactRequests.concat([request]);
            let completed = false;
            const complete = function() {
                if (completed)
                    return;
                completed = true;
                if (generation !== root._compactRequestGeneration)
                    return;
                root._compactRequests = root._compactRequests.filter(item => item !== request);
                pendingRequests--;
                if (xhr.status === 200) {
                    try {
                        const response = JSON.parse(xhr.responseText);
                        let leagueLogo = "";
                        if (response.leagues && response.leagues[0] && response.leagues[0].logos && response.leagues[0].logos[0])
                            leagueLogo = response.leagues[0].logos[0].href;
                        const events = (response.events || []).map(e => {
                            e.leagueName = entry.name;
                            e.sportCategory = entry.sport;
                            e.leagueLogo = leagueLogo;
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
            };
            xhr.open("GET", url);
            xhr.timeout = 12000;
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE)
                    complete();
            };
            xhr.onerror = complete;
            xhr.ontimeout = complete;
            xhr.send();
        }
    }

    function fetchSearchGamesForToday() {
        root.cancelSearchRequests();
        const leaguesToFetch = root.searchLeagueEntries();
        root.searchLoading = true;
        root.searchError = "";
        if (leaguesToFetch.length === 0) {
            root.searchGames = [];
            root.searchLoading = false;
            return;
        }

        const date = root.espnDate(root.dayKey(DateTime.clock.date));
        let pendingRequests = leaguesToFetch.length;
        let failedRequests = 0;
        let collectedEvents = [];
        const generation = root._searchRequestGeneration;

        for (let i = 0; i < leaguesToFetch.length; i++) {
            const entry = leaguesToFetch[i];
            const url = `https://${root.apiHosts[0]}/apis/site/v2/sports/${encodeURIComponent(entry.sport)}/${encodeURIComponent(entry.league)}/scoreboard?dates=${date}`;
            const xhr = new XMLHttpRequest();
            const request = { xhr: xhr, generation: generation };
            root._searchRequests = root._searchRequests.concat([request]);
            let completed = false;
            const complete = function() {
                if (completed)
                    return;
                completed = true;
                if (generation !== root._searchRequestGeneration || root.searchSubscribers === 0)
                    return;
                root._searchRequests = root._searchRequests.filter(item => item !== request);
                pendingRequests--;
                if (xhr.status === 200) {
                    try {
                        const response = JSON.parse(xhr.responseText);
                        let leagueLogo = "";
                        if (response.leagues?.[0]?.logos?.[0])
                            leagueLogo = String(response.leagues[0].logos[0].href ?? "");
                        const events = (response.events ?? []).map(event => Object.assign({}, event, {
                            leagueName: entry.name,
                            leagueId: entry.league,
                            sportCategory: entry.sport,
                            leagueLogo: leagueLogo
                        }));
                        collectedEvents = collectedEvents.concat(events);
                    } catch (parseError) {
                        failedRequests++;
                    }
                } else {
                    failedRequests++;
                }

                if (pendingRequests === 0) {
                    root.searchLoading = false;
                    root.searchError = failedRequests === leaguesToFetch.length
                        ? qsTr("Could not load today's games")
                        : "";
                    root.processGames(collectedEvents, true);
                }
            };
            xhr.open("GET", url);
            xhr.timeout = 12000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE)
                    complete();
            };
            xhr.onerror = complete;
            xhr.ontimeout = complete;
            xhr.send();
        }
    }

    // ── Timetable projection ─────────────────────────────────────────────

    function dayKey(value) {
        if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value))
            return value;
        const date = value instanceof Date ? value : new Date(value);
        if (isNaN(date.getTime()))
            return "";
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    function espnDate(value) {
        return String(value ?? "").replace(/-/g, "");
    }

    function scheduleKey(entry, fromKey, toKey) {
        return [entry.sport, entry.league, fromKey, toKey].join("|");
    }

    function timetableCompetition(event) {
        const competitions = Array.isArray(event?.competitions) ? event.competitions : [];
        if (competitions.length === 0)
            return null;
        const leagueName = String(event?.leagueName ?? "").toLowerCase();
        const isRacing = event?.sportCategory === "racing" || event?.sportCategory === "motorsports" || leagueName.includes("f1") || leagueName.includes("formula");
        if (!isRacing || competitions.length === 1)
            return competitions[0];
        return competitions.find(item => item?.status?.type?.state === "in")
            || competitions.find(item => item?.status?.type?.state === "pre")
            || competitions[competitions.length - 1];
    }

    function teamFilterTerms() {
        return String(root.teamFilter ?? "").toLowerCase().split(",").map(item => item.trim()).filter(item => item.length > 0);
    }

    function matchesConfiguredTeams(event, competition) {
        const terms = root.teamFilterTerms();
        if (terms.length === 0)
            return true;
        const competitors = Array.isArray(competition?.competitors) ? competition.competitors : [];
        const names = [];
        for (let i = 0; i < competitors.length; i++) {
            const item = competitors[i] ?? ({});
            const team = item.team ?? ({});
            const athlete = item.athlete ?? ({});
            names.push(String(team.displayName || team.shortDisplayName || team.name || athlete.displayName || athlete.shortName || "").toLowerCase());
            names.push(String(team.abbreviation || "").toLowerCase());
        }
        names.push(String(event?.name ?? "").toLowerCase());
        return terms.some(term => names.some(name => name.includes(term)));
    }

    function durationMinutesForSport(sport) {
        switch (String(sport ?? "")) {
        case "basketball":
        case "hockey":
            return 150;
        case "football":
            return 210;
        case "baseball":
        case "tennis":
        case "racing":
        case "motorsports":
            return 180;
        case "golf":
            return 300;
        default:
            return 120;
        }
    }

    function normalizedCompetitor(value, fallback) {
        const item = value ?? ({});
        const team = item.team ?? ({});
        const athlete = item.athlete ?? ({});
        const logos = Array.isArray(team.logos) ? team.logos : [];
        const records = Array.isArray(item.records) ? item.records : (Array.isArray(item.record) ? item.record : []);
        return {
            id: String(item.id || team.id || athlete.id || ""),
            name: String(team.displayName || team.shortDisplayName || team.name || athlete.displayName || athlete.shortName || fallback),
            abbreviation: String(team.abbreviation || athlete.shortName || ""),
            score: String(item.score ?? item.displayValue ?? ""),
            logo: String(team.logo || logos?.[0]?.href || athlete.headshot || ""),
            winner: item.winner === true,
            homeAway: String(item.homeAway ?? ""),
            form: String(item.form || team.form || ""),
            record: records.length > 0 ? String(records[0]?.summary || records[0]?.displayValue || "") : "",
            links: root.normalizedLinks(team.links ?? [])
        };
    }

    function normalizedLinks(values) {
        const result = [];
        const seen = ({});
        const list = Array.isArray(values) ? values : [];
        for (let i = 0; i < list.length; i++) {
            const item = list[i] ?? ({});
            const href = String(item.href ?? "");
            if (!/^https?:\/\//.test(href) || seen[href])
                continue;
            seen[href] = true;
            result.push({
                href: href,
                label: String(item.text || item.shortText || "ESPN"),
                rel: Array.isArray(item.rel) ? item.rel.map(value => String(value)) : []
            });
        }
        return result;
    }

    function normalizedBroadcasts(competition) {
        const result = [];
        const groups = Array.isArray(competition?.broadcasts) ? competition.broadcasts : [];
        for (let i = 0; i < groups.length; i++) {
            const item = groups[i] ?? ({});
            const names = Array.isArray(item.names) ? item.names : [];
            for (let j = 0; j < names.length; j++) {
                const name = String(names[j] ?? "").trim();
                if (name.length > 0 && !result.includes(name))
                    result.push(name);
            }
            const name = String(item.name ?? "").trim();
            if (name.length > 0 && !result.includes(name))
                result.push(name);
        }
        const legacy = String(competition?.broadcast ?? "").trim();
        if (legacy.length > 0 && !result.includes(legacy))
            result.push(legacy);
        return result;
    }

    function normalizeTimetableGame(event) {
        const competition = root.timetableCompetition(event);
        if (!competition || !root.matchesConfiguredTeams(event, competition))
            return null;

        const competitors = Array.isArray(competition.competitors) ? competition.competitors : [];
        let homeValue = competitors.find(item => item?.homeAway === "home") ?? competitors[0] ?? null;
        let awayValue = competitors.find(item => item?.homeAway === "away") ?? competitors[1] ?? null;
        if (homeValue === awayValue)
            awayValue = competitors.length > 1 ? competitors[1] : null;

        const home = root.normalizedCompetitor(homeValue, "Home");
        const away = root.normalizedCompetitor(awayValue, "Away");
        if (home.logo.length === 0)
            home.logo = String(event?.leagueLogo ?? "");
        if (away.logo.length === 0)
            away.logo = String(event?.leagueLogo ?? "");

        const type = competition?.status?.type ?? event?.status?.type ?? ({});
        const state = String(type.state ?? "pre");
        const status = String(type.detail || type.shortDetail || type.description || (state === "pre" ? "Scheduled" : state));
        const startDate = new Date(competition.date || competition.startDate || event?.date);
        if (isNaN(startDate.getTime()))
            return null;
        const endDate = new Date(startDate.getTime() + root.durationMinutesForSport(event?.sportCategory) * 60 * 1000);
        const league = String(event?.leagueName || root.leagueNames[String(event?.leagueId)] || event?.leagueId || "Sports");
        const scoreKnown = home.score.length > 0 || away.score.length > 0;
        const matchup = away.name.length > 0 ? `${home.name} × ${away.name}` : String(event?.name || home.name);
        const liveTitle = scoreKnown && state !== "pre" ? `${home.name} ${home.score || "0"}–${away.score || "0"} ${away.name}` : matchup;
        const venue = competition.venue ?? ({});
        const address = venue.address ?? ({});
        const addressParts = [address.city, address.state, address.country].map(value => String(value ?? "").trim()).filter(value => value.length > 0);
        const links = root.normalizedLinks((event?.links ?? []).concat(competition?.links ?? []));
        const details = Array.isArray(competition.details) ? competition.details : [];
        const lastDetail = details.length > 0 ? details[details.length - 1] : null;
        const lastAthlete = lastDetail?.athletesInvolved?.[0]?.displayName ?? "";
        const lastPlay = competition?.situation?.lastPlay?.text
            || (lastDetail ? [lastDetail?.type?.text, lastAthlete, lastDetail?.clock?.displayValue].filter(value => String(value ?? "").length > 0).join(" · ") : "");

        return {
            id: String(event?.id ?? competition.id ?? ""),
            content: liveTitle,
            title: liveTitle,
            name: String(event?.name || matchup),
            startDate: startDate,
            endDate: endDate,
            start: Qt.formatTime(startDate, "hh:mm"),
            // WeekView lays out one day at a time. A late match keeps its real
            // endDate for details, but its block stops at this column's edge.
            end: root.dayKey(endDate) === root.dayKey(startDate) ? Qt.formatTime(endDate, "hh:mm") : "24:00",
            description: [league, status, lastPlay].filter(value => String(value ?? "").length > 0).join(" · "),
            calendar: `ESPN · ${league}`,
            readOnly: true,
            sportEvent: true,
            allDay: false,
            uid: "",
            colorToken: "tertiary",
            categories: ["Sports", league],
            sport: String(event?.sportCategory ?? ""),
            league: league,
            leagueId: String(event?.leagueId ?? ""),
            leagueLogo: String(event?.leagueLogo ?? ""),
            state: state,
            status: status,
            lastPlay: String(lastPlay ?? ""),
            home: home,
            away: away,
            venue: {
                id: String(venue.id ?? ""),
                name: String(venue.fullName || venue.name || ""),
                address: addressParts.join(", ")
            },
            location: [String(venue.fullName || venue.name || ""), addressParts.join(", ")].filter(value => value.length > 0).join(" · "),
            broadcasts: root.normalizedBroadcasts(competition),
            attendance: Number(competition.attendance ?? 0),
            notes: Array.isArray(competition.notes) ? competition.notes : [],
            links: links,
            url: links.length > 0 ? links[0].href : "",
            season: event?.season ?? null,
            competitionNote: String(competition.altGameNote ?? ""),
            fetchedAt: String(event?.fetchedAt ?? "")
        };
    }

    // Scoreboard responses contain a large amount of ESPN metadata that no
    // timetable consumer reads. Keeping that raw graph alive for every cached
    // range was disproportionately expensive: a few MiB of JSON became many
    // more MiB of JS objects, strings and arrays. Store a DTO with exactly the
    // fields used by the read-only timetable projection instead.
    function compactLinks(values) {
        const result = [];
        const list = Array.isArray(values) ? values : [];
        const seen = ({});
        for (let i = 0; i < list.length; i++) {
            const item = list[i] ?? ({});
            const href = String(item.href ?? "");
            if (!/^https?:\/\//.test(href) || seen[href])
                continue;
            seen[href] = true;
            result.push({
                href: href,
                text: String(item.text || item.shortText || "ESPN"),
                rel: Array.isArray(item.rel) ? item.rel.slice(0, 8).map(value => String(value)) : []
            });
        }
        return result;
    }

    function compactStatus(value) {
        const status = value ?? ({});
        const type = status.type ?? ({});
        return {
            type: {
                state: String(type.state ?? ""),
                detail: String(type.detail ?? ""),
                shortDetail: String(type.shortDetail ?? ""),
                description: String(type.description ?? "")
            }
        };
    }

    function compactSeason(value) {
        if (value === null || value === undefined)
            return null;
        if (typeof value !== "object")
            return String(value);
        return {
            name: String(value.name ?? ""),
            displayName: String(value.displayName ?? ""),
            year: value.year ?? null
        };
    }

    function compactScheduleCompetitor(value) {
        const item = value ?? ({});
        const team = item.team ?? ({});
        const athlete = item.athlete ?? ({});
        const teamLogos = Array.isArray(team.logos) ? team.logos : [];
        const records = Array.isArray(item.records) ? item.records : (Array.isArray(item.record) ? item.record : []);
        return {
            id: String(item.id || team.id || athlete.id || ""),
            homeAway: String(item.homeAway ?? ""),
            score: String(item.score ?? ""),
            displayValue: String(item.displayValue ?? ""),
            winner: item.winner === true,
            form: String(item.form || team.form || ""),
            records: records.length > 0 ? [{
                summary: String(records[0]?.summary ?? ""),
                displayValue: String(records[0]?.displayValue ?? "")
            }] : [],
            team: {
                id: String(team.id ?? ""),
                displayName: String(team.displayName ?? ""),
                shortDisplayName: String(team.shortDisplayName ?? ""),
                name: String(team.name ?? ""),
                abbreviation: String(team.abbreviation ?? ""),
                logo: String(team.logo ?? ""),
                logos: teamLogos.length > 0 ? [{ href: String(teamLogos[0]?.href ?? "") }] : [],
                links: root.compactLinks(team.links)
            },
            athlete: {
                id: String(athlete.id ?? ""),
                displayName: String(athlete.displayName ?? ""),
                shortName: String(athlete.shortName ?? ""),
                headshot: String(athlete.headshot ?? "")
            }
        };
    }

    function compactScheduleCompetition(value) {
        const competition = value ?? ({});
        const venue = competition.venue ?? ({});
        const address = venue.address ?? ({});
        const competitors = Array.isArray(competition.competitors) ? competition.competitors : [];
        const rawDetails = Array.isArray(competition.details) ? competition.details : [];
        const lastDetail = rawDetails.length > 0 ? rawDetails[rawDetails.length - 1] : null;
        const compactDetail = lastDetail ? {
            type: { text: String(lastDetail.type?.text ?? "") },
            clock: { displayValue: String(lastDetail.clock?.displayValue ?? "") },
            athletesInvolved: Array.isArray(lastDetail.athletesInvolved) && lastDetail.athletesInvolved.length > 0
                ? [{ displayName: String(lastDetail.athletesInvolved[0]?.displayName ?? "") }]
                : []
        } : null;
        return {
            id: String(competition.id ?? ""),
            date: String(competition.date ?? ""),
            startDate: String(competition.startDate ?? ""),
            status: root.compactStatus(competition.status),
            competitors: competitors.map(root.compactScheduleCompetitor),
            venue: {
                id: String(venue.id ?? ""),
                fullName: String(venue.fullName ?? ""),
                name: String(venue.name ?? ""),
                address: {
                    city: String(address.city ?? ""),
                    state: String(address.state ?? ""),
                    country: String(address.country ?? "")
                }
            },
            links: root.compactLinks(competition.links),
            broadcasts: Array.isArray(competition.broadcasts) ? competition.broadcasts.slice(0, 8).map(item => ({
                name: String(item?.name ?? ""),
                names: Array.isArray(item?.names) ? item.names.slice(0, 8).map(name => String(name)) : []
            })) : [],
            broadcast: String(competition.broadcast ?? ""),
            attendance: Number(competition.attendance ?? 0),
            notes: [],
            altGameNote: String(competition.altGameNote ?? ""),
            details: compactDetail ? [compactDetail] : [],
            situation: {
                lastPlay: { text: String(competition.situation?.lastPlay?.text ?? "") }
            }
        };
    }

    function compactScheduleEvent(value) {
        const event = value ?? ({});
        const competitions = Array.isArray(event.competitions) ? event.competitions : [];
        const firstCompetition = competitions[0] ?? ({});
        return {
            id: String(event.id ?? ""),
            date: String(event.date || firstCompetition.date || firstCompetition.startDate || ""),
            name: String(event.name ?? ""),
            status: root.compactStatus(event.status),
            leagueName: String(event.leagueName ?? ""),
            leagueId: String(event.leagueId ?? ""),
            sportCategory: String(event.sportCategory ?? ""),
            leagueLogo: String(event.leagueLogo ?? ""),
            season: root.compactSeason(event.season),
            links: root.compactLinks(event.links),
            competitions: competitions.map(root.compactScheduleCompetition)
        };
    }

    function compactScheduleCache(values) {
        const result = ({});
        const source = values && typeof values === "object" ? values : ({});
        for (const key of Object.keys(source)) {
            const entry = source[key] ?? ({});
            result[key] = {
                fetchedAt: Number(entry.fetchedAt ?? 0),
                sport: String(entry.sport ?? ""),
                league: String(entry.league ?? ""),
                name: String(entry.name ?? ""),
                leagueLogo: String(entry.leagueLogo ?? ""),
                events: Array.isArray(entry.events) ? entry.events.map(root.compactScheduleEvent) : []
            };
        }
        return result;
    }

    function cacheEntryFresh(entry, ttl) {
        return entry && Date.now() - Number(entry.fetchedAt ?? 0) <= ttl;
    }

    function removeScheduleRequest(key) {
        const next = ({});
        for (const requestKey in root.scheduleRequests) {
            if (requestKey !== String(key))
                next[requestKey] = root.scheduleRequests[requestKey];
        }
        root.scheduleRequests = next;
        root.timetableLoading = Object.keys(next).length > 0;
    }

    // ESPN's scoreboard answers a whole month (`dates=202609`) but rejects a
    // `from-to` range with HTTP 400, so a range is fetched month by month and
    // merged into the same cache entry — the range key, the TTL and the
    // projection stay exactly as they were. See SportsServiceHelpers.js.
    function scheduleRequestMonth(request) {
        return SportsCache.monthForIndex(request?.months, request?.monthIndex)
            || root.espnDate(request?.fromKey);
    }

    function startScheduleRequest(key, request) {
        const host = root.apiHosts[request.hostIndex] || root.apiHosts[0];
        const url = `https://${host}/apis/site/v2/sports/${encodeURIComponent(request.entry.sport)}/${encodeURIComponent(request.entry.league)}/scoreboard?dates=${root.scheduleRequestMonth(request)}`;
        const xhr = new XMLHttpRequest();
        request.xhr = xhr;
        const next = Object.assign({}, root.scheduleRequests);
        next[String(key)] = request;
        root.scheduleRequests = next;
        root.timetableLoading = true;
        xhr.timeout = 12000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                root.handleScheduleResponse(String(key), xhr.status, xhr.responseText);
        };
        xhr.onerror = function() { root.handleScheduleResponse(String(key), 0, ""); };
        xhr.ontimeout = function() { root.handleScheduleResponse(String(key), 0, ""); };
        xhr.open("GET", url);
        xhr.send();
    }

    function handleScheduleResponse(key, httpStatus, responseText) {
        const request = root.scheduleRequests[String(key)] ?? null;
        if (!request)
            return;
        if (httpStatus === 403 && request.hostIndex + 1 < root.apiHosts.length) {
            request.hostIndex += 1;
            root.startScheduleRequest(String(key), request);
            return;
        }
        if (httpStatus !== 200) {
            root.failScheduleRequest(String(key), request, `HTTP ${String(httpStatus)}`);
            return;
        }
        let parsed = null;
        try {
            parsed = JSON.parse(String(responseText ?? "{}"));
        } catch (error) {
            parsed = null;
        }
        if (!parsed || !Array.isArray(parsed.events)) {
            root.failScheduleRequest(String(key), request, "unreadable schedule data");
            return;
        }
        request.leagues = Array.isArray(request.leagues) && request.leagues.length > 0
            ? request.leagues
            : (Array.isArray(parsed.leagues) ? parsed.leagues : []);
        request.events = (request.events ?? []).concat(parsed.events);
        const months = Array.isArray(request.months) ? request.months : [];
        const nextMonth = Number(request.monthIndex ?? 0) + 1;
        if (nextMonth < months.length) {
            request.monthIndex = nextMonth;
            root.startScheduleRequest(String(key), request);
            return;
        }
        root.finishScheduleRequest(String(key), { events: request.events, leagues: request.leagues });
    }

    function failScheduleRequest(key, request, reason) {
        root.removeScheduleRequest(key);
        root.timetableError = `ESPN ${reason} · ${request.entry.name}`;
        console.warn(`[SportsService] Timetable fetch failed for ${request.entry.sport}/${request.entry.league} (${reason})`);
        root.rebuildTimetableGames();
    }

    function fetchScheduleEntry(entry, fromKey, toKey) {
        const key = root.scheduleKey(entry, fromKey, toKey);
        if (root.scheduleRequests[key] !== undefined)
            return;
        root.startScheduleRequest(key, {
            xhr: null,
            hostIndex: 0,
            entry: entry,
            fromKey: fromKey,
            toKey: toKey,
            months: SportsCache.espnMonths(fromKey, toKey),
            monthIndex: 0,
            events: [],
            leagues: []
        });
    }

    function finishScheduleRequest(key, response) {
        const request = root.scheduleRequests[String(key)] ?? null;
        if (!request)
            return;
        root.removeScheduleRequest(key);

        try {
            const events = Array.isArray(response?.events) ? response.events : [];
            const responseLeague = Array.isArray(response?.leagues) && response.leagues.length > 0 ? response.leagues[0] : ({});
            const logos = Array.isArray(responseLeague?.logos) ? responseLeague.logos : [];
            const nextCache = Object.assign({}, root.scheduleCache);
            nextCache[String(key)] = {
                fetchedAt: Date.now(),
                sport: request.entry.sport,
                league: request.entry.league,
                name: String(responseLeague?.name || request.entry.name),
                leagueLogo: String(logos?.[0]?.href ?? ""),
                events: events.map(root.compactScheduleEvent)
            };
            root.scheduleCache = root.prunedCache(nextCache, root.maximumScheduleEntries);
            root.scheduleCacheLoaded = true;
            root.timetableError = "";
            root.scheduleCacheSave();
        } catch (error) {
            root.timetableError = "ESPN returned invalid schedule data";
            console.warn(`[SportsService] Invalid timetable payload: ${String(error)}`);
        }
        root.rebuildTimetableGames();
    }

    function requestTimetableRange(fromValue, toValue, force = false) {
        if (!root.timetableActive)
            return;
        const fromKey = root.dayKey(fromValue);
        const toKey = root.dayKey(toValue);
        if (fromKey.length === 0 || toKey.length === 0)
            return;
        root.timetableRangeStart = fromKey;
        root.timetableRangeEnd = toKey;

        if (!root.cacheReady) {
            root.pendingRangeRequest = true;
            root.pendingRangeForce = root.pendingRangeForce || force;
            return;
        }

        const leagues = root.monitoredLeagueEntries();
        if (leagues.length === 0) {
            root.timetableGames = [];
            root.timetableGamesByDay = ({});
            root.timetableProjectionSignature = "";
            root.timetableLoading = false;
            return;
        }

        root.rebuildTimetableGames();
        const liveSensitive = root.rangeNeedsLiveRefresh();
        for (let i = 0; i < leagues.length; i++) {
            const entry = leagues[i];
            const key = root.scheduleKey(entry, fromKey, toKey);
            const cached = root.scheduleCache[key];
            if (force || liveSensitive || !root.cacheEntryFresh(cached, root.scheduleCacheTtlMs))
                root.fetchScheduleEntry(entry, fromKey, toKey);
        }
    }

    function cachedRangeSources() {
        const sources = [];
        const leagues = root.monitoredLeagueEntries();
        for (let i = 0; i < leagues.length; i++) {
            const entry = leagues[i];
            const key = root.scheduleKey(entry, root.timetableRangeStart, root.timetableRangeEnd);
            const cached = root.scheduleCache[key];
            const values = Array.isArray(cached?.events) ? cached.events : [];
            if (values.length === 0)
                continue;
            sources.push({
                key: key,
                entry: entry,
                cached: cached,
                events: values
            });
        }
        return sources;
    }

    function eventFitsCompactWindow(event) {
        const eventDate = new Date(event?.date);
        if (isNaN(eventDate.getTime()))
            return false;
        const state = String(event?.status?.type?.state ?? "");
        const now = Date.now();
        if (state === "pre")
            return (eventDate.getTime() - now) / (1000 * 60 * 60) <= Config.options.bar.sports.showBeforeHours;
        if (state === "post")
            return (now - eventDate.getTime()) / (1000 * 60) <= Config.options.bar.sports.showAfterMinutes;
        return true;
    }

    // The projection is a pure function of the cache contents, the visible range
    // and the team filter. Rebuilds arrive from events that change none of those
    // — a failed ESPN fetch, a repeated range request — and every rebuild
    // republishes `timetableGames`, which invalidates each month cell's sport
    // list and the week view's day model, so their delegates are rebuilt. A
    // signature of the inputs keeps a fruitless fetch from rebuilding the grid.
    property string timetableProjectionSignature: ""

    function timetableSourceSignature() {
        return SportsCache.sourceSignature(root.timetableRangeStart, root.timetableRangeEnd,
            root.teamFilter, root.cachedRangeSources());
    }

    function rebuildTimetableGames() {
        if (!root.timetableActive)
            return;
        if (root.timetableRangeStart.length === 0 || root.timetableRangeEnd.length === 0)
            return;
        const signature = root.timetableSourceSignature();
        if (signature === root.timetableProjectionSignature)
            return;
        root.timetableProjectionSignature = signature;
        timetableProjectionTimer.stop();
        root.timetableProjectionSource = root.cachedRangeSources();
        root.timetableProjectionCompactEvents = [];
        root.timetableProjectionGames = [];
        root.timetableProjectionIndex = 0;
        root.timetableProjectionEventIndex = 0;
        root.timetableProjectionSeen = ({});
        root.timetableProjecting = root.timetableProjectionSource.length > 0;
        if (!root.timetableProjecting) {
            root.finishTimetableProjection();
            return;
        }
        timetableProjectionTimer.start();
    }

    function projectNextTimetableBatch() {
        if (!root.timetableActive) {
            timetableProjectionTimer.stop();
            root.timetableProjecting = false;
            return;
        }

        // The cursors stay in locals for the length of a batch. Writing them
        // back per event meant a metaobject property write, and its change
        // notification, for every cached ESPN entry — which is most of the work
        // once a month spans several leagues. The clock is sampled every
        // sixteen entries for the same reason; the overshoot is microseconds.
        const sources = root.timetableProjectionSource;
        const seen = root.timetableProjectionSeen;
        const compact = root.timetableProjectionCompactEvents;
        const collected = root.timetableProjectionGames;
        const rangeStart = root.timetableRangeStart;
        const rangeEnd = root.timetableRangeEnd;
        const budget = root.timetableProjectionBudgetMs;
        let sourceIndex = root.timetableProjectionIndex;
        let eventIndex = root.timetableProjectionEventIndex;
        let sinceClockCheck = 0;

        const startedAt = Date.now();
        while (sourceIndex < sources.length) {
            if (sinceClockCheck >= 16) {
                sinceClockCheck = 0;
                if (Date.now() - startedAt >= budget)
                    break;
            }
            sinceClockCheck += 1;

            const source = sources[sourceIndex];
            const values = source.events;
            if (eventIndex >= values.length) {
                sourceIndex += 1;
                eventIndex = 0;
                continue;
            }

            const sourceEventIndex = eventIndex;
            const sourceEvent = values[sourceEventIndex] ?? ({});
            eventIndex += 1;
            const id = String(sourceEvent.id ?? `${source.key}-${String(sourceEventIndex)}`);
            if (seen[id])
                continue;
            seen[id] = true;

            const raw = Object.assign({}, sourceEvent, {
                leagueName: String(source.cached?.name || source.entry.name),
                leagueId: source.entry.league,
                sportCategory: source.entry.sport,
                leagueLogo: String(source.cached?.leagueLogo ?? ""),
                fetchedAt: source.cached?.fetchedAt ? new Date(Number(source.cached.fetchedAt)).toISOString() : ""
            });
            if (root.eventFitsCompactWindow(raw))
                compact.push(raw);
            const game = root.normalizeTimetableGame(raw);
            if (!game)
                continue;
            const key = root.dayKey(game.startDate);
            if (key < rangeStart || key > rangeEnd)
                continue;
            collected.push(game);
        }

        root.timetableProjectionIndex = sourceIndex;
        root.timetableProjectionEventIndex = eventIndex;

        if (sourceIndex >= sources.length) {
            timetableProjectionTimer.stop();
            root.finishTimetableProjection();
        }
    }

    function finishTimetableProjection() {
        const compactEvents = root.timetableProjectionCompactEvents;
        const games = root.timetableProjectionGames;
        games.sort((left, right) => left.startDate.getTime() - right.startDate.getTime());
        // A republish that changes nothing still invalidates every month cell's
        // sport list and the week view's day model, which rebuilds their
        // delegates — and a failing fetch or a refresh tick used to repeat that
        // every minute. Only a real change reaches the views now.
        if (!SportsCache.sameGames(root.timetableGames, games)) {
            root.timetableGames = games;
            root.timetableGamesByDay = root.stableGamesByDay(games);
        }
        root.timetableProjectionSource = [];
        root.timetableProjectionCompactEvents = [];
        root.timetableProjectionGames = [];
        root.timetableProjectionIndex = 0;
        root.timetableProjectionEventIndex = 0;
        root.timetableProjectionSeen = ({});
        root.timetableProjecting = false;
        // Reuse the timetable response for bar/dock only when it actually
        // contains today. Navigating to another month must not blank or stale
        // the compact live score projection.
        if (root.enabled && root.timetableRangeCoversToday) {
            Qt.callLater(() => {
                if (root.enabled)
                    root.processGames(compactEvents);
            });
        }
    }

    // Indexed once per publication. The month grid asks forty-two cells for
    // "the games on this day", and the old filter walked the whole list per
    // cell with a Qt.formatDate call per game — so the cost was cells × games
    // on every republication, which is why a busy month felt slow to fill in.
    // The arrays are shared and read-only, same contract as
    // CalendarService.eventsByDay.
    //
    // Published imperatively rather than as a binding on `timetableGames`,
    // because a day whose games did not change must keep the *same* array
    // instance: `MonthDayCell` derives its whole entry list from it, and a new
    // identity there rebuilds every chip delegate of that cell. With many
    // sports events in the visible range a single refreshed game used to
    // rebuild the whole month; now only the affected days do.
    property var timetableGamesByDay: ({})

    /** Shared empty array so a day without games never changes identity. */
    readonly property var noTimetableGames: []

    function stableGamesByDay(games) {
        return SportsCache.gamesByDay(games, value => root.dayKey(value), root.timetableGamesByDay);
    }

    function gamesForDate(date) {
        const key = root.dayKey(date);
        if (key.length === 0)
            return root.noTimetableGames;
        return root.timetableGamesByDay[key] ?? root.noTimetableGames;
    }

    function gameById(gameId) {
        const id = String(gameId ?? "");
        return (root.timetableGames ?? []).find(game => String(game?.id ?? "") === id) ?? null;
    }

    function rangeNeedsLiveRefresh() {
        const games = root.timetableGames ?? [];
        for (let i = 0; i < games.length; i++) {
            if (root.gameNeedsLiveRefresh(games[i]))
                return true;
        }
        return false;
    }

    function gameNeedsLiveRefresh(game) {
        if (game?.state === "in")
            return true;
        const now = Date.now();
        const start = game?.startDate instanceof Date ? game.startDate.getTime() : new Date(game?.startDate).getTime();
        const end = game?.endDate instanceof Date ? game.endDate.getTime() : new Date(game?.endDate).getTime();
        return !isNaN(start) && !isNaN(end) && now >= start - 2 * 60 * 1000 && now <= end + 30 * 60 * 1000 && game?.state !== "post";
    }

    function gameNearKickoff(game) {
        if (!game || game?.state === "post")
            return false;
        const now = Date.now();
        const start = game?.startDate instanceof Date ? game.startDate.getTime() : new Date(game?.startDate).getTime();
        const end = game?.endDate instanceof Date ? game.endDate.getTime() : new Date(game?.endDate).getTime();
        return !isNaN(start) && !isNaN(end) && now >= start - 2 * 60 * 60 * 1000 && now <= end + 30 * 60 * 1000;
    }

    // ── Per-game summary/details ─────────────────────────────────────────

    function detailsForGame(gameId) {
        // detailsRevision makes bindings that call this function reactive even
        // though the cache is a plain JavaScript map.
        const revision = root.detailsRevision;
        const entry = root.detailsCache[String(gameId ?? "")];
        return entry?.data ?? null;
    }

    function detailsLoadingForGame(gameId) {
        return root.detailsRequests[String(gameId ?? "")] !== undefined;
    }

    function detailsErrorForGame(gameId) {
        return String(root.detailsErrors[String(gameId ?? "")] ?? "");
    }

    function focusGame(game) {
        if (!game?.sportEvent)
            return;
        root.focusedGameId = String(game.id ?? "");
        root.requestGameDetails(game, root.gameNeedsLiveRefresh(game));
    }

    function clearFocusedGame(gameId = "") {
        const id = String(gameId ?? "");
        if (id.length === 0 || root.focusedGameId === id)
            root.focusedGameId = "";
        if (id.length === 0 || root.detailsCache[id] === undefined)
            return;

        // The detail panel is the only consumer of the raw summary graph.
        // Drop it as soon as that panel closes instead of keeping up to 16
        // full ESPN responses alive for the whole shell session.
        const nextCache = Object.assign({}, root.detailsCache);
        delete nextCache[id];
        root.detailsCache = nextCache;
        const nextErrors = Object.assign({}, root.detailsErrors);
        delete nextErrors[id];
        root.detailsErrors = nextErrors;
        root.detailsRevision += 1;
        root.scheduleCacheSave();
    }

    function requestGameDetails(game, force = false) {
        const id = String(game?.id ?? "");
        const sport = String(game?.sport ?? "");
        const league = String(game?.leagueId ?? "");
        if (id.length === 0 || sport.length === 0 || league.length === 0)
            return;
        const cached = root.detailsCache[id];
        const ttl = root.gameNeedsLiveRefresh(game)
            ? root.liveDetailsCacheTtlMs
            : (root.gameNearKickoff(game) ? root.pregameDetailsCacheTtlMs : root.detailsCacheTtlMs);
        if (!force && root.cacheEntryFresh(cached, ttl))
            return;
        if (root.detailsRequests[id] !== undefined)
            return;
        root.startDetailsRequest(id, {
            xhr: null,
            hostIndex: 0,
            gameId: id,
            sport: sport,
            league: league
        });
    }

    function startDetailsRequest(key, request) {
        const host = root.apiHosts[request.hostIndex] || root.apiHosts[0];
        const url = `https://${host}/apis/site/v2/sports/${encodeURIComponent(request.sport)}/${encodeURIComponent(request.league)}/summary?event=${encodeURIComponent(request.gameId)}`;
        const xhr = new XMLHttpRequest();
        request.xhr = xhr;
        const next = Object.assign({}, root.detailsRequests);
        next[String(key)] = request;
        root.detailsRequests = next;
        root.detailsRevision += 1;
        xhr.timeout = 12000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                root.finishDetailsRequest(String(key), xhr.status, xhr.responseText);
        };
        xhr.onerror = function() { root.finishDetailsRequest(String(key), 0, ""); };
        xhr.ontimeout = function() { root.finishDetailsRequest(String(key), 0, ""); };
        xhr.open("GET", url);
        xhr.send();
    }

    function removeDetailsRequest(key) {
        const next = ({});
        for (const requestKey in root.detailsRequests) {
            if (requestKey !== String(key))
                next[requestKey] = root.detailsRequests[requestKey];
        }
        root.detailsRequests = next;
        root.detailsRevision += 1;
    }

    function finishDetailsRequest(key, httpStatus, responseText) {
        const request = root.detailsRequests[String(key)] ?? null;
        if (!request)
            return;
        if (httpStatus === 403 && request.hostIndex + 1 < root.apiHosts.length) {
            request.hostIndex += 1;
            root.startDetailsRequest(String(key), request);
            return;
        }
        root.removeDetailsRequest(key);

        if (httpStatus !== 200) {
            const errors = Object.assign({}, root.detailsErrors);
            errors[String(key)] = `ESPN HTTP ${String(httpStatus)}`;
            root.detailsErrors = errors;
            console.warn(`[SportsService] Details fetch failed for ${String(key)} (HTTP ${String(httpStatus)})`);
            return;
        }

        try {
            const parsed = JSON.parse(String(responseText ?? "{}"));
            const nextCache = Object.assign({}, root.detailsCache);
            nextCache[String(key)] = {
                fetchedAt: Date.now(),
                sport: request.sport,
                league: request.league,
                data: parsed
            };
            root.detailsCache = root.prunedDetailsCache(nextCache);
            const errors = Object.assign({}, root.detailsErrors);
            delete errors[String(key)];
            root.detailsErrors = errors;
            root.detailsRevision += 1;
            root.scheduleCacheSave();
        } catch (error) {
            const errors = Object.assign({}, root.detailsErrors);
            errors[String(key)] = "ESPN returned invalid game details";
            root.detailsErrors = errors;
            root.detailsRevision += 1;
            console.warn(`[SportsService] Invalid details payload: ${String(error)}`);
        }
    }

    // ── Persistent cache ─────────────────────────────────────────────────

    function prunedCache(values, maximumEntries) {
        const keys = Object.keys(values).sort((left, right) => Number(values[right]?.fetchedAt ?? 0) - Number(values[left]?.fetchedAt ?? 0));
        const result = ({});
        for (let i = 0; i < Math.min(keys.length, maximumEntries); i++)
            result[keys[i]] = values[keys[i]];
        return result;
    }

    function prunedDetailsCache(values) {
        const source = values ?? ({});
        const keys = Object.keys(source).sort((left, right) => {
            return Number(source[right]?.fetchedAt ?? 0) - Number(source[left]?.fetchedAt ?? 0);
        });
        const result = ({});
        let bytes = 2;
        for (let i = 0; i < keys.length && Object.keys(result).length < root.maximumDetailsEntries; i++) {
            const key = keys[i];
            const entry = source[key];
            let entryBytes = 0;
            try {
                entryBytes = JSON.stringify(entry?.data ?? entry).length;
            } catch (error) {
                entryBytes = root.maximumDetailsCacheBytes;
            }
            // Keep the newest response even if it alone exceeds the budget;
            // otherwise opening one game would silently show no details.
            if (Object.keys(result).length > 0 && bytes + entryBytes > root.maximumDetailsCacheBytes)
                continue;
            result[key] = entry;
            bytes += entryBytes;
        }
        return result;
    }

    function scheduleCacheSave() {
        if (root.timetableActive)
            cacheSaveDebounce.restart();
    }

    function loadCacheFromDisk(includeDetails) {
        if (!includeDetails) {
            // The compact bar/dock projection is fetched independently. The
            // weekly timetable cache can be several MiB on disk and is not
            // useful until the timetable acquires its first subscriber.
            root.scheduleCache = ({});
            root.scheduleCacheLoaded = false;
            root.detailsCache = ({});
            root.detailsCacheLoaded = false;
            root.detailsRevision += 1;
            root.finishCacheLoad();
            return;
        }

        // The FileView re-reads the file on every open, but its parsed,
        // compacted projection survives the close. Parsing it again would put
        // the whole document back through QV4 for nothing.
        if (root.scheduleCacheLoaded && root.detailsCacheLoaded) {
            root.finishCacheLoad();
            return;
        }

        try {
            const parsed = JSON.parse(sportsCacheFile.text() || "{}");
            const validSchema = parsed?.schema === 1 || parsed?.schema === 2;
            root.scheduleCache = validSchema
                ? root.compactScheduleCache(parsed.schedules)
                : ({});
            root.scheduleCacheLoaded = true;
            root.detailsCache = includeDetails && validSchema && parsed?.details && typeof parsed.details === "object"
                ? root.prunedDetailsCache(parsed.details)
                : ({});
            root.detailsCacheLoaded = includeDetails;
        } catch (error) {
            root.scheduleCache = ({});
            root.scheduleCacheLoaded = false;
            root.detailsCache = ({});
            root.detailsCacheLoaded = false;
        }
        root.detailsRevision += 1;
        root.finishCacheLoad();
    }

    function loadDetailsCacheFromDisk() {
        if (!root.cacheReady || !root.timetableActive || (root.scheduleCacheLoaded && root.detailsCacheLoaded))
            return;
        try {
            const parsed = JSON.parse(sportsCacheFile.text() || "{}");
            const validSchema = parsed?.schema === 1 || parsed?.schema === 2;
            if (!root.scheduleCacheLoaded) {
                root.scheduleCache = validSchema
                    ? root.compactScheduleCache(parsed.schedules)
                    : ({});
                root.scheduleCacheLoaded = true;
            }
            root.detailsCache = validSchema && parsed?.details && typeof parsed.details === "object"
                ? root.prunedDetailsCache(parsed.details)
                : ({});
        } catch (error) {
            root.scheduleCache = ({});
            root.scheduleCacheLoaded = false;
            root.detailsCache = ({});
        }
        root.detailsCacheLoaded = true;
        root.detailsRevision += 1;
    }

    function saveCache() {
        if (!root.timetableActive)
            return;
        if (!root.cacheReady) {
            cacheSaveDebounce.restart();
            return;
        }
        // Details may have been deliberately unloaded after the timetable
        // closed. Preserve the on-disk copy without keeping its parsed object
        // graph resident in the singleton.
        let details = root.detailsCache;
        if (!root.detailsCacheLoaded) {
            try {
                const parsed = JSON.parse(sportsCacheFile.text() || "{}");
                details = parsed?.details && typeof parsed.details === "object"
                    ? root.prunedDetailsCache(parsed.details)
                    : ({});
            } catch (error) {
                details = ({});
            }
        }
        sportsCacheFile.setText(JSON.stringify({
            schema: 2,
            schedules: root.scheduleCache,
            details: details
        }));
    }

    function finishCacheLoad() {
        root.cacheReady = true;
        if (root.pendingRangeRequest && root.timetableRangeStart.length > 0) {
            const force = root.pendingRangeForce;
            root.pendingRangeRequest = false;
            root.pendingRangeForce = false;
            root.requestTimetableRange(root.timetableRangeStart, root.timetableRangeEnd, force);
        }
    }

    function processGames(events, forSearch = false) {
        let validGames = [];

        const filterStr = forSearch ? "" : teamFilter.trim().toLowerCase();
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
            if (!forSearch && state === "pre" && hoursUntilStart > Config.options.bar.sports.showBeforeHours)
                continue;

            const minsSinceStart = (now - eventDate) / (1000 * 60);
            if (!forSearch && state === "post" && minsSinceStart > Config.options.bar.sports.showAfterMinutes)
                continue;

            let comp = event.competitions[0];
            const isRacing = (event.sportCategory === "racing" || event.sportCategory === "motorsports" || event.leagueName.toLowerCase().includes("f1") || event.leagueName.toLowerCase().includes("formula"));

            if (isRacing && event.competitions.length > 1) {
                let activeComp = event.competitions.find(c => c.status.type.state === "in");
                if (activeComp) {
                    comp = activeComp;
                } else {
                    let preComp = event.competitions.find(c => c.status.type.state === "pre");
                    if (preComp) {
                        comp = preComp;
                    } else {
                        comp = event.competitions[event.competitions.length - 1];
                    }
                }
            }

            if (!comp.competitors) {
                comp.competitors = [];
            }

            let matchesFilter = false;
            if (teamsToMatch.length > 0) {
                if (isRacing) {
                    for (let k = 0; k < comp.competitors.length; k++) {
                        const competitor = comp.competitors[k];
                        const athleteName = competitor.athlete ? (competitor.athlete.displayName || "").toLowerCase() : "";
                        const teamName = competitor.team ? (competitor.team.displayName || competitor.team.name || "").toLowerCase() : "";
                        for (let j = 0; j < teamsToMatch.length; j++) {
                            const t = teamsToMatch[j];
                            if (athleteName.includes(t) || teamName.includes(t)) {
                                matchesFilter = true;
                                break;
                            }
                        }
                        if (matchesFilter) break;
                    }
                } else {
                    const homeTeamName = (comp.competitors[0] && comp.competitors[0].team ? (comp.competitors[0].team.shortDisplayName || comp.competitors[0].team.name || "") : "").toLowerCase();
                    const awayTeamName = (comp.competitors[1] && comp.competitors[1].team ? (comp.competitors[1].team.shortDisplayName || comp.competitors[1].team.name || "") : "").toLowerCase();
                    for (let j = 0; j < teamsToMatch.length; j++) {
                        const t = teamsToMatch[j];
                        if (homeTeamName.includes(t) || awayTeamName.includes(t)) {
                            matchesFilter = true;
                            break;
                        }
                    }
                }
            } else {
                matchesFilter = true;
            }

            if (matchesFilter) {
                let lastPlayText = "";
                const compState = comp.status ? comp.status.type.state : state;
                if (compState === "in") {
                    const situation = comp.situation || null;
                    lastPlayText = situation && situation.lastPlay && situation.lastPlay.text ? situation.lastPlay.text : "";

                    if (lastPlayText === "" && comp.details && comp.details.length > 0) {
                        const lastEvent = comp.details[comp.details.length - 1];
                        const type = lastEvent.type ? lastEvent.type.text : "";
                        const athlete = lastEvent.athletesInvolved && lastEvent.athletesInvolved.length > 0 ? lastEvent.athletesInvolved[0].displayName : "";
                        const clock = lastEvent.clock ? lastEvent.clock.displayValue : "";

                        if (type !== "") {
                            lastPlayText = `${type}${athlete !== "" ? " - " + athlete : ""}${clock !== "" ? " (" + clock + ")" : ""}`;
                        }
                    }
                }

                let home = { name: "TBD", score: "0", logo: event.leagueLogo || "", winner: false };
                let away = { name: "TBD", score: "0", logo: event.leagueLogo || "", winner: false };

                if (isRacing) {
                    if (comp.competitors.length > 0) {
                        const first = comp.competitors[0];
                        home = {
                            name: first.athlete ? (first.athlete.shortName || first.athlete.displayName) : (first.team ? first.team.shortDisplayName : "P1"),
                            score: first.displayValue || (first.score ? "P1 (" + first.score + ")" : "P1"),
                            logo: first.team ? first.team.logo : (first.athlete ? first.athlete.headshot : (event.leagueLogo || "")),
                            winner: first.winner || false
                        };
                    }
                    if (comp.competitors.length > 1) {
                        const second = comp.competitors[1];
                        away = {
                            name: second.athlete ? (second.athlete.shortName || second.athlete.displayName) : (second.team ? second.team.shortDisplayName : "P2"),
                            score: second.displayValue || (second.score ? "P2 (" + second.score + ")" : "P2"),
                            logo: second.team ? second.team.logo : (second.athlete ? second.athlete.headshot : (event.leagueLogo || "")),
                            winner: second.winner || false
                        };
                    }
                } else {
                    if (comp.competitors.length >= 2) {
                        let first = comp.competitors[0];
                        let second = comp.competitors[1];
                        if (first.homeAway === "away" || second.homeAway === "home") {
                            first = comp.competitors[1];
                            second = comp.competitors[0];
                        }
                        home = {
                            name: first.team ? (first.team.shortDisplayName || first.team.name) : "Home",
                            score: first.score || "0",
                            logo: first.team ? first.team.logo : "",
                            winner: first.winner || false
                        };
                        away = {
                            name: second.team ? (second.team.shortDisplayName || second.team.name) : "Away",
                            score: second.score || "0",
                            logo: second.team ? second.team.logo : "",
                            winner: second.winner || false
                        };
                    } else if (comp.competitors.length === 1) {
                        let first = comp.competitors[0];
                        home = {
                            name: first.team ? (first.team.shortDisplayName || first.team.name) : "Home",
                            score: first.score || "0",
                            logo: first.team ? first.team.logo : "",
                            winner: first.winner || false
                        };
                    }
                }

                if (!home.logo || home.logo === "") home.logo = event.leagueLogo || "";
                if (!away.logo || away.logo === "") away.logo = event.leagueLogo || "";

                validGames.push({
                    id: event.id,
                    name: event.name,
                    date: event.date,
                    league: event.leagueName,
                    leagueId: event.leagueId ?? "",
                    sport: event.sportCategory ?? "",
                    status: (comp.status && comp.status.type && comp.status.type.state === "pre")
                        ? formatMatchTime(event.date)
                        : ((comp.status && comp.status.type && comp.status.type.state === "in")
                            ? compactMatchStatus(comp.status.type.detail, "in")
                            : (comp.status ? comp.status.type.detail : (event.status ? event.status.type.detail : ""))),
                    state: comp.status ? comp.status.type.state : state,
                    lastPlay: lastPlayText,
                    home: home,
                    away: away
                });
            }
        }

        if (forSearch) {
            validGames.sort((left, right) => new Date(left.date).getTime() - new Date(right.date).getTime());
            root.searchGames = validGames;
            return;
        }

        if (customOrder && customOrder.length > 0) {
            validGames.sort((a, b) => {
                let idxA = customOrder.indexOf(a.id);
                let idxB = customOrder.indexOf(b.id);
                if (idxA !== -1 && idxB !== -1) {
                    return idxA - idxB;
                }
                if (idxA !== -1) return -1;
                if (idxB !== -1) return 1;
                const order = { "in": 0, "pre": 1, "post": 2 };
                return (order[a.state] || 3) - (order[b.state] || 3);
            });
        } else {
            validGames.sort((a, b) => {
                const order = { "in": 0, "pre": 1, "post": 2 };
                return (order[a.state] || 3) - (order[b.state] || 3);
            });
        }

        let nextIndex = 0;
        let currentId = currentGame ? currentGame.id : Config.options.bar.sports.activeGameId;

        if (currentId) {
            let foundIndex = -1;
            for (let i = 0; i < validGames.length; i++) {
                if (validGames[i].id === currentId) {
                    foundIndex = i;
                    break;
                }
            }
            if (foundIndex !== -1) {
                nextIndex = foundIndex;
            } else if (currentGameIndex < validGames.length) {
                nextIndex = currentGameIndex;
            }
        } else if (currentGameIndex < validGames.length) {
            nextIndex = currentGameIndex;
        }

        allGames = validGames;
        currentGameIndex = nextIndex;
        currentGame = allGames.length > 0 ? allGames[currentGameIndex] : null;
    }

    Timer {
        id: timetableProjectionTimer
        interval: 4
        repeat: true
        onTriggered: root.projectNextTimetableBatch()
    }

    Timer {
        id: refreshTimer
        interval: updateInterval * 1000
        running: enabled && (!timetableActive || !root.timetableRangeCoversToday)
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchGames()
    }

    Timer {
        id: timetableRefreshTimer
        interval: Math.max(10, updateInterval) * 1000
        running: root.timetableActive && root.timetableRangeStart.length > 0
        repeat: true
        onTriggered: {
            const live = root.rangeNeedsLiveRefresh();
            root.requestTimetableRange(root.timetableRangeStart, root.timetableRangeEnd, live);
            if (root.focusedGameId.length > 0) {
                const focused = root.gameById(root.focusedGameId);
                if (focused && (root.gameNeedsLiveRefresh(focused) || root.gameNearKickoff(focused)))
                    root.requestGameDetails(focused, root.gameNeedsLiveRefresh(focused));
            }
        }
    }

    Timer {
        id: cacheSaveDebounce
        interval: 350
        onTriggered: root.saveCache()
    }

    Timer {
        id: cacheRetryTimer
        interval: 500
        onTriggered: {
            if (root.timetableActive)
                sportsCacheFile.reload();
        }
    }

    FileView {
        id: sportsCacheFile
        // The bar/dock compact projection does not use the weekly cache. A
        // blank path makes FileView release its text buffer while no timetable
        // consumer is alive, instead of retaining the whole JSON document.
        path: root.timetableActive ? Directories.sportsCachePath : ""
        watchChanges: false
        atomicWrites: true
        printErrors: false

        onLoaded: {
            if (!root.timetableActive)
                return;
            root.loadCacheFromDisk(root.timetableActive);
        }

        onLoadFailed: error => {
            if (!root.timetableActive)
                return;
            if (error !== FileViewError.FileNotFound)
                return;
            if (Date.now() - root.cacheInitTimestamp <= root.cacheGracePeriod) {
                cacheRetryTimer.restart();
                return;
            }
            root.scheduleCache = ({});
            root.scheduleCacheLoaded = false;
            root.detailsCache = ({});
            root.detailsCacheLoaded = false;
            root.finishCacheLoad();
            root.saveCache();
        }
    }

    readonly property real cacheInitTimestamp: Date.now()
    readonly property int cacheGracePeriod: 2000

    onEnabledChanged: {
        if (!enabled)
            root.cancelCompactRequests();
        if (enabled && !root.timetableActive) {
            fetchGames();
        } else {
            allGames = [];
            currentGameIndex = 0;
            currentGame = null;
        }
    }

    onTimetableActiveChanged: {
        if (!root.timetableActive && root.enabled) {
            root.fetchGames();
        }
    }

    onTeamFilterChanged: {
        if (root.timetableActive)
            root.rebuildTimetableGames();
        if (root.enabled && !root.timetableActive)
            root.fetchGames();
    }

    Connections {
        target: Config.options.bar.sports
        function onMonitoredLeaguesChanged() {
            if (root.timetableActive && root.timetableRangeStart.length > 0)
                root.requestTimetableRange(root.timetableRangeStart, root.timetableRangeEnd, false);
            if (root.enabled && !root.timetableActive)
                root.fetchGames();
            if (root.searchSubscribers > 0)
                root.fetchSearchGamesForToday();
        }
    }

    Connections {
        target: Config.options.search.modules.sports
        function onLeaguesChanged() {
            if (root.searchSubscribers > 0)
                root.fetchSearchGamesForToday();
        }
    }

}
