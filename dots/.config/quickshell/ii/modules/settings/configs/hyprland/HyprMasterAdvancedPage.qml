pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Layout -> More master settings.
 *
 * Everything about the master engine past the size, side and role of the master area - the
 * three things the diagram on the Layout tab draws.
 */
HyprSubPage {
    title: Translation.tr("More master settings")
    subtitle: Translation.tr("The stack, a centred master, dragging and the scratchpad")

    ContentSection {
        title: Translation.tr("Stack")
        icon: "view_list"

        HyprSwitch {
            optionKey: "master:new_on_top"
            buttonIcon: "vertical_align_top"
            text: Translation.tr("New windows join the top of the stack")
            textOn: Translation.tr("A new window goes to the top of the stack.")
            textOff: Translation.tr("A new window goes to the bottom of the stack.")
        }

        HyprSelect {
            optionKey: "master:new_on_active"
            defaultValue: "none"
            title: Translation.tr("Place new windows relative to the focused one")
            icon: "swap_vert"
            options: [
                { "displayName": Translation.tr("Before it"), "value": "before" },
                { "displayName": Translation.tr("After it"), "value": "after" },
                { "displayName": Translation.tr("Not at all"), "value": "none" }
            ]
        }

        HyprSwitch {
            optionKey: "master:allow_small_split"
            buttonIcon: "splitscreen_vertical_add"
            text: Translation.tr("Allow more than one master window")
            textOn: Translation.tr("Several windows can share the master area, split between them.")
            textOff: Translation.tr("The master area holds one window.")
        }

        HyprSwitch {
            optionKey: "master:always_keep_position"
            buttonIcon: "push_pin"
            text: Translation.tr("Keep the master in place when it is the only window")
            textOn: Translation.tr("A master left on its own keeps its size and side instead of filling the screen.")
            textOff: Translation.tr("A master left on its own fills the screen.")
        }

        HyprSwitch {
            optionKey: "master:focus_master_on_close"
            defaultValue: false
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Closing a window focuses the master")
            textOn: Translation.tr("When a window closes, focus goes to the master.")
            textOff: Translation.tr("When a window closes, focus goes to a neighbour, as it does elsewhere.")
        }

        HyprOptionNote {
            keys: ["master:new_on_top", "master:new_on_active", "master:allow_small_split",
                "master:always_keep_position", "master:focus_master_on_close"]
        }
    }

    ContentSection {
        title: Translation.tr("Centred master")
        icon: "align_horizontal_center"

        HyprSpinBox {
            optionKey: "master:slave_count_for_center_master"
            defaultValue: 2
            icon: "filter_2"
            text: Translation.tr("Windows in the stack before the master centres")
            from: 0
            to: 10
            stepSize: 1
        }

        HyprSelect {
            optionKey: "master:center_master_fallback"
            defaultValue: "left"
            title: Translation.tr("Until then, a centred master sits")
            icon: "west"
            options: [
                { "displayName": Translation.tr("Left"), "value": "left" },
                { "displayName": Translation.tr("Right"), "value": "right" },
                { "displayName": Translation.tr("Top"), "value": "top" },
                { "displayName": Translation.tr("Bottom"), "value": "bottom" }
            ]
        }

        HyprSwitch {
            optionKey: "master:center_ignores_reserved"
            buttonIcon: "crop_free"
            text: Translation.tr("A centred master ignores the bar")
            textOn: Translation.tr("A centred master is centred on the whole screen, bar included.")
            textOff: Translation.tr("A centred master is centred in the space the bar leaves.")
        }

        HyprOptionNote {
            keys: ["master:slave_count_for_center_master", "master:center_master_fallback",
                "master:center_ignores_reserved"]
        }
    }

    ContentSection {
        title: Translation.tr("Mouse drag")
        icon: "drag_pan"

        HyprSwitch {
            optionKey: "master:smart_resizing"
            defaultValue: true
            buttonIcon: "open_with"
            text: Translation.tr("Resize towards the edge the pointer is nearest")
            textOn: Translation.tr("Dragging with the resize shortcut moves whichever corner the pointer is nearest.")
            textOff: Translation.tr("Dragging with the resize shortcut always moves the bottom-right corner.")
        }

        HyprSwitch {
            optionKey: "master:drop_at_cursor"
            defaultValue: true
            buttonIcon: "drag_pan"
            text: Translation.tr("Drop a dragged window where the pointer is")
            textOn: Translation.tr("A dragged window lands where it is dropped.")
            textOff: Translation.tr("A dragged window dropped on the stack joins its top or bottom instead.")
        }

        HyprOptionNote {
            keys: ["master:smart_resizing", "master:drop_at_cursor"]
        }
    }

    ContentSection {
        title: Translation.tr("Scratchpad")
        icon: "photo_size_select_small"

        HyprSlider {
            optionKey: "master:special_scale_factor"
            defaultValue: 1
            buttonIcon: "photo_size_select_small"
            text: Translation.tr("Size of scratchpad windows")
            tooltipContent: `${Math.round(value * 100)}%`
            from: 0.3
            to: 1
            stepSize: 0.01
        }

        HyprOptionNote {
            keys: ["master:special_scale_factor"]
        }
    }
}
