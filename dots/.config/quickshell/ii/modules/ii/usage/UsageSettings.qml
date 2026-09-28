pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The usage overlay's own settings, behind the gear beside its close button:
 * overlay views, history and storage, and the sampler. Collecting at all and
 * loading the overlay stay in Settings → App Usage.
 */
AppSettingsPage {
    id: root

    readonly property var opts: Config.options.appStats
    property bool confirmDelete: false

    function humanBytes(bytes) {
        if (bytes < 0)
            return "—";
        if (bytes < 1024)
            return `${bytes} B`;
        if (bytes < 1024 * 1024)
            return `${Math.round(bytes / 1024)} KiB`;
        return `${(bytes / 1048576).toFixed(1)} MiB`;
    }

    title: Translation.tr("App usage settings")
    subtitle: Translation.tr("Views, history and the sampler")

    Component.onCompleted: AppStats.measureStorage()

    // ══ Primary column ══

    AppSettingsSection {
        title: Translation.tr("Overlay Preferences")
        symbol: "tune"

        AppToggleRow {
            symbol: "history"
            title: Translation.tr("Remember last view")
            description: Translation.tr("Remember the selected page, period and metric between openings")
            checked: root.opts.rememberLastView
            onToggled: value => root.opts.rememberLastView = value
        }
        AppToggleRow {
            symbol: "select_check_box"
            title: Translation.tr("Keep the selected app between openings")
            checked: root.opts.keepSelection
            onToggled: value => root.opts.keepSelection = value
        }
        AppToggleRow {
            symbol: "calendar_view_week"
            title: Translation.tr("Weeks start on Monday")
            checked: root.opts.weekStartsMonday
            onToggled: value => root.opts.weekStartsMonday = value
        }
        AppToggleRow {
            symbol: "trending_up"
            title: Translation.tr("Compare with the previous period")
            help: Translation.tr("Adds a percent change under the headline figure. Reads the period before the one on screen as well, which doubles the files a month view parses")
            checked: root.opts.showComparison
            onToggled: value => root.opts.showComparison = value
        }
        AppToggleRow {
            symbol: "terminal"
            title: Translation.tr("Count background services")
            help: Translation.tr("Processes owning no window. Recorded either way; this decides whether they appear in the list and the totals")
            checked: root.opts.showHeadless
            onToggled: value => root.opts.showHeadless = value
        }
        AppChoiceRow {
            symbol: "calendar_month"
            title: Translation.tr("Opens on")
            currentValue: root.opts.defaultGranularity
            onSelected: value => root.opts.defaultGranularity = value
            options: [
                { "label": Translation.tr("Day"), "value": "day" },
                { "label": Translation.tr("Week"), "value": "week" },
                { "label": Translation.tr("Month"), "value": "month" }
            ]
        }
        AppChoiceRow {
            symbol: "leaderboard"
            title: Translation.tr("Opens showing")
            currentValue: root.opts.defaultMetric
            onSelected: value => root.opts.defaultMetric = value
            options: [
                { "label": Translation.tr("Screen time"), "value": "fg" },
                { "label": Translation.tr("Focused"), "value": "focus" },
                { "label": Translation.tr("Energy"), "value": "energy" },
                { "label": Translation.tr("CPU"), "value": "cpu" },
                { "label": Translation.tr("GPU"), "value": "gpu" }
            ]
        }
        AppStepperRow {
            symbol: "filter_alt"
            title: Translation.tr("Hide apps under (seconds)")
            help: Translation.tr("Applies to the list only, and only to the metrics measured in time. The totals still count every app")
            value: root.opts.minDurationSec
            from: 0
            to: 3600
            stepSize: 30
            onMoved: value => root.opts.minDurationSec = value
        }
    }

    AppSettingsSection {
        title: Translation.tr("History & Storage")
        symbol: "database"

        AppChoiceRow {
            symbol: "auto_delete"
            title: Translation.tr("How long data is kept")
            description: {
                const oldest = AppStats.oldestDate();
                if (root.opts.retentionMode !== "previousMonth")
                    return Translation.tr("Keeping from %1 onwards.").arg(oldest);
                return Translation.tr("Keeping from %1 onwards — enough that last month is always whole, so the window slides between 31 and 62 days.").arg(oldest);
            }
            currentValue: root.opts.retentionMode
            onSelected: value => root.opts.retentionMode = value
            options: [
                { "label": Translation.tr("Keep the previous month"), "value": "previousMonth" },
                { "label": Translation.tr("Fixed number of days"), "value": "fixed" }
            ]
        }
        AppStepperRow {
            symbol: "event_repeat"
            title: root.opts.retentionMode === "previousMonth" ? Translation.tr("At least this many days") : Translation.tr("Days kept")
            value: root.opts.retentionDays
            from: 1
            to: 365
            onMoved: value => root.opts.retentionDays = value
        }
        AppSettingRow {
            symbol: "folder_open"
            title: Translation.tr("Stored right now")
            description: AppStats.storedDays < 0 ? Translation.tr("Measuring…") : Translation.tr("%1 days, %2").arg(AppStats.storedDays).arg(root.humanBytes(AppStats.storedBytes))

            below: Flow {
                Layout.fillWidth: true
                spacing: 8

                AppRowButton {
                    visible: !root.confirmDelete
                    symbol: "save"
                    label: Translation.tr("Write now")
                    tooltip: Translation.tr("Flush the current hour to disk instead of waiting for the next write")
                    onClicked: {
                        AppStats.refresh();
                        AppStats.measureStorage();
                    }
                }
                AppRowButton {
                    visible: !root.confirmDelete
                    symbol: "folder_open"
                    label: Translation.tr("Open folder")
                    onClicked: AppStats.openStateDir()
                }
                AppRowButton {
                    visible: !root.confirmDelete
                    symbol: "delete"
                    label: Translation.tr("Delete history")
                    danger: true
                    onClicked: root.confirmDelete = true
                }
                // Deleting is confirmed in place rather than in a dialog over the overlay.
                StyledText {
                    visible: root.confirmDelete
                    height: 36
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Every day file is removed. Collection carries on, so today's starts filling again at the next write.")
                    wrapMode: Text.WordWrap
                    width: parent.width
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                AppRowButton {
                    visible: root.confirmDelete
                    label: Translation.tr("Cancel")
                    onClicked: root.confirmDelete = false
                }
                AppRowButton {
                    visible: root.confirmDelete
                    symbol: "delete"
                    label: Translation.tr("Delete")
                    danger: true
                    filled: true
                    onClicked: {
                        AppStats.clearHistory();
                        root.confirmDelete = false;
                        AppStats.measureStorage();
                    }
                }
            }
        }
    }

    // ══ Secondary column ══

    secondary: AppSettingsSection {
        title: Translation.tr("Collection Settings")
        symbol: "settings_input_component"
        description: Translation.tr("The sampler reads these once when it starts, so changing any of them restarts it.")

        AppSettingRow {
            symbol: "monitor_heart"
            title: Translation.tr("Sampler Status")
            description: {
                if (!AppStats.enabled)
                    return Translation.tr("Turned off.");
                if (!AppStats.running)
                    return Translation.tr("Not running — check that the binary is built at scripts/appStats/app_stats.");
                switch (AppStats.source) {
                case "rapl":
                    return Translation.tr("Running, reading energy from RAPL counters.");
                case "battery":
                    return Translation.tr("Running, estimating energy from battery drain.");
                default:
                    return Translation.tr("Running without an energy source; watt-hours will stay empty.");
                }
            }
        }
        AppChoiceRow {
            symbol: "bolt"
            title: Translation.tr("Energy source")
            description: Translation.tr("RAPL needs the udev rule from the sampler's README. Battery drain is much cruder and reads zero on AC.")
            currentValue: root.opts.energySource
            onSelected: value => root.opts.energySource = value
            options: [
                { "label": Translation.tr("Automatic"), "value": "auto" },
                { "label": Translation.tr("RAPL counters"), "value": "rapl" },
                { "label": Translation.tr("Battery drain"), "value": "battery" },
                { "label": Translation.tr("None"), "value": "none" }
            ]
        }
        AppStepperRow {
            symbol: "timer"
            title: Translation.tr("Sample every (ms)")
            help: Translation.tr("How often the counters are read. Shorter means finer window attribution and more CPU")
            value: root.opts.sampleIntervalMs
            from: 1000
            to: 60000
            stepSize: 1000
            onMoved: value => root.opts.sampleIntervalMs = value
        }
        AppStepperRow {
            symbol: "save"
            title: Translation.tr("Write to disk every (ms)")
            value: root.opts.flushIntervalMs
            from: 5000
            to: 600000
            stepSize: 5000
            onMoved: value => root.opts.flushIntervalMs = value
        }
        AppStepperRow {
            symbol: "motion_sensor_idle"
            title: Translation.tr("Pause after idle for (seconds)")
            help: Translation.tr("Foreground time stops accruing once there has been no input for this long. 0 keeps it running")
            value: root.opts.idleTimeoutSec
            from: 0
            to: 3600
            stepSize: 30
            onMoved: value => root.opts.idleTimeoutSec = value
        }
        AppStepperRow {
            symbol: "stadia_controller"
            title: Translation.tr("Full GPU rescan every (samples)")
            help: Translation.tr("Only a backstop — a new window forces a rescan immediately. Lower values cost a full sweep of every process's file descriptors")
            value: root.opts.gpuFullEvery
            from: 1
            to: 600
            stepSize: 5
            onMoved: value => root.opts.gpuFullEvery = value
        }
        AppToggleRow {
            symbol: "terminal"
            title: Translation.tr("Record background services")
            help: Translation.tr("Off means processes with no window are never written down, and cannot be shown later")
            checked: root.opts.trackHeadless
            onToggled: value => root.opts.trackHeadless = value
        }
    }
}
