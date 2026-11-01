pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The sidebar Anki tab's backend: a JSON-lines bridge to scripts/anki/anki_daemon.py,
 * which runs the official `anki` package (Anki's own scheduler, renderer and AnkiWeb
 * sync) from a private venv in ~/.local/share/ii-anki.
 *
 * Headless and lazy: nothing runs until the tab asks (`hold()`), and the ~60 MB daemon
 * exits a minute after the last holder lets go. Collection state lives in the daemon;
 * this singleton mirrors only what the UI draws.
 */
Singleton {
    id: root

    readonly property string dataDir: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/ii-anki`)
    readonly property string pythonPath: `${root.dataDir}/venv/bin/python`
    readonly property string daemonPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/anki/anki_daemon.py"))
    readonly property string installerPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/anki/install.sh"))

    // ── Install state ────────────────────────────────────────────────────
    /// null until probed, then whether the venv with `anki` exists.
    property var installed: null
    property bool installing: false
    property string installStep: ""
    property string installError: ""

    // ── Daemon state ─────────────────────────────────────────────────────
    property int holders: 0
    readonly property bool wanted: root.holders > 0
    property bool ready: false
    /// "" or a fatal start error ("locked", "open-failed", "crashed").
    property string fatal: ""
    property bool mathjax: false
    property string version: ""

    // ── Collection mirror ────────────────────────────────────────────────
    property var decks: []
    property var totals: ({ "new": 0, "learn": 0, "review": 0 })
    property var studiedToday: ({ "cards": 0, "seconds": 0 })
    property int cardCount: 0
    property bool decksLoaded: false

    // ── Account / sync ───────────────────────────────────────────────────
    property bool loggedIn: false
    property string username: ""
    /// "", "login", "collection", "download", "upload", "media"
    property string syncStage: ""
    readonly property bool syncing: root.syncStage.length > 0
    property string syncError: ""
    property bool syncConflict: false
    property string lastSyncMessage: ""

    // ── Review session ───────────────────────────────────────────────────
    property var card: null
    property bool revealed: false
    property bool studying: false
    property var studyDeck: null
    property bool cardBusy: false
    property string lastError: ""
    /// Bumps on every new card so views can restart their entrance.
    property int cardSerial: 0

    signal cardAnswered(int ease)
    signal toast(string message)

    function hold() {
        root.holders += 1;
        if (root.installed === null)
            installProbe.running = true;
        root.ensureRunning();
    }

    function release() {
        root.holders = Math.max(0, root.holders - 1);
    }

    function ensureRunning() {
        if (!root.wanted || root.installed !== true || daemon.running || root.fatal.length > 0)
            return;
        root.ready = false;
        daemon.running = true;
    }

    function retryStart() {
        root.fatal = "";
        root.ensureRunning();
    }

    function install() {
        if (root.installing)
            return;
        root.installing = true;
        root.installError = "";
        root.installStep = Translation.tr("Starting");
        installer.running = true;
    }

    // ── Requests ─────────────────────────────────────────────────────────
    property int _nextId: 1
    property var _pending: ({})

    function request(cmd: string, args: var, callback: var) {
        if (!daemon.running || !root.ready) {
            if (callback)
                callback(false, "not-ready");
            return;
        }
        const id = root._nextId++;
        const msg = Object.assign({ "id": id, "cmd": cmd }, args || {});
        if (callback)
            root._pending[id] = callback;
        daemon.write(JSON.stringify(msg) + "\n");
    }

    function _handle(line: string) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.event !== undefined) {
            root._handleEvent(msg);
            return;
        }
        const cb = root._pending[msg.id];
        delete root._pending[msg.id];
        if (cb)
            cb(msg.ok, msg.ok ? msg.data : msg.error);
    }

    function _handleEvent(msg) {
        if (msg.event === "ready") {
            root.ready = true;
            root.fatal = "";
            root._afterReady();
        } else if (msg.event === "fatal") {
            root.fatal = msg.kind || "open-failed";
            root.lastError = msg.error || "";
        } else if (msg.event === "sync") {
            root.syncStage = msg.stage;
        }
    }

    function _afterReady() {
        root.request("hello", {}, (ok, data) => {
            if (!ok)
                return;
            root.version = data.version;
            root.mathjax = data.mathjax;
            root.loggedIn = data.loggedIn;
            root.username = data.username;
            root.cardCount = data.cards;
        });
        root.pushTheme();
        root.refreshDecks();
        if (root.studying && root.studyDeck)
            root.study(root.studyDeck);
    }

    // The daemon colours formulas and clamps images; the tab tells it how.
    property color themeText: Appearance.colors.colOnLayer1
    property int themeFontPx: Appearance.font.pixelSize.larger
    property int themeMaxWidth: 360
    onThemeTextChanged: root.pushTheme()
    readonly property bool themeDark: Appearance.m3colors.darkmode
    onThemeDarkChanged: root.pushTheme()
    onThemeMaxWidthChanged: themePush.restart()

    Timer {
        id: themePush
        interval: 300
        onTriggered: root.pushTheme()
    }

    function pushTheme() {
        if (!root.ready)
            return;
        root.request("theme", {
            "color": root.themeText.toString(),
            "fontPx": root.themeFontPx,
            "maxWidth": Math.round(root.themeMaxWidth),
            "dark": Appearance.m3colors.darkmode
        }, null);
    }

    function refreshDecks() {
        root.request("decks", {}, (ok, data) => {
            if (!ok)
                return;
            root.decks = data.decks;
            root.totals = data.totals;
            root.studiedToday = data.studiedToday;
            root.cardCount = data.cards;
            root.decksLoaded = true;
        });
    }

    function _setCard(ok, data) {
        root.cardBusy = false;
        if (!ok) {
            root.lastError = String(data);
            if (data === "stale-card")
                root.request("current", {}, root._setCard);
            else if (data === "nothing-to-undo")
                root.toast(Translation.tr("Nothing to undo"));
            return;
        }
        root.revealed = false;
        root.card = data;
        root.cardSerial += 1;
        if (data && data.autoplay)
            root.playSide(false);
        if (!data)
            root.refreshDecks();
    }

    function study(deck) {
        root.studyDeck = deck;
        root.studying = true;
        root.card = null;
        root.revealed = false;
        root.cardBusy = true;
        root.request("study", { "deckId": deck.id }, root._setCard);
    }

    function endStudy() {
        root.stopAudio();
        root.studying = false;
        root.card = null;
        root.revealed = false;
        root.refreshDecks();
    }

    function reveal(typed: string) {
        if (!root.card || root.revealed || root.cardBusy)
            return;
        root.cardBusy = true;
        root.request("reveal", { "cardId": root.card.cardId, "typed": typed ?? "" }, (ok, data) => {
            root.cardBusy = false;
            if (!ok) {
                root._setCard(ok, data);
                return;
            }
            root.card = data;
            root.revealed = true;
            if (data.autoplay)
                root.playSide(true);
        });
    }

    function answer(ease: int) {
        if (!root.card || !root.revealed || root.cardBusy)
            return;
        root.cardBusy = true;
        root.stopAudio();
        root.cardAnswered(ease);
        root.request("answer", { "cardId": root.card.cardId, "ease": ease }, root._setCard);
    }

    function cardAction(cmd: string, extra: var) {
        if (!root.card || root.cardBusy)
            return;
        root.cardBusy = true;
        root.request(cmd, Object.assign({ "cardId": root.card.cardId }, extra || {}), (ok, data) => {
            if (ok && (cmd === "flag" || cmd === "mark")) {
                root.cardBusy = false;
                // Same card, new flag: keep the side the user is on.
                const revealed = root.revealed;
                root.card = data;
                root.revealed = revealed;
                return;
            }
            root._setCard(ok, data);
        });
    }

    function undo() {
        if (root.cardBusy)
            return;
        root.cardBusy = true;
        root.request("undo", {}, root._setCard);
    }

    function playSide(answerSide: bool) {
        if (!root.card)
            return;
        const list = (answerSide ? root.card.audioA : root.card.audioQ).filter(a => a.kind === "file");
        if (list.length > 0)
            root.request("play", { "path": list[0].path }, null);
    }

    function play(path: string) {
        root.request("play", { "path": path }, null);
    }

    function stopAudio() {
        root.request("stopAudio", {}, null);
    }

    // ── Collection editing ───────────────────────────────────────────────
    function createDeck(name: string, callback: var) {
        root.request("createDeck", { "name": name }, (ok, data) => {
            if (ok)
                root.refreshDecks();
            if (callback)
                callback(ok, data);
        });
    }

    function addNote(deckId, fields: var, callback: var) {
        root.request("addNote", { "deckId": deckId, "fields": fields }, (ok, data) => {
            if (ok)
                root.refreshDecks();
            if (callback)
                callback(ok, data);
        });
    }

    property bool importing: false

    function importPackage() {
        if (root.importing || pickerProc.running)
            return;
        pickerProc.running = true;
    }

    function _importPath(path: string) {
        root.importing = true;
        root.request("importApkg", { "path": path }, (ok, data) => {
            root.importing = false;
            if (ok) {
                root.toast(Translation.tr("Imported %1 notes").arg(data.new + data.updated));
                root.refreshDecks();
            } else {
                root.toast(Translation.tr("Import failed: %1").arg(String(data)));
            }
        });
    }

    // ── Account ──────────────────────────────────────────────────────────
    function login(user: string, password: string, callback: var) {
        root.syncStage = "login";
        root.syncError = "";
        root.request("login", { "username": user, "password": password }, (ok, data) => {
            root.syncStage = "";
            if (ok) {
                root.loggedIn = true;
                root.username = data.username;
                root.sync();
            } else {
                root.syncError = root.describeSyncError(data);
            }
            if (callback)
                callback(ok, ok ? data : root.syncError);
        });
    }

    function logout() {
        root.request("logout", {}, (ok) => {
            if (!ok)
                return;
            root.loggedIn = false;
            root.username = "";
        });
    }

    function sync() {
        if (!root.loggedIn || root.syncing)
            return;
        root.syncError = "";
        root.syncConflict = false;
        root.syncStage = "collection";
        root.request("sync", {}, root._afterSync);
    }

    function resolveConflict(upload: bool) {
        root.syncConflict = false;
        root.syncStage = upload ? "upload" : "download";
        root.request("fullSync", { "upload": upload }, root._afterSync);
    }

    function _afterSync(ok, data) {
        root.syncStage = "";
        if (!ok) {
            root.syncError = root.describeSyncError(data);
            if (String(data) === "not-logged-in")
                root.loggedIn = false;
            return;
        }
        if (data.conflict) {
            root.syncConflict = true;
            root.lastSyncMessage = data.message || "";
            return;
        }
        root.lastSyncMessage = data.message || "";
        root.refreshDecks();
        if (root.studying && root.studyDeck)
            root.study(root.studyDeck);
    }

    function describeSyncError(err): string {
        const s = String(err);
        if (/auth|password|credential|SyncError: .*(403|unauthor)/i.test(s))
            return Translation.tr("AnkiWeb refused the email or password");
        if (/network|timed out|connect|dns|resolve/i.test(s))
            return Translation.tr("Couldn't reach AnkiWeb");
        if (s === "not-logged-in")
            return Translation.tr("Sign in to AnkiWeb first");
        return s;
    }

    // ── Processes ────────────────────────────────────────────────────────
    Timer {
        id: idleStop
        interval: 60000
        running: !root.wanted && daemon.running && !root.syncing && !root.importing
        onTriggered: {
            if (root.ready)
                daemon.write('{"id":0,"cmd":"quit"}\n');
            else
                daemon.running = false;
        }
    }

    onWantedChanged: root.ensureRunning()
    onInstalledChanged: root.ensureRunning()

    Process {
        id: daemon
        stdinEnabled: true
        command: ProcUtils.pdeath([root.pythonPath, root.daemonPath])
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root._handle(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("[Anki]", line)
        }
        onRunningChanged: {
            if (running)
                return;
            const wasReady = root.ready;
            root.ready = false;
            root.syncStage = "";
            root.cardBusy = false;
            const pending = root._pending;
            root._pending = {};
            for (const id in pending)
                pending[id](false, "daemon-exited");
            if (!wasReady && root.fatal.length === 0 && root.wanted)
                root.fatal = "crashed";
            else if (wasReady && root.wanted)
                respawn.restart();
        }
    }

    // A daemon that dies mid-session (killed, updated) comes back while the tab is open.
    Timer {
        id: respawn
        interval: 1000
        onTriggered: root.ensureRunning()
    }

    Process {
        id: installProbe
        command: ["test", "-x", root.pythonPath]
        onExited: (code) => root.installed = code === 0
    }

    Process {
        id: installer
        command: ["bash", root.installerPath]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("STEP "))
                    root.installStep = line.replace(/^STEP \S+ /, "");
                else if (line.startsWith("WARN "))
                    console.warn("[Anki] install:", line);
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim().length > 0)
                    root.installError = line.trim();
            }
        }
        onExited: (code) => {
            root.installing = false;
            if (code === 0) {
                root.installError = "";
                root.installed = true;
            } else if (root.installError.length === 0) {
                root.installError = Translation.tr("The installer stopped (code %1)").arg(code);
            }
        }
    }

    Process {
        id: pickerProc
        command: ["python3", Quickshell.shellPath("scripts/file_picker.py"), "--title", Translation.tr("Import Anki deck"),
            "--filters", JSON.stringify(["Anki decks (*.apkg)"])]
        stdout: StdioCollector {
            onStreamFinished: {
                let path = "";
                try {
                    path = JSON.parse(text.trim() || "null") || "";
                } catch (e) {
                    path = "";
                }
                if (path.length > 0)
                    root._importPath(path);
            }
        }
    }
}
