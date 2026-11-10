pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import qs.services
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

    // -------------------------------------------------------------- auto pin

    function autoPinSignal(identifier: string): bool {
        return identifier === "discordVoice" ? DiscordVoice.inVoice : GameDetector.rawRunning;
    }

    // Pins a widget while its signal holds and takes back only the pins it
    // made itself (`autoPinned`): a pin the user set is never touched, and a
    // pin the user dropped mid-session is not forced back.
    function setAutoPin(identifier: string, wanted: bool) {
        if (!Persistent.ready || !root.availableWidgets.some(w => w.identifier === identifier))
            return;
        // The crosshair keeps its own options.
        const options = identifier === "crosshair" ? Config.options.crosshair : Config.options.overlay?.[identifier];
        const entry = Persistent.states.overlay[identifier];
        if (!entry)
            return;
        // Turned off: whatever is pinned now belongs to the user.
        if (options?.autoPin === false) {
            if (entry.autoPinned)
                entry.autoPinned = false;
            return;
        }
        const open = Persistent.states.overlay.open;
        if (wanted) {
            if (entry.autoPinned) {
                // Claimed earlier (or before a restart): re-arm the window only.
                if (entry.pinned && open.includes(identifier))
                    root.pin(identifier, true);
                return;
            }
            if (entry.pinned && open.includes(identifier))
                return; // the user's own pin
            if (!open.includes(identifier))
                Persistent.states.overlay.open = [...open, identifier];
            entry.pinned = true;
            entry.autoPinned = true;
            root.pin(identifier, true);
        } else {
            if (!entry.autoPinned)
                return;
            entry.autoPinned = false;
            // Leave the crosshair in the widget list, only its pin goes.
            if (identifier !== "crosshair" && open.includes(identifier))
                Persistent.states.overlay.open = open.filter(id => id !== identifier);
            if (entry.pinned)
                entry.pinned = false;
            root.pin(identifier, false);
        }
    }

    // Pins apply at once; releases wait out short signal gaps (a launcher
    // handing over to the game window, a stale MangoHud log on a loading
    // screen) and re-read the live signal when they fire.
    function requestAutoPin(identifier: string) {
        if (root.autoPinSignal(identifier))
            root.setAutoPin(identifier, true);
        else if (root.autoPinSettled)
            autoPinRelease.restart();
    }

    function syncAutoPins() {
        for (const id of ["discordVoice", "perfMonitor", "crosshair"]) {
            const wanted = root.autoPinSignal(id);
            if (wanted || root.autoPinSettled)
                root.setAutoPin(id, wanted);
        }
    }

    // Right after boot the Discord bridge and the window list are still
    // empty, so nothing is released until they had time to come up.
    property bool autoPinSettled: false
    property Timer autoPinBootGrace: Timer {
        interval: 10000
        running: true
        onTriggered: {
            root.autoPinSettled = true;
            root.syncAutoPins();
        }
    }
    property Timer autoPinRelease: Timer {
        interval: 2500
        onTriggered: root.syncAutoPins()
    }

    Component.onCompleted: {
        root.restorePinnedPerfMonitor();
        root.syncAutoPins();
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restorePinnedPerfMonitor();
            root.syncAutoPins();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.syncAutoPins();
        }
    }
    // Flipping the option on pins at once.
    Connections {
        target: Config.options?.overlay?.discordVoice ?? null
        function onAutoPinChanged() {
            root.requestAutoPin("discordVoice");
        }
    }
    Connections {
        target: Config.options?.overlay?.perfMonitor ?? null
        function onAutoPinChanged() {
            root.requestAutoPin("perfMonitor");
        }
    }
    Connections {
        target: Config.options?.crosshair ?? null
        function onAutoPinChanged() {
            root.requestAutoPin("crosshair");
        }
    }
    Connections {
        target: DiscordVoice
        function onInVoiceChanged() {
            root.requestAutoPin("discordVoice");
        }
    }
    Connections {
        target: GameDetector
        function onRawRunningChanged() {
            root.requestAutoPin("perfMonitor");
            root.requestAutoPin("crosshair");
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
