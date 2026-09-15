pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland

QtObject {
    required property var screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property bool active: monitor !== null && Hyprland.workspaces.values.some(ws =>
        ws.active && ws.monitor?.name === monitor.name && ws.toplevels.values.some(t => t.wayland?.fullscreen))
}
