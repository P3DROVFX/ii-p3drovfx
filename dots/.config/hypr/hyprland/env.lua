local home_dir = os.getenv("HOME")

-- Puts `entries` at the front of a colon separated environment list, dropping any
-- duplicates from the result.
--
-- Hyprland re-runs this file on every `hyprctl reload`, and each run reads back the
-- value the previous one installed, so a plain prepend never settles: after fifty
-- reloads XDG_DATA_DIRS held the same four directories fifty times over. Everything
-- that walks that list paid for it -- a desktop entry rescan parsed eighteen thousand
-- files instead of four hundred, and blocked the shell for the better part of two
-- seconds every time a file manager touched ~/.local/share. Deduplicating the whole
-- result, rather than only the part being added, means a reload also repairs a value
-- that earlier reloads already inflated.
local function prepend_unique(name, entries)
    local seen = {}
    local result = {}

    local function add(dir)
        if dir == "" or seen[dir] then return end
        seen[dir] = true
        result[#result + 1] = dir
    end

    for _, dir in ipairs(entries) do add(dir) end
    for dir in (os.getenv(name) or ""):gmatch("[^:]+") do add(dir) end

    hl.env(name, table.concat(result, ":"))
end

-- Enforce local binary directory precedence for session
prepend_unique("PATH", { home_dir .. "/.local/bin" })

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
prepend_unique("XDG_DATA_DIRS", {
    home_dir .. "/.local/share/flatpak/exports/share",
    "/var/lib/flatpak/exports/share",
    "/usr/local/share",
    "/usr/share"
})

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- User QML modules: the shell's optional MpvWallpaper plugin installs here
-- (quickshell/ii/scripts/videos/build-mpv-wallpaper-plugin.sh).
prepend_unique("QML_IMPORT_PATH", { home_dir .. "/.local/lib/qt6/qml" })

-- Qt 6.12.0 started recycling a Text's glyph nodes on every text update, and when
-- the batch renderer had promoted that text node to a batch root the recycled nodes
-- never get a renderer matrix back: the next sync dereferences it on the render
-- thread (QSGInternalTextNode::addGlyphs → segfault, QTBUG-151670, fixed after
-- 6.12.0 in qtdeclarative c3c6897213). Media mode hits it on exit, when the shell
-- colours are restored and every Text repaints. Raising both thresholds keeps
-- text nodes from ever becoming batch roots; the node threshold alone is not enough,
-- Qt then falls back to the vertex one. Only for 6.12.0: elsewhere batch roots are
-- what keep big animated subtrees from re-uploading their geometry every frame.
local function qt_is(version)
    for _, dir in ipairs({ "/usr/lib", "/usr/lib64", "/usr/lib/x86_64-linux-gnu" }) do
        local f = io.open(dir .. "/libQt6Core.so." .. version, "r")
        if f then
            f:close()
            return true
        end
    end
    return false
end

if qt_is("6.12.0") then
    for _, name in ipairs({ "QSG_RENDERER_BATCH_NODE_THRESHOLD", "QSG_RENDERER_BATCH_VERTEX_THRESHOLD" }) do
        if not os.getenv(name) then hl.env(name, "2147483647") end
    end
end

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")

-- Wireless ADB: the adb server sends a TCP keepalive every second by default, which
-- wakes a locked phone ~30 times a minute and roughly doubled its idle drain once
-- adbd started surviving the lock. The server reads this when it starts, so it holds
-- for the shell, terminals and scrcpy alike. A vanished phone is caught by
-- KdeConnectService instead, whose 30 s probe drops any network device that stops
-- answering.
hl.env("ADB_TCP_KEEPALIVE_INTERVAL", "60")
