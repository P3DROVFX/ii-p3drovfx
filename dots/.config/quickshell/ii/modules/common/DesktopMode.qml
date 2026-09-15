import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
import qs.services

Scope {
    id: root

    readonly property bool desired: Config.ready
        && Config.options.panelFamily === "akebono"
        && (Config.options.akebono?.desktop?.floating ?? true)

    readonly property string floatScript: Quickshell.shellPath("scripts/desktop/de-float.sh")

    function enable() {
        HyprlandConfig.set("general:layout", "floating");
        floatTimer.restart();
    }

    function disable() {
        floatTimer.stop();
        HyprlandConfig.reset("general:layout");
    }

    onDesiredChanged: root.desired ? root.enable() : root.disable()

    Component.onCompleted: if (root.desired) root.enable()

    Timer {
        id: floatTimer
        interval: 500
        onTriggered: Quickshell.execDetached(["bash", root.floatScript])
    }
}