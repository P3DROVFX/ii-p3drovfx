import QtQuick
import Quickshell

import qs.modules.common

/**
 * The floating bubble: one control that is always exactly where the user left it.
 *
 * Everything this shell can do is otherwise behind an edge gesture, a keybind or a surface
 * that has to be summoned first — and on a tablet held in two hands, edge gestures are the
 * least reachable thing on the screen, especially over a fullscreen application where they
 * compete with whatever the application does with its own edges. Android's chat heads and
 * iPadOS's AssistiveTouch both exist for the same reason, and both work the same way: a
 * small circle you drag wherever you want it, which opens a sheet of large targets.
 *
 * One per monitor, so the bubble is on the screen being used rather than on whichever one
 * the shell happens to consider primary.
 */
Scope {
    id: root

    readonly property var settings: Config.options?.tablet?.bubble

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready && (root.settings?.enable ?? true)
                sourceComponent: TabletFloatingBubbleWindow {
                    screen: screenScope.modelData
                }
            }
        }
    }
}
