pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Reminders' own settings in the clock settings page — Samsung Reminder's Alert type,
 * Alert background and sounds, plus what a desktop adds: the all-day alert time, waking
 * from suspend, and how long completed and binned reminders are kept.
 */
ClockSettingsSection {
    id: root

    readonly property var options: Config.options.clockApp.reminders

    function daysLabel(value: int): string {
        return value === 1 ? Translation.tr("1 day") : Translation.tr("%1 days").arg(String(value));
    }

    function minutesLabel(value: int): string {
        return Translation.tr("%1 min").arg(String(value));
    }

    component Toggle: StyledSwitch {
        property string key
        checked: Boolean(root.options?.[key])
        checkable: false
        onClicked: root.options[key] = !root.options[key]
    }

    component Panel: Rectangle {
        default property alias content: panelFlow.data
        Layout.fillWidth: true
        implicitHeight: panelFlow.implicitHeight + ClockStyle.gapLarge * 2
        color: ClockStyle.colPane
        radius: ClockStyle.radiusSmall / 2

        Flow {
            id: panelFlow
            anchors {
                fill: parent
                margins: ClockStyle.gapLarge
                leftMargin: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gapSmall
        }
    }

    title: Translation.tr("Reminders")
    symbol: "task_alt"

    ClockSettingsRow {
        first: true
        symbol: "notifications_active"
        title: Translation.tr("Alert type")
        description: RemindersStyle.alertLevel(RemindersService.defaultAlert).description
    }
    Panel {
        Repeater {
            model: RemindersStyle.alertLevels

            ClockFormChip {
                required property var modelData
                symbol: modelData.icon
                label: modelData.label
                selected: RemindersService.defaultAlert === modelData.id
                onTriggered: root.options.defaultAlert = modelData.id
            }
        }
    }
    ClockSettingsRow {
        symbol: "wallpaper"
        title: Translation.tr("Alert background")
        description: (root.options.alertBackgroundImage ?? "").length > 0
            ? root.options.alertBackgroundImage.slice(root.options.alertBackgroundImage.lastIndexOf("/") + 1)
            : Translation.tr("Behind full-screen reminder alerts")
    }
    Panel {
        Swatch {
            swatch: ""
        }

        Repeater {
            model: RemindersStyle.palette

            Swatch {
                required property string modelData
                swatch: modelData
            }
        }

        ClockChip {
            symbol: "image"
            label: (root.options.alertBackgroundImage ?? "").length > 0 ? Translation.tr("Change image") : Translation.tr("Image")
            selected: (root.options.alertBackgroundImage ?? "").length > 0
            onClicked: imageDialog.active = true
        }

        ClockChip {
            visible: (root.options.alertBackgroundImage ?? "").length > 0
            symbol: "close"
            label: Translation.tr("No image")
            onClicked: root.options.alertBackgroundImage = ""
        }
    }
    ClockSettingsRow {
        symbol: "volume_up"
        title: Translation.tr("Alert sound")
        description: Translation.tr("Medium and Strong ring with the alarm sound")
        Toggle {
            key: "alertSound"
        }
    }
    ClockSettingsRow {
        symbol: "snooze"
        title: Translation.tr("Snooze length")
        ClockStepper {
            value: RemindersService.snoozeMinutes
            from: 1
            to: 60
            format: value => root.minutesLabel(value)
            onMoved: value => root.options.snoozeMinutes = value
        }
    }
    ClockSettingsRow {
        symbol: "notifications_paused"
        title: Translation.tr("Silence after")
        description: Translation.tr("A Strong alert nobody answers turns into a notification")
        ClockStepper {
            value: RemindersService.autoSilenceMinutes
            from: 0
            to: 10
            format: value => value === 0 ? Translation.tr("Never") : root.minutesLabel(value)
            onMoved: value => root.options.autoSilenceMinutes = value
        }
    }
    ClockSettingsRow {
        symbol: "wb_sunny"
        title: Translation.tr("All-day reminders alert at")
        ClockStepper {
            value: parseInt(RemindersService.allDayTime.split(":")[0]) || 0
            from: 0
            to: 23
            format: value => ClockFormat.alarmTime(ClockFormat.pad(value) + ":00")
            onMoved: value => root.options.allDayTime = ClockFormat.pad(value) + ":00"
        }
    }
    ClockSettingsRow {
        symbol: "power_settings_new"
        title: Translation.tr("Wake from suspend")
        description: Translation.tr("Wakes a sleeping computer for Medium and Strong reminders")
        Toggle {
            key: "wakeFromSuspend"
        }
    }
    ClockSettingsRow {
        symbol: "history"
        title: Translation.tr("Alert late reminders")
        description: Translation.tr("Missed by more than this while asleep, a reminder only leaves a notification")
        ClockStepper {
            value: RemindersService.catchUpMinutes
            from: 0
            to: 60
            stepSize: 5
            format: value => value === 0 ? Translation.tr("Never") : root.minutesLabel(value)
            onMoved: value => root.options.catchUpMinutes = value
        }
    }
    ClockSettingsRow {
        symbol: "auto_delete"
        title: Translation.tr("Delete completed reminders")
        description: Translation.tr("Moves them to the recycle bin after this long")
        ClockStepper {
            value: RemindersService.autoDeleteCompletedDays
            from: 0
            to: 90
            format: value => value === 0 ? Translation.tr("Never") : root.daysLabel(value)
            onMoved: value => root.options.autoDeleteCompletedDays = value
        }
    }
    ClockSettingsRow {
        symbol: "delete"
        title: Translation.tr("Recycle bin keeps")
        ClockStepper {
            value: RemindersService.trashDays
            from: 0
            to: 90
            format: value => value === 0 ? Translation.tr("Forever") : root.daysLabel(value)
            onMoved: value => root.options.trashDays = value
        }
    }
    ClockSettingsRow {
        symbol: "calendar_month"
        title: Translation.tr("Show in the timetable")
        description: Translation.tr("Timed reminders appear on their day")
        Toggle {
            key: "showInTimetable"
        }
    }
    ClockSettingsRow {
        last: true
        symbol: "lightbulb"
        title: Translation.tr("Suggest templates")
        description: Translation.tr("The \"Try these out\" cards on the Reminders home")
        Toggle {
            key: "showTemplates"
        }
    }

    // Kept out of the rows' layout: a dialog has no place in the column.
    Loader {
        id: imageDialog
        visible: false
        active: false
        sourceComponent: FileDialog {
            title: Translation.tr("Alert background")
            nameFilters: [Translation.tr("Images (*.png *.jpg *.jpeg *.webp *.avif)")]
            onAccepted: {
                const path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
                RemindersService.importImage(path, copy => {
                    if (copy.length > 0)
                        root.options.alertBackgroundImage = copy;
                });
                imageDialog.active = false;
            }
            onRejected: imageDialog.active = false
            Component.onCompleted: open()
        }
    }

    component Swatch: Rectangle {
        id: swatchItem
        property string swatch: ""
        readonly property color fill: swatchItem.swatch.length > 0 ? swatchItem.swatch : ClockStyle.colSurfaceHighest
        readonly property bool on: (root.options.alertBackgroundColor ?? "") === swatchItem.swatch

        width: 34
        height: 34
        radius: swatchItem.on ? ClockStyle.radiusSmall : 17
        color: swatchItem.fill
        border.width: swatchItem.on ? 3 : 1
        border.color: swatchItem.on ? ClockStyle.colOnSurface : ClockStyle.colOutline

        MaterialSymbol {
            anchors.centerIn: parent
            visible: swatchItem.on || swatchItem.swatch.length === 0
            text: swatchItem.on ? "check" : "palette"
            iconSize: 17
            color: swatchItem.swatch.length > 0 ? RemindersStyle.onColor(swatchItem.fill) : ClockStyle.colOnSurfaceVariant
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.options.alertBackgroundColor = swatchItem.swatch
        }
    }
}
