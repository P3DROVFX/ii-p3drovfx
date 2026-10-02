.pragma library

// Pure helpers for the EasyEffects integration: preset names and families, the preset
// JSON (chain order, blocks, defaults), socket value encoding and the equalizer's
// response curve. No QML types in here, so scripts/tests/test_easyeffects_logic.cjs can
// run it under Node.

// ── Preset names ─────────────────────────────────────────────────────────────

// What splits a preset family from the preset itself: "A50 · Music", "Speakers - Movies",
// "HD600: Harman". The first match wins; a name without one has no family.
var familySeparators = [" · ", " • ", " — ", " – ", " - ", ": ", " | ", " / "];

function splitName(name) {
    var text = String(name || "");
    for (var i = 0; i < familySeparators.length; i++) {
        var at = text.indexOf(familySeparators[i]);
        if (at > 0 && at + familySeparators[i].length < text.length)
            return { family: text.slice(0, at), label: text.slice(at + familySeparators[i].length) };
    }
    return { family: "", label: text };
}

function familyOf(name) {
    return splitName(name).family;
}

// The part worth showing where the device is already on screen: "Music" for "A50 · Music".
function shortName(name) {
    return splitName(name).label;
}

/**
 * The presets the quick switchers cycle through for a device.
 *
 * "device" keeps to the family of the device's own default preset (its autoload entry),
 * falling back to the family of the preset in use, so a headset's presets never land on
 * the laptop speakers. "all" is every preset. When the family matches nothing, or there
 * is no family to go by, every preset is offered.
 */
function presetsForDevice(all, deviceDefault, current, scope) {
    var list = Array.from(all || []);
    if (scope === "all")
        return list;
    var family = familyOf(deviceDefault) || familyOf(current);
    if (!family)
        return list;
    var matching = list.filter(function (name) { return familyOf(name) === family; });
    return matching.length > 0 ? matching : list;
}

function stepPreset(list, current, step) {
    var names = Array.from(list || []);
    if (names.length === 0)
        return "";
    var index = names.indexOf(current);
    if (index === -1)
        return step >= 0 ? names[0] : names[names.length - 1];
    var next = (index + step) % names.length;
    if (next < 0)
        next += names.length;
    return names[next];
}

// A glyph from the words in a preset's name; the generic equalizer mark otherwise.
var iconRules = [
    [/music|song|hifi|hi-fi|harman|studio|reference/i, "music_note"],
    [/movie|film|cinema|video|tv|series|netflix/i, "movie"],
    [/voice|vocal|speech|podcast|talk|call|meeting|dialog/i, "record_voice_over"],
    [/game|gaming|fps|esport/i, "sports_esports"],
    [/night|late|quiet|sleep/i, "bedtime"],
    [/bass|boost|club|party/i, "speaker"],
    [/mic|noise|denois|rnnoise|gate/i, "mic"],
    [/flat|neutral|off|none|bypass|default/i, "horizontal_rule"],
    [/loud|volume|normal/i, "volume_up"]
];

function iconFor(name) {
    var label = shortName(name);
    for (var i = 0; i < iconRules.length; i++) {
        if (iconRules[i][0].test(label))
            return iconRules[i][1];
    }
    return "graphic_eq";
}

var effectIcons = {
    autogain: "auto_fix_high", autotune: "music_note", bass_enhancer: "speaker", bass_loudness: "speaker",
    compressor: "compress", convolver: "spatial_audio", crossfeed: "headphones", crosstalk_canceller: "headphones",
    crusher: "grain", crystalizer: "diamond", deepfilternet: "noise_control_off", deesser: "record_voice_over",
    delay: "timer", echo_canceller: "voice_over_off", equalizer: "equalizer", midside_equalizer: "equalizer",
    exciter: "bolt", expander: "expand", filter: "filter_alt", gate: "door_front", level_meter: "monitoring",
    limiter: "vertical_align_top", loudness: "volume_up", maximizer: "open_in_full",
    multiband_compressor: "compress", multiband_gate: "door_front", pitch: "piano", reverb: "blur_on",
    rnnoise: "noise_control_off", speex: "record_voice_over", stereo_tools: "surround_sound",
    voice_suppressor: "voice_selection_off"
};

function effectIcon(plugin) {
    return effectIcons[instanceParts(plugin).plugin] || "tune";
}

// A file name EasyEffects will accept: no path separators, no hidden files.
function sanitizePresetName(name) {
    return String(name || "").replace(/[\/\\\u0000]/g, " ").replace(/\s+/g, " ").trim().replace(/^[.\s]+/, "");
}

function uniqueName(base, taken) {
    var names = Array.from(taken || []);
    if (names.indexOf(base) === -1)
        return base;
    for (var n = 2; n < 1000; n++) {
        var candidate = base + " (" + n + ")";
        if (names.indexOf(candidate) === -1)
            return candidate;
    }
    return base + " (" + Date.now() + ")";
}

// ── Devices ──────────────────────────────────────────────────────────────────

// EasyEffects keys an autoload entry by the node name and the device's active route:
// the route's description for cards that have routes, empty for Pro Audio profiles.
function routeFor(properties) {
    var props = properties || {};
    var routes = Number(props["device.routes"] || 0);
    return routes > 0 ? String(props["device.profile.description"] || "") : "";
}

function autoloadFileName(device, route) {
    return String(device || "") + ":" + String(route || "") + ".json";
}

// The entry for a device, preferring the one saved for its current route.
function autoloadFor(entries, device, route) {
    var list = Array.from(entries || []).filter(function (entry) { return entry && entry.device === device; });
    if (list.length === 0)
        return null;
    for (var i = 0; i < list.length; i++) {
        if ((list[i]["device-profile"] || "") === (route || ""))
            return list[i];
    }
    return list[0];
}

// ── KConfig files ────────────────────────────────────────────────────────────

function parseRc(text) {
    var groups = {};
    var current = "";
    String(text || "").split("\n").forEach(function (raw) {
        var line = raw.trim();
        if (line.length === 0 || line[0] === "#")
            return;
        if (line[0] === "[" && line[line.length - 1] === "]") {
            current = line.slice(1, -1);
            groups[current] = groups[current] || {};
            return;
        }
        var eq = line.indexOf("=");
        if (eq <= 0)
            return;
        groups[current] = groups[current] || {};
        groups[current][line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
    });
    return groups;
}

// ── Chain and blocks ─────────────────────────────────────────────────────────

function instanceParts(instance) {
    var text = String(instance || "");
    var hash = text.lastIndexOf("#");
    if (hash === -1)
        return { plugin: text, index: 0 };
    return { plugin: text.slice(0, hash), index: Number(text.slice(hash + 1)) || 0 };
}

function nextInstanceId(order, plugin) {
    var used = Array.from(order || []).map(instanceParts)
        .filter(function (parts) { return parts.plugin === plugin; })
        .map(function (parts) { return parts.index; });
    var index = 0;
    while (used.indexOf(index) !== -1)
        index++;
    return plugin + "#" + index;
}

function clone(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value));
}

function pipelineOf(preset, pipeline) {
    return (preset && preset[pipeline]) ? preset[pipeline] : null;
}

function chainOf(preset, pipeline) {
    var body = pipelineOf(preset, pipeline);
    return body && body.plugins_order ? Array.from(body.plugins_order) : [];
}

function bandDefault(control, band) {
    var defaults = control.defaults || [];
    var value = defaults[band];
    return value === null || value === undefined ? defaults[control.fromBand || 0] : value;
}

function bandBlock(bands, band) {
    var block = {};
    bands.controls.forEach(function (control) {
        if (band < (control.fromBand || 0))
            return;
        block[control.key] = bandDefault(control, band);
    });
    return block;
}

/**
 * A complete block for a new effect, every key at EasyEffects' own default.
 *
 * Complete, not minimal: a choice key missing from a preset keeps whatever the previous
 * preset left in it, and the banded effects throw on a missing band section.
 */
function defaultBlock(table, plugin) {
    var spec = table[plugin];
    if (!spec)
        return null;
    var block = {};
    spec.controls.forEach(function (control) {
        if (control.section) {
            block[control.section] = block[control.section] || {};
            block[control.section][control.key] = control.default;
        } else {
            block[control.key] = control.default;
        }
    });
    if (spec.bands && spec.channels) {
        var count = Number(block[spec.bands.countKey] || spec.bands.count);
        spec.channels.forEach(function (channel) {
            var bands = {};
            for (var n = 0; n < count; n++)
                bands["band" + n] = bandBlock(spec.bands, n);
            block[channel] = bands;
        });
    } else if (spec.bands) {
        for (var b = 0; b < spec.bands.count; b++)
            block["band" + b] = bandBlock(spec.bands, b);
    }
    return block;
}

function withPipeline(preset, pipeline, edit) {
    var next = clone(preset) || {};
    next[pipeline] = next[pipeline] || { blocklist: [], plugins_order: [] };
    next[pipeline].plugins_order = Array.from(next[pipeline].plugins_order || []);
    edit(next[pipeline]);
    return next;
}

function addEffect(preset, pipeline, table, plugin, position) {
    var block = defaultBlock(table, plugin);
    if (!block)
        return preset;
    return withPipeline(preset, pipeline, function (body) {
        var instance = nextInstanceId(body.plugins_order, plugin);
        var at = position === undefined || position < 0 || position > body.plugins_order.length
            ? body.plugins_order.length : position;
        body.plugins_order.splice(at, 0, instance);
        body[instance] = block;
    });
}

function removeEffect(preset, pipeline, instance) {
    return withPipeline(preset, pipeline, function (body) {
        body.plugins_order = body.plugins_order.filter(function (id) { return id !== instance; });
        delete body[instance];
    });
}

function moveEffect(preset, pipeline, from, to) {
    return withPipeline(preset, pipeline, function (body) {
        var order = body.plugins_order;
        if (from < 0 || from >= order.length || to < 0 || to >= order.length || from === to)
            return;
        var moved = order.splice(from, 1)[0];
        order.splice(to, 0, moved);
    });
}

// Writes one key. `section` is "" for a top-level key, a subsection ("sidechain"), a
// band ("band3") or a channel band ("left/band3").
function setValue(preset, pipeline, instance, section, key, value) {
    return withPipeline(preset, pipeline, function (body) {
        var target = body[instance] = body[instance] || {};
        String(section || "").split("/").filter(function (part) { return part.length > 0; })
            .forEach(function (part) {
                target[part] = target[part] || {};
                target = target[part];
            });
        target[key] = value;
    });
}

function valueAt(preset, pipeline, instance, section, key) {
    var body = pipelineOf(preset, pipeline);
    var target = body ? body[instance] : null;
    var parts = String(section || "").split("/").filter(function (part) { return part.length > 0; });
    for (var i = 0; target && i < parts.length; i++)
        target = target[parts[i]];
    return target ? target[key] : undefined;
}

// ── Socket values ────────────────────────────────────────────────────────────

// What set_property expects: a choice by index, a switch as true/false.
function encodeValue(control, value) {
    if (control.type === "enum") {
        var index = (control.options || []).indexOf(value);
        return index === -1 ? null : String(index);
    }
    if (control.type === "bool")
        return value ? "true" : "false";
    if (control.type === "int")
        return String(Math.round(Number(value)));
    if (control.type === "double")
        return String(Number(value));
    return String(value);
}

function decodeValue(control, raw) {
    var text = String(raw === undefined || raw === null ? "" : raw).trim();
    if (text.length === 0 || text.indexOf("error") === 0)
        return undefined;
    if (control.type === "enum") {
        var index = parseInt(text, 10);
        return isNaN(index) ? undefined : (control.options || [])[index];
    }
    if (control.type === "bool")
        return text === "true" || text === "1";
    if (control.type === "int" || control.type === "double") {
        var number = Number(text);
        return isNaN(number) ? undefined : number;
    }
    return text;
}

// "equalizer:0:left:band3Gain": the socket path of one control, or "" when the socket
// cannot reach it (EasyEffects only routes left/right channels, and only for the equalizer).
function socketPath(instance, control, band, channel) {
    var parts = instanceParts(instance);
    var prop = control.propPattern ? control.propPattern.replace("%1", String(band)) : control.prop;
    if (!prop)
        return "";
    if (channel) {
        if (parts.plugin !== "equalizer" || (channel !== "left" && channel !== "right"))
            return "";
        return parts.plugin + ":" + parts.index + ":" + channel + ":" + prop;
    }
    return parts.plugin + ":" + parts.index + ":" + prop;
}

// ── Labels and units ─────────────────────────────────────────────────────────

var acronyms = { alr: "ALR", hpf: "HPF", lpf: "LPF", q: "Q", sofa: "SOFA", vad: "VAD", agc: "AGC", bpm: "BPM",
    fft: "FFT", lfo: "LFO", ir: "IR", db: "dB", ms: "ms", hz: "Hz", eq: "EQ" };

// Keys whose spelled-out name says little.
var labelOverrides = { "num-bands": "Bands", "fcut": "Cutoff", "feed": "Feed level", "split-channels": "Split channels",
    "hpf-frequency": "High-pass frequency", "lpf-frequency": "Low-pass frequency", "hpf-mode": "High-pass",
    "lpf-mode": "Low-pass", "q": "Q" };

function labelFor(key) {
    if (labelOverrides[key])
        return labelOverrides[key];
    var words = String(key || "").split("-").filter(function (word) { return word.length > 0; });
    return words.map(function (word, i) {
        var lower = word.toLowerCase();
        if (acronyms[lower])
            return acronyms[lower];
        return i === 0 ? lower.charAt(0).toUpperCase() + lower.slice(1) : lower;
    }).join(" ");
}

function unitFor(key) {
    var k = String(key || "");
    if (/(^|-)(gain|threshold|makeup|preamp|reduction|amount|boost-amount|range|floor|zone)$|-to-|^volume$|^level|ceiling|knee|^target$/.test(k))
        return "dB";
    if (/(^|-)(attack|release|lookahead|reactivity|time|delay|hold|attack-time|release-time|predelay)$|-ms$/.test(k))
        return "ms";
    if (/frequency|fcut|cutoff|(^|-)(hpf|lpf|freq)(-|$)|split/.test(k))
        return "Hz";
    if (/(^|-)(dry|wet|mix|stereo-link|probability)/.test(k))
        return k.indexOf("probability") !== -1 ? "%" : "";
    return "";
}

function formatValue(control, value) {
    if (value === undefined || value === null)
        return "–";
    if (control.type === "bool")
        return value ? "On" : "Off";
    if (control.type === "enum" || control.type === "string")
        return String(value);
    var number = Number(value);
    var unit = unitFor(control.key);
    var digits = Math.abs(number) >= 1000 ? 0 : Math.abs(number) >= 100 ? 1 : 2;
    var text = unit === "Hz" && number >= 1000
        ? (number / 1000).toFixed(number >= 10000 ? 1 : 2).replace(/\.?0+$/, "") + " kHz"
        : String(Number(number.toFixed(control.type === "int" ? 0 : digits))) + (unit ? " " + unit : "");
    return text;
}

// A slider step that feels right for the range: fine for gains, coarse for frequencies.
function stepFor(control) {
    if (control.type === "int")
        return 1;
    var span = Number(control.max) - Number(control.min);
    if (!isFinite(span) || span <= 0)
        return 0.1;
    if (span > 1000)
        return 1;
    if (span > 100)
        return 0.5;
    if (span > 10)
        return 0.1;
    return 0.01;
}

// Logarithmic sliders for frequencies, so the audible range gets the width.
function isLogControl(control) {
    return control.type !== "bool" && control.type !== "enum" && unitFor(control.key) === "Hz"
        && Number(control.min) > 0 && Number(control.max) / Number(control.min) > 50;
}

// ── Equalizer response ───────────────────────────────────────────────────────

var sampleRate = 48000;

function biquad(type, f0, gainDb, q) {
    var A = Math.pow(10, gainDb / 40);
    var w0 = 2 * Math.PI * Math.min(f0, sampleRate * 0.49) / sampleRate;
    var cos = Math.cos(w0);
    var alpha = Math.sin(w0) / (2 * Math.max(q, 0.025));
    var sqrtA2alpha = 2 * Math.sqrt(A) * alpha;
    switch (type) {
    case "Bell":
        return [1 + alpha * A, -2 * cos, 1 - alpha * A, 1 + alpha / A, -2 * cos, 1 - alpha / A];
    case "Lo-shelf":
        return [A * ((A + 1) - (A - 1) * cos + sqrtA2alpha), 2 * A * ((A - 1) - (A + 1) * cos),
            A * ((A + 1) - (A - 1) * cos - sqrtA2alpha), (A + 1) + (A - 1) * cos + sqrtA2alpha,
            -2 * ((A - 1) + (A + 1) * cos), (A + 1) + (A - 1) * cos - sqrtA2alpha];
    case "Hi-shelf":
        return [A * ((A + 1) + (A - 1) * cos + sqrtA2alpha), -2 * A * ((A - 1) + (A + 1) * cos),
            A * ((A + 1) + (A - 1) * cos - sqrtA2alpha), (A + 1) - (A - 1) * cos + sqrtA2alpha,
            2 * ((A - 1) - (A + 1) * cos), (A + 1) - (A - 1) * cos - sqrtA2alpha];
    case "Hi-pass":
        return [(1 + cos) / 2, -(1 + cos), (1 + cos) / 2, 1 + alpha, -2 * cos, 1 - alpha];
    case "Lo-pass":
        return [(1 - cos) / 2, 1 - cos, (1 - cos) / 2, 1 + alpha, -2 * cos, 1 - alpha];
    case "Notch":
        return [1, -2 * cos, 1, 1 + alpha, -2 * cos, 1 - alpha];
    case "Bandpass":
        return [alpha, 0, -alpha, 1 + alpha, -2 * cos, 1 - alpha];
    }
    return null;
}

function magnitudeDb(coeffs, f) {
    var w = 2 * Math.PI * f / sampleRate;
    var c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w);
    var nr = coeffs[0] + coeffs[1] * c1 + coeffs[2] * c2;
    var ni = -(coeffs[1] * s1 + coeffs[2] * s2);
    var dr = coeffs[3] + coeffs[4] * c1 + coeffs[5] * c2;
    var di = -(coeffs[4] * s1 + coeffs[5] * s2);
    var num = nr * nr + ni * ni;
    var den = dr * dr + di * di;
    if (num <= 0 || den <= 0)
        return -60;
    return 10 * Math.log10(num / den);
}

function logFrequencies(points, lo, hi) {
    var list = [];
    var from = Math.log10(lo || 20), to = Math.log10(hi || 20000);
    for (var i = 0; i < points; i++)
        list.push(Math.pow(10, from + (to - from) * i / Math.max(1, points - 1)));
    return list;
}

/**
 * The summed response of a channel's bands, in dB, at each frequency.
 *
 * An approximation of what the filters do (RBJ biquads, each slope step one more pass),
 * which is what the curve is for: seeing the shape of a preset, not measuring it.
 */
function equalizerResponse(channel, bandCount, frequencies) {
    var bands = channel || {};
    var filters = [];
    for (var n = 0; n < bandCount; n++) {
        var band = bands["band" + n];
        if (!band || band.mute || band.type === "Off")
            continue;
        var coeffs = biquad(band.type, Number(band.frequency) || 1000, Number(band.gain) || 0, Number(band.q) || 0.7);
        if (!coeffs)
            continue;
        var passes = /^Hi-pass|^Lo-pass/.test(band.type) ? (parseInt(String(band.slope || "x1").slice(1), 10) || 1) : 1;
        filters.push({ coeffs: coeffs, passes: passes });
    }
    return frequencies.map(function (f) {
        var total = 0;
        filters.forEach(function (filter) { total += filter.passes * magnitudeDb(filter.coeffs, f); });
        return total;
    });
}

// ── Preset at a glance ───────────────────────────────────────────────────────

var equalizerChannels = { equalizer: ["left", "right"], midside_equalizer: ["mid", "side"] };

/**
 * What the whole chain does to the sound, in dB, at each frequency: every switched-on
 * equalizer summed. The other effects change level or dynamics, not frequencies, so the
 * curve stays an honest picture of the tone. A split equalizer contributes the mean of
 * its two channels; a chain without an equalizer is a flat line.
 */
function chainResponse(preset, pipeline, frequencies) {
    var body = pipelineOf(preset, pipeline);
    var total = frequencies.map(function () { return 0; });
    if (!body)
        return total;
    chainOf(preset, pipeline).forEach(function (instance) {
        var channels = equalizerChannels[instanceParts(instance).plugin];
        var block = body[instance];
        if (!channels || !block || block.bypass === true)
            return;
        var count = Number(block["num-bands"] || 0);
        var curves = (block["split-channels"] === true ? channels : [channels[0]]).map(function (channel) {
            return equalizerResponse(block[channel], count, frequencies);
        });
        total = total.map(function (value, i) {
            var sum = 0;
            curves.forEach(function (curve) { sum += curve[i]; });
            return value + sum / curves.length;
        });
    });
    return total;
}

/** The plugin names of a chain, in order, without the instance suffix: ["autogain", "equalizer"]. */
function chainPlugins(preset, pipeline) {
    return chainOf(preset, pipeline).map(function (instance) { return instanceParts(instance).plugin; });
}

// ── Control glyphs ───────────────────────────────────────────────────────────

// A glyph for a control, from the words in its key, so a settings tile says what it holds
// at a glance. The generic "tune" is for the keys no rule knows.
var controlIconRules = [
    [/^input-gain|^preamp/, "input"],
    [/^output-gain|^volume|^makeup|^level/, "volume_up"],
    [/^target|^reference/, "my_location"],
    [/silence|^reduction|^floor|^zone/, "volume_mute"],
    [/history|^lookahead|^hold/, "history"],
    [/threshold|^ceiling/, "vertical_align_center"],
    [/^ratio/, "compress"],
    [/^attack/, "trending_up"],
    [/^release/, "trending_down"],
    [/^knee/, "show_chart"],
    [/frequency|^fcut|cutoff|^hpf|^lpf|^freq/, "graphic_eq"],
    [/^q$|^width|^slope|bandwidth/, "tune"],
    [/gain|^boost|^amount|^drive|^harmonics/, "equalizer"],
    [/^dry|^wet|^mix|^blend/, "water_drop"],
    [/time|delay|^predelay|^decay/, "timer"],
    [/^room|^diffusion|^size/, "meeting_room"],
    [/^bypass|^enable|^force|^split|^mute|^solo/, "toggle_on"],
    [/^mode|^type|^scope|^std|^reference/, "category"],
    [/^balance|^stereo|^pan|^side|^mid/, "swap_horiz"],
    [/^semitones|^cents|^octaves|^pitch/, "piano"]
];

function controlIcon(key) {
    var text = String(key || "");
    for (var i = 0; i < controlIconRules.length; i++) {
        if (controlIconRules[i][0].test(text))
            return controlIconRules[i][1];
    }
    return "tune";
}

// ── Equalizer summary ────────────────────────────────────────────────────────

/**
 * The band of an equalizer that moves the sound the most, for a one-line summary:
 * `{ gain, type, frequency }`, or null when nothing moves. Passes and notches have no
 * gain to speak of and are skipped. `channel` is the section to read, "left" for a
 * normal equalizer.
 */
function strongestBand(block, channel) {
    var count = Number(block && block["num-bands"] || 0);
    var bands = (block && block[channel]) || {};
    var strongest = null;
    for (var n = 0; n < count; n++) {
        var band = bands["band" + n];
        if (!band || band.mute || band.type === "Off" || /pass|Notch/.test(band.type))
            continue;
        var gain = Number(band.gain) || 0;
        if (!strongest || Math.abs(gain) > Math.abs(strongest.gain))
            strongest = { gain: gain, type: band.type, frequency: Number(band.frequency) || 0 };
    }
    return strongest && Math.abs(strongest.gain) >= 0.05 ? strongest : null;
}

// ── Device glyphs ────────────────────────────────────────────────────────────

/**
 * A glyph for an audio device from the words PipeWire gives it (form factor, icon name,
 * description, node name), joined into `text`: a headset's microphone, an HDMI monitor,
 * Bluetooth buds. `pipeline` is "input" or "output".
 */
function deviceSymbol(text, pipeline) {
    var t = String(text || "").toLowerCase();
    if (pipeline === "input") {
        if (/headset|headphone/.test(t))
            return "headset_mic";
        if (/usb/.test(t))
            return "mic_external_on";
        return "mic";
    }
    if (/headphone|headset|earbud|buds|airpods/.test(t))
        return "headphones";
    if (/hdmi|display|monitor|tv/.test(t))
        return "tv";
    if (/bluez|bluetooth/.test(t))
        return "bluetooth_audio";
    return "speaker";
}
