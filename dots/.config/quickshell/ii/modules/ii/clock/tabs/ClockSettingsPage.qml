pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Every clock option in one place: the app, alarms, the bar popup, world clocks, timers
 * and the pomodoro. Writes go straight to Config, so the bar, the sidebar and the island
 * follow the moment a value changes.
 */
Rectangle {
    id: root

    property bool compact: false
    /// Two columns of sections once the page can hold them: a desktop window left a
    /// single 700 px column floating in the middle of empty space.
    property bool wide: false
    property real layoutWidth: root.width

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2, root.wide ? 1240 : ClockStyle.sheetMaxWidth * 1.3)

    readonly property var app: Config.options.clockApp
    readonly property var time: Config.options.time
    readonly property var alarms: Config.options.time.alarms
    readonly property var sounds: Config.options.sounds

    readonly property var startTabs: [
        { id: "last", label: Translation.tr("Last used") },
        { id: "alarms", label: Translation.tr("Alarms") },
        { id: "worldClock", label: Translation.tr("World clock") },
        { id: "timer", label: Translation.tr("Timer") },
        { id: "stopwatch", label: Translation.tr("Stopwatch") },
        { id: "pomodoro", label: Translation.tr("Pomodoro") },
        { id: "bedtime", label: Translation.tr("Bedtime") }
    ]
    readonly property var timeFormats: [
        { value: "hh:mm", label: Translation.tr("24h") },
        { value: "h:mm ap", label: Translation.tr("12h am/pm") },
        { value: "h:mm AP", label: Translation.tr("12h AM/PM") }
    ]

    signal tabRequested(string tabId)

    function setTimeFormat(value: string): void {
        DateUtils.syncHyprlockTimeFormat(value);
        Config.options.time.format = value;
    }

    function minutesLabel(value: int): string {
        return Translation.tr("%1 min").arg(String(value));
    }

    color: ClockStyle.colBackground

    component Toggle: StyledSwitch {
        property var target
        property string key
        checked: Boolean(target?.[key])
        checkable: false
        onClicked: target[key] = !target[key]
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 3
        clip: true

        GridLayout {
            id: column
            x: (flick.width - width) / 2
            y: ClockStyle.gapSmall
            width: root.contentWidth
            columns: root.wide ? 2 : 1
            columnSpacing: ClockStyle.gapHuge
            rowSpacing: ClockStyle.gapHuge
            uniformCellWidths: true

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("App")
                symbol: "apps"

                ClockSettingsRow {
                    first: true
                    symbol: "tab"
                    title: Translation.tr("Open on")
                    description: Translation.tr("The tab the app starts on")
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: startFlow.implicitHeight + ClockStyle.gapLarge * 2
                    color: ClockStyle.colPane
                    radius: ClockStyle.radiusSmall / 2

                    Flow {
                        id: startFlow
                        anchors {
                            fill: parent
                            margins: ClockStyle.gapLarge
                            leftMargin: ClockStyle.cardPadding
                        }
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: root.startTabs

                            ClockFormChip {
                                required property var modelData
                                label: modelData.label
                                selected: (root.app?.startTab ?? "last") === modelData.id
                                onTriggered: root.app.startTab = modelData.id
                            }
                        }
                    }
                }
                ClockSettingsRow {
                    symbol: "schedule"
                    title: Translation.tr("Clock format")
                    description: Translation.tr("Used everywhere in the shell")
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: formatFlow.implicitHeight + ClockStyle.gapLarge * 2
                    color: ClockStyle.colPane
                    radius: ClockStyle.radiusSmall / 2

                    Flow {
                        id: formatFlow
                        anchors {
                            fill: parent
                            margins: ClockStyle.gapLarge
                            leftMargin: ClockStyle.cardPadding
                        }
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: root.timeFormats

                            ClockFormChip {
                                required property var modelData
                                label: modelData.label
                                selected: root.time.format === modelData.value
                                onTriggered: root.setTimeFormat(modelData.value)
                            }
                        }
                    }
                }
                ClockSettingsRow {
                    symbol: "timer_10"
                    title: Translation.tr("Seconds in the app")
                    description: Translation.tr("World clock and the dial tick every second while the app is open")
                    Toggle {
                        target: root.app
                        key: "showSecondsInApp"
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "calendar_view_week"
                    title: Translation.tr("Start week on Monday")
                    StyledSwitch {
                        checked: root.time.firstDayOfWeek === 0
                        checkable: false
                        onClicked: root.time.firstDayOfWeek = root.time.firstDayOfWeek === 0 ? 6 : 0
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Alarms")
                symbol: "alarm"

                ClockSettingsRow {
                    first: true
                    symbol: "fullscreen"
                    title: Translation.tr("Full-screen ringing")
                    description: Translation.tr("Otherwise a notification (or the Dynamic Island) rings")
                    Toggle {
                        target: root.alarms
                        key: "useFullscreenPopup"
                    }
                }
                ClockSettingsRow {
                    symbol: "snooze"
                    title: Translation.tr("Snooze length")
                    ClockStepper {
                        value: root.alarms.snoozeMinutes ?? 9
                        from: 1
                        to: 30
                        format: value => root.minutesLabel(value)
                        onMoved: value => root.alarms.snoozeMinutes = value
                    }
                }
                ClockSettingsRow {
                    symbol: "notifications_paused"
                    title: Translation.tr("Silence after")
                    description: Translation.tr("A ringing alarm stops on its own after this long")
                    ClockStepper {
                        value: root.alarms.autoSilenceMinutes ?? 5
                        from: 0
                        to: 30
                        format: value => value === 0 ? Translation.tr("Never") : root.minutesLabel(value)
                        onMoved: value => root.alarms.autoSilenceMinutes = value
                    }
                }
                ClockSettingsRow {
                    symbol: "power_settings_new"
                    title: Translation.tr("Wake from suspend")
                    description: AlarmService.wakeScheduledFor
                        ? Translation.tr("Next wake-up %1").arg(Qt.formatDateTime(AlarmService.wakeScheduledFor, "ddd HH:mm"))
                        : Translation.tr("Wakes a sleeping computer shortly before the next alarm")
                    Toggle {
                        target: root.alarms
                        key: "wakeFromSuspend"
                    }
                }
                ClockSettingsRow {
                    symbol: "history"
                    title: Translation.tr("Ring late alarms")
                    description: Translation.tr("An alarm missed while the computer slept still rings if it is at most this late")
                    ClockStepper {
                        value: root.alarms.catchUpMinutes ?? 10
                        from: 0
                        to: 60
                        stepSize: 5
                        format: value => value === 0 ? Translation.tr("Never") : root.minutesLabel(value)
                        onMoved: value => root.alarms.catchUpMinutes = value
                    }
                }
                ClockSettingsRow {
                    symbol: "upcoming"
                    title: Translation.tr("Show the next alarm")
                    description: Translation.tr("In the bar and the island, this long before it rings")
                    ClockStepper {
                        value: root.alarms.showUpcoming === false ? 0 : (root.alarms.upcomingMinutes ?? 60)
                        from: 0
                        to: 180
                        stepSize: 15
                        format: value => value === 0 ? Translation.tr("Off") : root.minutesLabel(value)
                        onMoved: value => {
                            root.alarms.showUpcoming = value > 0;
                            if (value > 0)
                                root.alarms.upcomingMinutes = value;
                        }
                    }
                }
                ClockSettingsRow {
                    symbol: "phone_android"
                    title: Translation.tr("Mirror the phone's alarm")
                    description: PhoneAlarmService.nextAt
                        ? Translation.tr("Phone's next alarm %1").arg(Qt.formatDateTime(PhoneAlarmService.nextAt, "ddd HH:mm"))
                        : Translation.tr("Read over ADB while the phone is connected")
                    Toggle {
                        target: Config.options.clockApp.phoneAlarm
                        key: "enable"
                    }
                }
                ClockSettingsRow {
                    symbol: "volume_up"
                    title: Translation.tr("Alarm sound")
                    description: Translation.tr("Rings even when system sounds are off")
                    ClockIconButton {
                        symbol: "play_arrow"
                        tooltip: Translation.tr("Preview")
                        onClicked: {
                            const custom = root.sounds.custom?.alarm ?? "";
                            if (custom.length > 0)
                                SoundService.previewFile(custom);
                            else
                                SoundService.preview(root.sounds.theme, "alarm-clock-elapsed");
                        }
                    }
                    Toggle {
                        target: root.sounds
                        key: "alarm"
                    }
                }
                ClockSettingsRow {
                    symbol: "trending_up"
                    title: Translation.tr("Gentle wake")
                    description: Translation.tr("Fade the alarm in instead of starting at full volume")
                    Toggle {
                        target: root.sounds
                        key: "alarmFadeIn"
                    }
                }
                ClockSettingsRow {
                    visible: root.sounds.alarmFadeIn
                    symbol: "av_timer"
                    title: Translation.tr("Fade-in length")
                    ClockStepper {
                        value: root.sounds.alarmFadeInSeconds ?? 30
                        from: 5
                        to: 120
                        stepSize: 5
                        format: value => ClockFormat.shortDuration(value)
                        onMoved: value => root.sounds.alarmFadeInSeconds = value
                    }
                }
                ClockSettingsRow {
                    symbol: "calendar_month"
                    title: Translation.tr("Timetable suggestions")
                    description: Translation.tr("Offer upcoming timetable events as alarms")
                    Toggle {
                        target: root.app
                        key: "showTimetableEvents"
                    }
                }
                ClockSettingsRow {
                    visible: root.app?.showTimetableEvents ?? true
                    symbol: "more_time"
                    title: Translation.tr("Ring before the event")
                    ClockStepper {
                        value: root.app?.timetableLeadMinutes ?? 15
                        from: 0
                        to: 240
                        stepSize: 5
                        format: value => root.minutesLabel(value)
                        onMoved: value => root.app.timetableLeadMinutes = value
                    }
                }
                ClockSettingsRow {
                    last: true
                    visible: root.app?.showTimetableEvents ?? true
                    symbol: "date_range"
                    title: Translation.tr("Look ahead")
                    ClockStepper {
                        value: root.app?.timetableLookaheadDays ?? 2
                        from: 1
                        to: 14
                        format: value => Translation.tr("%1 days").arg(String(value))
                        onMoved: value => root.app.timetableLookaheadDays = value
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("World clock")
                symbol: "public"

                ClockSettingsRow {
                    first: true
                    symbol: "nest_clock_farsight_analog"
                    title: Translation.tr("Analog dial with every city")
                    Toggle {
                        target: root.app
                        key: "analogWorldClock"
                    }
                }
                ClockSettingsRow {
                    last: true
                    clickable: true
                    symbol: "edit_location_alt"
                    title: Translation.tr("Manage cities")
                    description: Translation.tr("%1 cities").arg(String(WorldClockService.clocks.length))
                    onClicked: root.tabRequested("worldClock")
                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: ClockStyle.iconNormal
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Bar clock popup")
                symbol: "toolbar"

                ClockSettingsRow {
                    first: true
                    symbol: "schedule"
                    title: Translation.tr("Analog clock")
                    description: Translation.tr("Click it to open this app")
                    Toggle {
                        target: root.alarms
                        key: "showAnalogClock"
                    }
                }
                ClockSettingsRow {
                    symbol: "public"
                    title: Translation.tr("World clocks")
                    Toggle {
                        target: root.alarms
                        key: "showWorldClocks"
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "alarm"
                    title: Translation.tr("Alarms")
                    Toggle {
                        target: root.alarms
                        key: "showAlarmsSection"
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Timer")
                symbol: "hourglass_top"

                ClockSettingsRow {
                    first: true
                    symbol: "notifications"
                    title: Translation.tr("Notify when a timer ends")
                    Toggle {
                        target: root.time.timer
                        key: "notify"
                    }
                }
                ClockSettingsRow {
                    symbol: "volume_up"
                    title: Translation.tr("Timer sound")
                    Toggle {
                        target: root.sounds
                        key: "timer"
                    }
                }
                ClockSettingsRow {
                    last: (root.time.timer?.presets ?? []).length === 0
                    symbol: "bolt"
                    title: Translation.tr("Presets")
                    description: (root.time.timer?.presets ?? []).length === 0
                        ? Translation.tr("Save one from the keypad with the bookmark button")
                        : Translation.tr("Tap a preset to remove it")
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: (root.time.timer?.presets ?? []).length > 0
                    implicitHeight: presetFlow.implicitHeight + ClockStyle.gapLarge * 2
                    color: ClockStyle.colPane
                    bottomLeftRadius: ClockStyle.radiusLarge
                    bottomRightRadius: ClockStyle.radiusLarge
                    topLeftRadius: ClockStyle.radiusSmall / 2
                    topRightRadius: ClockStyle.radiusSmall / 2

                    Flow {
                        id: presetFlow
                        anchors {
                            fill: parent
                            margins: ClockStyle.gapLarge
                            leftMargin: ClockStyle.cardPadding
                        }
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: root.time.timer?.presets ?? []

                            ClockFormChip {
                                required property var modelData
                                required property int index
                                symbol: "close"
                                label: ClockFormat.shortDuration(modelData)
                                onTriggered: {
                                    const next = Array.from(root.time.timer.presets);
                                    next.splice(index, 1);
                                    root.time.timer.presets = next;
                                }
                            }
                        }
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Pomodoro")
                symbol: "timelapse"

                ClockSettingsRow {
                    first: true
                    symbol: "notifications"
                    title: Translation.tr("Notify on each phase")
                    Toggle {
                        target: root.time.pomodoro
                        key: "notify"
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "volume_up"
                    title: Translation.tr("Pomodoro sound")
                    Toggle {
                        target: root.sounds
                        key: "pomodoro"
                    }
                }
            }
        }
    }
}
