pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * UI-independent ESPN scoreboard adapter for AI calls.
 *
 * It deliberately does not read the bar's monitored-league settings and does
 * not call SportsService.processGames(): an AI request may name any supported
 * league and must not change the bar's current game or persist UI state.
 */
QtObject {
    id: root

    readonly property int cacheTtlMs: 30000
    readonly property int maximumCacheEntries: 16
    // site.api.espn.com is intermittently denied by Akamai in this
    // environment. The web API host serves the same scoreboard payload and
    // is kept as the first endpoint, with the legacy host as a fallback.
    readonly property list<string> apiHosts: ["site.web.api.espn.com", "site.api.espn.com"]
    property var cache: ({})
    property var pendingRequests: ({})

    signal resultReady(string key, string callId, string sessionId, var outcome)

    function boundedText(value, maximum = 240): string {
        return String(value ?? "").trim().slice(0, maximum);
    }

    function endpointFor(value): var {
        const raw = String(value ?? "").trim().toLowerCase();
        const aliases = {
            "nba": { sport: "basketball", league: "nba", name: "NBA" },
            "nfl": { sport: "football", league: "nfl", name: "NFL" },
            "mlb": { sport: "baseball", league: "mlb", name: "MLB" },
            "nhl": { sport: "hockey", league: "nhl", name: "NHL" },
            "epl": { sport: "soccer", league: "eng.1", name: "Premier League" },
            "premier league": { sport: "soccer", league: "eng.1", name: "Premier League" },
            "brasileirao": { sport: "soccer", league: "bra.1", name: "Brasileirão" },
            "brasileirão": { sport: "soccer", league: "bra.1", name: "Brasileirão" },
            "bundesliga": { sport: "soccer", league: "ger.1", name: "Bundesliga" },
            "laliga": { sport: "soccer", league: "esp.1", name: "LaLiga" },
            "serie a": { sport: "soccer", league: "ita.1", name: "Serie A" },
            "ligue 1": { sport: "soccer", league: "fra.1", name: "Ligue 1" },
            "champions league": { sport: "soccer", league: "uefa.champions", name: "Champions League" },
            "libertadores": { sport: "soccer", league: "conmebol.libertadores", name: "Libertadores" }
        };
        if (aliases[raw] !== undefined)
            return aliases[raw];

        const separator = raw.indexOf("/") >= 0 ? "/" : (raw.indexOf(":") >= 0 ? ":" : "");
        if (separator.length > 0) {
            const parts = raw.split(separator);
            if (parts.length === 2 && ["soccer", "basketball", "football", "baseball", "hockey"].indexOf(parts[0]) >= 0 && parts[1].length > 0)
                return { sport: parts[0], league: parts[1], name: parts[1] };
        }

        // ESPN soccer league ids contain a dot. Accepting those ids keeps the
        // query parameterized while the route itself remains allow-listed.
        if (/^[a-z0-9]+(?:\.[a-z0-9]+)+$/.test(raw))
            return { sport: "soccer", league: raw, name: root.leagueName(raw) };
        return null;
    }

    function leagueName(league): string {
        const known = {
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
        };
        return known[String(league)] ?? String(league);
    }

    function dateParameter(value): string {
        const raw = String(value ?? "").trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(raw))
            return "";
        const parts = raw.split("-").map(Number);
        const date = new Date(parts[0], parts[1] - 1, parts[2]);
        if (date.getFullYear() !== parts[0] || date.getMonth() !== parts[1] - 1 || date.getDate() !== parts[2])
            return "";
        return raw.replace(/-/g, "");
    }

    function localIsoDate(): string {
        const now = new Date();
        const month = String(now.getMonth() + 1).padStart(2, "0");
        const day = String(now.getDate()).padStart(2, "0");
        return `${now.getFullYear()}-${month}-${day}`;
    }

    function statusValues(value): var {
        const rawValues = Array.isArray(value) ? value : String(value ?? "").split(/[\s,]+/);
        const aliases = {
            "scheduled": "pre",
            "upcoming": "pre",
            "live": "in",
            "inprogress": "in",
            "in-progress": "in",
            "final": "post",
            "completed": "post"
        };
        const values = [];
        for (let i = 0; i < rawValues.length; i++) {
            const raw = String(rawValues[i] ?? "").trim().toLowerCase();
            if (raw.length === 0)
                continue;
            const normalized = aliases[raw] || raw;
            if (["pre", "in", "post"].indexOf(normalized) >= 0 && values.indexOf(normalized) < 0)
                values.push(normalized);
        }
        return values;
    }

    function competitorDto(competitor, fallback): var {
        const item = competitor ?? ({});
        const team = item.team ?? ({});
        const athlete = item.athlete ?? ({});
        return {
            name: root.boundedText(team.displayName || team.shortDisplayName || team.name || athlete.displayName || fallback, 120),
            abbreviation: root.boundedText(team.abbreviation || team.shortName || athlete.shortName || "", 20),
            score: String(item.score ?? item.displayValue ?? ""),
            logo: String(team.logo || team.logos?.[0]?.href || athlete.headshot || ""),
            winner: item.winner === true
        };
    }

    function eventDto(event, route, responseLeagueName): var {
        const item = event ?? ({});
        const competitions = Array.isArray(item.competitions) ? item.competitions : [];
        const competition = competitions.length > 0 ? (competitions[0] ?? ({})) : ({});
        const competitors = Array.isArray(competition.competitors) ? competition.competitors : [];
        const eventStatus = item.status ?? ({});
        const eventType = eventStatus.type ?? ({ });
        const competitionStatus = competition.status ?? ({});
        const competitionType = competitionStatus.type ?? ({ });
        const state = String(competitionType.state ?? eventType.state ?? "unknown");
        const detail = root.boundedText(competitionType.detail || eventType.detail || eventStatus.displayClock || "", 160);

        let homeItem = competitors.length > 0 ? competitors[0] : null;
        let awayItem = competitors.length > 1 ? competitors[1] : null;
        if (homeItem?.homeAway === "away" || awayItem?.homeAway === "home") {
            const swap = homeItem;
            homeItem = awayItem;
            awayItem = swap;
        }

        const broadcasts = Array.isArray(competition.broadcasts) ? competition.broadcasts : [];
        const firstBroadcast = broadcasts.length > 0 ? (broadcasts[0] ?? ({})) : ({});
        const names = Array.isArray(firstBroadcast.names) ? firstBroadcast.names : [];
        const venue = competition.venue ?? ({});

        return {
            id: String(item.id ?? ""),
            name: root.boundedText(item.name || item.shortName || "Untitled game", 180),
            league: root.boundedText(responseLeagueName || route.name || root.leagueName(route.league), 100),
            leagueId: route.league,
            sport: route.sport,
            startTime: String(item.date ?? ""),
            state: state,
            status: detail || (state === "pre" ? "Scheduled" : state),
            home: root.competitorDto(homeItem, "TBD"),
            away: root.competitorDto(awayItem, "TBD"),
            venue: root.boundedText(venue.fullName || venue.address?.city || "", 140),
            broadcast: root.boundedText(names.length > 0 ? names.join(", ") : (firstBroadcast.name || ""), 140),
            lastPlay: root.boundedText(competition.situation?.lastPlay?.text || "", 180)
        };
    }

    function filteredGames(response, route, args): var {
        const events = Array.isArray(response?.events) ? response.events : [];
        const responseLeagues = Array.isArray(response?.leagues) ? response.leagues : [];
        const responseLeague = responseLeagues.length > 0 ? (responseLeagues[0] ?? ({})) : ({});
        const responseLeagueName = root.boundedText(responseLeague.name || "", 100);
        const team = String(args?.team ?? "").trim().toLowerCase();
        const statuses = root.statusValues(args?.status);
        const games = [];
        for (let i = 0; i < events.length; i++) {
            const game = root.eventDto(events[i], route, responseLeagueName);
            const haystack = [game.name, game.home.name, game.home.abbreviation, game.away.name, game.away.abbreviation].join(" ").toLowerCase();
            if (team.length > 0 && haystack.indexOf(team) < 0)
                continue;
            if (statuses.length > 0 && statuses.indexOf(game.state) < 0)
                continue;
            games.push(game);
        }
        const limit = Math.max(1, Math.min(20, Number(args?.limit ?? 10) || 10));
        return games.slice(0, limit);
    }

    function cacheKey(route, args): string {
        return [route.sport, route.league, String(args?.date ?? ""), String(args?.team ?? "").trim().toLowerCase(), root.statusValues(args?.status).join(","), String(args?.limit ?? 10)].join("|");
    }

    function freshCache(key): var {
        const entry = root.cache[String(key)];
        if (!entry || Date.now() - Number(entry.at ?? 0) > root.cacheTtlMs)
            return null;
        return Object.assign({}, entry.data, { cacheHit: true, freshness: "cached" });
    }

    function storeCache(key, data): void {
        const next = Object.assign({}, root.cache, { [String(key)]: { at: Date.now(), data: data } });
        const keys = Object.keys(next);
        while (keys.length > root.maximumCacheEntries) {
            const oldest = keys.shift();
            delete next[oldest];
        }
        root.cache = next;
    }

    function removePending(key): var {
        const request = root.pendingRequests[String(key)] ?? null;
        if (!request)
            return null;
        const next = ({ });
        for (const entry in root.pendingRequests) {
            if (entry !== String(key))
                next[entry] = root.pendingRequests[entry];
        }
        root.pendingRequests = next;
        return request;
    }

    function finish(key, httpStatus, responseText): void {
        const request = root.pendingRequests[String(key)] ?? null;
        if (!request)
            return;

        // Keep the subscriber and correlation entry alive while switching
        // hosts. Releasing here would make the late fallback callback look
        // like an unrelated request and could underflow SportsService's
        // subscriber count.
        if (httpStatus === 403 && request.hostIndex + 1 < root.apiHosts.length) {
            request.hostIndex += 1;
            root.startRequest(String(key), request);
            return;
        }

        root.removePending(key);
        SportsService.releaseAiSubscriber();

        let outcome = null;
        if (httpStatus !== 200) {
            outcome = {
                status: "error",
                summary: `ESPN returned HTTP ${httpStatus}`,
                data: null,
                retryable: httpStatus === 0 || httpStatus >= 500
            };
        } else {
            try {
                const response = JSON.parse(String(responseText ?? "{}"));
                const games = root.filteredGames(response, request.route, request.args);
                const data = {
                    league: request.route.name || root.leagueName(request.route.league),
                    leagueId: request.route.league,
                    sport: request.route.sport,
                    games: games,
                    fetchedAt: new Date().toISOString(),
                    freshness: "fresh",
                    cacheHit: false
                };
                root.storeCache(request.cacheKey, data);
                outcome = {
                    status: "success",
                    summary: games.length > 0 ? "ESPN games loaded" : "No games matched the request",
                    data: data
                };
            } catch (error) {
                outcome = {
                    status: "error",
                    summary: "ESPN returned invalid JSON",
                    data: null,
                    retryable: true
                };
            }
        }
        root.resultReady(String(key), request.callId, request.sessionId, outcome);
    }

    function startRequest(key, request): void {
        const host = root.apiHosts[request.hostIndex] || root.apiHosts[0];
        const date = root.dateParameter(request.args.date);
        const url = `https://${host}/apis/site/v2/sports/${encodeURIComponent(request.route.sport)}/${encodeURIComponent(request.route.league)}/scoreboard` + (date.length > 0 ? `?dates=${date}` : "");
        const xhr = new XMLHttpRequest();
        request.xhr = xhr;
        root.pendingRequests = Object.assign({}, root.pendingRequests, { [String(key)]: request });
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                root.finish(String(key), xhr.status, xhr.responseText);
        };
        xhr.onerror = function() { root.finish(String(key), 0, ""); };
        xhr.ontimeout = function() { root.finish(String(key), 0, ""); };
        xhr.open("GET", url);
        xhr.send();
    }

    function query(key, callId, sessionId, args, force = false): var {
        const route = root.endpointFor(args?.league);
        if (!route)
            return { status: "error", summary: "Unsupported ESPN league", data: null, retryable: false };
        const requestedDate = String(args?.date ?? "").trim();
        const isoDate = requestedDate.length > 0 ? requestedDate : root.localIsoDate();
        const date = root.dateParameter(isoDate);
        if (date.length === 0)
            return { status: "error", summary: "Date must use YYYY-MM-DD", data: null, retryable: false };

        const requestedStatus = String(args?.status ?? "").trim();
        const statuses = root.statusValues(args?.status);
        if (requestedStatus.length > 0 && statuses.length === 0)
            return { status: "error", summary: "Status must be pre, in or post", data: null, retryable: false };

        const normalizedArgs = Object.assign({}, args, { date: isoDate, status: statuses.join(",") });
        const requestKey = String(key);
        const cacheKeyValue = root.cacheKey(route, normalizedArgs);
        if (!force) {
            const cached = root.freshCache(cacheKeyValue);
            if (cached)
                return { status: "success", summary: "Fresh ESPN cache result", data: cached };
        }
        if (root.pendingRequests[requestKey] !== undefined)
            return { status: "pending" };

        const request = { xhr: null, hostIndex: 0, callId: String(callId ?? ""), sessionId: String(sessionId ?? ""), route: route, args: normalizedArgs, cacheKey: cacheKeyValue };
        root.pendingRequests = Object.assign({}, root.pendingRequests, { [requestKey]: request });
        SportsService.acquireAiSubscriber();
        root.startRequest(requestKey, request);
        return { status: "pending" };
    }

    function abortAll(): void {
        const keys = Object.keys(root.pendingRequests);
        for (let i = 0; i < keys.length; i++) {
            const request = root.removePending(keys[i]);
            if (!request)
                continue;
            request.xhr.abort();
            SportsService.releaseAiSubscriber();
        }
    }
}
