// Run with node scripts/tests/test_window_switcher_binds.cjs (needs `lua` on PATH)
//
// Behaviour of the Hyprland binds Alt+Tab puts on at runtime. The Lua that WindowSwitcher.qml
// generates (defineChunk, entryChunk, searchChunk, restoreChunk) is rendered from the QML
// source as the service renders it, then run in a real Lua interpreter against a stand-in for
// Hyprland's `hl` that keeps binds per submap, matches key presses the way Hyprland does
// (exact combination, then ignore_mods, then the catch-all; releases against transparent root
// binds too) and records the globals sent to the shell. Each scenario is a key sequence and
// the globals and submap it must end with.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const service = fs.readFileSync(path.join(root, 'services/WindowSwitcher.qml'), 'utf8');

// ---------------------------------------------------------------- render the QML's Lua

function stringProperty(name, endMarker) {
    const start = service.indexOf(`readonly property string ${name}: \``);
    if (start < 0)
        throw new Error(`no ${name} in WindowSwitcher.qml`);
    const open = service.indexOf('`', start) + 1;
    const end = service.indexOf(endMarker, open) + endMarker.length - 1;
    return service.slice(open, end);
}

function functionSource(name) {
    const start = service.indexOf(`function ${name}(`);
    const end = service.indexOf('\n    }\n', start) + 6;
    // Drop the QML type annotations so plain JS can run it.
    return service.slice(start, end).replace(/\((.*?)\): \w+ \{/, (_, args) => `(${args.replace(/: \w+/g, '')}) {`);
}

function propertyValue(name) {
    const m = new RegExp(`readonly property string ${name}: "([^"]*)"`).exec(service);
    if (!m)
        throw new Error(`no ${name}`);
    return m[1];
}

const stub = {
    submapName: propertyValue('submapName'),
    typingSubmapName: propertyValue('typingSubmapName'),
    bindTag: propertyValue('bindTag'),
    bindDescription: propertyValue('bindDescription'),
    bindDescriptionBack: propertyValue('bindDescriptionBack'),
    bindDescriptionSame: propertyValue('bindDescriptionSame'),
    bindDescriptionSameBack: propertyValue('bindDescriptionSameBack'),
    sameAppKey: propertyValue('sameAppKey'),
    searchKeys: 'abcdefghijklmnopqrstuvwxyz'.split('').concat(['space']),
    digitKeys: '1234567890'.split(''),
    sameAppConflict: false
};
const render = template => new Function('root', `return \`${template}\`;`)(stub);
stub.restoreAnimationsLua = render(stringProperty('restoreAnimationsLua', 'end`'));
const defineChunk = render(stringProperty('defineChunk', '\nend`'));
const restoreChunk = render(stringProperty('restoreChunk', '\nend`'));
stub.searchKeyBind = new Function('root', `return function ${functionSource('searchKeyBind').slice('function '.length)}`)(stub);
const entryChunk = new Function('root', `return function ${functionSource('entryChunk').slice('function '.length)}`)(stub);
const searchChunk = new Function('root', `return function ${functionSource('searchChunk').slice('function '.length)}`)(stub);

// ---------------------------------------------------------------- the stand-in compositor

const harness = String.raw`
local binds = {}            -- submap -> { { combo, fn, opts } }
local defining = nil
current = ""
globals = {}
config = { animations = { enabled = true } }
props = {}
hl = {}
local function key_of(combo) return (combo:match("([^%s+]+)$")) end
function hl.bind(combo, fn, opts)
  local m = defining or ""
  binds[m] = binds[m] or {}
  table.insert(binds[m], { combo = combo, fn = fn, opts = opts or {} })
end
function hl.unbind(combo)
  for _, list in pairs(binds) do
    for i = #list, 1, -1 do if list[i].combo == combo then table.remove(list, i) end end
  end
end
function hl.define_submap(name, fn) local prev = defining; defining = name; fn(); defining = prev end
function hl.get_current_submap() return current end
function hl.get_config(k) if k == "animations.enabled" then return config.animations.enabled end end
function hl.config(t) if t.animations then config.animations.enabled = t.animations.enabled end end
local now, timers = 0, {}
function hl.timer(fn, opts) table.insert(timers, { at = now + (opts and opts.timeout or 0), fn = fn }); return {} end
function advance(ms)
  now = now + ms
  local fired = true
  while fired do
    fired = false
    for i, t in ipairs(timers) do
      if t.at <= now then table.remove(timers, i); t.fn(); fired = true; break end
    end
  end
end
hl.dsp = {
  submap = function(n) return { t = "submap", n = n } end,
  global = function(n) return { t = "global", n = n } end,
  window = { set_prop = function(a) return { t = "prop", a = a } end },
}
function hl.dispatch(d)
  if d.t == "submap" then current = (d.n == "reset") and "" or d.n
  elseif d.t == "global" then sent_global = true; table.insert(globals, (d.n:gsub("^quickshell:windowSwitcher", "")))
  elseif d.t == "prop" then props[d.a.window] = d.a.value end
end
function count(submap, combo)
  local n = 0
  for _, b in ipairs(binds[submap] or {}) do if b.combo == combo then n = n + 1 end end
  return n
end
-- One tap of the key a bind matched. Hyprland 0.56 runs the function a second time as the key
-- comes up whenever the function dispatched a global itself.
local function tap(b)
  sent_global = false
  b.fn()
  local again = sent_global
  advance(1)
  if again then b.fn() end
  return true
end
-- A key going down as Hyprland matches it: the exact combination, else a bind ignoring
-- modifiers on the same key, else the catch-all - all in the current submap only.
function press(combo)
  local list = binds[current] or {}
  for _, b in ipairs(list) do
    if b.combo == combo and not b.opts.release then return tap(b) end
  end
  for _, b in ipairs(list) do
    if b.opts.ignore_mods and not b.opts.release and key_of(b.combo) == key_of(combo) then return tap(b) end
  end
  for _, b in ipairs(list) do
    if b.combo == "catchall" then return tap(b) end
  end
  return false
end
-- A key coming up: release binds in the current submap, and transparent ones in the root.
function release(key)
  local fired = {}
  for _, m in ipairs({ current, "" }) do
    for _, b in ipairs(binds[m] or {}) do
      if b.opts.release and key_of(b.combo) == key and (m == current or b.opts.transparent) and not fired[b] then
        fired[b] = true; b.fn()
        if m == current and current ~= "" then return end
      end
    end
  end
end
function take() advance(1); local g = table.concat(globals, ","); globals = {}; return g end
function expect(what, got, want)
  if got ~= want then error(what .. ": got [" .. tostring(got) .. "] want [" .. tostring(want) .. "]", 2) end
end
`;

function runLua(body) {
    const file = path.join(os.tmpdir(), `ws-binds-${process.pid}-${Math.random().toString(36).slice(2)}.lua`);
    fs.writeFileSync(file, `${harness}\n${body}\n`);
    try {
        return execFileSync('lua', [file], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } finally {
        fs.unlinkSync(file);
    }
}

const setup = `${defineChunk}\n${entryChunk(true, true)}\n${searchChunk(false, {})}\n`;
const S = stub.submapName;
const T = stub.typingSubmapName;

let failures = 0;
function scenario(name, body) {
    try {
        runLua(`${setup}\n${body}`);
        console.log(`ok - ${name}`);
    } catch (error) {
        failures++;
        console.log(`not ok - ${name}\n  ${String(error.stderr || error.message).trim().split('\n').join('\n  ')}`);
    }
}

scenario('Alt+Tab enters the hold submap; Alt up switches and leaves it', `
press("ALT + Tab"); expect("submap", current, "${S}"); expect("globals", take(), "Next")
press("ALT + Tab"); expect("globals", take(), "Next")
press("ALT + SHIFT + Tab"); expect("globals", take(), "Prev")
release("ALT_L"); expect("submap", current, ""); expect("globals", take(), "Commit")
`);

scenario('a stray Alt release outside the switcher does nothing', `
release("ALT_L"); expect("globals", take(), ""); expect("submap", current, "")
`);

scenario('keys mid-switch never reach a window', `
press("ALT + Tab"); take()
expect("swallowed", press("ALT + F4"), true); expect("globals", take(), ""); expect("submap", current, "${S}")
`);

scenario('Alt up with a search typed keeps it open in the typing submap', `
press("ALT + Tab"); take()
press("ALT + f"); press("ALT + SHIFT + i"); expect("globals", take(), "Key_f,Key_i")
release("ALT_L"); expect("submap", current, "${T}"); expect("globals", take(), "Release")
press("r"); press("SHIFT + e"); expect("globals", take(), "Key_r,Key_e")
press("Tab"); press("SHIFT + Tab"); press("ALT + Tab"); expect("globals", take(), "Next,Prev,Next")
press("Return"); expect("submap", current, ""); expect("globals", take(), "Commit")
`);

scenario('Escape in the typing submap cancels and leaves it', `
press("ALT + Tab"); press("ALT + a"); release("ALT_R"); take()
press("Escape"); expect("submap", current, ""); expect("globals", take(), "Cancel")
`);

scenario('Backspace back to nothing: Alt up switches again', `
press("ALT + Tab"); press("ALT + a"); press("BackSpace"); take()
release("ALT_L"); expect("submap", current, ""); expect("globals", take(), "Commit")
`);

scenario('Escape with Alt held clears the search first, then cancels', `
press("ALT + Tab"); press("ALT + a"); take(); expect("typed", __ii_alt_tab_q, 1)
press("Escape"); expect("submap", current, "${S}"); expect("globals", take(), "Escape")
release("ALT_L"); expect("after clearing, release switches", take(), "Commit")
press("ALT + Tab"); take()
press("Escape"); expect("submap", current, ""); expect("globals", take(), "Cancel")
`);

scenario('Alt+1…9 jump with nothing typed, type once a search is going', `
press("ALT + Tab"); take()
press("ALT + code:10"); press("ALT + code:18"); expect("globals", take(), "Jump_1,Jump_9")
press("ALT + code:19"); expect("0 types", take(), "Key_0")
press("ALT + SHIFT + code:11"); expect("a search is going", take(), "Key_2")
`);

scenario('digits by position in the typing submap follow the same rule', `
press("ALT + Tab"); press("ALT + x"); release("ALT_L"); take()
press("code:12"); expect("typed", take(), "Key_3")
press("BackSpace"); press("BackSpace"); take()
press("code:12"); expect("nothing typed: jump", take(), "Jump_3")
`);

scenario('Home, End, Delete and the arrows in both submaps', `
press("ALT + Tab"); take()
press("ALT + Home"); press("End"); press("ALT + Delete"); press("Left"); press("ALT + Down")
expect("globals", take(), "Home,End,Close,Left,Down")
press("ALT + q"); release("ALT_L"); take()
press("Home"); press("Up"); expect("typing", take(), "Home,Up")
`);

scenario('Alt+\` (key over Tab) opens the same-app switcher and steps it', `
press("ALT + code:49"); expect("submap", current, "${S}"); expect("globals", take(), "SameNext")
press("ALT + code:49"); press("ALT + SHIFT + code:49"); expect("globals", take(), "SameNext,SamePrev")
release("ALT_L"); expect("globals", take(), "Commit")
`);

scenario('type-to-search unbinding bare letters leaves the Alt+letter search', `
hl.unbind("a"); hl.unbind("SHIFT + a")
press("ALT + Tab"); press("ALT + a"); expect("globals", take(), "Next,Key_a")
`);

scenario('the typing submap binds its letters afresh each time, never twice', `
for i = 1, 3 do
  press("ALT + Tab"); press("ALT + a"); release("ALT_L"); press("Escape")
end
expect("a", count("${T}", "a"), 1)
expect("SHIFT + a", count("${T}", "SHIFT + a"), 1)
-- Even after type-to-search took them away in between.
hl.unbind("b"); take()
press("ALT + Tab"); press("ALT + a"); release("ALT_L"); press("b"); expect("globals", take(), "Next,Key_a,Release,Key_b")
`);

scenario('defined once per config generation; entry rewrites never stack', `
${defineChunk}
${entryChunk(true, true)}
${entryChunk(true, true)}
expect("hold letters", count("${S}", "ALT + a"), 1)
expect("hold Tab", count("${S}", "ALT + Tab"), 1)
expect("typing Tab", count("${T}", "ALT + Tab"), 1)
expect("root Tab", count("", "ALT + Tab"), 1)
expect("root same", count("", "ALT + ${stub.sameAppKey}"), 1)
expect("root release", count("", "ALT_L"), 1)
`);

scenario('switching off takes the entry binds away, and Alt+\` with them', `
${entryChunk(false, false)}
expect("root Tab", count("", "ALT + Tab"), 0)
expect("hold Tab", count("${S}", "ALT + Tab"), 0)
expect("root same", count("", "ALT + ${stub.sameAppKey}"), 0)
expect("unbound", press("ALT + Tab"), false)
`);

scenario('search-anywhere: Alt+letter on the desktop opens the switcher typing, digits never', `
${searchChunk(true, {})}
press("ALT + k"); expect("submap", current, "${S}"); expect("globals", take(), "Key_k")
release("ALT_L"); expect("a typed search stays", current, "${T}"); take()
press("Escape"); take()
expect("no root Alt+digit", count("", "ALT + 1") + count("", "ALT + code:10"), 0)
`);

scenario('restore after a crash: submap left, animations back', `
press("ALT + Tab"); press("ALT + a"); release("ALT_L")
expect("stranded", current, "${T}")
__ii_alt_tab_animations = true; config.animations.enabled = false
${restoreChunk}
expect("submap", current, "")
expect("animations", config.animations.enabled, true)
expect("record cleared", __ii_alt_tab_animations, nil)
`);

// The undimmed windows' record is a file (a config reload wipes Lua globals); the Lua that
// redims what it lists is checked here.
const redimChunk = new Function('root', 'Logic', `return function ${functionSource('redimChunk').slice('function '.length)}`)(
    stub, { normalisedAddress: raw => { const t = String(raw ?? '').trim(); return t === '' ? '' : (t.startsWith('0x') ? t : `0x${t}`); } });
scenario("a dead peek's undimmed windows get their dim back", `
${redimChunk('0x1\nabc\n\n not an address \n')}
expect("0x1", props["address:0x1"], "unset")
expect("abc", props["address:0xabc"], "unset")
local n = 0; for _ in pairs(props) do n = n + 1 end
expect("only those", n, 2)
`);

scenario('restore on a clean start touches nothing', `
press("SUPER + x")
${restoreChunk}
expect("submap", current, "")
expect("animations", config.animations.enabled, true)
`);

if (failures > 0) {
    console.log(`\n${failures} failed`);
    process.exit(1);
}
console.log('\nall passed');
