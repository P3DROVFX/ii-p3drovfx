pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Every App usage option in one place: how the app opens, what its figures count,
 * how long history is kept, and the sampler itself. Writes go straight to Config.
 * Collecting at all stays in Settings → App Usage.
 */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    /// Two columns of sections once the page can hold them.
    property bool wide: !root.compact && root.layoutWidth >= 1000

    readonly property var opts: Config.options.appStats
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2,
        root.wide ? 1240 : ClockStyle.sheetMaxWidth * 1.3)
    property bool confirmDelete: false

    readonly property var granularityChoices: [
        { value: "day", label: Translation.tr("Day") },
        { value: "week", label: Translation.tr("Week") },
        { value: "month", label: Translation.tr("Month") }
    ]
    readonly property var metricChoices: [
        { value: "fg", label: Translation.tr("Screen time") },
        { value: "focus", label: Translation.tr("Focused") },
        { value: "energy", label: Translation.tr("Energy") },
        { value: "cpu", label: Translation.tr("CPU") },
        { value: "gpu", label: Translation.tr("GPU") }
    ]
    readonly property var retentionChoices: [
        { value: "previousMonth", label: Translation.tr("Keep the previous month") },
        { value: "fixed", label: Translation.tr("Fixed number of days") }
    ]
    readonly property var energyChoices: [
        { value: "auto", label: Translation.tr("Automatic") },
        { value: "rapl", label: Translation.tr("RAPL counters") },
        { value: "battery", label: Translation.tr("Battery drain") },
        { value: "none", label: Translation.tr("None") }
    ]

    function humanBytes(bytes: real): string {
        if (bytes < 0)
            return "—";
        if (bytes < 1024)
            return `${bytes} B`;
        if (bytes < 1024 * 1024)
            return `${Math.round(bytes / 1024)} KiB`;
        return `${(bytes / 1048576).toFixed(1)} MiB`;
    }

    function seconds(value: int): string {
        return Translation.tr("%1 s").arg(String(value));
    }

    color: ClockStyle.colBackground

    Component.onCompleted: AppStats.measureStorage()

    component Toggle: StyledSwitch {
        property string key
        checked: Boolean(root.opts?.[key])
        checkable: false
        onClicked: root.opts[key] = !root.opts[key]
    }

    /// A row of chips under the row it belongs to, for choices too many to sit beside it.
    component ChoiceStrip: Rectangle {
        id: strip
        property var choices: []
        property string value: ""
        property bool last: false
        signal chosen(string value)

        Layout.fillWidth: true
        implicitHeight: stripFlow.implicitHeight + ClockStyle.gapLarge * 2
        color: ClockStyle.colPane
        topLeftRadius: ClockStyle.radiusSmall / 2
        topRightRadius: ClockStyle.radiusSmall / 2
        bottomLeftRadius: strip.last ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
        bottomRightRadius: strip.last ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2

        Flow {
            id: stripFlow
            anchors {
                fill: parent
                margins: ClockStyle.gapLarge
                leftMargin: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gapSmall

            Repeater {
                model: strip.choices

                ClockFormChip {
                    required property var modelData
                    label: modelData.label
                    selected: strip.value === modelData.value
                    onTriggered: strip.chosen(modelData.value)
                }
            }
        }
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 3

        GridLayout {
            id: column
            x: (flick.width - width) / 2
            y: ClockStyle.gapSmall
            width: root.contentWidth
            columns: root.wide ? 2 : 1
            columnSpacing: ClockStyle.gapHuge
            rowSpacing: ClockStyle.gapHuge
            uniformCellWidths: true

            // ── App ─────────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("App")
                symbol: "apps"

                ClockSettingsRow {
                    first: true
                    symbol: "history"
                    title: Translation.tr("Remember the last view between openings")
                    description: Translation.tr("The page, period and metric the app was left on")
                    clickable: true
                    onClicked: root.opts.rememberLastView = !root.opts.rememberLastView
                    Toggle {
                        key: "rememberLastView"
                    }
                }
                ClockSettingsRow {
                    symbol: "select_check_box"
                    title: Translation.tr("Keep the selected app between openings")
                    clickable: true
                    onClicked: root.opts.keepSelection = !root.opts.keepSelection
                    Toggle {
                        key: "keepSelection"
                    }
                }
                ClockSettingsRow {
                    symbol: "calendar_month"
                    title: Translation.tr("Opens on")
                    description: root.opts.rememberLastView
                        ? Translation.tr("Used when the last view is not remembered")
                        : Translation.tr("The period every opening starts on")

                    Repeater {
                        model: root.granularityChoices

                        ClockChip {
                            required property var modelData
                            label: modelData.label
                            selected: root.opts.defaultGranularity === modelData.value
                            onClicked: root.opts.defaultGranularity = modelData.value
                        }
                    }
                }
                ClockSettingsRow {
                    symbol: "leaderboard"
                    title: Translation.tr("Opens showing")
                    description: Translation.tr("The figure the app ranks by when it opens")
                }
                ChoiceStrip {
                    choices: root.metricChoices
                    value: root.opts.defaultMetric
                    onChosen: value => root.opts.defaultMetric = value
                }
                ClockSettingsRow {
                    last: true
                    symbol: "keyboard"
                    title: Translation.tr("Keybind")
                    description: Translation.tr("Super+U opens this app (the usageToggle shortcut)")
                }
            }

            // ── Figures ─────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Figures")
                symbol: "query_stats"

                ClockSettingsRow {
                    first: true
                    symbol: "calendar_view_week"
                    title: Translation.tr("Weeks start on Monday")
                    clickable: true
                    onClicked: root.opts.weekStartsMonday = !root.opts.weekStartsMonday
                    Toggle {
                        key: "weekStartsMonday"
                    }
                }
                ClockSettingsRow {
                    symbol: "trending_up"
                    title: Translation.tr("Compare with the previous period")
                    description: Translation.tr("Adds a percent change under the headline figure. Reads the period before the one on screen as well, which doubles the files a month view parses")
                    clickable: true
                    onClicked: root.opts.showComparison = !root.opts.showComparison
                    Toggle {
                        key: "showComparison"
                    }
                }
                ClockSettingsRow {
                    symbol: "terminal"
                    title: Translation.tr("Count background services")
                    description: Translation.tr("Processes owning no window. Recorded either way; this decides whether they appear in the list and the totals")
                    clickable: true
                    onClicked: root.opts.showHeadless = !root.opts.showHeadless
                    Toggle {
                        key: "showHeadless"
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "filter_alt"
                    title: Translation.tr("Hide apps under")
                    description: Translation.tr("Applies to the list only, and only to the metrics measured in time. The totals still count every app")
                    ClockStepper {
                        value: root.opts.minDurationSec
                        from: 0
                        to: 3600
                        stepSize: 30
                        format: value => value === 0 ? Translation.tr("Off") : root.seconds(value)
                        onMoved: value => root.opts.minDurationSec = value
                    }
                }
            }

            // ── History & storage ───────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("History & storage")
                symbol: "database"

                ClockSettingsRow {
                    first: true
                    symbol: "auto_delete"
                    title: Translation.tr("How long data is kept")
                    description: {
                        const oldest = AppStats.oldestDate();
                        if (root.opts.retentionMode !== "previousMonth")
                            return Translation.tr("Keeping from %1 onwards.").arg(oldest);
                        return Translation.tr("Keeping from %1 onwards — enough that last month is always whole, so the window slides between 31 and 62 days.").arg(oldest);
                    }
                }
                ChoiceStrip {
                    choices: root.retentionChoices
                    value: root.opts.retentionMode
                    onChosen: value => root.opts.retentionMode = value
                }
                ClockSettingsRow {
                    symbol: "event_repeat"
                    title: root.opts.retentionMode === "previousMonth" ? Translation.tr("At least this many days") : Translation.tr("Days kept")
                    ClockStepper {
                        value: root.opts.retentionDays
                        from: 1
                        to: 365
                        format: value => value === 1 ? Translation.tr("1 day") : Translation.tr("%1 days").arg(String(value))
                        onMoved: value => root.opts.retentionDays = value
                    }
                }
                ClockSettingsRow {
                    symbol: "folder_open"
                    title: Translation.tr("Stored right now")
                    description: AppStats.storedDays < 0 ? Translation.tr("Measuring…")
                        : Translation.tr("%1 days, %2").arg(AppStats.storedDays).arg(root.humanBytes(AppStats.storedBytes))
                }
                // Deleting is confirmed in place rather than in a dialog over the app.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: storageColumn.implicitHeight + ClockStyle.gapLarge * 2
                    color: root.confirmDelete ? ClockStyle.colErrorContainer : ClockStyle.colPane
                    topLeftRadius: ClockStyle.radiusSmall / 2
                    topRightRadius: ClockStyle.radiusSmall / 2
                    bottomLeftRadius: ClockStyle.radiusLarge
                    bottomRightRadius: ClockStyle.radiusLarge

                    Behavior on color {
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }

                    ColumnLayout {
                        id: storageColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: ClockStyle.gapLarge
                            leftMargin: ClockStyle.cardPadding
                        }
                        spacing: ClockStyle.gap

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.confirmDelete
                            text: Translation.tr("Every day file is removed. Collection carries on, so today's starts filling again at the next write.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: ClockStyle.textNormal
                            color: ClockStyle.colOnErrorContainer
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            ClockButton {
                                visible: !root.confirmDelete
                                variant: "tonal"
                                symbol: "save"
                                label: Translation.tr("Write now")
                                tooltip: Translation.tr("Flush the current hour to disk instead of waiting for the next write")
                                onClicked: {
                                    AppStats.refresh();
                                    AppStats.measureStorage();
                                }
                            }
                            ClockButton {
                                visible: !root.confirmDelete
                                variant: "tonal"
                                symbol: "folder_open"
                                label: Translation.tr("Open folder")
                                onClicked: AppStats.openStateDir()
                            }
                            ClockButton {
                                visible: !root.confirmDelete
                                variant: "text"
                                danger: true
                                symbol: "delete"
                                label: Translation.tr("Delete history")
                                onClicked: root.confirmDelete = true
                            }
                            ClockButton {
                                visible: root.confirmDelete
                                variant: "text"
                                label: Translation.tr("Cancel")
                                onClicked: root.confirmDelete = false
                            }
                            ClockButton {
                                visible: root.confirmDelete
                                variant: "filled"
                                danger: true
                                symbol: "delete"
                                label: Translation.tr("Delete")
                                onClicked: {
                                    AppStats.clearHistory();
                                    root.confirmDelete = false;
                                    AppStats.measureStorage();
                                }
                            }
                        }
                    }
                }
            }

            // ── Collection ──────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Collection")
                symbol: "settings_input_component"

                ClockSettingsRow {
                    first: true
                    symbol: "monitor_heart"
                    title: Translation.tr("Sampler")
                    description: {
                        let status;
                        if (!AppStats.enabled)
                            status = Translation.tr("Turned off.");
                        else if (!AppStats.running)
                            status = Translation.tr("Not running — check that the binary is built at scripts/appStats/app_stats.");
                        else if (AppStats.source === "rapl")
                            status = Translation.tr("Running, reading energy from RAPL counters.");
                        else if (AppStats.source === "battery")
                            status = Translation.tr("Running, estimating energy from battery drain.");
                        else
                            status = Translation.tr("Running without an energy source; watt-hours will stay empty.");
                        return status + " " + Translation.tr("It reads the options below once when it starts, so changing any of them restarts it.");
                    }

                    MaterialShapeWrappedMaterialSymbol {
                        text: AppStats.running ? "check" : "close"
                        iconSize: 18
                        padding: 8
                        shape: MaterialShape.Shape.Cookie7Sided
                        color: AppStats.running ? ClockStyle.colPrimaryContainer : ClockStyle.colErrorContainer
                        colSymbol: AppStats.running ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnErrorContainer
                        fill: 1
                    }
                }
                ClockSettingsRow {
                    symbol: "bolt"
                    title: Translation.tr("Energy source")
                    description: Translation.tr("RAPL needs the udev rule from the sampler's README. Battery drain is much cruder and reads zero on AC.")
                }
                ChoiceStrip {
                    choices: root.energyChoices
                    value: root.opts.energySource
                    onChosen: value => root.opts.energySource = value
                }
                ClockSettingsRow {
                    symbol: "timer"
                    title: Translation.tr("Sample every")
                    description: Translation.tr("How often the counters are read. Shorter means finer window attribution and more CPU")
                    ClockStepper {
                        value: root.opts.sampleIntervalMs
                        from: 1000
                        to: 60000
                        stepSize: 1000
                        format: value => root.seconds(value / 1000)
                        onMoved: value => root.opts.sampleIntervalMs = value
                    }
                }
                ClockSettingsRow {
                    symbol: "save"
                    title: Translation.tr("Write to disk every")
                    ClockStepper {
                        value: root.opts.flushIntervalMs
                        from: 5000
                        to: 600000
                        stepSize: 5000
                        format: value => root.seconds(value / 1000)
                        onMoved: value => root.opts.flushIntervalMs = value
                    }
                }
                ClockSettingsRow {
                    symbol: "motion_sensor_idle"
                    title: Translation.tr("Pause after idle for")
                    description: Translation.tr("Foreground time stops accruing once there has been no input for this long. Off keeps it running")
                    ClockStepper {
                        value: root.opts.idleTimeoutSec
                        from: 0
                        to: 3600
                        stepSize: 30
                        format: value => value === 0 ? Translation.tr("Off") : root.seconds(value)
                        onMoved: value => root.opts.idleTimeoutSec = value
                    }
                }
                ClockSettingsRow {
                    symbol: "stadia_controller"
                    title: Translation.tr("Full GPU rescan every (samples)")
                    description: Translation.tr("Only a backstop — a new window forces a rescan immediately. Lower values cost a full sweep of every process's file descriptors")
                    ClockStepper {
                        value: root.opts.gpuFullEvery
                        from: 1
                        to: 600
                        stepSize: 5
                        onMoved: value => root.opts.gpuFullEvery = value
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "terminal"
                    title: Translation.tr("Record background services")
                    description: Translation.tr("Off means processes with no window are never written down, and cannot be shown later")
                    clickable: true
                    onClicked: root.opts.trackHeadless = !root.opts.trackHeadless
                    Toggle {
                        key: "trackHeadless"
                    }
                }
            }
        }
    }
}
