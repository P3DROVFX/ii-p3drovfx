import qs
import qs.modules.common
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.dynamicIsland.styles.notch
import QtQuick
import Quickshell

Scope {
    id: root

    LazyLoader {
        id: islandLoader
        // One place decides whether the island exists; see IslandPolicy for why.
        active: IslandPolicy.enabled

        // The engine-driven notch is being brought to parity with the panel it replaces,
        // so both exist for now and the flag chooses. It flips to the new surface once
        // search, OSD and the overview are ported, and the panel is deleted with it.
        component: IslandPolicy.useEngineNotch ? engineNotch : legacyPanel
    }

    Component {
        id: legacyPanel
        DynamicIslandPanel {}
    }

    Component {
        id: engineNotch
        NotchIsland {}
    }
}
