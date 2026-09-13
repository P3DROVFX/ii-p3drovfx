import QtQuick
import qs.services
import ".."

/**
 * Connected to a Discord voice channel (through the Vesktop / arRPC
 * bridge the sidebar widget uses). Without the bridge this never holds.
 */
ModeCondition {
    id: root
    satisfied: DiscordVoice.inVoice
    reason: DiscordVoice.channel?.name ?? ""
}
