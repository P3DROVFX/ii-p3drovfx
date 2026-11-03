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
    // "PUSH_TO_TALK" | "VOICE_ACTIVITY", or "" while the backend has not said
    // (an old companion build never does, which hides the switch).
    property string inputMode: ""
    property string pttShortcut: ""
    readonly property bool pushToTalk: inputMode === "PUSH_TO_TALK"
    readonly property bool supportsInputMode: inputMode !== ""
    // The companion announces what it can do; Discord's own RPC can do all of it.
    property var backendFeatures: []
    readonly property bool supportsUserVoice: backend === "discord"
        || backendFeatures.indexOf("userVoice") !== -1
    // Installed and running, but built before per-user volume and the mode switch.
    readonly property bool companionOutdated: backend === "vencord"
        && backendFeatures.indexOf("userVoice") === -1
    readonly property string selfId: String(currentUser?.id ?? "")
    readonly property bool selfSpeaking: selfId !== ""
        && participants.some(user => String(user?.id ?? "") === selfId && user?.speaking === true)

    /**
     * Join/leave toasts. Kept here rather than in a view so every surface that
     * shows them (overlay widget, pinned or not) agrees on what is on screen, and
     * so the diff is taken once per bridge frame. Entries age out on `noticeClock`;
     * `leaving` gives the view a beat to animate out before the row is removed.
     */
    readonly property alias noticeModel: noticesModel
    readonly property int noticeLifetime: 4000
    readonly property int messageNoticeLifetime: 7000
    readonly property int noticeExitDuration: 260
    readonly property int maxNotices: 4
    property string _noticeChannelId: ""
    property int _noticeSerial: 0
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

    ListModel {
        id: noticesModel
    }

    // Every row carries every role: a ListModel fixes its roles on the first
    // append, so a join notice first would otherwise drop a message's text.
    function pushNotice(kind, user, context, text) {
        const name = user?.nick || user?.username || "Someone";
        const message = kind === "dm" || kind === "mention" || kind === "message";
        noticesModel.append({
            key: ++_noticeSerial, kind: kind, userId: String(user?.id ?? ""),
            name: name, avatar: avatarUrl(user, 64), born: Date.now(), leaving: false,
            context: String(context ?? ""), text: String(text ?? ""),
            lifetime: message ? messageNoticeLifetime : noticeLifetime
        });
        while (noticesModel.count > maxNotices)
            noticesModel.remove(0);
        noticeClock.start();
    }

    // Compares one bridge frame with the roster on screen. A frame for another
    // channel (or the first one after joining) only resets the baseline: the
    // whole room "joining" the moment you do is not news. Your own entry never
    // produces a notice.
    function diffMembers(incoming, channelId) {
        const sameChannel = channelId !== "" && channelId === _noticeChannelId;
        _noticeChannelId = channelId;
        if (!sameChannel || !Config.options.overlay.discordVoice.joinLeaveNotices)
            return;
        const before = new Map(participants.map(user => [String(user?.id ?? ""), user]));
        const after = new Set();
        for (const user of incoming || []) {
            const id = String(user?.id ?? "");
            after.add(id);
            if (id && id !== selfId && !before.has(id))
                pushNotice("join", user);
        }
        for (const [id, user] of before)
            if (id && id !== selfId && !after.has(id))
                pushNotice("leave", user);
    }

    function clearNotices() {
        noticesModel.clear();
        noticeClock.stop();
    }

    // Volume uses Discord's slider scale: 0-200, 100 = unchanged. The roster is
    // patched right away so a released slider does not snap back to the old
    // value while the echo is in flight; drags are coalesced into one command
    // per frame-ish tick instead of one per pointer event.
    property var _pendingUserVoice: ({})
    function setUserVolume(userId, volume) { _queueUserVoice(userId, {volume: Math.round(volume)}); }
    function setUserLocalMute(userId, value) { _queueUserVoice(userId, {mute: value === true}); }
    function _queueUserVoice(userId, change) {
        const id = String(userId ?? "");
        if (!id || id === selfId) return;
        const pending = Object.assign({}, _pendingUserVoice);
        pending[id] = Object.assign({}, pending[id] || {}, change);
        _pendingUserVoice = pending;
        _patchParticipant(id, change.volume !== undefined ? {volume: change.volume} : {localMute: change.mute});
        if (!userVoiceFlush.running) userVoiceFlush.start();
    }
    function _patchParticipant(id, fields) {
        const next = participants.map(user => String(user?.id ?? "") === id
            ? Object.assign({}, user, fields) : user);
        updateParticipants(next);
    }
    function setInputMode(mode) {
        if (mode !== "PUSH_TO_TALK" && mode !== "VOICE_ACTIVITY") return;
        inputMode = mode;
        send({cmd: "set_input_mode", mode: mode});
    }
    function togglePushToTalk() { setInputMode(pushToTalk ? "VOICE_ACTIVITY" : "PUSH_TO_TALK"); }

    Timer {
        id: userVoiceFlush
        interval: 60
        onTriggered: {
            const pending = root._pendingUserVoice;
            root._pendingUserVoice = ({});
            for (const id of Object.keys(pending))
                root.send(Object.assign({cmd: "set_user_voice", user_id: id}, pending[id]));
        }
    }

    Timer {
        id: noticeClock
        interval: 250
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (let index = noticesModel.count - 1; index >= 0; --index) {
                const entry = noticesModel.get(index);
                const age = now - entry.born;
                if (age >= entry.lifetime + root.noticeExitDuration)
                    noticesModel.remove(index);
                else if (age >= entry.lifetime && !entry.leaving)
                    noticesModel.setProperty(index, "leaving", true);
            }
            if (noticesModel.count === 0)
                stop();
        }
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
        case "backend":
            backend = message.backend || "";
            backendFeatures = Array.isArray(message.features) ? message.features : [];
            break;
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
            diffMembers(message.users, String(message.channel?.id ?? ""));
            if (!message.channel) clearNotices();
            channel = message.channel || null;
            updateParticipants(message.users);
            break;
        case "voice_state":
            diffMembers(message.users, String(channel?.id ?? ""));
            updateParticipants(message.users);
            break;
        // DMs and mentions, Vesktop companion only (Discord's RPC would need
        // the rpc.notifications.read scope, which the StreamKit client lacks).
        case "message_notice":
            if (Config.options.overlay.discordVoice.messageNotices)
                pushNotice(message.kind, message.author, message.context,
                    Config.options.overlay.discordVoice.messagePreview ? message.text : "");
            break;
        case "voice_settings":
            muted = message.mute === true;
            deafened = message.deaf === true;
            if (message.mode !== undefined) inputMode = String(message.mode || "");
            if (message.shortcut !== undefined) pttShortcut = String(message.shortcut || "");
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
        case "disconnected":
            status = "disconnected"; backend = ""; backendFeatures = []; inputMode = "";
            channel = null; _noticeChannelId = ""; clearNotices(); updateParticipants([]);
            reconnectTimer.restart();
            break;
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
            root._noticeChannelId = "";
            root.clearNotices();
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
