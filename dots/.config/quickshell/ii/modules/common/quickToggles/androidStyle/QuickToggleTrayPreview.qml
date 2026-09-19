pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A widget tile as it appears in the tray: its icon and its name, drawn once.
 *
 * The tray builds every tile that is not on the grid, and the widget tiles are the
 * expensive ones - a calendar, a task list, a media card or a notification list, each
 * with its services, its lists and its timers, none of which says anything useful at
 * tray size. Standing in for them here is what keeps opening edit mode cheap, and keeps
 * it from getting slower as more widgets are added to the catalog.
 *
 * It is a real tile (see AndroidWidgetTileBase), so it drags to the grid, carries the
 * add badge and packs exactly like the widget it stands for. The live widget is built
 * when it lands on the grid.
 */
AndroidWidgetTileBase {
    id: root

    /** Icon and name per widget type; a type not listed falls back to a generic one. */
    readonly property var meta: ({
        mediaWidget: { icon: "music_note", label: Translation.tr("Media") },
        calendarWidget: { icon: "calendar_month", label: Translation.tr("Calendar") },
        tasksWidget: { icon: "task_alt", label: Translation.tr("Tasks") },
        timerWidget: { icon: "timer", label: Translation.tr("Timer") },
        countdownWidget: { icon: "hourglass_top", label: Translation.tr("Countdown") },
        pomodoroWidget: { icon: "search_activity", label: Translation.tr("Pomodoro") },
        fullCalendarWidget: { icon: "calendar_month", label: Translation.tr("Calendar") },
        fullTasksWidget: { icon: "task_alt", label: Translation.tr("Tasks") },
        fullTimerWidget: { icon: "timer", label: Translation.tr("Timer") },
        fullCountdownWidget: { icon: "hourglass_top", label: Translation.tr("Countdown") },
        fullPomodoroWidget: { icon: "search_activity", label: Translation.tr("Pomodoro") },
        fullNotesWidget: { icon: "sticky_note_2", label: Translation.tr("Notes") },
        clockWidget: { icon: "schedule", label: Translation.tr("Clock") },
        iosClockWidget: { icon: "schedule", label: Translation.tr("Clock") },
        notificationListWidget: { icon: "notifications", label: Translation.tr("Notifications") },
        weatherIconShape: { icon: "partly_cloudy_day", label: Translation.tr("Weather") },
        weatherCard: { icon: "partly_cloudy_day", label: Translation.tr("Weather") }
    })
    readonly property var entry: root.meta[root.buttonData.type]
        ?? ({ icon: "widgets", label: root.buttonData.type })

    tooltipText: root.entry.label

    /** Side by side when the tile is too short for a column. */
    readonly property bool stacked: root.surface.height >= 70

    Column {
        anchors.centerIn: parent
        spacing: 4
        visible: root.stacked

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.entry.icon
            iconSize: Appearance.font.pixelSize.hugeass
            color: Appearance.colors.colOnLayer2
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.surface.width - 12)
            horizontalAlignment: Text.AlignHCenter
            text: root.entry.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer2
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 6
        visible: !root.stacked

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: root.entry.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer2
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.surface.width - 40)
            text: root.entry.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer2
        }
    }
}
