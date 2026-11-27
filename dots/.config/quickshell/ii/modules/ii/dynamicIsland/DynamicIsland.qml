import qs
import qs.modules.common
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.dynamicIsland.styles.notch
import QtQuick
import Quickshell

Scope {
    id: root

    readonly property var panelWindow: islandLoader.item ? islandLoader.item.panelWindow : null

    LazyLoader {
        id: islandLoader
        // One place decides whether the island exists; see IslandPolicy for why.
        active: IslandPolicy.enabled

        component: NotchIsland {}
    }
}
