-- zscroll: full-height rows of N windows on a vertical tape, in Z order.
-- Adapted from VietNguyenVN/End4_plus (custom/layouts/zscroll.lua).
--
-- Registered as `lua:zscroll`. Select it with general:layout (Settings -> Hyprland
-- -> Layout writes it). Hyprland owns target order: new windows append, closing or
-- floating one compacts the rest. The focused row fills the work area; the rows
-- above and below sit just off screen and peek through the outer gaps.
--
-- Options are Lua globals, read on every layout pass so a settings write (which
-- reloads the config) or `hyprctl eval 'zscroll_windows_per_row = 3'` applies
-- without re-requiring this file. Settings -> Hyprland -> Layout manages them in
-- custom/variables.lua:
--
--   zscroll_windows_per_row        positive integer, slots per row (2)
--   zscroll_center_incomplete_rows center a row that is not full (false)
--   zscroll_focus_new_windows      a new tiled window takes focus and its row (true)
--   zscroll_pointer_follows        keyboard/wheel navigation centres the pointer (true)
--   zscroll_resize_step            width change per resize step, 0.01-0.25 (0.05)
--   zscroll_wheel_rows             Super+wheel walks rows instead of workspaces (true)
--   zscroll_keybinds               install the zscroll shortcuts below (false: opt-in, so
--                                  nobody off zscroll has a default bind replaced)
--   zscroll_full_width_classes     comma-separated window classes that take a whole row ("")
--   zscroll_single_window_fills    a workspace's only tiled window fills the screen (true)
--   zscroll_super_overview         the search opens over the scrolloverview plugin on zscroll
--                                  and on the native scrolling layout (true)
--   zscroll_overview_scale         scrolloverview zoom, 0.2-0.9 (0.6)
--   zscroll_overview_layout        "vertical" or "horizontal" workspaces (vertical)
--
-- Windows can also be given a whole row with the `zscroll-full` tag in a window rule.
--
-- Shortcuts, with zscroll_keybinds (each falls back to the normal action outside zscroll):
--   Super + arrows             spatial focus; up/down keep the column
--   Super + Shift + arrows     swap in that direction
--   Super + [ / ]              shrink / grow the focused window's width
--   Super + ; / '              fewer / more windows per row (until the next reload)
--   Super + Shift + PgUp/PgDn  move the whole row up / down
--   Super + wheel              previous / next row (own toggle, zscroll_wheel_rows)
local NAME = "lua:zscroll"
local M = { name = NAME }

local rows = {}
local row_sizes = {}
local row_partitions = {}
local reordering = false
-- Super+;/' changes capacity until the next reload; nil follows the global.
local capacity_override = nil
local last_capacity = nil

local function bool_option(name, fallback)
    local value = _G[name]
    if value == nil then return fallback end
    return value == true or value == 1 or value == "true"
end

local function capacity()
    local count = capacity_override or tonumber(_G.zscroll_windows_per_row) or 2
    count = math.floor(count)
    if count < 1 then count = 1 end
    if count > 8 then count = 8 end
    return count
end

local function resize_step()
    local step = tonumber(_G.zscroll_resize_step) or 0.05
    return math.max(0.01, math.min(0.25, step))
end

local function full_width_classes()
    local raw = _G.zscroll_full_width_classes
    local set = {}
    if type(raw) ~= "string" then return set end
    for entry in raw:gmatch("[^,]+") do
        local class = entry:match("^%s*(.-)%s*$"):lower()
        if class ~= "" then set[class] = true end
    end
    return set
end

-- Width fractions remember the capacity they were made for; a new capacity drops them.
local function sync_capacity()
    local count = capacity()
    if last_capacity ~= count then
        row_sizes = {}
        row_partitions = {}
        last_capacity = count
    end
    return count
end

local function active_workspace()
    return hl.get_active_special_workspace() or hl.get_active_workspace()
end

local function is_zscroll(workspace)
    return workspace ~= nil and workspace.tiled_layout == NAME
end

local function workspace_of(ctx)
    for _, target in ipairs(ctx.targets) do
        local win = target.window
        if win and win.workspace then
            return win.workspace
        end
    end
end

local function focused_index(ctx)
    local active = hl.get_active_window()
    if not active or active.floating then
        return nil
    end
    for i, target in ipairs(ctx.targets) do
        local win = target.window
        if win then
            if win.address == active.address then
                return i
            end
            -- A group is one layout target, even when another member has focus.
            if win.group then
                for _, member in ipairs(win.group.members or {}) do
                    if member.address == active.address then
                        return i
                    end
                end
            end
        end
    end
end

local function full_width(target, classes)
    local function tagged(win)
        if not win then return false end
        local class = win.class or win.initial_class
        if class and classes[tostring(class):lower()] then return true end
        local tags = win.tags or {}
        if type(tags) == "string" then
            for tag in tags:gmatch("[^,%s]+") do
                if tag == "zscroll-full" or tag == "zscroll-full*" then return true end
            end
        else
            for _, tag in ipairs(tags) do
                if tag == "zscroll-full" or tag == "zscroll-full*" then return true end
            end
        end
        return false
    end
    local win = target.window
    if tagged(win) then return true end
    if win and win.group then
        for _, member in ipairs(win.group.members or {}) do
            if tagged(member) then return true end
        end
    end
    return false
end

local function order_key(targets, classes)
    local ids = {}
    for i, target in ipairs(targets) do
        local win = target.window
        ids[i] = tostring(win and (win.stable_id or win.address) or i) .. (full_width(target, classes) and "!" or "")
    end
    return table.concat(ids, ":")
end

-- Preserve target order: a full-width target starts its own row, even if the
-- preceding row has an empty right slot. Pair ordinary targets after it anew.
local function pack(ctx)
    local count = sync_capacity()
    local classes = full_width_classes()
    local slots, packed = {}, {}
    local workspace = workspace_of(ctx)
    local partition = workspace and row_partitions[workspace.id]
    if partition and partition.order == order_key(ctx.targets, classes) then
        local index = 1
        for row, members in ipairs(partition.counts) do
            packed[row] = {}
            for column = 0, members - 1 do
                packed[row][column + 1] = index
                slots[index] = { row = row, column = column, full = full_width(ctx.targets[index], classes) }
                index = index + 1
            end
        end
        return slots, packed
    end
    if workspace then row_partitions[workspace.id] = nil end
    local open_row
    for i, target in ipairs(ctx.targets) do
        local full = full_width(target, classes)
        if full or not open_row then
            packed[#packed + 1] = {}
            open_row = #packed
        end
        local members = packed[open_row]
        slots[i] = { row = open_row, column = #members, full = full }
        members[#members + 1] = i
        if full or #members == count then open_row = nil end
    end
    return slots, packed
end

-- Keep keyboard width adjustments for an unchanged ordered row only.
local function sizes_for(ctx, packed, workspace)
    local count = capacity()
    local old = row_sizes[workspace.id] or {}
    local current, result = {}, {}
    for row, members in ipairs(packed) do
        local ids = { tostring(count) }
        for _, index in ipairs(members) do
            local win = ctx.targets[index].window
            ids[#ids + 1] = tostring(win and (win.stable_id or win.address) or index)
        end
        local key = table.concat(ids, ":")
        local sizes = old[key]
        if not sizes then
            sizes = {}
            for column = 1, count do sizes[column] = 1 / count end
        end
        current[key], result[row] = sizes, sizes
    end
    row_sizes[workspace.id] = current
    return result
end

local function recalculate(ctx)
    if reordering then return end
    local workspace = workspace_of(ctx)
    if not workspace or #ctx.targets == 0 then return end
    local slots, packed = pack(ctx)
    local sizes = sizes_for(ctx, packed, workspace)
    local center = bool_option("zscroll_center_incomplete_rows", false)
    -- A lone window has nothing to share its row with: give it the whole screen.
    local lone = #ctx.targets == 1 and bool_option("zscroll_single_window_fills", true)
    local i = focused_index(ctx)
    local row = i and slots[i].row or (rows[workspace.id] or 1)
    row = math.max(1, math.min(row, #packed))
    rows[workspace.id] = row
    local area = ctx.area
    for index, target in ipairs(ctx.targets) do
        local slot = slots[index]
        local fractions = sizes[slot.row]
        local start, occupied = 0, 0
        for column = 1, slot.column do start = start + fractions[column] end
        for column = 1, #packed[slot.row] do occupied = occupied + fractions[column] end
        local offset = center and not slot.full
            and math.floor((area.w - math.floor(area.w * occupied + 1e-7)) / 2) or 0
        local left = offset + math.floor(area.w * start + 1e-7)
        local right = offset + math.floor(area.w * (start + fractions[slot.column + 1]) + 1e-7)
        local whole = slot.full or lone
        local width = whole and area.w or right - left
        target:place({
            x = area.x + (whole and 0 or left),
            y = area.y + (slot.row - row) * area.h,
            w = width,
            h = area.h,
        })
    end
end

local function destination(ctx, i, direction)
    local slots, packed = pack(ctx)
    local slot = slots[i]
    local members = packed[slot.row]
    if direction == "next" then
        return math.min(i + 1, #ctx.targets)
    elseif direction == "prev" then
        return math.max(i - 1, 1)
    elseif direction == "l" then
        return members[math.max(1, slot.column)]
    elseif direction == "r" then
        return members[math.min(#members, slot.column + 2)]
    elseif direction == "u" or direction == "d" then
        local adjacent = packed[slot.row + (direction == "u" and -1 or 1)]
        return adjacent and adjacent[math.min(#adjacent, slot.column + 1)] or i
    end
end

local function resize_focused(ctx, delta)
    local workspace, i = workspace_of(ctx), focused_index(ctx)
    if not workspace or not i or capacity() == 1 then return end
    local slots, packed = pack(ctx)
    local slot = slots[i]
    if slot.full then return end
    local sizes = sizes_for(ctx, packed, workspace)[slot.row]
    local column = slot.column + 1
    local minimum = math.min(120 / ctx.area.w, 1 / capacity())
    local available = 0
    for j, size in ipairs(sizes) do
        if j ~= column then available = available + math.max(0, size - minimum) end
    end
    local change = math.max(minimum - sizes[column], math.min(delta, available))
    if math.abs(change) < 1e-10 then return end
    for j, size in ipairs(sizes) do
        if j ~= column then
            -- Growing borrows proportionally from slots with space to spare;
            -- shrinking returns space evenly, including unoccupied slots.
            local share = change > 0 and math.max(0, size - minimum) / available or 1 / (#sizes - 1)
            sizes[j] = size - change * share
        end
    end
    sizes[column] = sizes[column] + change
end

local function swap_row(ctx, direction)
    local workspace, i = workspace_of(ctx), focused_index(ctx)
    if not workspace or not i then return end
    local slots, packed = pack(ctx)
    local row = slots[i].row
    local adjacent = row + (direction == "u" and -1 or 1)
    if not packed[adjacent] then return end
    packed[row], packed[adjacent] = packed[adjacent], packed[row]
    local desired, counts, current = {}, {}, {}
    for index, target in ipairs(ctx.targets) do
        if not target.window then return end
        current[index] = target
    end
    for r, members in ipairs(packed) do
        counts[r] = #members
        for _, index in ipairs(members) do desired[#desired + 1] = ctx.targets[index] end
    end
    -- Native swaps recalculate synchronously. Wait until the whole permutation
    -- is finished so temporary pairings cannot discard the original row widths.
    reordering = true
    local ok, err = pcall(function()
        for index, target in ipairs(desired) do
            if current[index] ~= target then
                local other = index + 1
                while current[other] ~= target do other = other + 1 end
                hl.dispatch(hl.dsp.window.swap({ window = current[index].window, target = target.window }))
                current[index], current[other] = current[other], current[index]
            end
        end
    end)
    reordering = false
    if not ok then return "zscroll: row swap failed: " .. tostring(err) end
    -- Preserve partial rows too: moving a singleton ahead of a pair must not
    -- silently combine it with the first window of that pair.
    row_partitions[workspace.id] = { order = order_key(desired, full_width_classes()), counts = counts }
end

local function layout_msg(ctx, msg)
    if msg == "refresh" then
        return -- Hyprland calls recalculate after layout_msg returns.
    end
    local row_direction = msg:match("^swaprow ([ud])$")
    if row_direction then return swap_row(ctx, row_direction) end
    local resize_delta = msg:match("^resize ([+-][%d.]+)$")
    if resize_delta then
        resize_focused(ctx, tonumber(resize_delta))
        return
    end
    local capacity_delta = msg:match("^capacity ([+-]1)$")
    if capacity_delta then
        capacity_override = math.max(1, math.min(8, capacity() + tonumber(capacity_delta)))
        sync_capacity()
        hl.notification.create({ text = "zscroll: " .. capacity() .. " windows per row", duration = 1500, icon = "info" })
        return
    end
    local action, direction = msg:match("^(%S+)%s+(%S+)$")
    if action ~= "focus" and action ~= "swap" then
        return "zscroll: expected focus/swap next|prev|l|r|u|d, swaprow u|d, resize ±x, capacity ±1 or refresh"
    end
    local i = focused_index(ctx)
    if not i then
        return
    end
    local next_index = destination(ctx, i, direction)
    if not next_index then
        return "zscroll: unknown direction " .. tostring(direction)
    end
    if next_index == i then
        return
    end
    local win = ctx.targets[next_index].window
    if not win then
        return
    end
    if action == "swap" then
        -- Swap the actual layout targets, keeping native drag/swap order coherent.
        hl.dispatch(hl.dsp.window.swap({ target = win }))
    else
        hl.dispatch(hl.dsp.focus({ window = win }))
    end
end

hl.layout.register("zscroll", { recalculate = recalculate, layout_msg = layout_msg })

-- Focus events can run during window creation. Defer until target insertion
-- finishes, and coalesce bursts to avoid re-entering the layout callback.
local pending_open
local refresh_timer
local function refresh()
    refresh_timer = nil
    local workspace = active_workspace()
    local win = pending_open
    pending_open = nil
    if win and win.mapped and not win.floating and win.workspace and workspace
        and win.workspace.id == workspace.id and is_zscroll(workspace) then
        hl.dispatch(hl.dsp.focus({ window = win }))
    end
    if is_zscroll(workspace) then
        hl.dispatch(hl.dsp.layout("refresh"))
    end
end

local function queue_refresh()
    -- One-shot timers are destroyed after firing (Hyprland 0.56); their handles
    -- cannot be rearmed. Create a fresh one for each event burst.
    if not refresh_timer then
        refresh_timer = hl.timer(refresh, { timeout = 1, type = "oneshot" })
    end
end

hl.on("window.open", function(win)
    local workspace = active_workspace()
    -- Do not steal focus for apps routed to a background/special workspace.
    if win and not win.floating and win.workspace and workspace
        and win.workspace.id == workspace.id and is_zscroll(workspace) then
        if bool_option("zscroll_focus_new_windows", true) then
            pending_open = win
        end
        queue_refresh()
    end
end)
hl.on("window.active", queue_refresh)
hl.on("workspace.active", queue_refresh)
hl.on("workspace.special_active", queue_refresh)
hl.on("window.fullscreen", queue_refresh)
hl.on("workspace.removed", function(workspace)
    -- The Lua wrapper may survive the removed workspace; its id is then nil.
    local id = workspace and workspace.id
    if id ~= nil then
        rows[id] = nil
        row_sizes[id] = nil
        row_partitions[id] = nil
    end
end)

-- Wait until the layout has placed the destination row, then centre the pointer
-- in the newly focused window. Mouse clicks never come through here.
local pointer_generation = 0
local function center_pointer_after_navigation()
    if not bool_option("zscroll_pointer_follows", true) then return end
    pointer_generation = pointer_generation + 1
    local request = pointer_generation
    local focused = hl.get_active_window()
    local address = focused and focused.address
    if not address then return end
    hl.timer(function()
        local win = hl.get_active_window()
        if request ~= pointer_generation or not win or win.address ~= address then return end
        local at, size = win.at, win.size
        if at and size then
            hl.dispatch(hl.dsp.cursor.move({ x = at.x + size.x / 2, y = at.y + size.y / 2 }))
        end
    end, { timeout = 1, type = "oneshot" })
end

local function in_zscroll()
    local workspace = active_workspace()
    local win = hl.get_active_window()
    return is_zscroll(workspace) and win ~= nil and not win.floating
end

--- A callback for a shared key: zscroll's message in zscroll, `fallback` elsewhere.
function M.guarded(msg, fallback, navigates)
    return function()
        if in_zscroll() then
            hl.dispatch(hl.dsp.layout(msg))
            if navigates then center_pointer_after_navigation() end
        elseif fallback then
            hl.dispatch(fallback)
        end
    end
end

function M.resize_message(sign)
    return function()
        if in_zscroll() then
            hl.dispatch(hl.dsp.layout(string.format("resize %s%.3f", sign, resize_step())))
        else
            hl.dispatch(hl.dsp.focus({ direction = sign == "-" and "l" or "r" }))
        end
    end
end

function M.wheel(direction, fallback)
    return function()
        if bool_option("zscroll_wheel_rows", true) and in_zscroll() then
            hl.dispatch(hl.dsp.layout("focus " .. direction))
            center_pointer_after_navigation()
        else
            hl.dispatch(fallback)
        end
    end
end

-- ── Overview ────────────────────────────────────────────────────────────────
-- The scrolloverview plugin (github.com/yayuuu/hyprland-scroll-overview) zooms
-- out over the workspaces and their whole tape, as End4_plus uses it. It loads
-- after the config, so everything about it is looked up when Super is pressed.
local function scrolloverview()
    local plugin = hl.plugin and hl.plugin.scrolloverview
    return plugin and plugin.overview and plugin or nil
end

-- Load the plugin at startup once Settings has built it. The script refuses a
-- .so built for another Hyprland commit, which could take the compositor down.
hl.on("hyprland.start", function()
    hl.exec_cmd("bash \"$HOME/.config/quickshell/$qsConfig/scripts/hyprland/scrolloverview.sh\" load")
end)

function M.overview_available()
    return scrolloverview() ~= nil
end

-- What the plugin sets while one of its overviews exists (applyInputConfigOverrides).
local OVERVIEW_OVERRIDES = {
    ["input:follow_mouse"] = 0,
    ["cursor:no_warps"] = 1,
    ["cursor:warp_on_change_workspace"] = 0,
}
local overrides_were_set = false

local function config_number(name)
    local ok, value = pcall(hl.get_config, name)
    if not ok then return nil end
    if type(value) == "boolean" then return value and 1 or 0 end
    return tonumber(value)
end

local function overview_overrides_applied()
    for name, value in pairs(OVERVIEW_OVERRIDES) do
        if config_number(name) ~= value then return false end
    end
    return true
end

local function run_overview(action)
    local plugin = scrolloverview()
    if not plugin then return false end
    local scale = tonumber(_G.zscroll_overview_scale) or 0.6
    local layout = _G.zscroll_overview_layout == "horizontal" and "horizontal" or "vertical"
    pcall(hl.config, { plugin = { scrolloverview = {
        scale = math.max(0.2, math.min(0.9, scale)),
        workspace_gap = 60,
        layout = layout,
        -- The vertical wheel always walks workspaces (and tilt/horizontal scroll
        -- the tape), whichever way they are stacked. The plugin's default turns
        -- the vertical wheel into column stepping when they sit side by side.
        input = { scrolling_mode = 2 },
        shadow = { enabled = false },
    } } })
    -- Inside a Lua keybind the plugin runs the action right away and returns
    -- nothing; anywhere else (hyprctl eval) it returns a plain function to call
    -- (never an hl.dsp descriptor, so it must not go through hl.dispatch()).
    local run = plugin.overview(action)
    if type(run) == "function" then run() end
    return true
end

-- The plugin is the overview of both scrolling layouts: zscroll and Hyprland's
-- native `scrolling`, whose tape it was written for.
local function is_scrolling(workspace)
    return workspace ~= nil and (workspace.tiled_layout == NAME or workspace.tiled_layout == "scrolling")
end

function M.plugin_overview_wanted()
    return bool_option("zscroll_super_overview", true) and is_scrolling(active_workspace())
        and scrolloverview() ~= nil
end

--- Called by the shell (hyprctl eval) as its search opens and closes. Super keeps
--- the shell's own bind, so the search always opens; on a zscroll workspace with
--- the plugin loaded the shell stands its overview aside and the plugin's opens
--- behind the search bar (the plugin hands keys to a focused top layer). The same
--- goes for workspaces on the native scrolling layout. Opening
--- returns false where the plugin is not wanted; the shell then draws its own.
function M.shell_overview(open)
    if open then
        if not M.plugin_overview_wanted() then return false end
        overrides_were_set = overview_overrides_applied()
        return run_overview("open")
    end
    run_overview("close")
    return true
end

--- Whether the plugin's overview is still up. It has no query for that, but while
--- an overview exists it pins these options (restored when it is torn down, after
--- its close animation); the shell polls this after a workspace or window change
--- to tell "walked to another workspace inside the overview" from "picked one and
--- left". If the user's own config already had those values, it cannot tell and
--- answers true, so the search is never closed under them.
function M.plugin_overview_open()
    if not scrolloverview() then return false end
    return overrides_were_set or overview_overrides_applied()
end

-- ── Shortcuts ────────────────────────────────────────────────────────────────
-- Each replaces the default bind with a guarded one that does the old thing
-- outside zscroll, so every other layout behaves exactly as before.
local function rebind(key, action, opts)
    pcall(hl.unbind, key)
    hl.bind(key, action, opts)
end

if bool_option("zscroll_keybinds", false) then
    for key, direction in pairs({ Left = "l", Right = "r", Up = "u", Down = "d" }) do
        rebind("SUPER + " .. key, M.guarded("focus " .. direction, hl.dsp.focus({ direction = direction }), true))
        rebind("SUPER + SHIFT + " .. key, M.guarded("swap " .. direction, hl.dsp.window.move({ direction = direction }), false))
    end
    rebind("SUPER + BracketLeft", M.resize_message("-"), { repeating = true })
    rebind("SUPER + BracketRight", M.resize_message("+"), { repeating = true })
    rebind("SUPER + Semicolon", M.guarded("capacity -1", hl.dsp.layout("splitratio -0.1"), false), { repeating = true })
    rebind("SUPER + Apostrophe", M.guarded("capacity +1", hl.dsp.layout("splitratio +0.1"), false), { repeating = true })
    -- Super+Shift+PgUp/PgDn sent the window to the next workspace; inside zscroll
    -- they move the whole row instead.
    rebind("SUPER + SHIFT + Page_up", M.guarded("swaprow u", hl.dsp.window.move({ workspace = "-1" }), true))
    rebind("SUPER + SHIFT + Page_down", M.guarded("swaprow d", hl.dsp.window.move({ workspace = "+1" }), true))
end

-- Super+wheel walks rows on zscroll. It has its own toggle, so it is not tied to
-- the shortcuts above; the guarded bind switches workspaces exactly like the
-- default everywhere else (and on zscroll with the toggle off, read per scroll).
if bool_option("zscroll_wheel_rows", true) then
    rebind("SUPER + mouse_up", M.wheel("u", hl.dsp.focus({ workspace = "-1" })))
    rebind("SUPER + mouse_down", M.wheel("d", hl.dsp.focus({ workspace = "+1" })))
end

-- Super is left exactly as hyprland/keybinds.lua binds it: it always opens the
-- shell's search, which calls M.shell_overview() to bring the plugin's overview
-- up behind its bar. Taking Super for the plugin alone left zscroll with no way
-- to search, and wrapping the shell's global in a Lua bind lost its release.

return M
