pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Layout -> More dwindle settings.
 *
 * Everything about the dwindle engine past where a new window goes and how evenly it splits -
 * the two things the diagram on the Layout tab draws. What is here changes how the tree behaves
 * over time rather than where the next window lands.
 */
HyprSubPage {
    title: Translation.tr("More dwindle settings")
    subtitle: Translation.tr("Sideways splits, closing windows, dragging and the scratchpad")

    ContentSection {
        title: Translation.tr("Splitting")
        icon: "splitscreen"

        HyprSlider {
            optionKey: "dwindle:split_width_multiplier"
            defaultValue: 1
            buttonIcon: "aspect_ratio"
            text: Translation.tr("How wide before a window splits sideways")
            tooltipContent: `${value.toFixed(2)}×`
            from: 0.1
            to: 3
            stepSize: 0.05

            StyledToolTip {
                text: Translation.tr("A window splits side by side while it is wider than its height times this. Above 1 it takes an unusually wide window to split sideways; below 1, almost any window does.")
            }
        }

        HyprSwitch {
            optionKey: "dwindle:use_active_for_splits"
            defaultValue: true
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Split the focused window")
            textOn: Translation.tr("A new window splits the one that has focus.")
            textOff: Translation.tr("A new window splits whichever window is under the pointer.")
        }

        HyprSwitch {
            optionKey: "dwindle:preserve_split"
            buttonIcon: "lock"
            text: Translation.tr("Keep the split direction when a window closes")
            textOn: Translation.tr("The split a closing window leaves behind stays the way it was.")
            textOff: Translation.tr("The windows left behind re-split to suit their new shape.")
        }

        HyprSwitch {
            optionKey: "dwindle:permanent_direction_override"
            buttonIcon: "push_pin"
            text: Translation.tr("A preselected direction stays selected")
            textOn: Translation.tr("A direction chosen with layoutmsg preselect holds until you change it.")
            textOff: Translation.tr("A direction chosen with layoutmsg preselect applies to the next window only.")
        }

        HyprOptionNote {
            keys: ["dwindle:split_width_multiplier", "dwindle:use_active_for_splits",
                "dwindle:preserve_split", "dwindle:permanent_direction_override"]
        }
    }

    ContentSection {
        title: Translation.tr("Mouse drag")
        icon: "drag_pan"

        HyprSwitch {
            optionKey: "dwindle:smart_resizing"
            defaultValue: true
            buttonIcon: "open_with"
            text: Translation.tr("Resize towards the edge the pointer is nearest")
            textOn: Translation.tr("Dragging with the resize shortcut moves whichever corner the pointer is nearest.")
            textOff: Translation.tr("Dragging with the resize shortcut always moves the bottom-right corner.")
        }

        HyprSwitch {
            optionKey: "dwindle:precise_mouse_move"
            buttonIcon: "drag_pan"
            text: Translation.tr("Drop a dragged window exactly where the pointer is")
            textOn: Translation.tr("A dragged window lands on the side of the window it is dropped on that the pointer is nearest.")
            textOff: Translation.tr("A dragged window swaps places with the window it is dropped on.")
        }

        HyprOptionNote {
            keys: ["dwindle:smart_resizing", "dwindle:precise_mouse_move"]
        }
    }

    ContentSection {
        title: Translation.tr("Scratchpad")
        icon: "photo_size_select_small"

        HyprSlider {
            optionKey: "dwindle:special_scale_factor"
            defaultValue: 1
            buttonIcon: "photo_size_select_small"
            text: Translation.tr("Size of scratchpad windows")
            tooltipContent: `${Math.round(value * 100)}%`
            from: 0.3
            to: 1
            stepSize: 0.01
        }

        HyprOptionNote {
            keys: ["dwindle:special_scale_factor"]
        }
    }
}
