import QtQuick
import Quickshell

import qs.modules.common

/// Per-screen host for the home-screen icons, plus the workspace swipe handler.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready
                sourceComponent: TabletHomeIconsWindow {
                    screen: screenScope.modelData
                }
            }
        }
    }

    // Swiping across the wallpaper moves between workspaces, as between home screen pages.
    TabletWorkspaceDragHandler {}
}
