pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Weather the island may glance at.
 *
 * True once the service has real data: `Weather.data` starts as a placeholder
 * (lastRefresh "00:00") and only the fetch overwrites it, so showing before that
 * would advertise a fake 0°C. Deliberately *not* gated on `bar.weather.enable`:
 * that switch belongs to the bar's widget, and the island's own toggle is the
 * only gate here (IslandSource.allowed). The first fetch runs unconditionally at
 * service start; while the glance is on show this source keeps it fresh on the
 * service's own interval, which is what the bar's gated timer would have done.
 */
ContinuousSource {
    id: source

    activityId: "weather"

    condition: Weather.data?.lastRefresh !== undefined
        && Weather.data.lastRefresh !== "00:00"

    // A QtObject has no default property: the timer hangs off a property, the way
    // BatterySource hangs its Connections.
    property Timer _refetch: Timer {
        interval: Weather.fetchInterval
        running: source.active
        repeat: true
        // Not forced: getData rate-limits itself, so an island left open for
        // weeks cannot turn into a polling loop against the API.
        onTriggered: Weather.getData(false)
    }
}
