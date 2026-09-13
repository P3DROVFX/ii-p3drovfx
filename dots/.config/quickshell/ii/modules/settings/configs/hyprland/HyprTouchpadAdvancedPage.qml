pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Input -> Advanced touchpad.
 *
 * Gestures and click-mapping past tap-to-click and natural scrolling. Left off the Input tab
 * itself because almost nobody changes these after the first time they get the touchpad
 * feeling right.
 */
HyprSubPage {
    title: Translation.tr("Advanced touchpad")
    subtitle: Translation.tr("Gestures, clicks and orientation")

    ContentSection {
        title: Translation.tr("Gestures")
        icon: "gesture"

        HyprSwitch {
            optionKey: "input:touchpad:tap_and_drag"
            defaultValue: true
            buttonIcon: "drag_pan"
            text: Translation.tr("Tap then drag to move things")
            textOn: Translation.tr("Tap, then touch again and move, to drag.")
            textOff: Translation.tr("Dragging needs the pad held down.")
        }

        HyprSelect {
            optionKey: "input:touchpad:drag_lock"
            defaultValue: 0
            title: Translation.tr("Drag lock")
            icon: "lock_open"
            options: [
                { "displayName": Translation.tr("Off"), "value": 0 },
                { "displayName": Translation.tr("Until a timeout"), "value": 1 },
                { "displayName": Translation.tr("Until the next tap"), "value": 2 }
            ]
        }

        HyprSelect {
            optionKey: "input:touchpad:drag_3fg"
            defaultValue: 0
            title: Translation.tr("Three-finger drag")
            icon: "3d_rotation"
            options: [
                { "displayName": Translation.tr("Off"), "value": 0 },
                { "displayName": Translation.tr("Three fingers"), "value": 1 },
                { "displayName": Translation.tr("Four fingers"), "value": 2 }
            ]
        }

        HyprSlider {
            optionKey: "input:touchpad:scroll_factor"
            defaultValue: 1
            buttonIcon: "unfold_more"
            text: Translation.tr("Scroll distance")
            tooltipContent: `${value.toFixed(2)}×`
            from: 0.05
            to: 3
            stepSize: 0.05
        }

        HyprOptionNote {
            keys: ["input:touchpad:tap-and-drag", "input:touchpad:drag_lock",
                "input:touchpad:drag_3fg", "input:touchpad:scroll_factor"]
        }
    }

    ContentSection {
        title: Translation.tr("Clicks & orientation")
        icon: "touch_app"

        HyprSwitch {
            optionKey: "input:touchpad:clickfinger_behavior"
            buttonIcon: "pinch"
            text: Translation.tr("Right click with two fingers anywhere")
            textOn: Translation.tr("Two fingers click right and three click middle, wherever they land on the pad.")
            textOff: Translation.tr("The button areas at the bottom of the pad decide which click you get.")
        }

        HyprSwitch {
            optionKey: "input:touchpad:middle_button_emulation"
            buttonIcon: "adjust"
            text: Translation.tr("Both buttons at once is a middle click")
            textOn: Translation.tr("Pressing the left and right buttons together is a middle click.")
            textOff: Translation.tr("Pressing both buttons together is just two clicks.")
        }

        HyprSelect {
            optionKey: "input:touchpad:tap_button_map"
            title: Translation.tr("Two and three finger taps")
            icon: "touch_app"
            options: [
                { "displayName": Translation.tr("libinput default"), "value": "" },
                { "displayName": Translation.tr("Right, then middle"), "value": "lrm" },
                { "displayName": Translation.tr("Middle, then right"), "value": "lmr" }
            ]
        }

        HyprSwitch {
            optionKey: "input:touchpad:flip_x"
            buttonIcon: "flip"
            text: Translation.tr("Flip horizontally")
            textOn: Translation.tr("Left and right on the pad are swapped.")
            textOff: Translation.tr("Left on the pad is left on the screen.")
        }

        HyprSwitch {
            optionKey: "input:touchpad:flip_y"
            buttonIcon: "flip_camera_android"
            text: Translation.tr("Flip vertically")
            textOn: Translation.tr("Up and down on the pad are swapped.")
            textOff: Translation.tr("Up on the pad is up on the screen.")
        }

        HyprOptionNote {
            keys: ["input:touchpad:clickfinger_behavior", "input:touchpad:middle_button_emulation",
                "input:touchpad:tap_button_map", "input:touchpad:flip_x", "input:touchpad:flip_y"]
        }
    }
}
