pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "modes/ModeSchema.js" as ModeSchema

/**
 * Combined "a game is running / focused" signal for Modes, the Game Mode
 * toggle and anything else that wants it.
 *
 * Five signals, by confidence:
 *  1. launcher classes (steam_app_*, gamescope, heroic/lutris/bottles,
 *     minecraft/prism/modrinth, omikuji, orion, bedrock, mcpelauncher,
 *     fullscreen wine .exe) — instant
 *  2. desktop entry category "Game" — instant
 *  3. user list Config.options.modes.game.extraClasses — instant
 *  4. focused window fullscreen with GPU above `gpuThreshold` % for `holdSec`
 *  5. MangoHud log while a game is running (opt-in, useMangoHudLog) — instant
 *
 * `reason` says which one fired ("Steam app", "fullscreen + GPU 62 %") so a
 * false positive can be diagnosed from the trigger chip.
 *
 * Hysteresis: on immediately (signal 4 after its hold); `gameRunning` drops
 * 30 s after the last matching window is gone, `gameFocused` 5 s after focus
 * left it, so alt-tabbing to a chat does not end a gaming mode.
 *
 * GPU polling costs a process per sample on NVIDIA/Intel, so it runs only
 * while someone holds `acquire()` and the heuristic is enabled.
 */
Singleton {
    id: root

    readonly property var settings: Config.options.modes.game
    readonly property int runningOffDelayMs: 30000
    readonly property int focusedOffDelayMs: 5000

    // Conditions that currently depend on the detector.
    property int users: 0
    readonly property bool gpuWanted: root.users > 0 && (root.settings?.useGpuHeuristic ?? true)
    // What ResourceUsage currently holds for us. Synced with a short delay so
    // the release/acquire pair of a watcher rebuild does not reset sampling.
    property bool gpuRequested: false
    onGpuWantedChanged: gpuSync.restart()

    property Timer gpuSync: Timer {
        interval: 500
        repeat: false
        onTriggered: {
            if (root.gpuWanted === root.gpuRequested)
                return;
            root.gpuRequested = root.gpuWanted;
            ResourceUsage.requestGpuMonitoring(root.gpuRequested);
            if (!root.gpuRequested)
                root.gpuGameAddress = "";
        }
    }

    function acquire() {
        root.users += 1;
    }

    function release() {
        root.users = Math.max(0, root.users - 1);
    }

    // ---------------------------------------------------------------- matching

    readonly property var launcherRegexes: ModeSchema.GAME_LAUNCHER_PATTERNS.map(p => new RegExp(p, "i"))
    readonly property var extraRegexes: ModeSchema.classRegexes(root.settings?.extraClasses)
    readonly property var wineRegex: /\.exe$/i

    // MangoHud writes a log only while it is injected into a game.
    property string mangoHudGame: ""

    property Process mangoHudWatch: Process {
        command: ["python3", `${Directories.scriptPath}/perfOverlay/perf_monitor.py`,
            "watch", "--mangohud-dir", FileUtils.trimFileProtocol(`${Directories.cache}/perf-overlay/mangohud`)]
        running: root.settings?.useMangoHudLog ?? false
        onRunningChanged: if (!running) root.mangoHudGame = ""
        onExited: root.mangoHudGame = ""
        stdout: SplitParser {
            onRead: line => {
                try {
                    const message = JSON.parse(line);
                    if (message.t === "game")
                        root.mangoHudGame = String(message.process ?? "");
                } catch (e) {}
            }
        }
    }

    // Desktop-entry lookups are not free; remember the verdict per class.
    property var categoryCache: ({})

    readonly property var toolCategories: ["Utility", "Network", "FileTransfer", "Development", "Office", "System", "Settings"]

    function isGameByDesktopEntry(cls) {
        if (!cls)
            return false;
        const cached = root.categoryCache[cls];
        if (cached !== undefined)
            return cached;
        let verdict = false;
        try {
            const entry = DesktopEntries.heuristicLookup(cls);
            const cats = Array.from(entry?.categories ?? []);
            // "Game" next to a tool category (save editors, stores, trainers:
            // Utility;Game, Network;FileTransfer;Game) is a tool about games.
            verdict = cats.indexOf("Game") !== -1
                && !cats.some(c => root.toolCategories.indexOf(c) !== -1);
        } catch (e) {
            verdict = false;
        }
        root.categoryCache[cls] = verdict;
        return verdict;
    }

    readonly property var clientRegexes: ModeSchema.GAME_CLIENT_PATTERNS.map(p => new RegExp(p, "i"))

    // Every process Steam starts for a game carries SteamGameId=<appid> (native
    // games keep arbitrary classes like "Lightning.bin.x86_64"); the client and
    // its web helper do not. Window pids are probed once each, off the UI thread.
    property var steamApps: ({})     // pid -> appid, published
    property var steamVerdicts: ({}) // pid -> appid ("0" = not a Steam game), probed
    readonly property string windowPidKey: {
        const seen = {};
        for (const w of (HyprlandData.windowList ?? []))
            if (w.pid > 0) seen[w.pid] = true;
        return Object.keys(seen).sort().join(" ");
    }
    onWindowPidKeyChanged: root.probeSteam()
    onUsersChanged: root.probeSteam()

    function probeSteam() {
        if (root.users <= 0 || steamProbe.busy)
            return;
        const all = root.windowPidKey.length ? root.windowPidKey.split(" ") : [];
        const keep = {};
        const todo = [];
        for (const p of all) {
            if (root.steamVerdicts[p] !== undefined)
                keep[p] = root.steamVerdicts[p];
            else
                todo.push(p);
        }
        root.steamVerdicts = keep;
        root.publishSteam();
        if (todo.length === 0)
            return;
        steamProbe.asked = todo;
        steamProbe.busy = true;
        steamProbe.command = ["sh", "-c",
            'for p; do v=$(tr "\\0" "\\n" <"/proc/$p/environ" 2>/dev/null | sed -n "s/^SteamGameId=//p" | head -n1); echo "$p ${v:-0}"; done',
            "sh"].concat(todo);
        steamProbe.running = true;
    }

    function publishSteam() {
        const out = {};
        for (const p in root.steamVerdicts)
            if (/^[1-9]\d*$/.test(root.steamVerdicts[p]))
                out[p] = root.steamVerdicts[p];
        root.steamApps = out;
    }

    property Process steamProbe: Process {
        property var asked: []
        property bool busy: false
        stdout: StdioCollector {
            onStreamFinished: {
                const verdicts = Object.assign({}, root.steamVerdicts);
                for (const p of steamProbe.asked)
                    verdicts[p] = "0";
                for (const line of text.split("\n")) {
                    const m = line.match(/^(\d+) (\S+)$/);
                    if (m) verdicts[m[1]] = m[2];
                }
                root.steamVerdicts = verdicts;
                root.publishSteam();
                steamProbe.busy = false;
                Qt.callLater(root.probeSteam);
            }
        }
    }

    readonly property var clientTitleRules: ModeSchema.GAME_CLIENT_TITLE_RULES.map(r => ({
        cls: new RegExp(r.cls, "i"), playing: new RegExp(r.playing, "i") }))

    readonly property var ignoreRegexes: ModeSchema.classRegexes(root.settings?.ignoreClasses)

    // User exclusion list: a class pattern, or the window's Steam app id.
    function isIgnored(win) {
        if (!win || (root.ignoreRegexes.length === 0 && !(root.settings?.ignoreClasses?.length)))
            return false;
        const initial = String(win.initialClass || "");
        const current = String(win["class"] || "");
        if (root.ignoreRegexes.some(rx => rx.test(initial) || rx.test(current)))
            return true;
        const app = root.steamApps[win.pid];
        return !!app && Array.from(root.settings.ignoreClasses).some(s => String(s).trim() === app);
    }

    // A store/launcher's own window (Steam, Big Picture, its web helper).
    function isClientWindow(win) {
        if (!win)
            return false;
        const initial = String(win.initialClass || "");
        const current = String(win["class"] || "");
        if (root.clientRegexes.some(rx => rx.test(initial) || rx.test(current)))
            return true;
        const title = String(win.title || "");
        return root.clientTitleRules.some(r => (r.cls.test(initial) || r.cls.test(current)) && !r.playing.test(title));
    }

    // Returns a short reason, or "" when the window is not a game.
    function classify(win) {
        if (!win || root.isIgnored(win))
            return "";
        const initial = String(win.initialClass || "");
        const current = String(win["class"] || "");
        const cls = initial || current;
        if (root.settings?.useLauncherClasses ?? true) {
            for (const rx of root.launcherRegexes) {
                if (rx.test(initial) || rx.test(current))
                    return /^steam_app_/i.test(cls) ? "Steam app" : `launcher ${cls}`;
            }
            if ((win.fullscreen ?? 0) >= 2 && (root.wineRegex.test(initial) || root.wineRegex.test(current)))
                return `fullscreen ${cls}`;
        }
        const steamApp = root.steamApps[win.pid];
        if (steamApp)
            return `Steam game ${steamApp}`;
        for (const rx of root.extraRegexes) {
            if (rx.test(initial) || rx.test(current))
                return `listed ${cls}`;
        }
        if (root.isClientWindow(win))
            return "";
        if (root.settings?.useDesktopCategory ?? true) {
            if (root.isGameByDesktopEntry(current))
                return `${cls} (Game category)`;
            if (initial !== current && root.isGameByDesktopEntry(initial))
                return `${cls} (Game category)`;
        }
        return "";
    }

    readonly property string focusedAddress: {
        const a = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
        return a ? `0x${a}` : "";
    }
    readonly property var focusedWindow: HyprlandData.windowByAddress[root.focusedAddress] ?? null
    readonly property bool focusedFullscreen: (ToplevelManager.activeToplevel?.fullscreen ?? false)
        || ((root.focusedWindow?.fullscreen ?? 0) >= 2)

    // [{address, cls, reason}] for signals 1–3.
    readonly property var classMatches: {
        const out = [];
        for (const w of (HyprlandData.windowList ?? [])) {
            const reason = root.classify(w);
            if (reason)
                out.push({ address: w.address, cls: w["class"] || w.initialClass || "", reason: reason });
        }
        return out;
    }

    // ---------------------------------------------------------------- gpu heuristic

    readonly property int gpuPercent: Math.round((ResourceUsage.gpuUsage ?? 0) * 100)
    readonly property bool gpuCandidate: root.gpuWanted && root.focusedFullscreen
        && root.focusedAddress.length > 0 && !root.isClientWindow(root.focusedWindow)
        && !root.isIgnored(root.focusedWindow)
        && root.gpuPercent >= (root.settings?.gpuThreshold ?? 45)
    // Window that passed the hold; cleared when it closes or leaves fullscreen.
    property string gpuGameAddress: ""
    property int gpuGamePercent: 0

    property Timer gpuHold: Timer {
        interval: Math.max(1, root.settings?.holdSec ?? 20) * 1000
        repeat: false
        running: root.gpuCandidate && root.gpuGameAddress !== root.focusedAddress
        onTriggered: {
            root.gpuGameAddress = root.focusedAddress;
            root.gpuGamePercent = root.gpuPercent;
            console.log(`[GameDetector] fullscreen + GPU ${root.gpuPercent} % held for ${interval / 1000} s, `
                + `treating ${root.focusedWindow?.["class"] ?? root.focusedAddress} as a game`);
        }
    }

    readonly property var gpuGameWindow: root.gpuGameAddress
        ? (HyprlandData.windowByAddress[root.gpuGameAddress] ?? null) : null
    readonly property bool gpuGameStillValid: root.gpuGameWindow !== null
        && (root.gpuGameWindow.fullscreen ?? 0) >= 2
    onGpuGameStillValidChanged: {
        if (!root.gpuGameStillValid && root.gpuGameAddress)
            root.gpuGameAddress = "";
    }

    // ---------------------------------------------------------------- combined

    readonly property var matches: {
        const list = root.classMatches.slice();
        const gpuListed = list.some(m => m.address === root.gpuGameAddress);
        if (root.gpuGameAddress && root.gpuGameStillValid && !gpuListed) {
            list.push({
                address: root.gpuGameAddress,
                cls: root.gpuGameWindow?.["class"] ?? "",
                reason: `fullscreen + GPU ${root.gpuGamePercent} %`
            });
        }
        if (root.mangoHudGame.length > 0 && (root.settings?.useMangoHudLog ?? false))
            list.push({ address: "", cls: root.mangoHudGame, reason: "MangoHud log" });
        return list;
    }
    readonly property bool rawRunning: root.matches.length > 0
    // The MangoHud match has no window: an empty focus must not match it.
    readonly property bool rawFocused: root.focusedAddress.length > 0
        && root.matches.some(m => m.address === root.focusedAddress)
    readonly property var primaryMatch: (root.focusedAddress.length > 0
        ? root.matches.find(m => m.address === root.focusedAddress) : undefined)
        ?? root.matches[0] ?? null

    property bool gameRunning: false
    property bool gameFocused: false
    property string gameClass: ""
    property string reason: ""

    onRawRunningChanged: {
        if (root.rawRunning) {
            runningOff.stop();
            root.gameRunning = true;
            return;
        }
        runningOff.restart();
    }

    onRawFocusedChanged: {
        if (root.rawFocused) {
            focusedOff.stop();
            root.gameFocused = true;
            return;
        }
        focusedOff.restart();
    }

    onPrimaryMatchChanged: {
        if (!root.primaryMatch)
            return;
        root.gameClass = root.primaryMatch.cls;
        root.reason = root.primaryMatch.reason;
    }

    property Timer runningOff: Timer {
        interval: root.runningOffDelayMs
        repeat: false
        onTriggered: {
            if (root.rawRunning)
                return;
            root.gameRunning = false;
            root.gameClass = "";
            root.reason = "";
        }
    }

    property Timer focusedOff: Timer {
        interval: root.focusedOffDelayMs
        repeat: false
        onTriggered: {
            if (!root.rawFocused)
                root.gameFocused = false;
        }
    }

    // "Treat this window as a game" from the trigger chip / settings.
    function addExtraClass(cls) {
        const clean = String(cls || "").trim();
        if (!clean.length)
            return false;
        const list = Array.from(root.settings.extraClasses ?? []);
        if (list.indexOf(clean) !== -1)
            return false;
        list.push(clean);
        root.settings.extraClasses = list;
        return true;
    }

    function removeExtraClass(cls) {
        root.settings.extraClasses = Array.from(root.settings.extraClasses ?? []).filter(c => c !== cls);
    }

    function statusText() {
        const lines = [];
        lines.push(`running=${root.gameRunning} focused=${root.gameFocused} users=${root.users} `
            + `mangohud=${root.mangoHudGame || "-"} gpuPolling=${root.gpuRequested} gpu=${root.gpuPercent}% `
            + `focusedFullscreen=${root.focusedFullscreen}`);
        for (const m of root.matches) {
            const focused = m.address === root.focusedAddress ? " (focused)" : "";
            lines.push(`  ${m.address} ${m.cls}: ${m.reason}${focused}`);
        }
        if (root.gpuCandidate && !root.gpuGameAddress)
            lines.push(`  hold: ${root.focusedWindow?.["class"] ?? "?"} at ${root.gpuPercent} %, `
                + `${root.gpuHold.running ? "counting" : "idle"}`);
        return lines.join("\n");
    }

    Component.onCompleted: {
        if (root.rawRunning)
            root.gameRunning = true;
        if (root.rawFocused)
            root.gameFocused = true;
    }
}
