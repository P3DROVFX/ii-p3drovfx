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

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
