import QtQuick
import Quickshell

import qs.modules.common

/// Per-screen host for the recents carousel.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready
                sourceComponent: TabletRecentsWindow {
                    screen: screenScope.modelData
                    contentComponent: recentsContent
                }
            }

            Component {
                id: recentsContent
                TabletRecentsContent {}
            }
        }
    }
}
