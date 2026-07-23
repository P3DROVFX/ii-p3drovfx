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
        case "connected": status = "connected"; break;
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
        case "unavailable": status = "unavailable"; errorMessage = message.message || ""; break;
        // The companion is one of two backends. Its failure leaves Discord's
        // own RPC usable, so this reports the reason without moving `status`
        // into an authorization state the user cannot act on.
        case "companion_error": errorMessage = message.message || ""; break;
        case "disconnected": status = "disconnected"; backend = ""; channel = null; updateParticipants([]); break;
        case "error":
            status = "auth_required";
            errorMessage = message.message || "Discord RPC error";
            break;
        }
    }

    Component.onCompleted: start(false)

    Timer {
        id: restartTimer
        onTriggered: root.start(false)
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
