pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell

Singleton {
    id: root

    property bool automatic: Config.options?.light?.darkMode?.automatic ?? false
    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    onClockHourChanged: {
        if (automatic && clockMinute === 0) {
            if (clockHour === 18) enableDarkMode();
            else if (clockHour === 6) disableDarkMode();
        }
    }

    onClockMinuteChanged: {
        if (automatic && clockMinute === 0) {
            if (clockHour === 18) enableDarkMode();
            else if (clockHour === 6) disableDarkMode();
        }
    }

    function enableDarkMode() {
        if (!Appearance.m3colors.darkmode) {
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
        }
    }

    function disableDarkMode() {
        if (Appearance.m3colors.darkmode) {
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
        }
    }
}
