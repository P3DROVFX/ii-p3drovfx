-- This file sources other files in `hyprland` and `custom` folders
-- You wanna add your stuff in files in `custom`

local function safe_require(module_name)
    package.loaded[module_name] = nil
    local ok, err = pcall(require, module_name)
    if not ok then
        hl.exec_cmd("notify-send 'Hyprland Lua Error' 'Failed to load " .. module_name .. ": " .. tostring(err):gsub("'", "\\'") .. "' -u critical -a 'Hyprland'")
    end
    return ok
end

-- Internal stuff --
safe_require("hyprland.lib")
safe_require("hyprland.services")

-- Environment variables --
safe_require("hyprland.env")
if is_file_exists(HOME .. "/.config/hypr/custom/env.lua") then
    safe_require("custom.env")
end

-- Default configurations --
safe_require("hyprland.execs")
safe_require("hyprland.general")
safe_require("hyprland.rules")
safe_require("hyprland.colors")
safe_require("hyprland.keybinds")

-- Custom configurations --
if is_file_exists(HOME .. "/.config/hypr/custom/input.lua") then
    safe_require("custom.input")
end
if is_file_exists(HOME .. "/.config/hypr/custom/execs.lua") then
    safe_require("custom.execs")
end
if is_file_exists(HOME .. "/.config/hypr/custom/general.lua") then
    safe_require("custom.general")
end
if is_file_exists(HOME .. "/.config/hypr/custom/rules.lua") then
    safe_require("custom.rules")
end
if is_file_exists(HOME .. "/.config/hypr/custom/keybinds.lua") then
    safe_require("custom.keybinds")
end

-- nwg-displays support: re-add the files if it updates later
safe_require("workspaces")
safe_require("monitors")

-- Shell overrides --
safe_require("hyprland.shellOverrides.main")

-- hyprmon: managed monitor profile include
safe_require("hyprmon")
