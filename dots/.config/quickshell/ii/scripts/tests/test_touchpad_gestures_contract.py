#!/usr/bin/env python3
"""Contract for the touchpad gesture module the compositor loads (hypr/hyprland/gestures.lua).

The module is run for real under a stand-in `hl` that enforces the two Hyprland rules the
whole design exists to satisfy: the first gesture on a finger count and axis wins, and
"unset" only removes an exact match. A registration Hyprland would reject shows up here
as an error line instead of as a red bar on somebody's screen.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GESTURES_LUA = ROOT.parents[1] / "hypr" / "hyprland" / "gestures.lua"
GENERAL_LUA = ROOT.parents[1] / "hypr" / "hyprland" / "general.lua"
CONFIG_QML = ROOT / "modules" / "common" / "Config.qml"
LUA = shutil.which("lua") or shutil.which("lua5.4")

HARNESS = r"""
local registered, errors, events = {}, {}, {}

local AXIS = { up = "vertical", down = "vertical", vertical = "vertical",
    left = "horizontal", right = "horizontal", horizontal = "horizontal",
    swipe = "swipe", pinch = "pinch", pinchin = "pinch", pinchout = "pinch" }

local function mods_of(spec) return string.upper(spec.mods or "") end

hl = {
    gesture = function(spec)
        local scale, inhibit = spec.scale or 1, spec.disable_inhibit or false
        if spec.action == "unset" then
            for i, g in ipairs(registered) do
                if g.fingers == spec.fingers and g.direction == spec.direction and mods_of(g) == mods_of(spec)
                    and g.scale == scale and g.disable_inhibit == inhibit then
                    table.remove(registered, i)
                    return
                end
            end
            errors[#errors + 1] = "unset-missing " .. spec.fingers .. " " .. spec.direction
            return
        end
        local axis = AXIS[spec.direction]
        for _, g in ipairs(registered) do
            if g.fingers == spec.fingers and mods_of(g) == mods_of(spec) then
                if g.direction == axis or g.direction == spec.direction
                    or ((axis == "vertical" or axis == "horizontal") and g.direction == "swipe") then
                    errors[#errors + 1] = "shadowed " .. spec.fingers .. " " .. spec.direction
                    return
                end
            end
        end
        registered[#registered + 1] = { fingers = spec.fingers, direction = spec.direction, mods = spec.mods,
            scale = scale, disable_inhibit = inhibit, action = spec.action, spec = spec }
    end,
    dispatch = function(d)
        if type(d) == "table" and d.event then events[#events + 1] = d.event end
        if type(d) == "table" and d.cmd then events[#events + 1] = "exec:" .. d.cmd end
        if type(d) == "table" and d.tag then events[#events + 1] = "dispatch:" .. d.tag end
    end,
    dsp = {
        event = function(s) return { event = s } end,
        exec_cmd = function(c) return { cmd = c } end,
        focus = function() return { tag = "focus" } end,
        workspace = { toggle_special = function() return { tag = "toggle_special" } end },
        window = { move = function() return { tag = "move" } end, close = function() return { tag = "close" } end }
    },
    get_active_monitor = function() return nil end,
    get_active_window = function() return nil end,
    get_windows = function() return {} end
}

dofile(GESTURES_PATH)

local function find(fingers, direction)
    for _, g in ipairs(registered) do
        if g.fingers == fingers and g.direction == direction then return g end
    end
end

local function show(label)
    local parts = {}
    for _, g in ipairs(registered) do
        parts[#parts + 1] = g.fingers .. ":" .. g.direction .. ":" .. type(g.action)
            .. (type(g.action) == "string" and ("=" .. g.action) or "")
    end
    print(label .. " registered=" .. table.concat(parts, " "))
    print(label .. " errors=" .. table.concat(errors, "|"))
    print(label .. " events=" .. table.concat(events, "|"))
    errors, events = {}, {}
end

show("load")

print("custom result=" .. ii_gestures.apply({
    { fingers = 3, direction = "horizontal", kind = "hyprland", action = "workspace" },
    { fingers = 3, direction = "up", kind = "shell", action = "overview" },
    { fingers = 3, direction = "vertical", kind = "command", arg = "true" },
    { fingers = 4, direction = "left", kind = "tracked", action = "sidebarRight", scale = 2 },
    { fingers = 4, direction = "left", kind = "hyprland", action = "close" },
    { fingers = 4, direction = "swipe", mods = "SUPER", kind = "hyprland", action = "bogus" },
    { fingers = 4, direction = "pinch", kind = "tracked", action = "overview" },
    { fingers = 5, direction = "pinchin", kind = "dispatch", arg = "hl.dsp.window.close()" },
    { fingers = 5, direction = "up", kind = "hyprland", action = "special", arg = "magic" },
    { fingers = 12, direction = "up", kind = "hyprland", action = "close" },
    { fingers = 3, direction = "sideways", kind = "hyprland", action = "close" }
}))
print("special name=" .. tostring(find(5, "up").spec.workspace_name))
find(3, "up").action()
find(3, "vertical").action()
find(5, "pinchin").action()

local tracked = find(4, "left").action
tracked.start({ time_ms = 1000 })
tracked.update({ time_ms = 1010, delta = { x = -0.2, y = 0 } })
tracked.update({ time_ms = 1020, delta = { x = -5, y = 3 } })
tracked.update({ time_ms = 1030, delta = { x = -5, y = 0 } })
tracked.update({ time_ms = 1040, delta = { x = 30, y = 0 } })
tracked.finish({ time_ms = 1050, cancelled = false })
show("custom")

print("again result=" .. ii_gestures.apply(ii_gestures.defaults))
show("again")

print("reload result=" .. ii_gestures.reload())
ii_gestures.report()
show("reload")
"""


def run_module(state_home):
    env = dict(os.environ, XDG_STATE_HOME=str(state_home))
    script = "GESTURES_PATH = %r\n%s" % (str(GESTURES_LUA), HARNESS)
    done = subprocess.run([LUA, "-"], input=script, capture_output=True, text=True, env=env, timeout=20)
    if done.returncode != 0:
        raise AssertionError(done.stderr)
    lines = {}
    for line in done.stdout.splitlines():
        key, _, value = line.partition("=")
        lines[key] = value
    return lines


def write_snapshot(state_home, text):
    target = Path(state_home) / "quickshell" / "user" / "generated"
    target.mkdir(parents=True)
    (target / "touchpad_gestures.lua").write_text(text, encoding="utf-8")


DEFAULT_REGISTRATION = ("4:swipe:string=move 4:pinch:string=float 3:horizontal:string=workspace "
                        "3:up:function 3:down:function")


@unittest.skipUnless(LUA, "no lua interpreter installed")
class TouchpadGestureModuleContracts(unittest.TestCase):
    def test_defaults_register_cleanly_when_there_is_no_snapshot(self):
        with tempfile.TemporaryDirectory() as state:
            out = run_module(state)
        self.assertEqual(out["load registered"], DEFAULT_REGISTRATION)
        self.assertEqual(out["load errors"], "")

    def test_a_new_set_replaces_the_old_one_without_a_rejected_registration(self):
        with tempfile.TemporaryDirectory() as state:
            out = run_module(state)
        # Entries 5-7 and 10-11 are wrong on purpose; each is reported, none reaches Hyprland.
        self.assertEqual(out["custom result"],
                         "5:shadowed;6:unknown action;7:needs one direction;10:bad finger count;11:bad direction")
        self.assertEqual(out["custom registered"],
                         "3:horizontal:string=workspace 3:up:function 3:vertical:function 4:left:table "
                         "5:pinchin:function 5:up:string=special")
        self.assertEqual(out["custom errors"], "")
        self.assertEqual(out["special name"], "magic")
        self.assertEqual(out["again result"], "ok")
        self.assertEqual(out["again registered"], DEFAULT_REGISTRATION)
        self.assertEqual(out["again errors"], "")

    def test_shell_actions_travel_as_custom_events(self):
        with tempfile.TemporaryDirectory() as state:
            out = run_module(state)
        events = out["custom events"].split("|")
        self.assertEqual(events[:3], ["iigesture,trigger,overview,up", "exec:true", "dispatch:close"])

    def test_a_tracked_gesture_reports_whole_pixels_along_its_own_direction(self):
        with tempfile.TemporaryDirectory() as state:
            out = run_module(state)
        tracked = [e for e in out["custom events"].split("|") if e.startswith("iigesture,") and "trigger" not in e]
        self.assertEqual(tracked[0], "iigesture,begin,sidebarRight,left")
        # scale 2: 0.4 px rounds to nothing and is not sent; then 10, 20, and back to 0.
        travels = [e.split(",")[3] for e in tracked if e.split(",")[1] == "update"]
        self.assertEqual(travels, ["10", "20", "0"])
        self.assertTrue(tracked[-1].startswith("iigesture,end,sidebarRight,0,"))

    def test_the_snapshot_wins_over_the_defaults_and_can_switch_gestures_off(self):
        with tempfile.TemporaryDirectory() as state:
            write_snapshot(state, 'return { version = 1, enabled = true, bindings = {\n'
                                  '    { fingers = 3, direction = "up", kind = "shell", action = "overview" },\n} }\n')
            out = run_module(state)
        self.assertEqual(out["load registered"], "3:up:function")
        self.assertEqual(out["reload events"], "iigesture,applied,1,snapshot,ok")

        with tempfile.TemporaryDirectory() as state:
            write_snapshot(state, "return { version = 1, enabled = false, bindings = {} }\n")
            out = run_module(state)
        self.assertEqual(out["load registered"], "")
        self.assertEqual(out["reload events"], "iigesture,applied,1,off,ok")

    def test_a_broken_or_hostile_snapshot_falls_back_to_the_defaults(self):
        for text in ("return {", "return 5", 'os.execute("true") return { bindings = {} }'):
            with tempfile.TemporaryDirectory() as state:
                write_snapshot(state, text)
                out = run_module(state)
            self.assertEqual(out["load registered"], DEFAULT_REGISTRATION, text)
            self.assertEqual(out["load errors"], "", text)


class TouchpadGestureDefaultsContracts(unittest.TestCase):
    ENTRY = re.compile(r'fingers"?\s*[:=]\s*(\d+),\s*"?direction"?\s*[:=]\s*"(\w+)",\s*"?kind"?\s*[:=]\s*"(\w+)",'
                       r'\s*"?action"?\s*[:=]\s*"(\w+)"')

    def test_the_shell_and_the_compositor_ship_the_same_defaults(self):
        lua = GESTURES_LUA.read_text(encoding="utf-8")
        lua_block = lua[lua.index("ii_gestures.defaults = {"):]
        lua_block = lua_block[:lua_block.index("\n}")]
        qml = CONFIG_QML.read_text(encoding="utf-8")
        qml_block = qml[qml.index("property JsonObject touchpadGestures"):]
        qml_block = qml_block[qml_block.index("property list<var> bindings: ["):]
        qml_block = qml_block[:qml_block.index("]")]
        self.assertEqual(self.ENTRY.findall(lua_block), self.ENTRY.findall(qml_block))
        self.assertEqual(len(self.ENTRY.findall(lua_block)), 5)

    def test_gestures_are_registered_in_one_place(self):
        self.assertNotIn("hl.gesture(", GENERAL_LUA.read_text(encoding="utf-8"))
        self.assertIn('pcall(require, "hyprland.gestures")', GENERAL_LUA.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
