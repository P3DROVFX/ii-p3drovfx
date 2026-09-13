/**
 * BudsLinkSemantics.js
 *
 * Normalization logic for BudsLink Companion D-Bus schema.
 * Translates raw D-Bus Config and State properties into normalized,
 * brand-agnostic data structures for the Quickshell UI.
 */
.pragma library

// Canonical Noise Control Mode Keys
const NOISE_MODE_OFF = "off";
const NOISE_MODE_TRANSPARENCY = "transparency";
const NOISE_MODE_ADAPTIVE = "adaptive";
const NOISE_MODE_ANC = "anc";

const NOISE_MODE_METADATA = {
    "off": { key: "off", label: "Off", icon: "hearing", legacyName: "Normal" },
    "transparency": { key: "transparency", label: "Transparency", icon: "visibility", legacyName: "Transparency" },
    "adaptive": { key: "adaptive", label: "Adaptive", icon: "auto_awesome", legacyName: "Adaptive" },
    "anc": { key: "anc", label: "ANC", icon: "noise_control_off", legacyName: "NoiseCanceling" }
};

/**
 * Metadata (label/icon/legacy name) for a canonical noise mode key; null when unknown.
 */
function noiseModeMetadata(key) {
    return NOISE_MODE_METADATA[key] || null;
}

/**
 * Normalizes MAC address string to standard format: AA:BB:CC:DD:EE:FF
 */
function normalizeMac(mac) {
    if (!mac || typeof mac !== "string") return "";
    const trimmed = mac.trim().replace(/[-_]/g, ":").toUpperCase();
    const match = /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(trimmed);
    return match ? trimmed : "";
}

/**
 * Extract canonical MAC address from D-Bus object path.
 */
function extractMacFromPath(path) {
    if (!path || typeof path !== "string") return "";
    const match = path.match(/dev_([0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2})/);
    if (match) {
        return match[1].replace(/_/g, ":").toUpperCase();
    }
    return "";
}

/**
 * Infer component identity (left, right, case, device) from icon name or index.
 */
function inferBatteryComponentId(iconName, index) {
    const icon = (iconName || "").toLowerCase();
    if (icon.includes("left") || icon.includes("bbm-left")) return "left";
    if (icon.includes("right") || icon.includes("bbm-right")) return "right";
    if (icon.includes("case") || icon.includes("box") || icon.includes("bbm-case") || icon.includes("cradle")) return "case";
    if (icon.includes("headset") || icon.includes("headphone") || icon.includes("device")) return "device";

    // Positional fallback if 3 batteries: 1=left, 2=right, 3=case
    if (index === 1) return "left";
    if (index === 2) return "right";
    if (index === 3) return "case";
    return "unknown" + index;
}

function getBatteryComponentLabel(id) {
    switch (id) {
        case "left": return "Left";
        case "right": return "Right";
        case "case": return "Case";
        case "device": return "Headset";
        default: return "Battery";
    }
}

/**
 * Normalizes raw BudsLink device battery data into standard structured object.
 */
function normalizeBattery(rawState, rawConfig) {
    const state = (rawState && typeof rawState === "object") ? rawState : {};
    const config = (rawConfig && typeof rawConfig === "object") ? rawConfig : {};

    const components = [];
    const lookup = {};

    for (let i = 1; i <= 3; i++) {
        const levelKey = "battery" + i + "Level";
        const statusKey = "battery" + i + "Status";
        const iconKey = "battery" + i + "Icon";
        const showKey = "battery" + i + "ShowOnDisconnect";

        const rawLevel = state[levelKey];
        const rawStatus = state[statusKey] || "";
        const icon = config[iconKey] || "";
        const showOnDisconnect = config[showKey] === true;

        if (rawLevel === undefined && !rawStatus) continue;

        const level = (rawLevel !== undefined && rawLevel !== null && Number.isFinite(Number(rawLevel)))
            ? Math.max(0, Math.min(100, Math.round(Number(rawLevel))))
            : null;

        const status = String(rawStatus || "unknown").toLowerCase();
        const isCharging = (status === "charging" || status.includes("charg")) && !status.includes("discharg");
        const isDisconnected = status === "disconnected" || status === "not-reported" || status === "none";
        const isAvailable = level !== null && (!isDisconnected || showOnDisconnect);

        const id = inferBatteryComponentId(icon, i);
        const label = getBatteryComponentLabel(id);

        const comp = {
            index: i,
            id: id,
            label: label,
            level: level,
            status: status,
            available: isAvailable,
            charging: isCharging,
            connected: !isDisconnected
        };

        components.push(comp);
        lookup[id] = comp;
    }

    // Compute aggregate level
    let aggregate = null;
    if (state.computedBatteryLevel !== undefined && state.computedBatteryLevel !== null && Number.isFinite(Number(state.computedBatteryLevel))) {
        aggregate = Math.max(0, Math.min(100, Math.round(Number(state.computedBatteryLevel))));
    } else {
        // Compute average of available earbud components (excluding case if earbuds present)
        const earbudComps = components.filter(c => c.available && (c.id === "left" || c.id === "right" || c.id === "device"));
        if (earbudComps.length > 0) {
            const sum = earbudComps.reduce((acc, c) => acc + (c.level || 0), 0);
            aggregate = Math.round(sum / earbudComps.length);
        } else {
            const anyAvailable = components.filter(c => c.available);
            if (anyAvailable.length > 0) {
                aggregate = anyAvailable[0].level;
            }
        }
    }

    return {
        available: components.some(c => c.available) || aggregate !== null,
        aggregate: aggregate,
        components: components,
        left: lookup["left"] || null,
        right: lookup["right"] || null,
        case: lookup["case"] || null,
        device: lookup["device"] || null
    };
}

/**
 * Infer semantic noise mode from BudsLink icon or button name.
 */
function inferNoiseModeSemantic(iconName, buttonName) {
    const icon = (iconName || "").toLowerCase();
    const name = (buttonName || "").toLowerCase().trim();

    // 1. Icon-based matching (Highest accuracy per Section 25)
    if (icon.includes("bbm-anc-off") || icon.includes("anc-off") || icon.includes("hearing-off")) {
        return NOISE_MODE_OFF;
    }
    if (icon.includes("bbm-adaptive") || icon.includes("adaptive")) {
        return NOISE_MODE_ADAPTIVE;
    }
    if (icon.includes("bbm-transperancy") || icon.includes("bbm-transparency") || icon.includes("transparency") || icon.includes("ambient")) {
        return NOISE_MODE_TRANSPARENCY;
    }
    if (icon.includes("bbm-anc-on") || icon.includes("anc-on") || icon.includes("noise-cancelling") || icon.includes("noise-cancellation")) {
        return NOISE_MODE_ANC;
    }

    // 2. Name-based matching fallback
    if (name === "off" || name === "normal" || name === "desativado" || name === "desligado") {
        return NOISE_MODE_OFF;
    }
    if (name.includes("adaptive") || name.includes("adaptável") || name.includes("adaptavel")) {
        return NOISE_MODE_ADAPTIVE;
    }
    if (name.includes("transparen") || name.includes("ambient") || name.includes("ambiente")) {
        return NOISE_MODE_TRANSPARENCY;
    }
    if (name.includes("anc") || name.includes("cancelling") || name.includes("cancellation") || name.includes("cancelamento")) {
        return NOISE_MODE_ANC;
    }

    return null;
}

/**
 * Normalizes Toggle 1 (Noise Control) and Toggle 2 (Conversation Awareness or auxiliary toggle).
 */
function normalizeNoiseControls(rawState, rawConfig) {
    const state = (rawState && typeof rawState === "object") ? rawState : {};
    const config = (rawConfig && typeof rawConfig === "object") ? rawConfig : {};

    const isVisible = state.toggle1Visible !== false;
    const modes = [];
    const modeKeyToButtonIndex = {};
    const buttonIndexToModeKey = {};

    for (let i = 1; i <= 4; i++) {
        const iconKey = "toggle1Button" + i + "Icon";
        const nameKey = "toggle1Button" + i + "Name";

        const icon = config[iconKey];
        const name = config[nameKey];

        if (!icon && !name) continue;

        const semanticKey = inferNoiseModeSemantic(icon, name) || ("mode" + i);
        const meta = NOISE_MODE_METADATA[semanticKey] || {
            key: semanticKey,
            label: name || ("Mode " + i),
            icon: "tune",
            legacyName: name || "Mode"
        };

        const modeEntry = {
            key: semanticKey,
            buttonIndex: i,
            label: name || meta.label,
            icon: meta.icon,
            iconSource: icon || "",
            legacyName: meta.legacyName
        };

        modes.push(modeEntry);
        modeKeyToButtonIndex[semanticKey] = i;
        buttonIndexToModeKey[i] = semanticKey;
    }

    const currentState = Number(state.toggle1State) || 1;
    const currentModeKey = buttonIndexToModeKey[currentState] || (modes.length > 0 ? modes[0].key : NOISE_MODE_OFF);
    const currentModeMeta = modes.find(m => m.key === currentModeKey) || (modes.length > 0 ? modes[0] : NOISE_MODE_METADATA["off"]);

    return {
        available: isVisible && modes.length > 0,
        title: config.toggle1Title || "Noise Control",
        modes: modes,
        currentMode: currentModeKey,
        currentModeLabel: currentModeMeta.label,
        currentModeIcon: currentModeMeta.icon,
        currentState: currentState,
        modeKeyToButtonIndex: modeKeyToButtonIndex,
        buttonIndexToModeKey: buttonIndexToModeKey,
        hasAdaptive: modes.some(m => m.key === NOISE_MODE_ADAPTIVE),
        hasTransparency: modes.some(m => m.key === NOISE_MODE_TRANSPARENCY),
        hasAnc: modes.some(m => m.key === NOISE_MODE_ANC)
    };
}

/**
 * Normalizes Toggle 2 (often Conversation Awareness / Speak-to-Chat).
 */
function normalizeConversationAwareness(rawState, rawConfig) {
    const state = (rawState && typeof rawState === "object") ? rawState : {};
    const config = (rawConfig && typeof rawConfig === "object") ? rawConfig : {};

    const isVisible = state.toggle2Visible !== false;
    const title = (config.toggle2Title || "").toLowerCase();
    const btn1Icon = (config.toggle2Button1Icon || "").toLowerCase();
    const btn2Icon = (config.toggle2Button2Icon || "").toLowerCase();
    const btn1Name = (config.toggle2Button1Name || "").toLowerCase();
    const btn2Name = (config.toggle2Button2Name || "").toLowerCase();

    const isCA = title.includes("conversation") || title.includes("speak") || title.includes("voice") ||
                 btn1Icon.includes("ca") || btn2Icon.includes("ca") ||
                 btn1Name.includes("conversation") || btn2Name.includes("conversation");

    if (!isCA && !config.toggle2Button1Name && !config.toggle2Button1Icon) {
        return {
            available: false,
            enabled: false,
            title: "",
            toggleState: 0
        };
    }

    const currentState = Number(state.toggle2State) || 1;
    // Determine which button corresponds to "on"
    let onButtonIndex = 2;
    if (btn1Icon.includes("on") || btn1Name.includes("on") || btn1Name.includes("ativad") || btn1Name.includes("ligad")) {
        onButtonIndex = 1;
    } else if (btn2Icon.includes("on") || btn2Name.includes("on") || btn2Name.includes("ativad") || btn2Name.includes("ligad")) {
        onButtonIndex = 2;
    }

    const isEnabled = currentState === onButtonIndex;

    return {
        available: isVisible && (isCA || Boolean(config.toggle2Button1Name || config.toggle2Button1Icon)),
        enabled: isEnabled,
        title: config.toggle2Title || "Conversation Awareness",
        toggleState: currentState,
        onButtonIndex: onButtonIndex,
        offButtonIndex: onButtonIndex === 1 ? 2 : 1
    };
}

/**
 * Normalizes Dynamic Option Boxes (1..4) from BudsLink.
 */
function normalizeOptionBoxes(rawState, rawConfig) {
    const state = (rawState && typeof rawState === "object") ? rawState : {};
    const config = (rawConfig && typeof rawConfig === "object") ? rawConfig : {};

    const boxes = [];
    const isGlobalVisible = state.optionsBoxVisible !== false;

    if (!isGlobalVisible) return boxes;

    for (let i = 1; i <= 4; i++) {
        const boxKey = "optionsBox" + i;
        const boxType = config[boxKey];
        if (!boxType) continue;

        const sliderTitle = config["box" + i + "SliderTitle"];
        const checkBtn1 = config["box" + i + "CheckButton1"];
        const checkBtn2 = config["box" + i + "CheckButton2"];
        const radioTitle = config["box" + i + "RadioTitle"];

        const hasSlider = sliderTitle !== undefined || boxType.includes("slider");
        const hasCheck = (checkBtn1 !== undefined || checkBtn2 !== undefined) || boxType.includes("check");
        const hasRadio = radioTitle !== undefined || boxType.includes("radio");

        const boxData = {
            index: i,
            type: boxType,
            hasSlider: hasSlider,
            slider: hasSlider ? {
                title: sliderTitle || "Level",
                value: Number(state["box" + i + "SliderValue"]) || 0,
                isDragging: Boolean(state["box" + i + "SliderIsDragging"])
            } : null,
            hasCheck: hasCheck,
            checkButtons: hasCheck ? [
                checkBtn1 ? { index: 1, title: checkBtn1, state: Boolean(state["box" + i + "CheckButton1State"]) } : null,
                checkBtn2 ? { index: 2, title: checkBtn2, state: Boolean(state["box" + i + "CheckButton2State"]) } : null
            ].filter(Boolean) : [],
            hasRadio: hasRadio,
            radio: hasRadio ? {
                title: radioTitle || "Option",
                state: Number(state["box" + i + "RadioButtonState"]) || 0
            } : null
        };

        boxes.push(boxData);
    }

    return boxes;
}

/**
 * Normalizes label indicators if present.
 */
function normalizeIndicators(rawState, rawConfig) {
    const state = (rawState && typeof rawState === "object") ? rawState : {};
    const config = (rawConfig && typeof rawConfig === "object") ? rawConfig : {};

    const indicators = [];
    for (let i = 1; i <= 3; i++) {
        const text = state["indicator" + i + "Text"] || config["indicator" + i + "Text"];
        const icon = state["indicator" + i + "Icon"] || config["indicator" + i + "Icon"];
        if (text || icon) {
            indicators.push({
                index: i,
                text: text || "",
                icon: icon || ""
            });
        }
    }
    return indicators;
}

/**
 * Complete device representation combining all normalizations.
 */
function normalizeDevice(rawDevice) {
    if (!rawDevice || typeof rawDevice !== "object") return null;

    const path = rawDevice.path || "";
    const mac = rawDevice.mac || extractMacFromPath(path);
    const alias = rawDevice.alias || "";
    const rawConfig = rawDevice.config || {};
    const rawState = rawDevice.state || {};

    const battery = normalizeBattery(rawState, rawConfig);
    const noiseControls = normalizeNoiseControls(rawState, rawConfig);
    const conversationAwareness = normalizeConversationAwareness(rawState, rawConfig);
    const optionBoxes = normalizeOptionBoxes(rawState, rawConfig);
    const indicators = normalizeIndicators(rawState, rawConfig);

    return {
        path: path,
        mac: mac,
        alias: alias,
        rawConfig: rawConfig,
        rawState: rawState,
        battery: battery,
        noiseControls: noiseControls,
        conversationAwareness: conversationAwareness,
        optionBoxes: optionBoxes,
        indicators: indicators,
        hasSettingsButton: rawConfig.showSettingsButton === true,
        capabilities: {
            enhanced: true,
            provider: "budslink",
            batteryBreakdown: battery.available && battery.components.length > 1,
            leftBattery: battery.left !== null && battery.left.available,
            rightBattery: battery.right !== null && battery.right.available,
            caseBattery: battery.case !== null && battery.case.available,
            noiseControl: noiseControls.available,
            adaptiveNoiseControl: noiseControls.hasAdaptive,
            transparency: noiseControls.hasTransparency,
            anc: noiseControls.hasAnc,
            conversationAwareness: conversationAwareness.available,
            dynamicOptions: optionBoxes.length > 0,
            deviceSettings: rawConfig.showSettingsButton === true
        }
    };
}
