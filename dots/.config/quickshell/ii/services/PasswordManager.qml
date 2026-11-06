pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common

/**
 * Passwords: the bar widget's bridge to a password manager CLI.
 *
 * `scripts/password_manager.py` holds one adapter per CLI (Bitwarden `bw`,
 * `rbw`, `pass`). This side keeps only what a person sees — vault state,
 * names, usernames, hosts — and never a secret: copies and auto-type happen
 * inside the helper, which hands the value straight to wl-copy / wtype.
 *
 * Costs nothing until the widget exists (singletons are built on first use),
 * and nothing while idle: no polling, one status call when the popup opens.
 */
Singleton {
    id: root

    readonly property var _cfg: Config.options?.bar?.passwordManager ?? null
    readonly property string configuredProvider: root._cfg?.provider ?? "auto"
    readonly property int clipboardClearSeconds: Math.max(0, root._cfg?.clipboardClear ?? 30)
    readonly property int autoLockMinutes: Math.max(0, root._cfg?.autoLock ?? 15)
    readonly property bool lockWithScreen: root._cfg?.lockWithScreen ?? true
    readonly property bool suggestForWindow: root._cfg?.suggestForWindow ?? true

    // "unknown" until the first status answer, then one of
    // missing | unauthenticated | locked | unlocked.
    property string state: "unknown"
    property string provider: ""
    property string account: ""
    // Host of a non-default server (bitwarden.eu, self-hosted); "" for bitwarden.com.
    property string server: ""
    property var items: []
    property bool loadingItems: false
    property bool busy: false
    property string busyAction: ""
    property string errorText: ""
    property string errorCode: ""
    // Bumped on every failure so the popup can shake even on a repeated error.
    property int errorSerial: 0
    property bool wtypeAvailable: false
    // { bitwarden: bool, rbw: bool, pass: bool } — for the settings page.
    property var installed: ({})

    readonly property bool unlocked: root.state === "unlocked"
    readonly property bool needsPassword: root.provider === "bitwarden"
    readonly property string providerName: {
        switch (root.provider) {
        case "bitwarden": return "Bitwarden";
        case "rbw": return "Bitwarden (rbw)";
        case "pass": return "pass";
        default: return Translation.tr("Passwords");
        }
    }

    // ── Clipboard countdown (drawn by the bar widget) ────────────────────────
    property real clipStartedAt: 0
    property int clipSeconds: 0
    property string clipField: ""
    property string clipItemName: ""
    readonly property bool clipActive: root.clipSeconds > 0 && root.clipStartedAt > 0
    property int clipRemaining: 0

    Timer {
        id: clipTicker
        interval: 1000
        repeat: true
        running: root.clipActive
        triggeredOnStart: true
        onTriggered: {
            const left = Math.ceil(root.clipSeconds - (Date.now() - root.clipStartedAt) / 1000);
            root.clipRemaining = Math.max(0, left);
            if (left <= 0) {
                root.clipStartedAt = 0;
                root.clipSeconds = 0;
                root.clipField = "";
                root.clipItemName = "";
            }
        }
    }

    // ── Recents (ids only — never a secret) ──────────────────────────────────
    readonly property var recentIds: Persistent.states?.passwordManager?.recent ?? []

    function _touchRecent(id: string): void {
        if (!Persistent.states?.passwordManager)
            return;
        const next = [id].concat(Array.from(root.recentIds).filter(x => x !== id)).slice(0, 12);
        Persistent.states.passwordManager.recent = next;
    }

    // ── Context: the window the user was in when they opened the popup ───────
    readonly property string activeTitle: (ToplevelManager.activeToplevel?.title ?? "").toLowerCase()
    readonly property string activeAppId: (ToplevelManager.activeToplevel?.appId ?? "").toLowerCase()

    function _hostLabel(host: string): string {
        const parts = String(host ?? "").toLowerCase().split(".");
        if (parts.length < 2)
            return parts[0] ?? "";
        // "accounts.google.com" → "google", "github.com" → "github".
        return parts[parts.length - 2];
    }

    function contextScore(item): int {
        const title = root.activeTitle;
        if (!root.suggestForWindow || title.length === 0)
            return 0;
        const hosts = (item.hosts && item.hosts.length > 0) ? item.hosts : (item.host ? [item.host] : []);
        for (const host of hosts) {
            if (host.length > 3 && title.indexOf(host) >= 0)
                return 3;
        }
        const name = String(item.name ?? "").toLowerCase().trim();
        if (name.length >= 3 && title.indexOf(name) >= 0)
            return 2;
        for (const host of hosts) {
            const label = root._hostLabel(host);
            if (label.length >= 4 && title.indexOf(label) >= 0)
                return 1;
        }
        return 0;
    }

    readonly property var suggestion: {
        if (!root.unlocked || root.items.length === 0)
            return null;
        let best = null;
        let bestScore = 0;
        for (const item of root.items) {
            const score = root.contextScore(item);
            if (score > bestScore) {
                best = item;
                bestScore = score;
            }
        }
        return best;
    }

    // ── Search ───────────────────────────────────────────────────────────────
    function _subsequence(needle: string, hay: string): bool {
        let j = 0;
        for (let i = 0; i < hay.length && j < needle.length; i++) {
            if (hay[i] === needle[j])
                j++;
        }
        return j === needle.length;
    }

    function _score(item, q: string): int {
        const name = String(item.name ?? "").toLowerCase();
        const user = String(item.user ?? "").toLowerCase();
        const host = String(item.host ?? "").toLowerCase();
        const folder = String(item.folder ?? "").toLowerCase();
        if (name === q) return 100;
        if (name.startsWith(q)) return 80;
        if (name.split(/[\s\-_./@]+/).some(w => w.startsWith(q))) return 65;
        if (host.startsWith(q) || root._hostLabel(host).startsWith(q)) return 60;
        if (name.indexOf(q) >= 0) return 50;
        if (host.indexOf(q) >= 0) return 40;
        if (user.indexOf(q) >= 0) return 30;
        if (folder.indexOf(q) >= 0) return 20;
        if (q.length >= 2 && root._subsequence(q, name)) return 10;
        return 0;
    }

    function results(query: string, limit: int): var {
        const q = String(query ?? "").trim().toLowerCase();
        const recent = Array.from(root.recentIds);
        const recentBoost = id => {
            const i = recent.indexOf(id);
            return i < 0 ? 0 : (12 - i);
        };
        let ranked;
        if (q.length === 0) {
            // No query: the window's match, then recents, then favourites.
            const picked = [];
            const seen = {};
            const push = item => {
                if (item && !seen[item.id]) {
                    seen[item.id] = true;
                    picked.push(item);
                }
            };
            push(root.suggestion);
            const byId = {};
            for (const item of root.items)
                byId[item.id] = item;
            for (const id of recent)
                push(byId[id]);
            for (const item of root.items) {
                if (item.favorite)
                    push(item);
            }
            ranked = picked;
        } else {
            ranked = root.items
                .map(item => ({ item: item, score: root._score(item, q) }))
                .filter(entry => entry.score > 0)
                .map(entry => ({
                    item: entry.item,
                    score: entry.score + recentBoost(entry.item.id) + root.contextScore(entry.item) * 4
                        + (entry.item.favorite ? 3 : 0)
                }))
                .sort((a, b) => b.score - a.score || String(a.item.name).localeCompare(String(b.item.name)))
                .map(entry => entry.item);
        }
        return ranked.slice(0, Math.max(1, limit));
    }

    // ── Commands ─────────────────────────────────────────────────────────────
    function _cmd(args: var): var {
        return ["python3", Directories.scriptPath + "/password_manager.py"]
            .concat(args)
            .concat(["--provider", root.configuredProvider]);
    }

    function _fail(payload): void {
        root.errorText = String(payload?.error ?? Translation.tr("Something went wrong"));
        root.errorCode = String(payload?.code ?? "error");
        root.errorSerial++;
    }

    function clearError(): void {
        root.errorText = "";
        root.errorCode = "";
    }

    function refresh(): void {
        if (statusProc.running)
            return;
        statusProc.exec(root._cmd(["status"]));
    }

    function loadItems(): void {
        if (listProc.running || !root.unlocked)
            return;
        root.loadingItems = true;
        listProc.exec(root._cmd(["list"]));
    }

    function _runAction(name: string, args: var): bool {
        if (actionProc.running)
            return false;
        root.busy = true;
        root.busyAction = name;
        actionProc.pendingStdin = "";
        actionProc.exec(root._cmd(args));
        return true;
    }

    function unlock(password: string): void {
        if (actionProc.running)
            return;
        root.clearError();
        root.busy = true;
        root.busyAction = "unlock";
        actionProc.pendingStdin = root.needsPassword ? String(password ?? "") + "\n" : "";
        actionProc.stdinEnabled = root.needsPassword;
        actionProc.exec(root._cmd(["unlock"]));
    }

    function lock(): void {
        root.items = [];
        root._runAction("lock", ["lock"]);
    }

    function sync(): void {
        root._runAction("sync", ["sync"]);
    }

    function copy(item, field: string): void {
        if (!item)
            return;
        actionProc.lastItem = item;
        actionProc.lastField = field;
        if (root._runAction("copy", ["copy", "--id", String(item.id), "--field", field,
                "--clear", String(root.clipboardClearSeconds)]))
            root._noteUse(item);
    }

    function autoType(item, mode: string): void {
        if (!item)
            return;
        actionProc.lastItem = item;
        if (root._runAction("type", ["type", "--id", String(item.id), "--mode", mode]))
            root._noteUse(item);
    }

    function openLoginTerminal(): void {
        const terminal = Config.options?.apps?.terminal ?? "kitty -1";
        // The helper finds bw/rbw outside the session PATH (nvm, cargo…) and
        // keeps the session bw prints, so the vault comes back unlocked.
        const helper = Directories.scriptPath + "/password_manager.py";
        Quickshell.execDetached(["bash", "-c", `${terminal} -e python3 "$1" login --provider "$2"`,
            "bash", helper, root.provider || "auto"]);
        loginWatch.restart();
    }

    function _noteUse(item): void {
        root._touchRecent(String(item.id));
        if (root.autoLockMinutes > 0)
            autoLockTimer.restart();
    }

    function _applyStatus(payload): void {
        if (!payload?.ok) {
            root._fail(payload);
            return;
        }
        const wasUnlocked = root.unlocked;
        root.provider = String(payload.provider ?? "");
        root.account = String(payload.account ?? "");
        const host = String(payload.server ?? "").replace(/^https?:\/\//, "").replace(/\/.*$/, "").replace(/^vault\./, "");
        root.server = (host === "" || host.endsWith("bitwarden.com")) ? "" : host;
        root.state = String(payload.state ?? "locked");
        if (!root.unlocked) {
            root.items = [];
            autoLockTimer.stop();
        } else {
            if (!wasUnlocked && root.autoLockMinutes > 0)
                autoLockTimer.restart();
            if (root.items.length === 0)
                root.loadItems();
        }
    }

    Process {
        id: statusProc
        stdout: StdioCollector { id: statusOut }
        onExited: {
            try {
                root._applyStatus(JSON.parse(statusOut.text || "{}"));
            } catch (error) {
                console.warn("[PasswordManager] invalid status payload:", error);
            }
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector { id: listOut }
        onExited: {
            root.loadingItems = false;
            try {
                const payload = JSON.parse(listOut.text || "{}");
                if (payload.ok) {
                    root.items = payload.items ?? [];
                } else if (payload.code === "locked") {
                    root.state = "locked";
                    root.items = [];
                } else {
                    root._fail(payload);
                }
            } catch (error) {
                console.warn("[PasswordManager] invalid list payload:", error);
            }
        }
    }

    Process {
        id: actionProc
        property string pendingStdin: ""
        property var lastItem: null
        property string lastField: ""

        stdout: StdioCollector { id: actionOut }
        onStarted: {
            if (actionProc.pendingStdin.length > 0) {
                actionProc.write(actionProc.pendingStdin);
                actionProc.pendingStdin = "";
            }
            actionProc.stdinEnabled = false;
        }
        onExited: {
            const action = root.busyAction;
            root.busy = false;
            root.busyAction = "";
            let payload = {};
            try {
                payload = JSON.parse(actionOut.text || "{}");
            } catch (error) {
                payload = { ok: false, error: Translation.tr("The helper returned invalid data") };
            }
            if (!payload.ok) {
                root._fail(payload);
                if (payload.code === "locked") {
                    root.state = "locked";
                    root.items = [];
                }
                return;
            }
            root.clearError();
            switch (action) {
            case "unlock":
                root.state = "unlocked";
                root.refresh();
                break;
            case "lock":
                root.items = [];
                root.refresh();
                break;
            case "sync":
                root.items = [];
                root.loadItems();
                break;
            case "copy":
                root.clipField = actionProc.lastField;
                root.clipItemName = String(actionProc.lastItem?.name ?? "");
                root.clipSeconds = Number(payload.clear ?? 0);
                root.clipStartedAt = root.clipSeconds > 0 ? Date.now() : 0;
                root.clipRemaining = root.clipSeconds;
                break;
            }
        }
    }

    Process {
        id: detectProc
        stdout: StdioCollector { id: detectOut }
        onExited: {
            try {
                const payload = JSON.parse(detectOut.text || "{}");
                root.wtypeAvailable = payload.wtype ?? false;
                root.installed = payload.providers ?? {};
            } catch (error) {
                root.wtypeAvailable = false;
            }
        }
    }

    // The sign-in happens in a terminal we cannot see finish: check for a
    // while so the bar flips to unlocked without reopening the popup.
    Timer {
        id: loginWatch
        interval: 3000
        repeat: true
        property int ticks: 0
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            ticks++;
            if (root.unlocked || ticks > 100) {
                stop();
                return;
            }
            root.refresh();
        }
    }

    Timer {
        id: autoLockTimer
        interval: Math.max(1, root.autoLockMinutes) * 60000
        repeat: false
        onTriggered: {
            if (root.unlocked && root.provider !== "pass")
                root.lock();
        }
    }

    onAutoLockMinutesChanged: {
        if (root.autoLockMinutes <= 0)
            autoLockTimer.stop();
        else if (root.unlocked)
            autoLockTimer.restart();
    }

    onConfiguredProviderChanged: {
        root.items = [];
        root.state = "unknown";
        root.refresh();
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked && root.lockWithScreen && root.unlocked && root.provider !== "pass")
                root.lock();
        }
    }

    function detect(): void {
        if (!detectProc.running)
            detectProc.exec(["python3", Directories.scriptPath + "/password_manager.py", "detect"]);
    }

    Component.onCompleted: {
        root.refresh();
        root.detect();
    }
}
