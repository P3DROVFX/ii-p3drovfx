pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.modules.common
import qs.services
import "budslink/BudsLinkSemantics.js" as BudsLinkSemantics

Singleton {
    id: root

    // =========================================================================
    // Helpers & MAC Resolution
    // =========================================================================
    function canonicalizeMac(deviceOrMac): string {
        if (!deviceOrMac)
            return "";
        if (typeof deviceOrMac === "string")
            return BudsLinkSemantics.normalizeMac(deviceOrMac);
        if (typeof deviceOrMac === "object") {
            if (deviceOrMac.address)
                return BudsLinkSemantics.normalizeMac(deviceOrMac.address);
            if (deviceOrMac.mac)
                return BudsLinkSemantics.normalizeMac(deviceOrMac.mac);
        }
        return "";
    }

    function findDeviceByMac(mac: string): var {
        const canonical = BudsLinkSemantics.normalizeMac(mac);
        if (!canonical || !BluetoothStatus.available)
            return null;
        for (let d of BluetoothStatus.connectedDevices) {
            if (d && BudsLinkSemantics.normalizeMac(d.address) === canonical)
                return d;
        }
        return null;
    }

    // =========================================================================
    // Provider Resolution & Priority (Plan Sections 2, 27, 29)
    // =========================================================================
    function providerForDevice(device): string {
        if (!device)
            return null;

        const mac = canonicalizeMac(device);
        if (mac.length > 0 && BudsLinkService.hasMac(mac))
            return "budslink";

        if (SoundcoreService.isHeadsetSupported(device))
            return "soundcore";

        if (BudsService.isHeadsetSupported(device))
            return "legacyBuds";

        return null;
    }

    function providerForMac(mac: string): string {
        const canonical = BudsLinkSemantics.normalizeMac(mac);
        if (!canonical)
            return null;

        if (BudsLinkService.hasMac(canonical))
            return "budslink";

        const dev = findDeviceByMac(canonical);
        if (dev) {
            if (SoundcoreService.isHeadsetSupported(dev))
                return "soundcore";
            if (BudsService.isHeadsetSupported(dev))
                return "legacyBuds";
        }
        return null;
    }

    function isEnhanced(device): bool {
        return root.providerForDevice(device) !== null;
    }

    // =========================================================================
    // Deterministic Active Device Selection (Plan Section 88)
    // =========================================================================
    readonly property var activeDevice: {
        if (!BluetoothStatus.available || !BluetoothStatus.enabled)
            return null;

        const connectedList = BluetoothStatus.connectedDevices;
        if (!connectedList || connectedList.length === 0)
            return null;

        // 1. First connected device positively claimed by BudsLink
        for (let d of connectedList) {
            if (d && d.connected) {
                const mac = canonicalizeMac(d.address);
                if (mac.length > 0 && BudsLinkService.hasMac(mac))
                    return d;
            }
        }

        // 2. Connected Soundcore device
        for (let d of connectedList) {
            if (d && d.connected && SoundcoreService.isHeadsetSupported(d))
                return d;
        }

        // 3. Connected legacy Buds device
        for (let d of connectedList) {
            if (d && d.connected && BudsService.isHeadsetSupported(d))
                return d;
        }

        // 4. Any audio candidate
        for (let d of connectedList) {
            if (d && d.connected && BudsLinkService.isAudioCandidate(d))
                return d;
        }

        return connectedList.length > 0 ? connectedList[0] : null;
    }

    readonly property string activeProvider: root.providerForDevice(root.activeDevice)
    readonly property bool connected: root.activeDevice !== null && root.activeProvider !== null

    // =========================================================================
    // Capabilities Inspection (Plan Section 70)
    // =========================================================================
    function supports(device, capability: string): bool {
        if (!device || !capability)
            return false;

        const provider = root.providerForDevice(device);
        if (!provider)
            return false;

        if (provider === "budslink") {
            const info = BudsLinkService.infoForDevice(device);
            if (!info)
                return false;
            const norm = BudsLinkSemantics.normalizeDevice(info);
            return norm && norm.capabilities ? Boolean(norm.capabilities[capability]) : false;
        }

        if (provider === "soundcore" || provider === "legacyBuds") {
            switch (capability) {
                case "noiseControl":
                case "transparency":
                case "anc":
                    return true;
                case "adaptiveNoiseControl":
                case "conversationAwareness":
                case "batteryBreakdown":
                case "leftBattery":
                case "rightBattery":
                case "caseBattery":
                case "dynamicOptions":
                case "deviceSettings":
                    return false;
                default:
                    return false;
            }
        }

        return false;
    }

    // =========================================================================
    // Battery Telemetry & Breakdown (Plan Sections 18, 19, 20)
    // =========================================================================
    function batteryInfo(device): var {
        if (!device)
            return {
                available: false,
                aggregate: null,
                components: [],
                left: null,
                right: null,
                case: null,
                device: null
            };

        const provider = root.providerForDevice(device);

        if (provider === "budslink") {
            const raw = BudsLinkService.infoForDevice(device);
            if (raw && (raw.state || raw.config)) {
                const normBattery = BudsLinkSemantics.normalizeBattery(raw.state, raw.config);
                if (normBattery.available)
                    return normBattery;
            }
        }

        // Generic BlueZ fallback
        const hasBlueZBattery = Boolean(device.batteryAvailable);
        const blueZLevel = hasBlueZBattery ? Math.max(0, Math.min(100, Math.round((device.battery ?? 0) * 100))) : null;

        const devComp = {
            index: 1,
            id: "device",
            label: device.name || "Device",
            level: blueZLevel,
            status: hasBlueZBattery ? "discharging" : "unknown",
            available: hasBlueZBattery,
            charging: false,
            connected: Boolean(device.connected)
        };

        return {
            available: hasBlueZBattery,
            aggregate: blueZLevel,
            components: hasBlueZBattery ? [devComp] : [],
            left: null,
            right: null,
            case: null,
            device: devComp
        };
    }

    function primaryBatteryPercent(device): var {
        const info = batteryInfo(device);
        return (info && info.available && info.aggregate !== null) ? info.aggregate : null;
    }

    // =========================================================================
    // Noise Control & Mode Selection (Plan Sections 24, 25, 54, 55)
    // =========================================================================
    function noiseControl(device): var {
        if (!device) {
            return {
                available: false,
                title: "Noise Control",
                modes: [],
                currentMode: "off",
                currentModeLabel: "Normal",
                currentModeIcon: "hearing",
                currentState: 1,
                hasAdaptive: false,
                hasTransparency: false,
                hasAnc: false
            };
        }

        const provider = root.providerForDevice(device);
        const mac = canonicalizeMac(device.address);

        if (provider === "budslink") {
            const info = BudsLinkService.infoForDevice(device);
            if (info) {
                return BudsLinkSemantics.normalizeNoiseControls(info.state, info.config);
            }
        }

        if (provider === "soundcore" || provider === "legacyBuds") {
            const rawService = provider === "soundcore" ? SoundcoreService : BudsService;
            const rawMode = rawService.getModeForMac(mac);

            let currentKey = "off";
            if (rawMode === "Transparency") currentKey = "transparency";
            else if (rawMode === "NoiseCanceling") currentKey = "anc";
            else if (rawMode === "Adaptive") currentKey = "adaptive";

            const supportedKeys = provider === "legacyBuds"
                ? Array.from(BudsService.getSupportedModesForMac(mac))
                : ["off", "transparency", "anc"];
            const modes = supportedKeys.map((key, idx) => {
                const meta = BudsLinkSemantics.noiseModeMetadata(key) || { key: key, label: key, icon: "tune", legacyName: key };
                return { key: key, buttonIndex: idx + 1, label: meta.label, icon: meta.icon, legacyName: meta.legacyName };
            });

            const currentMeta = modes.find(m => m.key === currentKey) || modes[0];

            return {
                available: true,
                title: "Noise Control",
                modes: modes,
                currentMode: currentKey,
                currentModeLabel: currentMeta.label,
                currentModeIcon: currentMeta.icon,
                currentState: currentMeta.buttonIndex,
                hasAdaptive: modes.some(m => m.key === "adaptive"),
                hasTransparency: true,
                hasAnc: true
            };
        }

        return {
            available: false,
            title: "Noise Control",
            modes: [],
            currentMode: "off",
            currentModeLabel: "Normal",
            currentModeIcon: "hearing",
            currentState: 1,
            hasAdaptive: false,
            hasTransparency: false,
            hasAnc: false
        };
    }

    function currentNoiseMode(device): string {
        const nc = noiseControl(device);
        return nc.currentMode || "off";
    }

    function setNoiseMode(deviceOrMac, modeKey: string): void {
        const mac = canonicalizeMac(deviceOrMac);
        if (!mac) return;

        let targetKey = String(modeKey || "off").toLowerCase().trim();
        if (targetKey === "normal") targetKey = "off";

        const provider = root.providerForMac(mac);
        if (!provider) {
            console.warn("[EarbudsControlService] No provider available for device MAC:", mac);
            return;
        }

        if (provider === "budslink") {
            const dev = findDeviceByMac(mac) || deviceOrMac;
            const nc = noiseControl(dev);
            if (nc && nc.modeKeyToButtonIndex && nc.modeKeyToButtonIndex[targetKey] !== undefined) {
                const btnIdx = nc.modeKeyToButtonIndex[targetKey];
                BudsLinkService.sendAction(mac, "toggle1State", btnIdx);
            } else {
                console.warn(`[EarbudsControlService] Unsupported noise mode "${modeKey}" for BudsLink device ${mac}`);
            }
            return;
        }

        let legacyModeName = "Normal";
        if (targetKey === "transparency") legacyModeName = "Transparency";
        else if (targetKey === "anc") legacyModeName = "NoiseCanceling";
        else if (targetKey === "off") legacyModeName = "Normal";
        else if (targetKey === "adaptive" && provider === "legacyBuds") legacyModeName = "Adaptive";
        else {
            console.warn(`[EarbudsControlService] Unsupported noise mode "${modeKey}" for provider ${provider}`);
            return;
        }

        if (provider === "soundcore") {
            SoundcoreService.setMode(mac, legacyModeName);
        } else if (provider === "legacyBuds") {
            BudsService.setMode(mac, legacyModeName);
        }
    }

    function cycleNoiseMode(device): void {
        if (!device) return;
        const nc = noiseControl(device);
        if (!nc.available || !nc.modes || nc.modes.length <= 1) return;

        const modes = nc.modes;
        const currIdx = modes.findIndex(m => m.key === nc.currentMode);
        const nextIdx = currIdx >= 0 ? (currIdx + 1) % modes.length : 0;
        const nextMode = modes[nextIdx];

        if (nextMode) {
            root.setNoiseMode(device, nextMode.key);
        }
    }

    // =========================================================================
    // Conversation Awareness (Plan Section 21)
    // =========================================================================
    function conversationAwareness(device): var {
        if (!device) return { available: false, enabled: false };
        const provider = root.providerForDevice(device);
        if (provider === "budslink") {
            const info = BudsLinkService.infoForDevice(device);
            if (info) {
                return BudsLinkSemantics.normalizeConversationAwareness(info.state, info.config);
            }
        }
        return { available: false, enabled: false };
    }

    function setConversationAwareness(deviceOrMac, enabled: bool): void {
        const mac = canonicalizeMac(deviceOrMac);
        if (!mac) return;

        const provider = root.providerForMac(mac);
        if (provider === "budslink") {
            const dev = findDeviceByMac(mac) || deviceOrMac;
            const ca = conversationAwareness(dev);
            if (ca.available) {
                const targetState = enabled ? ca.onButtonIndex : ca.offButtonIndex;
                BudsLinkService.sendAction(mac, "toggle2State", targetState);
            }
        }
    }

    // =========================================================================
    // Dynamic Options & External Settings (Plan Sections 22, 23, 73)
    // =========================================================================
    function dynamicControls(device): list<var> {
        if (!device) return [];
        const provider = root.providerForDevice(device);
        if (provider === "budslink") {
            const info = BudsLinkService.infoForDevice(device);
            if (info) {
                return BudsLinkSemantics.normalizeOptionBoxes(info.state, info.config);
            }
        }
        return [];
    }

    function indicators(device): list<var> {
        if (!device) return [];
        const provider = root.providerForDevice(device);
        if (provider === "budslink") {
            const info = BudsLinkService.infoForDevice(device);
            if (info) {
                return BudsLinkSemantics.normalizeIndicators(info.state, info.config);
            }
        }
        return [];
    }

    function sendSliderAction(deviceOrMac, boxIndex: int, value: int, isDragging: bool): void {
        const mac = canonicalizeMac(deviceOrMac);
        if (!mac) return;
        if (isDragging) {
            BudsLinkService.sendAction(mac, "box" + boxIndex + "SliderIsDragging", 1);
        } else {
            BudsLinkService.sendAction(mac, "box" + boxIndex + "SliderValue", value);
            BudsLinkService.sendAction(mac, "box" + boxIndex + "SliderIsDragging", 0);
        }
    }

    function sendCheckAction(deviceOrMac, boxIndex: int, checkIndex: int, state: bool): void {
        const mac = canonicalizeMac(deviceOrMac);
        if (!mac) return;
        BudsLinkService.sendAction(mac, "box" + boxIndex + "CheckButton" + checkIndex + "State", state ? 1 : 0);
    }

    function sendRadioAction(deviceOrMac, boxIndex: int, state: int): void {
        const mac = canonicalizeMac(deviceOrMac);
        if (!mac) return;
        BudsLinkService.sendAction(mac, "box" + boxIndex + "RadioButtonState", state);
    }

    function openDeviceSettings(deviceOrMac): void {
        const mac = canonicalizeMac(deviceOrMac);
        if (!mac) return;
        BudsLinkService.openDeviceSettings(mac);
    }
}
