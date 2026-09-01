pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

/**
 * Validates and applies small, reversible local controls through existing
 * shell services. The model never receives a command string or a compositor
 * address; it receives a typed preview and the captured previous value.
 */
QtObject {
    id: root

    function numberIn(value, minimum, maximum): var {
        const number = Number(value);
        return Number.isFinite(number) && number >= minimum && number <= maximum ? number : null;
    }

    function status(): var {
        const monitor = Brightness.getTargetMonitor();
        return {
            audio: { volumePercent: Math.round(Number(Audio.value ?? 0) * 100), muted: Audio.muted === true },
            brightness: { monitor: String(monitor?.screen?.name ?? ""), percent: Math.round(Number(monitor?.brightness ?? 0) * 100) },
            dnd: Notifications.silent === true,
            nightlight: { enabled: Hyprsunset.temperatureActive === true, temperature: Number(Hyprsunset.colorTemperature ?? 5000) },
            theme: { mode: DarkModeService.automatic ? "automatic" : (Appearance.m3colors.darkmode ? "dark" : "light") }
        };
    }

    function current(toolId): var {
        const state = root.status();
        switch (String(toolId)) {
        case "audio_set": return state.audio.volumePercent;
        case "brightness_set": return state.brightness.percent;
        case "dnd_set": return state.dnd;
        case "nightlight_set": return state.nightlight;
        case "theme_set_mode": return state.theme.mode;
        }
        return null;
    }

    function valueFor(toolId, args): var {
        switch (String(toolId)) {
        case "audio_set":
            return root.numberIn(args?.volumePercent, 0, 100);
        case "brightness_set":
            return root.numberIn(args?.percent, 0, 100);
        case "dnd_set":
            return typeof args?.enabled === "boolean" ? args.enabled : null;
        case "nightlight_set": {
            const enabled = args?.enabled;
            const temperature = args?.temperature;
            if (enabled !== undefined && typeof enabled !== "boolean")
                return null;
            if (temperature !== undefined && root.numberIn(temperature, 2500, 6500) === null)
                return null;
            if (enabled === undefined && temperature === undefined)
                return null;
            return {
                enabled: enabled === undefined ? Hyprsunset.temperatureActive === true : enabled,
                temperature: temperature === undefined ? Number(Hyprsunset.colorTemperature ?? 5000) : Number(temperature)
            };
        }
        case "theme_set_mode": {
            const mode = String(args?.mode ?? "").toLowerCase();
            return ["light", "dark", "automatic"].indexOf(mode) >= 0 ? mode : null;
        }
        }
        return null;
    }

    function preview(toolId, args): var {
        const value = root.valueFor(toolId, args);
        if (value === null)
            return { ok: false, error: "invalidValue" };
        const previous = root.current(toolId);
        return {
            ok: true,
            toolId: String(toolId),
            value: value,
            undo: previous,
            summary: root.summary(toolId, value),
            previousSummary: root.summary(toolId, previous)
        };
    }

    function summary(toolId, value): string {
        switch (String(toolId)) {
        case "audio_set": return `Volume ${Math.round(Number(value))}%`;
        case "brightness_set": return `Brightness ${Math.round(Number(value))}%`;
        case "dnd_set": return value ? "Do Not Disturb on" : "Do Not Disturb off";
        case "nightlight_set": return value.enabled ? `Night light on · ${Math.round(Number(value.temperature))} K` : "Night light off";
        case "theme_set_mode": return `Theme ${String(value)}`;
        }
        return String(value ?? "");
    }

    function apply(preview): var {
        const toolId = String(preview?.toolId ?? "");
        const value = preview?.value;
        switch (toolId) {
        case "audio_set":
            if (!Audio.sink?.audio) return { ok: false, error: "audioUnavailable" };
            Audio.sink.audio.volume = Number(value) / 100;
            break;
        case "brightness_set": {
            const monitor = Brightness.getTargetMonitor();
            if (!monitor) return { ok: false, error: "brightnessUnavailable" };
            monitor.setBrightness(Number(value) / 100);
            break;
        }
        case "dnd_set":
            Notifications.silent = value === true;
            break;
        case "nightlight_set":
            Hyprsunset.colorTemperature = Number(value.temperature);
            if (value.enabled) Hyprsunset.enableTemperature();
            else Hyprsunset.disableTemperature();
            break;
        case "theme_set_mode":
            Config.options.light.darkMode.automatic = value === "automatic";
            if (value === "dark") DarkModeService.enableDarkMode();
            else if (value === "light") DarkModeService.disableDarkMode();
            else DarkModeService.checkTime();
            break;
        default:
            return { ok: false, error: "unknownControl" };
        }
        return { ok: true, value: value, summary: root.summary(toolId, value) };
    }

    function undo(preview): var {
        return root.apply({ toolId: preview?.toolId, value: preview?.undo });
    }
}
