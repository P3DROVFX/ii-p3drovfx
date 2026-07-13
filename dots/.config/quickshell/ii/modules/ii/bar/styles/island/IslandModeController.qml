import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs

QtObject {
    id: root

    required property var screen

    readonly property bool isSearchOpenHere: {
        return GlobalStates.overviewOpen
            && root.screen
            && root.screen.name === GlobalStates.activeSearchMonitor;
    }

    readonly property bool isOsdOpenHere: {
        if (!GlobalStates.osdVolumeOpen)
            return false;
        const monitor = Hyprland.focusedMonitor;
        const name = monitor ? monitor.name : "";
        const screen = Quickshell.screens.find(s => s.name === name);
        const targetScreen = screen ? screen : Quickshell.screens[0];
        const targetName = targetScreen ? targetScreen.name : "";
        return root.screen && root.screen.name === targetName;
    }

    readonly property bool isNotificationActiveHere: {
        if (Notifications.popupList.length === 0)
            return false;
        const monitor = Hyprland.focusedMonitor;
        const name = monitor ? monitor.name : "";
        const targetScreen = Quickshell.screens.find(s => Config.options.notifications.monitor.enable ? s.name === Config.options.notifications.monitor.name : s.name === name);
        const targetName = targetScreen ? targetScreen.name : "";
        return root.screen && targetName !== "" && root.screen.name === targetName;
    }

    readonly property string _calculatedMode: {
        if (isSearchOpenHere)
            return "search";
        if (isOsdOpenHere)
            return "osd";
        if (isNotificationActiveHere)
            return "notification";
        return "";
    }

    readonly property string resolvedMode: _calculatedMode
}
