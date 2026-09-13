pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Input -> Advanced mouse.
 *
 * Everything about the mouse past sensitivity and natural scrolling: focus-follows-pointer
 * tuning, scroll method, button swap. Left off the Input tab itself because almost nobody
 * changes these after the first time they get the pointer feeling right.
 */
HyprSubPage {
    title: Translation.tr("Advanced mouse")
    subtitle: Translation.tr("Focus, scrolling and button behaviour")

    ContentSection {
        title: Translation.tr("Buttons & scrolling")
        icon: "mouse"

        HyprSwitch {
            optionKey: "input:left_handed"
            buttonIcon: "back_hand"
            text: Translation.tr("Swap the mouse buttons")
            textOn: Translation.tr("The right button clicks and the left one opens menus.")
            textOff: Translation.tr("The left button clicks and the right one opens menus.")
        }

        HyprSwitch {
            optionKey: "input:force_no_accel"
            buttonIcon: "linear_scale"
            text: Translation.tr("Send raw movement, unaccelerated")
            textOn: Translation.tr("Movement reaches the screen exactly as the mouse reports it, as games and drawing prefer.")
            textOff: Translation.tr("Fast movements are accelerated by libinput, as the profile above decides.")
        }

        HyprSlider {
            optionKey: "input:scroll_factor"
            defaultValue: 1
            buttonIcon: "unfold_more"
            text: Translation.tr("Scroll distance")
            tooltipContent: `${value.toFixed(2)}×`
            from: 0.05
            to: 3
            stepSize: 0.05
        }

        HyprSwitch {
            optionKey: "input:scroll_button_lock"
            buttonIcon: "lock"
            text: Translation.tr("Scroll button stays held")
            textOn: Translation.tr("One press of the scroll button holds it down until the next press.")
            textOff: Translation.tr("The scroll button scrolls only while it is held.")
        }

        HyprSelect {
            optionKey: "input:scroll_method"
            title: Translation.tr("Scroll method")
            icon: "swipe_vertical"
            options: [
                { "displayName": Translation.tr("libinput default"), "value": "" },
                { "displayName": Translation.tr("Two fingers"), "value": "2fg" },
                { "displayName": Translation.tr("Edge"), "value": "edge" },
                { "displayName": Translation.tr("Hold a button"), "value": "on_button_down" },
                { "displayName": Translation.tr("Off"), "value": "no_scroll" }
            ]
        }

        HyprOptionNote {
            keys: ["input:left_handed", "input:force_no_accel", "input:scroll_factor",
                "input:scroll_button_lock", "input:scroll_method"]
        }
    }

    ContentSection {
        title: Translation.tr("Focus")
        icon: "ads_click"

        HyprSelect {
            optionKey: "input:follow_mouse"
            defaultValue: 1
            title: Translation.tr("Focus follows the pointer")
            icon: "ads_click"
            options: [
                { "displayName": Translation.tr("Never"), "value": 0 },
                { "displayName": Translation.tr("Always"), "value": 1 },
                { "displayName": Translation.tr("Detached"), "value": 2 },
                { "displayName": Translation.tr("Click to focus"), "value": 3 }
            ]
        }

        HyprSwitch {
            optionKey: "input:mouse_refocus"
            defaultValue: true
            buttonIcon: "center_focus_weak"
            text: Translation.tr("Moving the mouse can change focus")
            textOn: Translation.tr("Focus moves to the window under the pointer whenever the pointer is over another one.")
            textOff: Translation.tr("Focus moves only when the pointer crosses into another window.")
        }

        HyprSlider {
            optionKey: "input:follow_mouse_threshold"
            buttonIcon: "straighten"
            text: Translation.tr("Movement needed before focus follows")
            tooltipContent: `${Math.round(value)} px`
            from: 0
            to: 200
            stepSize: 5
        }

        HyprSelect {
            optionKey: "input:focus_on_close"
            title: Translation.tr("When a window closes, focus goes to")
            icon: "close"
            options: [
                { "displayName": Translation.tr("The next window"), "value": 0 },
                { "displayName": Translation.tr("Whatever is under the pointer"), "value": 1 }
            ]
        }

        HyprOptionNote {
            keys: ["input:follow_mouse", "input:mouse_refocus", "input:follow_mouse_threshold",
                "input:focus_on_close"]
        }
    }
}
