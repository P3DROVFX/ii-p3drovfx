import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common

Scope {
    id: root
    readonly property string script: Quickshell.shellPath("scripts/desktop/hyprbars.sh")
    readonly property var cfg: Config.options[Config.options.panelFamily]?.hyprbars ?? null
    readonly property bool desired: cfg?.enable ?? false
    readonly property string barFont: (cfg?.font ?? "") || Appearance.font.family.title
    readonly property bool glyphs: cfg?.glyphs ?? false
    readonly property bool macColors: cfg?.macColors ?? false
    readonly property int barHeight: cfg?.barHeight ?? 34

    function run(action) {
        Quickshell.execDetached(["bash", root.script, action, root.barFont, root.glyphs ? "glyphs" : "semaphore", root.macColors ? "mac" : "themed", String(root.barHeight)]);
    }

    onDesiredChanged: run(desired ? "load" : "disable")
    onBarFontChanged: if (desired) fontApply.restart()
    onGlyphsChanged: if (desired) run("style")
    onMacColorsChanged: if (desired) run("style")
    onBarHeightChanged: if (desired) run("style")
    Component.onCompleted: if (desired) run("load")

    Timer {
        id: fontApply
        interval: 600
        onTriggered: root.run("font")
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.run(root.desired ? "restyle" : "disable");
        }
    }
}