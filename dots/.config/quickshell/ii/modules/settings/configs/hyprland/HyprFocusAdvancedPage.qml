pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Layout -> More focus settings.
 *
 * How the move-focus shortcuts pick their target once the everyday cases - an app asking for
 * attention, the edge of a screen - are handled on the Layout tab.
 */
HyprSubPage {
    title: Translation.tr("More focus settings")
    subtitle: Translation.tr("Which neighbour is picked, fullscreen and groups")

    ContentSection {
        title: Translation.tr("Moving focus")
        icon: "center_focus_strong"

        HyprSelect {
            optionKey: "binds:focus_preferred_method"
            defaultValue: 0
            title: Translation.tr("Moving focus in a direction picks")
            icon: "open_in_full"
            options: [
                { "displayName": Translation.tr("The nearest window"), "value": 0 },
                { "displayName": Translation.tr("The one sharing the longest edge"), "value": 1 }
            ]
        }

        HyprSwitch {
            optionKey: "binds:movefocus_cycles_fullscreen"
            buttonIcon: "fullscreen"
            text: Translation.tr("Move focus while fullscreen instead of leaving it")
            textOn: Translation.tr("While a window is fullscreen, moving focus cycles through the others, whichever direction you press.")
            textOff: Translation.tr("While a window is fullscreen, moving focus hands fullscreen to the window in that direction.")
        }

        HyprOptionNote {
            keys: ["binds:focus_preferred_method", "binds:movefocus_cycles_fullscreen"]
        }
    }

    ContentSection {
        title: Translation.tr("Groups")
        icon: "tab_group"

        HyprSwitch {
            optionKey: "binds:movefocus_cycles_groupfirst"
            buttonIcon: "tab_group"
            text: Translation.tr("Move through a group before leaving it")
            textOn: Translation.tr("Moving focus walks the tabs of a group before it moves on to the next window.")
            textOff: Translation.tr("Moving focus leaves a group straight away; its tabs are reached with the group shortcuts.")
        }

        HyprSwitch {
            optionKey: "binds:ignore_group_lock"
            buttonIcon: "lock_open"
            text: Translation.tr("Group shortcuts ignore a locked group")
            textOn: Translation.tr("Windows can be moved into and out of a group even while it is locked.")
            textOff: Translation.tr("A locked group keeps its windows and takes no new ones.")
        }

        HyprOptionNote {
            keys: ["binds:movefocus_cycles_groupfirst", "binds:ignore_group_lock"]
        }
    }
}
