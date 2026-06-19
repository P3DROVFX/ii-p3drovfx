-- This file sources other files in `hyprland` and `custom` folders
-- You wanna add your stuff in files in `custom`

-- Internal stuff --
require("hyprland.lib")
require("hyprland.services")

local function safe_require(module_name)
    local ok, err = pcall(require, module_name)
    if not ok then
        hl.exec_cmd("notify-send 'Hyprland Lua Error' 'Failed to load " .. module_name .. ": " .. tostring(err):gsub("'", "\\'") .. "' -u critical -a 'Hyprland'")
    end
    return ok
end

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
if is_file_exists(HOME .. "/.config/hypr/hyprmon.lua") then
    require("hyprmon")
end

-- Shell overrides --
safe_require("hyprland.shellOverrides.main")

