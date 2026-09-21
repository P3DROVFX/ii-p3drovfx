pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * A microphone, camera or screen share is in use.
 *
 * A state for as long as any sensor is held: it sits beside the clock as a dot and never
 * leaves for a bubble, because an indicator that can be hidden is not an indicator. The
 * probe behind it is the one the bar's privacy pill already runs, so this costs nothing
 * the shell was not already paying.
 *
 * A sensor *starting* is also news once: which app just took the camera is the whole
 * point of the indicator, and a dot does not say it. So a kind that was not held before
 * takes the centre for a moment, naming the app, and folds back into the dot. Kinds that
 * were already held when the shell came up (a reload mid-call) are not news.
 */
ContinuousSource {
    id: source

    activityId: "privacy"

    condition: Privacy.active
    payload: Privacy.activeKinds

    /** How long the "Firefox is using the camera" moment holds the centre. */
    readonly property int announceMs: 3000
    property bool announcing: false
    readonly property string tierOverride: source.announcing ? "transient" : ""

    /** The kind the announcement is about, for the face. */
    property string announcedKind: ""
    /** The apps holding it, joined for display. */
    readonly property string announcedApps: source.appsFor(source.announcedKind).join(", ")

    function appsFor(kind) {
        const names = [];
        if (kind === "")
            return names;
        for (const item of Privacy.activeItems) {
            const app = String(item.app ?? "");
            if (String(item.kind) === kind && app !== "" && names.indexOf(app) === -1)
                names.push(app);
        }
        return names;
    }

    /**
     * Captures the island already shows as their own activity - song recognition,
     * dictation, a screen recording. Announcing "songrec is using the microphone" over
     * the Listening card would replace the card with a sentence about it.
     */
    readonly property var shellCaptures: ["songrec", "voxtype", "wf-recorder", "gpu-screen-recorder",
        "wl-screenrec"]

    function isShellCapture(kind) {
        const apps = source.appsFor(kind);
        return apps.length > 0 && apps.every(app => source.shellCaptures.indexOf(app.toLowerCase()) !== -1);
    }

    // The kinds held at the last change, so only a newly taken one announces.
    property var _heldKinds: []
    /**
     * The probe's first report lists whatever was already held when the shell came up.
     * That is the state the shell woke into, not something that just happened, so it is
     * the baseline and never announced. A timer is not enough: the probe starts a poll
     * interval late, and after a reload later still. Its first report always arrives as
     * a change, even an empty one, because Privacy rebuilds the list on first output.
     */
    property bool _baselined: false

    Component.onCompleted: {
        // The bar's pill may have started the probe first: then its first report has
        // already been and gone, and what it said is the baseline.
        if (Privacy._lastSerialized !== "") {
            source._heldKinds = Array.from(Privacy.activeKinds ?? []);
            source._baselined = true;
        }
    }

    onPayloadChanged: {
        const kinds = Array.from(source.payload ?? []);
        const fresh = kinds.filter(kind => source._heldKinds.indexOf(kind) === -1);
        source._heldKinds = kinds;
        if (!source._baselined) {
            source._baselined = true;
            return;
        }
        if (fresh.length === 0 || !source.allowed || IslandPolicy.quietWindowActive)
            return;
        // Several at once (a video call takes both): announce the one in Privacy's own
        // order, which puts the camera first.
        const kind = fresh.find(candidate => !source.isShellCapture(candidate));
        if (kind === undefined)
            return;
        source.announcedKind = kind;
        source.revision += 1;
        source.announcing = true;
        source._announceTimer.restart();
    }

    onActiveChanged: {
        if (source.active)
            return;
        source._announceTimer.stop();
        source.announcing = false;
    }

    property Timer _announceTimer: Timer {
        interval: source.announceMs
        onTriggered: {
            // Reading it is not a reason to take it away.
            if (source.hovered)
                source._announceTimer.restart();
            else
                source.announcing = false;
        }
    }
}
