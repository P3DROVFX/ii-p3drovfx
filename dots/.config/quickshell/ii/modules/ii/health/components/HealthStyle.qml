pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * System Health's tokens. Surfaces, radii, motion and type come from ClockStyle, since
 * the app is a member of the clock family; what is added here is only what health has
 * that the clock does not: severity, and the sizes of its own pieces.
 *
 * Severity reuses the existing roles rather than inventing colours: critical is the
 * error container, warning the tertiary container, info the secondary container and
 * healthy the primary container. A card and the controls on it share that family.
 */
Singleton {
    id: root

    function colSeverity(sev) {
        return sev === "critical" ? ClockStyle.colErrorContainer
             : sev === "warning" ? ClockStyle.colTertiaryContainer
             : sev === "info" ? ClockStyle.colSecondaryContainer
             : ClockStyle.colPrimaryContainer;
    }

    function colSeverityHover(sev) {
        return sev === "critical" ? ClockStyle.colErrorContainerHover
             : sev === "warning" ? ClockStyle.colTertiaryContainerHover
             : sev === "info" ? ClockStyle.colSecondaryContainerHover
             : ClockStyle.colPrimaryContainerHover;
    }

    function colOnSeverity(sev) {
        return sev === "critical" ? ClockStyle.colOnErrorContainer
             : sev === "warning" ? ClockStyle.colOnTertiaryContainer
             : sev === "info" ? ClockStyle.colOnSecondaryContainer
             : ClockStyle.colOnPrimaryContainer;
    }

    function severitySymbol(kind) {
        switch (kind) {
        case "unit": return "error";
        case "appLaunch": return "rocket_launch";
        case "restartLoop": return "autorenew";
        case "crash": return "heart_broken";
        case "journal": return "receipt_long";
        case "disk": return "hard_drive";
        case "drive": return "storage";
        case "firmware": return "memory";
        case "security": return "shield";
        case "reboot": return "restart_alt";
        case "deletedLibs": return "sync_problem";
        case "pacnew": return "description";
        case "timesync": return "schedule";
        case "pressure": return "speed";
        case "thermal": return "device_thermostat";
        case "rebuild": return "construction";
        case "shellHelper": return "build_circle";
        case "shellMemory": return "memory_alt";
        case "shellErrors": return "bug_report";
        case "slowBoot": return "timer";
        case "config": return "settings_alert";
        case "battery": return "battery_horiz_050";
        case "peripheralBattery": return "battery_low";
        case "mce": return "memory";
        case "gpu": return "developer_board";
        case "oom": return "memory_alt";
        case "edac": return "memory_alt";
        case "radioFw": return "wifi_off";
        case "usb": return "usb";
        case "aer": return "cable";
        case "overheat": return "device_thermostat";
        case "fan": return "mode_fan_off";
        default: return "info";
        }
    }

    // The one wide, light face in the app: the crash stage's program name. Everywhere
    // else type is condensed or rounded; this is the contrast the stage is built on.
    readonly property var axesWideLight: ({ "wght": 300, "wdth": 125, "ROND": 0 })
    // The noise figure: the only thin number, so "hidden" reads as quiet.
    readonly property var axesThin: ({ "wght": 260, "wdth": 30, "ROND": 100 })
    // The hero's caption beside the digit: wide and italic against the condensed digit.
    readonly property var axesWideItalic: ({ "wght": 420, "wdth": 112, "ROND": 100 })

    // ── Sizes ───────────────────────────────────────────────────────────
    readonly property int heroMinHeight: 260
    readonly property int heroDigitMax: 168
    readonly property int heroDigitMin: 88
    readonly property int laneHeight: 44
    readonly property int laneLabelWidth: 168
    readonly property int laneLabelWidthCompact: 104
    readonly property int stageMinWidth: 340
    readonly property int vitalMinWidth: 200
    readonly property int systemCardMinWidth: 260
    readonly property int sideBySideMin: 820
}
