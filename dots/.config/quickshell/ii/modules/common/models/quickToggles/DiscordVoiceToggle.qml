import QtQuick
import qs
import qs.services
import qs.modules.common

/**
 * Your microphone in a Discord call: tap to mute, right-click to deafen.
 *
 * DiscordVoice is only read once a Discord client has had a window this session (see
 * GlobalStates.discordClientSeen): reading it starts its bridge, and a tile sitting in
 * the tray must not do that for someone who never runs Discord.
 */
QuickToggleModel {
    id: root

    readonly property bool armed: GlobalStates.discordClientSeen
    readonly property bool inCall: root.armed && DiscordVoice.inVoice
    readonly property bool muted: root.inCall && DiscordVoice.muted
    readonly property bool deafened: root.inCall && DiscordVoice.deafened

    name: Translation.tr("Discord")
    available: root.inCall
    toggled: root.inCall && !root.muted && !root.deafened
    icon: root.deafened ? "headset_off" : (root.muted ? "mic_off" : "headset_mic")
    statusText: {
        if (!root.inCall)
            return Translation.tr("Not in a call");
        if (root.deafened)
            return Translation.tr("Deafened");
        if (root.muted)
            return Translation.tr("Muted");
        return DiscordVoice.channel?.name ?? Translation.tr("In a call");
    }
    tooltipText: Translation.tr("Discord voice | Click to mute, right-click to deafen")

    mainAction: () => {
        if (root.inCall)
            DiscordVoice.setMuted(!DiscordVoice.muted);
    }
    altAction: () => {
        if (root.inCall)
            DiscordVoice.setDeafened(!DiscordVoice.deafened);
    }
}
