pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Input -> Advanced cursor.
 *
 * Zoom, warping and hardware-cursor overrides: niche behaviour past "hide when idle" that
 * almost nobody needs to reach for. The cursor's theme and size live in the Environment tab,
 * since those are environment variables rather than compositor options.
 */
HyprSubPage {
    title: Translation.tr("Advanced cursor")
    subtitle: Translation.tr("Zoom, warping and hardware overrides")

    ContentSection {
        title: Translation.tr("Hiding & warping")
        icon: "my_location"

        HyprSwitch {
            optionKey: "cursor:hide_on_key_press"
            buttonIcon: "keyboard"
            text: Translation.tr("Hide while typing")
            textOn: Translation.tr("The cursor disappears at the first keystroke and comes back when the mouse moves.")
            textOff: Translation.tr("The cursor stays on screen while you type.")
        }

        HyprSwitch {
            optionKey: "cursor:hide_on_touch"
            defaultValue: true
            buttonIcon: "touch_app"
            text: Translation.tr("Hide when the screen is touched")
            textOn: Translation.tr("The cursor disappears when the screen is touched and comes back when the mouse moves.")
            textOff: Translation.tr("The cursor stays on screen while you touch it.")
        }

        HyprSwitch {
            optionKey: "cursor:no_warps"
            buttonIcon: "my_location"
            text: Translation.tr("Never move the cursor by itself")
            textOn: Translation.tr("The cursor stays where you left it, whatever gets focused.")
            textOff: Translation.tr("The cursor jumps to a window Hyprland focuses.")
        }

        HyprSwitch {
            optionKey: "cursor:persistent_warps"
            buttonIcon: "history"
            text: Translation.tr("Remember where the cursor was in each window")
            textOn: Translation.tr("A jump into a window lands where the cursor last was in it.")
            textOff: Translation.tr("A jump into a window lands in its middle.")
        }

        HyprSelect {
            optionKey: "cursor:warp_on_change_workspace"
            defaultValue: 0
            title: Translation.tr("Jump to the focused window when changing workspace")
            icon: "swap_horiz"
            options: [
                { "displayName": Translation.tr("No"), "value": 0 },
                { "displayName": Translation.tr("Yes"), "value": 1 },
                { "displayName": Translation.tr("Force"), "value": 2 }
            ]
        }

        HyprOptionNote {
            keys: ["cursor:hide_on_key_press", "cursor:hide_on_touch", "cursor:no_warps",
                "cursor:persistent_warps", "cursor:warp_on_change_workspace"]
        }
    }

    ContentSection {
        title: Translation.tr("Zoom & hardware")
        icon: "zoom_in"

        HyprSwitch {
            optionKey: "cursor:zoom_rigid"
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Zoom stays centred on the screen")
            textOn: Translation.tr("The zoomed view is fixed to the middle of the screen; the cursor moves within it.")
            textOff: Translation.tr("The zoomed view follows the cursor around.")
        }

        HyprSlider {
            optionKey: "cursor:zoom_factor"
            defaultValue: 1
            buttonIcon: "zoom_in"
            text: Translation.tr("Screen zoom")
            tooltipContent: `${value.toFixed(1)}×`
            from: 1
            to: 5
            stepSize: 0.1
            decimals: 1
        }

        HyprSelect {
            optionKey: "cursor:no_hardware_cursors"
            defaultValue: 2
            title: Translation.tr("Hardware cursor")
            icon: "memory"
            options: [
                { "displayName": Translation.tr("Use it"), "value": 0 },
                { "displayName": Translation.tr("Never"), "value": 1 },
                { "displayName": Translation.tr("Decide automatically"), "value": 2 }
            ]
        }

        HyprOptionNote {
            keys: ["cursor:zoom_rigid", "cursor:zoom_factor", "cursor:no_hardware_cursors"]
        }
    }
}
