pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import "./discordVoice" as DiscordPackage

Singleton {
    id: root

    signal requestCenter(string identifier)

    readonly property var discordVoiceIcon: Component { DiscordPackage.TaskbarGlyph {} }

    readonly property var widgetSymbols: {
        "crosshair": "point_scan",
        "fpsLimiter": "animation",
        "floatingImage": "imagesmode",
        "recorder": "screen_record",
        "media": "music_note",
        "resources": "browse_activity",
        "notes": "note_stack",
        "volumeMixer": "volume_up",
        "discordVoice": "voice_chat",
        "perfMonitor": "speed"
    }

    readonly property list<var> availableWidgets: {
        if (!Config?.ready) return []

        let result = []
        const configButtons = Config.options.overlay.buttons ?? []

        for (let i = 0; i < configButtons.length; i++) {
            const id = configButtons[i]
            if (widgetSymbols.hasOwnProperty(id)) {
                const entry = {
                    identifier: id,
                    materialSymbol: widgetSymbols[id]
                }
                if (id === "discordVoice") {
                    entry.iconComponent = root.discordVoiceIcon
                }
                result.push(entry)
            }
        }

        return result
    }
    readonly property bool hasPinnedWidgets: root.pinnedWidgetIdentifiers.length > 0

    property list<string> pinnedWidgetIdentifiers: []
    // The sampler of the live performance HUD, for its IPC.
    property QtObject perfSampler: null
    property list<var> clickableWidgets: []

    function pin(identifier: string, pin = true) {
        if (pin) {
            if (!root.pinnedWidgetIdentifiers.includes(identifier)) {
                root.pinnedWidgetIdentifiers.push(identifier)
            }
        } else {
            root.pinnedWidgetIdentifiers = root.pinnedWidgetIdentifiers.filter(id => id !== identifier)
        }
    }

    // Shows or hides the performance HUD pinned over the game, without opening
    // the overlay (IPC `perfMonitor toggle` / the perfMonitorToggle shortcut).
    function togglePerfMonitor() {
        const id = "perfMonitor";
        const entry = Persistent.states.overlay.perfMonitor;
        const open = Persistent.states.overlay.open;
        if (open.includes(id) && entry.pinned) {
            Persistent.states.overlay.open = open.filter(w => w !== id);
            root.pin(id, false);
            return;
        }
        if (!open.includes(id))
            Persistent.states.overlay.open = [...open, id];
        entry.pinned = true;
        // Pinning here too arms the overlay window, which creates the widget.
        root.pin(id, true);
    }

    // A pinned HUD comes back with the shell. Other widgets only register
    // once the overlay window exists, so the window has to be armed for it.
    function restorePinnedPerfMonitor() {
        if (!Persistent.ready)
            return;
        const entry = Persistent.states.overlay.perfMonitor;
        if (entry?.pinned && Persistent.states.overlay.open.includes("perfMonitor")) {
            root.pin("perfMonitor", true);
            return;
        }
        // Not coming back: a crash may have left MangoHud logging armed for
        // a HUD nobody is running (the script disarms only when it is idle).
        if (!root.perfIdleChecked) {
            root.perfIdleChecked = true;
            Quickshell.execDetached(["python3", `${Directories.scriptPath}/perfOverlay/perf_monitor.py`, "disarm"]);
        }
    }
    property bool perfIdleChecked: false
    Component.onCompleted: restorePinnedPerfMonitor()
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restorePinnedPerfMonitor();
        }
    }

    function registerClickableWidget(widget: QtObject, clickable = true) {
        if (clickable) {
            if (!root.clickableWidgets.includes(widget)) {
                root.clickableWidgets.push(widget)
            }
        } else {
            root.clickableWidgets = root.clickableWidgets.filter(w => w !== widget)
        }
    }
}
