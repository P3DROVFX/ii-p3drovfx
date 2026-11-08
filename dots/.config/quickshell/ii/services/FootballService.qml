pragma Singleton
import qs
import QtQuick
import Quickshell
import qs.modules.common
import "FootballData.js" as FootballData

/**
 * Data source of the cheatsheet's Football overview.
 *
 * Headless and on demand: nothing is fetched until the page asks, and the live
 * refresh only runs while a page holds `acquire()`. Every request is localised
 * with the shell language (ESPN translates status, commentary and stat labels),
 * cached with a short TTL for live data and a long one for the rest, and
 * de-duplicated while in flight. Results are published as new objects so the
 * page's bindings re-evaluate exactly once per change.
 *
 * Independent from SportsService, which feeds the bar: different leagues,
 * different cadence, and nothing here may wake the bar widgets.
 */
Singleton {
    id: root

    // ── Consumers ────────────────────────────────────────────────────────────
    property int subscribers: 0
    readonly property bool apiEnabled: Config.options?.bar?.sports?.apiEnabled ?? true
    readonly property bool active: apiEnabled && subscribers > 0

    function acquire() {
        root.subscribers += 1;
    }
    function release() {
        root.subscribers = Math.max(0, root.subscribers - 1);
    }

    // ── Settings ─────────────────────────────────────────────────────────────
    readonly property var settings: Config.options.cheatsheet.football
    readonly property var enabledLeagues: (root.settings?.leagues ?? []).filter(slug => root.leagueBySlug(slug) !== null)
    readonly property var favoriteTeams: root.settings?.favoriteTeams ?? []
    readonly property int liveRefreshMs: Math.max(15, root.settings?.refreshInterval ?? 30) * 1000

    readonly property string languageCode: String(Translation.languageCode || "en_US")
    readonly property string lang: root.languageCode.split(/[_-]/)[0].toLowerCase() || "en"
    readonly property string region: (root.languageCode.split(/[_-]/)[1] ?? root.lang).toLowerCase()
    readonly property string localeQuery: `lang=${encodeURIComponent(root.lang)}&region=${encodeURIComponent(root.region)}`
    readonly property string apiBase: "https://site.api.espn.com/apis/site/v2/sports/soccer"

    // The leagues the page can show. Slugs are ESPN's; logos are its CDN.
    readonly property var leagueCatalog: [
        { slug: "eng.1", name: "Premier League", country: "England", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/23.png" },
        { slug: "esp.1", name: "LALIGA", country: "Spain", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/15.png" },
        { slug: "ita.1", name: "Serie A", country: "Italy", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/12.png" },
        { slug: "ger.1", name: "Bundesliga", country: "Germany", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/10.png" },
        { slug: "fra.1", name: "Ligue 1", country: "France", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/9.png" },
        { slug: "bra.1", name: "Brasileirão", country: "Brazil", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/85.png" },
        { slug: "por.1", name: "Liga Portugal", country: "Portugal", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/14.png" },
        { slug: "ned.1", name: "Eredivisie", country: "Netherlands", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/11.png" },
        { slug: "arg.1", name: "Liga Profesional", country: "Argentina", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/1.png" },
        { slug: "usa.1", name: "MLS", country: "USA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/19.png" },
        { slug: "mex.1", name: "Liga MX", country: "Mexico", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/22.png" },
        { slug: "tur.1", name: "Süper Lig", country: "Turkey", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/18.png" },
        { slug: "bel.1", name: "Pro League", country: "Belgium", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/6.png" },
        { slug: "sco.1", name: "Premiership", country: "Scotland", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/45.png" },
        { slug: "uefa.champions", name: "Champions League", country: "UEFA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/2.png" },
        { slug: "uefa.europa", name: "Europa League", country: "UEFA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/2310.png" },
        { slug: "uefa.europa.conf", name: "Conference League", country: "UEFA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/20296.png" },
        { slug: "uefa.nations", name: "Nations League", country: "UEFA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/2395.png" },
        { slug: "conmebol.libertadores", name: "Libertadores", country: "CONMEBOL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/58.png" },
        { slug: "conmebol.sudamericana", name: "Sudamericana", country: "CONMEBOL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/1208.png" },
        { slug: "bra.copa_do_brazil", name: "Copa do Brasil", country: "Brazil", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/528.png" },
        { slug: "eng.fa", name: "FA Cup", country: "England", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/40.png" },
        { slug: "esp.copa_del_rey", name: "Copa del Rey", country: "Spain", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/80.png" },
        { slug: "fifa.world", name: "World Cup", country: "FIFA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/4.png" },
        { slug: "fifa.cwc", name: "Club World Cup", country: "FIFA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/1932.png" }
    ]

    function leagueBySlug(slug) {
        for (let i = 0; i < root.leagueCatalog.length; i++) {
            if (root.leagueCatalog[i].slug === slug)
                return root.leagueCatalog[i];
        }
        return null;
    }

    function isLeagueEnabled(slug) {
        return root.enabledLeagues.indexOf(slug) !== -1;
    }

    function setLeagueEnabled(slug, enabled) {
        const current = (root.settings?.leagues ?? []).slice();
        const index = current.indexOf(slug);
        if (enabled && index === -1)
            current.push(slug);
        else if (!enabled && index !== -1)
            current.splice(index, 1);
        else
            return;
        Config.options.cheatsheet.football.leagues = current;
        root.dayCache = ({});
        root.revision += 1;
    }

    // ── Favourites ───────────────────────────────────────────────────────────
    function isFavorite(teamId) {
        const id = String(teamId ?? "");
        return id !== "" && root.favoriteTeams.some(team => String(team?.id) === id);
    }

    function toggleFavorite(team) {
        const id = String(team?.id ?? "");
        if (id === "")
            return;
        const current = root.favoriteTeams.slice();
        const index = current.findIndex(item => String(item?.id) === id);
        if (index !== -1)
            current.splice(index, 1);
        else
            current.push({ id: id, name: String(team.name ?? ""), logo: String(team.logo ?? ""), league: String(team.league ?? "") });
        Config.options.cheatsheet.football.favoriteTeams = current;
    }

    function favoriteIds() {
        return root.favoriteTeams.map(team => String(team?.id));
    }

    // ── Generic request plumbing ─────────────────────────────────────────────
    property var _inFlight: ({})
    property int revision: 0

    function request(key, url, onDone) {
        if (root._inFlight[key] || !root.apiEnabled)
            return;
        const flights = Object.assign({}, root._inFlight);
        flights[key] = true;
        root._inFlight = flights;
        const xhr = new XMLHttpRequest();
        let finished = false;
        const finish = function() {
            if (finished)
                return;
            finished = true;
            const next = Object.assign({}, root._inFlight);
            delete next[key];
            root._inFlight = next;
            let payload = null;
            if (xhr.status === 200) {
                try {
                    payload = JSON.parse(xhr.responseText);
                } catch (error) {
                    payload = null;
                }
            }
            onDone(payload);
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                finish();
        };
        xhr.onerror = finish;
        xhr.ontimeout = finish;
        xhr.open("GET", url);
        xhr.timeout = 15000;
        xhr.send();
    }

    function isLoading(key) {
        return root._inFlight[key] === true;
    }

    // In play, or past its kickoff without a result yet: data that changes by
    // the minute. A match cached before kickoff must not stay "upcoming".
    function liveish(match) {
        if (!match)
            return false;
        if (match.state === "in")
            return true;
        return match.state === "pre" && match.date !== "" && new Date(match.date).getTime() <= Date.now() + 60000;
    }

    function fresh(entry, liveTtl, staleTtl) {
        if (!entry || !entry.fetchedAt)
            return false;
        return Date.now() - entry.fetchedAt < (entry.live ? liveTtl : staleTtl);
    }

    // ── Matches by day ───────────────────────────────────────────────────────
    // dayKey → { fetchedAt, live, matches, error, pending }
    property var dayCache: ({})

    function dayKey(date) {
        const d = date instanceof Date ? date : new Date(date);
        const pad = value => String(value).padStart(2, "0");
        return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
    }

    function dayEntry(key) {
        void root.revision;
        return root.dayCache[key] ?? null;
    }

    function setDayEntry(key, entry) {
        const next = Object.assign({}, root.dayCache);
        next[key] = entry;
        root.dayCache = next;
    }

    function requestDay(key, force = false) {
        const existing = root.dayCache[key];
        if (existing?.pending)
            return;
        if (!force && root.fresh(existing, root.liveRefreshMs - 1000, 30 * 60 * 1000))
            return;
        const leagues = root.enabledLeagues.slice();
        if (leagues.length === 0) {
            root.setDayEntry(key, { fetchedAt: Date.now(), live: false, matches: [], error: "", pending: false });
            return;
        }
        root.setDayEntry(key, Object.assign({}, existing ?? { matches: [] }, { pending: true }));
        let remaining = leagues.length;
        const collected = [];
        let failures = 0;
        leagues.forEach(slug => {
            const league = root.leagueBySlug(slug);
            const url = `${root.apiBase}/${encodeURIComponent(slug)}/scoreboard?dates=${key}&${root.localeQuery}`;
            root.request(`day:${key}:${slug}`, url, payload => {
                if (payload)
                    FootballData.normalizeScoreboard(payload, league).forEach(match => collected.push(match));
                else
                    failures += 1;
                remaining -= 1;
                if (remaining > 0)
                    return;
                // A league's scoreboard can include the previous or next day
                // around midnight UTC; keep only matches on the asked local day.
                const matches = collected.filter(match => root.dayKey(match.date) === key)
                    .sort((left, right) => new Date(left.date) - new Date(right.date));
                root.setDayEntry(key, {
                    fetchedAt: Date.now(),
                    live: matches.some(match => root.liveish(match)),
                    matches: matches,
                    error: failures === leagues.length ? Translation.tr("Could not reach ESPN") : "",
                    pending: false
                });
            });
        });
    }

    // ── Match details ────────────────────────────────────────────────────────
    property var detailCache: ({})

    function details(eventId) {
        return root.detailCache[String(eventId)] ?? null;
    }

    function requestDetails(eventId, force = false) {
        const id = String(eventId ?? "");
        if (id === "")
            return;
        const existing = root.detailCache[id];
        if (!force && existing && root.fresh({ fetchedAt: existing.fetchedAt, live: root.liveish(existing) },
                root.liveRefreshMs - 1000, existing.state === "pre" ? 10 * 60 * 1000 : 60 * 60 * 1000))
            return;
        root.request(`detail:${id}`, `${root.apiBase}/all/summary?event=${encodeURIComponent(id)}&${root.localeQuery}`, payload => {
            if (!payload)
                return;
            const next = Object.assign({}, root.detailCache);
            next[id] = FootballData.normalizeDetail(payload, id);
            // Keep the cache small: the open match and a few recent ones.
            const keys = Object.keys(next);
            if (keys.length > 12) {
                keys.sort((left, right) => next[left].fetchedAt - next[right].fetchedAt);
                for (let i = 0; i < keys.length - 12; i++)
                    delete next[keys[i]];
            }
            root.detailCache = next;
        });
    }

    // English position abbreviations per match, for the formation layout
    // (the localised payload translates them). Only fetched for a lineup on
    // screen, and only when the shell language is not English already.
    property var positionsCache: ({})

    function positions(eventId) {
        return root.positionsCache[String(eventId)] ?? null;
    }

    function requestPositions(eventId) {
        const id = String(eventId ?? "");
        if (id === "" || root.lang === "en" || root.positionsCache[id])
            return;
        root.request(`positions:${id}`, `${root.apiBase}/all/summary?event=${encodeURIComponent(id)}`, payload => {
            const map = ({});
            (payload?.rosters ?? []).forEach(roster => (roster?.roster ?? []).forEach(player => {
                const athleteId = String(player?.athlete?.id ?? "");
                if (athleteId !== "")
                    map[athleteId] = String(player?.position?.abbreviation ?? "");
            }));
            const next = Object.assign({}, root.positionsCache);
            next[id] = map;
            const keys = Object.keys(next);
            if (keys.length > 12)
                delete next[keys[0]];
            root.positionsCache = next;
        });
    }

    // ── League standings ─────────────────────────────────────────────────────
    property var standingsCache: ({})

    function standings(slug) {
        return root.standingsCache[slug] ?? null;
    }

    function requestStandings(slug, force = false) {
        if (!slug)
            return;
        const existing = root.standingsCache[slug];
        if (!force && root.fresh(existing, 0, 30 * 60 * 1000))
            return;
        root.request(`standings:${slug}`, `https://site.api.espn.com/apis/v2/sports/soccer/${encodeURIComponent(slug)}/standings?${root.localeQuery}`, payload => {
            const next = Object.assign({}, root.standingsCache);
            next[slug] = payload ? Object.assign({ fetchedAt: Date.now(), error: "" }, FootballData.normalizeStandings(payload))
                : { fetchedAt: Date.now(), error: Translation.tr("Could not reach ESPN"), groups: [] };
            root.standingsCache = next;
        });
    }

    // The league's current round: its scoreboard without a date.
    property var leagueRoundCache: ({})

    function leagueRound(slug) {
        return root.leagueRoundCache[slug] ?? null;
    }

    function requestLeagueRound(slug, force = false) {
        if (!slug)
            return;
        const existing = root.leagueRoundCache[slug];
        if (!force && root.fresh(existing, root.liveRefreshMs - 1000, 15 * 60 * 1000))
            return;
        const league = root.leagueBySlug(slug) ?? { slug: slug, name: "", short: "", logo: "" };
        root.request(`round:${slug}`, `${root.apiBase}/${encodeURIComponent(slug)}/scoreboard?${root.localeQuery}`, payload => {
            const matches = payload ? FootballData.normalizeScoreboard(payload, league)
                .sort((left, right) => new Date(left.date) - new Date(right.date)) : [];
            const next = Object.assign({}, root.leagueRoundCache);
            next[slug] = {
                fetchedAt: Date.now(),
                live: matches.some(match => root.liveish(match)),
                matches: matches,
                round: String(payload?.week?.number ?? ""),
                error: payload ? "" : Translation.tr("Could not reach ESPN")
            };
            root.leagueRoundCache = next;
        });
    }

    // ── Team overview ────────────────────────────────────────────────────────
    // teamId → { fetchedAt, team, results, fixtures, live }
    property var teamCache: ({})

    function team(teamId) {
        return root.teamCache[String(teamId)] ?? null;
    }

    function requestTeam(teamId, slug, force = false) {
        const id = String(teamId ?? "");
        if (id === "")
            return;
        const existing = root.teamCache[id];
        if (!force && root.fresh(existing, root.liveRefreshMs, 20 * 60 * 1000))
            return;
        const league = slug || "all";
        const base = `${root.apiBase}/${encodeURIComponent(league)}/teams/${encodeURIComponent(id)}/schedule?${root.localeQuery}`;
        const parts = ({});
        const merge = () => {
            if (parts.results === undefined || parts.fixtures === undefined)
                return;
            const info = parts.results?.team ?? parts.fixtures?.team ?? null;
            const results = (parts.results?.matches ?? []).filter(match => match.state !== "pre")
                .sort((left, right) => new Date(right.date) - new Date(left.date));
            const fixtures = (parts.fixtures?.matches ?? []).filter(match => match.state !== "post")
                .sort((left, right) => new Date(left.date) - new Date(right.date));
            const next = Object.assign({}, root.teamCache);
            next[id] = {
                fetchedAt: Date.now(),
                team: info,
                results: results,
                fixtures: fixtures,
                live: fixtures.some(match => root.liveish(match)),
                error: !info ? Translation.tr("Could not reach ESPN") : ""
            };
            root.teamCache = next;
        };
        root.request(`team:${id}:results`, base, payload => {
            parts.results = payload ? FootballData.normalizeSchedule(payload) : null;
            merge();
        });
        root.request(`team:${id}:fixtures`, `${base}&fixture=true`, payload => {
            parts.fixtures = payload ? FootballData.normalizeSchedule(payload) : null;
            merge();
        });
    }

    // ── Team search ──────────────────────────────────────────────────────────
    property string searchQuery: ""
    property var searchResults: []
    property bool searchLoading: false
    property int _searchGeneration: 0

    function searchTeams(query) {
        const text = String(query ?? "").trim();
        root.searchQuery = text;
        root._searchGeneration += 1;
        const generation = root._searchGeneration;
        if (text.length < 2 || !root.apiEnabled) {
            root.searchResults = [];
            root.searchLoading = false;
            return;
        }
        root.searchLoading = true;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || generation !== root._searchGeneration)
                return;
            root.searchLoading = false;
            try {
                root.searchResults = xhr.status === 200 ? FootballData.normalizeSearch(JSON.parse(xhr.responseText)) : [];
            } catch (error) {
                root.searchResults = [];
            }
        };
        xhr.open("GET", `https://site.web.api.espn.com/apis/search/v2?query=${encodeURIComponent(text)}&limit=20&type=team&${root.localeQuery}`);
        xhr.timeout = 12000;
        xhr.send();
    }

    // ── Links ────────────────────────────────────────────────────────────────
    readonly property var highlightTerms: ({
        "pt": "melhores momentos",
        "es": "resumen",
        "fr": "résumé",
        "it": "highlights",
        "de": "Highlights",
        "nl": "samenvatting",
        "ru": "обзор матча",
        "uk": "огляд матчу",
        "tr": "geniş özet",
        "ja": "ハイライト",
        "he": "תקציר",
        "vi": "highlights",
        "zh": "集锦"
    })

    // A YouTube search for the match's highlights, written the way people
    // search for them in the shell's language ("melhores momentos", "resumen").
    function highlightsUrl(match) {
        if (!match)
            return "";
        const term = root.highlightTerms[root.lang] ?? "highlights";
        const joiner = (root.lang === "pt" || root.lang === "es") ? "x" : "vs";
        const date = match.date ? new Date(match.date).toLocaleDateString(Qt.locale(root.languageCode), Locale.ShortFormat) : "";
        const query = `${match.home?.name ?? ""} ${joiner} ${match.away?.name ?? ""} ${term} ${date}`.replace(/\s+/g, " ").trim();
        return `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`;
    }

    // Win / draw / loss initials as football is written in the shell language.
    readonly property var resultLetters: ({
        "pt": { W: "V", D: "E", L: "D" },
        "es": { W: "G", D: "E", L: "P" },
        "fr": { W: "V", D: "N", L: "D" },
        "it": { W: "V", D: "N", L: "P" },
        "de": { W: "S", D: "U", L: "N" }
    })

    function resultLetter(result) {
        return (root.resultLetters[root.lang] ?? {})[result] ?? result;
    }

    function espnUrl(match) {
        return match?.link || (match?.id ? `https://www.espn.com/soccer/match/_/gameId/${match.id}` : "");
    }

    // ── Live refresh ─────────────────────────────────────────────────────────
    // The page tells the service what it shows; only that is refreshed, and
    // only while something on it is live.
    property string watchedDay: ""
    property string watchedMatch: ""
    property string watchedTeam: ""
    property string watchedTeamLeague: ""
    property string watchedLeague: ""

    Timer {
        interval: root.liveRefreshMs
        repeat: true
        running: root.active
        onTriggered: {
            const day = root.dayCache[root.watchedDay];
            if (root.watchedDay !== "" && day?.live)
                root.requestDay(root.watchedDay, true);
            const detail = root.detailCache[root.watchedMatch];
            if (root.watchedMatch !== "" && detail && root.liveish(detail))
                root.requestDetails(root.watchedMatch, true);
            const round = root.leagueRoundCache[root.watchedLeague];
            if (root.watchedLeague !== "" && round?.live)
                root.requestLeagueRound(root.watchedLeague, true);
            const teamEntry = root.teamCache[root.watchedTeam];
            if (root.watchedTeam !== "" && teamEntry?.live)
                root.requestTeam(root.watchedTeam, root.watchedTeamLeague, true);
        }
    }

    // Coming back (the cheatsheet reopened, the tab shown again) refreshes what
    // is on screen at once: the page tree outlives a closed cheatsheet, so
    // nothing else would ask before the next tick. The TTLs keep it cheap.
    function refreshWatched() {
        if (root.watchedDay !== "")
            root.requestDay(root.watchedDay);
        if (root.watchedMatch !== "")
            root.requestDetails(root.watchedMatch);
        if (root.watchedLeague !== "") {
            root.requestLeagueRound(root.watchedLeague);
            root.requestStandings(root.watchedLeague);
        }
        if (root.watchedTeam !== "")
            root.requestTeam(root.watchedTeam, root.watchedTeamLeague);
    }

    onActiveChanged: {
        if (root.active)
            Qt.callLater(root.refreshWatched);
    }

    // A language change invalidates every localised payload.
    onLanguageCodeChanged: {
        root.dayCache = ({});
        root.detailCache = ({});
        root.standingsCache = ({});
        root.teamCache = ({});
        root.leagueRoundCache = ({});
        root.revision += 1;
    }
}
