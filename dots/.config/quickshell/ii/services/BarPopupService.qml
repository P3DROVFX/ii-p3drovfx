pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Item {
    id: root

    readonly property var knownPopups: [
        "clock", "weather", "battery", "bluetooth", "resources",
        "keyboard", "activeWindow", "sports", "portWatcher", "privacy",
        "aiPlanUsage", "media", "tray", "record", "dictation",
        "mode", "screenShare", "shellUpdate"
    ]

    function list(): string {
        return root.knownPopups.join(", ");
    }

    function status(): string {
        let items = root.knownPopups.map(id => ({
            id: id,
            open: GlobalStates.isBarPopupOpen(id)
        }));
        return JSON.stringify(items);
    }

    // Unified router target
    IpcHandler {
        target: "barPopup"
        function toggle(name: string): void { GlobalStates.toggleBarPopup(name); }
        function open(name: string): void { GlobalStates.openBarPopup(name); }
        function close(name: string): void { GlobalStates.closeBarPopup(name); }
        function toggleOnMonitor(name: string, monitor: string): void { GlobalStates.toggleBarPopup(name, monitor); }
        function openOnMonitor(name: string, monitor: string): void { GlobalStates.openBarPopup(name, monitor); }
        function closeOnMonitor(name: string, monitor: string): void { GlobalStates.closeBarPopup(name, monitor); }
        function closeAll(): void { GlobalStates.closeAllBarPopups(); }
        function list(): string { return root.list(); }
        function status(): string { return root.status(); }
    }

    IpcHandler {
        target: "barPopups"
        function toggle(name: string): void { GlobalStates.toggleBarPopup(name); }
        function open(name: string): void { GlobalStates.openBarPopup(name); }
        function close(name: string): void { GlobalStates.closeBarPopup(name); }
        function toggleOnMonitor(name: string, monitor: string): void { GlobalStates.toggleBarPopup(name, monitor); }
        function openOnMonitor(name: string, monitor: string): void { GlobalStates.openBarPopup(name, monitor); }
        function closeOnMonitor(name: string, monitor: string): void { GlobalStates.closeBarPopup(name, monitor); }
        function closeAll(): void { GlobalStates.closeAllBarPopups(); }
        function list(): string { return root.list(); }
        function status(): string { return root.status(); }
    }

    // Individual Targets
    IpcHandler {
        target: "clockPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("clock"); }
        function open(): void { GlobalStates.openBarPopup("clock"); }
        function close(): void { GlobalStates.closeBarPopup("clock"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("clock", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("clock", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("clock", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("clock"); }
    }
    IpcHandler {
        target: "barClockPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("clock"); }
        function open(): void { GlobalStates.openBarPopup("clock"); }
        function close(): void { GlobalStates.closeBarPopup("clock"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("clock", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("clock", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("clock", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("clock"); }
    }

    IpcHandler {
        target: "weatherPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("weather"); }
        function open(): void { GlobalStates.openBarPopup("weather"); }
        function close(): void { GlobalStates.closeBarPopup("weather"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("weather", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("weather", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("weather", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("weather"); }
    }
    IpcHandler {
        target: "barWeatherPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("weather"); }
        function open(): void { GlobalStates.openBarPopup("weather"); }
        function close(): void { GlobalStates.closeBarPopup("weather"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("weather", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("weather", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("weather", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("weather"); }
    }

    IpcHandler {
        target: "batteryPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("battery"); }
        function open(): void { GlobalStates.openBarPopup("battery"); }
        function close(): void { GlobalStates.closeBarPopup("battery"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("battery", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("battery", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("battery", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("battery"); }
    }
    IpcHandler {
        target: "barBatteryPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("battery"); }
        function open(): void { GlobalStates.openBarPopup("battery"); }
        function close(): void { GlobalStates.closeBarPopup("battery"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("battery", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("battery", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("battery", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("battery"); }
    }

    IpcHandler {
        target: "bluetoothPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("bluetooth"); }
        function open(): void { GlobalStates.openBarPopup("bluetooth"); }
        function close(): void { GlobalStates.closeBarPopup("bluetooth"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("bluetooth", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("bluetooth", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("bluetooth", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("bluetooth"); }
    }
    IpcHandler {
        target: "barBluetoothPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("bluetooth"); }
        function open(): void { GlobalStates.openBarPopup("bluetooth"); }
        function close(): void { GlobalStates.closeBarPopup("bluetooth"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("bluetooth", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("bluetooth", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("bluetooth", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("bluetooth"); }
    }

    IpcHandler {
        target: "resourcesPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("resources"); }
        function open(): void { GlobalStates.openBarPopup("resources"); }
        function close(): void { GlobalStates.closeBarPopup("resources"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("resources", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("resources", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("resources", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("resources"); }
    }
    IpcHandler {
        target: "barResourcesPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("resources"); }
        function open(): void { GlobalStates.openBarPopup("resources"); }
        function close(): void { GlobalStates.closeBarPopup("resources"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("resources", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("resources", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("resources", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("resources"); }
    }

    IpcHandler {
        target: "keyboardLayoutPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("keyboard"); }
        function open(): void { GlobalStates.openBarPopup("keyboard"); }
        function close(): void { GlobalStates.closeBarPopup("keyboard"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("keyboard", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("keyboard", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("keyboard", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("keyboard"); }
    }
    IpcHandler {
        target: "barKeyboardPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("keyboard"); }
        function open(): void { GlobalStates.openBarPopup("keyboard"); }
        function close(): void { GlobalStates.closeBarPopup("keyboard"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("keyboard", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("keyboard", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("keyboard", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("keyboard"); }
    }

    IpcHandler {
        target: "activeWindowPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("activeWindow"); }
        function open(): void { GlobalStates.openBarPopup("activeWindow"); }
        function close(): void { GlobalStates.closeBarPopup("activeWindow"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("activeWindow", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("activeWindow", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("activeWindow", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("activeWindow"); }
    }
    IpcHandler {
        target: "barActiveWindowPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("activeWindow"); }
        function open(): void { GlobalStates.openBarPopup("activeWindow"); }
        function close(): void { GlobalStates.closeBarPopup("activeWindow"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("activeWindow", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("activeWindow", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("activeWindow", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("activeWindow"); }
    }

    IpcHandler {
        target: "sportsPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("sports"); }
        function open(): void { GlobalStates.openBarPopup("sports"); }
        function close(): void { GlobalStates.closeBarPopup("sports"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("sports", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("sports", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("sports", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("sports"); }
    }
    IpcHandler {
        target: "barSportsPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("sports"); }
        function open(): void { GlobalStates.openBarPopup("sports"); }
        function close(): void { GlobalStates.closeBarPopup("sports"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("sports", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("sports", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("sports", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("sports"); }
    }

    IpcHandler {
        target: "portWatcherPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("portWatcher"); }
        function open(): void { GlobalStates.openBarPopup("portWatcher"); }
        function close(): void { GlobalStates.closeBarPopup("portWatcher"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("portWatcher", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("portWatcher", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("portWatcher", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("portWatcher"); }
    }
    IpcHandler {
        target: "barPortWatcherPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("portWatcher"); }
        function open(): void { GlobalStates.openBarPopup("portWatcher"); }
        function close(): void { GlobalStates.closeBarPopup("portWatcher"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("portWatcher", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("portWatcher", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("portWatcher", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("portWatcher"); }
    }

    IpcHandler {
        target: "privacyPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("privacy"); }
        function open(): void { GlobalStates.openBarPopup("privacy"); }
        function close(): void { GlobalStates.closeBarPopup("privacy"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("privacy", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("privacy", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("privacy", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("privacy"); }
    }
    IpcHandler {
        target: "barPrivacyPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("privacy"); }
        function open(): void { GlobalStates.openBarPopup("privacy"); }
        function close(): void { GlobalStates.closeBarPopup("privacy"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("privacy", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("privacy", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("privacy", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("privacy"); }
    }

    IpcHandler {
        target: "aiPlanUsagePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("aiPlanUsage"); }
        function open(): void { GlobalStates.openBarPopup("aiPlanUsage"); }
        function close(): void { GlobalStates.closeBarPopup("aiPlanUsage"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("aiPlanUsage", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("aiPlanUsage", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("aiPlanUsage", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("aiPlanUsage"); }
    }
    IpcHandler {
        target: "barAiPlanUsagePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("aiPlanUsage"); }
        function open(): void { GlobalStates.openBarPopup("aiPlanUsage"); }
        function close(): void { GlobalStates.closeBarPopup("aiPlanUsage"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("aiPlanUsage", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("aiPlanUsage", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("aiPlanUsage", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("aiPlanUsage"); }
    }

    IpcHandler {
        target: "mediaPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("media"); }
        function open(): void { GlobalStates.openBarPopup("media"); }
        function close(): void { GlobalStates.closeBarPopup("media"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("media", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("media", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("media", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("media"); }
    }
    IpcHandler {
        target: "barMediaPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("media"); }
        function open(): void { GlobalStates.openBarPopup("media"); }
        function close(): void { GlobalStates.closeBarPopup("media"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("media", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("media", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("media", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("media"); }
    }

    IpcHandler {
        target: "trayPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("tray"); }
        function open(): void { GlobalStates.openBarPopup("tray"); }
        function close(): void { GlobalStates.closeBarPopup("tray"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("tray", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("tray", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("tray", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("tray"); }
    }
    IpcHandler {
        target: "barTrayPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("tray"); }
        function open(): void { GlobalStates.openBarPopup("tray"); }
        function close(): void { GlobalStates.closeBarPopup("tray"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("tray", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("tray", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("tray", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("tray"); }
    }

    IpcHandler {
        target: "recordPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("record"); }
        function open(): void { GlobalStates.openBarPopup("record"); }
        function close(): void { GlobalStates.closeBarPopup("record"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("record", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("record", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("record", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("record"); }
    }
    IpcHandler {
        target: "barRecordPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("record"); }
        function open(): void { GlobalStates.openBarPopup("record"); }
        function close(): void { GlobalStates.closeBarPopup("record"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("record", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("record", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("record", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("record"); }
    }

    IpcHandler {
        target: "dictationPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("dictation"); }
        function open(): void { GlobalStates.openBarPopup("dictation"); }
        function close(): void { GlobalStates.closeBarPopup("dictation"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("dictation", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("dictation", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("dictation", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("dictation"); }
    }
    IpcHandler {
        target: "barDictationPopup"
        function toggle(): void { GlobalStates.toggleBarPopup("dictation"); }
        function open(): void { GlobalStates.openBarPopup("dictation"); }
        function close(): void { GlobalStates.closeBarPopup("dictation"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("dictation", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("dictation", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("dictation", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("dictation"); }
    }

    IpcHandler {
        target: "modePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("mode"); }
        function open(): void { GlobalStates.openBarPopup("mode"); }
        function close(): void { GlobalStates.closeBarPopup("mode"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("mode", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("mode", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("mode", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("mode"); }
    }
    IpcHandler {
        target: "barModePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("mode"); }
        function open(): void { GlobalStates.openBarPopup("mode"); }
        function close(): void { GlobalStates.closeBarPopup("mode"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("mode", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("mode", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("mode", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("mode"); }
    }

    IpcHandler {
        target: "screenSharePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("screenShare"); }
        function open(): void { GlobalStates.openBarPopup("screenShare"); }
        function close(): void { GlobalStates.closeBarPopup("screenShare"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("screenShare", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("screenShare", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("screenShare", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("screenShare"); }
    }
    IpcHandler {
        target: "barScreenSharePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("screenShare"); }
        function open(): void { GlobalStates.openBarPopup("screenShare"); }
        function close(): void { GlobalStates.closeBarPopup("screenShare"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("screenShare", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("screenShare", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("screenShare", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("screenShare"); }
    }

    IpcHandler {
        target: "shellUpdatePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("shellUpdate"); }
        function open(): void { GlobalStates.openBarPopup("shellUpdate"); }
        function close(): void { GlobalStates.closeBarPopup("shellUpdate"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("shellUpdate", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("shellUpdate", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("shellUpdate", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("shellUpdate"); }
    }
    IpcHandler {
        target: "barShellUpdatePopup"
        function toggle(): void { GlobalStates.toggleBarPopup("shellUpdate"); }
        function open(): void { GlobalStates.openBarPopup("shellUpdate"); }
        function close(): void { GlobalStates.closeBarPopup("shellUpdate"); }
        function toggleOnMonitor(monitor: string): void { GlobalStates.toggleBarPopup("shellUpdate", monitor); }
        function openOnMonitor(monitor: string): void { GlobalStates.openBarPopup("shellUpdate", monitor); }
        function closeOnMonitor(monitor: string): void { GlobalStates.closeBarPopup("shellUpdate", monitor); }
        function status(): bool { return GlobalStates.isBarPopupOpen("shellUpdate"); }
    }
}
