import qs
import qs.modules.common
import qs.modules.ii.dynamicIsland.core
import QtQuick
import Quickshell

Scope {
    id: root

    LazyLoader {
        id: islandLoader
        // One place decides whether the island exists; see IslandPolicy for why.
        active: IslandPolicy.enabled

        component: DynamicIslandPanel {}
    }
}
