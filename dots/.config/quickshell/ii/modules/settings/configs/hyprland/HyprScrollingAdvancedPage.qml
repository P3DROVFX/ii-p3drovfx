pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Layout -> More scrolling settings.
 *
 * Everything about the scrolling engine past the width and side of a new column and what
 * happens at the ends of the row.
 */
HyprSubPage {
    title: Translation.tr("More scrolling settings")
    subtitle: Translation.tr("A lone column, following focus and preset widths")

    ContentSection {
        title: Translation.tr("Columns")
        icon: "view_column"

        HyprSwitch {
            optionKey: "scrolling:fullscreen_on_one_column"
            defaultValue: true
            buttonIcon: "fullscreen"
            text: Translation.tr("A single column fills the screen")
            textOn: Translation.tr("A column with nothing beside it stretches to the full width.")
            textOff: Translation.tr("A column with nothing beside it keeps its own width.")
        }

        HyprTextField {
            optionKey: "scrolling:explicit_column_widths"
            defaultValue: "0.333, 0.5, 0.667, 1.0"
            icon: "format_list_numbered"
            text: Translation.tr("Preset column widths")
            placeholderText: "0.333, 0.5, 0.667, 1.0"
            tooltip: Translation.tr("The widths the layoutmsg colresize +conf and -conf messages cycle through, as fractions of the screen.")
        }

        HyprOptionNote {
            keys: ["scrolling:fullscreen_on_one_column", "scrolling:explicit_column_widths"]
        }
    }

    ContentSection {
        title: Translation.tr("Following focus")
        icon: "center_focus_weak"

        HyprSwitch {
            optionKey: "scrolling:follow_focus"
            defaultValue: true
            buttonIcon: "center_focus_weak"
            text: Translation.tr("Scroll to the focused window automatically")
            textOn: Translation.tr("The row scrolls so that the focused window is in view.")
            textOff: Translation.tr("The row stays put; focus can sit off the edge of the screen.")
        }

        HyprSlider {
            optionKey: "scrolling:follow_min_visible"
            defaultValue: 0.4
            buttonIcon: "visibility"
            text: Translation.tr("How much of a window must show before it counts as visible")
            tooltipContent: `${Math.round(value * 100)}%`
            from: 0
            to: 1
            stepSize: 0.05
        }

        HyprSelect {
            optionKey: "scrolling:focus_fit_method"
            defaultValue: 1
            title: Translation.tr("Bring a focused column into view by")
            icon: "fit_screen"
            options: [
                { "displayName": Translation.tr("Centring it"), "value": 0 },
                { "displayName": Translation.tr("Scrolling the least it can"), "value": 1 }
            ]
        }

        HyprOptionNote {
            keys: ["scrolling:follow_focus", "scrolling:follow_min_visible",
                "scrolling:focus_fit_method"]
        }
    }
}
