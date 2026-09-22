pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * The system tray's programs, as an island activity.
 *
 * Present for as long as the tray holds at least one item the bar would show (the
 * pinned and unpinned sets, already filtered for passive items by the tray's own
 * smart filter). It never takes the island's centre: it is a bubble beside it, or a
 * glance next to the clock while bubbles are off — which is how the bar's tray reads
 * when it moves over. Presence is its only job; the presentations read TrayService
 * themselves, and the per-activity toggle is resolved by IslandSource.allowed.
 */
ContinuousSource {
    id: source

    activityId: "systemTray"

    condition: TrayService.pinnedItems.length + TrayService.unpinnedItems.length > 0
}
