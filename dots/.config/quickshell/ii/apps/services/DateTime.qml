pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Slim DateTime stand-in for standalone apps: SystemClock only, no /proc/uptime timer.
 */
Singleton {
    id: root

    property var clock: SystemClock {
        id: clock
        precision: (Config.options?.time?.secondPrecision ?? false)
            ? SystemClock.Seconds
            : SystemClock.Minutes
    }

    readonly property bool use12HourClock: /a/i.test(Config.options?.time?.format ?? "hh:mm")
    readonly property string time: Qt.locale().toString(clock.date, Config.options?.time?.format ?? "hh:mm")
    readonly property string shortDate: Qt.locale().toString(clock.date, Config.options?.time?.shortDateFormat ?? "dd/MM")
    readonly property string date: Qt.locale().toString(clock.date, Config.options?.time?.dateWithYearFormat ?? "dd/MM/yyyy")
    readonly property string longDate: Qt.locale().toString(clock.date, Config.options?.time?.dateFormat ?? "dddd, dd/MM")
}
