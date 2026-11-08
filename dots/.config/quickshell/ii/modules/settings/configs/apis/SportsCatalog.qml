import QtQuick
import qs.modules.common
import qs.services

/**
 * What the Sports page can offer, straight from ESPN: every league of a sport
 * with its real name and logo (`leagues/dropdown`), the leagues popular in the
 * shell's region first, and a team search across all sports. Fetched on demand
 * per sport and kept for the life of the page.
 */
QtObject {
    id: root

    readonly property string languageCode: String(Translation.languageCode || "en_US")
    readonly property string lang: root.languageCode.split(/[_-]/)[0].toLowerCase() || "en"
    readonly property string region: (root.languageCode.split(/[_-]/)[1] ?? root.lang).toLowerCase()

    readonly property var sports: [
        { id: "soccer", label: Translation.tr("Football"), icon: "sports_soccer" },
        { id: "basketball", label: Translation.tr("Basketball"), icon: "sports_basketball" },
        { id: "football", label: Translation.tr("American football"), icon: "sports_football" },
        { id: "hockey", label: Translation.tr("Ice hockey"), icon: "sports_hockey" },
        { id: "baseball", label: Translation.tr("Baseball"), icon: "sports_baseball" },
        { id: "racing", label: Translation.tr("Motorsport"), icon: "sports_motorsports" },
        { id: "tennis", label: Translation.tr("Tennis"), icon: "sports_tennis" },
        { id: "mma", label: Translation.tr("MMA"), icon: "sports_mma" },
        { id: "rugby", label: Translation.tr("Rugby"), icon: "sports_rugby" },
        { id: "golf", label: Translation.tr("Golf"), icon: "sports_golf" },
        { id: "volleyball", label: Translation.tr("Volleyball"), icon: "sports_volleyball" },
        { id: "lacrosse", label: Translation.tr("Lacrosse"), icon: "sports" },
        { id: "australian-football", label: Translation.tr("Aussie rules"), icon: "sports_rugby" }
    ]

    function sportById(id) {
        return root.sports.find(sport => sport.id === id) ?? { id: id, label: id, icon: "sports" };
    }

    // sport → { all: [...], popular: [...], loading, error }
    property var leagues: ({})

    function normalize(list) {
        return (Array.isArray(list) ? list : []).map(item => ({
            slug: String(item?.slug ?? ""),
            name: String(item?.name ?? item?.shortName ?? item?.slug ?? ""),
            short: String(item?.abbreviation ?? item?.shortName ?? ""),
            logo: String((item?.logos ?? [])[0]?.href ?? "")
        })).filter(item => item.slug !== "");
    }

    function setEntry(sport, patch) {
        const next = Object.assign({}, root.leagues);
        next[sport] = Object.assign({}, next[sport] ?? { all: [], popular: [], loading: false, error: "" }, patch);
        root.leagues = next;
    }

    function fetchJson(url, done) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let payload = null;
            try {
                payload = xhr.status === 200 ? JSON.parse(xhr.responseText) : null;
            } catch (error) {
                payload = null;
            }
            done(payload);
        };
        xhr.open("GET", url);
        xhr.timeout = 12000;
        xhr.send();
    }

    readonly property bool apiEnabled: Config.options.bar.sports.apiEnabled ?? true

    function load(sport) {
        if (!root.apiEnabled)
            return;
        const existing = root.leagues[sport];
        if (existing && (existing.loading || existing.all.length > 0))
            return;
        root.setEntry(sport, { loading: true, error: "" });
        const base = `https://site.api.espn.com/apis/site/v2/leagues/dropdown?sport=${encodeURIComponent(sport)}&limit=400`;
        let pending = 2;
        let all = null, popular = null;
        const finish = () => {
            if (!root)
                return;
            pending -= 1;
            if (pending > 0)
                return;
            const fullList = root.normalize(all?.leagues);
            // The regional list is ESPN's curated "popular here"; keep only
            // what the global list also knows, under the regional names.
            const popularList = root.normalize(popular?.leagues).filter(item => fullList.some(other => other.slug === item.slug));
            root.setEntry(sport, {
                loading: false,
                all: fullList,
                popular: popularList.length < fullList.length ? popularList : [],
                error: all ? "" : Translation.tr("Could not reach ESPN")
            });
        };
        root.fetchJson(base, payload => { all = payload; finish(); });
        root.fetchJson(`${base}&lang=${root.lang}&region=${root.region}`, payload => { popular = payload; finish(); });
    }

    // ── Team search ──────────────────────────────────────────────────────────
    property var teamResults: []
    property bool teamLoading: false
    property int _generation: 0

    function searchTeams(query) {
        const text = String(query ?? "").trim();
        root._generation += 1;
        const generation = root._generation;
        if (text.length < 2 || !root.apiEnabled) {
            root.teamResults = [];
            root.teamLoading = false;
            return;
        }
        root.teamLoading = true;
        root.fetchJson(`https://site.web.api.espn.com/apis/search/v2?query=${encodeURIComponent(text)}&limit=24&type=team&lang=${root.lang}&region=${root.region}`, payload => {
            if (!root || generation !== root._generation)
                return;
            root.teamLoading = false;
            const group = (payload?.results ?? []).find(item => item?.type === "team");
            root.teamResults = (group?.contents ?? []).map(item => {
                const match = /~t:(\d+)/.exec(String(item?.uid ?? ""));
                return {
                    id: match ? match[1] : String(item?.id ?? ""),
                    name: String(item?.displayName ?? ""),
                    league: String(item?.subtitle ?? ""),
                    leagueSlug: String(item?.defaultLeagueSlug ?? ""),
                    sport: String(item?.sport ?? ""),
                    logo: String(item?.image?.default ?? "")
                };
            }).filter(item => item.name !== "");
        });
    }
}
