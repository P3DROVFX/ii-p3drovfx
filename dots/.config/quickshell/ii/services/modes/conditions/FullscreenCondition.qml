import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import ".."

/**
 * The focused window is fullscreen. Reuses the computation the automatic
 * fullscreen DND already does.
 */
ModeCondition {
    id: root
    satisfied: Notifications.focusedWindowFullscreen
    reason: root.satisfied ? (ToplevelManager.activeToplevel?.appId ?? "fullscreen") : ""
}
