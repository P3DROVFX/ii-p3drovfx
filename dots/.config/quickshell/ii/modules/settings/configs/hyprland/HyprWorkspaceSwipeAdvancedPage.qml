pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Layout -> Advanced workspace swipe.
 *
 * When a swipe commits, direction locking, touchscreen behaviour and the rarer wrap options for
 * the touchpad workspace gesture - left off the Layout tab because the distance and direction
 * there cover what almost everyone actually tunes.
 */
HyprSubPage {
    title: Translation.tr("Advanced workspace swipe")
    subtitle: Translation.tr("Committing, direction lock, touchscreen and wrap-around")

    ContentSection {
        title: Translation.tr("Behaviour")
        icon: "swipe"

        HyprSlider {
            optionKey: "gestures:workspace_swipe_cancel_ratio"
            defaultValue: 0.5
            buttonIcon: "undo"
            text: Translation.tr("How far to swipe before it commits")
            tooltipContent: `${Math.round(value * 100)}%`
            from: 0
            to: 1
            stepSize: 0.05
        }

        HyprSlider {
            optionKey: "gestures:workspace_swipe_min_speed_to_force"
            defaultValue: 30
            integer: true
            buttonIcon: "bolt"
            text: Translation.tr("Speed that commits a swipe regardless")
            tooltipContent: value < 1 ? Translation.tr("Off") : `${Math.round(value)} px`
            from: 0
            to: 200
            stepSize: 1
        }

        HyprSwitch {
            optionKey: "gestures:workspace_swipe_create_new"
            defaultValue: true
            buttonIcon: "add"
            text: Translation.tr("Swiping past the last workspace makes a new one")
            textOn: Translation.tr("A swipe past the last workspace opens an empty one.")
            textOff: Translation.tr("A swipe stops at the last workspace.")
        }

        HyprSwitch {
            optionKey: "gestures:workspace_swipe_forever"
            buttonIcon: "all_inclusive"
            text: Translation.tr("Keep going past the next workspace in one swipe")
            textOn: Translation.tr("One long swipe can cross several workspaces.")
            textOff: Translation.tr("A swipe moves one workspace, however far it goes.")
        }

        HyprSwitch {
            optionKey: "gestures:workspace_swipe_use_r"
            buttonIcon: "tag"
            text: Translation.tr("Swipe through empty workspaces too")
            textOn: Translation.tr("A swipe counts every workspace of this screen, empty ones included.")
            textOff: Translation.tr("A swipe skips empty workspaces and moves between the ones in use.")
        }

        HyprOptionNote {
            keys: ["gestures:workspace_swipe_cancel_ratio", "gestures:workspace_swipe_min_speed_to_force",
                "gestures:workspace_swipe_create_new", "gestures:workspace_swipe_forever",
                "gestures:workspace_swipe_use_r"]
        }
    }

    ContentSection {
        title: Translation.tr("Direction lock")
        icon: "lock"

        HyprSwitch {
            optionKey: "gestures:workspace_swipe_direction_lock"
            defaultValue: true
            buttonIcon: "swipe_right"
            text: Translation.tr("Lock to the direction the swipe started in")
            textOn: Translation.tr("Once a swipe has started one way it cannot turn back the other.")
            textOff: Translation.tr("A swipe can change direction midway.")
        }

        HyprSlider {
            optionKey: "gestures:workspace_swipe_direction_lock_threshold"
            defaultValue: 10
            integer: true
            buttonIcon: "straighten"
            text: Translation.tr("Travel before the lock takes hold")
            tooltipContent: `${Math.round(value)} px`
            from: 0
            to: 200
            stepSize: 1
        }

        HyprOptionNote {
            keys: ["gestures:workspace_swipe_direction_lock",
                "gestures:workspace_swipe_direction_lock_threshold"]
        }
    }

    ContentSection {
        title: Translation.tr("Touchscreen")
        icon: "touch_app"

        HyprSwitch {
            optionKey: "gestures:workspace_swipe_touch"
            buttonIcon: "swipe"
            text: Translation.tr("Swipe workspaces from the edge of a touchscreen")
            textOn: Translation.tr("A swipe in from the edge of the screen switches workspace.")
            textOff: Translation.tr("Touchscreen swipes are left to the apps.")
        }

        HyprSwitch {
            optionKey: "gestures:workspace_swipe_touch_invert"
            buttonIcon: "swap_horiz"
            text: Translation.tr("Invert the touchscreen direction")
            textOn: Translation.tr("The workspaces move against your finger.")
            textOff: Translation.tr("The workspaces move with your finger.")
        }

        HyprOptionNote {
            keys: ["gestures:workspace_swipe_touch", "gestures:workspace_swipe_touch_invert"]
            notes: [{
                "icon": "info",
                "text": Translation.tr("Turning the swipe on and choosing how many fingers it takes is no longer a setting: since Hyprland 0.55 that is a gesture line, and the ones this config ships live in hyprland/general.lua. Everything here tunes a swipe that is already set up.")
            }]
        }
    }
}
