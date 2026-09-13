import QtQuick
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * Time window on given weekdays. Re-evaluated off the shared SystemClock so a
 * laptop resumed at 07:10 leaves a 23:00–07:00 window within the first tick.
 * Either end may be "sunrise" / "sunset", taken from the weather service
 * (so they need the weather widget's location to have loaded).
 */
ModeCondition {
    id: root
    // `date` changes once a minute (or second while the lock screen is up);
    // the binding only emits satisfiedChanged on an actual flip.
    readonly property var now: DateTime.clock.date
    readonly property var sun: ({ sunrise: Weather.data?.sunrise ?? "", sunset: Weather.data?.sunset ?? "" })
    satisfied: root.params?.type === "schedule" && ModeSchema.scheduleSatisfied(root.params, root.now, root.sun)
    reason: root.params ? `${root.params.from}–${root.params.to}` : ""

    // Epoch ms at which the current window closes; 0 outside the window.
    readonly property real endsAt: root.satisfied ? ModeSchema.scheduleEndsAt(root.params, root.now, root.sun) : 0
}
