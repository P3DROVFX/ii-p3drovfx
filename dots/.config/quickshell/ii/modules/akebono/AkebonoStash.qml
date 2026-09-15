pragma Singleton
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root
    readonly property string prefix: "special:desktop-min-"

    function nameFor(address) {
        return `${root.prefix}${address}`;
    }
    function isStashed(client) {
        return (client?.workspace?.name ?? "").startsWith(root.prefix);
    }
    function minimize(address) {
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${root.nameFor(address)}", follow = false, window = "address:${address}" })`);
    }
    function restore(address, workspaceId) {
        const ws = workspaceId ?? (Hyprland.focusedWorkspace?.id ?? 1);
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${ws}, follow = false, window = "address:${address}" })`);
    }
}
