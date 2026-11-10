.pragma library

// Pure normalisers for ESPN's soccer endpoints. FootballService feeds raw JSON
// in and gets small plain objects back, so the UI never walks ESPN's shapes and
// a payload change is fixed in one place.

function str(value) {
    return value === undefined || value === null ? "" : String(value);
}

function arr(value) {
    return Array.isArray(value) ? value : [];
}

function num(value) {
    const parsed = parseFloat(value);
    return isNaN(parsed) ? 0 : parsed;
}

function logoForTeamId(id) {
    return id ? `https://a.espncdn.com/i/teamlogos/soccer/500/${id}.png` : "";
}

function teamLogo(team) {
    if (!team)
        return "";
    if (typeof team.logo === "string" && team.logo !== "")
        return team.logo;
    const logos = arr(team.logos).length > 0 ? arr(team.logos) : arr(team.logo);
    if (logos.length > 0 && logos[0].href)
        return str(logos[0].href);
    return logoForTeamId(str(team.id));
}

function scoreText(value) {
    if (value && typeof value === "object")
        return str(value.displayValue ?? value.value);
    return str(value);
}

function competitor(entry) {
    const team = entry?.team ?? {};
    const record = arr(entry?.records)[0] ?? arr(entry?.record)[0] ?? null;
    return {
        id: str(team.id ?? entry?.id),
        name: str(team.displayName || team.name || team.location),
        short: str(team.shortDisplayName || team.displayName || team.name),
        abbr: str(team.abbreviation),
        logo: teamLogo(team),
        color: str(team.color),
        score: scoreText(entry?.score),
        shootout: entry?.shootoutScore !== undefined && entry?.shootoutScore !== null ? scoreText(entry.shootoutScore) : "",
        winner: entry?.winner === true,
        form: str(entry?.form),
        record: str(record?.summary ?? record?.displayValue)
    };
}

function sides(competitors) {
    const list = arr(competitors);
    const home = list.find(item => item?.homeAway === "home") ?? list[0] ?? {};
    const away = list.find(item => item?.homeAway === "away") ?? (list[1] !== home ? list[1] : {}) ?? {};
    return { home: home, away: away };
}

function matchLink(event) {
    const links = arr(event?.links);
    let fallback = "";
    for (let i = 0; i < links.length; i++) {
        const href = str(links[i]?.href);
        if (!/^https?:\/\//.test(href))
            continue;
        const rel = arr(links[i].rel);
        if (rel.indexOf("summary") !== -1 && rel.indexOf("desktop") !== -1)
            return href;
        if (fallback === "")
            fallback = href;
    }
    return fallback !== "" ? fallback : (event?.id ? `https://www.espn.com/soccer/match/_/gameId/${event.id}` : "");
}

// Goals and red cards for a match row, from the scoreboard's `details`.
function incidents(competition, homeId) {
    const result = [];
    const details = arr(competition?.details);
    for (let i = 0; i < details.length; i++) {
        const detail = details[i];
        if (!detail || detail.shootout)
            continue;
        let kind = "";
        if (detail.scoringPlay)
            kind = detail.ownGoal ? "own" : (detail.penaltyKick ? "pen" : "goal");
        else if (detail.redCard)
            kind = "red";
        if (kind === "")
            continue;
        const athlete = arr(detail.athletesInvolved)[0] ?? null;
        result.push({
            kind: kind,
            side: str(detail.team?.id) === homeId ? "home" : "away",
            name: str(athlete?.shortName || athlete?.displayName),
            minute: str(detail.clock?.displayValue)
        });
    }
    return result;
}

function statusOf(competition, event) {
    const status = competition?.status ?? event?.status ?? {};
    const type = status.type ?? {};
    return {
        state: str(type.state),
        completed: type.completed === true,
        detail: str(type.shortDetail || type.detail),
        description: str(type.description),
        clock: str(status.displayClock),
        period: status.period ?? 0
    };
}

function normalizeMatch(event, league) {
    const competition = arr(event?.competitions)[0] ?? {};
    const pair = sides(competition.competitors);
    const home = competitor(pair.home);
    const away = competitor(pair.away);
    const status = statusOf(competition, event);
    const eventLeague = event?.league ?? null;
    const broadcasts = [];
    arr(competition.broadcasts).forEach(item => arr(item?.names).forEach(name => broadcasts.push(str(name))));
    arr(competition.geoBroadcasts).forEach(item => {
        const name = str(item?.media?.shortName);
        if (name !== "" && broadcasts.indexOf(name) === -1)
            broadcasts.push(name);
    });
    return {
        id: str(event?.id),
        date: str(event?.date || competition.date),
        league: league ?? {
            slug: str(eventLeague?.slug),
            name: str(eventLeague?.name),
            short: str(eventLeague?.abbreviation || eventLeague?.shortName),
            logo: ""
        },
        state: status.state,
        completed: status.completed,
        statusDetail: status.detail,
        statusDescription: status.description,
        clock: status.clock,
        period: status.period,
        home: home,
        away: away,
        venue: str(competition.venue?.fullName || event?.venue?.displayName),
        city: str(competition.venue?.address?.city),
        note: str(arr(competition.notes)[0]?.headline),
        broadcasts: broadcasts.join(", "),
        link: matchLink(event),
        incidents: incidents(competition, home.id)
    };
}

function normalizeScoreboard(payload, league) {
    const leagueInfo = arr(payload?.leagues)[0] ?? null;
    const resolved = {
        slug: league.slug,
        name: league.name || str(leagueInfo?.name),
        short: league.short || str(leagueInfo?.abbreviation),
        logo: league.logo || str(arr(leagueInfo?.logos)[0]?.href)
    };
    return arr(payload?.events).map(event => normalizeMatch(event, resolved));
}

// ── Match summary ────────────────────────────────────────────────────────────

function playerStat(player, name) {
    const stats = arr(player?.stats);
    for (let i = 0; i < stats.length; i++) {
        if (stats[i]?.name === name)
            return Math.round(num(stats[i].value ?? stats[i].displayValue));
    }
    return 0;
}

function subFlag(value) {
    return value === true || (value && typeof value === "object" && value.didSub === true);
}

function normalizePlayer(player) {
    const athlete = player?.athlete ?? {};
    return {
        id: str(athlete.id),
        name: str(athlete.displayName || athlete.fullName),
        short: str(athlete.shortName || athlete.displayName),
        last: str(athlete.lastName || athlete.shortName || athlete.displayName),
        jersey: str(player?.jersey),
        pos: str(player?.position?.abbreviation),
        posName: str(player?.position?.displayName),
        place: parseInt(player?.formationPlace, 10) || 0,
        starter: player?.starter === true,
        subbedIn: subFlag(player?.subbedIn),
        subbedOut: subFlag(player?.subbedOut),
        goals: playerStat(player, "totalGoals"),
        assists: playerStat(player, "goalAssists"),
        ownGoals: playerStat(player, "ownGoals"),
        yellow: playerStat(player, "yellowCards"),
        red: playerStat(player, "redCards"),
        saves: playerStat(player, "saves"),
        shots: playerStat(player, "totalShots")
    };
}

function keyEventKind(type) {
    const value = str(type).toLowerCase();
    if (value.indexOf("own-goal") !== -1 || value.indexOf("own goal") !== -1)
        return "own";
    if (value.indexOf("penalty") !== -1 && value.indexOf("miss") !== -1)
        return "penmiss";
    if (value.indexOf("penalty") !== -1 && value.indexOf("saved") !== -1)
        return "penmiss";
    if (value.indexOf("goal") !== -1 || value.indexOf("penalty---scored") !== -1)
        return "goal";
    if (value.indexOf("yellow-red") !== -1 || value.indexOf("red-card") !== -1)
        return "red";
    if (value.indexOf("yellow-card") !== -1)
        return "yellow";
    if (value.indexOf("substitution") !== -1)
        return "sub";
    if (value.indexOf("var") !== -1)
        return "var";
    if (value.indexOf("delay") !== -1)
        return "";
    if (value === "kickoff" || value.indexOf("halftime") !== -1 || value.indexOf("start-") === 0
            || value.indexOf("end-") === 0 || value.indexOf("full-time") !== -1 || value.indexOf("extra") !== -1
            || value.indexOf("shootout") !== -1)
        return "phase";
    return "other";
}

const statOrder = [
    "possessionPct", "totalShots", "shotsOnTarget", "wonCorners", "foulsCommitted", "offsides",
    "yellowCards", "redCards", "saves", "totalPasses", "accuratePasses", "passPct", "totalCrosses",
    "accurateCrosses", "totalLongBalls", "accurateLongBalls", "totalTackles", "effectiveTackles",
    "interceptions", "totalClearance", "blockedShots", "penaltyKickGoals"
];

function statValue(key, stat) {
    const raw = num(stat?.value ?? stat?.displayValue);
    if (key === "possessionPct")
        return { value: raw, text: `${Math.round(raw)}%` };
    if (/Pct$/.test(key)) {
        const percent = raw <= 1 ? raw * 100 : raw;
        return { value: percent, text: `${Math.round(percent)}%` };
    }
    return { value: raw, text: str(stat?.displayValue ?? Math.round(raw)) };
}

function normalizeStats(boxscore, homeId) {
    const teams = arr(boxscore?.teams);
    const homeTeam = teams.find(item => str(item?.team?.id) === homeId || item?.homeAway === "home") ?? teams[0];
    const awayTeam = teams.find(item => item !== homeTeam) ?? null;
    if (!homeTeam || !awayTeam)
        return [];
    const byName = list => {
        const map = ({});
        arr(list).forEach(stat => { if (stat?.name) map[stat.name] = stat; });
        return map;
    };
    const homeStats = byName(homeTeam.statistics);
    const awayStats = byName(awayTeam.statistics);
    const result = [];
    for (let i = 0; i < statOrder.length; i++) {
        const key = statOrder[i];
        if (!homeStats[key] || !awayStats[key])
            continue;
        const h = statValue(key, homeStats[key]);
        const a = statValue(key, awayStats[key]);
        result.push({
            key: key,
            label: str(homeStats[key].label || homeStats[key].displayName || key),
            home: h.text,
            away: a.text,
            homeValue: h.value,
            awayValue: a.value
        });
    }
    return result;
}

function standingStat(entry, name) {
    const stats = arr(entry?.stats);
    for (let i = 0; i < stats.length; i++) {
        if (stats[i]?.name === name || stats[i]?.type === name)
            return stats[i];
    }
    return null;
}

function normalizeStandingEntry(entry, highlightIds) {
    const team = typeof entry?.team === "object" && entry.team !== null ? entry.team : null;
    const id = str(team?.id ?? entry?.id);
    const value = name => standingStat(entry, name);
    const gd = value("pointDifferential");
    const logoList = arr(entry?.logo);
    return {
        rank: Math.round(num(value("rank")?.value)) || 0,
        id: id,
        name: str(team ? (team.displayName || team.name) : entry?.team),
        short: str(team ? (team.shortDisplayName || team.abbreviation || team.displayName) : entry?.team),
        logo: team ? teamLogo(team) : (logoList.length > 0 ? str(logoList[0].href) : logoForTeamId(id)),
        played: str(value("gamesPlayed")?.displayValue ?? "0"),
        wins: str(value("wins")?.displayValue ?? "0"),
        draws: str(value("ties")?.displayValue ?? "0"),
        losses: str(value("losses")?.displayValue ?? "0"),
        goalsFor: str(value("pointsFor")?.displayValue ?? ""),
        goalsAgainst: str(value("pointsAgainst")?.displayValue ?? ""),
        goalDiff: str(gd?.displayValue ?? "0"),
        points: str(value("points")?.displayValue ?? "0"),
        noteColor: str(entry?.note?.color),
        noteText: str(entry?.note?.description),
        highlight: highlightIds.indexOf(id) !== -1
    };
}

function sortStandings(entries) {
    return entries.slice().sort((left, right) => {
        if (left.rank && right.rank)
            return left.rank - right.rank;
        return num(right.points) - num(left.points);
    });
}

function normalizeStandingGroups(groups, highlightIds) {
    return arr(groups).map(group => ({
        name: str(group?.name || group?.header),
        entries: sortStandings(arr(group?.standings?.entries).map(entry => normalizeStandingEntry(entry, highlightIds)))
    })).filter(group => group.entries.length > 0);
}

function gameResult(teamId, homeId, awayId, homeScore, awayScore) {
    const own = teamId === homeId ? num(homeScore) : num(awayScore);
    const other = teamId === homeId ? num(awayScore) : num(homeScore);
    return own > other ? "W" : (own < other ? "L" : "D");
}

function normalizeForm(lastFive, homeId) {
    return arr(lastFive).map(entry => {
        const teamId = str(entry?.team?.id);
        return {
            teamId: teamId,
            side: teamId === homeId ? "home" : "away",
            name: str(entry?.team?.displayName),
            logo: teamLogo(entry?.team),
            games: arr(entry?.events).map(game => ({
                id: str(game?.id),
                date: str(game?.gameDate),
                opponent: str(game?.opponent?.displayName),
                opponentLogo: teamLogo(game?.opponent),
                atVs: str(game?.atVs),
                score: str(game?.score),
                competition: str(game?.leagueName),
                result: gameResult(teamId, str(game?.homeTeamId), str(game?.awayTeamId), game?.homeTeamScore, game?.awayTeamScore)
            }))
        };
    });
}

function normalizeHeadToHead(seasonSeries) {
    const series = arr(seasonSeries).find(item => item?.type === "head-to-head") ?? arr(seasonSeries)[0] ?? null;
    if (!series)
        return { summary: "", games: [] };
    return {
        summary: str(series.summary),
        games: arr(series.events).map(event => {
            const pair = sides(event?.competitors);
            return {
                id: str(event?.id),
                date: str(event?.date),
                completed: event?.statusType?.completed === true,
                status: str(event?.statusType?.shortDetail || event?.statusType?.detail),
                home: competitor(pair.home),
                away: competitor(pair.away)
            };
        })
    };
}

function normalizeNews(news) {
    return arr(news?.articles).slice(0, 8).map(article => ({
        headline: str(article?.headline),
        description: str(article?.description),
        published: str(article?.published),
        link: str(article?.links?.web?.href),
        image: str(arr(article?.images)[0]?.url),
        video: str(article?.type) === "Media"
    })).filter(article => article.headline !== "" && article.link !== "");
}

function normalizeDetail(payload, eventId) {
    const header = payload?.header ?? {};
    const competition = arr(header.competitions)[0] ?? {};
    const pair = sides(competition.competitors);
    const home = competitor(pair.home);
    const away = competitor(pair.away);
    const status = statusOf(competition, null);
    const info = payload?.gameInfo ?? {};
    const sideOf = teamId => str(teamId) === home.id ? "home" : (str(teamId) === away.id ? "away" : "");

    const lineups = arr(payload?.rosters).map(roster => {
        const players = arr(roster?.roster).map(normalizePlayer);
        const teamId = str(roster?.team?.id);
        return {
            side: roster?.homeAway === "away" ? "away" : (roster?.homeAway === "home" ? "home" : sideOf(teamId)),
            teamId: teamId,
            formation: str(roster?.formation),
            starters: players.filter(player => player.starter).sort((left, right) => left.place - right.place),
            subs: players.filter(player => !player.starter)
        };
    }).filter(lineup => lineup.starters.length > 0 || lineup.subs.length > 0);

    const keyEvents = arr(payload?.keyEvents).map(event => ({
        id: str(event?.id),
        kind: keyEventKind(event?.type?.type || event?.type?.text),
        label: str(event?.type?.text),
        text: str(event?.text),
        short: str(event?.shortText),
        minute: str(event?.clock?.displayValue),
        period: event?.period?.number ?? 0,
        side: sideOf(event?.team?.id),
        players: arr(event?.participants).map(item => str(item?.athlete?.displayName)).filter(name => name !== "")
    })).filter(event => event.kind !== "");

    const commentary = arr(payload?.commentary).map(entry => ({
        minute: str(entry?.time?.displayValue),
        text: str(entry?.text),
        sequence: entry?.sequence ?? 0
    })).filter(entry => entry.text !== "").reverse();

    const officials = arr(info.officials).map(item => str(item?.displayName || item?.fullName)).filter(name => name !== "");
    const address = info.venue?.address ?? {};

    return {
        id: str(eventId || competition.id),
        fetchedAt: Date.now(),
        date: str(competition.date),
        state: status.state,
        completed: status.completed,
        statusDetail: status.detail,
        statusDescription: status.description,
        clock: status.clock,
        period: status.period,
        home: home,
        away: away,
        league: {
            slug: str(header.league?.slug),
            name: str(header.league?.name),
            short: str(header.league?.abbreviation || header.league?.shortName)
        },
        season: str(header.season?.name),
        venue: str(info.venue?.fullName),
        city: [str(address.city), str(address.country)].filter(part => part !== "").join(", "),
        attendance: Math.round(num(info.attendance)),
        officials: officials,
        lineups: lineups,
        keyEvents: keyEvents,
        commentary: commentary,
        stats: normalizeStats(payload?.boxscore, home.id),
        standings: normalizeStandingGroups(payload?.standings?.groups, [home.id, away.id]),
        standingsTitle: str(payload?.standings?.header),
        form: normalizeForm(payload?.lastFiveGames, home.id),
        headToHead: normalizeHeadToHead(payload?.seasonseries),
        news: normalizeNews(payload?.news),
        link: eventId ? `https://www.espn.com/soccer/match/_/gameId/${eventId}` : ""
    };
}

// ── League standings, team schedule, search ──────────────────────────────────

function normalizeStandings(payload) {
    const children = arr(payload?.children);
    const groups = children.length > 0
        ? children.map(child => ({ name: str(child?.name), standings: child?.standings }))
        : (payload?.standings ? [{ name: str(payload?.name), standings: payload.standings }] : []);
    return {
        name: str(payload?.name),
        season: str(arr(payload?.seasons)[0]?.displayName ?? payload?.season?.displayName),
        groups: normalizeStandingGroups(groups, [])
    };
}

function normalizeSchedule(payload) {
    const team = payload?.team ?? {};
    const matches = arr(payload?.events).map(event => {
        const league = event?.league ?? null;
        return normalizeMatch(event, league ? {
            slug: str(league.slug),
            name: str(league.name),
            short: str(league.abbreviation || league.shortName),
            logo: ""
        } : null);
    });
    return {
        team: {
            id: str(team.id),
            name: str(team.displayName || team.name),
            short: str(team.shortDisplayName || team.abbreviation),
            logo: teamLogo(team),
            color: str(team.color),
            standing: str(team.standingSummary),
            record: str(team.recordSummary)
        },
        matches: matches
    };
}

function normalizeSearch(payload) {
    const groups = arr(payload?.results);
    const teams = groups.find(group => group?.type === "team");
    return arr(teams?.contents).filter(item => item?.sport === "soccer" || /^s:600~/.test(str(item?.uid))).map(item => {
        const match = /~t:(\d+)/.exec(str(item?.uid));
        const id = match ? match[1] : "";
        return {
            id: id,
            name: str(item?.displayName),
            subtitle: str(item?.subtitle),
            league: str(item?.defaultLeagueSlug),
            logo: str(item?.image?.default) || logoForTeamId(id)
        };
    }).filter(item => item.id !== "");
}
