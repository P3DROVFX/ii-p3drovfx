import QtQuick
import Quickshell

import qs.modules.common

/// There is one native toplevel, on Hyprland's focused monitor/workspace when opened.
Scope {
    Loader {
        active: Config.ready
        sourceComponent: TabletAppWindow {}
    }
}
