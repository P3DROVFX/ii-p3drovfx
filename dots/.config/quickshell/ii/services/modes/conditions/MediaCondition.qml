import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import ".."

/**
 * Something is playing (`playing: true`, default) or nothing is. `player`
 * narrows it to players whose name contains the text ("spotify").
 */
ModeCondition {
    id: root
    readonly property string player: String(root.params?.player ?? "").toLowerCase()
    readonly property bool wantPlaying: root.params?.playing !== false

    // Bumped whenever a player appears, leaves or changes state; the
    // players list itself does not signal per-player changes.
    property int revision: 0
    readonly property var playing: {
        root.revision;
        return Array.from(Mpris.players?.values ?? []).filter(p => p && p.isPlaying && root.matches(p));
    }

    function matches(p) {
        if (!root.player.length)
            return true;
        const text = `${p.identity ?? ""} ${p.desktopEntry ?? ""} ${p.dbusName ?? ""}`.toLowerCase();
        return text.indexOf(root.player) !== -1;
    }

    readonly property Instantiator trackers: Instantiator {
        model: Mpris.players
        delegate: QtObject {
            required property var modelData
            readonly property bool playing: modelData?.isPlaying ?? false
            onPlayingChanged: root.revision += 1
        }
        onObjectAdded: (index, object) => root.revision += 1
        onObjectRemoved: (index, object) => root.revision += 1
    }

    satisfied: root.wantPlaying ? root.playing.length > 0 : root.playing.length === 0
    reason: root.playing[0]?.identity ?? (root.wantPlaying ? "" : "nothing playing")
}
