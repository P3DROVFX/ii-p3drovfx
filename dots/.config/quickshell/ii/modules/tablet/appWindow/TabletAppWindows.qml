import QtQuick
import Quickshell

import qs.modules.common

/// Per-screen host for the app window. One is open at a time, on whichever screen it lands.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready
                sourceComponent: TabletAppWindow {
                    screen: screenScope.modelData
                }
            }
        }
    }
}
