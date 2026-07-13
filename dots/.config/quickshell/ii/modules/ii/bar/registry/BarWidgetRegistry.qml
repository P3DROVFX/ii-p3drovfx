import QtQuick
import qs
import qs.modules.common

// Widget style registry — centralizes style config lookup and padding rules.
// Instantiate once in BarComponent; all functions are pure (read-only Config access).
QtObject {
    id: root

    // Returns the configured style key for a widget.
    // Returns: "default" | "expressive" | "minimal"
    function getStyle(widgetId) {
        const s = Config.options.bar.styles;
        switch (widgetId) {
            case "workspaces":             return s.workspaces   ?? "default"; // default, expressive, minimal, dock
            case "clock":                  return s.clock        ?? "default";
            case "music_player":           return s.media        ?? "default";
            case "utility_buttons":        return s.utilButtons  ?? "default";
            case "weather":                return s.weather      ?? "default";
            case "dashboard_panel_button": return s.dashboard    ?? "default";
            case "system_monitor":         return s.resources    ?? "default";
            case "policies_panel_button":  return s.policies     ?? "default";
            case "power":                  return s.power        ?? "default";
            case "battery":                return s.battery      ?? "default";
            case "system_tray":            return s.systray      ?? "default";
            case "bluetooth_devices":      return s.bluetooth    ?? "default";
            case "keyboard_layout":        return s.keyboard     ?? "default";
            case "sports":                 return s.sports       ?? "default";
            case "active_window":          return s.activeWindow ?? "default";
            // Always expressive — no user config toggle
            case "record_indicator":
            case "phone_scrcpy_indicator":
                return "expressive";
            default:
                return "default";
        }
    }

    // Returns true when the widget's BarGroup should have zero padding.
    function isPaddingless(widgetId, isExpressive) {
        if (isExpressive && widgetId !== "workspaces") return true;
        if (widgetId === "system_monitor" && Config.options.bar.resources.showDocker) return true;
        if (widgetId === "dashboard_panel_button") return true;
        if (widgetId === "policies_panel_button") return true;
        return false;
    }
}
