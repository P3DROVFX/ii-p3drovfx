pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.services
import "modes/ModeSchema.js" as ModeSchema

/**
 * Combined "a game is running / focused" signal for Modes, the Game Mode
 * toggle and anything else that wants it.
 *
 * Four signals, by confidence:
 *  1. launcher classes (steam_app_*, gamescope, heroic/lutris/bottles,
 *     minecraft/prism, fullscreen wine .exe) — instant
 *  2. desktop entry category "Game" — instant
 *  3. user list Config.options.modes.game.extraClasses — instant
 *  4. focused window fullscreen with GPU above `gpuThreshold` % for `holdSec`
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

    // Desktop-entry lookups are not free; remember the verdict per class.
    property var categoryCache: ({})

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
            verdict = cats.indexOf("Game") !== -1;
        } catch (e) {
            verdict = false;
        }
        root.categoryCache[cls] = verdict;
        return verdict;
    }

    // Returns a short reason, or "" when the window is not a game.
    function classify(win) {
        if (!win)
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
        for (const rx of root.extraRegexes) {
            if (rx.test(initial) || rx.test(current))
                return `listed ${cls}`;
        }
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
        && root.focusedAddress.length > 0 && root.gpuPercent >= (root.settings?.gpuThreshold ?? 45)
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
        return list;
    }
    readonly property bool rawRunning: root.matches.length > 0
    readonly property bool rawFocused: root.matches.some(m => m.address === root.focusedAddress)
    readonly property var primaryMatch: root.matches.find(m => m.address === root.focusedAddress)
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
            + `gpuPolling=${root.gpuRequested} gpu=${root.gpuPercent}% `
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
