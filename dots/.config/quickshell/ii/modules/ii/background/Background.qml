pragma ComponentBehavior: Bound

import qs
import Quickshell
import qs.modules.ii.background.widgets
import qs.modules.ii.background.compositor

Scope {
    id: backgroundScope

    WidgetStateManager {
        id: widgetState
    }

    readonly property alias widgetSyncVersion: widgetState.syncVersion
    readonly property alias widgetStateManager: widgetState

    Variants {
        id: root
        model: Quickshell.screens

        BackgroundRoot {
            widgetStateManager: widgetState
        }
    }

    Variants {
        id: widgetsVariant
        model: Quickshell.screens

        BackgroundWidgetsWindow {
            widgetStateManager: widgetState
        }
    }

    Variants {
        id: blurOverlayVariant
        model: Quickshell.screens

        BlurOverlayWindow {}
    }
}
