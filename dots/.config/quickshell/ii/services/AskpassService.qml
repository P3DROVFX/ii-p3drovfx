pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Password prompts answered on the Dynamic Island: sudo, and optionally ssh/git and polkit.
 *
 * Every route is opt-in and off by default. sudo, ssh and git reach the shell through
 * `scripts/askpass/ii-askpass`, a client that speaks the askpass protocol (prompt in,
 * secret on stdout) and forwards it here over a Unix socket in $XDG_RUNTIME_DIR. The
 * socket exists only while a route is on, so with everything off the client finds no one
 * and falls back to a terminal or another askpass. Polkit already authenticates inside
 * the shell, so its route only decides whether PolkitService's flow is drawn here
 * or by the full-screen dialog.
 *
 * Nothing that works "for users without an askpass" is left to their setup: while a
 * sudo route is on, `askpass-setup.sh` installs the client outside the shell's tree,
 * installs a `sudo` wrapper in ~/.local/bin (never over one that isn't ours) and
 * exports SUDO_ASKPASS. Switching the routes off undoes exactly what it did.
 *
 * The secret passes through here once, on its way to the socket. It is never logged,
 * stored or kept once answered: the request object holding a socket is dropped.
 */
Singleton {
    id: root

    // ── The opt-in ───────────────────────────────────────────────────────────
    readonly property var options: Config.ready ? Config.options.bar.floatingNotch : null
    /** `sudo -A`, and anything else that runs SUDO_ASKPASS without a terminal. */
    readonly property bool sudoEnabled: !!root.options && root.options.askpassSudo === true
    /** Plain `sudo` typed in a terminal, through the wrapper; drawn as a pill. */
    readonly property bool terminalEnabled: !!root.options && root.options.askpassTerminal === true
    readonly property bool sshEnabled: !!root.options && root.options.askpassSsh === true
    readonly property bool polkitEnabled: !!root.options && root.options.askpassPolkit === true

    /** The island is on and will draw the prompt; IslandPolicy says so. */
    readonly property bool islandReady: GlobalStates.islandOwnsAskpass
    readonly property bool listening: root.islandReady
        && (root.sudoEnabled || root.terminalEnabled || root.sshEnabled)
    /** Polkit goes to the island instead of the full-screen dialog. */
    readonly property bool polkitOnIsland: root.islandReady && root.polkitEnabled

    /** "card" or "pill", per route. */
    readonly property string guiStyle: root.options && root.options.askpassStyle === "pill" ? "pill" : "card"
    readonly property string terminalStyle: root.options && root.options.askpassTerminalStyle === "card"
        ? "card" : "pill"

    // ── Requests ─────────────────────────────────────────────────────────────
    /**
     * Pending prompts, oldest first; the island shows the first. Each is a plain object:
     * { id, kind, route, prompt, command, echo, confirm, info, requester, chain,
     *   sockets, attempt, pending, racesFinger, fingerprintOver, windowClass,
     *   windowTitle, focusNow, resolved, arrivedAt }
     */
    property var requests: []
    readonly property var current: root.requests.length > 0 ? root.requests[0] : null
    readonly property int waitingCount: Math.max(0, root.requests.length - 1)
    /** The card draws the current request as this style. */
    readonly property string currentStyle: {
        const request = root.current;
        if (!request)
            return root.guiStyle;
        return request.route === "terminal" ? root.terminalStyle : root.guiStyle;
    }
    /** Bumped when a field of the current request changes in place. */
    property int revision: 0

    property int _nextId: 1
    /** requester pid -> { at, attempt, prompt } for the last answered sudo request. */
    property var _answered: ({})
    /** requester pid -> when the user cancelled it; see `cancel`. */
    property var _cancelled: ({})

    /**
     * After editing a request in place. Each one is replaced by a copy: `current` is a
     * var, and a var only tells its readers when it becomes a different object, so an
     * edit to the same one never reached the card (the requester's icon, the fingerprint
     * giving up). Nothing keeps a request across this but by its id.
     */
    function _changed() {
        root.requests = root.requests.map(request => Object.assign({}, request));
        root.revision += 1;
    }

    // ── Answers ──────────────────────────────────────────────────────────────
    function _reply(socket, message) {
        if (!socket || !socket.connected)
            return;
        socket.write(JSON.stringify(message) + "\n");
        socket.flush();
    }

    function _remove(request) {
        root.requests = root.requests.filter(other => other !== request);
        root.revision += 1;
    }

    /** Answer the prompt on screen. False when there is nobody to answer yet. */
    function submit(secret) {
        const request = root.current;
        if (!request)
            return false;
        if (request.kind === "polkit") {
            if (PolkitService.interactionAvailable)
                PolkitService.submit(secret);
            request.pending = true;
            root._changed();
            return true;
        }
        // Held while pam_unix takes over from grosshack (see _dropSocket): the answer
        // waits in the field for the prompt that is about to land on it.
        if (request.sockets.length === 0 || request.pending)
            return false;
        for (const socket of request.sockets)
            root._reply(socket, { r: "ok", secret: String(secret) });
        root._noteAnswered(request);
        root._checking(request);
        return true;
    }

    /**
     * An answered sudo prompt stays as "Checking…" while PAM decides: the client leaves a
     * watcher on the socket that says "done" when sudo goes on (or gives up), and a wrong
     * password brings the next prompt onto this one (see _receive) - rather than the
     * island closing for PAM's pause and opening again. Anything else just goes.
     */
    function _checking(request) {
        if (request.kind !== "sudo") {
            root._remove(request);
            return;
        }
        request.pending = true;
        root._changed();
    }

    /**
     * Cancelling ends the sudo, not just this prompt. A prompt that raced a finger
     * (pam_fprintd_grosshack) is followed at once by pam_unix asking again from the same
     * sudo, so whatever that sudo asks next is cancelled without being shown.
     */
    function cancel() {
        const request = root.current;
        if (!request)
            return;
        if (request.kind === "polkit") {
            PolkitService.cancel();
            root._remove(request);
            return;
        }
        for (const socket of request.sockets)
            root._reply(socket, { r: "cancel" });
        if (request.kind === "sudo")
            root._cancelled[request.requester] = Date.now();
        root._remove(request);
    }

    function _noteAnswered(request) {
        if (request.kind === "sudo")
            root._answered[request.requester] = {
                at: Date.now(),
                attempt: request.attempt,
                prompt: request.prompt
            };
    }

    /**
     * A password, passphrase or PIN, or grosshack's password-or-finger - as opposed to a
     * second factor asked after one (a verification code, a token), which is a new question
     * and not a retry.
     */
    function _asksPassword(prompt) {
        const text = String(prompt ?? "");
        return /pass(word|phrase)|\bpin\b|finger/i.test(text)
            && !/one.?time|verification|\bcode\b|\btoken\b|\botp\b/i.test(text);
    }

    // Records older than any retry or follow-up could be are dropped as new ones come.
    function _prune(map) {
        const now = Date.now();
        for (const key of Object.keys(map)) {
            const at = typeof map[key] === "number" ? map[key] : map[key].at;
            if (now - at > 60000)
                delete map[key];
        }
    }

    // ── The socket ───────────────────────────────────────────────────────────
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/ii-askpass.sock`

    SocketServer {
        active: root.listening
        path: root.socketPath
        handler: Socket {
            id: socket
            parser: SplitParser {
                onRead: data => {
                    // A chunk can carry more than one line.
                    for (const line of String(data).split("\n")) {
                        if (line.trim() !== "")
                            root._receive(socket, line);
                    }
                }
            }
            onConnectedChanged: {
                if (!socket.connected)
                    root._dropSocket(socket);
            }
        }
    }

    function _routeEnabled(message) {
        if (message.kind === "ssh" || message.kind === "git")
            return root.sshEnabled;
        if (message.route === "terminal")
            return root.terminalEnabled;
        return root.sudoEnabled;
    }

    function _receive(socket, line) {
        let message = null;
        try {
            message = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!message)
            return;
        // The terminal answered a plain `sudo` before the island did. Any other prompt on
        // the same card is one grosshack abandoned: nothing reads it.
        if (message.op === "answered") {
            const answered = root.requests.find(request => request.sockets.indexOf(socket) !== -1);
            if (!answered)
                return;
            root._noteAnswered(answered);
            for (const other of answered.sockets) {
                if (other !== socket)
                    root._reply(other, { r: "cancel" });
            }
            answered.sockets.splice(0, answered.sockets.length, socket);
            root._checking(answered);
            return;
        }
        // The answer's watcher: sudo went on (right password) or gave up.
        if (message.op === "done") {
            const finished = root.requests.find(request => request.sockets.indexOf(socket) !== -1);
            if (finished)
                root._remove(finished);
            return;
        }
        if (message.op !== "ask")
            return;
        if (!root._routeEnabled(message)) {
            root._reply(socket, { r: "fallback" });
            return;
        }
        const requester = Number(message.requester) || 0;
        const kind = ["sudo", "ssh", "git"].indexOf(message.kind) !== -1 ? message.kind : "sudo";
        const prompt = String(message.prompt ?? "");
        root._prune(root._answered);
        root._prune(root._cancelled);

        if (kind === "sudo" && root._cancelled[requester] !== undefined) {
            root._reply(socket, { r: "cancel" });
            return;
        }

        // A second prompt from a sudo whose first is still open: grosshack's fingerprint
        // phase ended without a match and pam_unix asks again. Same card, same text;
        // the answer goes to both.
        if (kind === "sudo") {
            const open = root.requests.find(request => request.kind === "sudo"
                && request.requester === requester);
            // The answer was checked and sudo asks again: the same prompt, now saying the
            // password was wrong - or a new question, when it is one (a code after the
            // password).
            if (open && open.pending) {
                const retry = open.prompt === prompt
                    || (root._asksPassword(open.prompt) && root._asksPassword(prompt));
                delete root._answered[requester];
                // The last answer's watcher is done: the new prompt holds the card now.
                for (const watcher of open.sockets)
                    root._reply(watcher, { r: "again" });
                open.sockets.splice(0, open.sockets.length, socket);
                open.attempt = retry ? open.attempt + 1 : 0;
                open.pending = false;
                open.prompt = prompt;
                open.echo = message.echo === true;
                open.racesFinger = /finger/i.test(prompt);
                open.fingerprintOver = false;
                root._changed();
                return;
            }
            if (open) {
                open.sockets.push(socket);
                if (open.racesFinger)
                    open.fingerprintOver = true;
                root._changed();
                return;
            }
        }

        // The same sudo asking the same question again soon after an answer: the
        // password was wrong. A different question (a code after the password) is not.
        let attempt = 0;
        const last = root._answered[requester];
        const sameQuestion = last && (last.prompt === prompt
            || (root._asksPassword(last.prompt) && root._asksPassword(prompt)));
        if (kind === "sudo" && sameQuestion && Date.now() - last.at < 20000)
            attempt = last.attempt + 1;
        delete root._answered[requester];

        const chain = Array.isArray(message.chain) ? message.chain.map(Number) : [];
        const request = {
            id: root._nextId++,
            kind: kind,
            route: message.route === "terminal" ? "terminal" : "askpass",
            prompt: prompt,
            command: String(message.command ?? ""),
            echo: message.echo === true,
            confirm: message.confirm === true,
            info: message.info === true,
            requester: requester,
            chain: chain,
            sockets: [socket],
            attempt: attempt,
            pending: false,
            // pam_fprintd_grosshack's prompt: typing and a finger race for it.
            racesFinger: kind === "sudo" && /finger/i.test(prompt),
            fingerprintOver: false,
            windowClass: "",
            windowTitle: "",
            focusNow: false,
            resolved: false,
            arrivedAt: Date.now()
        };
        root.requests = root.requests.concat([request]);
        root.revision += 1;
        root._findWindow(request);
    }

    function _dropSocket(socket) {
        let changed = false;
        const left = [];
        for (const request of root.requests) {
            const index = request.sockets.indexOf(socket);
            if (index === -1) {
                left.push(request);
                continue;
            }
            request.sockets.splice(index, 1);
            changed = true;
            if (request.kind === "polkit" || request.sockets.length > 0) {
                left.push(request);
                continue;
            }
            // grosshack abandons the prompt that raced a finger whenever the finger side
            // ends, and after a timeout pam_unix asks again a moment later. Held briefly,
            // so that question lands on this prompt instead of the island closing and
            // opening again; see _receive.
            // The same goes for an answer being checked whose watcher just saw the next
            // prompt coming.
            if (request.pending || (request.racesFinger && !request.fingerprintOver)) {
                left.push(request);
                lingerTimer.restart();
            }
            // Otherwise nobody is waiting for this prompt any more (Ctrl-C, sudo gone).
        }
        if (changed) {
            root.requests = left;
            root.revision += 1;
        }
    }

    // Ends the hold above: a prompt still without an asker goes.
    Timer {
        id: lingerTimer
        interval: 400
        onTriggered: {
            const left = root.requests.filter(request => request.kind === "polkit"
                || request.sockets.length > 0);
            if (left.length === root.requests.length)
                return;
            root.requests = left;
            root.revision += 1;
        }
    }

    // ── Who asked ────────────────────────────────────────────────────────────
    /**
     * The window whose process started sudo, and whether it is the focused one.
     *
     * One read per request, never polled. A prompt only takes the keyboard by itself when
     * the user is looking at the window that asked - a background build asking midway
     * must not steal whatever is being typed elsewhere into a password field and burn a
     * faillock attempt.
     */
    // The lookup is handed the request's id, never the request: an object passed through
    // createObject's initial properties arrives as a copy, and whatever the lookup found
    // was written to that copy.
    Component {
        id: windowLookup
        Process {
            id: lookup
            property int requestId: 0
            command: ["sh", "-c", "hyprctl -j clients; printf '\\n\\x1e\\n'; hyprctl -j activewindow"]
            stdout: StdioCollector {
                id: lookupOut
                onStreamFinished: {
                    root._resolveWindow(lookup.requestId, String(lookupOut.text ?? ""));
                    lookup.destroy();
                }
            }
            onExited: (code, status) => {
                if (code !== 0) {
                    root._resolveWindow(lookup.requestId, "");
                    lookup.destroy();
                }
            }
        }
    }

    function _findWindow(request) {
        const process = windowLookup.createObject(root, { requestId: request.id });
        process.running = true;
    }

    function _resolveWindow(requestId, text) {
        const request = root.requests.find(entry => entry.id === requestId);
        if (!request || request.resolved)
            return;
        request.resolved = true;
        try {
            const parts = text.split("\x1e");
            const clients = JSON.parse(parts[0]);
            const active = JSON.parse(parts[1] || "{}");
            for (const pid of request.chain) {
                const windows = clients.filter(entry => entry.pid === pid);
                if (windows.length === 0)
                    continue;
                // One process can own several windows - kitty, a foot server, a terminal
                // server. The one whose title shows the command is the asker when titles
                // tell them apart; otherwise whichever of them is focused.
                const command = request.command.length > 4 ? request.command : "";
                const titled = command === "" ? []
                    : windows.filter(entry => String(entry.title ?? "").indexOf(command) !== -1);
                const focused = windows.find(entry => !!active && entry.address === active.address);
                const client = titled.length === 1 ? titled[0] : (focused ?? windows[0]);
                request.windowClass = String(client.class ?? "");
                request.windowTitle = String(client.title ?? "");
                request.focusNow = !!active && active.address === client.address;
                break;
            }
        } catch (e) {
            // No compositor answer: the prompt just waits for a click.
        }
        root._changed();
    }

    // ── Polkit ───────────────────────────────────────────────────────────────
    readonly property bool _polkitWanted: root.polkitOnIsland && PolkitService.active && !!PolkitService.flow
    on_PolkitWantedChanged: root._syncPolkit()

    function _syncPolkit() {
        const existing = root.requests.find(request => request.kind === "polkit");
        if (root._polkitWanted && !existing) {
            root.requests = root.requests.concat([{
                id: root._nextId++,
                kind: "polkit",
                route: "askpass",
                prompt: PolkitService.cleanPrompt,
                command: PolkitService.cleanMessage,
                echo: PolkitService.flow?.responseVisible ?? false,
                confirm: false,
                info: false,
                requester: 0,
                chain: [],
                sockets: [],
                attempt: 0,
                pending: false,
                racesFinger: false,
                fingerprintOver: false,
                windowClass: "",
                windowTitle: "",
                // Asked for by something the user just did in a GUI; there is no process
                // tree to check against.
                focusNow: true,
                resolved: true,
                arrivedAt: Date.now()
            }]);
            root.revision += 1;
        } else if (!root._polkitWanted && existing) {
            root._remove(existing);
        }
    }

    Connections {
        target: PolkitService
        function onInteractionAvailableChanged() {
            const request = root.requests.find(entry => entry.kind === "polkit");
            if (!request || !PolkitService.interactionAvailable)
                return;
            // Interaction coming back after an answer means the answer was wrong.
            if (request.pending)
                request.attempt += 1;
            request.pending = false;
            request.prompt = PolkitService.cleanPrompt;
            request.echo = PolkitService.flow?.responseVisible ?? false;
            root._changed();
        }
    }

    // ── Session setup ────────────────────────────────────────────────────────
    /**
     * The askpass the user had before the shell touched anything, kept as the client's
     * fallback. Read from the shell's own environment, which Hyprland gave it at start.
     */
    readonly property string _previousAskpass: Quickshell.env("II_ASKPASS_FALLBACK")
        || Quickshell.env("SUDO_ASKPASS") || ""

    /** What the last setup run reported: { wrapper: installed|foreign|absent, binOnPath }. */
    property var setupStatus: ({})
    readonly property string _setupKey: [root.sudoEnabled && root.islandReady,
        root.terminalEnabled && root.islandReady, root.sshEnabled && root.islandReady].join(",")
    on_SetupKeyChanged: setupDebounce.restart()
    // Once at start as well: after a reload the service can be created with the config
    // and the island already there, and a key that never changes never runs the setup -
    // which is also what refreshes the installed client after the shell's copy changed.
    Component.onCompleted: setupDebounce.restart()

    Timer {
        id: setupDebounce
        interval: 600
        onTriggered: {
            // Config becoming ready restarts it.
            if (!Config.ready)
                return;
            setupProc.running = false;
            setupProc.running = true;
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                setupDebounce.restart();
        }
    }

    Process {
        id: setupProc
        command: ["bash", `${Directories.scriptPath}/askpass/askpass-setup.sh`,
            (root.sudoEnabled && root.islandReady) ? "1" : "0",
            (root.terminalEnabled && root.islandReady) ? "1" : "0",
            (root.sshEnabled && root.islandReady) ? "1" : "0",
            root._previousAskpass]
        stdout: StdioCollector {
            id: setupOut
            onStreamFinished: {
                try {
                    root.setupStatus = JSON.parse(String(setupOut.text ?? "").trim().split("\n").pop());
                } catch (e) {
                    root.setupStatus = {};
                }
            }
        }
    }
}
