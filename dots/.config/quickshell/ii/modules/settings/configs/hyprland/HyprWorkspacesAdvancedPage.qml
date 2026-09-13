pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Layout -> More workspace settings.
 *
 * What switching workspaces does to the scratchpad and to pinned windows, and the two timing
 * thresholds behind the scroll-wheel and drag shortcuts.
 */
HyprSubPage {
    title: Translation.tr("More workspace settings")
    subtitle: Translation.tr("The scratchpad, pinned windows, scroll-wheel and drag thresholds")

    ContentSection {
        title: Translation.tr("Switching")
        icon: "dashboard"

        HyprSwitch {
            optionKey: "binds:hide_special_on_workspace_change"
            buttonIcon: "visibility_off"
            text: Translation.tr("Leaving a workspace hides the scratchpad")
            textOn: Translation.tr("The scratchpad closes when you switch workspace.")
            textOff: Translation.tr("The scratchpad stays open when you switch workspace.")
        }

        HyprSwitch {
            optionKey: "binds:allow_pin_fullscreen"
            buttonIcon: "push_pin"
            text: Translation.tr("A pinned window can go fullscreen")
            textOn: Translation.tr("A pinned window can go fullscreen, and is pinned again when it comes back.")
            textOff: Translation.tr("A pinned window cannot go fullscreen.")
        }

        HyprOptionNote {
            keys: ["binds:hide_special_on_workspace_change", "binds:allow_pin_fullscreen"]
        }
    }

    ContentSection {
        title: Translation.tr("Shortcut thresholds")
        icon: "timer"

        HyprSlider {
            optionKey: "binds:scroll_event_delay"
            defaultValue: 300
            integer: true
            buttonIcon: "mouse"
            text: Translation.tr("Wait between scroll shortcuts")
            tooltipContent: `${Math.round(value)} ms`
            from: 0
            to: 800
            stepSize: 10

            StyledToolTip {
                text: Translation.tr("How long a scroll-wheel shortcut ignores further scrolling. Lower it for a faster wheel, raise it if one flick skips several workspaces.")
            }
        }

        HyprSlider {
            optionKey: "binds:drag_threshold"
            defaultValue: 0
            integer: true
            buttonIcon: "drag_indicator"
            text: Translation.tr("Movement before a click becomes a drag")
            tooltipContent: value < 1 ? Translation.tr("Off") : `${Math.round(value)} px`
            from: 0
            to: 64
            stepSize: 1
        }

        HyprOptionNote {
            keys: ["binds:scroll_event_delay", "binds:drag_threshold"]
        }
    }
}
