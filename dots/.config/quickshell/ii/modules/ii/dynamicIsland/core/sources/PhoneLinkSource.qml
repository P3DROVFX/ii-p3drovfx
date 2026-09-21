pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.modules.ii.dynamicIsland.core

/**
 * The phone's camera or microphone is streaming into this computer.
 *
 * Both run in the background once started from the Phone tab - the camera as a webcam
 * other apps can open, the microphone as an input - and nothing on screen says so once
 * the sidebar closes. The privacy indicator does not either: it deliberately ignores
 * the relay itself, and only names an app once one opens the device.
 *
 * Read from the flags the phone services publish in GlobalStates, so the island never
 * constructs those services (and their dependency probes) for someone who has not.
 * Starting a stream is news once; one that was already running when the shell came up
 * is not.
 */
ContinuousSource {
    id: source

    activityId: "phoneLink"

    readonly property bool phoneEnabled: Config.ready && Config.options.policies.phone !== 0
    readonly property bool camera: source.phoneEnabled && GlobalStates.phoneCameraRunning
    readonly property bool microphone: source.phoneEnabled && GlobalStates.phoneMicRunning

    condition: source.camera || source.microphone
    /** The streams running, camera first: "camera", "microphone". */
    payload: [source.camera ? "camera" : "", source.microphone ? "microphone" : ""]
        .filter(kind => kind !== "")

    // ── A stream starting is news once ──────────────────────────────────────
    readonly property int announceMs: 3000
    property bool announcing: false
    readonly property string tierOverride: source.announcing ? "transient" : ""
    /** The stream the announcement is about. */
    property string announcedKind: ""

    property var _running: []

    Component.onCompleted: source._running = Array.from(source.payload ?? [])

    onPayloadChanged: {
        const kinds = Array.from(source.payload ?? []);
        const fresh = kinds.filter(kind => source._running.indexOf(kind) === -1);
        source._running = kinds;
        if (fresh.length === 0 || !source.allowed || IslandPolicy.quietWindowActive)
            return;
        source.announcedKind = fresh[0];
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
            if (source.hovered)
                source._announceTimer.restart();
            else
                source.announcing = false;
        }
    }
}
