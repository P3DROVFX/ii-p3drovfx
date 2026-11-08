import QtQuick
import qs.modules.common

/**
 * Reads and writes what the user follows. Leagues live in
 * `bar.sports.monitoredLeagues` ({sport, league, name, logo, enabled}); teams in
 * `bar.sports.teamFilter` (the names SportsService matches) with their crests
 * kept in `bar.sports.followedTeams`. Lists are rebuilt and assigned whole, and
 * only when they really change (Config writes on every assignment).
 */
QtObject {
    id: root

    readonly property var leagues: Array.from(Config.options.bar.sports.monitoredLeagues ?? [])
    readonly property var teamTerms: String(Config.options.bar.sports.teamFilter ?? "").split(",")
        .map(term => term.trim()).filter(term => term.length > 0)
    readonly property var teamDetails: Array.from(Config.options.bar.sports.followedTeams ?? [])
    readonly property int activeLeagueCount: root.leagues.filter(item => item?.enabled).length

    function key(sport, league) {
        return `${sport}/${league}`;
    }

    function isFollowed(sport, league) {
        return root.leagues.some(item => item?.sport === sport && item?.league === league);
    }

    function follow(sport, entry) {
        if (root.isFollowed(sport, entry.slug))
            return;
        const list = JSON.parse(JSON.stringify(root.leagues));
        list.push({ sport: sport, league: entry.slug, name: entry.name, logo: entry.logo ?? "", enabled: true });
        Config.options.bar.sports.monitoredLeagues = list;
    }

    function unfollow(sport, league) {
        const list = JSON.parse(JSON.stringify(root.leagues)).filter(item => !(item.sport === sport && item.league === league));
        if (list.length !== root.leagues.length)
            Config.options.bar.sports.monitoredLeagues = list;
    }

    function toggle(sport, entry) {
        if (root.isFollowed(sport, entry.slug))
            root.unfollow(sport, entry.slug);
        else
            root.follow(sport, entry);
    }

    function setEnabled(sport, league, enabled) {
        const list = JSON.parse(JSON.stringify(root.leagues));
        const match = list.find(item => item.sport === sport && item.league === league);
        if (!match || match.enabled === enabled)
            return;
        match.enabled = enabled;
        Config.options.bar.sports.monitoredLeagues = list;
    }

    // Older entries were saved with a slug-ish name ("Eng 1"); the catalog
    // fixes them when it learns the real one.
    function refreshName(sport, entry) {
        const list = JSON.parse(JSON.stringify(root.leagues));
        const match = list.find(item => item.sport === sport && item.league === entry.slug);
        if (!match || (match.name === entry.name && (match.logo ?? "") === (entry.logo ?? "")))
            return;
        match.name = entry.name;
        match.logo = entry.logo ?? "";
        Config.options.bar.sports.monitoredLeagues = list;
    }

    // ── Teams ────────────────────────────────────────────────────────────────
    function teamDetail(name) {
        const lower = String(name).toLowerCase();
        return root.teamDetails.find(item => String(item?.name ?? "").toLowerCase() === lower) ?? null;
    }

    function isTeamFollowed(name) {
        const lower = String(name).toLowerCase();
        return root.teamTerms.some(term => term.toLowerCase() === lower);
    }

    function followTeam(team) {
        if (root.isTeamFollowed(team.name))
            return;
        Config.options.bar.sports.teamFilter = root.teamTerms.concat([team.name]).join(", ");
        const details = JSON.parse(JSON.stringify(root.teamDetails)).filter(item => String(item.name).toLowerCase() !== team.name.toLowerCase());
        details.push({ id: team.id ?? "", name: team.name, logo: team.logo ?? "", sport: team.sport ?? "", league: team.league ?? "" });
        Config.options.bar.sports.followedTeams = details;
    }

    function unfollowTeam(name) {
        const lower = String(name).toLowerCase();
        Config.options.bar.sports.teamFilter = root.teamTerms.filter(term => term.toLowerCase() !== lower).join(", ");
        const details = root.teamDetails.filter(item => String(item?.name ?? "").toLowerCase() !== lower);
        if (details.length !== root.teamDetails.length)
            Config.options.bar.sports.followedTeams = JSON.parse(JSON.stringify(details));
    }

    function clearTeams() {
        Config.options.bar.sports.teamFilter = "";
        if (root.teamDetails.length > 0)
            Config.options.bar.sports.followedTeams = [];
    }
}
