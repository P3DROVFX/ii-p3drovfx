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
    property bool showShortcutHints: false
    property string sessionMode: ""
    signal modeRequested(string mode)

    function cycleMode(delta = 1) {
        const cur = Math.max(0, root.modes.indexOf(root.mode));
        const next = (cur + delta + root.modes.length) % root.modes.length;
        root.modeRequested(root.modes[next]);
    }

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
    readonly property string mode: root.modes.includes(root.sessionMode)
        ? root.sessionMode
        : root.modes.includes(Persistent.states.cheatsheet.timetableView)
        ? Persistent.states.cheatsheet.timetableView
        : "week"

    ToolbarTabBar {
        id: tabBar
        requestOnly: true
        showShortcutHints: root.showShortcutHints
        showShortcutNumbers: false
        currentIndex: Math.max(0, root.modes.indexOf(root.mode))
        tabButtonList: [
            {
                "icon": "calendar_view_day",
                "name": root.compact ? "" : Translation.tr("Day"),
                "shortcut": "⇧D"
            },
            {
                "icon": "view_column",
                "name": root.compact ? "" : Translation.tr("3 days"),
                "shortcut": "⇧3"
            },
            {
                "icon": "calendar_view_week",
                "name": root.compact ? "" : Translation.tr("Week"),
                "shortcut": "⇧W"
            },
            {
                "icon": "calendar_view_month",
                "name": root.compact ? "" : Translation.tr("Month"),
                "shortcut": "⇧M"
            }
        ]

        onIndexSelected: index => {
            root.modeRequested(root.modes[index]);
        }
    }
}
