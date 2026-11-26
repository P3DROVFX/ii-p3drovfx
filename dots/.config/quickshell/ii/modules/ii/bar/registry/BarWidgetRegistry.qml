pragma Singleton
import QtQuick
import Quickshell
import qs
import qs.modules.common

// Scanner anchors: Quickshell only synthesizes QML modules reachable via static
// imports from the entry point. Keeping these once in this singleton (instead
// of in BarComponent.qml) ensures all dynamically-loaded bar widgets and their
// popup/sculpt/tray sub-modules resolve without bloating BarComponent.
import qs.modules.ii.bar.widgets.workspaces
import qs.modules.ii.bar.widgets.clock
import qs.modules.ii.bar.widgets.media
import qs.modules.ii.bar.widgets.battery
import qs.modules.ii.bar.widgets.bluetooth
import qs.modules.ii.bar.widgets.resources
import qs.modules.ii.bar.widgets.keyboard
import qs.modules.ii.bar.widgets.tray
import qs.modules.ii.bar.widgets.sports
import qs.modules.ii.bar.widgets.activeWindow
import qs.modules.ii.bar.widgets.dashboard
import qs.modules.ii.bar.widgets.notifications
import qs.modules.ii.bar.widgets.power
import qs.modules.ii.bar.widgets.utilButtons
import qs.modules.ii.bar.widgets.policies
import qs.modules.ii.bar.widgets.timer
import qs.modules.ii.bar.widgets.indicators
import qs.modules.ii.bar.widgets.dockToPanel
import qs.modules.ii.bar.widgets.portWatcher
import qs.modules.ii.bar.widgets.passwordManager
import qs.modules.ii.bar.widgets.networkSpeed
import qs.modules.ii.bar.widgets.privacy
import qs.modules.ii.bar.widgets.aiPlanUsage
import qs.modules.ii.bar.widgets.weather
import qs.modules.ii.bar.widgets.search
import qs.modules.ii.bar.widgets.date

// Shared singleton for bar widget style resolution, padding rules, widget URL
// mapping, and bar themes. Replaces per-slot BarWidgetRegistry and BarThemes
// instances across all widgets and all monitors.
Singleton {
    id: root

    // ── Bar themes (shared across all bars and widgets) ───────────────────────
    readonly property var themes: ({
        "content": {
            "name": "Content",
            "barBackground": Appearance.m3colors["m3primaryContainer"],
            "componentBackground": Appearance.m3colors["m3inverseOnSurface"],
            "highlight": Appearance.colors["colPrimary"]
        },
        "primary": {
            "name": "Primary",
            "barBackground": Appearance.m3colors["m3surfaceTint"],
            "componentBackground": Appearance.m3colors["m3primaryContainer"],
            "highlight": Appearance.colors["colTertiary"]
        },
        "secondary": {
            "name": "Secondary",
            "barBackground": Appearance.m3colors["m3secondaryContainer"],
            "componentBackground": Appearance.m3colors["m3primaryContainer"],
            "highlight": Appearance.colors["colPrimary"]
        },
        "surface": {
            "name": "Surface",
            "barBackground": Appearance.m3colors["m3surfaceContainerHigh"],
            "componentBackground": Appearance.m3colors["m3surfaceBright"],
            "highlight": Appearance.colors["colPrimary"]
        }
    })

    readonly property var activeTheme: themes[Config.options.bar.expressiveColorTheme] || themes["content"]

    function getTheme(themeName) {
        return themes[themeName] || themes["content"];
    }

    // Returns the configured style key for a widget.
    function getStyle(widgetId) {
        const s = Config.options.bar.styles;
        switch (widgetId) {
            case "workspaces":             return s.workspaces   ?? "default";
            case "clock":                  return s.clock        ?? "default";
            case "music_player":           return s.media        ?? "default";
            case "utility_buttons":        return s.utilButtons  ?? "default";
            case "weather":                return s.weather      ?? "default";
            case "dashboard_panel_button": return s.dashboard    ?? "default";
            case "notifications_button":   return s.notification ?? "default";
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
            case "record_indicator":       return s.recordIndicator ?? "expressive";
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

    function isMaterial(widgetId) {
        const s = Config.options.bar.styles;
        if (widgetId === "clock" && s.clock === "material") return true;
        if (widgetId === "keyboard_layout" && s.keyboard === "material") return true;
        if (widgetId === "battery" && s.battery === "material") return true;
        return false;
    }

    function isExpressive(widgetId) {
        const s = Config.options.bar.styles;
        switch (widgetId) {
            case "clock":                  return s.clock === "expressive" || s.clock === "neural" || s.clock === "relief";
            case "music_player":           return s.media === "expressive" || s.media === "neural" || s.media === "ring" || s.media === "tonal";
            case "workspaces":             return s.workspaces === "expressive";
            case "utility_buttons":        return s.utilButtons !== "default";
            case "weather":                return s.weather === "expressive" || s.weather === "horizon" || s.weather === "tessera" || s.weather === "sculpt";
            case "dashboard_panel_button": return s.dashboard !== "default";
            case "notifications_button":   return s.notification === "expressive";
            case "system_monitor":         return s.resources === "expressive" || s.resources === "sculpt";
            case "policies_panel_button":  return s.policies !== "default";
            case "power":                  return s.power !== "default";
            case "battery":                return s.battery === "expressive";
            case "system_tray":            return s.systray === "expressive";
            case "bluetooth_devices":      return s.bluetooth === "expressive" || s.bluetooth === "sculpt";
            case "keyboard_layout":        return s.keyboard === "expressive" || s.keyboard === "sculpt";
            case "sports":                 return s.sports === "expressive";
            case "active_window":          return s.activeWindow === "expressive";
            case "record_indicator":       return s.recordIndicator !== "default";
            case "dictation_indicator":
            case "phone_scrcpy_indicator":
            case "shell_update_indicator":
            case "mode_indicator":
            case "easyeffects_indicator":
            case "privacy_pill":
                return true;
            case "port_watcher":           return s.portWatcher === "expressive";
            case "password_manager":       return s.passwordManager === "expressive";
            case "ai_plan_usage":          return s.aiPlanUsage === "expressive";
            case "network_speed":          return s.networkSpeed === "expressive";
            case "search":                 return s.search === "expressive" || s.search === "neural" || s.search === "sculpt";
            case "date":                   return s.date === "expressive" || s.date === "neural";
            case "timer":                  return s.timer === "expressive" || s.timer === "sculpt";
            default:
                return false;
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

    // Resolves each widget slot to its QML URL (relative to modules/ii/bar/) + prop mode.
    function resolveWidgetSpec(id, isVert, style) {
        const isExp = style === "expressive";
        const isMin = style === "minimal";
        switch (id) {
        case "workspaces":
            if (isMin) return ({ url: "widgets/workspaces/MinimalWorkspaces.qml", props: "vertical" });
            if (isExp) return ({ url: "widgets/workspaces/ExpressiveWorkspaces.qml", props: "vertical" });
            if (style === "dock") return ({ url: "widgets/workspaces/DockWorkspaces.qml", props: "vertical" });
            if (style === "index") return ({ url: "widgets/workspaces/IndexWorkspaces.qml", props: "vertical" });
            if (style === "pills") return ({ url: "widgets/workspaces/PillsWorkspaces.qml", props: "vertical" });
            return ({ url: "widgets/workspaces/Workspaces.qml", props: "vertical" });
        case "music_player":
            if (isExp) return ({ url: "widgets/media/ExpressiveMedia.qml", props: "vertical" });
            if (style === "neural") return isVert ? ({ url: "../verticalBar/VerticalNeuralMedia.qml", props: "none" }) : ({ url: "widgets/media/NeuralMedia.qml", props: "vertical" });
            if (style === "ring") return ({ url: "widgets/media/RingMedia.qml", props: "vertical" });
            if (style === "tonal") return ({ url: "widgets/media/TonalMedia.qml", props: "vertical" });
            return isVert ? ({ url: "../verticalBar/VerticalMedia.qml", props: "none" }) : ({ url: "widgets/media/Media.qml", props: "none" });
        case "system_monitor":
            if (isExp) return ({ url: "widgets/resources/ExpressiveResources.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/resources/SculptResources.qml", props: "vertical" });
            return isVert ? ({ url: "../verticalBar/Resources.qml", props: "none" }) : ({ url: "widgets/resources/Resources.qml", props: "none" });
        case "clock":
            if (isExp) return ({ url: "widgets/clock/ExpressiveClockWidget.qml", props: "vertical" });
            if (style === "neural") return ({ url: "widgets/clock/NeuralClockWidget.qml", props: "vertical" });
            if (style === "relief") return ({ url: "widgets/clock/ReliefClockWidget.qml", props: "vertical" });
            return isVert ? ({ url: "../verticalBar/VerticalClockWidget.qml", props: "none" }) : ({ url: "widgets/clock/ClockWidget.qml", props: "none" });
        case "battery":
            if (isExp) return ({ url: "widgets/battery/ExpressiveBattery.qml", props: "vertical" });
            return isVert ? ({ url: "../verticalBar/BatteryIndicator.qml", props: "none" }) : ({ url: "widgets/battery/BatteryIndicator.qml", props: "none" });
        case "keyboard_layout":
            if (isExp) return ({ url: "widgets/keyboard/ExpressiveKeyboardLayout.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/keyboard/SculptKeyboardLayout.qml", props: "vertical" });
            return isVert ? ({ url: "../verticalBar/VerticalKeyboardLayoutWidget.qml", props: "none" }) : ({ url: "widgets/keyboard/KeyboardLayoutWidget.qml", props: "vertical" });
        case "utility_buttons":
            if (style === "segments") return ({ url: "widgets/utilButtons/SegmentedUtilButtons.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/utilButtons/SculptUtilButtons.qml", props: "vertical" });
            if (isExp) return ({ url: "widgets/utilButtons/ExpressiveUtilButtons.qml", props: "vertical" });
            return ({ url: "widgets/utilButtons/UtilButtons.qml", props: "vertical" });
        case "system_tray":
            if (isExp) return ({ url: "widgets/tray/ExpressiveSystemTray.qml", props: "vertical" });
            return ({ url: "widgets/tray/SysTray.qml", props: "vertical" });
        case "active_window":
            if (isExp) return ({ url: "widgets/activeWindow/ExpressiveActiveWindow.qml", props: "vertical" });
            return ({ url: "widgets/activeWindow/ActiveWindow.qml", props: "vertical" });
        case "weather":
            if (isExp) return ({ url: "widgets/weather/ExpressiveWeatherBar.qml", props: "vertical" });
            if (style === "horizon") return ({ url: "widgets/weather/HorizonWeatherWidget.qml", props: "vertical" });
            if (style === "tessera") return ({ url: "widgets/weather/TesseraWeatherWidget.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/weather/SculptWeatherWidget.qml", props: "vertical" });
            return ({ url: "widgets/weather/WeatherBar.qml", props: "vertical" });
        case "policies_panel_button":
            if (style === "outline") return ({ url: "widgets/policies/OutlinePoliciesPanelButton.qml", props: "vertical" });
            if (isExp) return ({ url: "widgets/policies/ExpressivePoliciesPanelButton.qml", props: "vertical" });
            return ({ url: "widgets/policies/PoliciesPanelButton.qml", props: "radii" });
        case "dashboard_panel_button":
            if (style === "orbs") return ({ url: "widgets/dashboard/OrbsDashboardPanelButton.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/dashboard/SculptDashboardPanelButton.qml", props: "vertical" });
            if (isExp) return ({ url: "widgets/dashboard/ExpressiveDashboardPanelButton.qml", props: "vertical" });
            return isVert ? ({ url: "widgets/dashboard/VerticalDashboardPanelButton.qml", props: "radii" }) : ({ url: "widgets/dashboard/DashboardPanelButton.qml", props: "radii" });
        case "notifications_button":
            if (isExp) return ({ url: "widgets/notifications/ExpressiveNotificationsButton.qml", props: "vertical" });
            return ({ url: "widgets/notifications/NotificationsButton.qml", props: "vertical" });
        case "bluetooth_devices":
            if (isExp) return ({ url: "widgets/bluetooth/ExpressiveBluetoothDevices.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/bluetooth/SculptBluetoothDevices.qml", props: "vertical" });
            return isVert ? ({ url: "../verticalBar/VerticalBluetoothDevicesWidget.qml", props: "none" }) : ({ url: "widgets/bluetooth/BluetoothDevicesWidget.qml", props: "vertical" });
        case "sports":
            if (isExp) return ({ url: "widgets/sports/ExpressiveSports.qml", props: "vertical" });
            return ({ url: "widgets/sports/Sports.qml", props: "vertical" });
        case "power":
            if (style === "solid") return ({ url: "widgets/power/SolidPowerButton.qml", props: "vertical" });
            if (style === "dot") return ({ url: "widgets/power/DotPowerButton.qml", props: "vertical" });
            if (isExp) return ({ url: "widgets/power/ExpressivePowerButton.qml", props: "vertical" });
            return ({ url: "widgets/power/PowerButton.qml", props: "verticalAndRadii" });
        case "network_speed":
            if (isExp) return ({ url: "widgets/networkSpeed/ExpressiveNetworkSpeed.qml", props: "vertical" });
            return ({ url: "widgets/networkSpeed/NetworkSpeedWidget.qml", props: "vertical" });
        case "date":
            if (isExp) return ({ url: "widgets/date/ExpressiveDateWidget.qml", props: "vertical" });
            if (style === "neural") return ({ url: "widgets/date/NeuralDateWidget.qml", props: "vertical" });
            return ({ url: "widgets/date/DateWidget.qml", props: "vertical" });
        case "timer":
            if (isExp) return ({ url: "widgets/timer/ExpressiveTimerWidget.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/timer/SculptTimerWidget.qml", props: "vertical" });
            return isVert ? ({ url: "../verticalBar/VerticalTimerWidget.qml", props: "none" }) : ({ url: "widgets/timer/TimerWidget.qml", props: "none" });
        case "record_indicator":
            return ({ url: "widgets/indicators/RecordIndicator.qml", props: "vertical" });
        case "dictation_indicator":
            return ({ url: "widgets/indicators/DictationIndicator.qml", props: "vertical" });
        case "phone_scrcpy_indicator":
            return ({ url: "widgets/indicators/PhoneScrcpyIndicator.qml", props: "vertical" });
        case "shell_update_indicator":
            return ({ url: "widgets/indicators/ShellUpdateIndicator.qml", props: "vertical" });
        case "mode_indicator":
            return ({ url: "widgets/indicators/ModeIndicator.qml", props: "vertical" });
        case "easyeffects_indicator":
            return ({ url: "widgets/indicators/EasyEffectsIndicator.qml", props: "vertical" });
        case "screen_share_indicator":
            return ({ url: "widgets/indicators/ScreenShareIndicator.qml", props: "none" });
        case "dock_to_panel":
            return ({ url: "widgets/dockToPanel/DockToPanel.qml", props: "vertical" });
        case "port_watcher":
            if (isExp) return ({ url: "widgets/portWatcher/ExpressivePortWatcher.qml", props: "vertical" });
            return ({ url: "widgets/portWatcher/PortWatcherWidget.qml", props: "vertical" });
        case "password_manager":
            if (isExp) return ({ url: "widgets/passwordManager/ExpressivePasswordManager.qml", props: "vertical" });
            return ({ url: "widgets/passwordManager/PasswordManagerWidget.qml", props: "vertical" });
        case "ai_plan_usage":
            if (isExp) return ({ url: "widgets/aiPlanUsage/ExpressiveAiPlanUsage.qml", props: "vertical" });
            return ({ url: "widgets/aiPlanUsage/AiPlanUsageWidget.qml", props: "vertical" });
        case "privacy_pill":
            return ({ url: "widgets/privacy/PrivacyPill.qml", props: "vertical" });
        case "search":
            if (isExp) return ({ url: "widgets/search/ExpressiveSearchBarWidget.qml", props: "vertical" });
            if (style === "neural") return ({ url: "widgets/search/NeuralSearchBarWidget.qml", props: "vertical" });
            if (style === "sculpt") return ({ url: "widgets/search/SculptSearchBarWidget.qml", props: "vertical" });
            return ({ url: "widgets/search/SearchBarWidget.qml", props: "vertical" });
        default:
            return null;
        }
    }
}
