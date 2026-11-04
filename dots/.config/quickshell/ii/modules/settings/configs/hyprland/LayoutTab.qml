pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Layout.
 *
 * The tiling engine and everything that follows from it, plus the focus and workspace rules that
 * decide where attention goes once the windows are placed.
 *
 * Only the engine that is actually running gets a section, because the four of them share almost
 * no options and showing all four at once would be four times the page for no gain. The diagram
 * at the top is the point of the tab: it runs the same arithmetic the layout does and draws where
 * the next window lands, so the options stop being folklore.
 *
 * Each section keeps the two or three settings people come back to - for an engine, the ones the
 * diagram draws - and ends with a door to the rest. The door says what is behind it and how many
 * of those settings have been changed, so nothing is hidden, only put away.
 */
ContentPage {
    id: tab

    forceWidth: false

    /// The "More …" doors at the end of each section are what advanced mode is for: each one is
    /// a page of settings that exist because Hyprland has them, not because anybody asked.
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    readonly property string engine:
        String(HyprlandGui.displayValue("general:layout", "dwindle") ?? "dwindle")
    readonly property bool knownEngine:
        ["dwindle", "master", "scrolling", "lua:zscroll", "monocle"].includes(tab.engine)

    /// zscroll's settings are Lua globals (custom/variables.lua) that its layout reads on every
    /// pass, not Hyprland options - there is nothing for hyprctl to report.
    function zscrollOn(name: string, fallback: bool): bool {
        const value = HyprlandGui.globalValue(name, fallback);
        return value === true || value === 1 || value === "true";
    }
    function zscrollNumber(name: string, fallback: real): real {
        const value = Number(HyprlandGui.globalValue(name, fallback));
        return isNaN(value) ? fallback : value;
    }

    /// A bool option as the hub shows it: what this page set, else what Hyprland reports.
    function isOn(key: string, fallback: bool): bool {
        const value = HyprlandGui.displayValue(key, fallback);
        return value === true || value === 1;
    }

    ContentSection {
        title: Translation.tr("Tiling engine")
        icon: "view_quilt"

        HyprSelect {
            optionKey: "general:layout"
            defaultValue: "dwindle"
            title: Translation.tr("How windows are arranged")
            icon: "grid_view"
            options: [
                { "displayName": Translation.tr("Dwindle"), "icon": "splitscreen", "value": "dwindle" },
                { "displayName": Translation.tr("Master"), "icon": "view_sidebar", "value": "master" },
                { "displayName": Translation.tr("Scrolling"), "icon": "view_carousel", "value": "scrolling" },
                { "displayName": Translation.tr("Rows (zscroll)"), "icon": "view_agenda", "value": "lua:zscroll" },
                { "displayName": Translation.tr("Monocle"), "icon": "crop_square", "value": "monocle" }
            ]
        }

        ContentSubsection {
            title: Translation.tr("Where the next window lands")
            icon: "preview"
            Layout.fillWidth: true

            HyprLayoutPreview {
                engine: tab.engine
            }
        }

        HyprOptionNote {
            keys: ["general:layout"]
            notes: tab.knownEngine ? [] : [{
                "icon": "help",
                "text": Translation.tr("The layout in use is \"%1\", which is neither built in nor drawn here. A Lua layout is written as lua:<name>.").arg(tab.engine)
            }]
        }
    }

    Loader {
        active: tab.engine === "dwindle"
        visible: active
        Layout.fillWidth: true

        sourceComponent: ContentSection {
            title: Translation.tr("Dwindle")
            icon: "splitscreen"

            HyprSelect {
                id: dwindlePlacement

                // Two keys, one decision. smart_split takes the quarter the pointer is in and
                // overrides force_split while it is on, so it is a fourth answer to the same
                // question - as a switch of its own it needed a footnote to say so.
                readonly property bool smart: tab.isOn("dwindle:smart_split", false)
                readonly property int side: Number(HyprlandGui.displayValue("dwindle:force_split", 0)) || 0

                keys: ["dwindle:force_split", "dwindle:smart_split"]
                title: Translation.tr("Where a new window goes")
                icon: "flip"
                currentOverride: dwindlePlacement.smart ? "quarter"
                    : (["pointer", "left", "right"][dwindlePlacement.side] ?? "pointer")
                options: [
                    { "displayName": Translation.tr("The side the pointer is on"), "value": "pointer" },
                    { "displayName": Translation.tr("Left or top"), "value": "left" },
                    { "displayName": Translation.tr("Right or bottom"), "value": "right" },
                    { "displayName": Translation.tr("The quarter nearest the pointer"), "value": "quarter" }
                ]
                onSelected: newValue => HyprlandGui.batch(() => {
                    HyprlandGui.setKey("dwindle:smart_split", newValue === "quarter");
                    if (newValue !== "quarter")
                        HyprlandGui.setKey("dwindle:force_split", ({ "pointer": 0, "left": 1, "right": 2 })[newValue] ?? 0);
                })
            }

            HyprSlider {
                id: splitRatioSlider

                optionKey: "dwindle:default_split_ratio"
                defaultValue: 1
                buttonIcon: "straighten"
                text: Translation.tr("How evenly a window splits")
                // Hyprland spells this as a 0.1-1.9 number where 1 is even; what it means to
                // anyone looking at it is the share the first side takes.
                readonly property int firstShare:
                    Math.round(Math.max(0.08, Math.min(0.92, value / 2)) * 100)
                tooltipContent: `${splitRatioSlider.firstShare}% / ${100 - splitRatioSlider.firstShare}%`
                from: 0.1
                to: 1.9
                stepSize: 0.05
            }

            HyprSelect {
                optionKey: "dwindle:split_bias"
                defaultValue: 0
                title: Translation.tr("Which window keeps that share")
                icon: "balance"
                options: [
                    { "displayName": Translation.tr("The left or top one"), "value": 0 },
                    { "displayName": Translation.tr("The one already open"), "value": 1 }
                ]
            }

            HyprNavRow {
                visible: tab.advanced
                buttonIcon: "tune"
                text: Translation.tr("More dwindle settings")
                description: Translation.tr("Sideways splits, what a closing window leaves behind, dragging, scratchpad size")
                keys: ["dwindle:split_width_multiplier", "dwindle:preserve_split",
                    "dwindle:use_active_for_splits", "dwindle:permanent_direction_override",
                    "dwindle:smart_resizing", "dwindle:precise_mouse_move",
                    "dwindle:special_scale_factor"]
                configPage: Qt.resolvedUrl("HyprDwindleAdvancedPage.qml")
            }

            HyprOptionNote {
                keys: ["dwindle:force_split", "dwindle:smart_split", "dwindle:default_split_ratio",
                    "dwindle:split_bias"]
            }
        }
    }

    Loader {
        active: tab.engine === "master"
        visible: active
        Layout.fillWidth: true

        sourceComponent: ContentSection {
            title: Translation.tr("Master")
            icon: "view_sidebar"

            HyprSlider {
                optionKey: "master:mfact"
                defaultValue: 0.55
                buttonIcon: "width_normal"
                text: Translation.tr("Size of the master area")
                tooltipContent: `${Math.round(value * 100)}%`
                from: 0.1
                to: 0.9
                stepSize: 0.01
            }

            HyprSelect {
                optionKey: "master:orientation"
                defaultValue: "left"
                title: Translation.tr("Where the master area sits")
                icon: "align_horizontal_left"
                options: [
                    { "displayName": Translation.tr("Left"), "value": "left" },
                    { "displayName": Translation.tr("Right"), "value": "right" },
                    { "displayName": Translation.tr("Top"), "value": "top" },
                    { "displayName": Translation.tr("Bottom"), "value": "bottom" },
                    { "displayName": Translation.tr("Centre"), "value": "center" }
                ]
            }

            HyprSelect {
                optionKey: "master:new_status"
                defaultValue: "slave"
                title: Translation.tr("A new window becomes")
                icon: "add_box"
                options: [
                    { "displayName": Translation.tr("The master"), "value": "master" },
                    { "displayName": Translation.tr("Part of the stack"), "value": "slave" },
                    { "displayName": Translation.tr("Whatever the focused one is"), "value": "inherit" }
                ]
            }

            HyprNavRow {
                visible: tab.advanced
                buttonIcon: "tune"
                text: Translation.tr("More master settings")
                description: Translation.tr("Stack order, several masters, a centred master, dragging, scratchpad size")
                keys: ["master:new_on_top", "master:new_on_active", "master:allow_small_split",
                    "master:always_keep_position", "master:focus_master_on_close",
                    "master:slave_count_for_center_master", "master:center_master_fallback",
                    "master:center_ignores_reserved", "master:smart_resizing", "master:drop_at_cursor",
                    "master:special_scale_factor"]
                configPage: Qt.resolvedUrl("HyprMasterAdvancedPage.qml")
            }

            HyprOptionNote {
                keys: ["master:mfact", "master:orientation", "master:new_status"]
            }
        }
    }

    Loader {
        active: tab.engine === "scrolling"
        visible: active
        Layout.fillWidth: true

        sourceComponent: ContentSection {
            title: Translation.tr("Scrolling")
            icon: "view_carousel"

            HyprSlider {
                optionKey: "scrolling:column_width"
                defaultValue: 0.5
                buttonIcon: "width_normal"
                text: Translation.tr("Width of a new column")
                tooltipContent: `${Math.round(value * 100)}%`
                from: 0.1
                to: 1
                stepSize: 0.01
            }

            HyprSelect {
                optionKey: "scrolling:direction"
                defaultValue: "right"
                title: Translation.tr("New columns appear on the")
                icon: "swap_horiz"
                options: [
                    { "displayName": Translation.tr("Right"), "value": "right" },
                    { "displayName": Translation.tr("Left"), "value": "left" }
                ]
            }

            HyprSelect {
                id: scrollingWrap

                // Two switches that read as one question: what happens at the end of the row.
                readonly property bool focusWraps: tab.isOn("scrolling:wrap_focus", true)
                readonly property bool movingWraps: tab.isOn("scrolling:wrap_swapcol", true)

                keys: ["scrolling:wrap_focus", "scrolling:wrap_swapcol"]
                title: Translation.tr("Wrap around at the ends of the row")
                icon: "loop"
                currentOverride: scrollingWrap.focusWraps
                    ? (scrollingWrap.movingWraps ? "both" : "focus")
                    : (scrollingWrap.movingWraps ? "moving" : "never")
                options: [
                    { "displayName": Translation.tr("Never"), "value": "never" },
                    { "displayName": Translation.tr("Focus only"), "value": "focus" },
                    { "displayName": Translation.tr("Focus and moving"), "value": "both" },
                    { "displayName": Translation.tr("Moving only"), "value": "moving" }
                ]
                onSelected: newValue => HyprlandGui.batch(() => {
                    HyprlandGui.setKey("scrolling:wrap_focus", newValue === "focus" || newValue === "both");
                    HyprlandGui.setKey("scrolling:wrap_swapcol", newValue === "both" || newValue === "moving");
                })
            }

            HyprNavRow {
                visible: tab.advanced
                buttonIcon: "tune"
                text: Translation.tr("More scrolling settings")
                description: Translation.tr("A lone column, following focus, preset widths")
                keys: ["scrolling:fullscreen_on_one_column", "scrolling:follow_focus",
                    "scrolling:follow_min_visible", "scrolling:focus_fit_method",
                    "scrolling:explicit_column_widths"]
                configPage: Qt.resolvedUrl("HyprScrollingAdvancedPage.qml")
            }

            HyprOptionNote {
                keys: ["scrolling:column_width", "scrolling:direction", "scrolling:wrap_focus",
                    "scrolling:wrap_swapcol"]
            }
        }
    }

    Loader {
        active: tab.engine === "lua:zscroll"
        visible: active
        Layout.fillWidth: true

        sourceComponent: ContentSection {
            title: Translation.tr("Rows (zscroll)")
            icon: "view_agenda"

            ZscrollPluginCard {}

            HyprSelect {
                title: Translation.tr("Windows in a row")
                icon: "view_column"
                keys: []
                currentOverride: Math.round(tab.zscrollNumber("zscroll_windows_per_row", 2))
                options: [1, 2, 3, 4].map(count => ({ "displayName": String(count), "value": count }))
                onSelected: newValue => HyprlandGui.setGlobal("zscroll_windows_per_row", newValue)
            }

            HyprSelect {
                title: Translation.tr("Width change per Super + [ or ]")
                icon: "width_normal"
                keys: []
                currentOverride: tab.zscrollNumber("zscroll_resize_step", 0.05)
                options: [0.03, 0.05, 0.1].map(step => ({
                    "displayName": `${Math.round(step * 100)}%`, "value": step
                }))
                onSelected: newValue => HyprlandGui.setGlobal("zscroll_resize_step", newValue)
            }

            HyprToggle {
                buttonIcon: "fullscreen"
                text: Translation.tr("A window alone on its workspace fills the screen")
                switchOn: tab.zscrollOn("zscroll_single_window_fills", true)
                textOn: Translation.tr("The only tiled window takes the whole row; the second one splits it.")
                textOff: Translation.tr("The only window keeps its slot width.")
                onRequested: wanted => HyprlandGui.setGlobal("zscroll_single_window_fills", wanted)
            }

            HyprToggle {
                buttonIcon: "format_align_center"
                text: Translation.tr("Centre a row that is not full")
                switchOn: tab.zscrollOn("zscroll_center_incomplete_rows", false)
                textOn: Translation.tr("A row with free slots sits in the middle of the screen.")
                textOff: Translation.tr("A row with free slots starts at the left edge.")
                onRequested: wanted => HyprlandGui.setGlobal("zscroll_center_incomplete_rows", wanted)
            }

            HyprToggle {
                buttonIcon: "open_in_new"
                text: Translation.tr("A new window takes focus and brings its row")
                switchOn: tab.zscrollOn("zscroll_focus_new_windows", true)
                textOn: Translation.tr("Opening an app on this workspace scrolls to its row.")
                textOff: Translation.tr("New windows join the end of the tape; the view stays where it is.")
                onRequested: wanted => HyprlandGui.setGlobal("zscroll_focus_new_windows", wanted)
            }

            HyprToggle {
                buttonIcon: "mouse"
                text: Translation.tr("Pointer follows keyboard navigation")
                switchOn: tab.zscrollOn("zscroll_pointer_follows", true)
                textOn: Translation.tr("Moving focus with the keyboard or wheel centres the pointer on the new window.")
                textOff: Translation.tr("The pointer stays where it is.")
                onRequested: wanted => HyprlandGui.setGlobal("zscroll_pointer_follows", wanted)
            }

            HyprToggle {
                buttonIcon: "swap_vert"
                text: Translation.tr("Super + scroll moves between rows")
                switchOn: tab.zscrollOn("zscroll_wheel_rows", true)
                textOn: Translation.tr("On a zscroll workspace the wheel walks rows; elsewhere it still switches workspaces.")
                textOff: Translation.tr("Super + scroll always switches workspaces.")
                onRequested: wanted => HyprlandGui.setGlobal("zscroll_wheel_rows", wanted)
            }

            HyprToggle {
                buttonIcon: "keyboard"
                text: Translation.tr("zscroll shortcuts")
                alwaysExplain: true
                switchOn: tab.zscrollOn("zscroll_keybinds", false)
                textOn: Translation.tr("Super + arrows focus, Super + Shift + arrows swap, Super + [ ] resize, Super + ; ' change windows per row, Super + Shift + PgUp/PgDn move the row. Outside zscroll they do what they did before.")
                textOff: Translation.tr("Off by default, so no default shortcut is replaced. Turn it on to navigate zscroll from the keyboard.")
                onRequested: wanted => HyprlandGui.setGlobal("zscroll_keybinds", wanted)
            }

            HyprToggle {
                buttonIcon: "overview_key"
                text: Translation.tr("Super opens the zscroll overview")
                alwaysExplain: true
                switchOn: tab.zscrollOn("zscroll_super_overview", true)
                textOn: Translation.tr("On a zscroll workspace, tapping Super zooms out over every workspace and its rows (scrolloverview plugin). Without the plugin loaded, Super opens the shell's search as before.")
                textOff: Translation.tr("Super always opens the shell's search and overview.")
                onRequested: wanted => HyprlandGui.setGlobal("zscroll_super_overview", wanted)
            }

            HyprSelect {
                visible: tab.zscrollOn("zscroll_super_overview", true)
                title: Translation.tr("Overview zoom")
                icon: "zoom_out"
                keys: []
                currentOverride: tab.zscrollNumber("zscroll_overview_scale", 0.6)
                options: [0.4, 0.5, 0.6, 0.7].map(scale => ({
                    "displayName": `${Math.round(scale * 100)}%`, "value": scale
                }))
                onSelected: newValue => HyprlandGui.setGlobal("zscroll_overview_scale", newValue)
            }

            HyprSelect {
                visible: tab.zscrollOn("zscroll_super_overview", true)
                title: Translation.tr("Overview lays workspaces out")
                icon: "view_stream"
                keys: []
                currentOverride: String(HyprlandGui.globalValue("zscroll_overview_layout", "vertical"))
                options: [
                    { "displayName": Translation.tr("Top to bottom"), "value": "vertical" },
                    { "displayName": Translation.tr("Side by side"), "value": "horizontal" }
                ]
                onSelected: newValue => HyprlandGui.setGlobal("zscroll_overview_layout", newValue)
            }

            ConfigTextField {
                id: zscrollFullWidth

                readonly property string optionValue:
                    String(HyprlandGui.globalValue("zscroll_full_width_classes", "") ?? "")

                Layout.fillWidth: true
                icon: "fit_screen"
                text: Translation.tr("Apps that always get a whole row")
                placeholderText: Translation.tr("Window classes, comma separated (e.g. firefox, steam)")
                onOptionValueChanged: {
                    if (!zscrollFullWidth.textField.activeFocus)
                        zscrollFullWidth.inputText = zscrollFullWidth.optionValue;
                }
                Component.onCompleted: zscrollFullWidth.inputText = zscrollFullWidth.optionValue

                Connections {
                    target: zscrollFullWidth.textField

                    function onEditingFinished() {
                        const cleaned = zscrollFullWidth.inputText.split(",")
                            .map(name => name.trim()).filter(name => name !== "").join(", ");
                        if (cleaned !== zscrollFullWidth.optionValue)
                            HyprlandGui.setGlobal("zscroll_full_width_classes", cleaned);
                    }
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("Windows fill rows left to right, then the next row down. The focused row fills the screen; the rows above and below peek through the outer gaps and can be clicked. The overview shows a workspace's rows side by side.")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Focus")
        icon: "center_focus_strong"

        HyprSwitch {
            optionKey: "misc:focus_on_activate"
            buttonIcon: "notifications_active"
            text: Translation.tr("An app asking for attention gets focus")
            textOn: Translation.tr("A window that asks to be raised takes focus from whatever you were doing.")
            textOff: Translation.tr("A window that asks to be raised is only marked urgent.")
        }

        HyprSwitch {
            optionKey: "binds:window_direction_monitor_fallback"
            defaultValue: true
            buttonIcon: "monitor"
            text: Translation.tr("Moving past the edge of a screen crosses to the next")
            textOn: Translation.tr("Moving focus off the last window in a direction carries on to the next screen.")
            textOff: Translation.tr("Moving focus stops at the edge of the screen.")
        }

        HyprNavRow {
            visible: tab.advanced
            buttonIcon: "tune"
            text: Translation.tr("More focus settings")
            description: Translation.tr("Which neighbour is picked, fullscreen, groups")
            keys: ["binds:focus_preferred_method", "binds:movefocus_cycles_fullscreen",
                "binds:movefocus_cycles_groupfirst", "binds:ignore_group_lock"]
            configPage: Qt.resolvedUrl("HyprFocusAdvancedPage.qml")
        }

        HyprOptionNote {
            keys: ["misc:focus_on_activate", "binds:window_direction_monitor_fallback"]
        }
    }

    ContentSection {
        title: Translation.tr("Workspaces")
        icon: "dashboard"

        HyprSelect {
            id: backAndForth

            // Two switches, one behaviour: what the shortcut of the workspace you are already on
            // does. The second one only means anything once the first is on.
            readonly property bool goesBack: tab.isOn("binds:workspace_back_and_forth", false)
            readonly property bool cycles: tab.isOn("binds:allow_workspace_cycles", false)

            keys: ["binds:workspace_back_and_forth", "binds:allow_workspace_cycles"]
            title: Translation.tr("The shortcut of the workspace you are already on")
            icon: "swap_horiz"
            currentOverride: !backAndForth.goesBack ? "nothing" : (backAndForth.cycles ? "cycle" : "back")
            options: [
                { "displayName": Translation.tr("Does nothing"), "value": "nothing" },
                { "displayName": Translation.tr("Goes back to the previous one"), "value": "back" },
                { "displayName": Translation.tr("Keeps flipping between the two"), "value": "cycle" }
            ]
            onSelected: newValue => HyprlandGui.batch(() => {
                HyprlandGui.setKey("binds:workspace_back_and_forth", newValue !== "nothing");
                if (newValue !== "nothing")
                    HyprlandGui.setKey("binds:allow_workspace_cycles", newValue === "cycle");
            })
        }

        HyprSelect {
            optionKey: "binds:workspace_center_on"
            defaultValue: 1
            title: Translation.tr("After switching, the pointer goes to")
            icon: "my_location"
            options: [
                { "displayName": Translation.tr("The middle of the screen"), "value": 0 },
                { "displayName": Translation.tr("The last window used there"), "value": 1 }
            ]
        }

        HyprNavRow {
            visible: tab.advanced
            buttonIcon: "tune"
            text: Translation.tr("More workspace settings")
            description: Translation.tr("Scratchpad, pinned windows, scroll-wheel and drag thresholds")
            keys: ["binds:hide_special_on_workspace_change", "binds:allow_pin_fullscreen",
                "binds:scroll_event_delay", "binds:drag_threshold"]
            configPage: Qt.resolvedUrl("HyprWorkspacesAdvancedPage.qml")
        }

        HyprOptionNote {
            keys: ["binds:workspace_back_and_forth", "binds:allow_workspace_cycles",
                "binds:workspace_center_on"]
        }
    }

    ContentSection {
        title: Translation.tr("Workspace swipe")
        icon: "swipe"

        HyprSlider {
            optionKey: "gestures:workspace_swipe_distance"
            defaultValue: 300
            integer: true
            buttonIcon: "straighten"
            text: Translation.tr("Finger travel for a full workspace")
            tooltipContent: `${Math.round(value)} px`
            from: 50
            to: 2000
            stepSize: 10
        }

        HyprSwitch {
            optionKey: "gestures:workspace_swipe_invert"
            defaultValue: true
            buttonIcon: "swap_horiz"
            text: Translation.tr("Invert the touchpad direction")
            textOn: Translation.tr("The workspaces move with your fingers, the way pages do on a phone.")
            textOff: Translation.tr("The workspaces move against your fingers.")
        }

        HyprNavRow {
            visible: tab.advanced
            buttonIcon: "tune"
            text: Translation.tr("Advanced workspace swipe")
            description: Translation.tr("When a swipe commits, direction lock, touchscreen, wrap-around")
            keys: ["gestures:workspace_swipe_cancel_ratio", "gestures:workspace_swipe_min_speed_to_force",
                "gestures:workspace_swipe_create_new", "gestures:workspace_swipe_forever",
                "gestures:workspace_swipe_use_r", "gestures:workspace_swipe_direction_lock",
                "gestures:workspace_swipe_direction_lock_threshold", "gestures:workspace_swipe_touch",
                "gestures:workspace_swipe_touch_invert"]
            configPage: Qt.resolvedUrl("HyprWorkspaceSwipeAdvancedPage.qml")
        }

        HyprOptionNote {
            keys: ["gestures:workspace_swipe_distance", "gestures:workspace_swipe_invert"]
        }
    }

    ContentSection {
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "windows"
                label: Translation.tr("Windows")
            }

            RelatedChip {
                pageId: "tiling"
                label: Translation.tr("Window tiling")
            }

            RelatedChip {
                pageId: "workspaces"
                label: Translation.tr("Workspaces")
            }

            RelatedChip {
                pageId: "touchGestures"
                label: Translation.tr("Touch & gestures")
            }
        }
    }
}
