pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Something is playing.
 *
 * Browsers register a player the moment a page *could* play audio, with no title and an
 * unknown artist, which is how the island used to end up showing an empty media pill on
 * every tab. A player only counts once it names a track.
 */
ContinuousSource {
    id: source

    activityId: "media"

    condition: {
        if (MprisController.activePlayer === null)
            return false;
        const track = MprisController.activeTrack;
        const title = (track && track.title) ? track.title : "";
        const artist = (track && track.artist) ? track.artist : "";
        if ((title === "" || title === "No title") && (artist === "" || artist === "Unknown Artist"))
            return false;
        return true;
    }

    // A track change is an accent on an activity that is already present, not a new
    // arrival: the presentation crossfades its art and rewinds its ring, and the island
    // itself does not move.
    /**
     * Starting playback is an event even though the activity was already present: a
     * paused track keeps the source active, and an auto-hiding island still has to show
     * the moment the user presses play.
     */
    readonly property bool playing: MprisController.activePlayer ? MprisController.activePlayer.isPlaying : false
    onPlayingChanged: {
        if (source.playing && source.active)
            source.revision += 1;
    }

    property Connections _mpris: Connections {
        target: MprisController
        function onTrackChanged() {
            if (source.active)
                source.revision += 1;
        }
    }
}
