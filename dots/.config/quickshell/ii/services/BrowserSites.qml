pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Public state consumed by LauncherSearch. `sites` is replaced only after a
    // complete background build, so matching never observes a partial index.
    property bool ready: false
    property bool loading: false
    property string error: ""
    property string profilePath: ""
    property var sites: []
    property int revision: 0

    readonly property var options: Config.options?.search?.browserSites ?? null
    readonly property bool enabled: root.options?.enable !== false
    readonly property string configuredProfilePath: String(root.options?.profilePath ?? "")
    readonly property int maxIndexedSites: Math.max(0, Number(root.options?.maxIndexedSites ?? 300))
    readonly property int maxResults: Math.max(0, Number(root.options?.maxResults ?? 6))
    readonly property bool includeHistory: root.options?.includeHistory !== false
    readonly property bool useLocalFavicons: root.options?.useLocalFavicons !== false
    readonly property bool allowRemoteFavicons: root.options?.allowRemoteFavicons === true
    readonly property int refreshMinutes: Math.max(1, Number(root.options?.refreshMinutes ?? 10))
    readonly property int refreshIntervalMs: Math.max(60000, root.refreshMinutes * 60000)
    // Sessionstore snapshots are large and may contain deep per-tab history.
    // A transient helper reads them out of process, at most once per minute.
    readonly property int openTabsRefreshMs: 60000
    readonly property string configSignature: JSON.stringify([
        root.enabled,
        root.configuredProfilePath,
        root.maxIndexedSites,
        root.includeHistory,
        root.useLocalFavicons
    ])
    readonly property string helperPath: Directories.scriptPath + "/browser_sites_helper.py"
    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    readonly property string faviconCachePath: root.homePath + "/.cache/quickshell/favicons"
    readonly property int maxFaviconCacheEntries: 256

    property real placesMtime: 0
    property real sessionMtime: 0
    property real lastBuildAt: 0
    property int buildGeneration: 0
    property bool rebuildPending: false
    property bool rebuildPendingPeriodicRefresh: false
    property bool initialized: false
    property int buildRetryAttempt: 0
    property bool buildRetryPeriodicRefresh: false
    readonly property int buildRetryBaseMs: 1000
    readonly property int buildRetryMaxMs: 60000

    property bool privateBrowsingSupported: false
    property var privateCommand: []
    property string defaultHandlerDesktopId: ""

    property var faviconQueue: []
    property var faviconQueued: ({})
    property var faviconSources: ({})
    property var faviconActive: null
    property var faviconFailures: ({})
    readonly property int faviconFailureBaseMs: 30000
    readonly property int faviconFailureMaxMs: 600000

    function buildCommand(subcommand: string): var {
        const command = [
            "python3",
            root.helperPath,
            subcommand,
            "--home",
            root.homePath,
            "--profile",
            root.configuredProfilePath
        ];
        if (subcommand === "build") {
            command.push("--max-indexed-sites", String(root.maxIndexedSites));
            command.push("--include-history", root.includeHistory ? "1" : "0");
            command.push("--cache-dir", root.faviconCachePath);
        }
        return command;
    }

    function resetFaviconFailures() {
        root.faviconFailures = ({});
    }

    function clearPublishedIndex() {
        root.ready = false;
        root.error = "";
        root.profilePath = "";
        root.sites = [];
        root.placesMtime = 0;
        root.sessionMtime = 0;
        root.lastBuildAt = 0;
        root.privateBrowsingSupported = false;
        root.privateCommand = [];
        root.defaultHandlerDesktopId = "";
        root.faviconQueue = [];
        root.faviconQueued = ({});
        root.faviconSources = ({});
        root.resetFaviconFailures();
        root.revision++;
    }

    function initialize() {
        if (root.initialized || !Config.ready)
            return;
        root.initialized = true;
        if (root.enabled)
            root.startBuild(false);
    }

    function invalidateForConfigChange() {
        if (!root.initialized)
            return;
        root.buildGeneration++;
        rebuildDebounce.stop();
        buildRetryTimer.stop();
        root.buildRetryAttempt = 0;
        root.buildRetryPeriodicRefresh = false;
        root.rebuildPending = false;
        root.rebuildPendingPeriodicRefresh = false;
        statusProcess.running = false;
        root.clearPublishedIndex();
        if (!root.enabled) {
            root.loading = false;
            return;
        }
        if (!Config.ready)
            return;
        if (buildProcess.running) {
            root.rebuildPending = true;
            root.rebuildPendingPeriodicRefresh = false;
            root.loading = true;
            return;
        }
        rebuildDebounce.restart();
    }

    function startBuild(periodicRefresh: bool) {
        if (!root.enabled || !Config.ready)
            return;
        const preservePublishedIndex = periodicRefresh === true;
        rebuildDebounce.stop();
        if (buildProcess.running) {
            root.rebuildPending = true;
            root.rebuildPendingPeriodicRefresh = preservePublishedIndex;
            return;
        }
        statusProcess.running = false;
        buildRetryTimer.stop();
        root.resetFaviconFailures();
        if (!preservePublishedIndex && root.ready)
            root.clearPublishedIndex();
        root.loading = true;
        root.error = "";
        buildProcess.generation = root.buildGeneration;
        buildProcess.signature = root.configSignature;
        buildProcess.periodicRefresh = preservePublishedIndex;
        buildProcess.hadReady = root.ready;
        buildProcess.command = root.buildCommand("build");
        buildProcess.running = true;
    }

    function runPendingBuild(): bool {
        if (!root.rebuildPending)
            return false;
        const periodicRefresh = root.rebuildPendingPeriodicRefresh;
        root.rebuildPending = false;
        root.rebuildPendingPeriodicRefresh = false;
        buildRetryTimer.stop();
        Qt.callLater(() => root.startBuild(periodicRefresh));
        return true;
    }

    function scheduleBuildRetry(periodicRefresh: bool) {
        if (!root.enabled || !Config.ready)
            return;
        root.buildRetryPeriodicRefresh = periodicRefresh === true;
        buildRetryTimer.interval = Math.min(
            root.buildRetryMaxMs,
            root.buildRetryBaseMs * Math.pow(2, root.buildRetryAttempt)
        );
        root.buildRetryAttempt++;
        buildRetryTimer.restart();
    }

    function finishBuild() {
        const stale = buildProcess.generation !== root.buildGeneration
            || buildProcess.signature !== root.configSignature;
        if (stale || !root.enabled) {
            root.loading = false;
            root.runPendingBuild();
            return;
        }
        let result = null;
        try {
            result = JSON.parse(buildOutput.text || "{}");
        } catch (parseError) {
            result = ({
                ok: false,
                error: "Browser site index returned invalid data"
            });
        }

        if (result?.ok === true && Array.isArray(result.sites)) {
            buildRetryTimer.stop();
            root.buildRetryAttempt = 0;
            root.buildRetryPeriodicRefresh = false;
            root.profilePath = String(result.profilePath ?? "");
            root.placesMtime = Number(result.placesMtime ?? 0);
            root.sessionMtime = Number(result.sessionMtime ?? 0);
            root.sites = result.sites;
            root.lastBuildAt = Date.now();
            root.privateBrowsingSupported = result.privateBrowsingSupported === true
                && Array.isArray(result.privateCommand)
                && result.privateCommand.some(argument => String(argument).includes("__URL__"));
            root.privateCommand = root.privateBrowsingSupported ? result.privateCommand : [];
            root.defaultHandlerDesktopId = root.privateBrowsingSupported
                ? String(result.defaultHandlerDesktopId ?? "")
                : "";

            const knownSources = Object.assign({}, root.faviconSources);
            for (let i = 0; i < root.sites.length; i++) {
                const site = root.sites[i];
                if (site?.host && site?.favicon)
                    knownSources[root.hostFor(site)] = String(site.favicon);
            }
            root.faviconSources = knownSources;
            root.ready = true;
            root.error = "";
            root.revision++;
            refreshTimer.restart();
        } else {
            const preservePublishedIndex = buildProcess.periodicRefresh
                && buildProcess.hadReady;
            if (!preservePublishedIndex)
                root.clearPublishedIndex();
            root.error = String(result.error ?? "Could not build browser site index");
        }
        root.loading = false;

        if (root.runPendingBuild())
            return;
        if (result?.ok !== true)
            root.scheduleBuildRetry(buildProcess.periodicRefresh && root.ready);
    }

    function checkForRefresh() {
        if (!root.enabled || !root.ready || root.loading || statusProcess.running)
            return;
        statusProcess.generation = root.buildGeneration;
        statusProcess.signature = root.configSignature;
        statusProcess.command = root.buildCommand("status");
        statusProcess.running = true;
    }

    function finishRefreshCheck() {
        if (!root.enabled || root.loading || buildProcess.running)
            return;
        if (statusProcess.generation !== root.buildGeneration
                || statusProcess.signature !== root.configSignature)
            return;
        let result = null;
        try {
            result = JSON.parse(statusOutput.text || "{}");
        } catch (parseError) {
            return;
        }
        if (result?.ok !== true)
            return;
        const candidateProfile = String(result.profilePath ?? "");
        const candidateMtime = Number(result.placesMtime ?? 0);
        const candidateSessionMtime = Number(result.sessionMtime ?? 0);
        const profileChanged = candidateProfile !== root.profilePath;
        const mtimeChanged = Math.abs(candidateMtime - root.placesMtime) > 0.0001;
        const sessionMtimeChanged = Math.abs(candidateSessionMtime - root.sessionMtime) > 0.0001;
        const intervalElapsed = Date.now() - root.lastBuildAt >= root.refreshMinutes * 60000;
        if (profileChanged) {
            root.buildGeneration++;
            root.clearPublishedIndex();
            root.startBuild(false);
        } else if (sessionMtimeChanged || (intervalElapsed && mtimeChanged)) {
            root.startBuild(true);
        }
    }

    function normalized(value): string {
        return String(value ?? "").trim().toLowerCase();
    }

    function scoreField(field: string, query: string, exact: int, prefix: int, contains: int): int {
        if (field === query)
            return exact;
        if (field.startsWith(query))
            return prefix;
        if (field.includes(query))
            return contains;
        return 0;
    }

    function scoreSite(site: var, query: string, tokens: var): int {
        const host = root.normalized(site?.host).replace(/^www\./, "");
        const title = root.normalized(site?.title);
        const path = root.normalized(site?.path);
        const searchable = host + " " + title + " " + path;
        for (let i = 0; i < tokens.length; i++) {
            if (!searchable.includes(tokens[i]))
                return -1;
        }

        let score = 0;
        score += root.scoreField(host, query, 1200, 1000, 760);
        score += root.scoreField(title, query, 720, 620, 440);
        score += root.scoreField(path, query, 360, 300, 220);
        for (let i = 0; i < tokens.length; i++) {
            const token = tokens[i];
            if (host.includes(token))
                score += 180;
            if (title.includes(token))
                score += 90;
            if (path.includes(token))
                score += 35;
        }
        if (site?.source === "open")
            score += 320;
        else if (site?.bookmarked === true)
            score += 160;
        score += Math.min(120, Math.floor(Math.log(1 + Math.max(0, Number(site?.frecency ?? 0))) * 12));
        return score;
    }

    function matchSites(queryText: string): var {
        const normalizedQuery = root.normalized(queryText);
        if (normalizedQuery.length === 0)
            return [];
        const tokens = normalizedQuery.split(/\s+/).filter(token => token.length > 0);
        const matches = [];
        const source = root.sites ?? [];
        for (let i = 0; i < source.length; i++) {
            const site = source[i];
            const score = root.scoreSite(site, normalizedQuery, tokens);
            if (score < 0)
                continue;
            matches.push(Object.assign({}, site, { matchScore: score }));
        }
        matches.sort((left, right) => {
            if (right.matchScore !== left.matchScore)
                return right.matchScore - left.matchScore;
            if (right.source !== left.source) {
                const sourceRank = { open: 3, favorite: 2, suggested: 1 };
                return Number(sourceRank[right.source] ?? 0) - Number(sourceRank[left.source] ?? 0);
            }
            if (right.bookmarked !== left.bookmarked)
                return right.bookmarked ? 1 : -1;
            if (Number(right.frecency) !== Number(left.frecency))
                return Number(right.frecency) - Number(left.frecency);
            return String(left.url).localeCompare(String(right.url));
        });
        return matches.slice(0, root.maxResults);
    }

    function match(queryText: string): var {
        return root.matchSites(queryText);
    }

    function hostFor(siteOrUrl: var): string {
        if (typeof siteOrUrl === "object" && siteOrUrl !== null && siteOrUrl.host) {
            const providedHost = String(siteOrUrl.host).toLowerCase();
            const hostWithOptionalPort = providedHost.match(/^\[([^\]]+)\](?::\d+)?$|^([^:]+)(?::\d+)?$/);
            return hostWithOptionalPort
                ? String(hostWithOptionalPort[1] ?? hostWithOptionalPort[2] ?? "")
                : providedHost;
        }
        const raw = typeof siteOrUrl === "object" && siteOrUrl !== null
            ? String(siteOrUrl.url ?? "")
            : String(siteOrUrl ?? "");
        const match = raw.match(/^[a-z][a-z0-9+.-]*:\/\/(?:[^@/]+@)?(\[[^\]]+\]|[^/:?#]+)(?::\d+)?/i);
        if (!match)
            return "";
        return String(match[1]).replace(/^\[|\]$/g, "").toLowerCase();
    }

    function requestFavicon(siteOrUrl: var) {
        if (!root.useLocalFavicons || root.profilePath.length === 0)
            return;
        const host = root.hostFor(siteOrUrl);
        if (host.length === 0 || root.faviconSources[host] || root.faviconQueued[host])
            return;
        const failure = root.faviconFailures[host];
        if (failure && Date.now() < failure.retryAfter)
            return;
        if (typeof siteOrUrl === "object" && siteOrUrl !== null && siteOrUrl.favicon) {
            const sources = Object.assign({}, root.faviconSources);
            sources[host] = String(siteOrUrl.favicon);
            root.faviconSources = sources;
            return;
        }
        const url = typeof siteOrUrl === "object" && siteOrUrl !== null
            ? String(siteOrUrl.url ?? "")
            : String(siteOrUrl ?? "");
        if (!/^https?:\/\//i.test(url))
            return;
        const queued = Object.assign({}, root.faviconQueued);
        queued[host] = true;
        root.faviconQueued = queued;
        root.faviconQueue = root.faviconQueue.concat([{
            host: host,
            url: url,
            profile: root.profilePath,
            generation: root.buildGeneration
        }]);
        root.startNextFavicon();
    }

    function startNextFavicon() {
        if (faviconProcess.running || root.faviconQueue.length === 0)
            return;
        const entry = root.faviconQueue[0];
        root.faviconQueue = root.faviconQueue.slice(1);
        root.faviconActive = entry;
        faviconProcess.command = [
            "python3",
            root.helperPath,
            "favicon",
            "--profile",
            entry.profile,
            "--url",
            entry.url,
            "--cache-dir",
            root.faviconCachePath,
            "--max-cache-entries",
            String(root.maxFaviconCacheEntries)
        ];
        faviconProcess.running = true;
    }

    function finishFavicon() {
        const active = root.faviconActive;
        if (active === null) {
            Qt.callLater(root.startNextFavicon);
            return;
        }
        const queued = Object.assign({}, root.faviconQueued);
        delete queued[active.host];
        root.faviconQueued = queued;
        let result = null;
        try {
            result = JSON.parse(faviconOutput.text || "{}");
        } catch (parseError) {
            result = null;
        }
        const currentRequest = active.profile === root.profilePath
            && active.generation === root.buildGeneration
            && root.useLocalFavicons;
        let extracted = false;
        if (currentRequest && result?.ok === true) {
            const host = String(result.host ?? active.host);
            const source = String(result.source ?? "");
            if (host.length > 0 && source.startsWith("file://")) {
                const sources = Object.assign({}, root.faviconSources);
                sources[host] = source;
                root.faviconSources = sources;
                const failures = Object.assign({}, root.faviconFailures);
                delete failures[active.host];
                delete failures[host];
                root.faviconFailures = failures;
                extracted = true;
            }
        }
        if (currentRequest && !extracted) {
            const failures = Object.assign({}, root.faviconFailures);
            const previousAttempts = Number(failures[active.host]?.attempts ?? 0);
            const attempts = previousAttempts + 1;
            const delay = Math.min(
                root.faviconFailureMaxMs,
                root.faviconFailureBaseMs * Math.pow(2, previousAttempts)
            );
            failures[active.host] = {
                attempts: attempts,
                failedAt: Date.now(),
                retryAfter: Date.now() + delay
            };
            root.faviconFailures = failures;
        }
        root.faviconActive = null;
        // One icon arriving is not a reason to rebuild every launcher result.
        // Typing surfaces a handful of new sites at once, and each fetch used
        // to publish a revision of its own — so a single keystroke bought a
        // second full recomputation of the result set, and then a third.
        faviconSettleTimer.restart();
        Qt.callLater(root.startNextFavicon);
    }

    function faviconFor(siteOrUrl: var): string {
        const host = root.hostFor(siteOrUrl);
        if (host.length === 0)
            return "";
        if (root.useLocalFavicons) {
            const localSource = String(root.faviconSources[host] ?? "");
            if (localSource.startsWith("file://"))
                return localSource;
            root.requestFavicon(siteOrUrl);
        }
        if (root.allowRemoteFavicons)
            return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(host) + "&sz=64";
        return "";
    }

    function privateWindowCommand(url: string): var {
        if (!root.privateBrowsingSupported || !/^https?:\/\//i.test(String(url ?? "")))
            return [];
        return root.privateCommand.map(argument => String(argument).split("__URL__").join(String(url)));
    }

    function openPrivateWindow(url: string): bool {
        const command = root.privateWindowCommand(url);
        if (command.length === 0)
            return false;
        Quickshell.execDetached(command);
        return true;
    }

    onConfigSignatureChanged: root.invalidateForConfigChange()
    // Long enough to collect the burst a keystroke sets off, short enough that
    // an icon still lands while the row that wants it is on screen.
    readonly property Timer faviconSettleTimer: Timer {
        id: faviconSettleTimer
        interval: 250
        repeat: false
        onTriggered: root.revision++
    }

    onAllowRemoteFaviconsChanged: root.revision++
    onRefreshMinutesChanged: {
        if (refreshTimer.running)
            refreshTimer.restart();
    }
    onMaxResultsChanged: root.revision++

    Component.onCompleted: Qt.callLater(root.initialize)

    Connections {
        target: Config

        function onReadyChanged() {
            if (Config.ready)
                root.initialize();
        }
    }

    Timer {
        id: rebuildDebounce
        interval: 120
        repeat: false
        onTriggered: root.startBuild(false)
    }

    Timer {
        id: refreshTimer
        interval: Math.min(root.openTabsRefreshMs, root.refreshIntervalMs)
        repeat: true
        running: root.enabled && root.ready && !root.loading
        onTriggered: root.checkForRefresh()
    }

    Timer {
        id: buildRetryTimer
        interval: root.buildRetryBaseMs
        repeat: false
        onTriggered: root.startBuild(root.buildRetryPeriodicRefresh)
    }

    Process {
        id: buildProcess
        property int generation: -1
        property string signature: ""
        property bool periodicRefresh: false
        property bool hadReady: false

        stdout: StdioCollector { id: buildOutput }
        stderr: StdioCollector { id: buildErrorOutput }
        onExited: root.finishBuild()
    }

    Process {
        id: statusProcess
        property int generation: -1
        property string signature: ""

        stdout: StdioCollector { id: statusOutput }
        onExited: root.finishRefreshCheck()
    }

    Process {
        id: faviconProcess
        stdout: StdioCollector { id: faviconOutput }
        onExited: root.finishFavicon()
    }
}
