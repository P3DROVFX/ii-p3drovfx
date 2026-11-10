/*
 * Quickshell/II Discord Voice companion for Vencord
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import definePlugin, { PluginNative } from "@utils/types";
import { findByCodeLazy, findByPropsLazy } from "@webpack";
import { ChannelRTCStore, ChannelStore, FluxDispatcher, GuildMemberStore, MediaEngineStore, SelectedChannelStore, UserStore, VoiceStateStore } from "@webpack/common";

const Native = VencordNative.pluginHelpers.iiDiscordVoice as PluginNative<typeof import("./native")>;
const AudioActions = findByPropsLazy("toggleSelfMute", "toggleSelfDeaf");
// Discord's own "should this message notify me" (the same lookup xsOverlay
// uses): honours muted servers/channels, @silent, and the mention settings.
const discordShouldNotify = findByCodeLazy(".SUPPRESS_NOTIFICATIONS))return!1");
const DM = 1, GROUP_DM = 3;
const PREVIEW_LIMIT = 160;

// What this build of the companion can do. The shell offers per-user volume
// and the input-mode switch only when the running plugin announces them, so an
// older install keeps working and the overlay can ask for an update instead.
const FEATURES = ["userVoice", "inputMode", "messageNotices"];

// Discord stores local volume as amplitude; its own slider shows a perceptual
// 0-200 scale (100 = unchanged). The shell speaks the slider's scale.
function amplitudeToPerceptual(amplitude: number) {
    if (!(amplitude > 0)) return 0;
    const db = 20 * Math.log10(amplitude / 100);
    return Math.max(0, Math.min(200, db > 0 ? db / 6 * 100 + 100 : (50 + db) / 50 * 100));
}

function perceptualToAmplitude(perceptual: number) {
    if (!(perceptual > 0)) return 0;
    const db = perceptual > 100 ? (perceptual - 100) / 100 * 6 : perceptual / 100 * 50 - 50;
    return 100 * Math.pow(10, db / 20);
}

function readable(message: any, guildId?: string) {
    let text = String(message.content || "")
        .replace(/<@!?(\d{17,20})>/g, (_, id) => {
            const user = UserStore.getUser(id);
            const nick = guildId && user ? GuildMemberStore.getNick(guildId, id) : null;
            return `@${nick || user?.globalName || user?.username || "user"}`;
        })
        .replace(/<@&\d{17,20}>/g, "@role")
        .replace(/<#(\d{17,20})>/g, (_, id) => `#${ChannelStore.getChannel(id)?.name || "channel"}`)
        .replace(/<a?:(\w+):\d{17,20}>/g, ":$1:")
        .replace(/\s+/g, " ")
        .trim();
    if (!text) {
        if (message.attachments?.length) text = "[attachment]";
        else if (message.sticker_items?.length) text = "[sticker]";
        else if (message.embeds?.length) text = "[embed]";
    }
    return text.length > PREVIEW_LIMIT ? text.slice(0, PREVIEW_LIMIT - 1) + "…" : text;
}

function messageNotice(message: any) {
    const self = UserStore.getCurrentUser();
    if (!message?.author || !self || message.author.id === self.id) return;
    const channelId = message.channel_id;
    const channel = ChannelStore.getChannel(channelId);
    if (!channel) return;
    // Reading that channel right now: Discord would not toast either.
    if (document.hasFocus() && SelectedChannelStore.getChannelId() === channelId) return;
    let notify: boolean;
    try {
        notify = Boolean(discordShouldNotify(message, channelId));
    } catch {
        notify = channel.type === DM || channel.type === GROUP_DM
            || (message.mentions || []).some((user: any) => (user?.id ?? user) === self.id);
    }
    if (!notify) return;
    const direct = channel.type === DM || channel.type === GROUP_DM;
    const mentioned = message.mention_everyone
        || (message.mentions || []).some((user: any) => (user?.id ?? user) === self.id)
        || (message.mention_roles || []).length > 0;
    const author = message.author;
    void Native.publishEvent(JSON.stringify({
        kind: direct ? "dm" : (mentioned ? "mention" : "message"),
        author: {
            id: author.id,
            username: author.username,
            nick: (channel.guild_id && GuildMemberStore.getNick(channel.guild_id, author.id)) || author.globalName || author.global_name || author.username,
            avatar: author.avatar || ""
        },
        context: direct
            ? (channel.type === GROUP_DM ? (channel.name || "Group DM") : "")
            : `#${channel.name || "channel"}`,
        text: readable(message, channel.guild_id)
    }));
}

let timer: ReturnType<typeof setInterval> | undefined;
let publishing = false;
let pending = false;
let running = false;

function participant(userId: string, state: any, guildId?: string) {
    const user = UserStore.getUser(userId);
    if (!user) return null;
    return {
        id: user.id,
        username: user.username,
        nick: (guildId && GuildMemberStore.getNick(guildId, user.id)) || user.globalName || user.username,
        avatar: user.avatar || "",
        mute: Boolean(state.mute || state.selfMute),
        deaf: Boolean(state.deaf || state.selfDeaf),
        speaking: Boolean(state.speaking),
        volume: Math.round(amplitudeToPerceptual(MediaEngineStore.getLocalVolume(user.id))),
        localMute: Boolean(MediaEngineStore.isLocalMute(user.id))
    };
}

function snapshot() {
    const channelId = SelectedChannelStore.getVoiceChannelId();
    const channel = channelId ? ChannelStore.getChannel(channelId) : null;
    const states = channelId ? VoiceStateStore.getVoiceStatesForChannel(channelId) || {} : {};
    const speakingIds = new Set(channelId
        ? ChannelRTCStore.getSpeakingParticipants(channelId).map(participant => participant.user.id)
        : []);
    const users = Object.entries(states)
        .map(([userId, state]) => {
            const normalized = { ...(state as object), speaking: speakingIds.has(userId) };
            return participant(userId, normalized, channel?.guild_id);
        })
        .filter(Boolean);
    const currentUser = UserStore.getCurrentUser();
    const ownState = currentUser ? VoiceStateStore.getVoiceStateForUser(currentUser.id) : null;
    return {
        version: 1,
        backend: "vencord",
        timestamp: Date.now(),
        features: FEATURES,
        user: currentUser ? {
            id: currentUser.id,
            username: currentUser.username,
            avatar: currentUser.avatar || ""
        } : null,
        channel: channel ? { id: channel.id, name: channel.name || "Voice channel", guild_id: channel.guild_id || "" } : null,
        users,
        mute: Boolean(ownState?.mute || ownState?.selfMute),
        deaf: Boolean(ownState?.deaf || ownState?.selfDeaf),
        inputMode: MediaEngineStore.getMode() || ""
    };
}

function applyCommand(raw: string) {
    if (!raw) return;
    try {
        const command = JSON.parse(raw);
        if (command.type !== "command") return;
        const state = snapshot();
        if (typeof command.mute === "boolean" && command.mute !== state.mute)
            AudioActions.toggleSelfMute();
        if (typeof command.deaf === "boolean" && command.deaf !== state.deaf)
            AudioActions.toggleSelfDeaf();
        const userVoice = command.userVoice;
        if (userVoice && typeof userVoice.userId === "string" && userVoice.userId) {
            const { userId } = userVoice;
            if (typeof userVoice.volume === "number") {
                const volume = perceptualToAmplitude(Math.max(0, Math.min(200, userVoice.volume)));
                if (typeof AudioActions.setLocalVolume === "function")
                    AudioActions.setLocalVolume(userId, volume);
                else
                    FluxDispatcher.dispatch({ type: "AUDIO_SET_LOCAL_VOLUME", context: "default", userId, volume });
            }
            if (typeof userVoice.mute === "boolean" && userVoice.mute !== MediaEngineStore.isLocalMute(userId)) {
                if (typeof AudioActions.toggleLocalMute === "function")
                    AudioActions.toggleLocalMute(userId);
                else
                    FluxDispatcher.dispatch({ type: "AUDIO_TOGGLE_LOCAL_MUTE", context: "default", userId });
            }
        }
        if ((command.inputMode === "PUSH_TO_TALK" || command.inputMode === "VOICE_ACTIVITY")
                && command.inputMode !== MediaEngineStore.getMode()) {
            const options = MediaEngineStore.getModeOptions();
            if (typeof AudioActions.setMode === "function")
                AudioActions.setMode(command.inputMode, options);
            else
                FluxDispatcher.dispatch({ type: "AUDIO_SET_MODE", context: "default", mode: command.inputMode, options });
        }
    } catch { /* Ignore malformed or obsolete commands. */ }
}

async function commandLoop() {
    while (running) {
        const command = await Native.nextCommand();
        if (running) applyCommand(command);
    }
}

// Coalesces bursts of Flux events into one in-flight publish, but always
// re-publishes afterwards if anything arrived meanwhile. Dropping the trailing
// event outright would leave the shell showing stale mute state until the next
// heartbeat, five seconds later.
async function publish() {
    if (publishing) {
        pending = true;
        return;
    }
    publishing = true;
    try {
        do {
            pending = false;
            await Native.publishState(JSON.stringify(snapshot()));
        } while (pending);
    } finally {
        publishing = false;
        pending = false;
    }
}

export default definePlugin({
    name: "iiDiscordVoice",
    description: "Shares Vesktop voice state with Quickshell/II",
    authors: [{ name: "xephy", id: 0n }],
    enabledByDefault: true,

    flux: {
        VOICE_STATE_UPDATES() { void publish(); },
        AUDIO_TOGGLE_SELF_MUTE() { void publish(); },
        AUDIO_TOGGLE_SELF_DEAF() { void publish(); },
        AUDIO_SET_LOCAL_VOLUME() { void publish(); },
        AUDIO_TOGGLE_LOCAL_MUTE() { void publish(); },
        AUDIO_SET_MODE() { void publish(); },
        SPEAKING() { void publish(); },
        STOP_SPEAKING() { void publish(); },
        MESSAGE_CREATE({ message, optimistic }: { message: any; optimistic: boolean; }) {
            if (optimistic || !running) return;
            try { messageNotice(message); } catch { /* A notice must never break the plugin. */ }
        }
    },

    start() {
        running = true;
        void commandLoop();
        void publish();
        // Flux handlers carry state immediately. This low-frequency heartbeat
        // exists only to reconnect after Quickshell restarts and detect hangs.
        timer = setInterval(() => void publish(), 5000);
    },

    stop() {
        running = false;
        if (timer) clearInterval(timer);
        timer = undefined;
        void Native.disconnect();
    }
});
