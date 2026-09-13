.pragma library

// Canonical Tokenizer for Keybindings and Chords across Hyprland, Personal Libraries, and Editors.

const MODIFIER_ORDER = ["Super", "Ctrl", "Alt", "Shift"];

const MODIFIER_ALIASES = {
    "super": "Super",
    "win": "Super",
    "windows": "Super",
    "mod4": "Super",
    "meta": "Super",
    "cmd": "Super",
    "command": "Super",
    "super_l": "Super",
    "super_r": "Super",
    "ctrl": "Ctrl",
    "control": "Ctrl",
    "mod1": "Alt",
    "alt": "Alt",
    "option": "Alt",
    "opt": "Alt",
    "alt_l": "Alt",
    "alt_r": "Alt",
    "shift": "Shift",
    "shift_l": "Shift",
    "shift_r": "Shift"
};

const KEY_ALIASES = {
    "return": "Enter",
    "enter": "Enter",
    "cr": "Enter",
    "<cr>": "Enter",
    "backspace": "Backspace",
    "back_space": "Backspace",
    "bs": "Backspace",
    "<bs>": "Backspace",
    "escape": "Esc",
    "esc": "Esc",
    "<esc>": "Esc",
    "space": "Space",
    "<space>": "Space",
    "tab": "Tab",
    "<tab>": "Tab",
    "delete": "Del",
    "del": "Del",
    "<del>": "Del",
    "insert": "Ins",
    "ins": "Ins",
    "<ins>": "Ins",
    "pageup": "PageUp",
    "page_up": "PageUp",
    "pgup": "PageUp",
    "pagedown": "PageDown",
    "page_down": "PageDown",
    "pgdn": "PageDown",
    "plus": "+",
    "minus": "-",
    "slash": "/",
    "backslash": "\\",
    "equal": "=",
    "semicolon": ";",
    "colon": ":",
    "comma": ",",
    "period": ".",
    "grave": "`",
    "tilde": "~",
    "exclamation": "!",
    "at": "@",
    "hash": "#",
    "dollar": "$",
    "percent": "%",
    "caret": "^",
    "ampersand": "&",
    "asterisk": "*",
    "left": "Left",
    "right": "Right",
    "up": "Up",
    "down": "Down",
    "home": "Home",
    "end": "End",
    "leader": "<leader>",
    "<leader>": "<leader>"
};

function normalizeKeyName(rawKey) {
    if (!rawKey) return "";
    const clean = String(rawKey).trim();
    const lower = clean.toLowerCase();
    if (KEY_ALIASES[lower]) return KEY_ALIASES[lower];
    if (MODIFIER_ALIASES[lower]) return MODIFIER_ALIASES[lower];
    
    // Function keys: F1-F24
    if (/^f([1-9]|1[0-9]|2[0-4])$/i.test(clean)) {
        return clean.toUpperCase();
    }
    
    // Single character letters uppercase for consistency
    if (clean.length === 1 && clean >= 'a' && clean <= 'z') {
        return clean.toUpperCase();
    }
    
    return clean;
}

function parseVimNotation(chord) {
    // Converts Vim notation like <C-S-F> or <M-x> or <leader>ff into canonical format
    let text = String(chord || "").trim();
    
    text = text.replace(/<([CSMAD])-([A-Za-z0-9_+\-<>]+)>/gi, (match, mod, key) => {
        const modUpper = mod.toUpperCase();
        let modName = "Ctrl";
        if (modUpper === "S") modName = "Shift";
        else if (modUpper === "M" || modUpper === "A") modName = "Alt";
        else if (modUpper === "D") modName = "Super";
        return modName + "+" + key;
    });
    
    return text;
}

function parseSingleChord(chordStr) {
    const raw = parseVimNotation(chordStr);
    if (!raw) return { modifiers: [], key: "", canonical: "" };
    
    // Check if chord ends with literal '+' (e.g. "Ctrl++" or "Ctrl+Shift++")
    let working = raw;
    let hasTrailingPlus = false;
    if (working.endsWith("++")) {
        hasTrailingPlus = true;
        working = working.slice(0, -2);
    } else if (working === "+") {
        return { modifiers: [], key: "+", canonical: "+" };
    }
    
    const parts = working.split("+").map(p => p.trim()).filter(p => p.length > 0);
    if (hasTrailingPlus) {
        parts.push("+");
    }
    
    if (parts.length === 0) {
        return { modifiers: [], key: "", canonical: "" };
    }
    
    const modifiers = new Set();
    let mainKey = "";
    
    for (let i = 0; i < parts.length; i++) {
        const part = parts[i];
        const lower = part.toLowerCase();
        if (MODIFIER_ALIASES[lower] && (i < parts.length - 1 || parts.length === 1)) {
            if (i === parts.length - 1 && parts.length === 1) {
                mainKey = MODIFIER_ALIASES[lower];
            } else {
                modifiers.add(MODIFIER_ALIASES[lower]);
            }
        } else {
            mainKey = normalizeKeyName(part);
        }
    }
    
    const sortedModifiers = MODIFIER_ORDER.filter(m => modifiers.has(m));
    const canonicalPieces = [...sortedModifiers];
    if (mainKey && !sortedModifiers.includes(mainKey)) {
        canonicalPieces.push(mainKey);
    }
    
    const canonical = canonicalPieces.join("+");
    return {
        modifiers: sortedModifiers,
        key: mainKey,
        canonical: canonical
    };
}

function tokenize(input) {
    const raw = String(input || "").trim();
    if (!raw) return { stages: [], canonical: "", tokens: [] };
    
    // Split by alternative separator (e.g. " / " or " | ")
    const alternatives = raw.split(/\s*[\/|]\s*/).filter(a => a.length > 0);
    const parsedAlternatives = alternatives.map(alt => {
        // Split by sequence separator (" then ", " -> ", " , ", or space between chords)
        let normalizedSeq = alt.replace(/\s+then\s+/gi, " ")
                               .replace(/\s*->\s*/g, " ")
                               .replace(/\s*,\s*/g, " ");
                               
        const chordParts = normalizedSeq.split(/\s+/).filter(p => p.length > 0);
        const stages = chordParts.map(parseSingleChord);
        const canonical = stages.map(s => s.canonical).join(" ");
        return {
            stages: stages,
            canonical: canonical
        };
    });
    
    const fullCanonical = parsedAlternatives.map(a => a.canonical).join(" / ");
    const allStages = [];
    for (let i = 0; i < parsedAlternatives.length; i++) {
        const st = parsedAlternatives[i].stages;
        for (let j = 0; j < st.length; j++) {
            allStages.push(st[j]);
        }
    }
    
    return {
        alternatives: parsedAlternatives,
        stages: allStages,
        canonical: fullCanonical,
        tokens: allStages.map(s => s.canonical)
    };
}

function spokenDescription(input) {
    const parsed = tokenize(input);
    if (!parsed.stages.length) return "";
    
    return parsed.stages.map(stage => {
        const parts = [];
        for (const mod of stage.modifiers) {
            if (mod === "Super") parts.push("Super");
            else if (mod === "Ctrl") parts.push("Control");
            else if (mod === "Alt") parts.push("Alt");
            else if (mod === "Shift") parts.push("Shift");
        }
        if (stage.key && !stage.modifiers.includes(stage.key)) {
            parts.push(stage.key);
        }
        return parts.join(" + ");
    }).join(" then ");
}

function matchQuery(shortcutStr, query) {
    if (!shortcutStr || !query) return false;
    const normKeybind = tokenize(shortcutStr).canonical.toLowerCase();
    const normQuery = tokenize(query).canonical.toLowerCase();
    if (normKeybind.includes(normQuery)) return true;
    
    // Also match raw text search
    const cleanKeybind = String(shortcutStr).toLowerCase();
    const cleanQuery = String(query).toLowerCase().trim();
    return cleanKeybind.includes(cleanQuery);
}

function keyEventToString(event, Qt) {
    if (!event) return "";
    const key = event.key;
    
    // Ignore pure modifier presses
    if (key === 0x01000021 || key === 0x01000020 || key === 0x01000023 || key === 0x01000022 || key === 0x01000024) {
        return "";
    }
    
    const modifiers = [];
    if (event.modifiers & (Qt?.MetaModifier ?? 0x10000000)) modifiers.push("Super");
    if (event.modifiers & (Qt?.ControlModifier ?? 0x04000000)) modifiers.push("Ctrl");
    if (event.modifiers & (Qt?.AltModifier ?? 0x08000000)) modifiers.push("Alt");
    if (event.modifiers & (Qt?.ShiftModifier ?? 0x02000000)) modifiers.push("Shift");
    
    let keyName = "";
    if (key >= 0x41 && key <= 0x5a) {
        keyName = String.fromCharCode(key);
    } else if (key >= 0x30 && key <= 0x39) {
        keyName = String.fromCharCode(key);
    } else if (key >= 0x01000030 && key <= 0x01000047) {
        keyName = "F" + (key - 0x01000030 + 1);
    } else {
        switch (key) {
            case 0x01000004: keyName = "Enter"; break;
            case 0x01000005: keyName = "Enter"; break;
            case 0x01000000: keyName = "Esc"; break;
            case 0x01000001: keyName = "Tab"; break;
            case 0x01000002: keyName = "Tab"; break;
            case 0x01000003: keyName = "Backspace"; break;
            case 0x20: keyName = "Space"; break;
            case 0x01000007: keyName = "Del"; break;
            case 0x01000006: keyName = "Ins"; break;
            case 0x01000012: keyName = "Left"; break;
            case 0x01000013: keyName = "Up"; break;
            case 0x01000014: keyName = "Right"; break;
            case 0x01000015: keyName = "Down"; break;
            case 0x01000016: keyName = "PageUp"; break;
            case 0x01000017: keyName = "PageDown"; break;
            case 0x01000010: keyName = "Home"; break;
            case 0x01000011: keyName = "End"; break;
            case 0x2b: keyName = "+"; break;
            case 0x2d: keyName = "-"; break;
            case 0x2f: keyName = "/"; break;
            case 0x5c: keyName = "\\"; break;
            case 0x3d: keyName = "="; break;
            case 0x3b: keyName = ";"; break;
            case 0x2c: keyName = ","; break;
            case 0x2e: keyName = "."; break;
            case 0x60: keyName = "`"; break;
            default:
                if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 33 && event.text.charCodeAt(0) <= 126) {
                    keyName = event.text.toUpperCase();
                }
                break;
        }
    }
    
    if (!keyName) return "";
    
    const pieces = [...modifiers];
    if (!pieces.includes(keyName)) {
        pieces.push(keyName);
    }
    return pieces.join("+");
}
