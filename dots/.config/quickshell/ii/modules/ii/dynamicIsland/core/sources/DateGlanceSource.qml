pragma ComponentBehavior: Bound

import QtQuick

/**
 * Today's date, glanced at beside the clock.
 *
 * A state with nothing to wait for: it is there for as long as the user keeps it on.
 * The text is the shell's own date format (Settings > Language & time), drawn by the
 * resting face from `DateTime`, so the day rolls over by itself at midnight.
 */
ContinuousSource {
    id: source

    activityId: "date"

    condition: true
}
