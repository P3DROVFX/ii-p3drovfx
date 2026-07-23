/*
 * end4-pC Discord Voice companion for Vencord
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import definePlugin, { PluginNative } from "@utils/types";
import { findByPropsLazy } from "@webpack";
import { ChannelRTCStore, ChannelStore, GuildMemberStore, SelectedChannelStore, UserStore, VoiceStateStore } from "@webpack/common";

const Native = VencordNative.pluginHelpers.End4DiscordVoice as PluginNative<typeof import("./native")>;
const AudioActions = findByPropsLazy("toggleSelfMute", "toggleSelfDeaf");

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
        speaking: Boolean(state.speaking)
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
        user: currentUser ? {
            id: currentUser.id,
            username: currentUser.username,
            avatar: currentUser.avatar || ""
        } : null,
        channel: channel ? { id: channel.id, name: channel.name || "Voice channel", guild_id: channel.guild_id || "" } : null,
        users,
        mute: Boolean(ownState?.mute || ownState?.selfMute),
        deaf: Boolean(ownState?.deaf || ownState?.selfDeaf)
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
    name: "End4DiscordVoice",
    description: "Shares Vesktop voice state with the end4-pC Quickshell plugin",
    authors: [{ name: "xephy", id: 0n }],
    enabledByDefault: true,

    flux: {
        VOICE_STATE_UPDATES() { void publish(); },
        AUDIO_TOGGLE_SELF_MUTE() { void publish(); },
        AUDIO_TOGGLE_SELF_DEAF() { void publish(); },
        SPEAKING() { void publish(); },
        STOP_SPEAKING() { void publish(); }
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
