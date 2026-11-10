-- Touchpad gestures
--
-- Every gesture this config registers goes through ii_gestures.apply(), which remembers
-- what it registered. Hyprland keeps the *first* gesture on a finger count and axis and
-- rejects a later one, and "unset" only removes an exact match - so replacing a set means
-- taking the previous one away first, and only the code that registered it knows what
-- that was.
--
-- The list comes from one of two places:
--   - the shell's snapshot (Settings -> Touchpad gestures): a Lua table the shell writes
--     from its config.json. It is read here, at config load, so the chosen layout survives
--     the shell being down; the shell only calls ii_gestures.reload() when the list changes.
--   - ii_gestures.defaults below, when there is no snapshot.
--
-- Hyprland's own actions (workspace, move, float, ...) are registered as native gestures.
-- The shell has no part in them while they run; it is only ever on the other end of the
-- "shell" and "tracked" kinds, which reach it as a custom event on the event socket.

ii_gestures = { version = 1 }

local EVENT_PREFIX = "iigesture,"

local function emit(payload)
    hl.dispatch(hl.dsp.event(EVENT_PREFIX .. payload))
end

-- Scratchpad gestures
-- Canonical pair: toggle_special("special") and workspace "special:special" both
-- resolve the workspace by name, so they always target the same workspace ID.
-- (A bare "special" move target bypasses the name lookup and can create a second
-- workspace with the same name but a different ID.)
local SCRATCH_TOGGLE = "special"
local SCRATCH_WS = "special:special"

-- Window object, not an address string: the weak ref expires when the window
-- closes (fields read as nil), whereas addresses are heap pointers that can be
-- reused by a later window.
local last_sent = nil

local function in_scratchpad(win)
    local ws = win and win.workspace
    return ws ~= nil and ws.name == SCRATCH_WS
end

-- Manual filter instead of hl.get_windows({ workspace = ... }): resolving a
-- workspace selector can create the workspace as a side effect.
local function any_scratchpad_window()
    for _, w in ipairs(hl.get_windows()) do
        if in_scratchpad(w) then return w end
    end
    return nil
end

local function show_scratchpad_and_refocus()
    hl.dispatch(hl.dsp.workspace.toggle_special(SCRATCH_TOGGLE))
    if in_scratchpad(last_sent) then
        hl.dispatch(hl.dsp.focus({ window = last_sent }))
    else
        last_sent = nil
    end
end

local function handle_scratchpad_gesture(direction)
    local monitor = hl.get_active_monitor()
    if not monitor then return end

    local special = monitor.active_special_workspace
    local scratch_visible = special ~= nil and special.name == SCRATCH_WS

    if direction == "up" then
        if scratch_visible then
            local win = hl.get_active_window()
            if in_scratchpad(win) then
                -- Retrieve the focused window to the regular workspace; the
                -- scratchpad auto-hides via binds:hide_special_on_workspace_change.
                if monitor.active_workspace then
                    hl.dispatch(hl.dsp.window.move({ workspace = monitor.active_workspace, window = win }))
                    if last_sent and last_sent.address == win.address then
                        last_sent = nil
                    end
                end
            else
                -- Focus is on a regular window below the overlay: focus the
                -- scratchpad (last-sent window if still there, else any of its
                -- windows); if the scratchpad is empty, hide it.
                local target = in_scratchpad(last_sent) and last_sent or any_scratchpad_window()
                if target then
                    hl.dispatch(hl.dsp.focus({ window = target }))
                else
                    hl.dispatch(hl.dsp.workspace.toggle_special(SCRATCH_TOGGLE))
                end
            end
        else
            -- Also replaces any other visible special workspace with the scratchpad.
            show_scratchpad_and_refocus()
        end
    elseif direction == "down" then
        if special then
            -- Hide whichever special workspace is visible (name is "special:<name>").
            hl.dispatch(hl.dsp.workspace.toggle_special(string.sub(special.name, 9)))
        else
            local win = hl.get_active_window()
            if win then
                hl.dispatch(hl.dsp.window.move({ workspace = SCRATCH_WS, window = win, follow = false }))
                -- Record only if the move actually landed the window there.
                if in_scratchpad(win) then
                    last_sent = win
                end
            end
        end
    end
end

-- Actions that only make sense written in Lua, offered to the shell by name.
ii_gestures.handlers = {
    scratchpadUp = function() handle_scratchpad_gesture("up") end,
    scratchpadDown = function() handle_scratchpad_gesture("down") end
}

-- What this config ships. The shell's own default list mirrors it
-- (Config.qml, interactions.touchpadGestures.bindings) - change both.
ii_gestures.defaults = {
    { fingers = 4, direction = "swipe", kind = "hyprland", action = "move" },
    { fingers = 4, direction = "pinch", kind = "hyprland", action = "float" },
    { fingers = 3, direction = "horizontal", kind = "hyprland", action = "workspace" },
    { fingers = 3, direction = "up", kind = "lua", action = "scratchpadUp" },
    { fingers = 3, direction = "down", kind = "lua", action = "scratchpadDown" }
}

local NATIVE_ACTIONS = {
    workspace = true, move = true, resize = true, special = true, close = true,
    float = true, fullscreen = true, cursor_zoom = true, scroll_move = true
}

local DIRECTIONS = {
    swipe = "swipe", horizontal = "horizontal", vertical = "vertical",
    left = "horizontal", right = "horizontal", up = "vertical", down = "vertical",
    pinch = "pinch", pinchin = "pinch", pinchout = "pinch"
}

-- Which way along which axis a one-direction swipe travels, for the tracked kind.
local TRAVEL = {
    up = { axis = "y", sign = -1 }, down = { axis = "y", sign = 1 },
    left = { axis = "x", sign = -1 }, right = { axis = "x", sign = 1 }
}

local function non_empty(value)
    return type(value) == "string" and value ~= ""
end

-- "super shift" and "SHIFT + SUPER" are the same modifier mask to Hyprland.
local function mods_key(mods)
    if not non_empty(mods) then return "" end
    local parts = {}
    for word in string.gmatch(string.upper(mods), "[%w_]+") do
        parts[#parts + 1] = word
    end
    table.sort(parts)
    return table.concat(parts, "+")
end

-- A swipe that follows the fingers: the shell gets where the gesture is, not just that
-- it happened. Travel is in touchpad pixels along the gesture's own direction, so it
-- only grows while the fingers keep going the way the gesture was bound.
local function tracked_action(entry, scale)
    local id = entry.action
    local travel_def = TRAVEL[entry.direction]
    local travel, sent, velocity, last_time = 0, 0, 0, 0

    return {
        start = function(event)
            travel, sent, velocity = 0, 0, 0
            last_time = event.time_ms or 0
            emit("begin," .. id .. "," .. entry.direction)
        end,
        update = function(event)
            local delta = event.delta and event.delta[travel_def.axis] or 0
            local step = delta * travel_def.sign * scale
            local now = event.time_ms or last_time
            local elapsed = now - last_time
            if elapsed > 0 then
                velocity = velocity * 0.5 + (step / elapsed * 1000) * 0.5
                last_time = now
            end
            travel = math.max(0, travel + step)

            -- Whole pixels only: a resting hand jitters by fractions, and each of
            -- those would otherwise be a frame for the shell to draw.
            local rounded = math.floor(travel + 0.5)
            if rounded == sent then return end
            sent = rounded
            emit("update," .. id .. "," .. rounded .. "," .. math.floor(velocity + 0.5))
        end,
        finish = function(event)
            emit("end," .. id .. "," .. (event.cancelled and 1 or 0) .. "," .. math.floor(velocity + 0.5))
        end
    }
end

-- The `action` Hyprland should get for an entry, or nil and why not.
local function build_action(entry, spec, scale)
    local kind, action, arg = entry.kind, entry.action, entry.arg

    if kind == "hyprland" then
        if not NATIVE_ACTIONS[action] then return nil, "unknown action" end
        if action == "special" and non_empty(arg) then spec.workspace_name = arg end
        if (action == "float" or action == "fullscreen" or action == "cursor_zoom") and non_empty(entry.mode) then
            spec.mode = entry.mode
        end
        if action == "cursor_zoom" and non_empty(arg) then spec.zoom_level = arg end
        return action
    end

    if kind == "lua" then
        local handler = ii_gestures.handlers[action]
        if not handler then return nil, "unknown handler" end
        return handler
    end

    if kind == "shell" then
        if not non_empty(action) then return nil, "no action" end
        local direction = entry.direction
        return function() emit("trigger," .. action .. "," .. direction) end
    end

    if kind == "tracked" then
        if not non_empty(action) then return nil, "no action" end
        if not TRAVEL[entry.direction] then return nil, "needs one direction" end
        return tracked_action(entry, scale)
    end

    if kind == "command" then
        if not non_empty(arg) then return nil, "no command" end
        return function() hl.dispatch(hl.dsp.exec_cmd(arg)) end
    end

    if kind == "dispatch" then
        if not non_empty(arg) then return nil, "no dispatcher" end
        local chunk = load("return " .. arg)
        if not chunk then return nil, "invalid Lua" end
        return function()
            local ok, dispatcher = pcall(chunk)
            if ok and dispatcher then hl.dispatch(dispatcher) end
        end
    end

    return nil, "unknown kind"
end

-- Exactly what was handed to hl.gesture, minus the action: what "unset" has to match.
local applied = {}

-- Hyprland's own rule for "an earlier gesture already covers this one".
local function shadowed_by(entry)
    local axis = DIRECTIONS[entry.direction]
    for _, other in ipairs(applied) do
        if other.fingers == entry.fingers and mods_key(other.mods) == mods_key(entry.mods) then
            if other.direction == axis or other.direction == entry.direction
                or ((axis == "vertical" or axis == "horizontal") and other.direction == "swipe") then
                return other
            end
        end
    end
    return nil
end

-- Replace everything this module registered with `list`. Returns "ok", or one
-- "index:reason" per entry that could not be registered, joined with ";".
function ii_gestures.apply(list)
    for _, spec in ipairs(applied) do
        hl.gesture({
            fingers = spec.fingers, direction = spec.direction, mods = spec.mods,
            scale = spec.scale, disable_inhibit = spec.disable_inhibit, action = "unset"
        })
    end
    applied = {}

    local problems = {}
    for index, entry in ipairs(type(list) == "table" and list or {}) do
        local problem = nil
        local fingers = tonumber(entry.fingers)
        local direction = type(entry.direction) == "string" and string.lower(entry.direction) or ""

        if not fingers or fingers < 2 or fingers > 9 or fingers ~= math.floor(fingers) then
            problem = "bad finger count"
        elseif not DIRECTIONS[direction] then
            problem = "bad direction"
        end

        if not problem then
            local scale = math.min(10, math.max(0.1, tonumber(entry.scale) or 1))
            local spec = { fingers = fingers, direction = direction, scale = scale }
            if non_empty(entry.mods) then spec.mods = entry.mods end
            if entry.disable_inhibit == true then spec.disable_inhibit = true end

            local normalised = { fingers = fingers, direction = direction, mods = spec.mods,
                kind = entry.kind, action = entry.action, arg = entry.arg, mode = entry.mode }
            local action, why = build_action(normalised, spec, scale)
            if not action then
                problem = why
            elseif shadowed_by(spec) then
                problem = "shadowed"
            else
                applied[#applied + 1] = { fingers = spec.fingers, direction = spec.direction, mods = spec.mods,
                    scale = spec.scale, disable_inhibit = spec.disable_inhibit }
                spec.action = action
                hl.gesture(spec)
            end
        end

        if problem then problems[#problems + 1] = index .. ":" .. problem end
    end

    return #problems == 0 and "ok" or table.concat(problems, ";")
end

local function snapshot_path()
    local state = os.getenv("XDG_STATE_HOME")
    if not non_empty(state) then state = os.getenv("HOME") .. "/.local/state" end
    return state .. "/quickshell/user/generated/touchpad_gestures.lua"
end

-- The snapshot is data: run it with no globals, so it can only ever build a table.
local function read_snapshot()
    local chunk = loadfile(snapshot_path(), "t", {})
    if not chunk then return nil end
    if setfenv then setfenv(chunk, {}) end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" or type(data.bindings) ~= "table" then return nil end
    return data
end

local last_result = "ok"
local last_source = "defaults"

-- (Re)apply the snapshot, or the defaults when there is none.
function ii_gestures.reload()
    local snapshot = read_snapshot()
    if not snapshot then
        last_source = "defaults"
        last_result = ii_gestures.apply(ii_gestures.defaults)
    elseif snapshot.enabled == false then
        last_source = "off"
        last_result = ii_gestures.apply({})
    else
        last_source = "snapshot"
        last_result = ii_gestures.apply(snapshot.bindings)
    end
    return last_result
end

-- Tell the shell how the last reload went. `hyprctl eval` does not hand a return
-- value back, so the answer travels the same way the gestures do.
function ii_gestures.report()
    emit("applied," .. ii_gestures.version .. "," .. last_source .. "," .. last_result)
end

ii_gestures.reload()
