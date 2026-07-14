import qs
import qs.modules.common
import QtQuick
import Quickshell

Scope {
    id: root

    Component.onCompleted: {
        console.log("[DynamicIsland] Scope completed - Config.ready:", Config.ready, "floatingNotch.enable:", Config.options.bar.floatingNotch.enable);
    }

    LazyLoader {
        id: islandLoader
        active: Config.ready && Config.options.bar.floatingNotch.enable

        Component.onCompleted: {
            console.log("[DynamicIsland] Loader active:", active, "Config.ready:", Config.ready, "floatingNotch.enable:", Config.options.bar.floatingNotch.enable);
        }

        component: DynamicIslandPanel {}
    }
}
