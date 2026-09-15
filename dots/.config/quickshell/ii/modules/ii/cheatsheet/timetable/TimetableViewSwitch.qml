import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

/**
 * Day / three-day / week / month selector for the cheatsheet header.
 *
 * Lives outside the timetable so it reads as a header control next to the tab
 * bar, like the close button on the other side. `requestOnly` keeps the
 * persisted state the single source of truth — a two-way binding on
 * currentIndex is what makes a recreated tab bar snap to the wrong entry.
 */
Toolbar {
    id: root

    property bool animateIn: true
    property bool compact: false

    enableShadow: false
    opacity: root.animateIn ? 1 : 0
    transform: Translate {
        y: root.animateIn ? 0 : -20
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.OutCubic
        }
    }

    readonly property var modes: ["day", "threeDay", "week", "month"]
    readonly property string mode: root.modes.includes(Persistent.states.cheatsheet.timetableView)
        ? Persistent.states.cheatsheet.timetableView
        : "week"

    ToolbarTabBar {
        id: tabBar
        requestOnly: true
        currentIndex: Math.max(0, root.modes.indexOf(root.mode))
        tabButtonList: [
            {
                "icon": "calendar_view_day",
                "name": root.compact ? "" : Translation.tr("Day")
            },
            {
                "icon": "view_column",
                "name": root.compact ? "" : Translation.tr("3 days")
            },
            {
                "icon": "calendar_view_week",
                "name": root.compact ? "" : Translation.tr("Week")
            },
            {
                "icon": "calendar_view_month",
                "name": root.compact ? "" : Translation.tr("Month")
            }
        ]

        onIndexSelected: index => {
            Persistent.states.cheatsheet.timetableView = root.modes[index];
        }
    }
}
