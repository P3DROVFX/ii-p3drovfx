import qs
import qs.modules.common
import QtQuick
import Quickshell

Scope {
    id: root

    LazyLoader {
        id: islandLoader
        active: Config.ready && (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar)

        component: DynamicIslandPanel {}
    }
}
