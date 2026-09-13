import QtQuick
import Quickshell

import qs.modules.common

/// Per-screen host for the tablet dock. See TabletDockWindow for what it is.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready
                sourceComponent: TabletDockWindow {
                    screen: screenScope.modelData
                }
            }
        }
    }
}
