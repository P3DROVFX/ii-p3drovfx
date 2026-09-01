import QtQuick
import Quickshell

import qs.modules.common

/**
 * The tablet family's app drawer: every installed app in one searchable grid.
 *
 * This replaces the ii launcher for this family. It also claims the bottom edge, so a swipe
 * up from the base opens it — the gesture Android uses, registered through
 * TouchGestureDragRegistry so the shared gesture service stays family-agnostic.
 */
Scope {
    id: root

    /// Host for the shell's tool panels. Injected by the composition root because the
    /// panels live in the ii family and modules/tablet may not import them.
    property Component toolHostComponent: null

    /// Long-pressed an app in the grid. The drawer does not know what a home screen is, so
    /// the composition root connects this to whatever should receive it.
    signal appHeld(string appId)

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready
                sourceComponent: TabletAppDrawerWindow {
                    screen: screenScope.modelData
                    contentComponent: drawerContent
                    onAppHeld: appId => root.appHeld(appId)
                }
            }

            Component {
                id: drawerContent
                TabletAppDrawerContent {
                    toolHostComponent: root.toolHostComponent
                }
            }
        }
    }

    TabletAppDrawerDragHandler {}
}
