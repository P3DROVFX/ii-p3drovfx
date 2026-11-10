pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Music recognition: listening, then what it heard.
 *
 * Listening is live for as long as SongRec runs (its own timeout caps it at 30 s by
 * default) and can be cancelled from the island. The result - or the reason there is
 * none - then takes the centre for a while, long enough to reach for Open.
 */
ContinuousSource {
    id: source

    activityId: "songRec"

    /** "listening", "result", "failed" or "". */
    readonly property string phase: SongRec.running ? "listening" : source.outcome
    property string outcome: ""
    property string failureMessage: ""

    condition: source.phase !== ""
    payload: source.phase
    onPhaseChanged: if (source.active) source.revision += 1

    readonly property bool announcing: source.outcome !== "" && !SongRec.running
    readonly property string tierOverride: source.announcing ? "transient" : ""

    property Connections _songRec: Connections {
        target: SongRec
        function onTrackRecognized() {
            source._show("result");
        }
        function onRecognitionFailed(message) {
            source.failureMessage = message;
            source._show("failed");
        }
        function onRunningChanged() {
            // A new listen replaces whatever the last one said.
            if (SongRec.running) {
                source._outcomeTimer.stop();
                source.outcome = "";
            }
        }
    }

    function _show(outcome) {
        if (!source.allowed)
            return;
        source.outcome = outcome;
        source._outcomeTimer.interval = outcome === "result" ? 10000 : 4000;
        source._outcomeTimer.restart();
    }

    function dismiss() {
        source._outcomeTimer.stop();
        source.outcome = "";
    }

    property Timer _outcomeTimer: Timer {
        onTriggered: {
            if (source.hovered)
                source._outcomeTimer.restart();
            else
                source.outcome = "";
        }
    }
}
