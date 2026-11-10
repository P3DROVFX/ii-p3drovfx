pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Not an alias onto the inhibitor's own enabled: the Wayland object has to be held back
    // until its surface is up, so the two can't be the same flag. See _surfaceReady below.
    property bool inhibit: false

    // Epoch ms at which a timed session ends; 0 means "indefinite" (the classic behaviour).
    // Must be `real` — epoch ms is far past the range of QML's 32-bit int.
    property real expiresAt: 0
    readonly property bool timed: root.inhibit && root.expiresAt > 0
    // Recomputed from the wall clock rather than decremented: a Timer doesn't tick through
    // suspend, so anything counted down in software would be wrong after a resume.
    property real remainingMs: 0

    readonly property string _sessionId: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""

    // "never" | "session" | "always" — see Config.options.idle.persistInhibit
    readonly property string persistScope: (Config.options && Config.options.idle && Config.options.idle.persistInhibit) ? Config.options.idle.persistInhibit : "session"

    readonly property bool notifyOnExpiry: Config.options?.idle?.notifyOnExpiry ?? true
    readonly property int warnLeadSec: Config.options?.idle?.warnLeadSec ?? 60
    readonly property int extendMinutes: Config.options?.idle?.extendMinutes ?? 15
    // JsonAdapter hands back a QML list, not a JS array — normalize before anything maps over it
    // Sliced as well as capped on write: the dialog keeps every chip on one row, so a longer
    // list left over from an older config would overflow it.
    readonly property var quickDurations: Array.from(Config.options?.idle?.quickDurations ?? []).slice(0, root.maxRecentDurations)
    // The chip row is a recents list, maintained by _recordDuration() rather than edited by hand
    readonly property int maxRecentDurations: 3
    readonly property var defaultDurations: [15, 30, 60]

    // Latched so the pre-expiry warning fires once per timed session
    property bool _warned: false

    // The preset this session was started from, in minutes. Cleared once the session is
    // extended, since the remaining time no longer matches the preset it came from.
    property real sessionMinutes: 0

    function formatMinutes(minutes) {
        if (minutes <= 0) return Translation.tr("Indefinite");
        if (minutes < 60) return Translation.tr("%1 min").arg(Math.round(minutes));
        const hours = Math.floor(minutes / 60);
        const mins = Math.round(minutes % 60);
        return mins > 0 ? Translation.tr("%1 h %2 min").arg(hours).arg(mins) : Translation.tr("%1 h").arg(hours);
    }

    readonly property string remainingText: {
        if (!root.timed || root.remainingMs <= 0) return "";
        const sec = Math.ceil(root.remainingMs / 1000);
        if (sec < 60) return Translation.tr("%1 s").arg(sec);
        // Under ten minutes the seconds are what's actually being watched, and a
        // minutes-only readout that sits still for a whole minute reads as frozen.
        // Seconds are zero-padded so the label doesn't jitter as 10 s ticks down to 9 s.
        if (sec < 600) {
            const wholeMin = Math.floor(sec / 60);
            const restSec = sec % 60;
            if (restSec === 0) return Translation.tr("%1 min").arg(wholeMin);
            return Translation.tr("%1 min %2 s").arg(wholeMin).arg(String(restSec).padStart(2, "0"));
        }
        const min = Math.ceil(sec / 60);
        if (min < 60) return Translation.tr("%1 min").arg(min);
        const hours = Math.floor(min / 60);
        const mins = min % 60;
        return mins > 0 ? Translation.tr("%1 h %2 min").arg(hours).arg(mins) : Translation.tr("%1 h").arg(hours);
    }

    Timer {
        id: restoreTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!Persistent.ready || !Config.ready) return;
            if (root.persistScope === "never") {
                root._clear();
                return;
            }
            const storedId = Persistent.states.idle.sessionId || "";
            if (root.persistScope === "session" && storedId !== root._sessionId) {
                root._clear();
                return;
            }
            // The deadline is absolute, so one that elapsed while the shell was down stays elapsed
            const storedExpiry = Persistent.states.idle.expiresAt ?? 0;
            if (storedExpiry > 0 && storedExpiry <= Date.now()) {
                root._clear();
                return;
            }
            root.expiresAt = storedExpiry;
            root.sessionMinutes = Persistent.states.idle.durationMinutes ?? 0;
            root._warned = false;
            root.inhibit = Persistent.states.idle.inhibit ?? false;
            root._tick();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() { restoreTimer.restart() }
    }

    Connections {
        target: Config
        function onReadyChanged() { restoreTimer.restart() }
    }

    // Both singletons may already be ready by the time this one loads
    Component.onCompleted: restoreTimer.restart()

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: root.timed
        onTriggered: root._tick()
    }

    // Plain on/off, always indefinite. Timed sessions go through inhibitFor()/extendBy().
    function toggleInhibit(active = null) {
        const next = active !== null ? active : !root.inhibit
        root.expiresAt = 0
        root.remainingMs = 0
        root.sessionMinutes = 0
        root._warned = false
        root.inhibit = next
        root._persist()
    }

    // minutes <= 0 means indefinite
    function inhibitFor(minutes) {
        if (minutes <= 0) {
            root.toggleInhibit(true)
            return;
        }
        root.expiresAt = Date.now() + minutes * 60000
        root.sessionMinutes = minutes
        root._warned = false
        root.inhibit = true
        root._recordDuration(minutes)
        root._persist()
        root._tick()
    }

    // Coarser the longer the duration, so the stepper stays quick to drive at either end
    function _stepSizeFor(minutes) {
        if (minutes < 60) return 5;
        if (minutes < 240) return 15;
        return 30;
    }

    // Snaps to the step grid, so a value restored from an odd custom duration lands cleanly
    function stepMinutes(minutes, direction) {
        // Sizing the step off the value being left rather than the one being entered keeps
        // stepping down across a boundary the exact inverse of stepping back up
        const step = root._stepSizeFor(direction > 0 ? minutes : minutes - 1)
        const next = Math.round((minutes + direction * step) / step) * step
        return Math.max(5, Math.min(1440, next));
    }

    // Durations are a most-recently-added list, not a hand-edited one: a duration that
    // isn't already offered becomes a chip, pushing the oldest one off the end. Ones that
    // are already there keep their position, so chips don't shuffle under the pointer.
    function _recordDuration(minutes) {
        if (minutes <= 0) return;
        const current = root.quickDurations
        if (current.indexOf(minutes) !== -1) return;
        Config.options.idle.quickDurations = [minutes].concat(current).slice(0, root.maxRecentDurations)
    }

    function resetDurations() {
        Config.options.idle.quickDurations = root.defaultDurations
    }

    // Pushes the deadline out from whichever is later: now, or the current deadline.
    // Extending an indefinite session would shorten it, so that case is ignored.
    function extendBy(minutes) {
        if (minutes <= 0) return;
        if (root.inhibit && root.expiresAt <= 0) return;
        root.expiresAt = Math.max(Date.now(), root.expiresAt) + minutes * 60000
        root.sessionMinutes = 0
        root._warned = false
        root.inhibit = true
        root._persist()
        root._tick()
    }

    function _tick() {
        if (!root.timed) {
            root.remainingMs = 0
            return;
        }
        const left = root.expiresAt - Date.now()
        root.remainingMs = Math.max(0, left)
        if (left <= 0) {
            root._expire()
            return;
        }
        if (!root._warned && root.notifyOnExpiry && root.warnLeadSec > 0 && left <= root.warnLeadSec * 1000) {
            root._warned = true
            root._notifyExpiring()
        }
    }

    function _expire() {
        const shouldNotify = root.notifyOnExpiry
        root.toggleInhibit(false)
        if (shouldNotify) {
            Quickshell.execDetached(["notify-send", "-a", "Keep awake", "-i", "bedtime", "-t", "5000", "--hint=boolean:suppress-sound:true", Translation.tr("Keep awake ended"), Translation.tr("The system can sleep again.")])
        }
    }

    function _notifyExpiring() {
        // Tagged with a hint rather than the icon name: notify-send's -i doesn't survive as
        // appIcon here, so the shell can't tell this notification apart by icon.
        Quickshell.execDetached(["notify-send", "-a", "Keep awake", "-i", "hourglass_bottom", "-t", String(Math.max(5000, root.warnLeadSec * 1000)), "--hint=boolean:suppress-sound:true", "--hint=string:x-qs-notif:keepawake-warn", Translation.tr("Keep awake ending"), Translation.tr("Sleep resumes in %1.").arg(root.remainingText)])
    }

    // Reset without persisting — used by the startup restore path, which must not write back
    function _clear() {
        root.expiresAt = 0
        root.remainingMs = 0
        root.sessionMinutes = 0
        root._warned = false
        root.inhibit = false
    }

    function _persist() {
        if (!Persistent.ready) return;
        Persistent.states.idle.inhibit = root.inhibit
        Persistent.states.idle.expiresAt = root.expiresAt
        Persistent.states.idle.durationMinutes = root.sessionMinutes
        Persistent.states.idle.sessionId = root._sessionId
    }

    // Hyprland settles an idle inhibitor's fate when it is created: an inhibitor whose surface
    // hasn't committed a buffer yet fails its aliveAndVisible() check and is dropped, and it is
    // only ever reconsidered on window map/unmap, fullscreen or focus changes — a layer surface
    // becoming mapped doesn't trigger that. This window's surface isn't up yet when a Keep awake
    // restored at startup flips inhibit on, so the toggle read as on while the system slept
    // anyway, until some unrelated window happened to map. Holding the inhibitor back and then
    // re-asserting it makes that check run again once the surface is really there.
    property bool _surfaceReady: false
    property int _reassertsLeft: 4

    Timer {
        id: reassertTimer
        interval: 2000
        repeat: true
        running: root._reassertsLeft > 0
        onTriggered: {
            root._reassertsLeft--
            // Recreating the object is what makes Hyprland look again; Wayland keeps request
            // order, so it processes the destroy and then the create.
            root._surfaceReady = false
            Qt.callLater(() => root._surfaceReady = true)
        }
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.inhibit && root._surfaceReady
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Hyprland only counts a layer surface's inhibitor while its alpha is non-zero, and
            // re-evaluates that only on window map/unmap and fullscreen changes. A fullscreen
            // window fades the Top layer to 0, so leaving fullscreen re-checked a still-faded
            // surface and dropped Keep awake until the next window event. Overlay isn't faded.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:idleInhibitor"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
