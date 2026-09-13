#!/usr/bin/env python3
"""Round-trip tests for hyprgui.py. Run it directly: ./hyprgui_test.py"""
import json, os, shutil, subprocess, sys, tempfile

G = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hyprgui.py")
FAIL = []

ENV = dict(os.environ)

def run(args, stdin=None):
    p = subprocess.run([G] + args, input=stdin, capture_output=True, text=True, env=ENV)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

def check(name, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + name + (("  -- " + str(detail)) if not cond and detail else ""))
    if not cond: FAIL.append(name)

work = tempfile.mkdtemp(prefix="hyprgui-test-")
custom = os.path.join(work, "custom"); os.makedirs(custom)
ENV["XDG_STATE_HOME"] = os.path.join(work, "state")   # keep test backups out of ~/.local/state

HAND = '''-- hand written header
local function wanted_transform()
    return 0
end

hl.config({ input = { kb_layout = "fr" } })
hl.monitor({ output = "eDP-1", mode = "preferred" })
'''
target = os.path.join(custom, "general.lua")
open(target, "w").write(HAND)

NASTY = 'a"b\\c$|x'   # one quote, one backslash, a dollar and a pipe

DOC = {"version": 1, "entries": [
    {"kind": "config", "id": "input:kb_layout", "key": "input:kb_layout", "value": "us"},
    {"kind": "config", "id": "input:repeat_rate", "key": "input:repeat_rate", "value": 35},
    {"kind": "config", "id": "input:touchpad:tap-to-click", "key": "input:touchpad:tap-to-click", "value": True},
    {"kind": "config", "id": "cursor:inactive_timeout", "key": "cursor:inactive_timeout", "value": 3.5},
    {"kind": "device", "id": "mouse-1", "spec": {"name": "znt0001:00-14e5:e760-mouse", "sensitivity": -0.2}},
    {"kind": "env", "id": "XCURSOR_SIZE", "name": "XCURSOR_SIZE", "value": "24"},
    {"kind": "windowrule", "id": "w1", "spec": {"match": {"class": "^(kitty)$", "title": NASTY}, "float": True, "size": ["60%", "50%"]}},
    {"kind": "layerrule", "id": "l1", "spec": {"match": {"namespace": "^(waybar)$"}, "blur": True}},
    {"kind": "workspacerule", "id": "s1", "spec": {"workspace": "2", "persistent": True, "layout_opts": {"orientation": "left"}}},
    {"kind": "unbind", "id": "SUPER + T", "key": "SUPER + T"},
    {"kind": "bind", "id": "b1", "key": "SUPER + T", "dispatcher": {"__raw": "hl.dsp.exec_cmd(\"kitty -1\")"},
     "opts": {"description": "Terminal", "repeating": False}},
]}

rc, out, err = run(["write", "--file", target, "--json", "-", "--custom-dir", custom], json.dumps(DOC))
r = json.loads(out) if out.startswith("{") else {}
check("write succeeds", rc == 0 and r.get("ok") and r.get("changed"), out + err)

body = open(target).read()
check("hand-written header preserved", body.startswith(HAND.rstrip("\n").split("\n")[0]), body[:80])
check("wanted_transform preserved", "local function wanted_transform()" in body)
check("hl.monitor untouched", "hl.monitor({ output = \"eDP-1\", mode = \"preferred\" })" in body)
check("region at end of file", body.rstrip().endswith("-- <<< quickshell:managed:end"))
check("pre-fence kb_layout survives", body.count('hl.config({ input = { kb_layout = "fr" } })') == 1)

rc2, out2, _ = run(["write", "--file", target, "--json", "-", "--custom-dir", custom], json.dumps(DOC))
r2 = json.loads(out2)
check("second identical write is a no-op", r2.get("ok") and r2.get("changed") is False, out2)

rc3, out3, _ = run(["read", "--file", target])
back = json.loads(out3)
check("read finds the region", back["hasRegion"] and back["regionVersion"] == 1)
region_text = back.get("regionText", "")
check("read returns the region verbatim",
      region_text in body
      and region_text.startswith("-- >>> quickshell:managed:begin")
      and region_text.rstrip("\n").endswith("-- <<< quickshell:managed:end"),
      region_text[:80])
check("read reports the newest backup",
      isinstance(back.get("backup"), dict)
      and back["backup"]["count"] >= 1
      and back["backup"]["path"].startswith(os.path.join(work, "state")),
      back.get("backup"))
check("all entries round-trip", len(back["entries"]) == len(DOC["entries"]),
      [e.get("kind") for e in back["entries"]])
by_id = {e.get("id"): e for e in back["entries"]}
check("string value round-trips", by_id.get("input:kb_layout", {}).get("value") == "us")
check("int value round-trips", by_id.get("input:repeat_rate", {}).get("value") == 35)
check("bool value round-trips", by_id.get("input:touchpad:tap-to-click", {}).get("value") is True)
check("float value round-trips", by_id.get("cursor:inactive_timeout", {}).get("value") == 3.5)
check("dashed key written in Lua's underscore spelling, read back under its own id",
      'tap_to_click = true' in body and '"tap-to-click"' not in body.split("--@k")[0], body)
check("device spec round-trips", by_id.get("mouse-1", {}).get("spec", {}).get("sensitivity") == -0.2)
check("env round-trips", by_id.get("XCURSOR_SIZE", {}).get("value") == "24")
w1 = by_id.get("w1", {}).get("spec", {})
check("regex with $ | \\ and quote round-trips", w1.get("match", {}).get("title") == NASTY, w1)
check("array value round-trips", w1.get("size") == ["60%", "50%"])
check("nested rule table round-trips",
      by_id.get("s1", {}).get("spec", {}).get("layout_opts") == {"orientation": "left"})
check("unbind round-trips", by_id.get("SUPER + T", {}).get("kind") == "unbind")
b1 = by_id.get("b1", {})
check("bind dispatcher kept raw", b1.get("dispatcher") == {"__raw": 'hl.dsp.exec_cmd("kitty -1")'}, b1)
check("bind opts round-trip", b1.get("opts") == {"description": "Terminal", "repeating": False}, b1)
check("unmanaged pre-fence key reported",
      any(e["kind"] == "config" and e["key"] == "input:kb_layout" and e["value"] == "fr"
          for e in back["unmanaged"]), back["unmanaged"])

# Unknown lines inside the fence survive.
lines = open(target).read().split("\n")
idx = next(i for i, l in enumerate(lines) if l.startswith("hl.env"))
lines.insert(idx, 'hl.config({ future = { thing = 1 } })  --@z future:thing')
open(target, "w").write("\n".join(lines))
rc4, out4, _ = run(["read", "--file", target])
back4 = json.loads(out4)
raws = [e for e in back4["entries"] if e["kind"] == "raw"]
check("unknown tagged line kept as raw", len(raws) == 1 and "future" in raws[0]["text"], raws)

# Rewriting with the raw entry preserved keeps it verbatim.
doc2 = {"version": 1, "entries": back4["entries"]}
run(["write", "--file", target, "--json", "-", "--custom-dir", custom], json.dumps(doc2))
check("raw line survives a rewrite", "--@z future:thing" in open(target).read())

# Dry run does not touch the file.
before = open(target).read()
doc3 = {"version": 1, "entries": [DOC["entries"][0]]}
rc5, out5, _ = run(["write", "--file", target, "--json", "-", "--custom-dir", custom, "--dry-run"], json.dumps(doc3))
r5 = json.loads(out5)
check("dry-run returns a diff", r5.get("diff", "").startswith("---"), out5[:200])
check("dry-run leaves the file alone", open(target).read() == before)

# Strip removes the fence and nothing else.
rc6, out6, _ = run(["strip", "--file", target, "--custom-dir", custom])
after = open(target).read()
check("strip removes the region", "quickshell:managed" not in after, after[-200:])
check("strip keeps hand-written Lua", "local function wanted_transform()" in after and "hl.monitor" in after)

# Path guard.
outside = os.path.join(work, "main.lua"); open(outside, "w").write("-- upstream\n")
rc7, out7, err7 = run(["write", "--file", outside, "--json", "-", "--custom-dir", custom], json.dumps(DOC))
check("refuses to write outside custom/", rc7 != 0 and open(outside).read() == "-- upstream\n", err7)
rc8, out8, err8 = run(["write", "--file", os.path.join(custom, "..", "hyprland", "x.lua"),
                       "--json", "-", "--custom-dir", custom], json.dumps(DOC))
check("refuses traversal out of custom/", rc8 != 0, err8)

# Missing file gets created.
fresh = os.path.join(custom, "env.lua")
rc9, out9, _ = run(["write", "--file", fresh, "--json", "-", "--custom-dir", custom],
                   json.dumps({"version": 1, "entries": [DOC["entries"][5]]}))
r9 = json.loads(out9)
check("creates a missing file", r9.get("created") is True and os.path.exists(fresh), out9)
check("no backup for a created file", r9.get("backup") is None)
rc9b, out9b, _ = run(["read", "--file", fresh])
check("no backup reported for a never-backed-up file", json.loads(out9b).get("backup") is None, out9b)
check("backups land under XDG_STATE_HOME",
      os.path.isdir(os.path.join(work, "state", "quickshell", "hyprland-backups")))

# Empty entry list strips the region.
rc10, out10, _ = run(["write", "--file", fresh, "--json", "-", "--custom-dir", custom],
                     json.dumps({"version": 1, "entries": []}))
check("empty document removes the region", "quickshell:managed" not in open(fresh).read())

# ---------------------------------------------------------------- per-key lines
HAND2 = '''hl.config({
    input = {
        kb_layout = "fr",
        scroll_factor = 0.10,
        touchpad = {
            natural_scroll = true
        }
    },
    misc = {
        vrr = 1
    },
    decoration = {
        shadow = { color = "rgba" .. "(" .. "00000027)" }
    }
})
'''
multi = os.path.join(custom, "multi.lua")
open(multi, "w").write(HAND2)
back10 = json.loads(run(["read", "--file", multi])[1])
hand = {e["key"]: e for e in back10["unmanaged"] if e.get("kind") == "config"}
check("each key reports its own line",
      hand["input:kb_layout"]["line"] == 3 and hand["input:scroll_factor"]["line"] == 4
      and hand["misc:vrr"]["line"] == 10,
      {k: v.get("line") for k, v in hand.items()})
check("each key reports a span into the file",
      HAND2[slice(*hand["input:kb_layout"]["span"])] == 'kb_layout = "fr"',
      HAND2[slice(*hand["input:kb_layout"]["span"])])
check("a concatenated string stays raw instead of truncating",
      hand["decoration:shadow:color"]["value"] == {"__raw": '"rgba" .. "(" .. "00000027)"'},
      hand["decoration:shadow:color"]["value"])

# ---------------------------------------------------------------- drop-key
run(["write", "--file", multi, "--json", "-", "--custom-dir", custom],
    json.dumps({"version": 1, "entries": [DOC["entries"][0]]}))
region_before = json.loads(run(["read", "--file", multi])[1])["regionText"]
before_text = open(multi).read()
rc11, out11, _ = run(["drop-key", "--file", multi, "--key", "input:kb_layout",
                      "--custom-dir", custom, "--dry-run"])
r11 = json.loads(out11)
check("drop-key dry run returns a diff", r11.get("ok") and '-        kb_layout = "fr"' in r11.get("diff", ""),
      out11[:200])
check("drop-key dry run leaves the file alone", open(multi).read() == before_text)

rc12, out12, _ = run(["drop-key", "--file", multi, "--key", "input:kb_layout", "--custom-dir", custom])
r12 = json.loads(out12)
after_text = open(multi).read()
check("drop-key removes exactly one line",
      r12.get("ok") and after_text == before_text.replace('        kb_layout = "fr",\n', "", 1),
      r12.get("error"))
check("drop-key backs the file up first", bool(r12.get("backup")))
check("drop-key leaves the managed region byte for byte",
      json.loads(run(["read", "--file", multi])[1])["regionText"] == region_before)
check("drop-key leaves every other hand-written key alone",
      {e["key"] for e in json.loads(run(["read", "--file", multi])[1])["unmanaged"]
       if e.get("kind") == "config"}
      == {"input:scroll_factor", "input:touchpad:natural_scroll", "misc:vrr",
          "decoration:shadow:color"},
      [e.get("key") for e in json.loads(run(["read", "--file", multi])[1])["unmanaged"]])

rc13, out13, _ = run(["drop-key", "--file", multi, "--key", "input:kb_layout", "--custom-dir", custom])
check("drop-key on a key nobody set by hand fails", rc13 != 0 and json.loads(out13)["ok"] is False, out13)
rc14, _, err14 = run(["drop-key", "--file", outside, "--key", "input:kb_layout", "--custom-dir", custom])
check("drop-key refuses to touch a file outside custom/",
      rc14 != 0 and open(outside).read() == "-- upstream\n", err14)

# Emptying a table is not "changing another setting".
solo = os.path.join(custom, "solo.lua")
open(solo, "w").write('hl.config({ input = { kb_layout = "fr" } })\n')
rc15, out15, _ = run(["drop-key", "--file", solo, "--key", "input:kb_layout", "--custom-dir", custom])
check("drop-key can empty a table", json.loads(out15).get("ok") is True, out15)
check("emptied table is still valid Lua", "input = {  }" in open(solo).read() or "input = { }" in open(solo).read(),
      open(solo).read())

# ── A value that is itself a table ────────────────────────────────────────────
# A gradient is { colors = {...}, angle = n } and four gaps are named sides. Flattening those
# the way a plain hl.config table is flattened turns one key into two that were never written,
# and the browser could then neither reset nor re-edit what it had just set. The tag says where
# the key ends, so the tag is what decides.
nested = os.path.join(custom, "nested.lua")
open(nested, "w").write("-- header\n")
doc = {"version": 1, "entries": [
    {"kind": "config", "key": "general:col.nogroup_border",
     "value": {"colors": ["0xaaffb59b", "0x66aabbcc"], "angle": 45}},
    {"kind": "config", "key": "general:float_gaps",
     "value": {"top": 5, "right": 8, "bottom": 5, "left": 8}},
    {"kind": "config", "key": "decoration:shadow:offset", "value": [3, -7]},
]}
run(["write", "--file", nested, "--json", "-", "--custom-dir", custom], json.dumps(doc))
_, out16, _ = run(["read", "--file", nested])
back = {e["key"]: e["value"] for e in json.loads(out16)["entries"] if e.get("kind") == "config"}
check("a table value keeps the key it was written under",
      sorted(back) == ["decoration:shadow:offset", "general:col.nogroup_border",
                       "general:float_gaps"], sorted(back))
check("a gradient table round-trips whole",
      back.get("general:col.nogroup_border") == {"colors": ["0xaaffb59b", "0x66aabbcc"],
                                                 "angle": 45},
      back.get("general:col.nogroup_border"))
check("named gaps round-trip whole",
      back.get("general:float_gaps") == {"top": 5, "right": 8, "bottom": 5, "left": 8},
      back.get("general:float_gaps"))
check("a list value round-trips whole", back.get("decoration:shadow:offset") == [3, -7],
      back.get("decoration:shadow:offset"))

shutil.rmtree(work)
print()
print("%d failed" % len(FAIL) if FAIL else "all passed")
sys.exit(1 if FAIL else 0)
