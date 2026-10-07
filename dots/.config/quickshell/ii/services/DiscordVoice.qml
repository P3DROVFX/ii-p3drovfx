pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root

    property string status: "starting"
    // Which client is driving the state. Worth surfacing: the two backends fail
    // in different ways, and "Vesktop" in the popup is what tells a user the
    // companion plugin is actually running.
    property string backend: ""
    readonly property string backendLabel: backend === "vencord" ? "Vesktop"
        : (backend === "discord" ? "Discord" : "")
    property string errorMessage: ""
    property var currentUser: ({})
    property var channel: null
    property var participants: []
    readonly property alias participantModel: participantsModel
    readonly property int participantCount: participantsModel.count
    property bool muted: false
    property bool deafened: false
    property int restartAttempts: 0
    property var pendingMessages: []
    readonly property bool authenticated: status === "authenticated" || channel !== null
    readonly property bool inVoice: channel !== null
    readonly property int maxRestartAttempts: 5

    /**
     * Stopped because Discord is gone, not because it failed. The bridge reports
     * "unavailable" while neither the RPC socket nor the Vesktop companion answers;
     * after a minute of that it is stopped instead of reconnecting every 3 s for the
     * rest of the session. A Discord window coming back (or any voice command, see
     * send()) starts it again. A client in the tray keeps its RPC socket, so a call
     * never loses its bridge.
     */
    property bool parked: false

    /**
     * Vesktop, Equibop and Vencord-patched Discord route voice through arRPC, which
     * connects but never authorizes voice: on those clients only the iiDiscordVoice
     * companion plugin makes the bridge useful. Without it the bridge is not started
     * at all (the overlay offers the install), instead of idling on an RPC socket that
     * cannot answer. `recheck()` runs again after a successful install.
     */
    property bool isVencordClient: false
    property bool companionInstalled: false
    readonly property bool companionMissing: isVencordClient && !companionInstalled
    function recheck() { clientCheck.running = true; }
    readonly property bool discordWindowOpen: root.parked
        && (HyprlandData.windowList ?? []).some(client =>
            GlobalStates._discordClasses.indexOf(String(client?.class ?? "").toLowerCase()) !== -1)
    onDiscordWindowOpenChanged: if (root.discordWindowOpen) root.start(true)

    ListModel {
        id: participantsModel
        dynamicRoles: true
    }

    function updateParticipants(users) {
        const incoming = users || [];
        const incomingIds = new Set(incoming.map(user => String(user.id || "")));

        // Remove departed users without disturbing the relative position of
        // everyone who remains in the call.
        for (let index = participantsModel.count - 1; index >= 0; --index) {
            const current = participantsModel.get(index).participant;
            if (!incomingIds.has(String(current?.id || "")))
                participantsModel.remove(index);
        }

        // Update existing rows in place and append newcomers. Stable delegates
        // retain their image textures and can animate voice-state changes.
        for (const user of incoming) {
            const id = String(user.id || "");
            let existingIndex = -1;
            for (let index = 0; index < participantsModel.count; ++index) {
                if (String(participantsModel.get(index).participant?.id || "") === id) {
                    existingIndex = index;
                    break;
                }
            }
            if (existingIndex >= 0)
                participantsModel.setProperty(existingIndex, "participant", user);
            else
                participantsModel.append({ participant: user });
        }
        participants = incoming;
    }

    function avatarUrl(user, size) {
        if (!user?.id || !user?.avatar) return "";
        return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png?size=${size || 64}`;
    }

    function send(message) {
        if (!bridge.running) {
            pendingMessages = pendingMessages.concat([message]);
            start(true);
            return;
        }
        bridge.write(JSON.stringify(message) + "\n");
    }

    function connect() {
        errorMessage = "";
        send({cmd: "connect"});
    }

    function authorize() { send({cmd: "authorize"}); }
    function authorizeAfterFocusRelease() { focusReleaseDelay.restart(); }
    function setMuted(value) { send({cmd: "set_voice_settings", mute: value}); }
    function setDeafened(value) { send({cmd: "set_voice_settings", deaf: value}); }

    function start(manual) {
        if (bridge.running) return;
        parked = false;
        if (manual) restartAttempts = 0;
        status = "starting";
        bridge.running = true;
    }

    function flushPendingMessages() {
        const queued = pendingMessages;
        pendingMessages = [];
        for (const message of queued)
            bridge.write(JSON.stringify(message) + "\n");
    }

    function handleLine(line) {
        let message;
        try { message = JSON.parse(line); } catch (error) { return; }
        switch (message.type) {
        case "ready": connect(); break;
        case "backend": backend = message.backend || ""; break;
        case "connected": status = "connected"; reconnectTimer.stop(); parkTimer.stop(); break;
        case "auth_required": status = "auth_required"; break;
        case "authorizing":
            status = "authorizing";
            break;
        case "authenticated":
            status = "authenticated";
            currentUser = message.user || {};
            restartAttempts = 0;
            break;
        case "voice_channel":
            channel = message.channel || null;
            updateParticipants(message.users);
            break;
        case "voice_state": updateParticipants(message.users); break;
        case "voice_settings":
            muted = message.mute === true;
            deafened = message.deaf === true;
            break;
        case "unavailable":
            status = "unavailable";
            errorMessage = message.message || "";
            reconnectTimer.restart();
            // Repeated every reconnect: only the first one starts the countdown.
            if (!parkTimer.running)
                parkTimer.start();
            break;
        // The companion is one of two backends. Its failure leaves Discord's
        // own RPC usable, so this reports the reason without moving `status`
        // into an authorization state the user cannot act on.
        case "companion_error": errorMessage = message.message || ""; break;
        case "disconnected": status = "disconnected"; backend = ""; channel = null; updateParticipants([]); reconnectTimer.restart(); break;
        case "error":
            status = "auth_required";
            errorMessage = message.message || "Discord RPC error";
            break;
        }
    }

    Component.onCompleted: clientCheck.running = true

    Process {
        id: clientCheck
        // A leftover ~/.config/vesktop or ~/.config/equibop dir (e.g. from a theme
        // installer) without the client itself must not count, hence has_profile.
        // The companion counts once a client loads it, see companion_check.py.
        command: ["bash", "-c", `
            has_profile() {
                [ -d "$1/Local Storage" ] || [ -d "$1/Session Storage" ] || [ -d "$1/Cache" ]
            }
            if { [ -f ~/.config/Vencord/dist/patcher.js ] \\
                    && { command -v discord >/dev/null 2>&1 || has_profile ~/.config/discord; }; } \\
                || command -v vesktop >/dev/null 2>&1 \\
                || { [ -d ~/.config/vesktop ] && has_profile ~/.config/vesktop; } \\
                || command -v equibop >/dev/null 2>&1 \\
                || { [ -d ~/.config/equibop ] && has_profile ~/.config/equibop; }; then
                echo vencord
            fi
            python3 -I "${Directories.scriptPath}/discordVoice/companion_check.py"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.isVencordClient = lines.includes("vencord");
                root.companionInstalled = lines.includes("companion");
                if (!root.companionMissing) {
                    root.start(false);
                } else if (!bridge.running) {
                    root.status = "auth_required";
                    root.errorMessage = "Vesktop/Vencord users must install and enable the II Discord Voice companion.";
                }
            }
        }
    }

    Timer {
        id: parkTimer
        interval: 60000
        onTriggered: {
            if (root.status !== "unavailable")
                return;
            root.parked = true;
            reconnectTimer.stop();
            bridge.running = false;
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root.start(false)
    }

    // The bridge process stays alive after Discord drops the RPC socket (e.g. a
    // Discord restart), but it will not reconnect on its own. Re-issue connect on
    // a fixed cadence until the socket is back; connect() no-ops once linked.
    Timer {
        id: reconnectTimer
        interval: 3000
        repeat: true
        onTriggered: root.connect()
    }

    Timer {
        id: focusReleaseDelay
        interval: 220
        onTriggered: root.authorize()
    }

    Process {
        id: bridge
        command: ["python3", `${Directories.scriptPath}/discordVoice/discord_voice_bridge.py`]
        stdinEnabled: true
        onStarted: root.flushPendingMessages()
        // process-lifecycle: restart-safe -- capped exponential backoff; no running binding.
        stdout: SplitParser { onRead: data => root.handleLine(data) }
        stderr: SplitParser { onRead: data => console.warn("[DiscordVoice]", data) }
        onExited: (code, status) => {
            root.channel = null;
            root.updateParticipants([]);
            if (root.parked)
                return;
            if (root.restartAttempts >= root.maxRestartAttempts) {
                root.status = "stopped";
                root.errorMessage = "Discord bridge stopped after repeated failures";
                return;
            }
            root.restartAttempts++;
            root.status = "restarting";
            restartTimer.interval = Math.min(30000, 1000 * Math.pow(2, root.restartAttempts - 1));
            restartTimer.restart();
        }
    }
}
