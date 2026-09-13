pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Every configuration key Hyprland has, and the type each one takes.
 *
 * Hyprland ships the list itself: /usr/share/hypr/stubs/hl.meta.lua declares HL.ConfigValueTypes,
 * one field per key with its Lua type. Reading that file is the only way to stay current with the
 * compositor actually installed, since the list grows with every release. A copy of the same table
 * is bundled below for machines whose packaging leaves the stubs out, and the page says which of
 * the two it is showing.
 *
 * Three things about that list are easy to get wrong, so they are done here once.
 *
 * Keys are dotted in Lua and colon-separated in hyprctl, but `col` is not a table: Hyprland spells
 * the border colours `col.active_border`, which is one name containing a dot. The conversion is
 * therefore not a search and replace - `general.col.active_border` becomes
 * `general:col.active_border`, while `decoration.blur.size` becomes `decoration:blur:size`.
 *
 * The declared type is what Lua accepts; hyprctl's reported type is what the value is right now.
 * They agree everywhere except for six colours that Lua takes as a string and hyprctl reports as a
 * packed integer, which is why a colour is recognised by its name here rather than by its type.
 *
 * A colour cannot be written back in the shape it is read in. hyprctl prints a gradient as
 * `aaffb59b 0deg`, and feeding that straight back is refused with `invalid color`. What Hyprland
 * accepts is `rgba(RRGGBBAA)`, `0xAARRGGBB`, or a `{ colors = { ... }, angle = n }` table - so the
 * editors parse what they are shown and write one of those instead.
 */
Singleton {
    id: root

    readonly property string stubPath: "/usr/share/hypr/stubs/hl.meta.lua"

    /// "stub" when the list came from the file Hyprland ships, "bundled" when it did not.
    property string origin: ""
    property bool ready: false
    /**
     * Whether the browser lists the `debug.` keys.
     *
     * Session state rather than a setting, and off again after a restart on purpose. Those keys
     * turn on damage blinking and log spew, and one of them deliberately crashes the compositor;
     * finding them should take a decision, not a scroll.
     */
    property bool showDebug: false
    /// Where the browser opens: a section to start in, and a key to open and scroll to. Set just
    /// before the page is pushed, the same way the rule and keybind editors are pointed at theirs.
    property string browseSection: ""
    property string browseKey: ""

    function browse(section: string, key: string) {
        root.browseSection = section;
        root.browseKey = key;
    }

    /// Declared Lua type -> the keys that take it, in the stub's own dotted spelling. Generated
    /// from the stub shipped with Hyprland 0.56.2; used only when that file cannot be read.
    readonly property var bundledTypes: ({
        "boolean":
            "animations.enabled animations.workspace_wraparound binds.allow_pin_fullscreen "
            + "binds.allow_workspace_cycles binds.disable_keybind_grabbing "
            + "binds.hide_special_on_workspace_change binds.ignore_group_lock "
            + "binds.movefocus_cycles_fullscreen binds.movefocus_cycles_groupfirst "
            + "binds.pass_mouse_when_bound binds.window_direction_monitor_fallback "
            + "binds.workspace_back_and_forth cursor.enable_hyprcursor cursor.hide_on_key_press "
            + "cursor.hide_on_tablet cursor.hide_on_touch cursor.invisible cursor.no_warps "
            + "cursor.persistent_warps cursor.sync_gsettings_theme "
            + "cursor.warp_back_after_non_mouse_input cursor.zoom_detached_camera "
            + "cursor.zoom_disable_aa cursor.zoom_rigid debug.colored_stdout_logs "
            + "debug.damage_blink debug.disable_logs debug.disable_scale_checks debug.disable_time "
            + "debug.ds_handle_same_buffer debug.ds_handle_same_buffer_fifo "
            + "debug.enable_stdout_logs debug.fifo_pending_workaround debug.full_cm_proto "
            + "debug.gl_debugging debug.log_damage debug.overlay debug.pass "
            + "debug.render_solitary_wo_damage debug.suppress_errors debug.vfr "
            + "decoration.blur.enabled decoration.blur.ignore_opacity decoration.blur.input_methods "
            + "decoration.blur.new_optimizations decoration.blur.popups decoration.blur.special "
            + "decoration.blur.xray decoration.border_part_of_window decoration.dim_inactive "
            + "decoration.dim_modal decoration.glow.enabled decoration.motion_blur.enabled "
            + "decoration.shadow.enabled decoration.shadow.sharp "
            + "dwindle.permanent_direction_override dwindle.precise_mouse_move "
            + "dwindle.preserve_split dwindle.smart_resizing dwindle.smart_split "
            + "dwindle.use_active_for_splits ecosystem.enforce_permissions "
            + "ecosystem.no_donation_nag ecosystem.no_update_news experimental.wp_cm_1_2 "
            + "general.allow_tearing general.hover_icon_on_border general.modal_parent_blocking "
            + "general.no_focus_fallback general.resize_on_border general.snap.border_overlap "
            + "general.snap.enabled general.snap.respect_gaps gestures.scrolling.move_snap_cursor "
            + "gestures.scrolling.move_snap_to_grid gestures.workspace_swipe_create_new "
            + "gestures.workspace_swipe_direction_lock gestures.workspace_swipe_forever "
            + "gestures.workspace_swipe_invert gestures.workspace_swipe_touch "
            + "gestures.workspace_swipe_touch_invert gestures.workspace_swipe_use_r "
            + "group.auto_group group.focus_removed_window group.group_on_movetoworkspace "
            + "group.groupbar.blur group.groupbar.disable_when_only group.groupbar.enabled "
            + "group.groupbar.gradient_round_only_edges group.groupbar.gradients "
            + "group.groupbar.keep_upper_gap group.groupbar.middle_click_close "
            + "group.groupbar.render_titles group.groupbar.round_only_edges "
            + "group.groupbar.scrolling group.groupbar.stacked group.insert_after_current "
            + "group.merge_floated_into_tiled_on_groupbar group.merge_groups_on_drag "
            + "group.merge_groups_on_groupbar input.force_no_accel input.left_handed "
            + "input.mouse_refocus input.natural_scroll input.numlock_by_default "
            + "input.resolve_binds_by_sym input.scroll_button_lock input.special_fallthrough "
            + "input.tablet.absolute_region_position input.tablet.left_handed "
            + "input.tablet.relative_input input.touchdevice.enabled "
            + "input.touchpad.clickfinger_behavior input.touchpad.disable_while_typing "
            + "input.touchpad.flip_x input.touchpad.flip_y input.touchpad.middle_button_emulation "
            + "input.touchpad.natural_scroll input.touchpad.tap_and_drag "
            + "input.touchpad.tap_to_click input.virtualkeyboard.release_pressed_on_close "
            + "input_capture.capture_modifiers input_capture.enforce_barriers "
            + "master.allow_small_split master.always_keep_position master.center_ignores_reserved "
            + "master.drop_at_cursor master.focus_master_on_close master.new_on_top "
            + "master.smart_resizing misc.allow_session_lock_restore misc.always_follow_on_dnd "
            + "misc.animate_manual_resizes misc.animate_mouse_windowdragging "
            + "misc.close_special_on_empty misc.disable_autoreload "
            + "misc.disable_hyprland_guiutils_check misc.disable_hyprland_logo "
            + "misc.disable_scale_notification misc.disable_splash_rendering "
            + "misc.disable_watchdog_warning misc.disable_xdg_env_checks misc.enable_anr_dialog "
            + "misc.enable_swallow misc.exit_window_retains_fullscreen misc.focus_on_activate "
            + "misc.key_press_enables_dpms misc.layers_hog_keyboard_focus misc.middle_click_paste "
            + "misc.mouse_move_enables_dpms misc.mouse_move_focuses_monitor misc.name_vk_after_proc "
            + "misc.screencopy_force_8b misc.session_lock_blur misc.session_lock_xray "
            + "misc.size_limits_tiled opengl.nvidia_anti_flicker quirks.skip_non_kms_dmabuf_formats "
            + "render.cm_enabled render.commit_timing_enabled render.expand_undersized_textures "
            + "render.icc_vcgt_enabled render.new_render_scheduling render.send_content_type "
            + "render.use_shader_blur_blend render.xp_mode scrolling.follow_focus "
            + "scrolling.fullscreen_on_one_column scrolling.wrap_focus scrolling.wrap_swapcol "
            + "xwayland.create_abstract_socket xwayland.enabled xwayland.force_zero_scaling "
            + "xwayland.use_nearest_neighbor",
        "integer|boolean":
            "binds.drag_threshold binds.focus_preferred_method binds.scroll_event_delay "
            + "binds.workspace_center_on cursor.hotspot_padding cursor.min_refresh_rate "
            + "cursor.no_break_fs_vrr cursor.no_hardware_cursors cursor.use_cpu_buffer "
            + "cursor.warp_on_change_workspace cursor.warp_on_toggle_special debug.damage_tracking "
            + "debug.error_limit debug.error_position debug.invalidate_fp16 debug.manual_crash "
            + "decoration.blur.passes decoration.blur.size decoration.glow.range "
            + "decoration.glow.render_power decoration.motion_blur.samples decoration.rounding "
            + "decoration.shadow.range decoration.shadow.render_power dwindle.force_split "
            + "dwindle.split_bias general.border_size general.extend_border_grab_area "
            + "general.gaps_workspaces general.resize_corner general.snap.monitor_gap "
            + "general.snap.window_gap gestures.close_max_timeout "
            + "gestures.workspace_swipe_direction_lock_threshold gestures.workspace_swipe_distance "
            + "gestures.workspace_swipe_min_speed_to_force group.drag_into_group "
            + "group.groupbar.font_size group.groupbar.gaps_in group.groupbar.gaps_out "
            + "group.groupbar.gradient_rounding group.groupbar.height group.groupbar.indicator_gap "
            + "group.groupbar.indicator_height group.groupbar.priority group.groupbar.rounding "
            + "group.groupbar.text_offset group.groupbar.text_padding input.emulate_discrete_scroll "
            + "input.float_switch_override_focus input.focus_on_close input.follow_mouse "
            + "input.follow_mouse_shrink input.off_window_axis_events input.repeat_delay "
            + "input.repeat_rate input.rotation input.scroll_button input.tablet.transform "
            + "input.tablettool.eraser_button_mode input.tablettool.eraser_button_override "
            + "input.touchdevice.transform input.touchpad.drag_3fg input.touchpad.drag_lock "
            + "input.virtualkeyboard.share_states master.slave_count_for_center_master "
            + "misc.anr_missed_pings misc.force_default_wallpaper "
            + "misc.initial_workspace_token_timeout misc.initial_workspace_tracking "
            + "misc.lockdead_screen_delay misc.on_focus_under_fullscreen misc.render_unfocused_fps "
            + "misc.vrr quirks.prefer_hdr render.cm_auto_hdr render.ctm_animation "
            + "render.direct_scanout render.fp16_sdr_tf render.keep_unmodified_copy "
            + "render.non_shader_cm render.non_shader_cm_interop render.use_fp16 "
            + "scrolling.focus_fit_method",
        "number|boolean":
            "cursor.inactive_timeout cursor.zoom_factor decoration.active_opacity "
            + "decoration.blur.brightness decoration.blur.contrast "
            + "decoration.blur.input_methods_ignorealpha decoration.blur.noise "
            + "decoration.blur.popups_ignorealpha decoration.blur.vibrancy "
            + "decoration.blur.vibrancy_darkness decoration.dim_around decoration.dim_special "
            + "decoration.dim_strength decoration.fullscreen_opacity decoration.inactive_opacity "
            + "decoration.rounding_power decoration.shadow.scale dwindle.default_split_ratio "
            + "dwindle.special_scale_factor dwindle.split_width_multiplier "
            + "gestures.workspace_swipe_cancel_ratio group.groupbar.gradient_rounding_power "
            + "group.groupbar.rounding_power input.follow_mouse_threshold input.scroll_factor "
            + "input.sensitivity input.tablettool.pressure_range_max "
            + "input.tablettool.pressure_range_min input.touchpad.scroll_factor "
            + "layout.single_window_aspect_ratio_tolerance master.mfact master.special_scale_factor "
            + "scrolling.column_width scrolling.follow_min_visible",
        "string":
            "cursor.default_monitor decoration.screen_shader general.layout general.locale "
            + "group.groupbar.font_family group.groupbar.text_color "
            + "group.groupbar.text_color_inactive group.groupbar.text_color_locked_active "
            + "group.groupbar.text_color_locked_inactive input.accel_profile input.kb_file "
            + "input.kb_layout input.kb_model input.kb_options input.kb_rules input.kb_variant "
            + "input.scroll_method input.scroll_points input.tablet.output input.touchdevice.output "
            + "input.touchpad.tap_button_map master.center_master_fallback master.new_on_active "
            + "master.new_status master.orientation misc.background_color misc.col.splash "
            + "misc.font_family misc.splash_font_family misc.swallow_exception_regex "
            + "misc.swallow_regex render.cm_sdr_eotf scrolling.direction "
            + "scrolling.explicit_column_widths",
        "string|HL.Gradient":
            "decoration.glow.color decoration.glow.color_inactive decoration.shadow.color "
            + "decoration.shadow.color_inactive general.col.active_border "
            + "general.col.inactive_border general.col.nogroup_border "
            + "general.col.nogroup_border_active group.col.border_active group.col.border_inactive "
            + "group.col.border_locked_active group.col.border_locked_inactive "
            + "group.groupbar.col.active group.groupbar.col.inactive "
            + "group.groupbar.col.locked_active group.groupbar.col.locked_inactive",
        "HL.Vec2Like":
            "decoration.shadow.offset input.tablet.active_area_position "
            + "input.tablet.active_area_size input.tablet.region_position input.tablet.region_size "
            + "layout.single_window_aspect_ratio",
        "integer|HL.CssGap":
            "general.float_gaps general.gaps_in general.gaps_out",
        "integer|string":
            "group.groupbar.font_weight_active group.groupbar.font_weight_inactive"
    })

    /// Keys that already have a control written for them on one of the other tabs. The browser
    /// says so and offers the way over, because that control knows what the values mean and this
    /// one only knows the type. Hand-kept: it is read off the `optionKey` bindings in those tabs.
    readonly property var curatedKeys: ({
        "input":
            "cursor:enable_hyprcursor cursor:hide_on_key_press cursor:hide_on_touch "
            + "cursor:inactive_timeout cursor:no_hardware_cursors cursor:no_warps "
            + "cursor:persistent_warps cursor:warp_on_change_workspace cursor:zoom_factor "
            + "cursor:zoom_rigid input:accel_profile input:focus_on_close input:follow_mouse "
            + "input:follow_mouse_threshold input:force_no_accel input:kb_layout input:kb_model "
            + "input:kb_options input:kb_variant input:left_handed input:mouse_refocus "
            + "input:natural_scroll input:numlock_by_default input:repeat_delay input:repeat_rate "
            + "input:resolve_binds_by_sym input:scroll_button_lock input:scroll_factor "
            + "input:scroll_method input:sensitivity input:touchpad:clickfinger_behavior "
            + "input:touchpad:disable_while_typing input:touchpad:drag_3fg input:touchpad:drag_lock "
            + "input:touchpad:flip_x input:touchpad:flip_y input:touchpad:middle_button_emulation "
            + "input:touchpad:natural_scroll input:touchpad:scroll_factor "
            + "input:touchpad:tap_and_drag input:touchpad:tap_button_map "
            + "input:touchpad:tap_to_click",
        "layout":
            "binds:allow_pin_fullscreen binds:allow_workspace_cycles binds:drag_threshold "
            + "binds:focus_preferred_method binds:hide_special_on_workspace_change "
            + "binds:ignore_group_lock binds:movefocus_cycles_fullscreen "
            + "binds:movefocus_cycles_groupfirst binds:scroll_event_delay "
            + "binds:window_direction_monitor_fallback binds:workspace_back_and_forth "
            + "binds:workspace_center_on dwindle:default_split_ratio dwindle:force_split "
            + "dwindle:permanent_direction_override dwindle:precise_mouse_move "
            + "dwindle:preserve_split dwindle:smart_resizing dwindle:smart_split "
            + "dwindle:special_scale_factor dwindle:split_bias dwindle:split_width_multiplier "
            + "dwindle:use_active_for_splits general:layout gestures:workspace_swipe_cancel_ratio "
            + "gestures:workspace_swipe_create_new gestures:workspace_swipe_direction_lock "
            + "gestures:workspace_swipe_direction_lock_threshold gestures:workspace_swipe_distance "
            + "gestures:workspace_swipe_forever gestures:workspace_swipe_invert "
            + "gestures:workspace_swipe_min_speed_to_force gestures:workspace_swipe_touch "
            + "gestures:workspace_swipe_touch_invert gestures:workspace_swipe_use_r "
            + "master:allow_small_split master:always_keep_position master:center_ignores_reserved "
            + "master:center_master_fallback master:drop_at_cursor master:focus_master_on_close "
            + "master:mfact master:new_on_active master:new_on_top master:new_status "
            + "master:orientation master:slave_count_for_center_master master:smart_resizing "
            + "master:special_scale_factor misc:focus_on_activate scrolling:column_width "
            + "scrolling:direction scrolling:explicit_column_widths scrolling:focus_fit_method "
            + "scrolling:follow_focus scrolling:follow_min_visible "
            + "scrolling:fullscreen_on_one_column scrolling:wrap_focus scrolling:wrap_swapcol"
    })

    /**
     * The sections, in the order Hyprland's own documentation puts them, with the three layout
     * engines and the debugging switches after the rest. Alphabetical would be easier to
     * generate and harder to use: nobody looks for `animations` between `misc` and `opengl`.
     */
    readonly property var sectionOrder: ["general", "decoration", "animations", "input", "gestures",
        "group", "misc", "binds", "xwayland", "opengl", "render", "cursor", "ecosystem",
        "experimental", "layout", "dwindle", "master", "scrolling", "input_capture", "quirks",
        "debug"]

    /// Untranslated on purpose - the strings are wrapped where they are drawn, the same split the
    /// hub's own tab model uses, so switching language does not rebuild this table.
    readonly property var sectionMeta: ({
        "general": { "title": "General", "icon": "tune" },
        "decoration": { "title": "Decoration", "icon": "format_paint" },
        "animations": { "title": "Animations", "icon": "animation" },
        "input": { "title": "Input", "icon": "keyboard" },
        "gestures": { "title": "Gestures", "icon": "swipe" },
        "group": { "title": "Groups", "icon": "tab" },
        "misc": { "title": "Misc", "icon": "more_horiz" },
        "binds": { "title": "Keybind behaviour", "icon": "keyboard_command_key" },
        "xwayland": { "title": "XWayland", "icon": "desktop_windows" },
        "opengl": { "title": "OpenGL", "icon": "deployed_code" },
        "render": { "title": "Render", "icon": "display_settings" },
        "cursor": { "title": "Cursor", "icon": "mouse" },
        "ecosystem": { "title": "Ecosystem", "icon": "eco" },
        "experimental": { "title": "Experimental", "icon": "science" },
        "layout": { "title": "Layout", "icon": "dashboard" },
        "dwindle": { "title": "Dwindle layout", "icon": "account_tree" },
        "master": { "title": "Master layout", "icon": "view_sidebar" },
        "scrolling": { "title": "Scrolling layout", "icon": "swap_horiz" },
        "input_capture": { "title": "Input capture", "icon": "cast" },
        "quirks": { "title": "Quirks", "icon": "build" },
        "debug": { "title": "Debug", "icon": "bug_report" }
    })

    /// [{ key, dotted, section, path, leaf, declared, kind, words }], in section then key order.
    property var entries: []
    /// key -> entry, for the pages that hold a key and want everything else about it.
    property var byKey: ({})
    /// [{ id, title, icon, count }] for every section that has at least one key.
    property var sections: []

    // ------------------------------------------------------------- key shapes

    /**
     * `general.col.active_border` -> `general:col.active_border`.
     *
     * Every dot separates a table except the one after `col`, which is part of the option's own
     * name. Getting this wrong costs nothing visible - the key simply never matches anything -
     * so it is worth stating plainly rather than leaving as a clever line.
     */
    function toKey(dotted: string): string {
        const parts = String(dotted ?? "").split(".");
        const out = [];
        for (let i = 0; i < parts.length; i++) {
            if (parts[i] === "col" && i + 1 < parts.length) {
                out.push(`col.${parts[i + 1]}`);
                i += 1;
                continue;
            }
            out.push(parts[i]);
        }
        return out.join(":");
    }

    /// Hyprland answers to both `tap-to-click` and `tap_to_click`; the catalogue lists the second.
    function normalise(key: string): string {
        return String(key ?? "").replace(/-/g, "_");
    }

    /**
     * Which editor a key needs.
     *
     * The declared Lua type decides, except for the colours Hyprland stores as a packed integer
     * and declares as a plain string. Those are picked out by name, which is exact here: `col.`
     * and `_color` between them catch all six and nothing else in the list.
     */
    function kindFor(dotted: string, declared: string): string {
        if (declared === "boolean") return "bool";
        if (declared === "integer|boolean") return "int";
        if (declared === "number|boolean") return "float";
        if (declared === "string|HL.Gradient") return "gradient";
        if (declared === "HL.Vec2Like") return "vec2";
        if (declared === "integer|HL.CssGap") return "gaps";
        if (declared !== "string") return "text";
        const leaf = String(dotted).split(".").pop();
        const parent = String(dotted).split(".").slice(-2)[0] ?? "";
        if (parent === "col" || leaf.indexOf("color") >= 0) return "color";
        return "text";
    }

    /// What the type means, in words, for the line above the editor.
    function kindLabel(kind: string): string {
        if (kind === "bool") return Translation.tr("On or off");
        if (kind === "int") return Translation.tr("Whole number");
        if (kind === "float") return Translation.tr("Number, decimals allowed");
        if (kind === "color") return Translation.tr("Colour");
        if (kind === "gradient") return Translation.tr("Colour or gradient");
        if (kind === "vec2") return Translation.tr("Two numbers");
        if (kind === "gaps") return Translation.tr("One number, or four");
        return Translation.tr("Text");
    }

    function entryFor(key: string): var {
        return root.byKey[root.normalise(key)] ?? null;
    }

    /// The tab that has a proper control for this key, or "" when none has.
    function curatedIn(key: string): string {
        return root._curatedMap[root.normalise(key)] ?? "";
    }

    function sectionEntries(section: string): var {
        return root.entries.filter(entry => entry.section === section);
    }

    /**
     * Keys matching `query`, in catalogue order.
     *
     * Matched twice: against the key as written, and against the same key with its punctuation
     * turned into spaces, so "hardware cursor" finds `cursor:no_hardware_cursors` as readily as
     * "no_hardware" does. Plain substring both times rather than a fuzzy match, so what comes
     * back is what the words say.
     */
    function search(query: string, includeDebug: bool): var {
        const needle = String(query ?? "").trim().toLowerCase();
        return root.entries.filter(entry => {
            if (entry.section === "debug" && !includeDebug) return false;
            if (needle === "") return true;
            return entry.key.toLowerCase().indexOf(needle) >= 0 || entry.words.indexOf(needle) >= 0;
        });
    }

    // ---------------------------------------------------------------- values

    /// The reported value as one line of text, for a row that is not expanded.
    function format(kind: string, value: var): string {
        if (value === undefined || value === null) return "";
        if (kind === "bool") return value === true || value === 1
            ? Translation.tr("On") : Translation.tr("Off");
        if (kind === "color") return root.colorText(value);
        if (kind === "gradient") return root.gradientText(value);
        if (kind === "vec2") return Array.from(value ?? []).join(", ");
        // The shapes this page writes, which come back through displayValue() as the managed
        // value: a four-sided gap table, and anything else the writer builds as an object.
        if (kind === "gaps" && value !== null && typeof value === "object")
            return [value.top, value.right, value.bottom, value.left].join(" ");
        if (value !== null && typeof value === "object") return JSON.stringify(value);
        return String(value);
    }

    /// `rgba(RRGGBBAA)` / `rgb(RRGGBB)` - the shape the hub writes - as the AARRGGBB word hyprctl
    /// prints, so the readers below take either. Null when `value` is not that shape.
    function _writtenColor(value: var): var {
        const m = String(value ?? "").trim().match(/^rgba?\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})?\)$/);
        if (!m) return null;
        return (m[2] ?? "ff") + m[1];
    }

    /**
     * A colour as `#rrggbb`, whatever it arrived as.
     *
     * hyprctl hands these over three different ways depending on the option: a packed integer, a
     * gradient string of AARRGGBB words with an angle on the end, or nothing at all.
     */
    function colorText(value: var): string {
        const written = root._writtenColor(value);
        if (written !== null) value = written;
        if (typeof value === "number")
            return `#${(value >>> 0).toString(16).padStart(8, "0").slice(2)}`;
        const first = String(value ?? "").trim().split(/\s+/)[0] ?? "";
        if (!/^[0-9a-fA-F]{8}$/.test(first)) return String(value ?? "");
        return `#${first.slice(2)}`;
    }

    /// `#rrggbb` and an alpha of 0-255 for the swatch and the picker, from either shape above.
    function colorParts(value: var): var {
        const written = root._writtenColor(value);
        if (written !== null) value = written;
        if (typeof value === "number") {
            const packed = value >>> 0;
            return ({ "rgb": `#${packed.toString(16).padStart(8, "0").slice(2)}`,
                "alpha": packed >>> 24 });
        }
        const first = String(value ?? "").trim().split(/\s+/)[0] ?? "";
        if (!/^[0-9a-fA-F]{8}$/.test(first)) return ({ "rgb": "#000000", "alpha": 255 });
        return ({ "rgb": `#${first.slice(2)}`, "alpha": parseInt(first.slice(0, 2), 16) });
    }

    /// A gradient string as its colours and its angle, so the editor can put it back together.
    function gradientParts(value: var): var {
        // The shape gradientValue() builds, back from the managed layer.
        if (value !== null && typeof value === "object" && value.colors !== undefined)
            return ({ "colors": Array.from(value.colors).map(item => String(item).replace(/^0x/i, "")),
                "angle": Number(value.angle) || 0 });
        const words = String(value ?? "").trim().split(/\s+/).filter(word => word !== "");
        const colors = words.filter(word => /^[0-9a-fA-F]{8}$/.test(word));
        const angleWord = words.find(word => /deg$/.test(word)) ?? "0deg";
        return ({ "colors": colors, "angle": parseFloat(angleWord) || 0 });
    }

    /// A gradient as hyprctl prints it, whichever shape it arrived in.
    function gradientText(value: var): string {
        const parts = root.gradientParts(value);
        if (parts.colors.length === 0) return String(value ?? "");
        return `${parts.colors.join(" ")} ${parts.angle}deg`;
    }

    /// The shape Hyprland accepts for a gradient. Never the shape it prints.
    function gradientValue(colors: var, angle: real): var {
        const list = Array.from(colors ?? []).filter(item => /^[0-9a-fA-F]{8}$/.test(String(item)));
        if (list.length === 0) return "";
        return ({ "colors": list.map(item => `0x${item}`), "angle": Math.round(angle) });
    }

    /// `#rrggbb` plus an alpha, as the `rgba(RRGGBBAA)` Hyprland reads.
    function colorValue(rgb: string, alpha: int): string {
        const hex = String(rgb ?? "").replace("#", "").slice(0, 6).padStart(6, "0");
        const a = Math.min(255, Math.max(0, Math.round(alpha))).toString(16).padStart(2, "0");
        return `rgba(${hex}${a})`;
    }

    /// Four gaps as one number when they are all the same, and as a table when they are not.
    function gapsValue(text: string): var {
        const numbers = String(text ?? "").trim().split(/[\s,]+/)
            .map(word => parseInt(word, 10)).filter(number => !isNaN(number));
        if (numbers.length === 0) return undefined;
        if (numbers.length === 1) return numbers[0];
        while (numbers.length < 4) numbers.push(numbers[numbers.length - 1]);
        if (numbers.every(number => number === numbers[0])) return numbers[0];
        return ({ "top": numbers[0], "right": numbers[1], "bottom": numbers[2], "left": numbers[3] });
    }

    // --------------------------------------------------------------- reading

    property var _curatedMap: ({})

    function _build(table: var, origin: string) {
        const entries = [];
        const byKey = {};
        const counts = {};
        for (const dotted of Object.keys(table)) {
            const key = root.toKey(dotted);
            const section = key.split(":")[0];
            const path = key.split(":").slice(1).join(":");
            const declared = table[dotted];
            const entry = {
                "key": key,
                "dotted": dotted,
                "section": section,
                "path": path === "" ? key : path,
                "leaf": key.split(":").pop(),
                "declared": declared,
                "kind": root.kindFor(dotted, declared),
                "words": key.replace(/[:._]/g, " ").toLowerCase()
            };
            entries.push(entry);
            byKey[key] = entry;
            counts[section] = (counts[section] ?? 0) + 1;
        }
        const rank = section => {
            const at = root.sectionOrder.indexOf(section);
            return at < 0 ? root.sectionOrder.length : at;
        };
        entries.sort((left, right) => rank(left.section) - rank(right.section)
            || left.key.localeCompare(right.key));
        const sections = [];
        for (const id of root.sectionOrder) {
            if (!counts[id]) continue;
            const meta = root.sectionMeta[id] ?? ({});
            sections.push({ "id": id, "title": meta.title ?? id, "icon": meta.icon ?? "tune",
                "count": counts[id] });
        }
        // A section the shipped stub knows about and this file does not would otherwise vanish.
        for (const id of Object.keys(counts))
            if (root.sectionOrder.indexOf(id) < 0)
                sections.push({ "id": id, "title": id, "icon": "tune", "count": counts[id] });
        root.entries = entries;
        root.byKey = byKey;
        root.sections = sections;
        root.origin = origin;
        root.ready = true;
    }

    function _expand(table: var): var {
        const out = {};
        for (const declared of Object.keys(table))
            for (const dotted of String(table[declared]).split(" "))
                if (dotted !== "") out[dotted] = declared;
        return out;
    }

    function _useBundled() {
        root._build(root._expand(root.bundledTypes), "bundled");
    }

    /**
     * Pull HL.ConfigValueTypes out of the stub.
     *
     * The block is a run of `---@field ['a.b.c'] type` lines under one class, and the file holds
     * several other classes shaped the same way, so the scan is bounded by the class it wants
     * rather than run over the whole file. Anything short of a full table falls back to the
     * bundled copy: half a catalogue would be worse than a stale one, because the missing keys
     * would look like keys Hyprland does not have.
     */
    function _parseStub(text: string) {
        const lines = String(text ?? "").split("\n");
        const table = {};
        let inside = false;
        for (const line of lines) {
            if (line.indexOf("---@class HL.ConfigValueTypes") === 0) {
                inside = true;
                continue;
            }
            if (!inside) continue;
            const match = /^---@field \['([^']+)'\]\s+(\S+)/.exec(line);
            if (!match) break;
            table[match[1]] = match[2];
        }
        if (Object.keys(table).length < 50) {
            console.warn("[HyprlandCatalog] stub had no usable option table, using the bundled one");
            root._useBundled();
            return;
        }
        root._build(table, "stub");
    }

    Component.onCompleted: {
        const map = {};
        for (const tab of Object.keys(root.curatedKeys))
            for (const key of String(root.curatedKeys[tab]).split(" "))
                if (key !== "") map[key] = tab;
        root._curatedMap = map;
    }

    FileView {
        id: stubFile
        path: root.stubPath
        // FileView reads lazily otherwise, and nothing here asks for the text until this has
        // already answered - the catalogue would sit empty waiting for itself.
        preload: true
        printErrors: false
        onLoaded: root._parseStub(stubFile.text())
        onLoadFailed: root._useBundled()
    }
}
