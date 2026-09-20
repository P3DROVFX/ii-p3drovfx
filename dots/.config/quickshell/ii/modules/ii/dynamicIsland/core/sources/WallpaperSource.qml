pragma ComponentBehavior: Bound

import QtQuick
import qs

/**
 * The wallpaper picker is open and the island draws it.
 *
 * The same shape as SearchSource, for the same reason: `GlobalStates.wallpaperSelectorOpen`
 * is already the shell-wide answer to "is the picker open?", and it has to stay the
 * answer. Who *draws* it is the second question, and IslandPolicy owns that; a standalone
 * WallpaperSelector and an island both drawing the picker is the duplicate-surface bug.
 */
ContinuousSource {
    id: source

    activityId: "wallpaper"
    condition: GlobalStates.islandOwnsWallpaper && GlobalStates.wallpaperSelectorOpen
}
