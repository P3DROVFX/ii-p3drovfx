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
            case "workspaces":             return s.workspaces   ?? "default"; // default, expressive, minimal, dock, index, pills
            case "clock":                  return s.clock        ?? "default";
            case "music_player":           return s.media        ?? "default";
            case "utility_buttons":        return s.utilButtons  ?? "default";
            case "weather":                return s.weather      ?? "default";
            case "dashboard_panel_button": return s.dashboard    ?? "default";
            case "system_monitor":         return s.resources    ?? "default";
            case "policies_panel_button":  return s.policies     ?? "default";
            case "power":                  return s.power        ?? "default";
            case "battery": {
                const b = s.battery ?? "default";
                return b === "classic" ? "default" : b;
            }
            case "system_tray":            return s.systray      ?? "default";
            case "bluetooth_devices": {
                const bt = s.bluetooth ?? "default";
                return bt === "classic" ? "default" : bt;
            }
            case "keyboard_layout":        return s.keyboard     ?? "default";
            case "sports":                 return s.sports       ?? "default";
            case "active_window":          return s.activeWindow ?? "default";
            case "port_watcher":           return s.portWatcher  ?? "default";
            case "password_manager":       return s.passwordManager ?? "default";
            case "ai_plan_usage":          return s.aiPlanUsage  ?? "default";
            case "network_speed":          return s.networkSpeed ?? "default";
            case "search":                 return s.search       ?? "default";
            case "date":                   return s.date         ?? "default";
            case "timer":                  return s.timer        ?? "expressive";
            case "record_indicator":       return s.recordIndicator ?? "expressive"; // default, expressive, neural
            // Always expressive — no user config toggle
            case "privacy_pill":
            case "dictation_indicator":
            case "shell_update_indicator":
            case "phone_scrcpy_indicator":
            case "mode_indicator":
            case "easyeffects_indicator":
                return "expressive";
            default:
                return "default";
        }
    }

    // Returns true when the widget's BarGroup should have zero padding.
    function isPaddingless(widgetId, isExpressive) {
        if (isExpressive && widgetId !== "workspaces") return true;
        if (widgetId === "dashboard_panel_button") return true;
        if (widgetId === "policies_panel_button") return true;
        if (widgetId === "power") return true;
        if (widgetId === "privacy_pill") return true;
        return false;
    }
}
