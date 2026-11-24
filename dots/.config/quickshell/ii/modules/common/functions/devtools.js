.pragma library

/**
 * DevTools pure JavaScript execution engine for Quickshell Search.
 * All functions are deterministic and dependency-free.
 */

// ─── UTF-8 & Base64 Helpers ──────────────────────────────────────────────────

function utf8Encode(str) {
    if (typeof TextEncoder !== "undefined") {
        return new TextEncoder().encode(str);
    }
    const utf8 = [];
    for (let i = 0; i < str.length; i++) {
        let charcode = str.charCodeAt(i);
        if (charcode < 0x80) {
            utf8.push(charcode);
        } else if (charcode < 0x800) {
            utf8.push(0xc0 | (charcode >> 6),
                      0x80 | (charcode & 0x3f));
        } else if (charcode < 0xd800 || charcode >= 0xe000) {
            utf8.push(0xe0 | (charcode >> 12),
                      0x80 | ((charcode >> 6) & 0x3f),
                      0x80 | (charcode & 0x3f));
        } else {
            // Surrogate pair
            i++;
            charcode = 0x10000 + (((charcode & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
            utf8.push(0xf0 | (charcode >> 18),
                      0x80 | ((charcode >> 12) & 0x3f),
                      0x80 | ((charcode >> 6) & 0x3f),
                      0x80 | (charcode & 0x3f));
        }
    }
    return new Uint8Array(utf8);
}

function utf8Decode(bytes) {
    if (typeof TextDecoder !== "undefined") {
        return new TextDecoder("utf-8").decode(bytes);
    }
    let out = "";
    let i = 0;
    const len = bytes.length;
    while (i < len) {
        const c = bytes[i++];
        if (c < 0x80) {
            out += String.fromCharCode(c);
        } else if (c > 0xbf && c < 0xe0) {
            const c2 = bytes[i++];
            out += String.fromCharCode(((c & 0x1f) << 6) | (c2 & 0x3f));
        } else if (c > 0xdf && c < 0xf0) {
            const c2 = bytes[i++];
            const c3 = bytes[i++];
            out += String.fromCharCode(((c & 0x0f) << 12) | ((c2 & 0x3f) << 6) | (c3 & 0x3f));
        } else {
            const c2 = bytes[i++];
            const c3 = bytes[i++];
            const c4 = bytes[i++];
            let u = (((c & 0x07) << 18) | ((c2 & 0x3f) << 12) | ((c3 & 0x3f) << 6) | (c4 & 0x3f)) - 0x10000;
            out += String.fromCharCode(0xd800 + (u >> 10), 0xdc00 + (u & 0x3ff));
        }
    }
    return out;
}

const B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64_LOOKUP = new Uint8Array(256);
for (let i = 0; i < B64_CHARS.length; i++) {
    B64_LOOKUP[B64_CHARS.charCodeAt(i)] = i;
}

function bytesToBase64(bytes, urlSafe = false) {
    let output = "";
    const len = bytes.length;
    for (let i = 0; i < len; i += 3) {
        const b0 = bytes[i];
        const b1 = i + 1 < len ? bytes[i + 1] : 0;
        const b2 = i + 2 < len ? bytes[i + 2] : 0;

        const triple = (b0 << 16) | (b1 << 8) | b2;

        output += B64_CHARS.charAt((triple >> 18) & 63);
        output += B64_CHARS.charAt((triple >> 12) & 63);
        output += i + 1 < len ? B64_CHARS.charAt((triple >> 6) & 63) : (urlSafe ? "" : "=");
        output += i + 2 < len ? B64_CHARS.charAt(triple & 63) : (urlSafe ? "" : "=");
    }
    if (urlSafe) {
        output = output.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    }
    return output;
}

function base64ToBytes(str, urlSafe = false) {
    let clean = String(str || "").trim().replace(/\s+/g, "");
    if (urlSafe || clean.includes("-") || clean.includes("_")) {
        clean = clean.replace(/-/g, "+").replace(/_/g, "/");
        while (clean.length % 4 !== 0) {
            clean += "=";
        }
    }
    const len = clean.length;
    if (len % 4 !== 0) {
        throw new Error("Invalid Base64 string length");
    }
    let placeHolders = 0;
    if (clean.charAt(len - 1) === "=") placeHolders++;
    if (clean.charAt(len - 2) === "=") placeHolders++;

    const byteLen = (len * 3) / 4 - placeHolders;
    const bytes = new Uint8Array(byteLen);

    let cur = 0;
    for (let i = 0; i < len; i += 4) {
        const c0 = clean.charCodeAt(i);
        const c1 = clean.charCodeAt(i + 1);
        const c2 = clean.charCodeAt(i + 2);
        const c3 = clean.charCodeAt(i + 3);

        const v0 = B64_LOOKUP[c0];
        const v1 = B64_LOOKUP[c1];
        const v2 = c2 === 61 ? 0 : B64_LOOKUP[c2];
        const v3 = c3 === 61 ? 0 : B64_LOOKUP[c3];

        if (v0 === undefined || v1 === undefined || (c2 !== 61 && v2 === undefined) || (c3 !== 61 && v3 === undefined)) {
            throw new Error("Invalid Base64 character");
        }

        const triple = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3;
        bytes[cur++] = (triple >> 16) & 255;
        if (c2 !== 61) bytes[cur++] = (triple >> 8) & 255;
        if (c3 !== 61) bytes[cur++] = triple & 255;
    }
    return bytes;
}

// ─── 1. Generators ────────────────────────────────────────────────────────────

function generateUuid(options = {}) {
    const uppercase = Boolean(options.uppercase);
    const hyphens = options.hyphens !== false;
    const quantity = Math.max(1, Math.min(50, Number(options.quantity) || 1));

    const version = String(options.version ?? "4") === "7" ? 7 : 4;

    const hex = () => Math.floor(Math.random() * 16).toString(16);
    // v7 (RFC 9562): 48-bit Unix milliseconds first, so the IDs sort by creation.
    const createV7 = () => {
        const random = count => Array.from({ length: count }, hex).join("");
        const variant = (8 + Math.floor(Math.random() * 4)).toString(16);
        const raw = Date.now().toString(16).padStart(12, "0").slice(-12) + "7" + random(3) + variant + random(15);
        const formatted = hyphens
            ? `${raw.slice(0, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}-${raw.slice(16, 20)}-${raw.slice(20)}`
            : raw;
        return uppercase ? formatted.toUpperCase() : formatted.toLowerCase();
    };
    const createOne = () => {
        if (version === 7)
            return createV7();
        let pattern = hyphens ? "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx" : "xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx";
        let res = pattern.replace(/[xy]/g, c => {
            const r = Math.floor(Math.random() * 16);
            const v = c === "x" ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
        return uppercase ? res.toUpperCase() : res.toLowerCase();
    };

    if (quantity === 1) {
        return { output: createOne() };
    }
    const list = [];
    for (let i = 0; i < quantity; i++) {
        list.push(createOne());
    }
    return { output: list.join("\n"), meta: { count: quantity } };
}

function generatePassword(options = {}) {
    const length = Math.max(4, Math.min(128, Number(options.length) || 20));
    const uppercase = options.uppercase !== false;
    const lowercase = options.lowercase !== false;
    const numbers = options.numbers !== false;
    const symbols = options.symbols !== false;
    const avoidAmbiguous = options.avoidAmbiguous !== false;
    const quantity = Math.max(1, Math.min(50, Number(options.quantity) || 1));

    let upperChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    let lowerChars = "abcdefghijklmnopqrstuvwxyz";
    let numberChars = "0123456789";
    let symbolChars = "!@#$%^&*()_+-=[]{}|;:,.<>?";

    if (avoidAmbiguous) {
        upperChars = upperChars.replace(/[IO]/g, "");
        lowerChars = lowerChars.replace(/[lo]/g, "");
        numberChars = numberChars.replace(/[01]/g, "");
        symbolChars = symbolChars.replace(/[|`'"]/g, "");
    }

    let pool = "";
    const guaranteed = [];

    if (uppercase) {
        pool += upperChars;
        guaranteed.push(upperChars[Math.floor(Math.random() * upperChars.length)]);
    }
    if (lowercase) {
        pool += lowerChars;
        guaranteed.push(lowerChars[Math.floor(Math.random() * lowerChars.length)]);
    }
    if (numbers) {
        pool += numberChars;
        guaranteed.push(numberChars[Math.floor(Math.random() * numberChars.length)]);
    }
    if (symbols) {
        pool += symbolChars;
        guaranteed.push(symbolChars[Math.floor(Math.random() * symbolChars.length)]);
    }

    if (pool.length === 0) {
        pool = lowerChars;
        guaranteed.push(lowerChars[0]);
    }

    const createOne = () => {
        const chars = [...guaranteed];
        while (chars.length < length) {
            chars.push(pool[Math.floor(Math.random() * pool.length)]);
        }
        // Shuffle
        for (let i = chars.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const temp = chars[i];
            chars[i] = chars[j];
            chars[j] = temp;
        }
        return chars.join("");
    };

    if (quantity === 1) {
        return { output: createOne() };
    }
    const list = [];
    for (let i = 0; i < quantity; i++) {
        list.push(createOne());
    }
    return { output: list.join("\n"), meta: { count: quantity } };
}

const LOREM_WORDS = [
    "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
    "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
    "magna", "aliqua", "ut", "enim", "ad", "minim", "veniam", "quis", "nostrud",
    "exercitation", "ullamco", "laboris", "nisi", "ut", "aliquip", "ex", "ea", "commodo",
    "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate", "velit",
    "esse", "cillum", "dolore", "eu", "fugiat", "nulla", "pariatur", "excepteur", "sint",
    "occaecat", "cupidatat", "non", "proident", "sunt", "in", "culpa", "qui", "officia",
    "deserunt", "mollit", "anim", "id", "est", "laborum", "at", "vero", "eos", "accusamus",
    "iusto", "odio", "dignissimos", "ducimus", "blanditiis", "praesentium", "voluptatum",
    "deleniti", "atque", "corrupti", "quos", "dolores", "quas", "molestias", "excepturi",
    "sint", "obcaecati", "cupiditate", "provident", "similique", "mollitia", "animi",
    "nobis", "soluta", "nobis", "eleifend", "option", "congue", "nihil", "imperdiet"
];

function generateLorem(options = {}) {
    const unit = options.unit || "paragraphs"; // paragraphs, sentences, words
    const count = Math.max(1, Math.min(100, Number(options.count) || (unit === "paragraphs" ? 1 : (unit === "sentences" ? 3 : 20))));
    const startWithLorem = options.startWithLorem !== false;

    const randomWord = () => LOREM_WORDS[Math.floor(Math.random() * LOREM_WORDS.length)];

    const createSentence = (minWords = 6, maxWords = 14, forcedStart = null) => {
        const numWords = Math.floor(Math.random() * (maxWords - minWords + 1)) + minWords;
        const words = [];
        if (forcedStart) {
            words.push(...forcedStart.split(" "));
        }
        while (words.length < numWords) {
            words.push(randomWord());
        }
        let sentence = words.join(" ");
        sentence = sentence.charAt(0).toUpperCase() + sentence.slice(1) + ".";
        return sentence;
    };

    const createParagraph = (minSentences = 3, maxSentences = 6, isFirst = false) => {
        const numSentences = Math.floor(Math.random() * (maxSentences - minSentences + 1)) + minSentences;
        const sentences = [];
        for (let i = 0; i < numSentences; i++) {
            if (isFirst && i === 0 && startWithLorem) {
                sentences.push(createSentence(8, 14, "lorem ipsum dolor sit amet consectetur adipiscing elit"));
            } else {
                sentences.push(createSentence());
            }
        }
        return sentences.join(" ");
    };

    if (unit === "words") {
        const words = [];
        if (startWithLorem) {
            const prefix = ["lorem", "ipsum", "dolor", "sit", "amet"];
            words.push(...prefix.slice(0, Math.min(count, prefix.length)));
        }
        while (words.length < count) {
            words.push(randomWord());
        }
        return { output: words.join(" "), meta: { words: words.length } };
    }

    if (unit === "sentences") {
        const sentences = [];
        for (let i = 0; i < count; i++) {
            if (i === 0 && startWithLorem) {
                sentences.push(createSentence(8, 14, "lorem ipsum dolor sit amet consectetur adipiscing elit"));
            } else {
                sentences.push(createSentence());
            }
        }
        return { output: sentences.join(" "), meta: { sentences: count } };
    }

    // paragraphs
    const paragraphs = [];
    for (let i = 0; i < count; i++) {
        paragraphs.push(createParagraph(3, 6, i === 0));
    }
    return { output: paragraphs.join("\n\n"), meta: { paragraphs: count } };
}

// ─── 2. Encoders & Decoders ──────────────────────────────────────────────────

function toolBase64(input = "", options = {}) {
    const text = String(input);
    const mode = options.mode || "encode"; // encode, decode
    const urlSafe = Boolean(options.urlSafe);

    if (text.length === 0) {
        return { output: "" };
    }

    try {
        if (mode === "decode") {
            const bytes = base64ToBytes(text, urlSafe);
            const decoded = utf8Decode(bytes);
            return { output: decoded, meta: { bytes: bytes.length } };
        } else {
            const bytes = utf8Encode(text);
            const encoded = bytesToBase64(bytes, urlSafe);
            return { output: encoded, meta: { bytes: bytes.length } };
        }
    } catch (err) {
        return { output: "", error: err.message || "Failed to process Base64" };
    }
}

function toolUrlEncode(input = "", options = {}) {
    const text = String(input);
    const mode = options.mode || "encode";
    const component = options.component !== false;

    if (text.length === 0) {
        return { output: "" };
    }

    try {
        if (mode === "decode") {
            return { output: component ? decodeURIComponent(text) : decodeURI(text) };
        } else {
            return { output: component ? encodeURIComponent(text) : encodeURI(text) };
        }
    } catch (err) {
        return { output: "", error: err.message || "Invalid URL encoding sequence" };
    }
}

function toolHtmlEntities(input = "", options = {}) {
    const text = String(input);
    const mode = options.mode || "encode";

    if (text.length === 0) {
        return { output: "" };
    }

    if (mode === "decode") {
        const entities = {
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&copy;": "©",
            "&reg;": "®",
            "&euro;": "€",
            "&pound;": "£",
            "&yen;": "¥",
            "&cent;": "¢",
            "&mdash;": "—",
            "&ndash;": "–"
        };
        let decoded = text.replace(/&(?:[a-zA-Z]+|#\d+|#x[0-9a-fA-F]+);/g, match => {
            if (entities[match]) return entities[match];
            if (match.startsWith("&#x") || match.startsWith("&#X")) {
                const code = parseInt(match.slice(3, -1), 16);
                return isNaN(code) ? match : String.fromCodePoint(code);
            }
            if (match.startsWith("&#")) {
                const code = parseInt(match.slice(2, -1), 10);
                return isNaN(code) ? match : String.fromCodePoint(code);
            }
            return match;
        });
        return { output: decoded };
    } else {
        const map = {
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            "\"": "&quot;",
            "'": "&#39;"
        };
        const encoded = text.replace(/[&<>"']/g, c => map[c] || c);
        return { output: encoded };
    }
}

function toolJwtDecode(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0) {
        return { output: "" };
    }

    const parts = text.split(".");
    if (parts.length !== 3 && parts.length !== 2) {
        return { output: "", error: "Invalid JWT format. Expected header.payload.signature" };
    }

    try {
        const decodeSegment = (seg) => {
            const bytes = base64ToBytes(seg, true);
            const jsonStr = utf8Decode(bytes);
            return JSON.parse(jsonStr);
        };

        const header = decodeSegment(parts[0]);
        const payload = decodeSegment(parts[1]);

        let summary = "⚠️ Note: Signature is not verified (offline client-side decode)\n\n";

        // Claims info
        const claims = [];
        if (payload.iss) claims.push(`• Issuer (iss): ${payload.iss}`);
        if (payload.sub) claims.push(`• Subject (sub): ${payload.sub}`);
        if (payload.aud) claims.push(`• Audience (aud): ${Array.isArray(payload.aud) ? payload.aud.join(", ") : payload.aud}`);

        const now = Math.floor(Date.now() / 1000);
        if (payload.exp) {
            const expDate = new Date(payload.exp * 1000).toISOString().replace("T", " ").replace(/\.\d+Z$/, " UTC");
            const isExpired = payload.exp < now;
            const diffMin = Math.round(Math.abs(payload.exp - now) / 60);
            claims.push(`• Expires (exp): ${expDate} (${isExpired ? "EXPIRED " + diffMin + " min ago" : "Valid for " + diffMin + " min"})`);
        }
        if (payload.iat) {
            const iatDate = new Date(payload.iat * 1000).toISOString().replace("T", " ").replace(/\.\d+Z$/, " UTC");
            claims.push(`• Issued At (iat): ${iatDate}`);
        }
        if (payload.nbf) {
            const nbfDate = new Date(payload.nbf * 1000).toISOString().replace("T", " ").replace(/\.\d+Z$/, " UTC");
            claims.push(`• Not Before (nbf): ${nbfDate}`);
        }

        if (claims.length > 0) {
            summary += "── Key Claims ──\n" + claims.join("\n") + "\n\n";
        }

        summary += "── Header ──\n" + JSON.stringify(header, null, 2) + "\n\n";
        summary += "── Payload ──\n" + JSON.stringify(payload, null, 2);

        return {
            output: summary,
            meta: {
                header,
                payload,
                algorithm: header.alg,
                type: header.typ,
                expired: payload.exp ? payload.exp < now : null
            }
        };
    } catch (err) {
        return { output: "", error: "Failed to decode JWT: " + (err.message || "Invalid payload") };
    }
}

// ─── 3. Text Operations ───────────────────────────────────────────────────────

function splitWords(str) {
    if (!str) return [];
    return str
        .replace(/([a-z\d])([A-Z])/g, "$1 $2")
        .replace(/([A-Z]+)([A-Z][a-z\d]+)/g, "$1 $2")
        .replace(/[\W_]+/g, " ")
        .trim()
        .split(/\s+/)
        .filter(w => w.length > 0);
}

function toolCaseConvert(input = "", options = {}) {
    const text = String(input);
    const target = options.target || "camel"; // camel, pascal, snake, kebab, constant, title, upper, lower, dot

    if (text.length === 0) {
        return { output: "" };
    }

    const words = splitWords(text);
    if (words.length === 0) {
        return { output: "" };
    }

    let output = "";
    switch (target) {
    case "camel":
        output = words.map((w, idx) => idx === 0 ? w.toLowerCase() : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join("");
        break;
    case "pascal":
        output = words.map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join("");
        break;
    case "snake":
        output = words.map(w => w.toLowerCase()).join("_");
        break;
    case "kebab":
        output = words.map(w => w.toLowerCase()).join("-");
        break;
    case "constant":
        output = words.map(w => w.toUpperCase()).join("_");
        break;
    case "title":
        output = words.map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(" ");
        break;
    case "upper":
        output = text.toUpperCase();
        break;
    case "lower":
        output = text.toLowerCase();
        break;
    case "dot":
        output = words.map(w => w.toLowerCase()).join(".");
        break;
    default:
        output = words.join(" ");
    }

    return { output, meta: { wordsCount: words.length } };
}

function toolEscapeString(input = "", options = {}) {
    const text = String(input);
    const mode = options.mode || "json"; // json, regex, shell_single, shell_double, sql
    const action = options.action || "escape"; // escape, unescape

    if (text.length === 0) {
        return { output: "" };
    }

    if (action === "unescape") {
        try {
            if (mode === "json") {
                return { output: JSON.parse(`"${text.replace(/^"|"$/g, "")}"`) };
            }
            if (mode === "regex") {
                return { output: text.replace(/\\([.*+?^${}()|[\]\/\\])/g, "$1") };
            }
            if (mode === "shell_single") {
                return { output: text.replace(/'\\''/g, "'") };
            }
            return { output: text };
        } catch (err) {
            return { output: "", error: "Failed to unescape: " + err.message };
        }
    }

    let output = "";
    switch (mode) {
    case "json":
        output = JSON.stringify(text).slice(1, -1);
        break;
    case "regex":
        output = text.replace(/[.*+?^${}()|[\]\/\\]/g, "\\$&");
        break;
    case "shell_single":
        output = text.replace(/'/g, "'\\''");
        break;
    case "shell_double":
        output = text.replace(/["\\$`!]/g, "\\$&");
        break;
    case "sql":
        output = text.replace(/'/g, "''");
        break;
    default:
        output = text;
    }
    return { output };
}

function toolTextInspector(input = "", options = {}) {
    const text = String(input);
    const charsTotal = text.length;
    const charsNoSpaces = text.replace(/\s/g, "").length;
    const lines = text.length === 0 ? 0 : text.split(/\r\n|\r|\n/).length;
    const nonEmptyLines = text.length === 0 ? 0 : text.split(/\r\n|\r|\n/).filter(l => l.trim().length > 0).length;
    const words = text.trim().length === 0 ? 0 : text.trim().split(/\s+/).length;
    const sentences = text.trim().length === 0 ? 0 : (text.match(/[.!?]+(?:\s|$)/g) || []).length || (text.trim().length > 0 ? 1 : 0);
    const paragraphs = text.trim().length === 0 ? 0 : text.split(/\n\s*\n/).filter(p => p.trim().length > 0).length;
    const bytesUtf8 = utf8Encode(text).length;

    const readingTimeMin = Math.ceil(words / 200);
    const speakingTimeMin = Math.ceil(words / 130);

    const report = [
        `• Characters: ${charsTotal.toLocaleString()}`,
        `• Characters (no spaces): ${charsNoSpaces.toLocaleString()}`,
        `• Words: ${words.toLocaleString()}`,
        `• Lines: ${lines.toLocaleString()} (${nonEmptyLines.toLocaleString()} non-empty)`,
        `• Sentences: ${sentences.toLocaleString()}`,
        `• Paragraphs: ${paragraphs.toLocaleString()}`,
        `• UTF-8 Size: ${bytesUtf8.toLocaleString()} bytes`,
        `• Est. Reading Time: ~${readingTimeMin} min (200 wpm)`,
        `• Est. Speaking Time: ~${speakingTimeMin} min (130 wpm)`
    ].join("\n");

    return {
        output: report,
        meta: {
            characters: charsTotal,
            charactersNoSpaces: charsNoSpaces,
            words,
            lines,
            nonEmptyLines,
            sentences,
            paragraphs,
            bytesUtf8,
            readingTimeMin
        }
    };
}

function toolLineTools(input = "", options = {}) {
    const text = String(input);
    if (text.length === 0) return { output: "" };

    const operation = options.operation || "sort_az"; // sort_az, sort_za, sort_length_asc, sort_length_desc, dedupe, reverse, number, filter_empty, shuffle
    const caseSensitive = Boolean(options.caseSensitive);

    let hasTrailingNewline = text.endsWith("\n");
    let lines = text.split(/\r?\n/);
    if (hasTrailingNewline && lines[lines.length - 1] === "") {
        lines.pop();
    }

    switch (operation) {
    case "sort_az":
        lines.sort((a, b) => caseSensitive ? a.localeCompare(b) : a.localeCompare(b, undefined, { sensitivity: "accent" }));
        break;
    case "sort_za":
        lines.sort((a, b) => caseSensitive ? b.localeCompare(a) : b.localeCompare(a, undefined, { sensitivity: "accent" }));
        break;
    case "sort_length_asc":
        lines.sort((a, b) => a.length - b.length || (caseSensitive ? a.localeCompare(b) : a.localeCompare(b, undefined, { sensitivity: "accent" })));
        break;
    case "sort_length_desc":
        lines.sort((a, b) => b.length - a.length || (caseSensitive ? a.localeCompare(b) : a.localeCompare(b, undefined, { sensitivity: "accent" })));
        break;
    case "dedupe": {
        const seen = new Set();
        lines = lines.filter(line => {
            const key = caseSensitive ? line : line.toLowerCase();
            if (seen.has(key)) return false;
            seen.add(key);
            return true;
        });
        break;
    }
    case "reverse":
        lines.reverse();
        break;
    case "number": {
        const padLen = String(lines.length).length;
        lines = lines.map((line, idx) => `${String(idx + 1).padStart(padLen, " ")}. ${line}`);
        break;
    }
    case "filter_empty":
        lines = lines.filter(l => l.trim().length > 0);
        break;
    case "shuffle":
        for (let i = lines.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const temp = lines[i];
            lines[i] = lines[j];
            lines[j] = temp;
        }
        break;
    }

    const output = lines.join("\n") + (hasTrailingNewline ? "\n" : "");
    return { output, meta: { linesCount: lines.length } };
}

function toolWhitespace(input = "", options = {}) {
    const text = String(input);
    if (text.length === 0) return { output: "" };

    const operation = options.operation || "trim"; // trim, collapse, remove_blank, tabs_to_spaces, spaces_to_tabs, remove_all
    const tabSize = Math.max(1, Math.min(8, Number(options.tabSize) || 4));

    let output = "";
    switch (operation) {
    case "trim":
        output = text.split(/\r?\n/).map(l => l.trim()).join("\n");
        break;
    case "collapse":
        output = text.replace(/[^\S\r\n]+/g, " ");
        break;
    case "remove_blank":
        output = text.split(/\r?\n/).filter(l => l.trim().length > 0).join("\n");
        break;
    case "tabs_to_spaces":
        output = text.replace(/\t/g, " ".repeat(tabSize));
        break;
    case "spaces_to_tabs":
        output = text.replace(new RegExp(" ".repeat(tabSize), "g"), "\t");
        break;
    case "remove_all":
        output = text.replace(/\s+/g, "");
        break;
    default:
        output = text.trim();
    }

    return { output };
}

function toolRegexTester(input = "", options = {}) {
    const text = String(input);
    const pattern = String(options.pattern || "");
    const flags = String(options.flags !== undefined ? options.flags : "g");

    if (pattern.length === 0) {
        return { output: "Enter a regular expression pattern to test." };
    }

    try {
        const regex = new RegExp(pattern, flags.includes("g") ? flags : flags + "g");
        const matches = [];
        let match;

        let safety = 0;
        while ((match = regex.exec(text)) !== null && safety++ < 1000) {
            matches.push({
                index: match.index,
                length: match[0].length,
                value: match[0],
                groups: match.slice(1)
            });
            if (match[0].length === 0) {
                regex.lastIndex++;
            }
        }

        if (matches.length === 0) {
            return { output: "No matches found.", meta: { count: 0 } };
        }

        const lines = [`Found ${matches.length} match${matches.length === 1 ? "" : "es"}:\n`];
        matches.forEach((m, idx) => {
            lines.push(`[#${idx + 1}] at index ${m.index} (len ${m.length}): "${m.value}"`);
            if (m.groups && m.groups.length > 0) {
                m.groups.forEach((g, gIdx) => {
                    lines.push(`    Group ${gIdx + 1}: "${g !== undefined ? g : ""}"`);
                });
            }
        });

        return { output: lines.join("\n"), meta: { count: matches.length, matches } };
    } catch (err) {
        return { output: "", error: "Regex error: " + err.message };
    }
}

function toolSlugify(input = "", options = {}) {
    const text = String(input);
    const separator = options.separator || "-";
    const lowercase = options.lowercase !== false;

    if (text.length === 0) return { output: "" };

    let slug = text.normalize("NFD").replace(/[\u0300-\u036f]/g, ""); // remove accents
    if (lowercase) {
        slug = slug.toLowerCase();
    }
    slug = slug.replace(/[^\w\s-]/g, "") // remove non-word chars
               .trim()
               .replace(/[-\s]+/g, separator) // replace spaces/hyphens with separator
               .replace(new RegExp(`^\\${separator}+|\\${separator}+$`, "g"), ""); // trim separator

    return { output: slug };
}

function toolTextDiff(input = "", options = {}) {
    let original = "";
    let modified = "";

    if (options.original !== undefined && options.modified !== undefined) {
        original = String(options.original);
        modified = String(options.modified);
    } else {
        const parts = String(input).split(/\n===DIFF_SPLIT===\n/);
        if (parts.length === 2) {
            original = parts[0];
            modified = parts[1];
        } else {
            return { output: "Provide original and modified text separated by `\\n===DIFF_SPLIT===\\n` or via options." };
        }
    }

    const origLines = original.split(/\r?\n/);
    const modLines = modified.split(/\r?\n/);

    // LCS-based line diff
    const n = origLines.length;
    const m = modLines.length;

    // dp matrix for LCS
    const dp = Array.from({ length: n + 1 }, () => new Int32Array(m + 1));
    for (let i = 0; i < n; i++) {
        for (let j = 0; j < m; j++) {
            if (origLines[i] === modLines[j]) {
                dp[i + 1][j + 1] = dp[i][j] + 1;
            } else {
                dp[i + 1][j + 1] = Math.max(dp[i + 1][j], dp[i][j + 1]);
            }
        }
    }

    // Backtrack to build diff
    let i = n;
    let j = m;
    const diff = [];
    let addedCount = 0;
    let removedCount = 0;

    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && origLines[i - 1] === modLines[j - 1]) {
            diff.push({ type: "same", text: "  " + origLines[i - 1] });
            i--;
            j--;
        } else if (j > 0 && (i === 0 || dp[i][j - 1] >= dp[i - 1][j])) {
            diff.push({ type: "add", text: "+ " + modLines[j - 1] });
            addedCount++;
            j--;
        } else if (i > 0 && (j === 0 || dp[i][j - 1] < dp[i - 1][j])) {
            diff.push({ type: "del", text: "- " + origLines[i - 1] });
            removedCount++;
            i--;
        }
    }

    diff.reverse();

    const output = [
        `--- Original (${n} lines)`,
        `+++ Modified (${m} lines)`,
        `@@ -${removedCount} +${addedCount} @@`,
        ...diff.map(d => d.text)
    ].join("\n");

    return {
        output,
        meta: {
            additions: addedCount,
            deletions: removedCount,
            identical: addedCount === 0 && removedCount === 0
        }
    };
}

// ─── 4. Converters & Formatters ───────────────────────────────────────────────

function toolNumberBase(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0) return { output: "" };

    let clean = text.replace(/_/g, "");
    let base = options.fromBase || "auto";

    let numVal = null;
    let hasBigInt = typeof BigInt !== "undefined";

    try {
        if (base === "auto") {
            if (/^0b[01]+$/i.test(clean)) {
                numVal = hasBigInt ? BigInt(clean) : parseInt(clean.slice(2), 2);
            } else if (/^0o[0-7]+$/i.test(clean)) {
                numVal = hasBigInt ? BigInt(clean) : parseInt(clean.slice(2), 8);
            } else if (/^0x[0-9a-f]+$/i.test(clean)) {
                numVal = hasBigInt ? BigInt(clean) : parseInt(clean.slice(2), 16);
            } else if (/^-?\d+$/.test(clean)) {
                numVal = hasBigInt ? BigInt(clean) : parseInt(clean, 10);
            } else if (/^[01]+$/.test(clean) && clean.length > 8) {
                numVal = hasBigInt ? BigInt("0b" + clean) : parseInt(clean, 2);
            } else if (/^[0-9a-f]+$/i.test(clean) && /[a-f]/i.test(clean)) {
                numVal = hasBigInt ? BigInt("0x" + clean) : parseInt(clean, 16);
            } else {
                numVal = hasBigInt ? BigInt(clean) : parseInt(clean, 10);
            }
        } else {
            const radix = parseInt(base, 10);
            if (radix === 2) numVal = hasBigInt ? BigInt("0b" + clean.replace(/^0b/i, "")) : parseInt(clean.replace(/^0b/i, ""), 2);
            else if (radix === 8) numVal = hasBigInt ? BigInt("0o" + clean.replace(/^0o/i, "")) : parseInt(clean.replace(/^0o/i, ""), 8);
            else if (radix === 16) numVal = hasBigInt ? BigInt("0x" + clean.replace(/^0x/i, "")) : parseInt(clean.replace(/^0x/i, ""), 16);
            else numVal = hasBigInt ? BigInt(clean) : parseInt(clean, 10);
        }
    } catch (err) {
        return { output: "", error: "Invalid number format: " + text };
    }

    if (numVal === null || (typeof numVal === "number" && isNaN(numVal))) {
        return { output: "", error: "Invalid number format: " + text };
    }

    const isNegative = typeof numVal === "bigint" ? numVal < BigInt(0) : numVal < 0;
    const absVal = isNegative ? (typeof numVal === "bigint" ? -numVal : Math.abs(numVal)) : numVal;

    const binStr = (isNegative ? "-" : "") + absVal.toString(2);
    const octStr = (isNegative ? "-" : "") + absVal.toString(8);
    const decStr = numVal.toString(10);
    const hexStr = (isNegative ? "-" : "") + absVal.toString(16).toUpperCase();

    // Grouping for readability
    const binGrouped = binStr.replace(/\B(?=(\d{4})+(?!\d))/g, " ");
    const hexGrouped = hexStr.replace(/\B(?=([0-9A-F]{4})+(?![0-9A-F]))/g, " ");

    const output = [
        `• Decimal (10):      ${decStr}`,
        `• Hexadecimal (16):  0x${hexGrouped}`,
        `• Binary (2):        0b${binGrouped}`,
        `• Octal (8):         0o${octStr}`
    ].join("\n");

    return {
        output,
        meta: {
            decimal: decStr,
            hex: "0x" + hexStr,
            binary: "0b" + binStr,
            octal: "0o" + octStr
        }
    };
}

function toolUnixTimestamp(input = "", options = {}) {
    let text = String(input).trim();
    let date = null;

    if (text.length === 0 || text.toLowerCase() === "now") {
        date = new Date();
    } else if (/^-?\d+$/.test(text)) {
        const num = Number(text);
        // If digits <= 11, it's seconds, otherwise milliseconds
        if (text.length <= 11) {
            date = new Date(num * 1000);
        } else {
            date = new Date(num);
        }
    } else {
        date = new Date(text);
    }

    if (!date || isNaN(date.getTime())) {
        return { output: "", error: "Invalid date / timestamp format: " + text };
    }

    const unixSec = Math.floor(date.getTime() / 1000);
    const unixMs = date.getTime();
    const isoUtc = date.toISOString();
    const utcString = date.toUTCString();

    const pad = n => String(n).padStart(2, "0");
    const localStr = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;

    const now = Date.now();
    const diffSec = Math.round((unixMs - now) / 1000);
    let relative = "";
    if (Math.abs(diffSec) < 60) {
        relative = diffSec >= 0 ? "in a few seconds" : "a few seconds ago";
    } else if (Math.abs(diffSec) < 3600) {
        const min = Math.round(Math.abs(diffSec) / 60);
        relative = diffSec >= 0 ? `in ${min} min` : `${min} min ago`;
    } else if (Math.abs(diffSec) < 86400) {
        const hrs = Math.round(Math.abs(diffSec) / 3600);
        relative = diffSec >= 0 ? `in ${hrs} hours` : `${hrs} hours ago`;
    } else {
        const days = Math.round(Math.abs(diffSec) / 86400);
        relative = diffSec >= 0 ? `in ${days} days` : `${days} days ago`;
    }

    const output = [
        `• Unix (seconds):    ${unixSec}`,
        `• Unix (millis):     ${unixMs}`,
        `• ISO 8601 (UTC):    ${isoUtc}`,
        `• Local Time:        ${localStr}`,
        `• Relative:          ${relative}`,
        `• UTC Format:        ${utcString}`
    ].join("\n");

    return {
        output,
        meta: {
            unixSeconds: unixSec,
            unixMilliseconds: unixMs,
            iso: isoUtc,
            local: localStr,
            relative
        }
    };
}

function parseColor(str) {
    const text = String(str || "").trim().toLowerCase();
    if (!text) return null;

    // Hex #RGB, #RGBA, #RRGGBB, #RRGGBBAA
    const hexMatch = text.match(/^#?([0-9a-f]{3,8})$/);
    if (hexMatch) {
        let hex = hexMatch[1];
        let r = 0, g = 0, b = 0, a = 1;
        if (hex.length === 3) {
            r = parseInt(hex[0] + hex[0], 16);
            g = parseInt(hex[1] + hex[1], 16);
            b = parseInt(hex[2] + hex[2], 16);
        } else if (hex.length === 4) {
            r = parseInt(hex[0] + hex[0], 16);
            g = parseInt(hex[1] + hex[1], 16);
            b = parseInt(hex[2] + hex[2], 16);
            a = parseInt(hex[3] + hex[3], 16) / 255;
        } else if (hex.length === 6) {
            r = parseInt(hex.slice(0, 2), 16);
            g = parseInt(hex.slice(2, 4), 16);
            b = parseInt(hex.slice(4, 6), 16);
        } else if (hex.length === 8) {
            r = parseInt(hex.slice(0, 2), 16);
            g = parseInt(hex.slice(2, 4), 16);
            b = parseInt(hex.slice(4, 6), 16);
            a = parseInt(hex.slice(6, 8), 16) / 255;
        } else {
            return null;
        }
        return { r, g, b, a };
    }

    // rgb(r, g, b) or rgba(r, g, b, a)
    const rgbMatch = text.match(/^rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$/);
    if (rgbMatch) {
        return {
            r: Math.max(0, Math.min(255, parseInt(rgbMatch[1], 10))),
            g: Math.max(0, Math.min(255, parseInt(rgbMatch[2], 10))),
            b: Math.max(0, Math.min(255, parseInt(rgbMatch[3], 10))),
            a: rgbMatch[4] !== undefined ? Math.max(0, Math.min(1, parseFloat(rgbMatch[4]))) : 1
        };
    }

    // hsl(h, s%, l%) or hsla(h, s%, l%, a)
    const hslMatch = text.match(/^hsla?\s*\(\s*(\d+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$/);
    if (hslMatch) {
        const h = parseInt(hslMatch[1], 10) % 360;
        const s = parseFloat(hslMatch[2]) / 100;
        const l = parseFloat(hslMatch[3]) / 100;
        const a = hslMatch[4] !== undefined ? parseFloat(hslMatch[4]) : 1;

        const c = (1 - Math.abs(2 * l - 1)) * s;
        const x = c * (1 - Math.abs((h / 60) % 2 - 1));
        const m = l - c / 2;
        let r1 = 0, g1 = 0, b1 = 0;
        if (h < 60) { r1 = c; g1 = x; }
        else if (h < 120) { r1 = x; g1 = c; }
        else if (h < 180) { g1 = c; b1 = x; }
        else if (h < 240) { g1 = x; b1 = c; }
        else if (h < 300) { r1 = x; b1 = c; }
        else { r1 = c; b1 = x; }

        return {
            r: Math.round((r1 + m) * 255),
            g: Math.round((g1 + m) * 255),
            b: Math.round((b1 + m) * 255),
            a: Math.max(0, Math.min(1, a))
        };
    }

    return null;
}

function toolColorConverter(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0) return { output: "" };

    const color = parseColor(text);
    if (!color) {
        return { output: "", error: "Could not parse color: " + text };
    }

    const { r, g, b, a } = color;

    // Hex
    const toHex2 = n => n.toString(16).padStart(2, "0").toUpperCase();
    const hex = `#${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
    const hexAlpha = a < 1 ? `${hex}${toHex2(Math.round(a * 255))}` : hex;

    // RGB & RGBA
    const rgbStr = `rgb(${r}, ${g}, ${b})`;
    const rgbaStr = `rgba(${r}, ${g}, ${b}, ${Math.round(a * 100) / 100})`;

    // HSL
    const rNorm = r / 255;
    const gNorm = g / 255;
    const bNorm = b / 255;
    const max = Math.max(rNorm, gNorm, bNorm);
    const min = Math.min(rNorm, gNorm, bNorm);
    const delta = max - min;

    let h = 0;
    let s = 0;
    const l = (max + min) / 2;

    if (delta !== 0) {
        s = l > 0.5 ? delta / (2 - max - min) : delta / (max + min);
        if (max === rNorm) h = ((gNorm - bNorm) / delta + (gNorm < bNorm ? 6 : 0)) * 60;
        else if (max === gNorm) h = ((bNorm - rNorm) / delta + 2) * 60;
        else h = ((rNorm - gNorm) / delta + 4) * 60;
    }

    const hDeg = Math.round(h);
    const sPct = Math.round(s * 100);
    const lPct = Math.round(l * 100);

    const hslStr = `hsl(${hDeg}, ${sPct}%, ${lPct}%)`;
    const hslaStr = `hsla(${hDeg}, ${sPct}%, ${lPct}%, ${Math.round(a * 100) / 100})`;

    const output = [
        `• Hex:   ${hexAlpha}`,
        `• RGB:   ${a < 1 ? rgbaStr : rgbStr}`,
        `• HSL:   ${a < 1 ? hslaStr : hslStr}`,
        `• Alpha: ${Math.round(a * 100)}%`
    ].join("\n");

    return {
        output,
        meta: {
            hex: hexAlpha,
            rgb: rgbStr,
            rgba: rgbaStr,
            hsl: hslStr,
            hsla: hslaStr,
            r, g, b, a
        }
    };
}

function toolJsonFormatter(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0) return { output: "" };

    const indentMode = options.indent || "2"; // 2, 4, tab, minified
    const sortKeys = Boolean(options.sortKeys);

    let space = 2;
    if (indentMode === "4") space = 4;
    else if (indentMode === "tab") space = "\t";
    else if (indentMode === "minified") space = 0;

    try {
        let parsed = JSON.parse(text);

        if (sortKeys && typeof parsed === "object" && parsed !== null) {
            const sortObject = obj => {
                if (Array.isArray(obj)) return obj.map(sortObject);
                if (obj !== null && typeof obj === "object") {
                    return Object.keys(obj).sort().reduce((acc, k) => {
                        acc[k] = sortObject(obj[k]);
                        return acc;
                    }, {});
                }
                return obj;
            };
            parsed = sortObject(parsed);
        }

        const formatted = space === 0 ? JSON.stringify(parsed) : JSON.stringify(parsed, null, space);
        return {
            output: formatted,
            meta: {
                type: Array.isArray(parsed) ? "array" : typeof parsed,
                entries: typeof parsed === "object" && parsed !== null ? Object.keys(parsed).length : 1
            }
        };
    } catch (err) {
        // Detailed syntax error position locating
        let line = 1;
        let col = 1;
        const msg = err.message || "Invalid JSON";

        const posMatch = msg.match(/position (\d+)/i);
        if (posMatch) {
            const pos = parseInt(posMatch[1], 10);
            const sub = text.slice(0, pos);
            const lines = sub.split("\n");
            line = lines.length;
            col = lines[lines.length - 1].length + 1;
        }

        return {
            output: "",
            error: `JSON Syntax Error (Line ${line}, Col ${col}): ${msg}`,
            meta: { line, col }
        };
    }
}

// ─── Master Tool Runner ───────────────────────────────────────────────────────

// ─── 5. Identifiers ───────────────────────────────────────────────────────────

// NanoID's own URL-safe alphabet (64 symbols) and Crockford's base32 for ULID.
const NANOID_ALPHABET = "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict";
const ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

function generateUlid(time = Date.now()) {
    let timePart = "";
    let remaining = Math.max(0, Math.floor(time));
    for (let i = 0; i < 10; i++) {
        timePart = ULID_ALPHABET[remaining % 32] + timePart;
        remaining = Math.floor(remaining / 32);
    }
    let randomPart = "";
    for (let i = 0; i < 16; i++)
        randomPart += ULID_ALPHABET[Math.floor(Math.random() * 32)];
    return timePart + randomPart;
}

function generateIds(options = {}) {
    const kind = options.kind === "ulid" ? "ulid" : "nanoid";
    const size = Math.max(4, Math.min(64, Number(options.size) || 21));
    const quantity = Math.max(1, Math.min(50, Number(options.quantity) || 1));
    const createOne = () => {
        if (kind === "ulid")
            return generateUlid();
        let id = "";
        for (let i = 0; i < size; i++)
            id += NANOID_ALPHABET[Math.floor(Math.random() * NANOID_ALPHABET.length)];
        return id;
    };
    const list = [];
    for (let i = 0; i < quantity; i++)
        list.push(createOne());
    return quantity === 1 ? { output: list[0] } : { output: list.join("\n"), meta: { count: quantity } };
}

// ─── 6. Hashes ────────────────────────────────────────────────────────────────
//
// Plain JavaScript on purpose: the QML engine has no crypto API beyond MD5, and
// the Node test runner checks every digest against published test vectors.

function bytesToHex(bytes) {
    let out = "";
    for (let i = 0; i < bytes.length; i++)
        out += (bytes[i] & 0xff).toString(16).padStart(2, "0");
    return out;
}

// Merkle–Damgård padding: MD5 stores the bit length little-endian, SHA big-endian.
function padMessage(bytes, littleEndian) {
    const length = bytes.length;
    const paddedLength = Math.ceil((length + 9) / 64) * 64;
    const data = new Uint8Array(paddedLength);
    data.set(bytes);
    data[length] = 0x80;
    const low = (length * 8) >>> 0;
    const high = Math.floor(length / 0x20000000) >>> 0;
    for (let i = 0; i < 4; i++) {
        if (littleEndian) {
            data[paddedLength - 8 + i] = (low >>> (8 * i)) & 0xff;
            data[paddedLength - 4 + i] = (high >>> (8 * i)) & 0xff;
        } else {
            data[paddedLength - 1 - i] = (low >>> (8 * i)) & 0xff;
            data[paddedLength - 5 - i] = (high >>> (8 * i)) & 0xff;
        }
    }
    return data;
}

function readBigEndianWords(data, offset, target, count) {
    for (let i = 0; i < count; i++) {
        const j = offset + i * 4;
        target[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | data[j + 3];
    }
}

function wordsToBytesBigEndian(words) {
    const out = new Uint8Array(words.length * 4);
    for (let index = 0; index < words.length; index++) {
        for (let i = 0; i < 4; i++)
            out[index * 4 + i] = (words[index] >>> (24 - 8 * i)) & 0xff;
    }
    return out;
}

const MD5_SHIFTS = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
const MD5_CONSTANTS = Array.from({ length: 64 }, (unused, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0);

function md5Bytes(bytes) {
    const data = padMessage(bytes, true);
    let a0 = 0x67452301;
    let b0 = 0xefcdab89 | 0;
    let c0 = 0x98badcfe | 0;
    let d0 = 0x10325476;
    const words = new Int32Array(16);
    for (let offset = 0; offset < data.length; offset += 64) {
        for (let i = 0; i < 16; i++) {
            const j = offset + i * 4;
            words[i] = data[j] | (data[j + 1] << 8) | (data[j + 2] << 16) | (data[j + 3] << 24);
        }
        let a = a0;
        let b = b0;
        let c = c0;
        let d = d0;
        for (let i = 0; i < 64; i++) {
            let f;
            let g;
            if (i < 16) {
                f = (b & c) | (~b & d);
                g = i;
            } else if (i < 32) {
                f = (d & b) | (~d & c);
                g = (5 * i + 1) % 16;
            } else if (i < 48) {
                f = b ^ c ^ d;
                g = (3 * i + 5) % 16;
            } else {
                f = c ^ (b | ~d);
                g = (7 * i) % 16;
            }
            const sum = (a + f + MD5_CONSTANTS[i] + words[g]) | 0;
            a = d;
            d = c;
            c = b;
            b = (b + ((sum << MD5_SHIFTS[i]) | (sum >>> (32 - MD5_SHIFTS[i])))) | 0;
        }
        a0 = (a0 + a) | 0;
        b0 = (b0 + b) | 0;
        c0 = (c0 + c) | 0;
        d0 = (d0 + d) | 0;
    }
    const out = new Uint8Array(16);
    const state = [a0, b0, c0, d0];
    for (let index = 0; index < 4; index++) {
        for (let i = 0; i < 4; i++)
            out[index * 4 + i] = (state[index] >>> (8 * i)) & 0xff;
    }
    return out;
}

function sha1Bytes(bytes) {
    const data = padMessage(bytes, false);
    const h = [0x67452301, 0xefcdab89 | 0, 0x98badcfe | 0, 0x10325476, 0xc3d2e1f0 | 0];
    const w = new Int32Array(80);
    for (let offset = 0; offset < data.length; offset += 64) {
        readBigEndianWords(data, offset, w, 16);
        for (let i = 16; i < 80; i++) {
            const v = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
            w[i] = (v << 1) | (v >>> 31);
        }
        let a = h[0];
        let b = h[1];
        let c = h[2];
        let d = h[3];
        let e = h[4];
        for (let i = 0; i < 80; i++) {
            let f;
            let k;
            if (i < 20) {
                f = (b & c) | (~b & d);
                k = 0x5a827999;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ed9eba1;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8f1bbcdc | 0;
            } else {
                f = b ^ c ^ d;
                k = 0xca62c1d6 | 0;
            }
            const temp = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) | 0;
            e = d;
            d = c;
            c = (b << 30) | (b >>> 2);
            b = a;
            a = temp;
        }
        h[0] = (h[0] + a) | 0;
        h[1] = (h[1] + b) | 0;
        h[2] = (h[2] + c) | 0;
        h[3] = (h[3] + d) | 0;
        h[4] = (h[4] + e) | 0;
    }
    return wordsToBytesBigEndian(h);
}

// FIPS 180-4 derives SHA-256's constants from the first primes: the first 32
// bits of the fractional parts of their cube roots (K) and square roots (H).
const SHA256_PRIMES = (() => {
    const primes = [];
    for (let n = 2; primes.length < 64; n++) {
        if (primes.every(p => n % p !== 0))
            primes.push(n);
    }
    return primes;
})();
const fractionalWord = value => Math.floor((value - Math.floor(value)) * 4294967296) | 0;
const SHA256_K = SHA256_PRIMES.map(p => fractionalWord(Math.cbrt(p)));
const SHA256_INIT = SHA256_PRIMES.slice(0, 8).map(p => fractionalWord(Math.sqrt(p)));

function sha256Bytes(bytes) {
    const data = padMessage(bytes, false);
    const h = SHA256_INIT.slice();
    const w = new Int32Array(64);
    const rotr = (x, n) => (x >>> n) | (x << (32 - n));
    for (let offset = 0; offset < data.length; offset += 64) {
        readBigEndianWords(data, offset, w, 16);
        for (let i = 16; i < 64; i++) {
            const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
            const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
        }
        let a = h[0];
        let b = h[1];
        let c = h[2];
        let d = h[3];
        let e = h[4];
        let f = h[5];
        let g = h[6];
        let hh = h[7];
        for (let i = 0; i < 64; i++) {
            const t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + SHA256_K[i] + w[i]) | 0;
            const t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
            hh = g;
            g = f;
            f = e;
            e = (d + t1) | 0;
            d = c;
            c = b;
            b = a;
            a = (t1 + t2) | 0;
        }
        const round = [a, b, c, d, e, f, g, hh];
        for (let i = 0; i < 8; i++)
            h[i] = (h[i] + round[i]) | 0;
    }
    return wordsToBytesBigEndian(h);
}

const CRC32_TABLE = (() => {
    const table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++)
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        table[n] = c;
    }
    return table;
})();

function crc32(bytes) {
    let crc = -1;
    for (let i = 0; i < bytes.length; i++)
        crc = CRC32_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
    return (crc ^ -1) >>> 0;
}

function toolHashGenerator(input = "", options = {}) {
    const bytes = utf8Encode(String(input));
    const algorithm = String(options.algorithm || "all");
    const uppercase = Boolean(options.uppercase);
    const style = value => uppercase ? value.toUpperCase() : value;
    const digests = {
        md5: () => style(bytesToHex(md5Bytes(bytes))),
        sha1: () => style(bytesToHex(sha1Bytes(bytes))),
        sha256: () => style(bytesToHex(sha256Bytes(bytes))),
        crc32: () => style(crc32(bytes).toString(16).padStart(8, "0"))
    };
    if (algorithm !== "all") {
        if (!digests[algorithm])
            return { output: "", error: "Unknown algorithm: " + algorithm };
        const value = digests[algorithm]();
        const meta = {};
        meta[algorithm] = value;
        return { output: value, meta };
    }
    const labels = { md5: "MD5", sha1: "SHA-1", sha256: "SHA-256", crc32: "CRC32" };
    const meta = {};
    const lines = Object.keys(digests).map(key => {
        meta[key] = digests[key]();
        return `${labels[key].padEnd(8)} ${meta[key]}`;
    });
    return { output: lines.join("\n"), meta };
}

function toolHexText(input = "", options = {}) {
    const text = String(input);
    const separators = { space: " ", none: "", colon: ":" };
    const separator = separators[options.separator] !== undefined ? separators[options.separator] : " ";
    if (options.mode === "decode") {
        const clean = text.replace(/0x/gi, "").replace(/[\s:,-]/g, "");
        if (clean.length === 0)
            return { output: "" };
        if (!/^[0-9a-f]+$/i.test(clean))
            return { output: "", error: "The input contains characters that are not hexadecimal digits." };
        if (clean.length % 2 !== 0)
            return { output: "", error: "Hex input needs an even number of digits (two per byte)." };
        const bytes = new Uint8Array(clean.length / 2);
        for (let i = 0; i < clean.length; i += 2)
            bytes[i / 2] = parseInt(clean.substr(i, 2), 16);
        return { output: utf8Decode(bytes), meta: { bytes: bytes.length } };
    }
    const bytes = utf8Encode(text);
    const parts = [];
    for (let i = 0; i < bytes.length; i++)
        parts.push(bytes[i].toString(16).padStart(2, "0"));
    return { output: parts.join(separator), meta: { bytes: bytes.length } };
}

// ─── 7. Data converters ───────────────────────────────────────────────────────

function csvEscape(value, delimiter) {
    const text = value === null || value === undefined ? "" : (typeof value === "object" ? JSON.stringify(value) : String(value));
    return /["\r\n]/.test(text) || text.includes(delimiter) ? `"${text.replace(/"/g, '""')}"` : text;
}

function parseCsv(text, delimiter) {
    const rows = [];
    let row = [];
    let field = "";
    let quoted = false;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (quoted) {
            if (ch === '"') {
                if (text[i + 1] === '"') {
                    field += '"';
                    i++;
                } else {
                    quoted = false;
                }
            } else {
                field += ch;
            }
        } else if (ch === '"') {
            quoted = true;
        } else if (ch === delimiter) {
            row.push(field);
            field = "";
        } else if (ch === "\n" || ch === "\r") {
            if (ch === "\r" && text[i + 1] === "\n")
                i++;
            row.push(field);
            rows.push(row);
            row = [];
            field = "";
        } else {
            field += ch;
        }
    }
    if (quoted)
        throw new Error("a quoted field is never closed");
    if (field.length > 0 || row.length > 0) {
        row.push(field);
        rows.push(row);
    }
    return rows.filter(r => !(r.length === 1 && r[0] === ""));
}

function toolJsonCsv(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    const delimiter = options.delimiter === "tab" ? "\t" : (options.delimiter === ";" ? ";" : ",");

    if (options.mode === "csv_to_json") {
        let rows;
        try {
            rows = parseCsv(text, delimiter);
        } catch (err) {
            return { output: "", error: "CSV error: " + err.message };
        }
        if (rows.length === 0)
            return { output: "[]" };
        const headers = rows[0].map((header, index) => header.trim() || `column${index + 1}`);
        const infer = options.inferTypes !== false;
        const cast = value => {
            if (!infer)
                return value;
            if (/^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$/.test(value))
                return Number(value);
            if (value === "true" || value === "false")
                return value === "true";
            return value === "null" ? null : value;
        };
        const records = rows.slice(1).map(row => {
            const record = {};
            headers.forEach((header, index) => {
                record[header] = cast(row[index] !== undefined ? row[index] : "");
            });
            return record;
        });
        return { output: JSON.stringify(records, null, 2), meta: { rows: records.length, columns: headers.length } };
    }

    let data;
    try {
        data = JSON.parse(text);
    } catch (err) {
        return { output: "", error: "JSON error: " + err.message };
    }
    const records = Array.isArray(data) ? data : [data];
    if (records.some(record => record === null || typeof record !== "object" || Array.isArray(record)))
        return { output: "", error: "Expected an array of objects, such as [{\"name\": \"Ada\"}]." };
    const headers = [];
    records.forEach(record => Object.keys(record).forEach(key => {
        if (headers.indexOf(key) === -1)
            headers.push(key);
    }));
    const lines = [headers.map(header => csvEscape(header, delimiter)).join(delimiter)];
    records.forEach(record => lines.push(headers.map(header => csvEscape(record[header], delimiter)).join(delimiter)));
    return { output: lines.join("\n"), meta: { rows: records.length, columns: headers.length } };
}

// Single letters (K, M, G) follow dd and `ls -h`, which mean binary units.
const BYTE_UNITS = {
    b: 1, byte: 1, bytes: 1,
    kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, pb: 1e15,
    kib: 1024, mib: Math.pow(1024, 2), gib: Math.pow(1024, 3), tib: Math.pow(1024, 4), pib: Math.pow(1024, 5),
    k: 1024, m: Math.pow(1024, 2), g: Math.pow(1024, 3), t: Math.pow(1024, 4), p: Math.pow(1024, 5)
};

function formatSize(value) {
    if (!isFinite(value))
        return String(value);
    const rounded = Math.abs(value) >= 100 ? Math.round(value * 100) / 100 : Math.round(value * 1e6) / 1e6;
    return String(rounded);
}

function toolByteSize(input = "") {
    const text = String(input).trim().replace(/[,_]/g, "");
    if (text.length === 0)
        return { output: "" };
    const match = text.match(/^(\d+(?:\.\d+)?|\.\d+)\s*([a-zA-Z]*)$/);
    if (!match)
        return { output: "", error: "Enter a size such as 1.5 GiB, 500MB or 1048576." };
    const unit = (match[2] || "b").toLowerCase();
    const factor = BYTE_UNITS[unit];
    if (factor === undefined)
        return { output: "", error: "Unknown unit: " + match[2] };
    const bytes = Number(match[1]) * factor;
    const si = [["B", 1], ["kB", 1e3], ["MB", 1e6], ["GB", 1e9], ["TB", 1e12]];
    const binary = [["KiB", 1024], ["MiB", Math.pow(1024, 2)], ["GiB", Math.pow(1024, 3)], ["TiB", Math.pow(1024, 4)]];
    const lines = ["SI (powers of 1000)"]
        .concat(si.map(([name, size]) => `  ${name.padEnd(4)} ${formatSize(bytes / size)}`))
        .concat(["", "Binary (powers of 1024)"])
        .concat(binary.map(([name, size]) => `  ${name.padEnd(4)} ${formatSize(bytes / size)}`));
    if (/^[kmgtp]$/.test(unit))
        lines.push("", `"${match[2]}" is read as a binary unit, as dd and ls -h do.`);
    return { output: lines.join("\n"), meta: { bytes } };
}

// ─── 8. Web & system ──────────────────────────────────────────────────────────

function decodeUrlComponent(text) {
    try {
        return decodeURIComponent(String(text).replace(/\+/g, " "));
    } catch (err) {
        return String(text);
    }
}

function toolUrlParser(input = "") {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    const match = text.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(?:([^:@\/?#]*)(?::([^@\/?#]*))?@)?(\[[^\]]+\]|[^:\/?#]*)(?::(\d+))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/);
    if (!match)
        return { output: "", error: "Enter an absolute URL, such as https://example.com/path?q=1." };
    const scheme = match[1].toLowerCase();
    const user = match[2];
    const password = match[3];
    const host = match[4];
    const port = match[5];
    const path = match[6];
    const query = match[7];
    const fragment = match[8];
    const defaults = { http: "80", https: "443", ftp: "21", ws: "80", wss: "443", ssh: "22" };

    const lines = [`Scheme     ${scheme}`];
    if (user !== undefined)
        lines.push(`User       ${decodeUrlComponent(user)}`);
    if (password !== undefined)
        lines.push(`Password   ${"•".repeat(Math.max(1, Math.min(8, password.length)))}`);
    lines.push(`Host       ${host}`);
    lines.push(`Port       ${port ? port : (defaults[scheme] ? defaults[scheme] + " (default)" : "—")}`);
    lines.push(`Path       ${path || "/"}`);
    lines.push(`Origin     ${scheme}://${host}${port ? ":" + port : ""}`);

    const params = [];
    if (query) {
        query.split("&").filter(Boolean).forEach(pair => {
            const separator = pair.indexOf("=");
            params.push({
                key: decodeUrlComponent(separator >= 0 ? pair.slice(0, separator) : pair),
                value: separator >= 0 ? decodeUrlComponent(pair.slice(separator + 1)) : ""
            });
        });
    }
    if (params.length > 0) {
        lines.push("", `Query parameters (${params.length})`);
        const width = Math.min(24, Math.max.apply(null, params.map(param => param.key.length)));
        params.forEach(param => lines.push(`  ${param.key.padEnd(width)}  ${param.value}`));
    }
    if (fragment)
        lines.push("", `Fragment   ${decodeUrlComponent(fragment)}`);
    return { output: lines.join("\n"), meta: { host, params: params.length } };
}

const HTTP_CLASSES = { 1: "Informational", 2: "Success", 3: "Redirection", 4: "Client error", 5: "Server error" };
const HTTP_STATUS = [
    [100, "Continue", "Keep sending the request body."],
    [101, "Switching Protocols", "The server is switching protocols, e.g. to WebSocket."],
    [103, "Early Hints", "Preload hints sent before the final response."],
    [200, "OK", "The request succeeded."],
    [201, "Created", "A new resource was created."],
    [202, "Accepted", "Accepted for processing, not finished yet."],
    [204, "No Content", "Success, with no body to return."],
    [206, "Partial Content", "A byte range of the resource, for Range requests."],
    [301, "Moved Permanently", "The resource has a new permanent URL."],
    [302, "Found", "The resource is temporarily at another URL."],
    [303, "See Other", "Fetch the result from another URL with GET."],
    [304, "Not Modified", "The cached copy is still valid."],
    [307, "Temporary Redirect", "Temporarily elsewhere; repeat with the same method."],
    [308, "Permanent Redirect", "Permanently elsewhere; repeat with the same method."],
    [400, "Bad Request", "The request is malformed."],
    [401, "Unauthorized", "Authentication is required or has failed."],
    [402, "Payment Required", "Reserved; sometimes used for paywalls and quotas."],
    [403, "Forbidden", "Authenticated, but not allowed."],
    [404, "Not Found", "Nothing exists at this URL."],
    [405, "Method Not Allowed", "This URL does not accept the HTTP method."],
    [406, "Not Acceptable", "No representation matches the Accept headers."],
    [408, "Request Timeout", "The client took too long to send the request."],
    [409, "Conflict", "The request conflicts with the resource's current state."],
    [410, "Gone", "The resource was removed on purpose and will not return."],
    [411, "Length Required", "A Content-Length header is required."],
    [412, "Precondition Failed", "An If-* precondition did not hold."],
    [413, "Content Too Large", "The request body is larger than allowed."],
    [414, "URI Too Long", "The URL is longer than the server accepts."],
    [415, "Unsupported Media Type", "The Content-Type is not supported."],
    [416, "Range Not Satisfiable", "The requested range lies outside the resource."],
    [418, "I'm a teapot", "An April Fools' joke from RFC 2324."],
    [422, "Unprocessable Content", "Well-formed, but the content fails validation."],
    [425, "Too Early", "The server will not risk processing a replayed request."],
    [426, "Upgrade Required", "Switch to another protocol, such as TLS."],
    [428, "Precondition Required", "The request must be conditional."],
    [429, "Too Many Requests", "Rate limited; retry later (see Retry-After)."],
    [431, "Request Header Fields Too Large", "The request headers are too large."],
    [451, "Unavailable For Legal Reasons", "Blocked for legal reasons."],
    [500, "Internal Server Error", "The server hit an unexpected condition."],
    [501, "Not Implemented", "The server does not support this functionality."],
    [502, "Bad Gateway", "An upstream server returned an invalid response."],
    [503, "Service Unavailable", "Overloaded or down for maintenance."],
    [504, "Gateway Timeout", "An upstream server did not answer in time."],
    [505, "HTTP Version Not Supported", "The HTTP version is not supported."],
    [507, "Insufficient Storage", "The server cannot store what the request needs."],
    [511, "Network Authentication Required", "Log in to the network first, e.g. a captive portal."]
];

function toolHttpStatus(input = "") {
    const query = String(input).trim().toLowerCase();
    let matches;
    if (query.length === 0)
        matches = HTTP_STATUS;
    else if (/^[1-5]xx$/.test(query))
        matches = HTTP_STATUS.filter(entry => String(entry[0])[0] === query[0]);
    else if (/^\d{3}$/.test(query))
        matches = HTTP_STATUS.filter(entry => String(entry[0]) === query);
    else
        matches = HTTP_STATUS.filter(entry => `${entry[1]} ${entry[2]}`.toLowerCase().includes(query));
    if (matches.length === 0) {
        if (/^[1-5]\d\d$/.test(query))
            return { output: `${query} is not a registered status code; it falls in the ${HTTP_CLASSES[query[0]]} class (${query[0]}xx).`, meta: { count: 0 } };
        return { output: "No status code matches.", meta: { count: 0 } };
    }
    const lines = matches.map(entry => `${entry[0]}  ${entry[1]}\n     ${HTTP_CLASSES[String(entry[0])[0]]} · ${entry[2]}`);
    return { output: lines.join("\n"), meta: { count: matches.length } };
}

const CRON_MONTH_NAMES = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const CRON_DAY_NAMES = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
const CRON_MACROS = {
    "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
    "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *"
};
const WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function parseCronField(text, min, max, names, label) {
    const values = new Set();
    const toNumber = token => {
        if (names) {
            const named = names.indexOf(token.toLowerCase());
            if (named !== -1)
                return named + min;
        }
        if (!/^\d+$/.test(token))
            throw new Error(`${label}: "${token}" is not a number`);
        return Number(token);
    };
    for (const part of text.split(",")) {
        if (part.length === 0)
            throw new Error(`${label}: empty list item`);
        const pieces = part.split("/");
        if (pieces.length > 2)
            throw new Error(`${label}: "${part}" has more than one step`);
        const step = pieces.length === 2 ? Number(pieces[1]) : 1;
        if (!Number.isInteger(step) || step < 1)
            throw new Error(`${label}: invalid step "${pieces[1]}"`);
        let start;
        let end;
        if (pieces[0] === "*") {
            start = min;
            end = max;
        } else if (pieces[0].includes("-")) {
            const bounds = pieces[0].split("-");
            start = toNumber(bounds[0]);
            end = toNumber(bounds[1]);
        } else {
            start = toNumber(pieces[0]);
            end = pieces.length === 2 ? max : start;
        }
        if (start < min || end > max || start > end)
            throw new Error(`${label}: "${pieces[0]}" is outside ${min}-${max}`);
        for (let value = start; value <= end; value += step)
            values.add(value);
    }
    return values;
}

function describeCronField(text, values, formatValue, unit) {
    if (text === "*")
        return `every ${unit}`;
    const everyStep = text.match(/^\*\/(\d+)$/);
    if (everyStep)
        return `every ${everyStep[1]} ${unit}s`;
    // Consecutive runs collapse: 1,2,3,5 reads as "1–3, 5".
    const sorted = Array.from(values).sort((a, b) => a - b);
    const parts = [];
    for (let i = 0; i < sorted.length; i++) {
        let j = i;
        while (j + 1 < sorted.length && sorted[j + 1] === sorted[j] + 1)
            j++;
        parts.push(j - i >= 2
            ? `${formatValue(sorted[i])}–${formatValue(sorted[j])}`
            : sorted.slice(i, j + 1).map(formatValue).join(", "));
        i = j;
    }
    return parts.join(", ");
}

function toolCronExplainer(input = "", options = {}) {
    let expression = String(input).trim().replace(/\s+/g, " ");
    if (expression.length === 0)
        return { output: "" };
    const macro = CRON_MACROS[expression.toLowerCase()];
    if (macro)
        expression = macro;
    const fields = expression.split(" ");
    if (fields.length !== 5)
        return { output: "", error: "A cron expression has five fields: minute, hour, day of month, month and day of week." };

    let minutes;
    let hours;
    let days;
    let months;
    let weekdays;
    try {
        minutes = parseCronField(fields[0], 0, 59, null, "Minute");
        hours = parseCronField(fields[1], 0, 23, null, "Hour");
        days = parseCronField(fields[2], 1, 31, null, "Day of month");
        months = parseCronField(fields[3], 1, 12, CRON_MONTH_NAMES, "Month");
        weekdays = parseCronField(fields[4], 0, 7, CRON_DAY_NAMES, "Day of week");
    } catch (err) {
        return { output: "", error: err.message };
    }
    // Both 0 and 7 mean Sunday.
    if (weekdays.has(7)) {
        weekdays.delete(7);
        weekdays.add(0);
    }

    const pad = value => String(value).padStart(2, "0");
    const rows = [
        ["Minute", fields[0], describeCronField(fields[0], minutes, value => String(value), "minute")],
        ["Hour", fields[1], describeCronField(fields[1], hours, value => pad(value) + "h", "hour")],
        ["Day", fields[2], describeCronField(fields[2], days, value => String(value), "day")],
        ["Month", fields[3], describeCronField(fields[3], months, value => MONTH_LABELS[value - 1], "month")],
        ["Weekday", fields[4], describeCronField(fields[4], weekdays, value => WEEKDAY_LABELS[value], "weekday")]
    ];
    const lines = rows.map(row => `${row[0].padEnd(8)} ${row[1].padEnd(12)} ${row[2]}`);

    const count = Math.max(1, Math.min(50, Number(options.count) || 5));
    const now = options.now !== undefined ? new Date(Number(options.now)) : new Date();
    // Vixie cron: when both day fields are restricted, either one may match.
    const bothDaysRestricted = fields[2] !== "*" && fields[4] !== "*";
    const sortedHours = Array.from(hours).sort((a, b) => a - b);
    const sortedMinutes = Array.from(minutes).sort((a, b) => a - b);
    const runs = [];
    for (let offset = 0; offset < 366 * 5 && runs.length < count; offset++) {
        const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset);
        if (!months.has(date.getMonth() + 1))
            continue;
        const domMatch = days.has(date.getDate());
        const dowMatch = weekdays.has(date.getDay());
        if (bothDaysRestricted ? !(domMatch || dowMatch) : !(domMatch && dowMatch))
            continue;
        for (let h = 0; h < sortedHours.length && runs.length < count; h++) {
            for (let m = 0; m < sortedMinutes.length && runs.length < count; m++) {
                const run = new Date(date.getFullYear(), date.getMonth(), date.getDate(), sortedHours[h], sortedMinutes[m]);
                if (run > now)
                    runs.push(run);
            }
        }
    }
    lines.push("", runs.length > 0 ? "Next runs" : "No run in the next five years.");
    runs.forEach(run => lines.push(`  ${run.getFullYear()}-${pad(run.getMonth() + 1)}-${pad(run.getDate())} ${pad(run.getHours())}:${pad(run.getMinutes())}  ${WEEKDAY_LABELS[run.getDay()]}`));
    return { output: lines.join("\n"), meta: { runs: runs.length } };
}

function toolChmod(input = "") {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    const rwx = digit => (digit & 4 ? "r" : "-") + (digit & 2 ? "w" : "-") + (digit & 1 ? "x" : "-");
    let digits;
    let special = 0;
    if (/^[0-7]{3,4}$/.test(text)) {
        const all = text.split("").map(Number);
        if (all.length === 4)
            special = all.shift();
        digits = all;
    } else {
        // `ls -l` prints a file-type character first.
        const symbolic = text.length === 10 ? text.slice(1) : text;
        if (!/^[r-][w-][xsS-][r-][w-][xsS-][r-][w-][xtT-]$/.test(symbolic))
            return { output: "", error: "Enter octal (755, 0644) or symbolic (rwxr-xr-x, -rw-r--r--) permissions." };
        digits = [0, 1, 2].map(group => {
            const part = symbolic.slice(group * 3, group * 3 + 3);
            if (/[sStT]/.test(part[2]))
                special |= [4, 2, 1][group];
            return (part[0] === "r" ? 4 : 0) + (part[1] === "w" ? 2 : 0) + (/[xst]/.test(part[2]) ? 1 : 0);
        });
    }
    const chars = digits.map(rwx).join("").split("");
    if (special & 4)
        chars[2] = chars[2] === "x" ? "s" : "S";
    if (special & 2)
        chars[5] = chars[5] === "x" ? "s" : "S";
    if (special & 1)
        chars[8] = chars[8] === "x" ? "t" : "T";
    const symbolicResult = chars.join("");
    const octal = (special > 0 ? String(special) : "") + digits.join("");
    const names = ["Owner", "Group", "Others"];
    const lines = [`Octal     ${octal}`, `Symbolic  ${symbolicResult}`, `Command   chmod ${octal} <file>`, ""];
    digits.forEach((digit, index) => {
        const rights = [digit & 4 ? "read" : "", digit & 2 ? "write" : "", digit & 1 ? "execute" : ""].filter(Boolean);
        lines.push(`${names[index].padEnd(7)}  ${rwx(digit)}  ${rights.length > 0 ? rights.join(", ") : "no access"}`);
    });
    if (special > 0) {
        const flags = [special & 4 ? "setuid" : "", special & 2 ? "setgid" : "", special & 1 ? "sticky bit" : ""].filter(Boolean);
        lines.push("", `Special   ${flags.join(", ")}`);
    }
    return { output: lines.join("\n"), meta: { octal, symbolic: symbolicResult } };
}

// ─── 9. QR codes ──────────────────────────────────────────────────────────────
// Byte-mode QR encoder (ISO/IEC 18004), versions 1-40, after Nayuki's
// reference design. The engine has no BigInt and no Intl, so everything
// here is plain integer math.

const QR_ECC_CODEWORDS = [
    [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
    [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
];
const QR_ECC_BLOCKS = [
    [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
    [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
    [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
    [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81]
];
// Index = L, M, Q, H; value = the two format bits.
const QR_ECC_LEVELS = { L: 0, M: 1, Q: 2, H: 3 };
const QR_FORMAT_BITS = [1, 0, 3, 2];

function qrRawDataModules(ver) {
    let result = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
        const numAlign = Math.floor(ver / 7) + 2;
        result -= (25 * numAlign - 10) * numAlign - 55;
        if (ver >= 7)
            result -= 36;
    }
    return result;
}

function qrDataCodewords(ver, ecl) {
    return Math.floor(qrRawDataModules(ver) / 8) - QR_ECC_CODEWORDS[ecl][ver] * QR_ECC_BLOCKS[ecl][ver];
}

function qrGfMultiply(x, y) {
    let z = 0;
    for (let i = 7; i >= 0; i--) {
        z = (z << 1) ^ ((z >>> 7) * 0x11d);
        z ^= ((y >>> i) & 1) * x;
    }
    return z & 0xff;
}

function qrReedSolomonDivisor(degree) {
    const result = new Array(degree).fill(0);
    result[degree - 1] = 1;
    let rootValue = 1;
    for (let i = 0; i < degree; i++) {
        for (let j = 0; j < result.length; j++) {
            result[j] = qrGfMultiply(result[j], rootValue);
            if (j + 1 < result.length)
                result[j] ^= result[j + 1];
        }
        rootValue = qrGfMultiply(rootValue, 0x02);
    }
    return result;
}

function qrReedSolomonRemainder(data, divisor) {
    const result = divisor.map(() => 0);
    for (const b of data) {
        const factor = b ^ result.shift();
        result.push(0);
        for (let i = 0; i < divisor.length; i++)
            result[i] ^= qrGfMultiply(divisor[i], factor);
    }
    return result;
}

function qrAlignmentPositions(ver) {
    if (ver === 1)
        return [];
    const size = ver * 4 + 17;
    const numAlign = Math.floor(ver / 7) + 2;
    const step = ver === 32 ? 26 : Math.ceil((ver * 4 + 4) / (numAlign * 2 - 2)) * 2;
    const result = [6];
    for (let pos = size - 7; result.length < numAlign; pos -= step)
        result.splice(1, 0, pos);
    return result;
}

/// Encodes bytes into a QR matrix: { size, version, modules: bool[y][x] }.
function qrEncodeBytes(bytes, eclName = "M") {
    const ecl = QR_ECC_LEVELS[eclName] ?? 1;
    let version = 0;
    for (let ver = 1; ver <= 40; ver++) {
        const countBits = ver < 10 ? 8 : 16;
        if (4 + countBits + bytes.length * 8 <= qrDataCodewords(ver, ecl) * 8) {
            version = ver;
            break;
        }
    }
    if (version === 0)
        return null;

    // Data bits: byte mode, length, payload, terminator, padding.
    const bits = [];
    const push = (value, length) => {
        for (let i = length - 1; i >= 0; i--)
            bits.push((value >>> i) & 1);
    };
    push(0x4, 4);
    push(bytes.length, version < 10 ? 8 : 16);
    for (const b of bytes)
        push(b, 8);
    const capacity = qrDataCodewords(version, ecl) * 8;
    push(0, Math.min(4, capacity - bits.length));
    push(0, (8 - bits.length % 8) % 8);
    for (let pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11)
        push(pad, 8);
    const data = [];
    for (let i = 0; i < bits.length; i += 8) {
        let value = 0;
        for (let j = 0; j < 8; j++)
            value = (value << 1) | bits[i + j];
        data.push(value);
    }

    // Error correction, split into blocks and interleaved.
    const numBlocks = QR_ECC_BLOCKS[ecl][version];
    const blockEccLen = QR_ECC_CODEWORDS[ecl][version];
    const rawCodewords = Math.floor(qrRawDataModules(version) / 8);
    const numShortBlocks = numBlocks - rawCodewords % numBlocks;
    const shortBlockLen = Math.floor(rawCodewords / numBlocks);
    const divisor = qrReedSolomonDivisor(blockEccLen);
    const blocks = [];
    for (let i = 0, k = 0; i < numBlocks; i++) {
        const dat = data.slice(k, k + shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1));
        k += dat.length;
        const ecc = qrReedSolomonRemainder(dat, divisor);
        if (i < numShortBlocks)
            dat.push(0);
        blocks.push(dat.concat(ecc));
    }
    const codewords = [];
    for (let i = 0; i < blocks[0].length; i++) {
        for (let j = 0; j < blocks.length; j++) {
            if (i !== shortBlockLen - blockEccLen || j >= numShortBlocks)
                codewords.push(blocks[j][i]);
        }
    }

    // Function patterns.
    const size = version * 4 + 17;
    const modules = [];
    const isFunction = [];
    for (let y = 0; y < size; y++) {
        modules.push(new Array(size).fill(false));
        isFunction.push(new Array(size).fill(false));
    }
    const setFunction = (x, y, dark) => {
        modules[y][x] = dark;
        isFunction[y][x] = true;
    };
    for (let i = 0; i < size; i++) {
        setFunction(6, i, i % 2 === 0);
        setFunction(i, 6, i % 2 === 0);
    }
    const drawFinder = (x, y) => {
        for (let dy = -4; dy <= 4; dy++) {
            for (let dx = -4; dx <= 4; dx++) {
                const dist = Math.max(Math.abs(dx), Math.abs(dy));
                const xx = x + dx, yy = y + dy;
                if (xx >= 0 && xx < size && yy >= 0 && yy < size)
                    setFunction(xx, yy, dist !== 2 && dist !== 4);
            }
        }
    };
    drawFinder(3, 3);
    drawFinder(size - 4, 3);
    drawFinder(3, size - 4);
    const alignPos = qrAlignmentPositions(version);
    const numAlign = alignPos.length;
    for (let i = 0; i < numAlign; i++) {
        for (let j = 0; j < numAlign; j++) {
            if ((i === 0 && j === 0) || (i === 0 && j === numAlign - 1) || (i === numAlign - 1 && j === 0))
                continue;
            for (let dy = -2; dy <= 2; dy++) {
                for (let dx = -2; dx <= 2; dx++)
                    setFunction(alignPos[i] + dx, alignPos[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
            }
        }
    }
    const drawFormat = mask => {
        const formatData = (QR_FORMAT_BITS[ecl] << 3) | mask;
        let rem = formatData;
        for (let i = 0; i < 10; i++)
            rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
        const formatBits = ((formatData << 10) | rem) ^ 0x5412;
        const bit = i => ((formatBits >>> i) & 1) !== 0;
        for (let i = 0; i <= 5; i++)
            setFunction(8, i, bit(i));
        setFunction(8, 7, bit(6));
        setFunction(8, 8, bit(7));
        setFunction(7, 8, bit(8));
        for (let i = 9; i < 15; i++)
            setFunction(14 - i, 8, bit(i));
        for (let i = 0; i < 8; i++)
            setFunction(size - 1 - i, 8, bit(i));
        for (let i = 8; i < 15; i++)
            setFunction(8, size - 15 + i, bit(i));
        setFunction(8, size - 8, true);
    };
    drawFormat(0);
    if (version >= 7) {
        let rem = version;
        for (let i = 0; i < 12; i++)
            rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
        const versionBits = (version << 12) | rem;
        for (let i = 0; i < 18; i++) {
            const dark = ((versionBits >>> i) & 1) !== 0;
            const a = size - 11 + i % 3;
            const b = Math.floor(i / 3);
            setFunction(a, b, dark);
            setFunction(b, a, dark);
        }
    }

    // Codewords in the zigzag order.
    let bitIndex = 0;
    for (let right = size - 1; right >= 1; right -= 2) {
        if (right === 6)
            right = 5;
        for (let vert = 0; vert < size; vert++) {
            for (let j = 0; j < 2; j++) {
                const x = right - j;
                const upward = ((right + 1) & 2) === 0;
                const y = upward ? size - 1 - vert : vert;
                if (!isFunction[y][x] && bitIndex < codewords.length * 8) {
                    modules[y][x] = ((codewords[bitIndex >>> 3] >>> (7 - (bitIndex & 7))) & 1) !== 0;
                    bitIndex++;
                }
            }
        }
    }

    const maskHit = (mask, x, y) => {
        switch (mask) {
        case 0: return (x + y) % 2 === 0;
        case 1: return y % 2 === 0;
        case 2: return x % 3 === 0;
        case 3: return (x + y) % 3 === 0;
        case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
        case 5: return x * y % 2 + x * y % 3 === 0;
        case 6: return (x * y % 2 + x * y % 3) % 2 === 0;
        default: return ((x + y) % 2 + x * y % 3) % 2 === 0;
        }
    };
    const applyMask = mask => {
        for (let y = 0; y < size; y++) {
            for (let x = 0; x < size; x++) {
                if (!isFunction[y][x] && maskHit(mask, x, y))
                    modules[y][x] = !modules[y][x];
            }
        }
    };
    const penalty = () => {
        let score = 0;
        let dark = 0;
        const line = (get) => {
            // Runs of five or more, then 1:1:3:1:1 finder look-alikes with
            // four light modules on either side (the quiet zone counts).
            let runColor = false, runLength = 0;
            const padded = [false, false, false, false];
            for (let i = 0; i < size; i++) {
                const value = get(i);
                padded.push(value);
                if (value === runColor) {
                    runLength++;
                    if (runLength === 5)
                        score += 3;
                    else if (runLength > 5)
                        score++;
                } else {
                    runColor = value;
                    runLength = 1;
                }
            }
            padded.push(false, false, false, false);
            const text = padded.map(v => v ? "1" : "0").join("");
            for (const pattern of ["10111010000", "00001011101"]) {
                for (let at = text.indexOf(pattern); at !== -1; at = text.indexOf(pattern, at + 1))
                    score += 40;
            }
        };
        for (let y = 0; y < size; y++)
            line(x => modules[y][x]);
        for (let x = 0; x < size; x++)
            line(y => modules[y][x]);
        for (let y = 0; y < size - 1; y++) {
            for (let x = 0; x < size - 1; x++) {
                const c = modules[y][x];
                if (c === modules[y][x + 1] && c === modules[y + 1][x] && c === modules[y + 1][x + 1])
                    score += 3;
            }
        }
        for (let y = 0; y < size; y++) {
            for (let x = 0; x < size; x++) {
                if (modules[y][x])
                    dark++;
            }
        }
        const total = size * size;
        const k = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
        return score + Math.max(0, k) * 10;
    };

    let bestMask = 0, bestScore = Infinity;
    for (let mask = 0; mask < 8; mask++) {
        applyMask(mask);
        drawFormat(mask);
        const score = penalty();
        if (score < bestScore) {
            bestScore = score;
            bestMask = mask;
        }
        applyMask(mask);
    }
    applyMask(bestMask);
    drawFormat(bestMask);
    return { size, version, mask: bestMask, modules };
}

function qrEscapeWifi(value) {
    return String(value).replace(/([\\;,:"])/g, "\\$1");
}

function qrFields(text) {
    const fields = {};
    for (const line of String(text).split(/\r?\n/)) {
        const match = line.match(/^\s*([A-Za-z][\w -]*?)\s*[:=]\s*(.*)$/);
        if (match)
            fields[match[1].toLowerCase().replace(/[\s_-]+/g, "")] = match[2].trim();
    }
    return fields;
}

function qrPick(fields, names) {
    for (const name of names) {
        if (fields[name] !== undefined && fields[name] !== "")
            return fields[name];
    }
    return "";
}

/// What the code will hold: the text itself, a Wi-Fi join string or a vCard.
function qrPayload(text, kind) {
    const fields = qrFields(text);
    const ssid = qrPick(fields, ["ssid", "network", "wifi", "rede"]);
    const name = qrPick(fields, ["name", "fullname", "nome"]);
    const phone = qrPick(fields, ["phone", "tel", "mobile", "telefone", "celular"]);
    const email = qrPick(fields, ["email", "mail", "e-mail"]);
    let resolved = kind;
    if (kind === "auto")
        resolved = ssid && !phone && !email ? "wifi" : (name && (phone || email) ? "vcard" : "text");

    if (resolved === "wifi") {
        if (!ssid)
            return { error: "Wi-Fi needs a line such as \"ssid: Home\" (and \"password: …\")." };
        const password = qrPick(fields, ["password", "pass", "senha", "key"]);
        let security = qrPick(fields, ["security", "type", "auth", "seguranca"]).toUpperCase();
        if (!security)
            security = password ? "WPA" : "nopass";
        if (/^(NONE|OPEN|NOPASS)$/.test(security))
            security = "nopass";
        if (/^WPA/.test(security))
            security = "WPA";
        const hidden = /^(true|yes|sim|1)$/i.test(qrPick(fields, ["hidden", "oculta"]));
        let payload = `WIFI:T:${security};S:${qrEscapeWifi(ssid)};`;
        if (security !== "nopass")
            payload += `P:${qrEscapeWifi(password)};`;
        if (hidden)
            payload += "H:true;";
        return { kind: "wifi", payload: payload + ";" };
    }
    if (resolved === "vcard") {
        if (!name)
            return { error: "A contact needs at least \"name: …\" and a phone or e-mail line." };
        const parts = name.split(/\s+/);
        const last = parts.length > 1 ? parts.pop() : "";
        const lines = ["BEGIN:VCARD", "VERSION:3.0", `N:${last};${parts.join(" ")};;;`, `FN:${name}`];
        const org = qrPick(fields, ["org", "organization", "company", "empresa"]);
        const title = qrPick(fields, ["title", "role", "cargo"]);
        const url = qrPick(fields, ["url", "website", "site"]);
        const address = qrPick(fields, ["address", "adr", "endereco"]);
        if (org) lines.push(`ORG:${org}`);
        if (title) lines.push(`TITLE:${title}`);
        if (phone) lines.push(`TEL;TYPE=CELL:${phone}`);
        if (email) lines.push(`EMAIL:${email}`);
        if (url) lines.push(`URL:${url}`);
        if (address) lines.push(`ADR:;;${address};;;;`);
        lines.push("END:VCARD");
        return { kind: "vcard", payload: lines.join("\n") };
    }
    return { kind: "text", payload: String(text) };
}

// ─── 9b. Styled QR SVG Renderer (Pixel + Blob + Classic) ─────────────────────

const QR_SVG_KAPPA = 0.5522847498;
const _qrRegionsCache = {};
const _qrOuterDecorCache = {};
const _qrSvgCache = {};
const _qrSvgCacheOrder = [];
let _qrPolyCacheRaw = null;
let _qrPolyCacheData = null;
let _qrLastShapesRef = null;

function qrSvgFmt(n) {
    const r = Math.round(n * 100) / 100;
    if (r === 0)
        return "0";
    if (r > -1 && r < 1) {
        const s = String(r);
        return r > 0 ? s.slice(1) : "-" + s.slice(2);
    }
    return String(r);
}

function qrSvgHash2d(x, y, seed) {
    let h = (x * 374761393 + y * 668265263 + (seed || 0) * 1442695041) | 0;
    h = ((h ^ (h >>> 13)) * 1274126177) | 0;
    return (h ^ (h >>> 16)) >>> 0;
}

function qrSvgAlignmentCenters(version) {
    const pos = qrAlignmentPositions(version);
    const n = pos.length;
    const centers = [];
    for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
            if ((i === 0 && j === 0) || (i === 0 && j === n - 1) || (i === n - 1 && j === 0))
                continue;
            centers.push([pos[i], pos[j]]);
        }
    }
    return centers;
}

function qrSvgNormalizeMatrix(qr) {
    if (qr && qr.modules) {
        return {
            size: qr.size,
            version: qr.version || Math.round((qr.size - 17) / 4),
            modules: qr.modules
        };
    }
    const rows = (qr && qr.rows) || [];
    const size = rows.length;
    const modules = [];
    for (let y = 0; y < size; y++) {
        const row = [];
        for (let x = 0; x < size; x++)
            row.push(rows[y][x] === "1");
        modules.push(row);
    }
    return {
        size,
        version: (qr && qr.version) || Math.round((size - 17) / 4),
        modules
    };
}

function qrSvgParseHex(str, fallbackHex) {
    const parsed = parseColor(str);
    if (parsed)
        return { r: parsed.r, g: parsed.g, b: parsed.b, a: 1 };
    const fb = parseColor(fallbackHex);
    return fb ? { r: fb.r, g: fb.g, b: fb.b, a: 1 } : { r: 0, g: 0, b: 0, a: 1 };
}

function qrSvgMixHex(hexA, hexB, t) {
    const a = qrSvgParseHex(hexA, "#000000");
    const b = qrSvgParseHex(hexB, "#FFFFFF");
    const k = Math.max(0, Math.min(1, t));
    return colorToHex({
        r: a.r + (b.r - a.r) * k,
        g: a.g + (b.g - a.g) * k,
        b: a.b + (b.b - a.b) * k,
        a: 1
    });
}

function qrSvgGuardBackground(bgRgb, preferLightBg) {
    const lum = relativeLuminance(bgRgb);
    if (preferLightBg && lum >= 0.28)
        return bgRgb;
    if (!preferLightBg && lum <= 0.12)
        return bgRgb;
    const hsl = rgbToHsl(bgRgb);
    let lo = hsl.l;
    let hi = preferLightBg ? 1 : 0;
    for (let i = 0; i < 24; i++) {
        const mid = (lo + hi) * 0.5;
        const c = hslToRgb(hsl.h, hsl.s, mid);
        const mLum = relativeLuminance(c);
        if (preferLightBg ? mLum >= 0.30 : mLum <= 0.11)
            hi = mid;
        else
            lo = mid;
    }
    return parseColor(colorToHex(hslToRgb(hsl.h, hsl.s, hi))) || bgRgb;
}

function qrSvgEnsureContrast(fgHex, bgRgb, preferDarkInk, minRatio) {
    const fgRgb = qrSvgParseHex(fgHex, preferDarkInk ? "#000000" : "#FFFFFF");
    const bgLum = relativeLuminance(bgRgb);
    const fgLum = relativeLuminance(fgRgb);
    const rightSide = preferDarkInk ? fgLum < bgLum : fgLum > bgLum;
    if (rightSide && contrastRatio(fgRgb, bgRgb) >= minRatio)
        return colorToHex(fgRgb);

    const hsl = rgbToHsl(fgRgb);
    const bgHsl = rgbToHsl(bgRgb);
    let lo = rightSide ? hsl.l : bgHsl.l;
    const hiEnd = preferDarkInk ? 0 : 1;
    let hi = hiEnd;
    const endRgb = hslToRgb(hsl.h, hsl.s, hiEnd);
    if (contrastRatio(endRgb, bgRgb) < minRatio)
        return preferDarkInk ? "#000000" : "#FFFFFF";

    for (let i = 0; i < 28; i++) {
        const mid = (lo + hi) * 0.5;
        if (contrastRatio(hslToRgb(hsl.h, hsl.s, mid), bgRgb) >= minRatio)
            hi = mid;
        else
            lo = mid;
    }
    const dir = preferDarkInk ? -1 : 1;
    let l = hi;
    let out = hslToRgb(hsl.h, hsl.s, l);
    for (let guard = 0; guard < 50 && contrastRatio(parseColor(colorToHex(out)), bgRgb) < minRatio; guard++) {
        l = Math.max(0, Math.min(1, l + dir * 0.002));
        out = hslToRgb(hsl.h, hsl.s, l);
    }
    return colorToHex(out);
}

function qrSvgEnsureDotContrast(dotHex, bgRgb, maxRatio) {
    const dotRgb = qrSvgParseHex(dotHex, colorToHex(bgRgb));
    if (contrastRatio(dotRgb, bgRgb) <= maxRatio)
        return colorToHex(dotRgb);
    const bgHex = colorToHex(bgRgb);
    let lo = 0;
    let hi = 1;
    for (let i = 0; i < 20; i++) {
        const mid = (lo + hi) * 0.5;
        const mixed = qrSvgParseHex(qrSvgMixHex(bgHex, dotHex, mid), bgHex);
        if (contrastRatio(mixed, bgRgb) <= maxRatio)
            lo = mid;
        else
            hi = mid;
    }
    return qrSvgMixHex(bgHex, dotHex, lo);
}

/**
 * Resolves theme or explicit colours into a contrast-safe QR palette.
 * Dark/light module tones are guaranteed >= 5.0:1 against the background tint
 * (safely above 4.5:1), and decorative dots stay <= 1.28:1.
 */
function qrSvgResolveColors(style, colors) {
    const c = colors || {};
    const minRatio = typeof c.minContrast === "number" ? c.minContrast : 5.0;
    let isDark = false;
    if (c.darkmode !== undefined) {
        isDark = Boolean(c.darkmode);
    } else {
        const probe = c.backgroundTint || c.background || c.surfaceHigh || c.surface;
        if (probe && probe !== "transparent")
            isDark = relativeLuminance(qrSvgParseHex(probe, "#FFFFFF")) < 0.18;
    }

    if (style === "pixel") {
        let rawTint = c.backgroundTint;
        if (!rawTint) {
            const baseSurf = c.surfaceHigh || c.background || (isDark ? "#282320" : "#F4EAE1");
            if (c.primaryContainer) {
                const surfLum = relativeLuminance(qrSvgParseHex(baseSurf, "#F4EAE1"));
                const pcLum = relativeLuminance(qrSvgParseHex(c.primaryContainer, baseSurf));
                const samePolarity = (surfLum < 0.2) === (pcLum < 0.2);
                rawTint = qrSvgMixHex(baseSurf, c.primaryContainer, samePolarity ? 0.18 : 0.08);
            } else {
                rawTint = baseSurf;
            }
        }
        const tintRgb = qrSvgGuardBackground(qrSvgParseHex(rawTint, isDark ? "#282320" : "#F4EAE1"), !isDark);
        const backgroundTint = colorToHex(tintRgb);
        const preferDarkInk = relativeLuminance(tintRgb) >= 0.20;

        let tones;
        if (Array.isArray(c.tones) && c.tones.length > 0) {
            tones = c.tones.map(t => qrSvgEnsureContrast(t, tintRgb, preferDarkInk, minRatio));
        } else {
            const onSurf = c.onSurface || (preferDarkInk ? "#1F2A3A" : "#F3E5D8");
            const prim = c.primary || onSurf;
            const mainRaw = c.primary && c.onSurface ? qrSvgMixHex(onSurf, prim, 0.22) : prim;
            const main = qrSvgEnsureContrast(mainRaw, tintRgb, preferDarkInk, minRatio);
            const darker = qrSvgEnsureContrast(
                c.darker || qrSvgMixHex(main, preferDarkInk ? "#000000" : "#FFFFFF", 0.45),
                tintRgb, preferDarkInk, minRatio
            );
            const mid = qrSvgEnsureContrast(c.secondary || c.primary || main, tintRgb, preferDarkInk, minRatio);
            const accent = qrSvgEnsureContrast(c.tertiary || c.secondary || main, tintRgb, preferDarkInk, minRatio);
            tones = [main, darker, mid, accent];
        }

        const outerDot = qrSvgEnsureDotContrast(
            c.outerDot || qrSvgMixHex(backgroundTint, tones[0], 0.12),
            tintRgb, 1.28
        );
        const lightDot = qrSvgEnsureDotContrast(
            c.lightDot || qrSvgMixHex(backgroundTint, tones[0], 0.08),
            tintRgb, 1.22
        );
        const canvasBg = c.canvasBg !== undefined
            ? c.canvasBg
            : (c.surfaceLow || c.surface || (preferDarkInk ? "#FFFFFF" : "#141210"));

        return {
            canvasBg,
            backgroundTint,
            outerDot,
            lightDot,
            primary: tones[0],
            tones
        };
    }

    if (style === "blob") {
        const bgExplicit = c.background;
        const bgProbe = (bgExplicit && bgExplicit !== "transparent")
            ? bgExplicit
            : (c.cardBackground || c.surfaceLow || c.surface || (isDark ? "#1B1822" : "#FFFFFF"));
        const bgRgb = qrSvgGuardBackground(qrSvgParseHex(bgProbe, isDark ? "#1B1822" : "#FFFFFF"), !isDark);
        const preferDarkInk = relativeLuminance(bgRgb) >= 0.20;
        const primary = qrSvgEnsureContrast(
            c.primary || (preferDarkInk ? "#673AB7" : "#D0BCFF"),
            bgRgb, preferDarkInk, minRatio
        );
        return {
            background: bgExplicit === "transparent" ? "transparent" : colorToHex(bgRgb),
            primary
        };
    }

    // Classic / square
    const bgExplicit = c.background;
    const bgProbe = (bgExplicit && bgExplicit !== "transparent") ? bgExplicit : "#FFFFFF";
    const bgRgb = qrSvgGuardBackground(qrSvgParseHex(bgProbe, "#FFFFFF"), true);
    const preferDarkInk = relativeLuminance(bgRgb) >= 0.20;
    const primary = qrSvgEnsureContrast(c.primary || "#000000", bgRgb, preferDarkInk, minRatio);
    return {
        background: bgExplicit === "transparent" ? "transparent" : colorToHex(bgRgb),
        primary
    };
}

function qrSvgCompileRelCubics(cubics, scale) {
    if (!cubics || cubics.length === 0)
        return null;
    const ox = -scale * 0.5;
    const oy = -scale * 0.5;
    const round2 = v => Math.round(v * 100) / 100;
    const dx0 = round2(ox + cubics[0][0] * scale);
    const dy0 = round2(oy + cubics[0][1] * scale);
    let curX = dx0;
    let curY = dy0;
    const parts = [];
    for (let i = 0; i < cubics.length; i++) {
        const c = cubics[i];
        const c1x = round2(ox + c[2] * scale);
        const c1y = round2(oy + c[3] * scale);
        const c2x = round2(ox + c[4] * scale);
        const c2y = round2(oy + c[5] * scale);
        const ex = round2(ox + c[6] * scale);
        const ey = round2(oy + c[7] * scale);
        const dx1 = c1x - curX;
        const dy1 = c1y - curY;
        const dx2 = c2x - curX;
        const dy2 = c2y - curY;
        const dx = ex - curX;
        const dy = ey - curY;
        if (dx1 === 0 && dy1 === 0 && dx2 === 0 && dy2 === 0 && dx === 0 && dy === 0)
            continue;
        parts.push(
            (parts.length === 0 ? "c" : " ") +
            qrSvgFmt(dx1) + "," + qrSvgFmt(dy1) + " " +
            qrSvgFmt(dx2) + "," + qrSvgFmt(dy2) + " " +
            qrSvgFmt(dx) + "," + qrSvgFmt(dy)
        );
        curX = ex;
        curY = ey;
    }
    parts.push("z");
    return { dx0, dy0, body: parts.join("") };
}

function qrSvgCubicsToPath(cubics, cx, cy, scale) {
    const compiled = qrSvgCompileRelCubics(cubics, scale);
    if (!compiled)
        return "";
    return "M" + qrSvgFmt(cx + compiled.dx0) + "," + qrSvgFmt(cy + compiled.dy0) + compiled.body;
}

function qrSvgEvalCubic(c, t) {
    const u = 1 - t;
    const u2 = u * u, t2 = t * t;
    const w0 = u2 * u, w1 = 3 * t * u2, w2 = 3 * t2 * u, w3 = t2 * t;
    return [
        c[0] * w0 + c[2] * w1 + c[4] * w2 + c[6] * w3,
        c[1] * w0 + c[3] * w1 + c[5] * w2 + c[7] * w3
    ];
}

function qrSvgSamplePolygon(cubics, samplesPerCubic) {
    const pts = [];
    const n = samplesPerCubic || 6;
    for (let i = 0; i < cubics.length; i++) {
        const c = cubics[i];
        for (let s = 0; s < n; s++)
            pts.push(qrSvgEvalCubic(c, s / n));
    }
    return pts;
}

function qrSvgPolyBounds(cubics) {
    if (_qrPolyCacheRaw === cubics && _qrPolyCacheData)
        return _qrPolyCacheData;
    const poly = qrSvgSamplePolygon(cubics, 6);
    let rMin2 = Infinity;
    let rMax2 = 0;
    for (let i = 0; i < poly.length; i++) {
        const dx = poly[i][0] - 0.5;
        const dy = poly[i][1] - 0.5;
        const d2 = dx * dx + dy * dy;
        if (d2 < rMin2) rMin2 = d2;
        if (d2 > rMax2) rMax2 = d2;
    }
    const data = { poly, rMin: Math.sqrt(rMin2), rMax: Math.sqrt(rMax2) };
    _qrPolyCacheRaw = cubics;
    _qrPolyCacheData = data;
    return data;
}

function qrSvgPointInPoly(px, py, poly) {
    let inside = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const xi = poly[i][0], yi = poly[i][1];
        const xj = poly[j][0], yj = poly[j][1];
        const hit = ((yi > py) !== (yj > py)) &&
            (px < (xj - xi) * (py - yi) / (yj - yi + 1e-12) + xi);
        if (hit)
            inside = !inside;
    }
    return inside;
}

function qrSvgMinDistToPoly(px, py, poly) {
    let minD2 = Infinity;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const ax = poly[j][0], ay = poly[j][1];
        const bx = poly[i][0], by = poly[i][1];
        const abx = bx - ax, aby = by - ay;
        const len2 = abx * abx + aby * aby;
        let t = len2 > 0 ? ((px - ax) * abx + (py - ay) * aby) / len2 : 0;
        if (t < 0) t = 0;
        else if (t > 1) t = 1;
        const dx = px - (ax + t * abx);
        const dy = py - (ay + t * aby);
        const d2 = dx * dx + dy * dy;
        if (d2 < minD2) minD2 = d2;
    }
    return Math.sqrt(minD2);
}

function qrSvgFallbackCookie(lobes, innerRatio) {
    const n = lobes * 2;
    const pts = [];
    for (let i = 0; i < n; i++) {
        const a = (i * Math.PI * 2) / n - Math.PI / 2;
        const r = (i % 2 === 0) ? 0.5 : 0.5 * innerRatio;
        pts.push([0.5 + r * Math.cos(a), 0.5 + r * Math.sin(a)]);
    }
    const cubics = [];
    for (let j = 0; j < n; j++) {
        const p0 = pts[(j + n - 1) % n];
        const p1 = pts[j];
        const p2 = pts[(j + 1) % n];
        const s1x = (p0[0] + p1[0]) * 0.5, s1y = (p0[1] + p1[1]) * 0.5;
        const s2x = (p1[0] + p2[0]) * 0.5, s2y = (p1[1] + p2[1]) * 0.5;
        cubics.push([
            s1x, s1y,
            s1x + (p1[0] - s1x) * 0.66, s1y + (p1[1] - s1y) * 0.66,
            s2x + (p1[0] - s2x) * 0.66, s2y + (p1[1] - s2y) * 0.66,
            s2x, s2y
        ]);
    }
    return cubics;
}

function qrSvgBuildRegions(size, version) {
    const cacheKey = size + ":" + version;
    if (_qrRegionsCache[cacheKey])
        return _qrRegionsCache[cacheKey];
    const isFinder = [];
    const isSeparator = [];
    const isAlignment = [];
    for (let y = 0; y < size; y++) {
        isFinder.push(new Array(size).fill(false));
        isSeparator.push(new Array(size).fill(false));
        isAlignment.push(new Array(size).fill(false));
    }
    function markBox(arr, x0, y0, w, h) {
        for (let yy = Math.max(0, y0); yy < Math.min(size, y0 + h); yy++) {
            for (let xx = Math.max(0, x0); xx < Math.min(size, x0 + w); xx++)
                arr[yy][xx] = true;
        }
    }
    markBox(isFinder, 0, 0, 7, 7);
    markBox(isFinder, size - 7, 0, 7, 7);
    markBox(isFinder, 0, size - 7, 7, 7);
    markBox(isSeparator, 0, 0, 8, 8);
    markBox(isSeparator, size - 8, 0, 8, 8);
    markBox(isSeparator, 0, size - 8, 8, 8);
    const alignCenters = qrSvgAlignmentCenters(version);
    for (let a = 0; a < alignCenters.length; a++) {
        const ac = alignCenters[a];
        markBox(isAlignment, ac[0] - 2, ac[1] - 2, 5, 5);
    }
    const regions = { isFinder, isSeparator, isAlignment, alignCenters };
    _qrRegionsCache[cacheKey] = regions;
    return regions;
}

function qrSvgPillPath(x, y, w, h, r) {
    const rx = Math.min(r, w * 0.5, h * 0.5);
    const rxStr = qrSvgFmt(rx);
    const negRxStr = qrSvgFmt(-rx);
    const dxLine = w - rx * 2;
    const dyLine = h - rx * 2;
    const parts = ["M" + qrSvgFmt(x + rx) + "," + qrSvgFmt(y)];
    if (dxLine > 0.005) parts.push("h" + qrSvgFmt(dxLine));
    parts.push("a" + rxStr + "," + rxStr + " 0 0,1 " + rxStr + "," + rxStr);
    if (dyLine > 0.005) parts.push("v" + qrSvgFmt(dyLine));
    parts.push("a" + rxStr + "," + rxStr + " 0 0,1 " + negRxStr + "," + rxStr);
    if (dxLine > 0.005) parts.push("h" + qrSvgFmt(-dxLine));
    parts.push("a" + rxStr + "," + rxStr + " 0 0,1 " + negRxStr + "," + negRxStr);
    if (dyLine > 0.005) parts.push("v" + qrSvgFmt(-dyLine));
    parts.push("a" + rxStr + "," + rxStr + " 0 0,1 " + rxStr + "," + negRxStr);
    parts.push("z");
    return parts.join("");
}

function qrSvgCircleArcSuffix(r) {
    const rStr = qrSvgFmt(r);
    const dPos = qrSvgFmt(r * 2);
    const dNeg = qrSvgFmt(-r * 2);
    return "a" + rStr + "," + rStr + " 0 1,0 " + dPos + ",0a" + rStr + "," + rStr + " 0 1,0 " + dNeg + ",0z";
}

function qrSvgCirclePath(cx, cy, r) {
    return "M" + qrSvgFmt(cx - r) + "," + qrSvgFmt(cy) + qrSvgCircleArcSuffix(r);
}

function qrSvgRingPath(cx, cy, rOuter, rInner) {
    const ro = qrSvgFmt(rOuter), doPos = qrSvgFmt(rOuter * 2), doNeg = qrSvgFmt(-rOuter * 2);
    const ri = qrSvgFmt(rInner), diPos = qrSvgFmt(rInner * 2), diNeg = qrSvgFmt(-rInner * 2);
    const cyStr = qrSvgFmt(cy);
    return (
        "M" + qrSvgFmt(cx - rOuter) + "," + cyStr +
        "a" + ro + "," + ro + " 0 1,0 " + doPos + ",0a" + ro + "," + ro + " 0 1,0 " + doNeg + ",0z" +
        "M" + qrSvgFmt(cx - rInner) + "," + cyStr +
        "a" + ri + "," + ri + " 0 1,1 " + diPos + ",0a" + ri + "," + ri + " 0 1,1 " + diNeg + ",0z"
    );
}

function qrSvgPickToneIndex(h, tonesCount) {
    if (tonesCount <= 1)
        return 0;
    const p = (h >>> 8) % 100;
    if (p < 46) return 0;
    if (p < 72) return Math.min(1, tonesCount - 1);
    if (p < 89) return Math.min(2, tonesCount - 1);
    return Math.min(3, tonesCount - 1);
}

function qrSvgBuildOuterDecorPaths(size, viewMin, viewPad, quietZone, cookieScale, cookie4) {
    const cacheKey = size + ":" + cookieScale.toFixed(2);
    const cached = _qrOuterDecorCache[cacheKey];
    if (cached && cached.cookieRef === cookie4)
        return cached;

    const bounds = qrSvgPolyBounds(cookie4);
    const polyNorm = bounds.poly;
    const minG = Math.floor(viewMin);
    const maxG = Math.ceil(size + viewPad);
    const edgeMargin = 0.72;
    const quietMin = -quietZone;
    const quietMax = size + quietZone;
    const qrCenter = size * 0.5;
    const ox = qrCenter - cookieScale * 0.5;
    const oy = qrCenter - cookieScale * 0.5;
    const rMaxSkip = bounds.rMax + 0.02;
    const rMinInside = bounds.rMin - (1.45 / cookieScale + 0.02);
    const edgeSuffix = qrSvgCircleArcSuffix(0.25);

    const interiorRuns = [];
    const edgeDots = [];

    for (let gy = minG; gy < maxG; gy++) {
        const cy = gy + 0.5;
        const ny = (cy - oy) / cookieScale;
        const nyD = ny - 0.5;
        const inQuietY = cy > quietMin && cy < quietMax;
        let runStart = null;

        for (let gx = minG; gx < maxG; gx++) {
            const cx = gx + 0.5;
            let state = 0; // 0 = skip, 1 = interior (0.33), 2 = edge (0.25)
            if (!(inQuietY && cx > quietMin && cx < quietMax)) {
                const nx = (cx - ox) / cookieScale;
                const nxD = nx - 0.5;
                const rCenter = Math.sqrt(nxD * nxD + nyD * nyD);
                if (rCenter <= rMaxSkip) {
                    if (rCenter < rMinInside) {
                        state = 1;
                    } else if (qrSvgPointInPoly(nx, ny, polyNorm)) {
                        const distMod = qrSvgMinDistToPoly(nx, ny, polyNorm) * cookieScale;
                        if (distMod >= edgeMargin)
                            state = distMod < 1.35 ? 2 : 1;
                    }
                }
            }
            if (state === 1) {
                if (runStart === null)
                    runStart = gx;
            } else {
                if (runStart !== null) {
                    const w = gx - runStart;
                    interiorRuns.push("M" + runStart + "," + gy + "h" + w + "v1h-" + w + "z");
                    runStart = null;
                }
                if (state === 2)
                    edgeDots.push("M" + qrSvgFmt(cx - 0.25) + "," + qrSvgFmt(cy) + edgeSuffix);
            }
        }
        if (runStart !== null) {
            const w = maxG - runStart;
            interiorRuns.push("M" + runStart + "," + gy + "h" + w + "v1h-" + w + "z");
        }
    }

    const result = {
        cookieRef: cookie4,
        interiorPath: interiorRuns.join(""),
        edgePath: edgeDots.join("")
    };
    _qrOuterDecorCache[cacheKey] = result;
    return result;
}

function qrSvgRenderPixel(mat, regions, opts) {
    const size = mat.size;
    const colors = opts.colors;
    const shapes = opts.shapes || {};
    const cookie4 = shapes.cookie4Sided || qrSvgFallbackCookie(4, 0.72);
    const cookie9 = shapes.cookie9Sided || qrSvgFallbackCookie(9, 0.76);
    const smallShapesRaw = [
        shapes.cookie6Sided || qrSvgFallbackCookie(6, 0.78),
        shapes.cookie7Sided || qrSvgFallbackCookie(7, 0.78),
        shapes.cookie4Sided || qrSvgFallbackCookie(4, 0.78)
    ];

    const decoration = opts.decoration !== false;
    const quietZone = decoration ? 2.5 : 4;
    const moduleRatio = 0.85;
    const qrCenter = size * 0.5;
    const cookieScale = decoration
        ? Math.max(size * 1.46, (size * 0.5 + quietZone + 3.0) / 0.415)
        : (size + 8);
    const viewPad = decoration ? Math.ceil(cookieScale * 0.5 - size * 0.5 + 1.5) : 4;
    const viewMin = -viewPad;
    const viewSize = size + viewPad * 2;
    const defs = [];
    const elements = [];

    if (colors.canvasBg && colors.canvasBg !== "transparent") {
        elements.push('<rect x="' + qrSvgFmt(viewMin) + '" y="' + qrSvgFmt(viewMin) + '" width="' + qrSvgFmt(viewSize) + '" height="' + qrSvgFmt(viewSize) + '" fill="' + colors.canvasBg + '"/>');
    }

    elements.push('<path d="' + qrSvgCubicsToPath(cookie4, qrCenter, qrCenter, cookieScale) + '" fill="' + colors.backgroundTint + '"/>');

    if (decoration) {
        const decor = qrSvgBuildOuterDecorPaths(size, viewMin, viewPad, quietZone, cookieScale, cookie4);
        if (decor.interiorPath.length > 0) {
            defs.push('<pattern id="od" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r=".33" fill="' + colors.outerDot + '"/></pattern>');
            elements.push('<path d="' + decor.interiorPath + '" fill="url(#od)"/>');
        }
        if (decor.edgePath.length > 0)
            elements.push('<path d="' + decor.edgePath + '" fill="' + colors.outerDot + '"/>');
    }

    if (colors.lightDot) {
        const ldParts = [];
        for (let ly = 0; ly < size; ly++) {
            const row = mat.modules[ly];
            const sepRow = regions.isSeparator[ly];
            const alignRow = regions.isAlignment[ly];
            let lx = 0;
            while (lx < size) {
                if (row[lx] || sepRow[lx] || alignRow[lx]) {
                    lx++;
                    continue;
                }
                const x0 = lx;
                lx++;
                while (lx < size && !row[lx] && !sepRow[lx] && !alignRow[lx])
                    lx++;
                const w = lx - x0;
                ldParts.push("M" + x0 + "," + ly + "h" + w + "v1h-" + w + "z");
            }
        }
        if (ldParts.length > 0) {
            defs.push('<pattern id="ld" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r=".19" fill="' + colors.lightDot + '"/></pattern>');
            elements.push('<path d="' + ldParts.join("") + '" fill="url(#ld)"/>');
        }
    }

    const visited = [];
    for (let vy = 0; vy < size; vy++)
        visited.push(new Array(size).fill(false));

    function isDataDark(x, y) {
        if (x < 0 || y < 0 || x >= size || y >= size)
            return false;
        if (!mat.modules[y][x] || regions.isFinder[y][x] || regions.isAlignment[y][x])
            return false;
        return !visited[y][x];
    }

    const tones = colors.tones || [colors.primary];
    const bucketByColor = {};
    const bucketOrder = [];
    const toneBucketIdx = [];
    for (let t = 0; t < tones.length; t++) {
        const col = tones[t];
        if (bucketByColor[col] === undefined) {
            bucketByColor[col] = bucketOrder.length;
            bucketOrder.push({ color: col, parts: [] });
        }
        toneBucketIdx.push(bucketByColor[col]);
    }

    const mInset = (1 - moduleRatio) * 0.5;
    const pillRadius = moduleRatio * 0.5;
    const rxStr = qrSvgFmt(pillRadius);
    const dStr = qrSvgFmt(moduleRatio);
    const dNegStr = qrSvgFmt(-moduleRatio);
    const hPillMid = "a" + rxStr + "," + rxStr + " 0 1,1 0," + dStr + "h";
    const hPillEnd = "a" + rxStr + "," + rxStr + " 0 1,1 0," + dNegStr + "z";
    const vPillMid = "a" + rxStr + "," + rxStr + " 0 1,0 " + dStr + ",0v";
    const vPillEnd = "a" + rxStr + "," + rxStr + " 0 1,0 " + dNegStr + ",0z";
    const dotSuffix = qrSvgCircleArcSuffix(pillRadius);
    const smallCompiled = [
        qrSvgCompileRelCubics(smallShapesRaw[0], moduleRatio * 1.08),
        qrSvgCompileRelCubics(smallShapesRaw[1], moduleRatio * 1.08),
        qrSvgCompileRelCubics(smallShapesRaw[2], moduleRatio * 1.08)
    ];

    for (let y = 0; y < size; y++) {
        const yInsetStr = qrSvgFmt(y + mInset);
        const yHalfStr = qrSvgFmt(y + 0.5);
        for (let x = 0; x < size; x++) {
            if (!isDataDark(x, y))
                continue;
            const h = qrSvgHash2d(x, y, size);
            const maxCap = 2 + ((h >>> 3) % 3);
            let hAvail = 1;
            while (hAvail < maxCap && isDataDark(x + hAvail, y)) hAvail++;
            let vAvail = 1;
            while (vAvail < maxCap && isDataDark(x, y + vAvail)) vAvail++;

            let dir = "single";
            const preferV = (h & 1) === 1;
            if (preferV && vAvail >= 2) dir = "v";
            else if (!preferV && hAvail >= 2) dir = "h";
            else if (vAvail >= 2) dir = "v";
            else if (hAvail >= 2) dir = "h";

            const bucket = bucketOrder[toneBucketIdx[qrSvgPickToneIndex(h, tones.length)]].parts;
            if (dir === "h") {
                for (let hx = 0; hx < hAvail; hx++) visited[y][x + hx] = true;
                const span = hAvail - 1;
                bucket.push("M" + qrSvgFmt(x + 0.5) + "," + yInsetStr + "h" + span + hPillMid + (-span) + hPillEnd);
            } else if (dir === "v") {
                for (let hy = 0; hy < vAvail; hy++) visited[y + hy][x] = true;
                const span = vAvail - 1;
                bucket.push("M" + qrSvgFmt(x + mInset) + "," + yHalfStr + "v" + span + vPillMid + (-span) + vPillEnd);
            } else {
                visited[y][x] = true;
                if ((h % 5) === 0) {
                    const sc = smallCompiled[(h >>> 4) % smallCompiled.length];
                    bucket.push("M" + qrSvgFmt(x + 0.5 + sc.dx0) + "," + qrSvgFmt(y + 0.5 + sc.dy0) + sc.body);
                } else {
                    bucket.push("M" + qrSvgFmt(x + mInset) + "," + yHalfStr + dotSuffix);
                }
            }
        }
    }

    const tone0Parts = bucketOrder[toneBucketIdx[0]].parts;
    if (regions.alignCenters.length > 0) {
        for (let ai = 0; ai < regions.alignCenters.length; ai++) {
            const ac = regions.alignCenters[ai];
            const acx = ac[0] + 0.5;
            const acy = ac[1] + 0.5;
            tone0Parts.push(qrSvgRingPath(acx, acy, 2.44, 1.56));
            tone0Parts.push(qrSvgCirclePath(acx, acy, 0.62));
        }
    }

    const finderPositions = [[3.5, 3.5], [size - 3.5, 3.5], [3.5, size - 3.5]];
    const finderCoreBucket = bucketOrder[toneBucketIdx[tones.length > 1 ? 1 : 0]].parts;
    for (let fi = 0; fi < finderPositions.length; fi++) {
        const fp = finderPositions[fi];
        tone0Parts.push(qrSvgRingPath(fp[0], fp[1], 3.48, 2.52));
        finderCoreBucket.push(qrSvgCubicsToPath(cookie9, fp[0], fp[1], 3.16));
    }

    for (let bi = 0; bi < bucketOrder.length; bi++) {
        const b = bucketOrder[bi];
        if (b.parts.length > 0)
            elements.push('<path d="' + b.parts.join("") + '" fill="' + b.color + '"/>');
    }

    if (defs.length > 0)
        elements.unshift("<defs>" + defs.join("") + "</defs>");

    return {
        viewBox: qrSvgFmt(viewMin) + " " + qrSvgFmt(viewMin) + " " + qrSvgFmt(viewSize) + " " + qrSvgFmt(viewSize),
        elements
    };
}

function qrSvgRoundedOctagonLoop(cx, cy, halfSize, chamfer, r, ccw) {
    const h = halfSize;
    const c = chamfer;
    const pts = [
        [cx - h + c, cy - h],
        [cx + h - c, cy - h],
        [cx + h, cy - h + c],
        [cx + h, cy + h - c],
        [cx + h - c, cy + h],
        [cx - h + c, cy + h],
        [cx - h, cy + h - c],
        [cx - h, cy - h + c]
    ];
    if (ccw) pts.reverse();
    const n = pts.length;
    const cmds = [];
    for (let i = 0; i < n; i++) {
        const prev = pts[(i + n - 1) % n];
        const curr = pts[i];
        const next = pts[(i + 1) % n];
        const d1x = curr[0] - prev[0], d1y = curr[1] - prev[1];
        const d2x = next[0] - curr[0], d2y = next[1] - curr[1];
        const l1 = Math.sqrt(d1x * d1x + d1y * d1y);
        const l2 = Math.sqrt(d2x * d2x + d2y * d2y);
        const rr = Math.min(r, l1 * 0.45, l2 * 0.45);
        const pStart = [curr[0] - (d1x / l1) * rr, curr[1] - (d1y / l1) * rr];
        const pEnd = [curr[0] + (d2x / l2) * rr, curr[1] + (d2y / l2) * rr];
        if (i === 0) cmds.push("M" + qrSvgFmt(pStart[0]) + "," + qrSvgFmt(pStart[1]));
        else cmds.push("L" + qrSvgFmt(pStart[0]) + "," + qrSvgFmt(pStart[1]));
        cmds.push("Q" + qrSvgFmt(curr[0]) + "," + qrSvgFmt(curr[1]) + " " + qrSvgFmt(pEnd[0]) + "," + qrSvgFmt(pEnd[1]));
    }
    cmds.push("z");
    return cmds.join("");
}

function qrSvgBlobCornerCmd(dxIn, dyIn, dxOut, dyOut, rad) {
    const k = QR_SVG_KAPPA;
    const c1x = dxIn * rad * k;
    const c1y = dyIn * rad * k;
    const c2x = dxIn * rad + dxOut * rad * (1 - k);
    const c2y = dyIn * rad + dyOut * rad * (1 - k);
    const ex = dxIn * rad + dxOut * rad;
    const ey = dyIn * rad + dyOut * rad;
    return "c" + qrSvgFmt(c1x) + "," + qrSvgFmt(c1y) + " " + qrSvgFmt(c2x) + "," + qrSvgFmt(c2y) + " " + qrSvgFmt(ex) + "," + qrSvgFmt(ey);
}

function qrSvgTraceLiquidBlobs(grid, size, rOut, rIn) {
    const DIRS = [[1, 0], [0, 1], [-1, 0], [0, -1]];
    const cornerCmds = new Array(32);
    for (let dIn = 0; dIn < 4; dIn++) {
        for (let dOut = 0; dOut < 4; dOut++) {
            const dxIn = DIRS[dIn][0], dyIn = DIRS[dIn][1];
            const dxOut = DIRS[dOut][0], dyOut = DIRS[dOut][1];
            const cross = dxIn * dyOut - dyIn * dxOut;
            if (cross === 0) continue;
            const rad = cross > 0 ? rOut : rIn;
            cornerCmds[(dIn << 2) | dOut] = qrSvgBlobCornerCmd(dxIn, dyIn, dxOut, dyOut, rad);
        }
    }

    const stride = size + 1;
    const head = new Array(stride * stride).fill(-1);
    const edges = [];

    function addEdge(sx, sy, dirIdx) {
        const key = sy * stride + sx;
        const idx = edges.length;
        edges.push({
            sx, sy, dir: dirIdx,
            ex: sx + DIRS[dirIdx][0],
            ey: sy + DIRS[dirIdx][1],
            used: false,
            next: head[key]
        });
        head[key] = idx;
    }

    for (let y = 0; y < size; y++) {
        const row = grid[y];
        const rowUp = y > 0 ? grid[y - 1] : null;
        const rowDn = y + 1 < size ? grid[y + 1] : null;
        for (let x = 0; x < size; x++) {
            if (!row[x]) continue;
            if (!rowUp || !rowUp[x]) addEdge(x, y, 0);
            if (x + 1 >= size || !row[x + 1]) addEdge(x + 1, y, 1);
            if (!rowDn || !rowDn[x]) addEdge(x + 1, y + 1, 2);
            if (x <= 0 || !row[x - 1]) addEdge(x, y + 1, 3);
        }
    }

    const dotSuffix = qrSvgCircleArcSuffix(Math.min(0.45, rOut));
    const singleR = Math.min(0.45, rOut);
    const pathParts = [];

    for (let ei = 0; ei < edges.length; ei++) {
        const startEdge = edges[ei];
        if (startEdge.used) continue;
        const loop = [];
        let curr = startEdge;
        while (curr && !curr.used) {
            curr.used = true;
            loop.push(curr);
            const key = curr.ey * stride + curr.ex;
            const pref0 = (curr.dir + 1) & 3;
            const pref1 = curr.dir;
            const pref2 = (curr.dir + 3) & 3;
            let best0 = null, best1 = null, best2 = null;
            for (let idx = head[key]; idx !== -1; idx = edges[idx].next) {
                const cand = edges[idx];
                if (cand.used) continue;
                if (cand.dir === pref0) { best0 = cand; break; }
                if (cand.dir === pref1 && !best1) best1 = cand;
                else if (cand.dir === pref2 && !best2) best2 = cand;
            }
            curr = best0 || best1 || best2;
        }
        if (loop.length < 4) continue;
        if (loop.length === 4 &&
            loop[0].dir === 0 && loop[1].dir === 1 && loop[2].dir === 2 && loop[3].dir === 3) {
            pathParts.push("M" + qrSvgFmt(loop[0].sx + 0.5 - singleR) + "," + qrSvgFmt(loop[0].sy + 0.5) + dotSuffix);
            continue;
        }
        const verts = [];
        const nEdges = loop.length;
        for (let li = 0; li < nEdges; li++) {
            const prevE = loop[(li + nEdges - 1) % nEdges];
            const currE = loop[li];
            if (prevE.dir !== currE.dir) {
                verts.push({
                    x: currE.sx, y: currE.sy,
                    dIn: prevE.dir, dOut: currE.dir
                });
            }
        }
        const nv = verts.length;
        if (nv < 4) continue;
        const cmds = [];
        let prevOutX = 0;
        let prevOutY = 0;
        for (let vi = 0; vi < nv; vi++) {
            const v = verts[vi];
            const dxIn = DIRS[v.dIn][0], dyIn = DIRS[v.dIn][1];
            const dxOut = DIRS[v.dOut][0], dyOut = DIRS[v.dOut][1];
            const cross = dxIn * dyOut - dyIn * dxOut;
            const rad = cross > 0 ? rOut : rIn;
            const pInX = v.x - dxIn * rad;
            const pInY = v.y - dyIn * rad;
            if (vi === 0) {
                cmds.push("M" + qrSvgFmt(pInX) + "," + qrSvgFmt(pInY));
            } else {
                if (dxIn !== 0) {
                    const dx = pInX - prevOutX;
                    if (Math.abs(dx) > 0.005) cmds.push("h" + qrSvgFmt(dx));
                } else {
                    const dy = pInY - prevOutY;
                    if (Math.abs(dy) > 0.005) cmds.push("v" + qrSvgFmt(dy));
                }
            }
            cmds.push(cornerCmds[(v.dIn << 2) | v.dOut]);
            prevOutX = v.x + dxOut * rad;
            prevOutY = v.y + dyOut * rad;
        }
        cmds.push("z");
        pathParts.push(cmds.join(""));
    }
    return pathParts.join("");
}

function qrSvgRenderBlob(mat, regions, opts) {
    const size = mat.size;
    const colors = opts.colors;
    const quietZone = 4;
    const viewMin = -quietZone;
    const viewSize = size + quietZone * 2;
    const elements = [];
    if (colors.background && colors.background !== "transparent") {
        elements.push('<rect x="' + qrSvgFmt(viewMin) + '" y="' + qrSvgFmt(viewMin) + '" width="' + qrSvgFmt(viewSize) + '" height="' + qrSvgFmt(viewSize) + '" fill="' + colors.background + '"/>');
    }
    const grid = [];
    for (let y = 0; y < size; y++) {
        const row = [];
        const modRow = mat.modules[y];
        const findRow = regions.isFinder[y];
        const alignRow = regions.isAlignment[y];
        for (let x = 0; x < size; x++) {
            row.push(Boolean(modRow[x] && !findRow[x] && !alignRow[x]));
        }
        grid.push(row);
    }
    const pathParts = [];
    const blobPath = qrSvgTraceLiquidBlobs(grid, size, 0.38, 0.34);
    if (blobPath.length > 0)
        pathParts.push(blobPath);

    if (regions.alignCenters.length > 0) {
        for (let ai = 0; ai < regions.alignCenters.length; ai++) {
            const ac = regions.alignCenters[ai];
            pathParts.push(qrSvgRingPath(ac[0] + 0.5, ac[1] + 0.5, 2.46, 1.56));
            pathParts.push(qrSvgCirclePath(ac[0] + 0.5, ac[1] + 0.5, 0.70));
        }
    }

    const finderPositions = [[3.5, 3.5], [size - 3.5, 3.5], [3.5, size - 3.5]];
    for (let fi = 0; fi < finderPositions.length; fi++) {
        const fp = finderPositions[fi];
        pathParts.push(qrSvgRoundedOctagonLoop(fp[0], fp[1], 3.5, 1.65, 0.40, false));
        pathParts.push(qrSvgRoundedOctagonLoop(fp[0], fp[1], 2.5, 1.20, 0.28, true));
        pathParts.push(qrSvgPillPath(fp[0] - 1.5, fp[1] - 1.5, 3.0, 3.0, 0.72));
    }
    if (pathParts.length > 0)
        elements.push('<path d="' + pathParts.join("") + '" fill="' + colors.primary + '"/>');

    return {
        viewBox: qrSvgFmt(viewMin) + " " + qrSvgFmt(viewMin) + " " + qrSvgFmt(viewSize) + " " + qrSvgFmt(viewSize),
        elements
    };
}

function qrSvgRenderSquare(mat, opts) {
    const size = mat.size;
    const colors = opts.colors;
    const quietZone = 4;
    const viewMin = -quietZone;
    const viewSize = size + quietZone * 2;
    const parts = [];
    for (let y = 0; y < size; y++) {
        const row = mat.modules[y];
        let x = 0;
        while (x < size) {
            if (!row[x]) {
                x++;
                continue;
            }
            const x0 = x;
            x++;
            while (x < size && row[x])
                x++;
            const w = x - x0;
            parts.push("M" + x0 + "," + y + "h" + w + "v1h-" + w + "z");
        }
    }
    const elements = [];
    if (colors.background && colors.background !== "transparent") {
        elements.push('<rect x="' + qrSvgFmt(viewMin) + '" y="' + qrSvgFmt(viewMin) + '" width="' + qrSvgFmt(viewSize) + '" height="' + qrSvgFmt(viewSize) + '" fill="' + colors.background + '"/>');
    }
    elements.push('<path d="' + parts.join("") + '" fill="' + colors.primary + '"/>');
    return {
        viewBox: qrSvgFmt(viewMin) + " " + qrSvgFmt(viewMin) + " " + qrSvgFmt(viewSize) + " " + qrSvgFmt(viewSize),
        elements
    };
}

/// Renders a QR visual ({ size, version, rows, style, decoration }) as an SVG string.
function qrSvg(visual, colors = {}, options = {}) {
    if (!visual || (!visual.rows && !visual.modules))
        return "";
    const opts = options || {};
    const rawStyle = opts.style || visual.style || "pixel";
    const style = (rawStyle === "blob" || rawStyle === "classic" || rawStyle === "square") ? rawStyle : "pixel";
    const decoration = opts.decoration !== undefined ? Boolean(opts.decoration) : (visual.decoration !== false);
    const sizePx = opts.sizePx || 800;
    const resolvedColors = qrSvgResolveColors(style, colors);

    const shapesObj = opts.shapes || null;
    let canUseSvgCache = !opts.noCache;
    let shapeTag = "0";
    if (shapesObj) {
        if (_qrLastShapesRef === null)
            _qrLastShapesRef = shapesObj;
        if (shapesObj === _qrLastShapesRef)
            shapeTag = "1";
        else
            canUseSvgCache = false;
    }

    let rowsKey = "";
    if (canUseSvgCache) {
        if (visual.rows) {
            rowsKey = visual.rows.join(",");
        } else {
            const mods = visual.modules;
            const rParts = [];
            for (let i = 0; i < mods.length; i++) {
                const row = mods[i];
                const cParts = [];
                for (let j = 0; j < row.length; j++)
                    cParts.push(row[j] ? "1" : "0");
                rParts.push(cParts.join(""));
            }
            rowsKey = rParts.join(",");
        }
    }

    const cacheKey = canUseSvgCache
        ? (style + "|" + (decoration ? 1 : 0) + "|" + sizePx + "|" + shapeTag + "|" + JSON.stringify(resolvedColors) + "|" + rowsKey)
        : "";
    if (canUseSvgCache && _qrSvgCache[cacheKey] !== undefined)
        return _qrSvgCache[cacheKey];

    const mat = qrSvgNormalizeMatrix(visual);
    const regions = qrSvgBuildRegions(mat.size, mat.version);
    const renderOpts = {
        colors: resolvedColors,
        shapes: shapesObj,
        decoration
    };

    let result;
    if (style === "pixel")
        result = qrSvgRenderPixel(mat, regions, renderOpts);
    else if (style === "blob")
        result = qrSvgRenderBlob(mat, regions, renderOpts);
    else
        result = qrSvgRenderSquare(mat, renderOpts);

    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="' + sizePx + '" height="' + sizePx + '" viewBox="' + result.viewBox + '">' +
        result.elements.join("") +
        "</svg>";

    if (canUseSvgCache) {
        if (_qrSvgCacheOrder.length >= 24) {
            const oldest = _qrSvgCacheOrder.shift();
            delete _qrSvgCache[oldest];
        }
        _qrSvgCache[cacheKey] = svg;
        _qrSvgCacheOrder.push(cacheKey);
    }
    return svg;
}

function toolQrCode(input = "", options = {}) {
    const text = String(input).replace(/\s+$/, "");
    if (text.trim().length === 0)
        return { output: "" };
    const content = qrPayload(text, options.kind ?? "auto");
    if (content.error)
        return { output: "", error: content.error };
    const bytes = Array.from(utf8Encode(content.payload));
    const ecc = options.ecc ?? "M";
    const rawStyle = options.style ?? "pixel";
    const style = (rawStyle === "blob" || rawStyle === "classic") ? rawStyle : "pixel";
    const decoration = options.decoration !== false;
    const qr = qrEncodeBytes(bytes, ecc);
    if (!qr)
        return { output: "", error: `Too long for a QR code at level ${ecc}: ${bytes.length} bytes.` };

    // Half-block text: two module rows per text line, two quiet modules.
    const quiet = 2;
    const dark = (x, y) => x >= 0 && y >= 0 && x < qr.size && y < qr.size && qr.modules[y][x];
    const lines = [];
    for (let y = -quiet; y < qr.size + quiet; y += 2) {
        let row = "";
        for (let x = -quiet; x < qr.size + quiet; x++) {
            const top = dark(x, y), bottom = dark(x, y + 1);
            row += top && bottom ? "█" : top ? "▀" : bottom ? "▄" : " ";
        }
        lines.push(row);
    }
    const labels = { text: "Text", wifi: "Wi-Fi", vcard: "Contact (vCard)" };
    return {
        output: lines.join("\n"),
        meta: {
            content: labels[content.kind],
            version: qr.version,
            modules: `${qr.size}×${qr.size}`,
            ecc,
            bytes: bytes.length,
            payload: content.payload,
            visual: {
                kind: "qr",
                style,
                decoration,
                size: qr.size,
                version: qr.version,
                rows: qr.modules.map(row => row.map(v => v ? "1" : "0").join(""))
            }
        }
    };
}

// ─── 10. Subnets ──────────────────────────────────────────────────────────────
// IPv4 fits a double; IPv6 is kept as eight 16-bit words (no BigInt here).

function parseIpv4(text) {
    const parts = String(text).trim().split(".");
    if (parts.length !== 4)
        return null;
    let value = 0;
    for (const part of parts) {
        if (!/^\d{1,3}$/.test(part) || Number(part) > 255)
            return null;
        value = value * 256 + Number(part);
    }
    return value;
}

function formatIpv4(value) {
    return [24, 16, 8, 0].map(shift => Math.floor(value / Math.pow(2, shift)) % 256).join(".");
}

function ipv4Binary(value) {
    return [24, 16, 8, 0].map(shift => (Math.floor(value / Math.pow(2, shift)) % 256).toString(2).padStart(8, "0")).join(".");
}

function ipv4MaskFromPrefix(prefix) {
    return prefix === 0 ? 0 : (Math.pow(2, 32) - Math.pow(2, 32 - prefix));
}

function ipv4PrefixFromMask(mask) {
    for (let prefix = 0; prefix <= 32; prefix++) {
        if (ipv4MaskFromPrefix(prefix) === mask)
            return prefix;
    }
    return -1;
}

function ipv4Kind(value) {
    const inRange = (base, prefix) => Math.floor(value / Math.pow(2, 32 - prefix)) === Math.floor(parseIpv4(base) / Math.pow(2, 32 - prefix));
    if (inRange("10.0.0.0", 8) || inRange("172.16.0.0", 12) || inRange("192.168.0.0", 16)) return "Private (RFC 1918)";
    if (inRange("127.0.0.0", 8)) return "Loopback";
    if (inRange("169.254.0.0", 16)) return "Link-local";
    if (inRange("100.64.0.0", 10)) return "Carrier-grade NAT (RFC 6598)";
    if (inRange("224.0.0.0", 4)) return "Multicast";
    if (inRange("0.0.0.0", 8)) return "\"This network\"";
    if (inRange("192.0.2.0", 24) || inRange("198.51.100.0", 24) || inRange("203.0.113.0", 24)) return "Documentation";
    if (inRange("240.0.0.0", 4)) return value === 4294967295 ? "Broadcast" : "Reserved";
    return "Public";
}

function parseIpv6(text) {
    let s = String(text).trim().toLowerCase().replace(/^\[|\]$/g, "").replace(/%.*$/, "");
    if (!/^[0-9a-f:.]+$/.test(s) || s.indexOf(":") === -1)
        return null;
    // An IPv4 tail (::ffff:192.0.2.1) becomes the last two words.
    const v4 = s.match(/^(.*:)(\d+\.\d+\.\d+\.\d+)$/);
    if (v4) {
        const value = parseIpv4(v4[2]);
        if (value === null)
            return null;
        s = v4[1] + Math.floor(value / 65536).toString(16) + ":" + (value % 65536).toString(16);
    }
    const halves = s.split("::");
    if (halves.length > 2)
        return null;
    const head = halves[0] ? halves[0].split(":") : [];
    const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
    const missing = 8 - head.length - tail.length;
    if ((halves.length === 1 && missing !== 0) || (halves.length === 2 && missing < 1))
        return null;
    const groups = head.concat(new Array(halves.length === 2 ? missing : 0).fill("0"), tail);
    const words = [];
    for (const group of groups) {
        if (!/^[0-9a-f]{1,4}$/.test(group))
            return null;
        words.push(parseInt(group, 16));
    }
    return words;
}

/// RFC 5952: lowercase, no leading zeros, the longest run of 2+ zero words as ::.
function formatIpv6(words) {
    let bestStart = -1, bestLength = 0;
    for (let i = 0; i < 8;) {
        if (words[i] !== 0) {
            i++;
            continue;
        }
        let j = i;
        while (j < 8 && words[j] === 0)
            j++;
        if (j - i > bestLength && j - i >= 2) {
            bestStart = i;
            bestLength = j - i;
        }
        i = j;
    }
    // IPv4-mapped addresses keep their dotted tail (RFC 5952 §5).
    if (words.slice(0, 5).every(word => word === 0) && words[5] === 0xffff)
        return "::ffff:" + formatIpv4(words[6] * 65536 + words[7]);
    const hex = words.map(word => word.toString(16));
    if (bestStart < 0)
        return hex.join(":");
    return hex.slice(0, bestStart).join(":") + "::" + hex.slice(bestStart + bestLength).join(":");
}

function expandIpv6(words) {
    return words.map(word => word.toString(16).padStart(4, "0")).join(":");
}

function ipv6WithPrefix(words, prefix, fillOnes) {
    return words.map((word, i) => {
        const bits = Math.max(0, Math.min(16, prefix - i * 16));
        const keepMask = bits === 0 ? 0 : (0xffff << (16 - bits)) & 0xffff;
        return fillOnes ? (word & keepMask) | (~keepMask & 0xffff) : word & keepMask;
    });
}

function ipv6Compare(a, b) {
    for (let i = 0; i < 8; i++) {
        if (a[i] !== b[i])
            return a[i] < b[i] ? -1 : 1;
    }
    return 0;
}

function ipv6Kind(words) {
    const within = (base, prefix) => ipv6Compare(ipv6WithPrefix(words, prefix, false), ipv6WithPrefix(parseIpv6(base), prefix, false)) === 0;
    if (words.every(word => word === 0)) return "Unspecified";
    if (within("::1", 128)) return "Loopback";
    if (within("::ffff:0:0", 96)) return "IPv4-mapped";
    if (within("fe80::", 10)) return "Link-local";
    if (within("fc00::", 7)) return "Unique local (ULA)";
    if (within("ff00::", 8)) return "Multicast";
    if (within("2001:db8::", 32)) return "Documentation";
    if (within("64:ff9b::", 96)) return "NAT64";
    if (within("2002::", 16)) return "6to4";
    if (within("2000::", 3)) return "Global unicast";
    return "Reserved";
}

/// 2^n as a grouped decimal string (no BigInt in the QML engine).
function powerOfTwoString(exponent) {
    let digits = [1];
    for (let i = 0; i < exponent; i++) {
        let carry = 0;
        for (let j = 0; j < digits.length; j++) {
            const value = digits[j] * 2 + carry;
            digits[j] = value % 10;
            carry = value >= 10 ? 1 : 0;
        }
        if (carry)
            digits.push(1);
    }
    return digits.reverse().join("").replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function groupThousands(value) {
    return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function toolSubnet(input = "") {
    const lines = String(input).split(/\r?\n/).map(line => line.trim()).filter(line => line.length > 0);
    if (lines.length === 0)
        return { output: "" };
    const head = lines[0];
    const checks = lines.slice(1);
    const out = [];

    const v4 = head.match(/^(\d+\.\d+\.\d+\.\d+)\s*(?:\/\s*(\d+\.\d+\.\d+\.\d+|\d{1,2})|\s+(\d+\.\d+\.\d+\.\d+))?$/);
    if (v4) {
        const address = parseIpv4(v4[1]);
        if (address === null)
            return { output: "", error: "Each IPv4 octet must be 0-255." };
        const maskText = v4[2] ?? v4[3];
        let prefix = 32;
        if (maskText !== undefined) {
            if (maskText.indexOf(".") !== -1) {
                const mask = parseIpv4(maskText);
                prefix = mask === null ? -1 : ipv4PrefixFromMask(mask);
                if (prefix < 0)
                    return { output: "", error: "Not a valid netmask: " + maskText };
            } else {
                prefix = Number(maskText);
            }
        }
        if (prefix > 32)
            return { output: "", error: "An IPv4 prefix is 0-32." };
        const mask = ipv4MaskFromPrefix(prefix);
        const block = Math.pow(2, 32 - prefix);
        const network = Math.floor(address / block) * block;
        const broadcast = network + block - 1;
        // RFC 3021: /31 links use both addresses; /32 is a single host.
        const first = prefix >= 31 ? network : network + 1;
        const last = prefix >= 31 ? broadcast : broadcast - 1;
        const usable = prefix === 32 ? 1 : (prefix === 31 ? 2 : block - 2);
        out.push(`Address     ${formatIpv4(address)}/${prefix}`);
        out.push(`Netmask     ${formatIpv4(mask)}`);
        out.push(`Wildcard    ${formatIpv4(Math.pow(2, 32) - 1 - mask)}`);
        out.push(`Network     ${formatIpv4(network)}`);
        if (prefix < 31)
            out.push(`Broadcast   ${formatIpv4(broadcast)}`);
        out.push(`Hosts       ${formatIpv4(first)} – ${formatIpv4(last)}`);
        out.push(`Usable      ${groupThousands(usable)}${prefix < 31 ? ` (of ${groupThousands(block)} addresses)` : ""}`);
        out.push(`Type        ${ipv4Kind(address)}`);
        out.push("", `Binary      ${ipv4Binary(address)}`, `Mask        ${ipv4Binary(mask)}`);
        if (checks.length > 0) {
            out.push("", `In ${formatIpv4(network)}/${prefix}?`);
            for (const check of checks) {
                const value = parseIpv4(check);
                out.push(value === null
                    ? `  ?  ${check}   not an IPv4 address`
                    : `  ${value >= network && value <= broadcast ? "✓" : "✗"}  ${formatIpv4(value)}`);
            }
        }
        return { output: out.join("\n"), meta: { prefix, network: formatIpv4(network), usable } };
    }

    const v6 = head.match(/^([^\s/]+)\s*(?:\/\s*(\d{1,3}))?$/);
    const words = v6 ? parseIpv6(v6[1]) : null;
    if (!words)
        return { output: "", error: "Enter an IPv4 or IPv6 address with an optional prefix: 192.168.1.10/24, 10.0.0.1 255.255.0.0 or 2001:db8::1/64. Extra lines are checked for membership." };
    const prefix = v6[2] !== undefined ? Number(v6[2]) : 128;
    if (prefix > 128)
        return { output: "", error: "An IPv6 prefix is 0-128." };
    const network = ipv6WithPrefix(words, prefix, false);
    const last = ipv6WithPrefix(words, prefix, true);
    out.push(`Address     ${formatIpv6(words)}/${prefix}`);
    out.push(`Expanded    ${expandIpv6(words)}`);
    out.push(`Network     ${formatIpv6(network)}/${prefix}`);
    out.push(`First       ${formatIpv6(network)}`);
    out.push(`Last        ${formatIpv6(last)}`);
    out.push(`Addresses   2^${128 - prefix} = ${powerOfTwoString(128 - prefix)}`);
    if (prefix <= 64)
        out.push(`/64 subnets 2^${64 - prefix} = ${powerOfTwoString(64 - prefix)}`);
    out.push(`Type        ${ipv6Kind(words)}`);
    if (checks.length > 0) {
        out.push("", `In ${formatIpv6(network)}/${prefix}?`);
        for (const check of checks) {
            const value = parseIpv6(check);
            out.push(value === null
                ? `  ?  ${check}   not an IPv6 address`
                : `  ${ipv6Compare(value, network) >= 0 && ipv6Compare(value, last) <= 0 ? "✓" : "✗"}  ${formatIpv6(value)}`);
        }
    }
    return { output: out.join("\n"), meta: { prefix, network: formatIpv6(network) } };
}

// ─── 11. Units ────────────────────────────────────────────────────────────────

// Each dimension: [symbol, factor to the base unit, aliases]. Temperature and
// screen units are computed instead (offsets, DPI and root font size).
const UNIT_DIMENSIONS = [
    { id: "length", label: "Length", units: [
        ["nm", 1e-9, ["nanometer", "nanometers", "nanometro", "nanometros"]],
        ["µm", 1e-6, ["um", "micron", "microns", "micrometer", "micrometers", "micrometro"]],
        ["mm", 1e-3, ["millimeter", "millimeters", "milimetro", "milimetros"]],
        ["cm", 1e-2, ["centimeter", "centimeters", "centimetro", "centimetros"]],
        ["m", 1, ["meter", "meters", "metre", "metres", "metro", "metros"]],
        ["km", 1e3, ["kilometer", "kilometers", "kilometre", "quilometro", "quilometros", "kms"]],
        ["in", 0.0254, ["inch", "inches", "\"", "polegada", "polegadas", "pol"]],
        ["ft", 0.3048, ["foot", "feet", "'", "pe", "pes"]],
        ["yd", 0.9144, ["yard", "yards", "jarda", "jardas"]],
        ["mi", 1609.344, ["mile", "miles", "milha", "milhas"]],
        ["nmi", 1852, ["nautical mile", "nautical miles", "milha nautica", "milhas nauticas"]],
        ["au", 149597870700, ["astronomical unit", "ua"]],
        ["ly", 9460730472580800, ["light year", "light years", "light-year", "ano luz", "anos luz"]]
    ] },
    { id: "mass", label: "Mass", units: [
        ["mg", 1e-6, ["milligram", "milligrams", "miligrama", "miligramas"]],
        ["g", 1e-3, ["gram", "grams", "grama", "gramas"]],
        ["kg", 1, ["kilogram", "kilograms", "kilo", "kilos", "quilo", "quilos", "quilograma", "quilogramas"]],
        ["t", 1e3, ["tonne", "tonnes", "metric ton", "tonelada", "toneladas"]],
        ["ct", 2e-4, ["carat", "carats", "quilate", "quilates"]],
        ["oz", 0.028349523125, ["ounce", "ounces", "onca", "oncas"]],
        ["lb", 0.45359237, ["lbs", "pound", "pounds", "libra", "libras"]],
        ["st", 6.35029318, ["stone", "stones"]],
        ["short ton", 907.18474, ["us ton", "ton"]]
    ] },
    { id: "temperature", label: "Temperature", units: [
        ["°C", null, ["c", "celsius", "degc", "ºc", "graus", "grau"]],
        ["°F", null, ["f", "fahrenheit", "degf", "ºf"]],
        ["K", null, ["k", "kelvin", "kelvins"]],
        ["°R", null, ["rankine", "ºr"]]
    ] },
    { id: "area", label: "Area", units: [
        ["mm²", 1e-6, ["mm2", "sq mm"]],
        ["cm²", 1e-4, ["cm2", "sq cm"]],
        ["m²", 1, ["m2", "sq m", "sqm", "square meter", "square meters", "metro quadrado", "metros quadrados"]],
        ["ha", 1e4, ["hectare", "hectares"]],
        ["km²", 1e6, ["km2", "sq km", "square kilometer", "square kilometers"]],
        ["in²", 0.00064516, ["in2", "sq in", "square inch", "square inches"]],
        ["ft²", 0.09290304, ["ft2", "sq ft", "sqft", "square foot", "square feet"]],
        ["yd²", 0.83612736, ["yd2", "sq yd", "square yard", "square yards"]],
        ["acre", 4046.8564224, ["acres", "ac"]],
        ["mi²", 2589988.110336, ["mi2", "sq mi", "square mile", "square miles"]],
        ["alqueire SP", 24200, ["alqueire", "alqueires", "alqueire paulista"]],
        ["alqueire MG", 48400, ["alqueire mineiro", "alqueire goiano"]]
    ] },
    { id: "volume", label: "Volume", units: [
        ["ml", 1e-3, ["mL", "milliliter", "milliliters", "mililitro", "mililitros", "cc"]],
        ["cl", 1e-2, ["centiliter", "centiliters"]],
        ["dl", 1e-1, ["deciliter", "deciliters"]],
        ["l", 1, ["L", "liter", "liters", "litre", "litres", "litro", "litros"]],
        ["m³", 1e3, ["m3", "cubic meter", "cubic meters", "metro cubico", "metros cubicos"]],
        ["cm³", 1e-3, ["cm3", "cubic centimeter"]],
        ["tsp", 0.00492892159375, ["teaspoon", "teaspoons", "colher de cha"]],
        ["tbsp", 0.01478676478125, ["tablespoon", "tablespoons", "colher de sopa"]],
        ["fl oz", 0.0295735295625, ["floz", "fluid ounce", "fluid ounces"]],
        ["cup", 0.2365882365, ["cups", "xicara", "xicaras"]],
        ["pint", 0.473176473, ["pints", "us pint"]],
        ["qt", 0.946352946, ["quart", "quarts"]],
        ["gal", 3.785411784, ["gallon", "gallons", "us gal", "galao", "galoes"]],
        ["imp gal", 4.54609, ["imperial gallon", "uk gallon"]],
        ["in³", 0.016387064, ["in3", "cubic inch", "cubic inches"]],
        ["ft³", 28.316846592, ["ft3", "cubic foot", "cubic feet"]]
    ] },
    { id: "speed", label: "Speed", units: [
        ["m/s", 1, ["mps", "meters per second"]],
        ["km/h", 1 / 3.6, ["kmh", "kph", "kmph", "km per hour"]],
        ["mph", 0.44704, ["mi/h", "miles per hour"]],
        ["kn", 1852 / 3600, ["knot", "knots"]],
        ["ft/s", 0.3048, ["fps", "feet per second"]],
        ["Mach", 343, ["mach"]],
        ["c", 299792458, ["speed of light"]]
    ] },
    { id: "energy", label: "Energy", units: [
        ["J", 1, ["joule", "joules"]],
        ["kJ", 1e3, ["kilojoule", "kilojoules"]],
        ["MJ", 1e6, ["megajoule", "megajoules"]],
        ["cal", 4.184, ["calorie", "calories", "caloria", "calorias"]],
        ["kcal", 4184, ["Cal", "kilocalorie", "kilocalories", "quilocaloria", "quilocalorias"]],
        ["Wh", 3600, ["watt hour", "watt hours"]],
        ["kWh", 3.6e6, ["kilowatt hour", "kilowatt hours"]],
        ["BTU", 1055.05585262, ["btu", "btus"]],
        ["eV", 1.602176634e-19, ["electronvolt", "electronvolts"]]
    ] },
    { id: "power", label: "Power", units: [
        ["W", 1, ["watt", "watts"]],
        ["kW", 1e3, ["kilowatt", "kilowatts"]],
        ["MW", 1e6, ["megawatt", "megawatts"]],
        ["hp", 745.69987158227022, ["horsepower", "bhp"]],
        ["cv", 735.49875, ["ps", "metric horsepower", "cavalo", "cavalos"]],
        ["BTU/h", 0.29307107017, ["btuh", "btu/hr"]]
    ] },
    { id: "pressure", label: "Pressure", units: [
        ["Pa", 1, ["pascal", "pascals"]],
        ["hPa", 100, ["hectopascal", "hectopascals"]],
        ["kPa", 1e3, ["kilopascal", "kilopascals"]],
        ["MPa", 1e6, ["megapascal", "megapascals"]],
        ["bar", 1e5, ["bars"]],
        ["mbar", 100, ["millibar", "millibars"]],
        ["atm", 101325, ["atmosphere", "atmospheres", "atmosfera", "atmosferas"]],
        ["psi", 6894.757293168361, ["lbf/in2", "lb/in2"]],
        ["mmHg", 133.322387415, ["mmhg", "torr"]],
        ["inHg", 3386.389, ["inhg"]]
    ] },
    { id: "time", label: "Time", units: [
        ["ns", 1e-9, ["nanosecond", "nanoseconds"]],
        ["µs", 1e-6, ["us", "microsecond", "microseconds"]],
        ["ms", 1e-3, ["millisecond", "milliseconds", "milissegundo", "milissegundos"]],
        ["s", 1, ["sec", "secs", "second", "seconds", "segundo", "segundos"]],
        ["min", 60, ["mins", "minute", "minutes", "minuto", "minutos"]],
        ["h", 3600, ["hr", "hrs", "hour", "hours", "hora", "horas"]],
        ["d", 86400, ["day", "days", "dia", "dias"]],
        ["wk", 604800, ["week", "weeks", "semana", "semanas"]],
        ["mo", 2629746, ["month", "months", "mes", "meses"]],
        ["yr", 31556952, ["y", "year", "years", "ano", "anos"]]
    ] },
    { id: "screen", label: "Screen & type", units: [
        ["px", null, ["pixel", "pixels"]],
        ["rem", null, []],
        ["em", null, []],
        ["pt", null, ["point", "points", "ponto", "pontos"]],
        ["pc", null, ["pica", "picas"]],
        ["dp", null, ["dip"]]
    ] }
];

function normalizeUnitName(text) {
    return String(text).trim()
        .normalize("NFD").replace(/[̀-ͯ]/g, "")
        .replace(/\s+/g, " ")
        .replace(/\^2/g, "2").replace(/\^3/g, "3")
        .replace(/^deg\s*/i, "deg");
}

/// Finds a unit by symbol (case-sensitive first: Cal ≠ cal, MW ≠ mW) or alias.
function findUnit(text) {
    const raw = String(text).trim();
    if (raw.length === 0)
        return null;
    const plain = normalizeUnitName(raw);
    const lower = plain.toLowerCase();
    for (const dim of UNIT_DIMENSIONS) {
        for (const unit of dim.units) {
            if (unit[0] === raw || normalizeUnitName(unit[0]) === plain || unit[2].indexOf(raw) !== -1)
                return { dim, unit };
        }
    }
    for (const dim of UNIT_DIMENSIONS) {
        for (const unit of dim.units) {
            if (normalizeUnitName(unit[0]).toLowerCase() === lower || unit[2].some(alias => normalizeUnitName(alias).toLowerCase() === lower))
                return { dim, unit };
        }
    }
    return null;
}

function parseLooseNumber(text) {
    let s = String(text).trim().replace(/\s|_/g, "");
    // "1,5" is a decimal comma; "1,500" and "1.234,5" follow their pattern.
    if (/^-?\d{1,3}(\.\d{3})+,\d+$/.test(s))
        s = s.replace(/\./g, "").replace(",", ".");
    else if (/^-?\d+,\d{1,2}$/.test(s) || /^-?\d+,\d{4,}$/.test(s))
        s = s.replace(",", ".");
    else
        s = s.replace(/,/g, "");
    if (!/^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i.test(s))
        return NaN;
    return Number(s);
}

function formatUnitNumber(value) {
    if (!isFinite(value))
        return String(value);
    if (value === 0)
        return "0";
    const abs = Math.abs(value);
    if (abs >= 1e15 || abs < 1e-6)
        return value.toExponential(6).replace(/\.?0+e/, "e");
    const text = Number(value.toPrecision(10)).toString();
    if (text.indexOf("e") !== -1)
        return value.toExponential(6).replace(/\.?0+e/, "e");
    const parts = text.split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parts.join(".");
}

function temperatureToKelvin(value, symbol) {
    switch (symbol) {
    case "°C": return value + 273.15;
    case "°F": return (value - 32) * 5 / 9 + 273.15;
    case "°R": return value * 5 / 9;
    default: return value;
    }
}

function kelvinToTemperature(kelvin, symbol) {
    switch (symbol) {
    case "°C": return kelvin - 273.15;
    case "°F": return (kelvin - 273.15) * 9 / 5 + 32;
    case "°R": return kelvin * 9 / 5;
    default: return kelvin;
    }
}

/// Screen units go through CSS pixels: 1in = dpi px, 1pt = 1/72 in, 1rem = root font size.
function screenToPx(value, symbol, dpi, rootSize) {
    switch (symbol) {
    case "rem": case "em": return value * rootSize;
    case "pt": return value * dpi / 72;
    case "pc": return value * dpi / 6;
    case "dp": return value * dpi / 160;
    default: return value;
    }
}

function pxToScreen(px, symbol, dpi, rootSize) {
    switch (symbol) {
    case "rem": case "em": return px / rootSize;
    case "pt": return px * 72 / dpi;
    case "pc": return px * 6 / dpi;
    case "dp": return px * 160 / dpi;
    default: return px;
    }
}

function toolUnitConverter(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    const match = text.match(/^([-+]?[\d.,_\s]*\d(?:e[-+]?\d+)?|[-+]?\.\d+)\s*(.+?)(?:\s+(?:to|in|em|para|->|→|=)\s+(.+))?$/i);
    if (!match)
        return { output: "", error: "Enter a value and a unit, such as 10 km, 72 °F, 16px or 5 lb to kg." };
    const value = parseLooseNumber(match[1]);
    if (!isFinite(value))
        return { output: "", error: "Could not read the number: " + match[1] };
    const from = findUnit(match[2]);
    if (!from)
        return { output: "", error: "Unknown unit: " + match[2] };
    let target = null;
    if (match[3]) {
        target = findUnit(match[3]);
        if (!target)
            return { output: "", error: "Unknown unit: " + match[3] };
        if (target.dim.id !== from.dim.id && !(from.dim.id === "screen" && target.dim.id === "length") && !(from.dim.id === "length" && target.dim.id === "screen"))
            return { output: "", error: `${from.unit[0]} (${from.dim.label.toLowerCase()}) does not convert to ${target.unit[0]} (${target.dim.label.toLowerCase()}).` };
    }

    const dpi = Number(options.dpi ?? 96);
    const rootSize = Number(options.rootSize ?? 16);
    const rows = [];
    let label = from.dim.label;
    if (from.dim.id === "temperature") {
        const kelvin = temperatureToKelvin(value, from.unit[0]);
        if (kelvin < -1e-9)
            return { output: "", error: "That is below absolute zero." };
        for (const unit of from.dim.units)
            rows.push([unit[0], kelvinToTemperature(kelvin, unit[0])]);
    } else if (from.dim.id === "screen" || (from.dim.id === "length" && target && target.dim.id === "screen")) {
        // Screen units also show their physical size at the chosen DPI.
        const px = from.dim.id === "screen"
            ? screenToPx(value, from.unit[0], dpi, rootSize)
            : value * from.unit[1] / 0.0254 * dpi;
        label = `Screen & type (${dpi} DPI, 1rem = ${rootSize}px)`;
        for (const unit of UNIT_DIMENSIONS.find(dim => dim.id === "screen").units)
            rows.push([unit[0], pxToScreen(px, unit[0], dpi, rootSize)]);
        const metres = px / dpi * 0.0254;
        for (const symbol of ["mm", "cm", "in"])
            rows.push([symbol, metres / UNIT_DIMENSIONS[0].units.find(unit => unit[0] === symbol)[1]]);
    } else {
        const base = value * from.unit[1];
        for (const unit of from.dim.units)
            rows.push([unit[0], base / unit[1]]);
    }

    const out = [];
    if (target) {
        const hit = rows.find(row => row[0] === target.unit[0]);
        if (hit)
            out.push(`${formatUnitNumber(value)} ${from.unit[0]} = ${formatUnitNumber(hit[1])} ${hit[0]}`, "");
    }
    out.push(label);
    const width = Math.max(...rows.map(row => row[0].length));
    for (const row of rows)
        out.push(`  ${row[0].padEnd(width)}  ${formatUnitNumber(row[1])}${row[0] === from.unit[0] ? "   ←" : ""}`);
    if (from.unit[0] === "Mach")
        out.push("", "Mach 1 is taken as 343 m/s (dry air at 20 °C).");
    if (from.unit[0] === "mo" || from.unit[0] === "yr")
        out.push("", "A month is 1/12 of a mean Gregorian year (365.2425 days).");
    return { output: out.join("\n"), meta: { dimension: from.dim.label } };
}

// ─── 12. Time zones and dates ─────────────────────────────────────────────────
// The QML engine has no Intl and ignores toLocaleString's timeZone, so zones
// carry their standard offset and a daylight-saving rule. Rules are the ones
// in force since 2023; "Local" always follows the system clock instead.

const DAY_MS = 86400000;
const WEEKDAY_LONG = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

// [label, IANA id, standard offset (minutes), DST rule, aliases]
const TIME_ZONES = [
    ["UTC", "Etc/UTC", 0, "", ["utc", "gmt", "z", "zulu"]],
    ["Honolulu", "Pacific/Honolulu", -600, "", ["hawaii", "hst"]],
    ["Anchorage", "America/Anchorage", -540, "us", ["alaska", "akst", "akdt"]],
    ["Los Angeles", "America/Los_Angeles", -480, "us", ["la", "san francisco", "seattle", "vancouver", "pacific", "pst", "pdt", "pt", "california", "silicon valley"]],
    ["Denver", "America/Denver", -420, "us", ["mountain", "mst", "mdt", "calgary"]],
    ["Phoenix", "America/Phoenix", -420, "", ["arizona"]],
    ["Chicago", "America/Chicago", -360, "us", ["central", "cst", "cdt", "dallas", "houston", "austin", "winnipeg"]],
    ["Mexico City", "America/Mexico_City", -360, "", ["mexico", "cdmx", "ciudad de mexico", "cidade do mexico"]],
    ["New York", "America/New_York", -300, "us", ["nyc", "ny", "eastern", "est", "edt", "et", "boston", "washington", "miami", "atlanta", "toronto", "montreal", "nova york", "nova iorque"]],
    ["Bogotá", "America/Bogota", -300, "", ["bogota", "colombia"]],
    ["Lima", "America/Lima", -300, "", ["peru"]],
    ["Rio Branco", "America/Rio_Branco", -300, "", ["acre", "act"]],
    ["Manaus", "America/Manaus", -240, "", ["amazonas", "amt", "cuiaba", "porto velho", "boa vista"]],
    ["Caracas", "America/Caracas", -240, "", ["venezuela"]],
    ["Santiago", "America/Santiago", -240, "cl", ["chile"]],
    ["Halifax", "America/Halifax", -240, "us", ["atlantic", "ast", "adt"]],
    ["St. John's", "America/St_Johns", -210, "us", ["st johns", "newfoundland", "nst", "ndt"]],
    ["São Paulo", "America/Sao_Paulo", -180, "", ["sao paulo", "sp", "brasilia", "rio", "rio de janeiro", "brazil", "brasil", "brt", "belo horizonte", "curitiba", "porto alegre", "salvador", "recife", "fortaleza", "belem"]],
    ["Buenos Aires", "America/Argentina/Buenos_Aires", -180, "", ["argentina", "art"]],
    ["Montevideo", "America/Montevideo", -180, "", ["uruguay", "uruguai"]],
    ["Noronha", "America/Noronha", -120, "", ["fernando de noronha", "fnt"]],
    ["Azores", "Atlantic/Azores", -60, "eu", ["acores", "acores"]],
    ["Reykjavík", "Atlantic/Reykjavik", 0, "", ["reykjavik", "iceland", "islandia"]],
    ["London", "Europe/London", 0, "eu", ["uk", "gmt", "bst", "londres", "edinburgh", "manchester"]],
    ["Dublin", "Europe/Dublin", 0, "eu", ["ireland", "irlanda"]],
    ["Lisbon", "Europe/Lisbon", 0, "eu", ["lisboa", "portugal", "porto", "wet", "west"]],
    ["Lagos", "Africa/Lagos", 60, "", ["nigeria", "wat"]],
    ["Berlin", "Europe/Berlin", 60, "eu", ["berlim", "germany", "alemanha", "cet", "cest", "munich", "frankfurt", "hamburg"]],
    ["Paris", "Europe/Paris", 60, "eu", ["france", "franca"]],
    ["Madrid", "Europe/Madrid", 60, "eu", ["spain", "espanha", "barcelona"]],
    ["Rome", "Europe/Rome", 60, "eu", ["roma", "italy", "italia", "milan", "milao"]],
    ["Amsterdam", "Europe/Amsterdam", 60, "eu", ["amsterda", "netherlands", "holanda"]],
    ["Brussels", "Europe/Brussels", 60, "eu", ["bruxelas", "belgium"]],
    ["Zurich", "Europe/Zurich", 60, "eu", ["zurique", "geneva", "switzerland", "suica"]],
    ["Vienna", "Europe/Vienna", 60, "eu", ["viena", "austria"]],
    ["Prague", "Europe/Prague", 60, "eu", ["praga", "czechia"]],
    ["Warsaw", "Europe/Warsaw", 60, "eu", ["varsovia", "poland", "polonia"]],
    ["Stockholm", "Europe/Stockholm", 60, "eu", ["estocolmo", "sweden", "suecia"]],
    ["Oslo", "Europe/Oslo", 60, "eu", ["norway", "noruega"]],
    ["Copenhagen", "Europe/Copenhagen", 60, "eu", ["copenhague", "denmark", "dinamarca"]],
    ["Athens", "Europe/Athens", 120, "eu", ["atenas", "greece", "grecia", "eet", "eest"]],
    ["Helsinki", "Europe/Helsinki", 120, "eu", ["finland", "finlandia"]],
    ["Kyiv", "Europe/Kyiv", 120, "eu", ["kiev", "ukraine", "ucrania"]],
    ["Bucharest", "Europe/Bucharest", 120, "eu", ["bucareste", "romania"]],
    ["Cairo", "Africa/Cairo", 120, "eg", ["egypt", "egito"]],
    ["Johannesburg", "Africa/Johannesburg", 120, "", ["south africa", "cape town", "joanesburgo", "sast"]],
    ["Jerusalem", "Asia/Jerusalem", 120, "il", ["tel aviv", "israel"]],
    ["Istanbul", "Europe/Istanbul", 180, "", ["istambul", "turkey", "turquia", "ankara"]],
    ["Moscow", "Europe/Moscow", 180, "", ["moscou", "russia", "msk", "saint petersburg"]],
    ["Nairobi", "Africa/Nairobi", 180, "", ["kenya", "quenia", "eat"]],
    ["Riyadh", "Asia/Riyadh", 180, "", ["saudi arabia", "riad", "doha", "qatar"]],
    ["Tehran", "Asia/Tehran", 210, "", ["teera", "iran"]],
    ["Dubai", "Asia/Dubai", 240, "", ["uae", "abu dhabi", "emirados", "gst"]],
    ["Karachi", "Asia/Karachi", 300, "", ["pakistan", "paquistao", "pkt"]],
    ["Mumbai", "Asia/Kolkata", 330, "", ["india", "delhi", "new delhi", "kolkata", "calcutta", "bangalore", "bengaluru", "chennai", "hyderabad", "ist"]],
    ["Kathmandu", "Asia/Kathmandu", 345, "", ["nepal"]],
    ["Dhaka", "Asia/Dhaka", 360, "", ["bangladesh"]],
    ["Bangkok", "Asia/Bangkok", 420, "", ["banguecoque", "thailand", "tailandia", "hanoi", "ho chi minh", "vietnam"]],
    ["Jakarta", "Asia/Jakarta", 420, "", ["indonesia", "wib"]],
    ["Singapore", "Asia/Singapore", 480, "", ["singapura", "sgt", "kuala lumpur", "malaysia"]],
    ["Hong Kong", "Asia/Hong_Kong", 480, "", ["hk", "hkt"]],
    ["Shanghai", "Asia/Shanghai", 480, "", ["beijing", "pequim", "china", "shenzhen", "xangai"]],
    ["Taipei", "Asia/Taipei", 480, "", ["taiwan"]],
    ["Manila", "Asia/Manila", 480, "", ["philippines", "filipinas"]],
    ["Perth", "Australia/Perth", 480, "", ["awst", "western australia"]],
    ["Seoul", "Asia/Seoul", 540, "", ["seul", "korea", "coreia", "kst"]],
    ["Tokyo", "Asia/Tokyo", 540, "", ["toquio", "japan", "japao", "jst", "osaka"]],
    ["Darwin", "Australia/Darwin", 570, "", ["acst"]],
    ["Adelaide", "Australia/Adelaide", 570, "au", ["acdt"]],
    ["Brisbane", "Australia/Brisbane", 600, "", ["queensland"]],
    ["Sydney", "Australia/Sydney", 600, "au", ["australia", "melbourne", "canberra", "hobart", "aest", "aedt"]],
    ["Auckland", "Pacific/Auckland", 720, "nz", ["new zealand", "nova zelandia", "wellington", "nzst", "nzdt"]]
];

function utcDayOfMonth(year, month, weekday, nth) {
    // nth > 0: nth weekday of the month; nth = -1: the last one.
    if (nth > 0) {
        const firstWeekday = new Date(Date.UTC(year, month, 1)).getUTCDay();
        return 1 + (weekday - firstWeekday + 7) % 7 + (nth - 1) * 7;
    }
    const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
    const lastWeekday = new Date(Date.UTC(year, month, lastDay)).getUTCDay();
    return lastDay - (lastWeekday - weekday + 7) % 7;
}

/// Whether daylight saving is on at instant t (ms UTC) for a rule.
function dstActive(rule, std, t) {
    if (!rule)
        return false;
    const year = new Date(t).getUTCFullYear();
    const at = (month, day, hour, offset) => Date.UTC(year, month, day, hour) - offset * 60000;
    let start, end;
    switch (rule) {
    case "eu": // last Sunday of March to last Sunday of October, 01:00 UTC
        start = Date.UTC(year, 2, utcDayOfMonth(year, 2, 0, -1), 1);
        end = Date.UTC(year, 9, utcDayOfMonth(year, 9, 0, -1), 1);
        return t >= start && t < end;
    case "us": // second Sunday of March to first Sunday of November, 02:00 local
        start = at(2, utcDayOfMonth(year, 2, 0, 2), 2, std);
        end = at(10, utcDayOfMonth(year, 10, 0, 1), 2, std + 60);
        return t >= start && t < end;
    case "il": // Friday before the last Sunday of March to the last Sunday of October
        start = at(2, utcDayOfMonth(year, 2, 0, -1) - 2, 2, std);
        end = at(9, utcDayOfMonth(year, 9, 0, -1), 2, std + 60);
        return t >= start && t < end;
    case "eg": // last Friday of April to the end of the last Thursday of October
        start = at(3, utcDayOfMonth(year, 3, 5, -1), 0, std);
        end = at(9, utcDayOfMonth(year, 9, 4, -1) + 1, 0, std + 60);
        return t >= start && t < end;
    case "au": // southern: first Sunday of October to first Sunday of April
        start = at(9, utcDayOfMonth(year, 9, 0, 1), 2, std);
        end = at(3, utcDayOfMonth(year, 3, 0, 1), 3, std + 60);
        return t >= start || t < end;
    case "nz": // last Sunday of September to first Sunday of April
        start = at(8, utcDayOfMonth(year, 8, 0, -1), 2, std);
        end = at(3, utcDayOfMonth(year, 3, 0, 1), 3, std + 60);
        return t >= start || t < end;
    case "cl": // first Sunday of September 04:00 UTC to first Sunday of April 03:00 UTC
        start = Date.UTC(year, 8, utcDayOfMonth(year, 8, 0, 1), 4);
        end = Date.UTC(year, 3, utcDayOfMonth(year, 3, 0, 1), 3);
        return t >= start || t < end;
    default:
        return false;
    }
}

function normalizePlace(text) {
    return String(text).trim().toLowerCase()
        .normalize("NFD").replace(/[̀-ͯ]/g, "")
        .replace(/[_.]+/g, " ").replace(/\s+/g, " ");
}

/// A zone: { label, offsetAt(t) -> minutes, dst(t) -> bool }.
function findTimeZone(text) {
    const raw = String(text).trim();
    const key = normalizePlace(raw);
    if (key === "" || key === "local" || key === "here" || key === "aqui") {
        return {
            label: "Local",
            offsetAt: t => -new Date(t).getTimezoneOffset(),
            dst: t => {
                const year = new Date(t).getFullYear();
                const standard = Math.max(new Date(year, 0, 1).getTimezoneOffset(), new Date(year, 6, 1).getTimezoneOffset());
                return new Date(t).getTimezoneOffset() < standard;
            }
        };
    }
    const fixed = key.match(/^(?:utc|gmt)?\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?$/);
    if (fixed && (/^(utc|gmt)/.test(key) || /^[+-]/.test(key))) {
        const minutes = (fixed[1] === "-" ? -1 : 1) * (Number(fixed[2]) * 60 + Number(fixed[3] ?? 0));
        if (Math.abs(minutes) > 14 * 60)
            return null;
        return { label: "UTC" + formatUtcOffset(minutes).slice(3), offsetAt: () => minutes, dst: () => false };
    }
    for (const zone of TIME_ZONES) {
        const id = normalizePlace(zone[1]);
        if (normalizePlace(zone[0]) === key || id === key || id.split("/").pop() === key || zone[4].indexOf(key) !== -1) {
            return {
                label: zone[0],
                offsetAt: t => zone[2] + (dstActive(zone[3], zone[2], t) ? 60 : 0),
                dst: t => dstActive(zone[3], zone[2], t)
            };
        }
    }
    return null;
}

function formatUtcOffset(minutes) {
    const sign = minutes < 0 ? "−" : "+";
    const abs = Math.abs(minutes);
    const mins = abs % 60;
    return "UTC" + sign + Math.floor(abs / 60) + (mins ? ":" + String(mins).padStart(2, "0") : "");
}

/// The UTC instant of a wall-clock time in a zone (ms since epoch fields as UTC).
function wallTimeToUtc(zone, wallMs) {
    let utc = wallMs - zone.offsetAt(wallMs) * 60000;
    utc = wallMs - zone.offsetAt(utc) * 60000;
    return utc;
}

function pad2(n) {
    return String(n).padStart(2, "0");
}

function formatWall(ms, withYear) {
    const d = new Date(ms);
    return `${WEEKDAY_LABELS[d.getUTCDay()]} ${pad2(d.getUTCDate())} ${MONTH_LABELS[d.getUTCMonth()]}${withYear ? " " + d.getUTCFullYear() : ""}`;
}

function formatClock(ms) {
    const d = new Date(ms);
    return `${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}`;
}

/// Pulls "HH:MM", "9am", "21h30" or "now" off a string: { minutes, rest }.
function takeClockTime(text) {
    const now = text.match(/(^|\s)(now|agora)(\s|$)/i);
    if (now)
        return { now: true, rest: text.replace(now[0], " ") };
    const match = text.match(/(^|\s)(\d{1,2})(?:[:h](\d{2}))?\s*(am|pm|h)?(?=\s|$)/i);
    if (!match || (match[3] === undefined && match[4] === undefined))
        return { minutes: null, rest: text };
    let hours = Number(match[2]);
    const minutes = Number(match[3] ?? 0);
    const suffix = (match[4] ?? "").toLowerCase();
    if (suffix === "pm" && hours < 12) hours += 12;
    if (suffix === "am" && hours === 12) hours = 0;
    if (hours > 23 || minutes > 59)
        return { minutes: null, rest: text, error: "Not a valid time: " + match[0].trim() };
    return { minutes: hours * 60 + minutes, rest: text.replace(match[0], " ") };
}

/// Pulls a calendar date off a string: { year, month (0-11), day, rest }.
function takeCalendarDate(text, order = "dmy") {
    let match = text.match(/(^|\s)(\d{4})-(\d{1,2})-(\d{1,2})(?=\s|$|T)/);
    if (match)
        return { year: Number(match[2]), month: Number(match[3]) - 1, day: Number(match[4]), rest: text.replace(match[0], " ") };
    match = text.match(/(^|\s)(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?(?=\s|$)/);
    if (match) {
        const a = Number(match[2]), b = Number(match[3]);
        let year = match[4] !== undefined ? Number(match[4]) : null;
        if (year !== null && year < 100)
            year += 2000;
        const dmy = order !== "mdy";
        return { year, month: (dmy ? b : a) - 1, day: dmy ? a : b, rest: text.replace(match[0], " ") };
    }
    return null;
}

function validCalendarDate(year, month, day) {
    const d = new Date(Date.UTC(year, month, day));
    return d.getUTCFullYear() === year && d.getUTCMonth() === month && d.getUTCDate() === day;
}

function toolTimeZones(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    const clock = takeClockTime(text);
    if (clock.error)
        return { output: "", error: clock.error };
    const date = takeCalendarDate(clock.rest, options.dateOrder);
    const zoneText = (date ? date.rest : clock.rest).replace(/^\s*(in|em|at|no|na)\s+/i, "").trim();
    const source = findTimeZone(zoneText);
    if (!source)
        return { output: "", error: `Unknown place or zone: ${zoneText}. Try a city (Tokyo, São Paulo), an IANA id (Europe/Berlin), an abbreviation (EST) or UTC+3.` };

    const nowMs = Date.now();
    const sourceNowWall = nowMs + source.offsetAt(nowMs) * 60000;
    const today = new Date(sourceNowWall);
    let year = today.getUTCFullYear(), month = today.getUTCMonth(), day = today.getUTCDate();
    if (date) {
        year = date.year ?? year;
        month = date.month;
        day = date.day;
        if (!validCalendarDate(year, month, day))
            return { output: "", error: "Not a valid date." };
    }
    let instant;
    if (clock.now || (clock.minutes === null && !date)) {
        instant = nowMs;
    } else {
        const minutes = clock.minutes ?? 0;
        instant = wallTimeToUtc(source, Date.UTC(year, month, day) + minutes * 60000);
    }

    const names = String(options.zones ?? "Local, UTC, New York, London, Berlin, Tokyo").split(/[,;\n]/).map(s => s.trim()).filter(s => s.length > 0);
    const zones = [{ zone: source, name: source.label }];
    const unknown = [];
    for (const name of names) {
        const zone = findTimeZone(name);
        if (!zone)
            unknown.push(name);
        else if (!zones.some(z => z.zone.label === zone.label))
            zones.push({ zone, name: zone.label });
    }

    const sourceOffset = source.offsetAt(instant);
    const sourceWall = instant + sourceOffset * 60000;
    const sourceDay = Math.floor(sourceWall / DAY_MS);
    const out = [`${formatClock(sourceWall)}  ${formatWall(sourceWall, true)} in ${source.label} (${formatUtcOffset(sourceOffset)})`, ""];
    const width = Math.max(...zones.map(z => z.name.length));
    for (const entry of zones) {
        const offset = entry.zone.offsetAt(instant);
        const wall = instant + offset * 60000;
        const dayShift = Math.floor(wall / DAY_MS) - sourceDay;
        const shift = dayShift === 0 ? "" : (dayShift > 0 ? `+${dayShift} day` : `${dayShift} day`);
        const dst = entry.zone.dst(instant) ? "DST" : "";
        out.push(`${entry.name.padEnd(width)}  ${formatWall(wall, false)}  ${formatClock(wall)}  ${formatUtcOffset(offset).padEnd(10)}${[dst, shift].filter(Boolean).join("  ")}`.replace(/\s+$/, ""));
    }
    if (unknown.length > 0)
        out.push("", "Unknown: " + unknown.join(", "));

    if (options.grid) {
        // Meeting planner: every hour of the source day across the zones;
        // ✓ marks hours inside 09-18 everywhere.
        const cellWidth = Math.max(5, ...zones.map(z => Math.min(z.name.length, 12)));
        out.push("", zones.map(z => z.name.slice(0, 12).padEnd(cellWidth)).join("  ").replace(/\s+$/, ""));
        const dayStart = wallTimeToUtc(source, Date.UTC(year, month, day));
        let good = 0;
        for (let hour = 0; hour < 24; hour++) {
            const t = dayStart + hour * 3600000;
            let allWorking = true;
            const cells = zones.map(z => {
                const wall = t + z.zone.offsetAt(t) * 60000;
                const h = new Date(wall).getUTCHours();
                if (h < 9 || h >= 18)
                    allWorking = false;
                return formatClock(wall).padEnd(cellWidth);
            });
            if (allWorking)
                good++;
            out.push(cells.join("  ").replace(/\s+$/, "") + (allWorking ? "  ✓" : ""));
        }
        out.push("", good > 0 ? `${good} hour${good === 1 ? "" : "s"} inside 09:00-18:00 in every zone.` : "No hour is inside 09:00-18:00 in every zone.");
    }
    return { output: out.join("\n"), meta: { offset: formatUtcOffset(sourceOffset), zones: zones.length } };
}

// ── Dates ──

function localTodayDay() {
    const now = new Date();
    return Math.floor(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / DAY_MS);
}

/// A whole day as days since 1970-01-01 (UTC), from an ISO/BR/US date or a word.
function parseDayNumber(text, order) {
    const key = normalizePlace(text);
    const words = { today: 0, hoje: 0, now: 0, agora: 0, tomorrow: 1, amanha: 1, yesterday: -1, ontem: -1 };
    if (words[key] !== undefined)
        return localTodayDay() + words[key];
    const date = takeCalendarDate(" " + text + " ", order);
    if (!date || date.rest.trim().length > 0)
        return null;
    const year = date.year ?? new Date().getFullYear();
    if (!validCalendarDate(year, date.month, date.day))
        return null;
    return Math.floor(Date.UTC(year, date.month, date.day) / DAY_MS);
}

function dayToDate(dayNumber) {
    return new Date(dayNumber * DAY_MS);
}

function formatDay(dayNumber) {
    const d = dayToDate(dayNumber);
    return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())} (${WEEKDAY_LONG[d.getUTCDay()]})`;
}

function addMonths(dayNumber, months) {
    const d = dayToDate(dayNumber);
    const target = d.getUTCMonth() + months;
    const year = d.getUTCFullYear() + Math.floor(target / 12);
    const month = ((target % 12) + 12) % 12;
    const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
    return Math.floor(Date.UTC(year, month, Math.min(d.getUTCDate(), lastDay)) / DAY_MS);
}

function addBusinessDays(dayNumber, count) {
    let day = dayNumber;
    const step = count < 0 ? -1 : 1;
    for (let left = Math.abs(count); left > 0;) {
        day += step;
        const weekday = dayToDate(day).getUTCDay();
        if (weekday !== 0 && weekday !== 6)
            left--;
    }
    return day;
}

function businessDaysBetween(a, b) {
    // Weekdays in [a, b): whole weeks, then the remainder.
    const sign = b < a ? -1 : 1;
    let start = Math.min(a, b);
    const end = Math.max(a, b);
    const total = end - start;
    let count = Math.floor(total / 7) * 5;
    for (let day = start + Math.floor(total / 7) * 7; day < end; day++) {
        const weekday = dayToDate(day).getUTCDay();
        if (weekday !== 0 && weekday !== 6)
            count++;
    }
    return count * sign;
}

/// Calendar difference as years, months and days (start <= end).
function calendarDifference(start, end) {
    let years = 0, months = 0;
    while (addMonths(start, (years + 1) * 12) <= end)
        years++;
    while (addMonths(start, years * 12 + months + 1) <= end)
        months++;
    const days = end - addMonths(start, years * 12 + months);
    return { years, months, days };
}

function plural(count, word) {
    return `${count} ${word}${Math.abs(count) === 1 ? "" : "s"}`;
}

function isoWeek(dayNumber) {
    const d = dayToDate(dayNumber);
    const weekday = (d.getUTCDay() + 6) % 7; // Monday = 0
    const thursday = dayNumber - weekday + 3;
    const year = dayToDate(thursday).getUTCFullYear();
    const firstThursday = Math.floor(Date.UTC(year, 0, 4) / DAY_MS);
    const week = 1 + Math.floor((thursday - firstThursday + ((dayToDate(firstThursday).getUTCDay() + 6) % 7)) / 7);
    return { year, week };
}

function describeSpan(days) {
    const parts = [];
    const abs = Math.abs(days);
    parts.push(plural(abs, "day"));
    if (abs >= 7)
        parts.push(`${plural(Math.floor(abs / 7), "week")}${abs % 7 ? " " + plural(abs % 7, "day") : ""}`);
    return parts.join(" = ");
}

function toolDateCalculator(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    const order = options.dateOrder ?? "dmy";
    const today = localTodayDay();

    // Difference: "A to B", "A - B" with spaces, "A até B", "A → B".
    const range = text.match(/^(.+?)\s+(?:to|until|até|ate|a|→|->|–|-)\s+(.+)$/i);
    if (range && parseDayNumber(range[1], order) !== null && parseDayNumber(range[2], order) !== null) {
        const a = parseDayNumber(range[1], order);
        const b = parseDayNumber(range[2], order);
        const start = Math.min(a, b), end = Math.max(a, b);
        const diff = calendarDifference(start, end);
        const out = [
            `From   ${formatDay(a)}`,
            `To     ${formatDay(b)}`,
            "",
            `Days           ${b - a}`,
            `Span           ${describeSpan(b - a)}`,
            `Calendar       ${[plural(diff.years, "year"), plural(diff.months, "month"), plural(diff.days, "day")].join(", ")}`,
            `Business days  ${businessDaysBetween(a, b)} (Mon-Fri, end date excluded)`,
            `Weekend days   ${Math.abs(b - a) - Math.abs(businessDaysBetween(a, b))}`,
            `Hours          ${groupThousands(Math.abs(b - a) * 24)}`,
            "",
            `Counting both ends: ${Math.abs(b - a) + 1} days`
        ];
        return { output: out.join("\n"), meta: { days: b - a } };
    }

    // Arithmetic: "<date> + 3w 2d", "today - 1y", "+ 10 business days".
    const arith = text.match(/^(.*?)\s*([+-])\s*((?:\d+\s*[a-zçã ]+?\s*)+)$/i);
    if (arith) {
        const base = arith[1].trim().length === 0 ? today : parseDayNumber(arith[1], order);
        if (base === null)
            return { output: "", error: "Could not read the date: " + arith[1].trim() };
        const sign = arith[2] === "-" ? -1 : 1;
        let day = base;
        let months = 0, days = 0, business = 0;
        const partRe = /(\d+)\s*(business days?|bd|dias? uteis|dias? úteis|du|years?|yrs?|y|anos?|months?|mo|m|mes|meses|weeks?|wk|w|semanas?|s|days?|d|dias?)\b/gi;
        let consumed = "";
        for (let m = partRe.exec(arith[3]); m !== null; m = partRe.exec(arith[3])) {
            consumed += m[0];
            const n = Number(m[1]);
            const unit = normalizePlace(m[2]);
            if (/^(business|bd|dias? uteis|du)/.test(unit)) business += n;
            else if (/^(y|yr|year|ano)/.test(unit)) months += 12 * n;
            else if (/^(mo|m$|month|mes)/.test(unit)) months += n;
            else if (/^(w|wk|week|semana|s$)/.test(unit)) days += 7 * n;
            else days += n;
        }
        if (consumed.replace(/\s/g, "").length !== arith[3].replace(/\s/g, "").length)
            return { output: "", error: "Use amounts such as 90d, 3w, 2m (months), 1y or 10bd (business days)." };
        day = addMonths(day, sign * months) + sign * days;
        if (business)
            day = addBusinessDays(day, sign * business);
        const out = [
            `${formatDay(base)} ${arith[2]} ${arith[3].trim()}`,
            `= ${formatDay(day)}`,
            "",
            `${day - today === 0 ? "Today" : (day > today ? `In ${plural(day - today, "day")}` : `${plural(today - day, "day")} ago`)}`
        ];
        return { output: out.join("\n"), meta: { result: formatDay(day).slice(0, 10) } };
    }

    // A single date: everything about it.
    const day = parseDayNumber(text, order);
    if (day === null)
        return { output: "", error: "Enter a date (2026-12-25, 25/12/2026, today), a range (2026-01-01 to 2026-12-25) or a sum (today + 90d, 2026-03-01 - 2w, today + 10bd)." };
    const d = dayToDate(day);
    const year = d.getUTCFullYear();
    const startOfYear = Math.floor(Date.UTC(year, 0, 1) / DAY_MS);
    const daysInYear = Math.floor(Date.UTC(year + 1, 0, 1) / DAY_MS) - startOfYear;
    const week = isoWeek(day);
    const out = [
        formatDay(day),
        "",
        `Relative       ${day === today ? "today" : (day > today ? "in " + plural(day - today, "day") : plural(today - day, "day") + " ago")}`,
        `ISO week       ${week.year}-W${pad2(week.week)}`,
        `Day of year    ${day - startOfYear + 1} of ${daysInYear}`,
        `Days left      ${startOfYear + daysInYear - day - 1}`,
        `Quarter        Q${Math.floor(d.getUTCMonth() / 3) + 1}`,
        `Leap year      ${daysInYear === 366 ? "yes" : "no"}`,
        `Unix (00:00Z)  ${day * 86400}`
    ];
    if (day < today) {
        const diff = calendarDifference(day, today);
        out.push(`Age            ${[plural(diff.years, "year"), plural(diff.months, "month"), plural(diff.days, "day")].join(", ")}`);
    }
    return { output: out.join("\n"), meta: { week: `W${pad2(week.week)}` } };
}

// ─── 13. Color & design ───────────────────────────────────────────────────────

function srgbChannelToLinear(c) {
    const v = c / 255;
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

function linearChannelToSrgb(v) {
    const c = v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
    return c * 255;
}

/// WCAG 2.x relative luminance of an opaque colour.
function relativeLuminance(color) {
    return 0.2126 * srgbChannelToLinear(color.r) + 0.7152 * srgbChannelToLinear(color.g) + 0.0722 * srgbChannelToLinear(color.b);
}

function contrastRatio(a, b) {
    const la = relativeLuminance(a), lb = relativeLuminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function colorToHex(color) {
    const h = n => Math.round(Math.max(0, Math.min(255, n))).toString(16).padStart(2, "0").toUpperCase();
    return "#" + h(color.r) + h(color.g) + h(color.b);
}

/// Source-over: a translucent colour as it shows on an opaque background.
function compositeOver(top, bottom) {
    const a = top.a ?? 1;
    return {
        r: top.r * a + bottom.r * (1 - a),
        g: top.g * a + bottom.g * (1 - a),
        b: top.b * a + bottom.b * (1 - a),
        a: 1
    };
}

const CSS_NAMED_COLORS = {
    black: "#000000", white: "#ffffff", red: "#ff0000", green: "#008000", lime: "#00ff00", blue: "#0000ff",
    yellow: "#ffff00", cyan: "#00ffff", aqua: "#00ffff", magenta: "#ff00ff", fuchsia: "#ff00ff", gray: "#808080",
    grey: "#808080", silver: "#c0c0c0", maroon: "#800000", olive: "#808000", navy: "#000080", purple: "#800080",
    teal: "#008080", orange: "#ffa500", pink: "#ffc0cb", brown: "#a52a2a", gold: "#ffd700", indigo: "#4b0082",
    violet: "#ee82ee", coral: "#ff7f50", salmon: "#fa8072", crimson: "#dc143c", tomato: "#ff6347",
    turquoise: "#40e0d0", beige: "#f5f5dc", ivory: "#fffff0", lavender: "#e6e6fa", khaki: "#f0e68c",
    darkgray: "#a9a9a9", lightgray: "#d3d3d3", dimgray: "#696969", whitesmoke: "#f5f5f5", rebeccapurple: "#663399"
};

function parseAnyColor(text) {
    const key = String(text).trim().toLowerCase();
    return parseColor(CSS_NAMED_COLORS[key] ?? key);
}

/// Splits "fg on bg", two lines, "a, b", "a | b" or two space-separated tokens.
function splitColorPair(text) {
    const lines = String(text).split(/\r?\n/).map(line => line.trim()).filter(line => line.length > 0);
    if (lines.length >= 2)
        return [lines[0], lines[1]];
    const one = lines[0] ?? "";
    const tokens = one.match(/#?[0-9a-f]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)|[a-z]+/gi) ?? [];
    const colors = tokens.filter(token => !/^(on|vs|and|over|sobre|e|x|em)$/i.test(token));
    return colors.length >= 2 ? [colors[0], colors[1]] : null;
}

function rgbToHsl(color) {
    const r = color.r / 255, g = color.g / 255, b = color.b / 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    const l = (max + min) / 2;
    if (max === min)
        return { h: 0, s: 0, l };
    const d = max - min;
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let h;
    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0));
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    return { h: h * 60, s, l };
}

function hslToRgb(h, s, l) {
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const hh = ((h % 360) + 360) % 360 / 60;
    const x = c * (1 - Math.abs(hh % 2 - 1));
    const m = l - c / 2;
    const [r, g, b] = hh < 1 ? [c, x, 0] : hh < 2 ? [x, c, 0] : hh < 3 ? [0, c, x] : hh < 4 ? [0, x, c] : hh < 5 ? [x, 0, c] : [c, 0, x];
    return { r: (r + m) * 255, g: (g + m) * 255, b: (b + m) * 255, a: 1 };
}

/// The nearest colour (same hue and saturation, only lightness moves) that
/// reaches the target ratio against bg, or null.
function nearestContrastingColor(fg, bg, target) {
    const hsl = rgbToHsl(fg);
    let best = null;
    for (const direction of [-1, 1]) {
        let lo = hsl.l, hi = direction < 0 ? 0 : 1;
        const end = hslToRgb(hsl.h, hsl.s, hi);
        if (contrastRatio(end, bg) < target)
            continue;
        for (let i = 0; i < 30; i++) {
            const mid = (lo + hi) / 2;
            if (contrastRatio(hslToRgb(hsl.h, hsl.s, mid), bg) >= target)
                hi = mid;
            else
                lo = mid;
        }
        const delta = Math.abs(hi - hsl.l);
        if (best === null || delta < best.delta) {
            // Rounding to 8 bits can land just under the target: nudge on.
            let l = hi;
            let color = hslToRgb(hsl.h, hsl.s, l);
            for (let guard = 0; guard < 50 && contrastRatio(parseColor(colorToHex(color)), bg) < target; guard++) {
                l = Math.max(0, Math.min(1, l + direction * 0.002));
                color = hslToRgb(hsl.h, hsl.s, l);
            }
            best = { delta, color: parseColor(colorToHex(color)) };
        }
    }
    return best ? best.color : null;
}

function formatRatio(ratio) {
    return (Math.floor(ratio * 100) / 100).toFixed(2) + ":1";
}

function toolContrastChecker(input = "") {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    const pair = splitColorPair(text);
    if (!pair)
        return { output: "", error: "Enter a text colour and a background: \"#1E1E2E on #F5E0DC\", two lines, or two colours separated by a space." };
    const fgRaw = parseAnyColor(pair[0]);
    const bgRaw = parseAnyColor(pair[1]);
    if (!fgRaw || !bgRaw)
        return { output: "", error: "Could not parse colour: " + (!fgRaw ? pair[0] : pair[1]) };
    // A translucent background sits on white; a translucent text colour on the background.
    const bg = bgRaw.a < 1 ? compositeOver(bgRaw, { r: 255, g: 255, b: 255, a: 1 }) : bgRaw;
    const fg = fgRaw.a < 1 ? compositeOver(fgRaw, bg) : fgRaw;
    const ratio = contrastRatio(fg, bg);
    // WCAG compares the unrounded ratio; show it floored so 4.499 never reads 4.50.
    const pass = min => ratio >= min ? "✓ pass" : "✗ fail";
    const out = [
        `Text        ${colorToHex(fg)}${fgRaw.a < 1 ? `  (${pair[0].trim()} composited)` : ""}`,
        `Background  ${colorToHex(bg)}${bgRaw.a < 1 ? `  (${pair[1].trim()} on white)` : ""}`,
        "",
        `Contrast    ${formatRatio(ratio)}`,
        "",
        `AA   normal text (4.5:1)   ${pass(4.5)}`,
        `AA   large text  (3:1)     ${pass(3)}`,
        `AAA  normal text (7:1)     ${pass(7)}`,
        `AAA  large text  (4.5:1)   ${pass(4.5)}`,
        `UI   components  (3:1)     ${pass(3)}`,
        "",
        "Large text: 24px, or 18.66px bold."
    ];
    const suggestions = [];
    for (const [label, target] of [["AA", 4.5], ["AAA", 7]]) {
        if (ratio >= target)
            continue;
        const fix = nearestContrastingColor(fg, bg, target);
        suggestions.push(fix
            ? `  ${label.padEnd(4)} ${colorToHex(fix)}  (${formatRatio(contrastRatio(fix, bg))})`
            : `  ${label.padEnd(4)} not reachable by changing the text lightness`);
    }
    if (suggestions.length > 0)
        out.push("", "Closest text colour that passes:", ...suggestions);
    return {
        output: out.join("\n"),
        meta: {
            ratio: formatRatio(ratio),
            visual: { kind: "contrast", foreground: colorToHex(fg), background: colorToHex(bg), ratio: formatRatio(ratio) }
        }
    };
}

// ── OKLCH palettes ──

function rgbToOklab(color) {
    const r = srgbChannelToLinear(color.r), g = srgbChannelToLinear(color.g), b = srgbChannelToLinear(color.b);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return {
        L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    };
}

/// OKLab to linear sRGB, unclamped (out-of-gamut channels leave 0-1).
function oklabToLinear(L, a, b) {
    const l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
    const m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
    const s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
    return [
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    ];
}

function rgbToOklch(color) {
    const lab = rgbToOklab(color);
    const C = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
    let h = Math.atan2(lab.b, lab.a) * 180 / Math.PI;
    if (h < 0)
        h += 360;
    return { L: lab.L, C, h };
}

/// OKLCH to sRGB; chroma shrinks until the colour fits (hue and lightness kept).
function oklchToRgb(L, C, h) {
    const rad = h * Math.PI / 180;
    const inGamut = c => oklabToLinear(L, c * Math.cos(rad), c * Math.sin(rad)).every(v => v >= -1e-6 && v <= 1 + 1e-6);
    let chroma = C;
    if (!inGamut(chroma)) {
        let lo = 0, hi = chroma;
        for (let i = 0; i < 24; i++) {
            const mid = (lo + hi) / 2;
            if (inGamut(mid)) lo = mid;
            else hi = mid;
        }
        chroma = lo;
    }
    const lin = oklabToLinear(L, chroma * Math.cos(rad), chroma * Math.sin(rad));
    return { r: linearChannelToSrgb(Math.max(0, Math.min(1, lin[0]))), g: linearChannelToSrgb(Math.max(0, Math.min(1, lin[1]))), b: linearChannelToSrgb(Math.max(0, Math.min(1, lin[2]))), a: 1 };
}

function paletteEntries(base, scheme) {
    const lch = rgbToOklch(base);
    const hue = offset => oklchToRgb(lch.L, lch.C, lch.h + offset);
    switch (scheme) {
    case "complementary":
        return [["base", base], ["complement", hue(180)]];
    case "analogous":
        return [["-60°", hue(-60)], ["-30°", hue(-30)], ["base", base], ["+30°", hue(30)], ["+60°", hue(60)]];
    case "triadic":
        return [["base", base], ["+120°", hue(120)], ["+240°", hue(240)]];
    case "tetradic":
        return [["base", base], ["+90°", hue(90)], ["+180°", hue(180)], ["+270°", hue(270)]];
    case "split":
        return [["base", base], ["+150°", hue(150)], ["+210°", hue(210)]];
    case "shades": {
        // Toward black and white in perceptual steps.
        const out = [];
        for (let i = 0; i <= 10; i++) {
            const L = i / 10;
            out.push([String(Math.round(L * 100)), oklchToRgb(L, lch.C * Math.sin(Math.PI * L), lch.h)]);
        }
        return out;
    }
    default: {
        // Tonal ramp at the Material tone stops, lightness in OKLCH.
        const tones = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100];
        return tones.map(tone => [String(tone), oklchToRgb(tone / 100, lch.C, lch.h)]);
    }
    }
}

// ── Material You (matugen) schemes ──
// HCT/CAM16 and the 2021 dynamic scheme from Google's material-color-utilities
// (Apache 2.0), the spec matugen 4 generates. Checked colour by colour against
// `matugen color hex … --dry-run -j hex` in scripts/tests/test_devtools.js.

const MCU_SCALED_DISCOUNT_FROM_LINRGB = [
    [0.001200833568784504, 0.002389694492170889, 0.0002795742885861124],
    [0.0005891086651375999, 0.0029785502573438758, 0.0003270666104008398],
    [0.00010146692491640572, 0.0005364214359186694, 0.0032979401770712076]
];
const MCU_LINRGB_FROM_SCALED_DISCOUNT = [
    [1373.2198709594231, -1100.4251190754821, -7.278681089101213],
    [-271.815969077903, 559.6580465940733, -32.46047482791194],
    [1.9622899599665666, -57.173814538844006, 308.7233197812385]
];
const MCU_Y_FROM_LINRGB = [0.2126, 0.7152, 0.0722];
const MCU_WHITE_D65 = [95.047, 100.0, 108.883];

function mcuLinearized(component) {
    const n = component / 255;
    return (n <= 0.040449936 ? n / 12.92 : Math.pow((n + 0.055) / 1.055, 2.4)) * 100;
}

function mcuTrueDelinearized(linear) {
    const n = linear / 100;
    return (n <= 0.0031308 ? n * 12.92 : 1.055 * Math.pow(n, 1 / 2.4) - 0.055) * 255;
}

function mcuDelinearized(linear) {
    return Math.max(0, Math.min(255, Math.round(mcuTrueDelinearized(linear))));
}

// Rounded halfway values: JS Math.round(-0.5) is -0, Kotlin/Java's is 0; both clamp the same.
const MCU_CRITICAL_PLANES = (() => {
    const planes = [];
    for (let i = 0; i < 255; i++)
        planes.push(mcuLinearized(i + 0.5));
    return planes;
})();

function mcuLabF(t) {
    const e = 216 / 24389, kappa = 24389 / 27;
    return t > e ? Math.cbrt(t) : (kappa * t + 16) / 116;
}

function mcuLabInvF(ft) {
    const e = 216 / 24389, kappa = 24389 / 27;
    const ft3 = ft * ft * ft;
    return ft3 > e ? ft3 : (116 * ft - 16) / kappa;
}

function mcuYFromLstar(lstar) {
    return 100 * mcuLabInvF((lstar + 16) / 116);
}

function mcuLstarFromRgb(r, g, b) {
    const y = 0.2126 * mcuLinearized(r) + 0.7152 * mcuLinearized(g) + 0.0722 * mcuLinearized(b);
    return 116 * mcuLabF(y / 100) - 16;
}

const MCU_VC = (() => {
    const adaptingLuminance = 200 / Math.PI * mcuYFromLstar(50) / 100;
    const backgroundLstar = 50, surround = 2;
    const [x, y, z] = MCU_WHITE_D65;
    const rW = x * 0.401288 + y * 0.650173 + z * -0.051461;
    const gW = x * -0.250268 + y * 1.204414 + z * 0.045854;
    const bW = x * -0.002079 + y * 0.048952 + z * 0.953127;
    const f = 0.8 + surround / 10;
    const c = f >= 0.9 ? 0.59 + (0.69 - 0.59) * ((f - 0.9) * 10) : 0.525 + (0.59 - 0.525) * ((f - 0.8) * 10);
    let d = f * (1 - (1 / 3.6) * Math.exp((-adaptingLuminance - 42) / 92));
    d = Math.max(0, Math.min(1, d));
    const nc = f;
    const rgbD = [d * (100 / rW) + 1 - d, d * (100 / gW) + 1 - d, d * (100 / bW) + 1 - d];
    const k = 1 / (5 * adaptingLuminance + 1);
    const k4 = k * k * k * k;
    const k4F = 1 - k4;
    const fl = k4 * adaptingLuminance + 0.1 * k4F * k4F * Math.cbrt(5 * adaptingLuminance);
    const n = mcuYFromLstar(backgroundLstar) / MCU_WHITE_D65[1];
    const zz = 1.48 + Math.sqrt(n);
    const nbb = 0.725 / Math.pow(n, 0.2);
    const factors = [rW, gW, bW].map((w, i) => Math.pow(fl * rgbD[i] * w / 100, 0.42));
    const rgbA = factors.map(af => 400 * af / (af + 27.13));
    const aw = (2 * rgbA[0] + rgbA[1] + 0.05 * rgbA[2]) * nbb;
    return { n, aw, nbb, ncb: nbb, c, nc, rgbD, fl, z: zz };
})();

/// CAM16 hue and chroma of an sRGB colour (0-255 channels).
function mcuCam16(r, g, b) {
    const vc = MCU_VC;
    const rl = mcuLinearized(r), gl = mcuLinearized(g), bl = mcuLinearized(b);
    const x = 0.41233895 * rl + 0.35762064 * gl + 0.18051042 * bl;
    const y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl;
    const z = 0.01932141 * rl + 0.11916382 * gl + 0.95034478 * bl;
    const rC = 0.401288 * x + 0.650173 * y - 0.051461 * z;
    const gC = -0.250268 * x + 1.204414 * y + 0.045854 * z;
    const bC = -0.002079 * x + 0.048952 * y + 0.953127 * z;
    const adapt = (component, i) => {
        const dd = vc.rgbD[i] * component;
        const af = Math.pow(vc.fl * Math.abs(dd) / 100, 0.42);
        return Math.sign(dd) * 400 * af / (af + 27.13);
    };
    const rA = adapt(rC, 0), gA = adapt(gC, 1), bA = adapt(bC, 2);
    const a = (11 * rA - 12 * gA + bA) / 11;
    const bb = (rA + gA - 2 * bA) / 9;
    const u = (20 * rA + 20 * gA + 21 * bA) / 20;
    const p2 = (40 * rA + 20 * gA + bA) / 20;
    const atanDegrees = Math.atan2(bb, a) * 180 / Math.PI;
    const hue = atanDegrees < 0 ? atanDegrees + 360 : (atanDegrees >= 360 ? atanDegrees - 360 : atanDegrees);
    const ac = p2 * vc.nbb;
    const j = 100 * Math.pow(ac / vc.aw, vc.c * vc.z);
    const huePrime = hue < 20.14 ? hue + 360 : hue;
    const eHue = 0.25 * (Math.cos(huePrime * Math.PI / 180 + 2) + 3.8);
    const p1 = 50000 / 13 * eHue * vc.nc * vc.ncb;
    const t = p1 * Math.hypot(a, bb) / (u + 0.305);
    const alpha = Math.pow(1.64 - Math.pow(0.29, vc.n), 0.73) * Math.pow(t, 0.9);
    return { hue, chroma: alpha * Math.sqrt(j / 100) };
}

function mcuMatrixMultiply(row, matrix) {
    return matrix.map(m => row[0] * m[0] + row[1] * m[1] + row[2] * m[2]);
}

function mcuSanitizeRadians(angle) {
    return (angle + Math.PI * 8) % (Math.PI * 2);
}

function mcuChromaticAdaptation(component) {
    const af = Math.pow(Math.abs(component), 0.42);
    return Math.sign(component) * 400 * af / (af + 27.13);
}

function mcuHueOf(linrgb) {
    const sd = mcuMatrixMultiply(linrgb, MCU_SCALED_DISCOUNT_FROM_LINRGB);
    const rA = mcuChromaticAdaptation(sd[0]), gA = mcuChromaticAdaptation(sd[1]), bA = mcuChromaticAdaptation(sd[2]);
    return Math.atan2((rA + gA - 2 * bA) / 9, (11 * rA - 12 * gA + bA) / 11);
}

function mcuInCyclicOrder(a, b, c) {
    return mcuSanitizeRadians(b - a) < mcuSanitizeRadians(c - a);
}

function mcuNthVertex(y, n) {
    const [kR, kG, kB] = MCU_Y_FROM_LINRGB;
    const coordA = n % 4 <= 1 ? 0 : 100;
    const coordB = n % 2 === 0 ? 0 : 100;
    const bounded = v => v >= 0 && v <= 100;
    if (n < 4) {
        const r = (y - coordA * kG - coordB * kB) / kR;
        return bounded(r) ? [r, coordA, coordB] : [-1, -1, -1];
    }
    if (n < 8) {
        const g = (y - coordB * kR - coordA * kB) / kG;
        return bounded(g) ? [coordB, g, coordA] : [-1, -1, -1];
    }
    const b = (y - coordA * kR - coordB * kG) / kB;
    return bounded(b) ? [coordA, coordB, b] : [-1, -1, -1];
}

function mcuBisectToLimit(y, targetHue) {
    let left = [-1, -1, -1], right = left, leftHue = 0, rightHue = 0;
    let initialized = false, uncut = true;
    for (let n = 0; n < 12; n++) {
        const mid = mcuNthVertex(y, n);
        if (mid[0] < 0)
            continue;
        const midHue = mcuHueOf(mid);
        if (!initialized) {
            left = mid; right = mid; leftHue = midHue; rightHue = midHue;
            initialized = true;
            continue;
        }
        if (uncut || mcuInCyclicOrder(leftHue, midHue, rightHue)) {
            uncut = false;
            if (mcuInCyclicOrder(leftHue, targetHue, midHue)) {
                right = mid; rightHue = midHue;
            } else {
                left = mid; leftHue = midHue;
            }
        }
    }
    for (let axis = 0; axis < 3; axis++) {
        if (left[axis] === right[axis])
            continue;
        let lPlane, rPlane;
        if (left[axis] < right[axis]) {
            lPlane = Math.floor(mcuTrueDelinearized(left[axis]) - 0.5);
            rPlane = Math.ceil(mcuTrueDelinearized(right[axis]) - 0.5);
        } else {
            lPlane = Math.ceil(mcuTrueDelinearized(left[axis]) - 0.5);
            rPlane = Math.floor(mcuTrueDelinearized(right[axis]) - 0.5);
        }
        for (let i = 0; i < 8; i++) {
            if (Math.abs(rPlane - lPlane) <= 1)
                break;
            const mPlane = Math.floor((lPlane + rPlane) / 2);
            const coordinate = MCU_CRITICAL_PLANES[mPlane];
            const t = (coordinate - left[axis]) / (right[axis] - left[axis]);
            const mid = [0, 1, 2].map(k => left[k] + (right[k] - left[k]) * t);
            const midHue = mcuHueOf(mid);
            if (mcuInCyclicOrder(leftHue, targetHue, midHue)) {
                right = mid; rPlane = mPlane;
            } else {
                left = mid; leftHue = midHue; lPlane = mPlane;
            }
        }
    }
    return [0, 1, 2].map(k => (left[k] + right[k]) / 2);
}

function mcuInverseChromaticAdaptation(adapted) {
    const abs = Math.abs(adapted);
    const base = Math.max(0, 27.13 * abs / (400 - abs));
    return Math.sign(adapted) * Math.pow(base, 1 / 0.42);
}

function mcuFindResultByJ(hueRadians, chroma, y) {
    const vc = MCU_VC;
    let j = Math.sqrt(y) * 11;
    const tInnerCoeff = 1 / Math.pow(1.64 - Math.pow(0.29, vc.n), 0.73);
    const eHue = 0.25 * (Math.cos(hueRadians + 2) + 3.8);
    const p1 = eHue * (50000 / 13) * vc.nc * vc.ncb;
    const hSin = Math.sin(hueRadians), hCos = Math.cos(hueRadians);
    for (let round = 0; round < 5; round++) {
        const jNormalized = j / 100;
        const alpha = chroma === 0 || j === 0 ? 0 : chroma / Math.sqrt(jNormalized);
        const t = Math.pow(alpha * tInnerCoeff, 1 / 0.9);
        const ac = vc.aw * Math.pow(jNormalized, 1 / vc.c / vc.z);
        const p2 = ac / vc.nbb;
        const gamma = 23 * (p2 + 0.305) * t / (23 * p1 + 11 * t * hCos + 108 * t * hSin);
        const a = gamma * hCos, b = gamma * hSin;
        const rA = (460 * p2 + 451 * a + 288 * b) / 1403;
        const gA = (460 * p2 - 891 * a - 261 * b) / 1403;
        const bA = (460 * p2 - 220 * a - 6300 * b) / 1403;
        const linrgb = mcuMatrixMultiply([mcuInverseChromaticAdaptation(rA), mcuInverseChromaticAdaptation(gA), mcuInverseChromaticAdaptation(bA)], MCU_LINRGB_FROM_SCALED_DISCOUNT);
        if (linrgb[0] < 0 || linrgb[1] < 0 || linrgb[2] < 0)
            return null;
        const fnj = MCU_Y_FROM_LINRGB[0] * linrgb[0] + MCU_Y_FROM_LINRGB[1] * linrgb[1] + MCU_Y_FROM_LINRGB[2] * linrgb[2];
        if (fnj <= 0)
            return null;
        if (round === 4 || Math.abs(fnj - y) < 0.002) {
            if (linrgb[0] > 100.01 || linrgb[1] > 100.01 || linrgb[2] > 100.01)
                return null;
            return linrgb.map(mcuDelinearized);
        }
        j = j - (fnj - y) * j / (2 * fnj);
    }
    return null;
}

/// HCT (hue, chroma, tone) to [r, g, b], as HctSolver.solveToInt.
function mcuSolve(hueDegrees, chroma, lstar) {
    if (chroma < 0.0001 || lstar < 0.0001 || lstar > 99.9999) {
        const c = mcuDelinearized(mcuYFromLstar(lstar));
        return [c, c, c];
    }
    const hue = ((hueDegrees % 360) + 360) % 360;
    const hueRadians = hue / 180 * Math.PI;
    const y = mcuYFromLstar(lstar);
    const exact = mcuFindResultByJ(hueRadians, chroma, y);
    if (exact)
        return exact;
    return mcuBisectToLimit(y, hueRadians).map(mcuDelinearized);
}

function mcuHex(rgb) {
    return "#" + rgb.map(v => v.toString(16).padStart(2, "0")).join("");
}

function mcuRotateHue(sourceHue, hues, rotations, rotate = true) {
    if (!rotate)
        return sourceHue;
    for (let i = 0; i < hues.length - 1; i++) {
        if (sourceHue >= hues[i] && sourceHue < hues[i + 1])
            return ((sourceHue + rotations[i]) % 360 + 360) % 360;
    }
    return sourceHue;
}

// [hue, chroma] of each palette per scheme type (2021 spec). `rotate` is
// false for pure black, which matugen leaves unrotated.
function mcuPalettes(type, hue, rotate = true) {
    const h = d => ((hue + d) % 360 + 360) % 360;
    switch (type) {
    case "neutral":
        return { primary: [hue, 12], secondary: [hue, 8], tertiary: [hue, 16], neutral: [hue, 2], neutral_variant: [hue, 2] };
    case "vibrant": {
        const hues = [0, 41, 61, 101, 131, 181, 251, 301, 360];
        return {
            primary: [hue, 200],
            secondary: [mcuRotateHue(hue, hues, [18, 15, 10, 12, 15, 18, 15, 12, 12], rotate), 24],
            tertiary: [mcuRotateHue(hue, hues, [35, 30, 20, 25, 30, 35, 30, 25, 25], rotate), 32],
            neutral: [hue, 10],
            // matugen's material-colors uses 10 here (the Kotlin/Python ports say 12).
            neutral_variant: [hue, 10]
        };
    }
    case "expressive": {
        const hues = [0, 21, 51, 121, 151, 191, 271, 321, 360];
        return {
            primary: [h(240), 40],
            secondary: [mcuRotateHue(hue, hues, [45, 95, 45, 20, 45, 90, 45, 45, 45], rotate), 24],
            tertiary: [mcuRotateHue(hue, hues, [120, 120, 20, 45, 20, 15, 20, 120, 120], rotate), 32],
            neutral: [h(15), 8],
            neutral_variant: [h(15), 12]
        };
    }
    case "rainbow":
        return { primary: [hue, 48], secondary: [hue, 16], tertiary: [h(60), 24], neutral: [hue, 0], neutral_variant: [hue, 0] };
    case "fruit-salad":
        return { primary: [h(-50), 48], secondary: [h(-50), 36], tertiary: [hue, 36], neutral: [hue, 10], neutral_variant: [hue, 16] };
    default: // tonal spot
        return { primary: [hue, 36], secondary: [hue, 16], tertiary: [h(60), 24], neutral: [hue, 6], neutral_variant: [hue, 8] };
    }
}

// Role: [palette, dark tone, light tone]. Standard contrast meets every
// contrast curve at these tones, so no adjustment pass is needed.
const MCU_ROLES = [
    ["primary", "primary", 80, 40], ["on_primary", "primary", 20, 100],
    ["primary_container", "primary", 30, 90], ["on_primary_container", "primary", 90, 10],
    ["inverse_primary", "primary", 40, 80],
    ["primary_fixed", "primary", 90, 90], ["primary_fixed_dim", "primary", 80, 80],
    ["on_primary_fixed", "primary", 10, 10], ["on_primary_fixed_variant", "primary", 30, 30],
    ["secondary", "secondary", 80, 40], ["on_secondary", "secondary", 20, 100],
    ["secondary_container", "secondary", 30, 90], ["on_secondary_container", "secondary", 90, 10],
    ["secondary_fixed", "secondary", 90, 90], ["secondary_fixed_dim", "secondary", 80, 80],
    ["on_secondary_fixed", "secondary", 10, 10], ["on_secondary_fixed_variant", "secondary", 30, 30],
    ["tertiary", "tertiary", 80, 40], ["on_tertiary", "tertiary", 20, 100],
    ["tertiary_container", "tertiary", 30, 90], ["on_tertiary_container", "tertiary", 90, 10],
    ["tertiary_fixed", "tertiary", 90, 90], ["tertiary_fixed_dim", "tertiary", 80, 80],
    ["on_tertiary_fixed", "tertiary", 10, 10], ["on_tertiary_fixed_variant", "tertiary", 30, 30],
    ["error", "error", 80, 40], ["on_error", "error", 20, 100],
    ["error_container", "error", 30, 90], ["on_error_container", "error", 90, 10],
    ["background", "neutral", 6, 98], ["on_background", "neutral", 90, 10],
    ["surface", "neutral", 6, 98], ["on_surface", "neutral", 90, 10],
    ["surface_dim", "neutral", 6, 87], ["surface_bright", "neutral", 24, 98],
    ["surface_container_lowest", "neutral", 4, 100], ["surface_container_low", "neutral", 10, 96],
    ["surface_container", "neutral", 12, 94], ["surface_container_high", "neutral", 17, 92],
    ["surface_container_highest", "neutral", 22, 90],
    ["surface_variant", "neutral_variant", 30, 90], ["on_surface_variant", "neutral_variant", 80, 30],
    ["outline", "neutral_variant", 60, 50], ["outline_variant", "neutral_variant", 30, 80],
    ["inverse_surface", "neutral", 90, 20], ["inverse_on_surface", "neutral", 20, 95],
    ["shadow", "neutral", 0, 0], ["scrim", "neutral", 0, 0],
    ["surface_tint", "primary", 80, 40]
];

const MCU_TYPES = ["tonal-spot", "vibrant", "expressive", "neutral", "rainbow", "fruit-salad"];

/// Every matugen colour role, dark and light, for a source colour.
function materialScheme(rgb, type = "tonal-spot") {
    const cam = mcuCam16(rgb[0], rgb[1], rgb[2]);
    const palettes = mcuPalettes(type, cam.hue, rgb[0] + rgb[1] + rgb[2] > 0);
    palettes.error = [25, 84];
    const roles = [];
    for (const [name, palette, darkTone, lightTone] of MCU_ROLES) {
        const [hue, chroma] = palettes[palette];
        roles.push({ name, palette, dark: mcuHex(mcuSolve(hue, chroma, darkTone)), light: mcuHex(mcuSolve(hue, chroma, lightTone)) });
    }
    roles.unshift({ name: "source_color", palette: "", dark: mcuHex(rgb), light: mcuHex(rgb) });
    return { hue: cam.hue, chroma: cam.chroma, tone: mcuLstarFromRgb(rgb[0], rgb[1], rgb[2]), roles, palettes };
}

/// matugen's own command line works as input: matugen color hex "#6750A4" -t scheme-vibrant -m light.
function parseMatugenInput(text) {
    let rest = String(text).trim();
    let type = null, mode = null;
    rest = rest.replace(/(?:^|\s)(?:-t|--type)[\s=]+["']?(?:scheme-)?([a-z-]+)["']?/i, (unused, value) => { type = value.toLowerCase(); return " "; });
    rest = rest.replace(/(?:^|\s)(?:-m|--mode)[\s=]+["']?(dark|light)["']?/i, (unused, value) => { mode = value.toLowerCase(); return " "; });
    rest = rest.replace(/^\s*matugen\s+color\s+(?:hex|rgb|hsl)\s+/i, "").replace(/\s--?[a-z-]+(?:[\s=]+\S+)?/gi, " ").trim().replace(/^["']|["']$/g, "");
    return { color: rest, type, mode };
}

function camelRole(name) {
    return name.replace(/_([a-z])/g, (unused, ch) => ch.toUpperCase());
}

function toolMaterialScheme(text, options) {
    const parsed = parseMatugenInput(text);
    const base = parseAnyColor(parsed.color);
    if (!base)
        return { output: "", error: "Enter a source colour (#6750A4) or a matugen command: matugen color hex \"#6750A4\" -t scheme-vibrant -m light." };
    const type = parsed.type ?? options.matugenType ?? "tonal-spot";
    if (MCU_TYPES.indexOf(type) === -1)
        return { output: "", error: `Unsupported scheme type "${type}". Supported: ${MCU_TYPES.join(", ")} (content, fidelity and monochrome are not).` };
    const mode = parsed.mode ?? options.mode ?? "dark";
    const scheme = materialScheme([Math.round(base.r), Math.round(base.g), Math.round(base.b)], type);
    const pick = role => mode === "light" ? role.light : role.dark;
    let output;
    switch (options.format ?? "list") {
    case "json": {
        // matugen's -j hex "colors" object; "default" is the chosen mode.
        const colors = {};
        for (const role of scheme.roles.slice().sort((a, b) => a.name < b.name ? -1 : 1))
            colors[role.name] = { dark: { color: role.dark }, default: { color: pick(role) }, light: { color: role.light } };
        output = JSON.stringify({ colors, mode: mode === "light" ? "Light" : "Dark" }, null, 2);
        break;
    }
    case "css":
        output = ":root {\n" + scheme.roles.map(role => `  --${role.name.replace(/_/g, "-")}: ${pick(role)};`).join("\n") + "\n}";
        break;
    case "qml":
        // The shell's own naming: Appearance.m3colors.m3onPrimaryContainer.
        output = scheme.roles.map(role => {
            const name = camelRole(role.name);
            return `property color m3${name}: "${pick(role)}"`;
        }).join("\n");
        break;
    default: {
        const width = Math.max(...scheme.roles.map(role => role.name.length));
        output = [`${"role".padEnd(width)}  dark     light`]
            .concat(scheme.roles.map(role => `${role.name.padEnd(width)}  ${role.dark}  ${role.light}`))
            .join("\n");
    }
    }
    return {
        output,
        meta: {
            type,
            mode,
            hct: `${scheme.hue.toFixed(1)} ${scheme.chroma.toFixed(1)} ${scheme.tone.toFixed(1)}`,
            roles: scheme.roles.length,
            visual: { kind: "swatches", items: scheme.roles.map(role => ({ label: role.name, color: pick(role).toUpperCase() })) }
        }
    };
}

function toolPaletteGenerator(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0)
        return { output: "" };
    if ((options.scheme ?? "tonal") === "matugen" || /^matugen\b/i.test(text))
        return toolMaterialScheme(text, options);
    const base = parseAnyColor(text);
    if (!base)
        return { output: "", error: "Enter a base colour: #6750A4, rgb(103, 80, 164), hsl(260, 34%, 48%) or a CSS name." };
    const opaque = { r: base.r, g: base.g, b: base.b, a: 1 };
    const scheme = options.scheme ?? "tonal";
    const entries = paletteEntries(opaque, scheme).map(([label, color]) => [label, parseColor(colorToHex(color))]);
    const format = options.format ?? "list";
    const slug = label => label.replace(/°/g, "").replace(/^\+/, "plus-").replace(/^-/, "minus-").replace(/[^a-z0-9-]+/gi, "-").toLowerCase();
    let output;
    switch (format) {
    case "css":
        output = ":root {\n" + entries.map(([label, color]) => `  --color-${slug(label)}: ${colorToHex(color).toLowerCase()};`).join("\n") + "\n}";
        break;
    case "json":
        output = JSON.stringify(entries.reduce((acc, [label, color]) => { acc[label] = colorToHex(color).toLowerCase(); return acc; }, {}), null, 2);
        break;
    case "qml":
        output = entries.map(([label, color]) => `readonly property color ${"c" + slug(label).replace(/-([a-z0-9])/g, (unused, ch) => ch.toUpperCase()).replace(/^c(\w)/, (unused, ch) => "c" + ch.toUpperCase())}: "${colorToHex(color)}"`).join("\n");
        break;
    default: {
        const width = Math.max(...entries.map(([label]) => label.length));
        output = entries.map(([label, color]) => {
            const lch = rgbToOklch(color);
            return `${label.padEnd(width)}  ${colorToHex(color)}  oklch(${(lch.L * 100).toFixed(1)}% ${lch.C.toFixed(3)} ${lch.h.toFixed(1)})`;
        }).join("\n");
    }
    }
    return {
        output,
        meta: {
            colors: entries.length,
            visual: { kind: "swatches", items: entries.map(([label, color]) => ({ label, color: colorToHex(color) })) }
        }
    };
}

// ─── 14. Data formats: JSON, YAML, TOML ───────────────────────────────────────
// YAML covers the everyday block subset: mappings, sequences, flow
// collections, block scalars (| and >), quotes, anchors, aliases and <<
// merges. TOML follows v1.0 (dates stay strings, which JSON needs anyway).

function yamlStripComment(text) {
    let quote = "";
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (quote) {
            if (ch === "\\" && quote === "\"") i++;
            else if (ch === quote) quote = "";
        } else if (ch === "\"" || ch === "'") {
            if (i === 0 || /[\s:,\[{-]/.test(text[i - 1])) quote = ch;
        } else if (ch === "#" && (i === 0 || /\s/.test(text[i - 1]))) {
            return text.slice(0, i).replace(/\s+$/, "");
        }
    }
    return text.replace(/\s+$/, "");
}

function yamlUnquoteDouble(body) {
    return body.replace(/\\(u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)/g, (unused, esc) => {
        switch (esc[0]) {
        case "n": return "\n";
        case "t": return "\t";
        case "r": return "\r";
        case "0": return "\0";
        case "u": case "x": return String.fromCharCode(parseInt(esc.slice(1), 16));
        default: return esc;
        }
    });
}

function yamlScalar(text) {
    const s = String(text).trim();
    if (s.length >= 2 && s[0] === "\"" && s[s.length - 1] === "\"")
        return yamlUnquoteDouble(s.slice(1, -1));
    if (s.length >= 2 && s[0] === "'" && s[s.length - 1] === "'")
        return s.slice(1, -1).replace(/''/g, "'");
    if (s === "" || s === "~" || /^null$/i.test(s))
        return null;
    if (/^true$/i.test(s)) return true;
    if (/^false$/i.test(s)) return false;
    if (/^[-+]?\d+$/.test(s) && Math.abs(Number(s)) <= Number.MAX_SAFE_INTEGER) return Number(s);
    if (/^0x[0-9a-fA-F]+$/.test(s)) return parseInt(s.slice(2), 16);
    if (/^0o[0-7]+$/.test(s)) return parseInt(s.slice(2), 8);
    if (/^[-+]?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?$/.test(s)) return Number(s);
    if (/^[-+]?\.(inf|Inf|INF)$/.test(s)) return s[0] === "-" ? -Infinity : Infinity;
    if (/^\.(nan|NaN|NAN)$/.test(s)) return NaN;
    return s;
}

/// Flow collections: [a, b, {c: d}] and {a: 1, b: [2]}.
function yamlParseFlow(text, anchors) {
    let pos = 0;
    const skip = () => { while (pos < text.length && /\s/.test(text[pos])) pos++; };
    const fail = message => { throw new Error(message + " in " + text); };
    const parseQuoted = () => {
        const quote = text[pos];
        let end = pos + 1;
        while (end < text.length) {
            if (quote === "\"" && text[end] === "\\") { end += 2; continue; }
            if (text[end] === quote) {
                if (quote === "'" && text[end + 1] === "'") { end += 2; continue; }
                break;
            }
            end++;
        }
        const raw = text.slice(pos, end + 1);
        pos = end + 1;
        return yamlScalar(raw);
    };
    const parsePlain = stops => {
        const start = pos;
        while (pos < text.length && stops.indexOf(text[pos]) === -1) {
            if (text[pos] === ":" && (pos + 1 >= text.length || /[\s,\]}]/.test(text[pos + 1])) && stops.indexOf(":") !== -1)
                break;
            pos++;
        }
        const raw = text.slice(start, pos).trim();
        if (raw[0] === "*")
            return anchors[raw.slice(1)];
        return yamlScalar(raw);
    };
    const parseValue = stops => {
        skip();
        if (text[pos] === "[") return parseSeq();
        if (text[pos] === "{") return parseMap();
        if (text[pos] === "\"" || text[pos] === "'") return parseQuoted();
        return parsePlain(stops);
    };
    function parseSeq() {
        pos++;
        const out = [];
        skip();
        if (text[pos] === "]") { pos++; return out; }
        for (;;) {
            out.push(parseValue([",", "]"]));
            skip();
            if (text[pos] === ",") { pos++; skip(); if (text[pos] === "]") { pos++; return out; } continue; }
            if (text[pos] === "]") { pos++; return out; }
            fail("Expected , or ]");
        }
    }
    function parseMap() {
        pos++;
        const out = {};
        skip();
        if (text[pos] === "}") { pos++; return out; }
        for (;;) {
            skip();
            const key = text[pos] === "\"" || text[pos] === "'" ? parseQuoted() : parsePlain([":", ",", "}"]);
            skip();
            let value = null;
            if (text[pos] === ":") { pos++; value = parseValue([",", "}"]); skip(); }
            out[String(key)] = value;
            if (text[pos] === ",") { pos++; skip(); if (text[pos] === "}") { pos++; return out; } continue; }
            if (text[pos] === "}") { pos++; return out; }
            fail("Expected , or }");
        }
    }
    const value = parseValue([]);
    skip();
    if (pos < text.length)
        fail("Unexpected text after the collection");
    return value;
}

const YAML_KEY_RE = /^(?:"((?:[^"\\]|\\.)*)"|'((?:[^']|'')*)'|([^\s"'#\-?:,\[\]{}][^#]*?|[-?:][^\s#][^#]*?))\s*:(?:\s+(.*))?$/;

function yamlParse(source) {
    const lines = [];
    const rawLines = String(source).replace(/\r\n?/g, "\n").replace(/\t/g, "  ").split("\n");
    for (let i = 0; i < rawLines.length; i++) {
        const raw = rawLines[i];
        if (/^(---|\.\.\.)(\s|$)/.test(raw)) {
            if (lines.length > 0 && raw.startsWith("---"))
                throw new Error("Only one YAML document is supported (line " + (i + 1) + ")");
            continue;
        }
        if (/^%/.test(raw))
            continue;
        lines.push({ indent: raw.length - raw.replace(/^ +/, "").length, text: raw.trim(), raw, line: i + 1 });
    }
    const anchors = {};
    let index = 0;
    const significant = () => {
        while (index < lines.length && (lines[index].text === "" || lines[index].text[0] === "#"))
            index++;
        return index < lines.length ? lines[index] : null;
    };

    // "&name value", "!!tag value", "*alias".
    const decorate = text => {
        let rest = text, anchor = null;
        for (;;) {
            const tag = rest.match(/^!\S*\s*/);
            if (tag) { rest = rest.slice(tag[0].length); continue; }
            const anc = rest.match(/^&(\S+)\s*/);
            if (anc) { anchor = anc[1]; rest = rest.slice(anc[0].length); continue; }
            break;
        }
        return { anchor, rest };
    };

    const blockScalar = (header, parentIndent) => {
        const folded = header[0] === ">";
        const chomp = header.indexOf("-") !== -1 ? "strip" : (header.indexOf("+") !== -1 ? "keep" : "clip");
        const collected = [];
        let blockIndent = -1;
        while (index < lines.length) {
            const line = lines[index];
            if (line.text === "") { collected.push(""); index++; continue; }
            if (line.indent <= parentIndent) break;
            if (blockIndent < 0) blockIndent = line.indent;
            if (line.indent < blockIndent) break;
            collected.push(line.raw.slice(blockIndent));
            index++;
        }
        let trailing = 0;
        while (collected.length > 0 && collected[collected.length - 1] === "") { collected.pop(); trailing++; }
        let body;
        if (folded) {
            body = "";
            for (let i = 0; i < collected.length; i++) {
                const line = collected[i];
                if (i === 0) body = line;
                else if (line === "" || /^\s/.test(line) || /^\s/.test(collected[i - 1]) || collected[i - 1] === "") body += "\n" + line;
                else body += " " + line;
            }
        } else {
            body = collected.join("\n");
        }
        if (chomp === "strip") return body;
        if (chomp === "keep") return body + "\n".repeat(trailing + 1);
        return collected.length > 0 ? body + "\n" : body;
    };

    // Inline value after "key:" or "- ": scalar, flow collection or block scalar.
    const inlineValue = (text, parentIndent) => {
        const { anchor, rest } = decorate(text);
        let value;
        if (rest[0] === "*") {
            const name = rest.slice(1).trim();
            if (!(name in anchors)) throw new Error("Unknown alias *" + name);
            value = anchors[name];
        } else if (/^[|>][-+0-9]*$/.test(rest)) {
            value = blockScalar(rest, parentIndent);
        } else if (rest[0] === "[" || rest[0] === "{") {
            // Flow collections may continue on the following lines.
            let flow = rest;
            const balance = s => { let depth = 0, q = ""; for (const ch of s) { if (q) { if (ch === q) q = ""; } else if (ch === "\"" || ch === "'") q = ch; else if (ch === "[" || ch === "{") depth++; else if (ch === "]" || ch === "}") depth--; } return depth; };
            while (balance(flow) > 0 && index < lines.length) {
                flow += " " + yamlStripComment(lines[index].text);
                index++;
            }
            value = yamlParseFlow(flow, anchors);
        } else if (rest === "" && anchor !== null) {
            const next = significant();
            value = next && next.indent > parentIndent ? parseNode(next.indent) : null;
        } else {
            value = yamlScalar(rest);
        }
        if (anchor !== null) anchors[anchor] = value;
        return value;
    };

    function parseNode(indent) {
        const first = significant();
        if (!first || first.indent < indent)
            return null;
        const text = yamlStripComment(first.text);
        if (text === "-" || text.startsWith("- "))
            return parseSequence(first.indent);
        if (YAML_KEY_RE.test(text))
            return parseMapping(first.indent);
        // A plain or quoted scalar, possibly folded over several lines.
        index++;
        let scalarText = text;
        while (index < lines.length && lines[index].text !== "" && lines[index].indent >= indent && !YAML_KEY_RE.test(lines[index].text) && !lines[index].text.startsWith("- ")) {
            scalarText += " " + yamlStripComment(lines[index].text);
            index++;
        }
        return inlineValue(scalarText, first.indent - 1);
    }

    function parseSequence(indent) {
        const out = [];
        for (let line = significant(); line && line.indent === indent; line = significant()) {
            const text = yamlStripComment(line.text);
            if (!(text === "-" || text.startsWith("- ")))
                break;
            const rest = text === "-" ? "" : text.slice(2).replace(/^\s+/, "");
            if (rest === "") {
                index++;
                const next = significant();
                out.push(next && next.indent > indent ? parseNode(next.indent) : null);
                continue;
            }
            const restColumn = indent + (line.text.length - line.text.slice(1).replace(/^\s+/, "").length);
            const { anchor, rest: body } = decorate(rest);
            if (YAML_KEY_RE.test(body) || body === "-" || body.startsWith("- ")) {
                // "- key: value" opens a mapping at the column after the dash.
                lines[index] = { indent: restColumn + (rest.length - body.length), text: body, raw: " ".repeat(restColumn + (rest.length - body.length)) + body, line: line.line };
                const value = parseNode(lines[index].indent);
                if (anchor !== null) anchors[anchor] = value;
                out.push(value);
                continue;
            }
            index++;
            out.push(inlineValue(rest, indent));
        }
        return out;
    }

    function parseMapping(indent) {
        const out = {};
        for (let line = significant(); line && line.indent === indent; line = significant()) {
            const text = yamlStripComment(line.text);
            const match = text.match(YAML_KEY_RE);
            if (!match)
                throw new Error(`Line ${line.line}: expected "key: value", got "${text}"`);
            const key = match[1] !== undefined ? yamlUnquoteDouble(match[1]) : match[2] !== undefined ? match[2].replace(/''/g, "'") : match[3].trim();
            const rest = (match[4] ?? "").trim();
            index++;
            let value;
            if (rest === "") {
                const next = significant();
                // Sequences may sit at the key's own indentation.
                if (next && (next.indent > indent || (next.indent === indent && /^-(\s|$)/.test(next.text))))
                    value = parseNode(next.indent);
                else
                    value = null;
            } else {
                value = inlineValue(rest, indent);
            }
            if (key === "<<" && value !== null && typeof value === "object") {
                for (const source of Array.isArray(value) ? value : [value]) {
                    for (const k of Object.keys(source)) {
                        if (!(k in out)) out[k] = source[k];
                    }
                }
            } else {
                out[key] = value;
            }
        }
        return out;
    }

    const first = significant();
    if (!first)
        return null;
    const value = parseNode(first.indent);
    const extra = significant();
    if (extra)
        throw new Error(`Line ${extra.line}: unexpected indentation`);
    return value;
}

function yamlQuote(text) {
    if (text === "" || /^[\s]|[\s]$/.test(text) || /^[-?:,\[\]{}#&*!|>'"%@`]/.test(text) || /: |\s#|:$/.test(text)
        || /^(true|false|null|~|yes|no|on|off)$/i.test(text) || /^[-+]?(\d|\.\d)/.test(text) || /^[-+]?\.(inf|nan)$/i.test(text)
        || /[\u0000-\u001f\u007f]/.test(text))
        return JSON.stringify(text);
    return text;
}

function yamlKey(key) {
    return yamlQuote(String(key));
}

function yamlEmit(value, indentSize) {
    const pad = n => " ".repeat(n);
    const scalar = v => {
        if (v === null || v === undefined) return "null";
        if (typeof v === "boolean") return String(v);
        if (typeof v === "number") return isNaN(v) ? ".nan" : (v === Infinity ? ".inf" : (v === -Infinity ? "-.inf" : String(v)));
        return yamlQuote(String(v));
    };
    const isEmpty = v => (Array.isArray(v) && v.length === 0) || (v !== null && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === 0);
    const multiline = (s, depth) => "|" + (s.endsWith("\n") ? "" : "-") + "\n" + s.replace(/\n$/, "").split("\n").map(line => line.length ? pad(depth) + line : "").join("\n");
    const canBlock = s => s.indexOf("\n") !== -1 && !/[\u0000-\u0009\u000b-\u001f]/.test(s) && !/^\s/.test(s) && !/[ ]\n/.test(s);
    function emit(v, depth) {
        if (Array.isArray(v)) {
            return v.map(item => {
                if (item !== null && typeof item === "object" && !isEmpty(item)) {
                    const body = emit(item, depth + indentSize);
                    return pad(depth) + "-" + " ".repeat(Math.max(1, indentSize - 1)) + body.slice(depth + indentSize);
                }
                if (typeof item === "string" && canBlock(item))
                    return pad(depth) + "- " + multiline(item, depth + indentSize);
                return pad(depth) + "- " + (isEmpty(item) ? (Array.isArray(item) ? "[]" : "{}") : scalar(item));
            }).join("\n");
        }
        return Object.keys(v).map(key => {
            const item = v[key];
            if (item !== null && typeof item === "object" && !isEmpty(item))
                return pad(depth) + yamlKey(key) + ":\n" + emit(item, Array.isArray(item) ? depth : depth + indentSize);
            if (typeof item === "string" && canBlock(item))
                return pad(depth) + yamlKey(key) + ": " + multiline(item, depth + indentSize);
            return pad(depth) + yamlKey(key) + ": " + (isEmpty(item) ? (Array.isArray(item) ? "[]" : "{}") : scalar(item));
        }).join("\n");
    }
    if (value === null || typeof value !== "object")
        return scalar(value);
    if (isEmpty(value))
        return Array.isArray(value) ? "[]" : "{}";
    return emit(value, 0);
}

function tomlParse(source) {
    const text = String(source).replace(/\r\n?/g, "\n");
    let pos = 0;
    const root = {};
    let current = root;
    const fail = message => { throw new Error(`Line ${text.slice(0, pos).split("\n").length}: ${message}`); };
    const skipSpace = () => { while (pos < text.length && (text[pos] === " " || text[pos] === "\t")) pos++; };
    const skipComment = () => { if (text[pos] === "#") while (pos < text.length && text[pos] !== "\n") pos++; };
    const skipAll = () => { for (;;) { skipSpace(); skipComment(); if (text[pos] === "\n") { pos++; continue; } break; } };
    const expectLineEnd = () => { skipSpace(); skipComment(); if (pos < text.length && text[pos] !== "\n") fail("Expected the end of the line"); };

    const basicEscape = () => {
        const ch = text[pos + 1];
        pos += 2;
        switch (ch) {
        case "b": return "\b";
        case "t": return "\t";
        case "n": return "\n";
        case "f": return "\f";
        case "r": return "\r";
        case "\"": return "\"";
        case "\\": return "\\";
        case "e": return "\u001b";
        case "u": { const hex = text.substr(pos, 4); pos += 4; return String.fromCharCode(parseInt(hex, 16)); }
        case "U": { const code = parseInt(text.substr(pos, 8), 16); pos += 8; return String.fromCodePoint(code); }
        default: fail("Bad escape \\" + ch);
        }
        return "";
    };
    const parseString = () => {
        if (text.startsWith("\"\"\"", pos)) {
            pos += 3;
            if (text[pos] === "\n") pos++;
            let out = "";
            while (pos < text.length && !text.startsWith("\"\"\"", pos)) {
                if (text[pos] === "\\") {
                    if (/^\\[ \t]*\n/.test(text.slice(pos, pos + 64))) { pos++; while (/[\s]/.test(text[pos])) pos++; continue; }
                    out += basicEscape();
                    continue;
                }
                out += text[pos++];
            }
            pos += 3;
            // Up to two quotes may close the content: """a"""" ends in a quote.
            while (text[pos] === "\"") { out += "\""; pos++; }
            return out;
        }
        if (text.startsWith("'''", pos)) {
            pos += 3;
            if (text[pos] === "\n") pos++;
            const end = text.indexOf("'''", pos);
            if (end < 0) fail("Unclosed '''");
            let out = text.slice(pos, end);
            pos = end + 3;
            while (text[pos] === "'") { out += "'"; pos++; }
            return out;
        }
        if (text[pos] === "'") {
            const end = text.indexOf("'", pos + 1);
            if (end < 0 || text.slice(pos, end).indexOf("\n") !== -1) fail("Unclosed string");
            const out = text.slice(pos + 1, end);
            pos = end + 1;
            return out;
        }
        pos++;
        let out = "";
        while (pos < text.length && text[pos] !== "\"") {
            if (text[pos] === "\n") fail("Unclosed string");
            if (text[pos] === "\\") { out += basicEscape(); continue; }
            out += text[pos++];
        }
        pos++;
        return out;
    };
    const parseKeyPart = () => {
        skipSpace();
        if (text[pos] === "\"" || text[pos] === "'")
            return parseString();
        const match = text.slice(pos).match(/^[A-Za-z0-9_-]+/);
        if (!match) fail("Expected a key");
        pos += match[0].length;
        return match[0];
    };
    const parseKey = () => {
        const parts = [parseKeyPart()];
        for (;;) {
            skipSpace();
            if (text[pos] !== ".") break;
            pos++;
            parts.push(parseKeyPart());
        }
        return parts;
    };
    const parseValue = () => {
        skipSpace();
        const ch = text[pos];
        if (ch === "\"" || ch === "'") return parseString();
        if (ch === "[") {
            pos++;
            const out = [];
            for (;;) {
                skipAll();
                if (text[pos] === "]") { pos++; return out; }
                out.push(parseValue());
                skipAll();
                if (text[pos] === ",") { pos++; continue; }
                if (text[pos] === "]") { pos++; return out; }
                fail("Expected , or ] in an array");
            }
        }
        if (ch === "{") {
            pos++;
            const out = {};
            skipSpace();
            if (text[pos] === "}") { pos++; return out; }
            for (;;) {
                const key = parseKey();
                skipSpace();
                if (text[pos] !== "=") fail("Expected = in an inline table");
                pos++;
                assignPath(out, key, parseValue());
                skipSpace();
                if (text[pos] === ",") { pos++; continue; }
                if (text[pos] === "}") { pos++; return out; }
                fail("Expected , or } in an inline table");
            }
        }
        const rest = text.slice(pos);
        let match = rest.match(/^(true|false)(?![A-Za-z0-9_])/);
        if (match) { pos += match[0].length; return match[1] === "true"; }
        match = rest.match(/^\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:[Zz]|[-+]\d{2}:\d{2})?)?|^\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?/);
        if (match) { pos += match[0].length; return match[0]; }
        match = rest.match(/^[-+]?(inf|nan)(?![A-Za-z0-9_])/);
        if (match) { pos += match[0].length; return match[1] === "nan" ? NaN : (match[0][0] === "-" ? -Infinity : Infinity); }
        match = rest.match(/^0x[0-9A-Fa-f_]+|^0o[0-7_]+|^0b[01_]+/);
        if (match) { pos += match[0].length; const digits = match[0].slice(2).replace(/_/g, ""); return parseInt(digits, match[0][1] === "x" ? 16 : match[0][1] === "o" ? 8 : 2); }
        match = rest.match(/^[-+]?\d[\d_]*(\.\d[\d_]*)?([eE][-+]?\d[\d_]*)?/);
        if (match) { pos += match[0].length; return Number(match[0].replace(/_/g, "")); }
        fail("Unknown value");
        return null;
    };
    function assignPath(target, path, value) {
        let node = target;
        for (let i = 0; i < path.length - 1; i++) {
            if (!(path[i] in node)) node[path[i]] = {};
            node = node[path[i]];
            if (node === null || typeof node !== "object" || Array.isArray(node)) fail(`"${path.slice(0, i + 1).join(".")}" is not a table`);
        }
        if (path[path.length - 1] in node) fail(`Duplicate key "${path.join(".")}"`);
        node[path[path.length - 1]] = value;
    }
    const tableAt = (path, arrayTable) => {
        let node = root;
        for (let i = 0; i < path.length; i++) {
            const key = path[i];
            const last = i === path.length - 1;
            if (last && arrayTable) {
                if (!(key in node)) node[key] = [];
                if (!Array.isArray(node[key])) fail(`"${path.join(".")}" is not an array of tables`);
                const table = {};
                node[key].push(table);
                return table;
            }
            if (!(key in node)) node[key] = {};
            node = node[key];
            if (Array.isArray(node)) node = node[node.length - 1];
            if (node === null || typeof node !== "object") fail(`"${path.slice(0, i + 1).join(".")}" is not a table`);
        }
        return node;
    };

    for (;;) {
        skipAll();
        if (pos >= text.length) break;
        if (text.startsWith("[[", pos)) {
            pos += 2;
            const path = parseKey();
            skipSpace();
            if (!text.startsWith("]]", pos)) fail("Expected ]]");
            pos += 2;
            current = tableAt(path, true);
            expectLineEnd();
        } else if (text[pos] === "[") {
            pos++;
            const path = parseKey();
            skipSpace();
            if (text[pos] !== "]") fail("Expected ]");
            pos++;
            current = tableAt(path, false);
            expectLineEnd();
        } else {
            const key = parseKey();
            skipSpace();
            if (text[pos] !== "=") fail("Expected = after the key");
            pos++;
            assignPath(current, key, parseValue());
            expectLineEnd();
        }
    }
    return root;
}

function tomlKey(key) {
    return /^[A-Za-z0-9_-]+$/.test(key) ? key : JSON.stringify(key);
}

function tomlEmit(value, dropped) {
    if (value === null || typeof value !== "object" || Array.isArray(value))
        throw new Error("TOML needs a table (an object) at the top level.");
    const isTable = v => v !== null && typeof v === "object" && !Array.isArray(v);
    const isTableArray = v => Array.isArray(v) && v.length > 0 && v.every(isTable);
    const inline = (v, path) => {
        if (v === null || v === undefined) { dropped.push(path); return null; }
        if (typeof v === "string") return JSON.stringify(v);
        if (typeof v === "boolean") return String(v);
        if (typeof v === "number") {
            if (isNaN(v)) return "nan";
            if (!isFinite(v)) return v > 0 ? "inf" : "-inf";
            return String(v);
        }
        if (Array.isArray(v)) return "[" + v.map((item, i) => inline(item, path + "[" + i + "]")).filter(item => item !== null).join(", ") + "]";
        return "{ " + Object.keys(v).map(k => { const item = inline(v[k], path + "." + k); return item === null ? null : tomlKey(k) + " = " + item; }).filter(Boolean).join(", ") + " }";
    };
    const sections = [];
    const emitTable = (table, path, header) => {
        const lines = [];
        const keys = Object.keys(table);
        for (const key of keys) {
            const v = table[key];
            if (isTable(v) || isTableArray(v)) continue;
            const item = inline(v, path.concat(key).join("."));
            if (item !== null) lines.push(tomlKey(key) + " = " + item);
        }
        if (header !== null && (lines.length > 0 || keys.every(key => !isTable(table[key]) && !isTableArray(table[key]))))
            sections.push([header].concat(lines).join("\n"));
        else if (lines.length > 0)
            sections.push(lines.join("\n"));
        for (const key of keys) {
            const v = table[key];
            const childPath = path.concat(key);
            const name = childPath.map(tomlKey).join(".");
            if (isTable(v)) emitTable(v, childPath, "[" + name + "]");
            else if (isTableArray(v)) v.forEach(item => emitTable(item, childPath, "[[" + name + "]]"));
        }
    };
    emitTable(value, [], null);
    return sections.join("\n\n");
}

function detectDataFormat(text) {
    const trimmed = text.trim();
    if (/^[\[{]/.test(trimmed)) {
        try { JSON.parse(trimmed); return "json"; } catch (err) { /* not JSON */ }
    }
    if (/^\s*\[\[?[A-Za-z0-9_."' -]+\]\]?\s*$/m.test(text) || /^\s*[A-Za-z0-9_."-]+\s*=\s*\S/m.test(text))
        return "toml";
    return "yaml";
}

function toolDataConverter(input = "", options = {}) {
    const text = String(input);
    if (text.trim().length === 0)
        return { output: "" };
    const from = (options.from ?? "auto") === "auto" ? detectDataFormat(text) : options.from;
    const to = options.to ?? "json";
    const names = { json: "JSON", yaml: "YAML", toml: "TOML" };
    let value;
    try {
        value = from === "json" ? JSON.parse(text) : from === "toml" ? tomlParse(text) : yamlParse(text);
    } catch (err) {
        return { output: "", error: `${names[from]}: ${err.message}` };
    }
    const indent = options.indent === "4" ? 4 : 2;
    const dropped = [];
    let output;
    try {
        output = to === "yaml" ? yamlEmit(value, indent) : to === "toml" ? tomlEmit(value, dropped) : JSON.stringify(value, null, indent);
    } catch (err) {
        return { output: "", error: `${names[to]}: ${err.message}` };
    }
    const meta = { from: names[from], to: names[to] };
    if (dropped.length > 0) {
        meta.dropped = dropped.length;
        output += `\n\n# TOML has no null: dropped ${dropped.slice(0, 5).join(", ")}${dropped.length > 5 ? "…" : ""}`;
    }
    return { output, meta };
}

// ─── 15. Code formatters: XML/HTML, CSS, SQL ─────────────────────────────────

const HTML_VOID_ELEMENTS = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"];

function formatMarkup(text, options, html) {
    const indentUnit = options.indent === "tab" ? "\t" : " ".repeat(options.indent === "4" ? 4 : 2);
    const minify = options.mode === "minify";
    const tokenRe = html
        ? /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<!(?:"[^"]*"|'[^']*'|[^'">])*>|<(script|style|pre|textarea)\b(?:"[^"]*"|'[^']*'|[^'">])*>[\s\S]*?<\/\1\s*>|<\/?[A-Za-z](?:"[^"]*"|'[^']*'|[^'">])*>|[^<]+|</gi
        : /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<!(?:"[^"]*"|'[^']*'|[^'">])*>|<\/?[A-Za-z_:](?:"[^"]*"|'[^']*'|[^'">])*>|[^<]+|</g;
    const tokens = text.match(tokenRe) ?? [];
    const kindOf = token => {
        if (token.startsWith("<!--")) return "comment";
        if (token.startsWith("<![CDATA[") || token.startsWith("<?") || token.startsWith("<!")) return "special";
        if (token.startsWith("</")) return "close";
        if (token.startsWith("<") && token.length > 1) {
            const name = (token.match(/^<([A-Za-z_:][\w:.-]*)/) ?? [])[1] ?? "";
            if (/\/>$/.test(token) || (html && HTML_VOID_ELEMENTS.indexOf(name.toLowerCase()) !== -1)) return "single";
            if (html && /^<(script|style|pre|textarea)\b/i.test(token) && /<\/(script|style|pre|textarea)\s*>$/i.test(token)) return "raw";
            return "open";
        }
        return "text";
    };
    const items = tokens.map(token => ({ token, kind: kindOf(token) }))
        .filter(item => !(item.kind === "text" && item.token.trim() === ""))
        .filter(item => !(minify && item.kind === "comment"));
    if (minify) {
        return items.map(item => item.kind === "text" ? item.token.replace(/\s+/g, " ").trim()
            : item.kind === "raw" || item.kind === "special" ? item.token
            : item.token.replace(/\s+/g, " ").replace(/\s+(\/?>)$/, "$1")).join("");
    }
    const out = [];
    let depth = 0;
    for (let i = 0; i < items.length; i++) {
        const item = items[i];
        const pad = indentUnit.repeat(Math.max(0, depth));
        if (item.kind === "open") {
            const next = items[i + 1], after = items[i + 2];
            // <a>short text</a> and <a></a> stay on one line.
            if (next && next.kind === "close") {
                out.push(pad + item.token + next.token);
                i++;
                continue;
            }
            if (next && next.kind === "text" && after && after.kind === "close" && next.token.indexOf("\n") === -1 && next.token.trim().length <= 80) {
                out.push(pad + item.token + next.token.trim() + after.token);
                i += 2;
                continue;
            }
            out.push(pad + item.token);
            depth++;
        } else if (item.kind === "close") {
            depth = Math.max(0, depth - 1);
            out.push(indentUnit.repeat(depth) + item.token);
        } else if (item.kind === "text") {
            for (const line of item.token.trim().split(/\n/))
                out.push(pad + line.trim());
        } else {
            out.push(pad + item.token);
        }
    }
    return out.join("\n");
}

/// Splits CSS into strings, comments and structure, keeping quoted text whole.
function formatCss(text, options) {
    const indentUnit = options.indent === "tab" ? "\t" : " ".repeat(options.indent === "4" ? 4 : 2);
    const minify = options.mode === "minify";
    const out = [];
    let buffer = "";
    let depth = 0;
    const pad = () => indentUnit.repeat(depth);
    const squeeze = s => s.replace(/\s+/g, " ").trim();
    const flushDeclaration = () => {
        const decl = squeeze(buffer);
        buffer = "";
        if (!decl) return;
        const colon = decl.indexOf(":");
        if (minify) {
            out.push((colon > 0 ? decl.slice(0, colon).trim() + ":" + decl.slice(colon + 1).trim() : decl).replace(/\s*,\s*/g, ",").replace(/\s*!important/i, "!important") + ";");
        } else {
            out.push(pad() + (colon > 0 && !/^@/.test(decl) ? decl.slice(0, colon).trim() + ": " + decl.slice(colon + 1).trim() : decl).replace(/\s*!\s*important$/i, " !important") + ";");
        }
    };
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (ch === "\"" || ch === "'") {
            let j = i + 1;
            while (j < text.length && text[j] !== ch) { if (text[j] === "\\") j++; j++; }
            buffer += text.slice(i, j + 1);
            i = j;
        } else if (ch === "/" && text[i + 1] === "*") {
            const end = text.indexOf("*/", i + 2);
            const comment = text.slice(i, end < 0 ? text.length : end + 2);
            i = end < 0 ? text.length : end + 1;
            if (!minify) {
                if (squeeze(buffer)) buffer += comment;
                else out.push(pad() + comment);
            }
        } else if (ch === "{") {
            const selector = squeeze(buffer);
            buffer = "";
            if (minify)
                out.push(selector.replace(/\s*([,>+~])\s*/g, "$1") + "{");
            else
                out.push(pad() + selector.replace(/\s*,\s*/g, ", ") + " {");
            depth++;
        } else if (ch === ";") {
            flushDeclaration();
        } else if (ch === "}") {
            flushDeclaration();
            depth = Math.max(0, depth - 1);
            if (minify) {
                if (out.length > 0 && out[out.length - 1].endsWith(";")) out[out.length - 1] = out[out.length - 1].slice(0, -1);
                out.push("}");
            } else {
                out.push(pad() + "}");
                if (depth === 0) out.push("");
            }
        } else {
            buffer += ch;
        }
    }
    flushDeclaration();
    if (minify)
        return out.join("");
    return out.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

const SQL_KEYWORDS = ["select", "from", "where", "and", "or", "not", "in", "is", "null", "like", "ilike", "between", "exists",
    "join", "inner", "left", "right", "full", "outer", "cross", "on", "using", "as", "group", "by", "order", "having", "limit",
    "offset", "union", "all", "intersect", "except", "insert", "into", "values", "update", "set", "delete", "create", "table",
    "view", "index", "drop", "alter", "add", "column", "primary", "key", "foreign", "references", "default", "unique", "check",
    "constraint", "distinct", "case", "when", "then", "else", "end", "asc", "desc", "with", "recursive", "returning", "conflict",
    "do", "nothing", "true", "false", "over", "partition", "window", "if", "replace", "begin", "commit", "rollback", "fetch",
    "first", "next", "rows", "only", "natural", "lateral", "count", "sum", "avg", "min", "max", "coalesce", "cast", "integer",
    "int", "text", "varchar", "boolean", "timestamp", "date", "serial", "bigint", "numeric", "real", "uuid", "jsonb", "json"];

// Clause starters: [words..., indent body?]. Longest match wins.
const SQL_CLAUSES = [
    ["select", "distinct"], ["select"], ["from"], ["where"], ["group", "by"], ["order", "by"], ["having"], ["limit"], ["offset"],
    ["union", "all"], ["union"], ["intersect"], ["except"], ["insert", "into"], ["values"], ["update"], ["set"],
    ["delete", "from"], ["returning"], ["with", "recursive"], ["with"], ["on", "conflict"], ["window"],
    ["left", "outer", "join"], ["right", "outer", "join"], ["full", "outer", "join"], ["left", "join"], ["right", "join"],
    ["full", "join"], ["inner", "join"], ["cross", "join"], ["natural", "join"], ["join"], ["fetch", "first"], ["fetch", "next"]
];

function tokenizeSql(text) {
    const re = /(--[^\n]*|\/\*[\s\S]*?\*\/)|('(?:[^']|'')*'|"(?:[^"]|"")*"|`[^`]*`|\$\$[\s\S]*?\$\$)|(\s+)|([A-Za-z_][\w$]*)|(\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|(<>|<=|>=|!=|::|\|\||->>|->|[(),;.*=<>+\-\/%])|(.)/g;
    const tokens = [];
    for (let m = re.exec(text); m !== null; m = re.exec(text)) {
        if (m[1]) tokens.push({ type: "comment", text: m[1] });
        else if (m[2]) tokens.push({ type: "string", text: m[2] });
        else if (m[3]) continue;
        else if (m[4]) tokens.push({ type: "word", text: m[4] });
        else if (m[5]) tokens.push({ type: "number", text: m[5] });
        else tokens.push({ type: "symbol", text: m[6] || m[7] });
    }
    return tokens;
}

function formatSql(text, options) {
    const indentUnit = options.indent === "tab" ? "\t" : " ".repeat(options.indent === "4" ? 4 : 2);
    const upper = options.uppercase !== false;
    const tokens = tokenizeSql(text);
    const word = token => token.type === "word" && SQL_KEYWORDS.indexOf(token.text.toLowerCase()) !== -1
        ? (upper ? token.text.toUpperCase() : token.text.toLowerCase()) : token.text;
    const glue = (prev, next) => {
        if (!prev) return "";
        if (next === "," || next === ")" || next === ";" || next === "." || next === "::") return "";
        if (prev === "(" || prev === "." || prev === "::") return "";
        if (next === "(" && /^[A-Za-z_]/.test(prev) && SQL_CLAUSES.every(c => c.length !== 1 || c[0] !== prev.toLowerCase()) && ["in", "and", "or", "on", "as", "exists", "not", "values", "into", "using"].indexOf(prev.toLowerCase()) === -1) return "";
        return " ";
    };
    if (options.mode === "minify") {
        let out = "", prev = "";
        for (const token of tokens) {
            if (token.type === "comment") continue;
            const t = word(token);
            const g = glue(prev, t);
            out += (g === " " && (/^[,()=<>+\-*\/;]$/.test(t) || /^[,()=<>+\-*\/]$/.test(prev)) ? "" : g) + t;
            prev = t;
        }
        return out;
    }

    const lines = [];
    let line = "";
    let prev = "";
    let depth = 0;          // base indent of the current statement level
    let level = 0;          // indent of the line being built
    const parens = [];      // per "(": null, or the indents to restore after a subquery
    let clause = "";
    const newLine = extra => {
        if (line.trim().length > 0) lines.push(line.replace(/\s+$/, ""));
        level = Math.max(0, depth + (extra ?? 0));
        line = indentUnit.repeat(level);
        prev = "";
    };
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token.type === "comment") {
            if (token.text.startsWith("--")) { line += (line.trim() ? " " : "") + token.text; newLine(1); }
            else line += (line.trim() ? " " : "") + token.text;
            continue;
        }
        const lower = token.type === "word" ? token.text.toLowerCase() : "";
        // A clause keyword (possibly several words) starts a line at the base indent.
        let clauseWords = null;
        if (token.type === "word") {
            for (const candidate of SQL_CLAUSES) {
                if (candidate.every((w, k) => tokens[i + k] && tokens[i + k].type === "word" && tokens[i + k].text.toLowerCase() === w) && (!clauseWords || candidate.length > clauseWords.length))
                    clauseWords = candidate;
            }
        }
        if (clauseWords) {
            if (lines.length > 0 || line.trim().length > 0) newLine(0);
            const textWords = clauseWords.map((unused, k) => word(tokens[i + k])).join(" ");
            line += textWords;
            prev = textWords;
            clause = clauseWords[clauseWords.length - 1];
            i += clauseWords.length - 1;
            // Body of list clauses goes on the next line, indented.
            if (["select", "distinct", "set", "by", "returning", "values"].indexOf(clause) !== -1) newLine(1);
            continue;
        }
        if ((lower === "and" || lower === "or") && ["where", "having", "join", "on"].indexOf(clause) !== -1 && (parens.length === 0 || parens[parens.length - 1] !== null)) {
            newLine(1);
            line += word(token);
            prev = word(token);
            continue;
        }
        if (lower === "on" && clause === "join") clause = "on";
        const t = token.type === "word" ? word(token) : token.text;
        if (t === "(") {
            const nextWord = tokens[i + 1] && tokens[i + 1].type === "word" ? tokens[i + 1].text.toLowerCase() : "";
            const sub = nextWord === "select" || nextWord === "with";
            line += (clause === "into" && prev !== "" ? " " : glue(prev, t)) + t;
            prev = t;
            // A subquery indents from the line that opens it.
            parens.push(sub ? { depth, level, clause } : null);
            if (sub) { depth = level + 1; newLine(0); }
            continue;
        }
        if (t === ")") {
            const sub = parens.pop();
            if (sub) {
                depth = sub.level;
                newLine(0);
                line += ")";
                prev = ")";
                depth = sub.depth;
                clause = sub.clause;
                continue;
            }
            line += t;
            prev = t;
            continue;
        }
        if (t === ",") {
            line += ",";
            prev = ",";
            if (["select", "distinct", "set", "by", "returning"].indexOf(clause) !== -1 && (parens.length === 0 || parens[parens.length - 1] !== null)) newLine(1);
            continue;
        }
        if (t === ";") {
            line += ";";
            newLine(0);
            lines.push("");
            clause = "";
            continue;
        }
        line += glue(prev, t) + t;
        prev = t;
    }
    newLine(0);
    while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
    return lines.join("\n");
}

function toolCodeFormatter(input = "", options = {}) {
    const text = String(input);
    if (text.trim().length === 0)
        return { output: "" };
    let language = options.language ?? "auto";
    if (language === "auto") {
        const trimmed = text.trim();
        if (/^<(!doctype html|html|head|body|div|span|p|a|ul|section)\b/i.test(trimmed)) language = "html";
        else if (trimmed.startsWith("<")) language = "xml";
        else if (/^\s*(select|insert|update|delete|create|alter|drop|with)\b/i.test(trimmed)) language = "sql";
        else language = "css";
    }
    let output;
    switch (language) {
    case "html": output = formatMarkup(text, options, true); break;
    case "xml": output = formatMarkup(text, options, false); break;
    case "sql": output = formatSql(text, options); break;
    default: output = formatCss(text, options);
    }
    const names = { html: "HTML", xml: "XML", sql: "SQL", css: "CSS" };
    const meta = { language: names[language], chars: output.length };
    if (options.mode === "minify" && text.length > output.length)
        meta.saved = Math.round((text.length - output.length) / text.length * 100) + "%";
    return { output, meta };
}

// ─── 16. Developer tools ──────────────────────────────────────────────────────
// One slot per tool: each tool's code lives between its own markers.

// @slot-begin curl_converter
function curlcFromCodePoint(cp) {
    if (cp <= 0xffff)
        return String.fromCharCode(cp);
    const adj = cp - 0x10000;
    return String.fromCharCode(0xd800 + (adj >> 10), 0xdc00 + (adj & 0x3ff));
}

function curlcShellQuote(str) {
    const s = String(str);
    if (s.length === 0)
        return "''";
    if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(s))
        return s;
    return "'" + s.split("'").join("'\\''") + "'";
}

function curlcShellQuoteAlways(str) {
    return "'" + String(str).split("'").join("'\\''") + "'";
}

function curlcJsString(str) {
    return JSON.stringify(String(str));
}

function curlcPyString(str) {
    const s = String(str);
    let out = "\"";
    for (let i = 0; i < s.length; i++) {
        const ch = s.charAt(i);
        if (ch === "\\") out += "\\\\";
        else if (ch === "\"") out += "\\\"";
        else if (ch === "\n") out += "\\n";
        else if (ch === "\r") out += "\\r";
        else if (ch === "\t") out += "\\t";
        else {
            const code = s.charCodeAt(i);
            if (code < 0x20 || code === 0x7f)
                out += "\\x" + code.toString(16).padStart(2, "0");
            else
                out += ch;
        }
    }
    return out + "\"";
}

function curlcPyLiteral(val, indent) {
    const pad = "    ".repeat(indent);
    const innerPad = "    ".repeat(indent + 1);
    if (val === null) return "None";
    if (val === true) return "True";
    if (val === false) return "False";
    if (typeof val === "number") return String(val);
    if (typeof val === "string") return curlcPyString(val);
    if (Array.isArray(val)) {
        if (val.length === 0) return "[]";
        const items = val.map(item => innerPad + curlcPyLiteral(item, indent + 1));
        return "[\n" + items.join(",\n") + ",\n" + pad + "]";
    }
    const keys = Object.keys(val);
    if (keys.length === 0) return "{}";
    const lines = keys.map(k => innerPad + curlcPyString(k) + ": " + curlcPyLiteral(val[k], indent + 1));
    return "{\n" + lines.join(",\n") + ",\n" + pad + "}";
}

function curlcGoString(str) {
    const s = String(str);
    if (s.indexOf("`") === -1 && (s.indexOf("\n") !== -1 || s.indexOf("\"") !== -1)) {
        let safe = true;
        for (let i = 0; i < s.length; i++) {
            const c = s.charCodeAt(i);
            if (c < 0x20 && c !== 0x0a && c !== 0x09) {
                safe = false;
                break;
            }
        }
        if (safe) return "`" + s + "`";
    }
    return JSON.stringify(s);
}

function curlcIsHex(ch) {
    return /^[0-9a-fA-F]$/.test(ch);
}

function curlcIsOctal(ch) {
    return /^[0-7]$/.test(ch);
}

function curlcTokenize(input) {
    const src = String(input).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    const tokens = [];
    let current = "";
    let hasToken = false;
    let i = 0;
    const len = src.length;

    const flush = () => {
        if (hasToken) {
            tokens.push(current);
            current = "";
            hasToken = false;
        }
    };

    while (i < len) {
        const ch = src.charAt(i);

        // Whitespace separates tokens
        if (ch === " " || ch === "\t" || ch === "\n") {
            flush();
            i++;
            continue;
        }

        // Line continuations outside quotes: \<newline> or ^<newline>
        if ((ch === "\\" || ch === "^") && i + 1 < len && src.charAt(i + 1) === "\n") {
            i += 2;
            continue;
        }

        // ANSI-C quoting: $'...'
        if (ch === "$" && i + 1 < len && src.charAt(i + 1) === "'") {
            hasToken = true;
            i += 2;
            let closed = false;
            while (i < len) {
                const c = src.charAt(i);
                if (c === "'") {
                    i++;
                    closed = true;
                    break;
                }
                if (c === "\\" && i + 1 < len) {
                    const next = src.charAt(i + 1);
                    if (next === "a") { current += "\x07"; i += 2; }
                    else if (next === "b") { current += "\b"; i += 2; }
                    else if (next === "e" || next === "E") { current += "\x1b"; i += 2; }
                    else if (next === "f") { current += "\f"; i += 2; }
                    else if (next === "n") { current += "\n"; i += 2; }
                    else if (next === "r") { current += "\r"; i += 2; }
                    else if (next === "t") { current += "\t"; i += 2; }
                    else if (next === "v") { current += "\v"; i += 2; }
                    else if (next === "\\" || next === "'" || next === "\"" || next === "?") {
                        current += next;
                        i += 2;
                    } else if (next === "x") {
                        let hex = "";
                        let j = i + 2;
                        while (j < len && hex.length < 2 && curlcIsHex(src.charAt(j))) {
                            hex += src.charAt(j);
                            j++;
                        }
                        if (hex.length > 0) {
                            current += String.fromCharCode(parseInt(hex, 16));
                            i = j;
                        } else {
                            current += "\\x";
                            i += 2;
                        }
                    } else if (next === "u" || next === "U") {
                        const maxDigits = next === "u" ? 4 : 8;
                        let hex = "";
                        let j = i + 2;
                        while (j < len && hex.length < maxDigits && curlcIsHex(src.charAt(j))) {
                            hex += src.charAt(j);
                            j++;
                        }
                        if (hex.length > 0) {
                            const cp = parseInt(hex, 16);
                            current += cp <= 0x10ffff ? curlcFromCodePoint(cp) : ("\\" + next + hex);
                            i = j;
                        } else {
                            current += "\\" + next;
                            i += 2;
                        }
                    } else if (curlcIsOctal(next)) {
                        let oct = "";
                        let j = i + 1;
                        while (j < len && oct.length < 3 && curlcIsOctal(src.charAt(j))) {
                            oct += src.charAt(j);
                            j++;
                        }
                        current += String.fromCharCode(parseInt(oct, 8) & 0xff);
                        i = j;
                    } else if (next === "c" && i + 2 < len) {
                        const ctrl = src.charAt(i + 2).toUpperCase().charCodeAt(0);
                        current += String.fromCharCode(ctrl === 63 ? 127 : (ctrl & 0x1f));
                        i += 3;
                    } else {
                        current += "\\" + next;
                        i += 2;
                    }
                    continue;
                }
                current += c;
                i++;
            }
            if (!closed)
                return { error: "Unclosed $'...' quote in cURL command." };
            continue;
        }

        // Single-quoted string: '...'
        if (ch === "'") {
            hasToken = true;
            i++;
            let closed = false;
            while (i < len) {
                const c = src.charAt(i);
                if (c === "'") {
                    i++;
                    closed = true;
                    break;
                }
                current += c;
                i++;
            }
            if (!closed)
                return { error: "Unclosed single quote in cURL command." };
            continue;
        }

        // Double-quoted string: "..."
        if (ch === "\"") {
            hasToken = true;
            i++;
            let closed = false;
            while (i < len) {
                const c = src.charAt(i);
                if (c === "\"") {
                    i++;
                    closed = true;
                    break;
                }
                if (c === "\\" && i + 1 < len) {
                    const next = src.charAt(i + 1);
                    if (next === "\n") {
                        i += 2;
                        continue;
                    }
                    if (next === "\"" || next === "\\" || next === "$" || next === "`") {
                        current += next;
                        i += 2;
                        continue;
                    }
                    current += "\\" + next;
                    i += 2;
                    continue;
                }
                current += c;
                i++;
            }
            if (!closed)
                return { error: "Unclosed double quote in cURL command." };
            continue;
        }

        // Windows cmd Copy-as-cURL quoted string: ^"...^"
        if (ch === "^" && i + 1 < len && src.charAt(i + 1) === "\"") {
            hasToken = true;
            i += 2;
            let closed = false;
            while (i < len) {
                const c = src.charAt(i);
                if (c === "^" && i + 1 < len) {
                    const next = src.charAt(i + 1);
                    if (next === "\"") {
                        i += 2;
                        closed = true;
                        break;
                    }
                    if (next === "\n") {
                        current += "\n";
                        i += 2;
                        continue;
                    }
                    // Chrome cmd escaping for embedded quotes: ^\^"
                    if (next === "\\" && i + 3 < len && src.charAt(i + 2) === "^" && src.charAt(i + 3) === "\"") {
                        current += "\"";
                        i += 4;
                        continue;
                    }
                    current += next;
                    i += 2;
                    continue;
                }
                if (c === "\\" && i + 2 < len && src.charAt(i + 1) === "^" && src.charAt(i + 2) === "\"") {
                    current += "\"";
                    i += 3;
                    continue;
                }
                current += c;
                i++;
            }
            if (!closed)
                return { error: "Unclosed ^\" quote in cURL command." };
            continue;
        }

        // Backslash escape outside quotes
        if (ch === "\\" && i + 1 < len) {
            hasToken = true;
            current += src.charAt(i + 1);
            i += 2;
            continue;
        }

        // Windows cmd caret escape outside quotes
        if (ch === "^" && i + 1 < len) {
            const next = src.charAt(i + 1);
            if ("^&|<>%{}".indexOf(next) !== -1) {
                hasToken = true;
                current += next;
                i += 2;
                continue;
            }
        }

        hasToken = true;
        current += ch;
        i++;
    }

    flush();
    return { tokens };
}

function curlcSafeDecode(text) {
    try {
        return decodeURIComponent(String(text).replace(/\+/g, " "));
    } catch (e) {
        return String(text);
    }
}

function curlcParseUrl(rawUrl) {
    let url = String(rawUrl || "").trim();
    if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(url))
        url = "http://" + url;

    const m = url.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(?:([^:@\/?#]*)(?::([^@\/?#]*))?@)?(\[[^\]]+\]|[^:\/?#]*)(?::(\d+))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/);
    if (!m) {
        return {
            full: url,
            base: url,
            scheme: "",
            user: "",
            password: "",
            host: "",
            port: "",
            path: "/",
            queryRaw: "",
            queryParams: [],
            fragment: ""
        };
    }

    const scheme = m[1].toLowerCase();
    const user = m[2] !== undefined ? curlcSafeDecode(m[2]) : "";
    const password = m[3] !== undefined ? curlcSafeDecode(m[3]) : "";
    const hostName = m[4] || "";
    const port = m[5] || "";
    const host = port ? (hostName + ":" + port) : hostName;
    const path = m[6] || "/";
    const queryRaw = m[7] !== undefined ? m[7] : "";
    const fragment = m[8] !== undefined ? m[8] : "";

    const queryParams = [];
    if (queryRaw.length > 0) {
        const parts = queryRaw.split("&");
        for (let i = 0; i < parts.length; i++) {
            const part = parts[i];
            if (part.length === 0) continue;
            const eq = part.indexOf("=");
            if (eq >= 0) {
                queryParams.push({
                    key: curlcSafeDecode(part.slice(0, eq)),
                    value: curlcSafeDecode(part.slice(eq + 1))
                });
            } else {
                queryParams.push({
                    key: curlcSafeDecode(part),
                    value: ""
                });
            }
        }
    }

    const authPart = m[2] !== undefined ? (m[2] + (m[3] !== undefined ? ":" + m[3] : "") + "@") : "";
    const base = scheme + "://" + authPart + host + path;
    return {
        full: url,
        base,
        scheme,
        user,
        password,
        host,
        port,
        path,
        queryRaw,
        queryParams,
        fragment
    };
}

function curlcBuildUrlWithQuery(rawUrl, extraQuery) {
    if (!extraQuery)
        return rawUrl;
    const hashIdx = rawUrl.indexOf("#");
    const main = hashIdx >= 0 ? rawUrl.slice(0, hashIdx) : rawUrl;
    const frag = hashIdx >= 0 ? rawUrl.slice(hashIdx) : "";
    const qIdx = main.indexOf("?");
    let sep = "?";
    if (qIdx >= 0) {
        const existing = main.slice(qIdx + 1);
        sep = existing.length === 0 ? "" : "&";
    }
    return main + sep + extraQuery + frag;
}

function curlcEncodeDataUrlencode(spec) {
    const s = String(spec);
    if (s.charAt(0) === "@")
        return encodeURIComponent("<file:" + s.slice(1) + ">");
    const eq = s.indexOf("=");
    if (eq >= 0) {
        const name = s.slice(0, eq);
        const content = s.slice(eq + 1);
        if (name.length === 0)
            return encodeURIComponent(content);
        return name + "=" + encodeURIComponent(content);
    }
    const at = s.indexOf("@");
    if (at > 0) {
        const name = s.slice(0, at);
        const file = s.slice(at + 1);
        return name + "=" + encodeURIComponent("<file:" + file + ">");
    }
    return encodeURIComponent(s);
}

function curlcTryParseJson(text) {
    const trimmed = String(text || "").trim();
    if (trimmed.length === 0)
        return { ok: false };
    const first = trimmed.charAt(0);
    if (first !== "{" && first !== "[")
        return { ok: false };
    try {
        return { ok: true, value: JSON.parse(trimmed) };
    } catch (e) {
        return { ok: false };
    }
}

function curlcParseHeaderLine(rawHeader) {
    const s = String(rawHeader || "");
    const colon = s.indexOf(":");
    if (colon >= 0) {
        return {
            name: s.slice(0, colon).trim(),
            value: s.slice(colon + 1).replace(/^\s+/, ""),
            emptyMarker: false
        };
    }
    const semi = s.indexOf(";");
    if (semi >= 0) {
        return {
            name: s.slice(0, semi).trim(),
            value: "",
            emptyMarker: true
        };
    }
    return { name: s.trim(), value: "", emptyMarker: false };
}

function curlcParseCookiesString(raw, outList) {
    const parts = String(raw || "").split(";");
    for (let i = 0; i < parts.length; i++) {
        const part = parts[i].trim();
        if (!part) continue;
        const eq = part.indexOf("=");
        if (eq >= 0) {
            outList.push({
                name: part.slice(0, eq).trim(),
                value: part.slice(eq + 1).trim()
            });
        }
    }
}

function curlcParseFormField(spec, isStringOnly) {
    const s = String(spec || "");
    const eq = s.indexOf("=");
    if (eq < 0)
        return { key: s, value: "", isFile: false, filePath: "", fileName: "", mimeType: "" };

    const key = s.slice(0, eq);
    let rawVal = s.slice(eq + 1);
    let mimeType = "";

    // Check trailing ;type=... or ;filename=...
    const semiIdx = rawVal.indexOf(";");
    let mainVal = rawVal;
    let customName = "";
    if (semiIdx >= 0 && !isStringOnly) {
        mainVal = rawVal.slice(0, semiIdx);
        const attrs = rawVal.slice(semiIdx + 1).split(";");
        for (let i = 0; i < attrs.length; i++) {
            const attr = attrs[i].trim();
            if (/^type=/i.test(attr))
                mimeType = attr.slice(5).trim();
            else if (/^filename=/i.test(attr))
                customName = attr.slice(9).trim();
        }
    }

    if (!isStringOnly && mainVal.charAt(0) === "@") {
        let filePath = mainVal.slice(1);
        if (filePath.length >= 2 && filePath.charAt(0) === "\"" && filePath.charAt(filePath.length - 1) === "\"")
            filePath = filePath.slice(1, -1);
        const slash = Math.max(filePath.lastIndexOf("/"), filePath.lastIndexOf("\\"));
        const fileName = customName || (slash >= 0 ? filePath.slice(slash + 1) : filePath) || "file";
        return { key, value: filePath, isFile: true, filePath, fileName, mimeType };
    }

    return { key, value: mainVal, isFile: false, filePath: "", fileName: "", mimeType };
}

function curlcParseCommand(tokens) {
    let idx = 0;
    if (tokens[0] === "$" && tokens.length > 1)
        idx = 1;

    const cmd = String(tokens[idx] || "");
    const cmdBase = cmd.slice(Math.max(cmd.lastIndexOf("/"), cmd.lastIndexOf("\\")) + 1).toLowerCase();
    if (cmdBase !== "curl" && cmdBase !== "curl.exe")
        return { error: "Not a cURL command." };
    idx++;

    let method = "";
    let url = "";
    const headers = [];
    const cookies = [];
    const dataParts = [];
    const formFields = [];
    let auth = null;
    let hasData = false;
    let hasForm = false;
    let useGet = false;
    let headOnly = false;
    let followRedirects = false;
    let insecure = false;
    let compressed = false;
    let outputFile = "";
    let silent = false;
    let verbose = false;
    let maxTime = "";
    let connectTimeout = "";
    let jsonFlag = false;
    let userAgent = "";
    let referer = "";
    const warnings = [];
    let endOfOptions = false;

    const valueLongFlags = {
        "--url": "url",
        "--request": "request",
        "--header": "header",
        "--data": "data",
        "--data-raw": "data-raw",
        "--data-binary": "data-binary",
        "--data-ascii": "data-ascii",
        "--data-urlencode": "data-urlencode",
        "--json": "json",
        "--form": "form",
        "--form-string": "form-string",
        "--user": "user",
        "--cookie": "cookie",
        "--user-agent": "user-agent",
        "--referer": "referer",
        "--output": "output",
        "--max-time": "max-time",
        "--connect-timeout": "connect-timeout"
    };

    const boolLongFlags = {
        "--get": "get",
        "--head": "head",
        "--location": "location",
        "--insecure": "insecure",
        "--compressed": "compressed",
        "--silent": "silent",
        "--show-error": "show-error",
        "--verbose": "verbose"
    };

    const applyFlagValue = (kind, val) => {
        if (kind === "url") {
            url = val;
        } else if (kind === "request") {
            method = val.toUpperCase();
        } else if (kind === "header") {
            const parsed = curlcParseHeaderLine(val);
            if (parsed.name.length > 0) {
                if (parsed.name.toLowerCase() === "cookie") {
                    curlcParseCookiesString(parsed.value, cookies);
                } else {
                    headers.push({ name: parsed.name, value: parsed.value });
                }
            }
        } else if (kind === "data" || kind === "data-raw" || kind === "data-binary" || kind === "data-ascii") {
            hasData = true;
            dataParts.push(val);
        } else if (kind === "data-urlencode") {
            hasData = true;
            dataParts.push(curlcEncodeDataUrlencode(val));
        } else if (kind === "json") {
            hasData = true;
            jsonFlag = true;
            dataParts.push(val);
        } else if (kind === "form" || kind === "form-string") {
            hasForm = true;
            formFields.push(curlcParseFormField(val, kind === "form-string"));
        } else if (kind === "user") {
            const colon = val.indexOf(":");
            if (colon >= 0)
                auth = { user: val.slice(0, colon), password: val.slice(colon + 1) };
            else
                auth = { user: val, password: "" };
        } else if (kind === "cookie") {
            if (val.indexOf("=") >= 0)
                curlcParseCookiesString(val, cookies);
            else
                warnings.push("cookie file " + val + " (not expanded)");
        } else if (kind === "user-agent") {
            userAgent = val;
        } else if (kind === "referer") {
            referer = val;
        } else if (kind === "output") {
            outputFile = val;
        } else if (kind === "max-time") {
            maxTime = val;
        } else if (kind === "connect-timeout") {
            connectTimeout = val;
        }
    };

    const applyBoolFlag = kind => {
        if (kind === "get") useGet = true;
        else if (kind === "head") headOnly = true;
        else if (kind === "location") followRedirects = true;
        else if (kind === "insecure") insecure = true;
        else if (kind === "compressed") compressed = true;
        else if (kind === "silent") silent = true;
        else if (kind === "verbose") verbose = true;
    };

    const shortValueFlags = {
        X: "request",
        H: "header",
        d: "data",
        F: "form",
        u: "user",
        b: "cookie",
        A: "user-agent",
        e: "referer",
        o: "output",
        m: "max-time"
    };

    const shortBoolFlags = {
        G: "get",
        I: "head",
        L: "location",
        k: "insecure",
        s: "silent",
        S: "show-error",
        v: "verbose"
    };

    while (idx < tokens.length) {
        const tok = tokens[idx];
        if (endOfOptions) {
            if (!url) url = tok;
            else warnings.push("extra positional argument: " + tok);
            idx++;
            continue;
        }

        if (tok === "--") {
            endOfOptions = true;
            idx++;
            continue;
        }

        if (tok.startsWith("--")) {
            const eq = tok.indexOf("=");
            const flagName = eq >= 0 ? tok.slice(0, eq) : tok;
            if (valueLongFlags[flagName]) {
                let val;
                if (eq >= 0) {
                    val = tok.slice(eq + 1);
                } else {
                    if (idx + 1 >= tokens.length)
                        return { error: "Missing value for flag " + flagName + "." };
                    idx++;
                    val = tokens[idx];
                }
                applyFlagValue(valueLongFlags[flagName], val);
            } else if (boolLongFlags[flagName] && eq < 0) {
                applyBoolFlag(boolLongFlags[flagName]);
            } else {
                warnings.push(tok);
            }
            idx++;
            continue;
        }

        if (tok.startsWith("-") && tok.length > 1) {
            let j = 1;
            while (j < tok.length) {
                const ch = tok.charAt(j);
                if (shortValueFlags[ch]) {
                    const rest = tok.slice(j + 1);
                    let val;
                    if (rest.length > 0) {
                        val = rest;
                    } else {
                        if (idx + 1 >= tokens.length)
                            return { error: "Missing value for flag -" + ch + "." };
                        idx++;
                        val = tokens[idx];
                    }
                    applyFlagValue(shortValueFlags[ch], val);
                    break;
                } else if (shortBoolFlags[ch]) {
                    applyBoolFlag(shortBoolFlags[ch]);
                } else {
                    warnings.push("-" + ch);
                }
                j++;
            }
            idx++;
            continue;
        }

        if (!url)
            url = tok;
        else
            warnings.push("extra positional argument: " + tok);
        idx++;
    }

    if (!url)
        return { error: "No URL found in the cURL command." };

    if (userAgent) {
        const hasUa = headers.some(h => h.name.toLowerCase() === "user-agent");
        if (!hasUa) headers.push({ name: "User-Agent", value: userAgent });
    }
    if (referer) {
        const hasRef = headers.some(h => h.name.toLowerCase() === "referer");
        if (!hasRef) headers.push({ name: "Referer", value: referer });
    }
    if (jsonFlag) {
        if (!headers.some(h => h.name.toLowerCase() === "content-type"))
            headers.push({ name: "Content-Type", value: "application/json" });
        if (!headers.some(h => h.name.toLowerCase() === "accept"))
            headers.push({ name: "Accept", value: "application/json" });
    }

    let body = "";
    if (hasData)
        body = dataParts.join("&");

    if (useGet && body.length > 0) {
        url = curlcBuildUrlWithQuery(url, body);
        body = "";
        hasData = false;
    }

    if (!method) {
        if (headOnly) method = "HEAD";
        else if (useGet) method = "GET";
        else if (hasForm || hasData) method = "POST";
        else method = "GET";
    }

    // If Authorization: Basic ... header was provided without -u, keep in headers
    const parsedUrl = curlcParseUrl(url);
    if (!auth && parsedUrl.user)
        auth = { user: parsedUrl.user, password: parsedUrl.password };

    return {
        method,
        url: parsedUrl.full,
        parsedUrl,
        headers,
        cookies,
        auth,
        body,
        hasData,
        formFields,
        hasForm,
        followRedirects,
        insecure,
        compressed,
        outputFile,
        silent,
        verbose,
        maxTime,
        connectTimeout,
        warnings
    };
}

function curlcEffectiveHeaders(req, excludeNames) {
    const excludes = excludeNames.map(n => n.toLowerCase());
    const map = {};
    const order = [];
    for (let i = 0; i < req.headers.length; i++) {
        const h = req.headers[i];
        const lower = h.name.toLowerCase();
        if (excludes.indexOf(lower) !== -1)
            continue;
        if (map[lower]) {
            map[lower].value += ", " + h.value;
        } else {
            map[lower] = { name: h.name, value: h.value };
            order.push(lower);
        }
    }
    return order.map(k => map[k]);
}

function curlcCookieHeaderValue(cookies) {
    return cookies.map(c => c.name + "=" + c.value).join("; ");
}

function curlcIsJsonRequest(req) {
    if (!req.body) return { isJson: false };
    const ct = req.headers.find(h => h.name.toLowerCase() === "content-type");
    const ctIsJson = ct && /json/i.test(ct.value);
    const parsed = curlcTryParseJson(req.body);
    if (!parsed.ok) return { isJson: false };
    if (ctIsJson || !ct)
        return { isJson: true, value: parsed.value };
    return { isJson: false };
}

function curlcParseFormBody(body) {
    const pairs = String(body || "").split("&").filter(Boolean);
    if (pairs.length === 0) return null;
    const out = [];
    for (let i = 0; i < pairs.length; i++) {
        const p = pairs[i];
        const eq = p.indexOf("=");
        if (eq < 0) return null;
        out.push({
            key: curlcSafeDecode(p.slice(0, eq)),
            value: curlcSafeDecode(p.slice(eq + 1))
        });
    }
    return out;
}

function curlcIsFormUrlEncoded(req) {
    if (!req.body) return false;
    const ct = req.headers.find(h => h.name.toLowerCase() === "content-type");
    return Boolean(ct && /application\/x-www-form-urlencoded/i.test(ct.value));
}

function curlcAppendWarnings(lines, warnings, prefix) {
    if (warnings && warnings.length > 0)
        lines.push(prefix + "Warning: unknown flags ignored: " + warnings.join(", "));
}

function curlcGenFetch(req) {
    const lines = [];
    const notes = [];
    const headers = curlcEffectiveHeaders(req, req.hasForm ? ["content-type"] : []);
    if (req.cookies.length > 0)
        headers.push({ name: "Cookie", value: curlcCookieHeaderValue(req.cookies) });

    if (req.hasForm) {
        lines.push("const form = new FormData();");
        for (let i = 0; i < req.formFields.length; i++) {
            const f = req.formFields[i];
            if (f.isFile) {
                const blobOpts = f.mimeType ? (", { type: " + curlcJsString(f.mimeType) + " }") : "";
                lines.push("form.append(" + curlcJsString(f.key) + ", new Blob([\"\"]" + blobOpts + "), " + curlcJsString(f.fileName) + "); // from @" + f.filePath);
            } else {
                lines.push("form.append(" + curlcJsString(f.key) + ", " + curlcJsString(f.value) + ");");
            }
        }
        lines.push("");
    }

    const opts = [];
    if (req.method !== "GET")
        opts.push("  method: " + curlcJsString(req.method) + ",");

    if (headers.length > 0 || req.auth) {
        opts.push("  headers: {");
        for (let i = 0; i < headers.length; i++) {
            const h = headers[i];
            opts.push("    " + curlcJsString(h.name) + ": " + curlcJsString(h.value) + ",");
        }
        if (req.auth && !headers.some(h => h.name.toLowerCase() === "authorization")) {
            const creds = req.auth.user + ":" + req.auth.password;
            opts.push("    \"Authorization\": \"Basic \" + btoa(" + curlcJsString(creds) + "),");
        }
        opts.push("  },");
    }

    if (req.hasForm) {
        opts.push("  body: form,");
    } else if (req.body.length > 0) {
        const jsonCheck = curlcIsJsonRequest(req);
        if (jsonCheck.isJson) {
            const formatted = JSON.stringify(jsonCheck.value, null, 2);
            const indented = formatted.split("\n").map((l, idx) => idx === 0 ? l : "  " + l).join("\n");
            opts.push("  body: JSON.stringify(" + indented + "),");
        } else if (curlcIsFormUrlEncoded(req)) {
            const pairs = curlcParseFormBody(req.body);
            if (pairs) {
                opts.push("  body: new URLSearchParams({");
                for (let i = 0; i < pairs.length; i++)
                    opts.push("    " + curlcJsString(pairs[i].key) + ": " + curlcJsString(pairs[i].value) + ",");
                opts.push("  }),");
            } else {
                opts.push("  body: " + curlcJsString(req.body) + ",");
            }
        } else {
            opts.push("  body: " + curlcJsString(req.body) + ",");
        }
    }

    if (req.followRedirects)
        opts.push("  redirect: \"follow\",");
    if (req.maxTime) {
        const ms = Math.round(Number(req.maxTime) * 1000);
        if (isFinite(ms) && ms > 0)
            opts.push("  signal: AbortSignal.timeout(" + ms + "),");
    }
    if (req.connectTimeout && !req.maxTime)
        notes.push("// Note: fetch() has no separate connect timeout option (--connect-timeout)");
    if (req.insecure)
        notes.push("// Note: fetch() has no built-in option to skip TLS verification (-k/--insecure)");
    if (req.compressed)
        notes.push("// Note: fetch() handles compressed responses automatically (--compressed)");
    if (req.outputFile)
        notes.push("// Note: save response to " + req.outputFile + " (-o)");

    if (opts.length === 0) {
        lines.push("const response = await fetch(" + curlcJsString(req.url) + ");");
    } else {
        lines.push("const response = await fetch(" + curlcJsString(req.url) + ", {");
        for (let i = 0; i < opts.length; i++)
            lines.push(opts[i]);
        lines.push("});");
    }
    lines.push("const data = await response.text();");

    if (notes.length > 0) {
        lines.push("");
        for (let i = 0; i < notes.length; i++)
            lines.push(notes[i]);
    }
    curlcAppendWarnings(lines, req.warnings, "// ");
    return lines.join("\n");
}

function curlcGenPython(req) {
    const lines = ["import requests", ""];
    const notes = [];
    const headers = curlcEffectiveHeaders(req, req.hasForm ? ["content-type"] : []);

    let urlToUse = req.url;
    const params = req.parsedUrl.queryParams;
    if (params.length > 0) {
        urlToUse = req.parsedUrl.base + (req.parsedUrl.fragment ? "#" + req.parsedUrl.fragment : "");
        lines.push("params = {");
        const grouped = {};
        const order = [];
        for (let i = 0; i < params.length; i++) {
            const p = params[i];
            if (!grouped[p.key]) {
                grouped[p.key] = [];
                order.push(p.key);
            }
            grouped[p.key].push(p.value);
        }
        for (let i = 0; i < order.length; i++) {
            const k = order[i];
            const vals = grouped[k];
            if (vals.length === 1)
                lines.push("    " + curlcPyString(k) + ": " + curlcPyString(vals[0]) + ",");
            else
                lines.push("    " + curlcPyString(k) + ": [" + vals.map(curlcPyString).join(", ") + "],");
        }
        lines.push("}", "");
    }

    if (headers.length > 0) {
        lines.push("headers = {");
        for (let i = 0; i < headers.length; i++)
            lines.push("    " + curlcPyString(headers[i].name) + ": " + curlcPyString(headers[i].value) + ",");
        lines.push("}", "");
    }

    if (req.cookies.length > 0) {
        lines.push("cookies = {");
        for (let i = 0; i < req.cookies.length; i++)
            lines.push("    " + curlcPyString(req.cookies[i].name) + ": " + curlcPyString(req.cookies[i].value) + ",");
        lines.push("}", "");
    }

    let payloadArg = "";
    if (req.hasForm) {
        const hasAnyFile = req.formFields.some(f => f.isFile);
        if (hasAnyFile) {
            const dataFields = req.formFields.filter(f => !f.isFile);
            const fileFields = req.formFields.filter(f => f.isFile);
            if (dataFields.length > 0) {
                lines.push("data = {");
                for (let i = 0; i < dataFields.length; i++)
                    lines.push("    " + curlcPyString(dataFields[i].key) + ": " + curlcPyString(dataFields[i].value) + ",");
                lines.push("}", "");
                payloadArg += ", data=data";
            }
            lines.push("files = {");
            for (let i = 0; i < fileFields.length; i++) {
                const f = fileFields[i];
                if (f.mimeType)
                    lines.push("    " + curlcPyString(f.key) + ": (" + curlcPyString(f.fileName) + ", open(" + curlcPyString(f.filePath) + ", \"rb\"), " + curlcPyString(f.mimeType) + "),");
                else
                    lines.push("    " + curlcPyString(f.key) + ": open(" + curlcPyString(f.filePath) + ", \"rb\"),");
            }
            lines.push("}", "");
            payloadArg += ", files=files";
        } else {
            lines.push("files = {");
            for (let i = 0; i < req.formFields.length; i++) {
                const f = req.formFields[i];
                lines.push("    " + curlcPyString(f.key) + ": (None, " + curlcPyString(f.value) + "),");
            }
            lines.push("}", "");
            payloadArg = ", files=files";
        }
    } else if (req.body.length > 0) {
        const jsonCheck = curlcIsJsonRequest(req);
        if (jsonCheck.isJson) {
            lines.push("json_data = " + curlcPyLiteral(jsonCheck.value, 0), "");
            payloadArg = ", json=json_data";
        } else if (curlcIsFormUrlEncoded(req)) {
            const pairs = curlcParseFormBody(req.body);
            if (pairs) {
                lines.push("data = {");
                for (let i = 0; i < pairs.length; i++)
                    lines.push("    " + curlcPyString(pairs[i].key) + ": " + curlcPyString(pairs[i].value) + ",");
                lines.push("}", "");
                payloadArg = ", data=data";
            } else {
                lines.push("data = " + curlcPyString(req.body), "");
                payloadArg = ", data=data";
            }
        } else {
            lines.push("data = " + curlcPyString(req.body), "");
            payloadArg = ", data=data";
        }
    }

    const stdMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"];
    const args = [];
    let callPrefix;
    if (stdMethods.indexOf(req.method) !== -1) {
        callPrefix = "response = requests." + req.method.toLowerCase() + "(";
    } else {
        callPrefix = "response = requests.request(";
        args.push(curlcPyString(req.method));
    }
    args.push(curlcPyString(urlToUse));
    if (params.length > 0) args.push("params=params");
    if (headers.length > 0) args.push("headers=headers");
    if (req.cookies.length > 0) args.push("cookies=cookies");
    if (payloadArg) {
        const pParts = payloadArg.slice(2).split(", ");
        for (let i = 0; i < pParts.length; i++) args.push(pParts[i]);
    }
    if (req.auth)
        args.push("auth=(" + curlcPyString(req.auth.user) + ", " + curlcPyString(req.auth.password) + ")");
    if (req.followRedirects)
        args.push("allow_redirects=True");
    if (req.insecure)
        args.push("verify=False");
    if (req.connectTimeout && req.maxTime)
        args.push("timeout=(" + req.connectTimeout + ", " + req.maxTime + ")");
    else if (req.maxTime)
        args.push("timeout=" + req.maxTime);
    else if (req.connectTimeout)
        args.push("timeout=" + req.connectTimeout);

    if (args.length <= 2) {
        lines.push(callPrefix + args.join(", ") + ")");
    } else {
        lines.push(callPrefix);
        for (let i = 0; i < args.length; i++)
            lines.push("    " + args[i] + ",");
        lines.push(")");
    }

    if (req.outputFile) {
        lines.push("with open(" + curlcPyString(req.outputFile) + ", \"wb\") as f:");
        lines.push("    f.write(response.content)");
    }

    if (req.compressed)
        notes.push("# Note: requests handles gzip/deflate decompression automatically (--compressed)");
    if (notes.length > 0) {
        lines.push("");
        for (let i = 0; i < notes.length; i++)
            lines.push(notes[i]);
    }
    curlcAppendWarnings(lines, req.warnings, "# ");
    return lines.join("\n");
}

function curlcGenHttpie(req) {
    const flags = [];
    const notes = [];
    const headers = curlcEffectiveHeaders(req, req.hasForm ? ["content-type"] : []);

    if (req.followRedirects) flags.push("--follow");
    if (req.insecure) flags.push("--verify=no");
    if (req.auth)
        flags.push("--auth=" + curlcShellQuote(req.auth.user + ":" + req.auth.password));
    if (req.maxTime)
        flags.push("--timeout=" + curlcShellQuote(req.maxTime));
    if (req.outputFile)
        flags.push("--output=" + curlcShellQuote(req.outputFile));
    if (req.hasForm) {
        flags.push(req.formFields.some(f => f.isFile) ? "--multipart" : "--form");
    } else if (curlcIsFormUrlEncoded(req)) {
        flags.push("--form");
    }

    const items = [];
    for (let i = 0; i < headers.length; i++) {
        const h = headers[i];
        items.push(curlcShellQuote(h.name + ":" + h.value));
    }
    if (req.cookies.length > 0)
        items.push(curlcShellQuote("Cookie:" + curlcCookieHeaderValue(req.cookies)));

    let stdinPrefix = "";
    if (req.hasForm) {
        for (let i = 0; i < req.formFields.length; i++) {
            const f = req.formFields[i];
            if (f.isFile) {
                const suffix = f.mimeType ? (";type=" + f.mimeType) : "";
                items.push(curlcShellQuote(f.key + "@" + f.filePath + suffix));
            } else {
                items.push(curlcShellQuote(f.key + "=" + f.value));
            }
        }
    } else if (req.body.length > 0) {
        const jsonCheck = curlcIsJsonRequest(req);
        if (jsonCheck.isJson && typeof jsonCheck.value === "object" && !Array.isArray(jsonCheck.value) && jsonCheck.value !== null) {
            const keys = Object.keys(jsonCheck.value);
            if (keys.length === 0) {
                stdinPrefix = "printf '%s' '{}' | ";
            } else {
                for (let i = 0; i < keys.length; i++) {
                    const k = keys[i];
                    const v = jsonCheck.value[k];
                    if (typeof v === "string")
                        items.push(curlcShellQuote(k + "=" + v));
                    else
                        items.push(curlcShellQuote(k + ":=" + JSON.stringify(v)));
                }
            }
        } else if (curlcIsFormUrlEncoded(req)) {
            const pairs = curlcParseFormBody(req.body);
            if (pairs) {
                for (let i = 0; i < pairs.length; i++)
                    items.push(curlcShellQuote(pairs[i].key + "=" + pairs[i].value));
            } else {
                stdinPrefix = "printf '%s' " + curlcShellQuoteAlways(req.body) + " | ";
            }
        } else {
            stdinPrefix = "printf '%s' " + curlcShellQuoteAlways(req.body) + " | ";
        }
    }

    const parts = [stdinPrefix + "http"];
    for (let i = 0; i < flags.length; i++) parts.push(flags[i]);
    parts.push(req.method);
    parts.push(curlcShellQuoteAlways(req.url));
    for (let i = 0; i < items.length; i++) parts.push(items[i]);

    const lines = [];
    if (parts.length === 1) {
        lines.push(parts[0]);
    } else if (parts.length <= 3 && items.length === 0 && flags.length === 0) {
        lines.push(parts.join(" "));
    } else {
        lines.push(parts[0] + " " + parts[1] + (parts.length > 2 ? " \\" : ""));
        for (let i = 2; i < parts.length; i++) {
            const cont = i < parts.length - 1 ? " \\" : "";
            lines.push("  " + parts[i] + cont);
        }
    }

    if (req.compressed)
        notes.push("# Note: HTTPie requests and decodes compressed responses automatically (--compressed)");
    if (req.connectTimeout)
        notes.push("# Note: HTTPie has a single --timeout flag (no separate --connect-timeout)");
    if (notes.length > 0) {
        lines.push("");
        for (let i = 0; i < notes.length; i++) lines.push(notes[i]);
    }
    curlcAppendWarnings(lines, req.warnings, "# ");
    return lines.join("\n");
}

function curlcGenWget(req) {
    const parts = [];
    const notes = [];
    const headers = curlcEffectiveHeaders(req, []);

    if (req.method !== "GET")
        parts.push("--method=" + req.method);

    for (let i = 0; i < headers.length; i++) {
        const h = headers[i];
        if (h.name.toLowerCase() === "user-agent")
            parts.push("--user-agent=" + curlcShellQuoteAlways(h.value));
        else if (h.name.toLowerCase() === "referer")
            parts.push("--referer=" + curlcShellQuoteAlways(h.value));
        else
            parts.push("--header=" + curlcShellQuoteAlways(h.name + ": " + h.value));
    }

    if (req.cookies.length > 0)
        parts.push("--header=" + curlcShellQuoteAlways("Cookie: " + curlcCookieHeaderValue(req.cookies)));

    if (req.auth) {
        parts.push("--user=" + curlcShellQuoteAlways(req.auth.user));
        parts.push("--password=" + curlcShellQuoteAlways(req.auth.password));
    }

    if (req.insecure)
        parts.push("--no-check-certificate");
    if (req.compressed)
        parts.push("--compression=auto");
    if (req.connectTimeout && req.maxTime) {
        parts.push("--connect-timeout=" + req.connectTimeout);
        parts.push("--read-timeout=" + req.maxTime);
    } else if (req.maxTime) {
        parts.push("--timeout=" + req.maxTime);
    } else if (req.connectTimeout) {
        parts.push("--connect-timeout=" + req.connectTimeout);
    }

    if (req.outputFile)
        parts.push("-O " + curlcShellQuoteAlways(req.outputFile));
    else
        parts.push("-O -");

    if (req.hasForm) {
        notes.push("# Note: wget cannot build multipart/form-data (-F) natively; consider curl or httpie");
        const preview = req.formFields.map(f => f.isFile ? (f.key + "=@" + f.filePath) : (f.key + "=" + f.value)).join("&");
        parts.push("--body-data=" + curlcShellQuoteAlways(preview));
    } else if (req.body.length > 0) {
        parts.push("--body-data=" + curlcShellQuoteAlways(req.body));
    }

    if (req.followRedirects)
        notes.push("# Note: wget follows redirects by default (-L)");

    const lines = [];
    if (parts.length === 0) {
        lines.push("wget " + curlcShellQuoteAlways(req.url));
    } else {
        lines.push("wget \\");
        for (let i = 0; i < parts.length; i++)
            lines.push("  " + parts[i] + " \\");
        lines.push("  " + curlcShellQuoteAlways(req.url));
    }

    if (notes.length > 0) {
        lines.push("");
        for (let i = 0; i < notes.length; i++) lines.push(notes[i]);
    }
    curlcAppendWarnings(lines, req.warnings, "# ");
    return lines.join("\n");
}

function curlcGenGo(req) {
    const imports = ["\"fmt\"", "\"io\"", "\"net/http\""];
    const bodyLines = [];
    const notes = [];
    const hasFileForm = req.hasForm && req.formFields.some(f => f.isFile);

    let bodyExpr = "nil";
    if (req.hasForm) {
        imports.push("\"bytes\"", "\"mime/multipart\"");
        if (hasFileForm)
            imports.push("\"os\"", "\"path/filepath\"");
        bodyLines.push("\tvar buf bytes.Buffer");
        bodyLines.push("\twriter := multipart.NewWriter(&buf)");
        for (let i = 0; i < req.formFields.length; i++) {
            const f = req.formFields[i];
            if (f.isFile) {
                const idxSuffix = i > 0 ? String(i + 1) : "";
                bodyLines.push("\tf" + idxSuffix + ", err := os.Open(" + curlcGoString(f.filePath) + ")");
                bodyLines.push("\tif err != nil {");
                bodyLines.push("\t\tpanic(err)");
                bodyLines.push("\t}");
                bodyLines.push("\tdefer f" + idxSuffix + ".Close()");
                bodyLines.push("\tpart" + idxSuffix + ", err := writer.CreateFormFile(" + curlcGoString(f.key) + ", filepath.Base(" + curlcGoString(f.filePath) + "))");
                bodyLines.push("\tif err != nil {");
                bodyLines.push("\t\tpanic(err)");
                bodyLines.push("\t}");
                bodyLines.push("\tif _, err := io.Copy(part" + idxSuffix + ", f" + idxSuffix + "); err != nil {");
                bodyLines.push("\t\tpanic(err)");
                bodyLines.push("\t}");
            } else {
                bodyLines.push("\t_ = writer.WriteField(" + curlcGoString(f.key) + ", " + curlcGoString(f.value) + ")");
            }
        }
        bodyLines.push("\tif err := writer.Close(); err != nil {");
        bodyLines.push("\t\tpanic(err)");
        bodyLines.push("\t}");
        bodyExpr = "&buf";
    } else if (req.body.length > 0) {
        imports.push("\"strings\"");
        bodyLines.push("\tbody := strings.NewReader(" + curlcGoString(req.body) + ")");
        bodyExpr = "body";
    }

    if (req.insecure)
        imports.push("\"crypto/tls\"");
    if (req.maxTime || req.connectTimeout)
        imports.push("\"time\"");

    imports.sort();

    const lines = ["package main", "", "import ("];
    for (let i = 0; i < imports.length; i++)
        lines.push("  " + imports[i]);
    lines.push(")", "", "func main() {");

    for (let i = 0; i < bodyLines.length; i++)
        lines.push(bodyLines[i].replace(/^\t+/g, m => "  ".repeat(m.length)));

    lines.push("  req, err := http.NewRequest(" + curlcGoString(req.method) + ", " + curlcGoString(req.url) + ", " + bodyExpr + ")");
    lines.push("  if err != nil {");
    lines.push("    panic(err)");
    lines.push("  }");

    const headers = req.hasForm ? req.headers.filter(h => h.name.toLowerCase() !== "content-type") : req.headers;
    if (req.hasForm)
        lines.push("  req.Header.Set(\"Content-Type\", writer.FormDataContentType())");

    const seenHeaders = {};
    for (let i = 0; i < headers.length; i++) {
        const h = headers[i];
        const lower = h.name.toLowerCase();
        const op = seenHeaders[lower] ? "Add" : "Set";
        seenHeaders[lower] = true;
        lines.push("  req.Header." + op + "(" + curlcGoString(h.name) + ", " + curlcGoString(h.value) + ")");
    }

    for (let i = 0; i < req.cookies.length; i++) {
        const c = req.cookies[i];
        lines.push("  req.AddCookie(&http.Cookie{Name: " + curlcGoString(c.name) + ", Value: " + curlcGoString(c.value) + "})");
    }

    if (req.auth)
        lines.push("  req.SetBasicAuth(" + curlcGoString(req.auth.user) + ", " + curlcGoString(req.auth.password) + ")");

    const clientFields = [];
    const timeoutSec = req.maxTime || req.connectTimeout;
    if (timeoutSec) {
        const num = Number(timeoutSec);
        if (isFinite(num) && num > 0)
            clientFields.push("    Timeout: " + num + " * time.Second,");
    }
    if (req.insecure) {
        clientFields.push("    Transport: &http.Transport{");
        clientFields.push("      TLSClientConfig: &tls.Config{InsecureSkipVerify: true},");
        clientFields.push("    },");
    }

    if (clientFields.length === 0) {
        lines.push("  client := &http.Client{}");
    } else {
        lines.push("  client := &http.Client{");
        for (let i = 0; i < clientFields.length; i++)
            lines.push(clientFields[i]);
        lines.push("  }");
    }

    lines.push("  resp, err := client.Do(req)");
    lines.push("  if err != nil {");
    lines.push("    panic(err)");
    lines.push("  }");
    lines.push("  defer resp.Body.Close()");
    lines.push("  respBody, err := io.ReadAll(resp.Body)");
    lines.push("  if err != nil {");
    lines.push("    panic(err)");
    lines.push("  }");
    lines.push("  fmt.Println(string(respBody))");

    if (req.followRedirects)
        notes.push("  // Note: http.Client follows up to 10 redirects by default (-L)");
    if (req.compressed)
        notes.push("  // Note: http.Transport requests and decodes gzip automatically (--compressed)");
    if (req.outputFile)
        notes.push("  // Note: write respBody to " + req.outputFile + " (-o)");
    for (let i = 0; i < notes.length; i++)
        lines.push(notes[i]);
    curlcAppendWarnings(lines, req.warnings, "  // ");
    lines.push("}");
    return lines.join("\n");
}

function curlcGenParsed(req) {
    const out = [];
    const u = req.parsedUrl;
    out.push("Method      " + req.method);
    out.push("URL         " + req.url);
    if (u.scheme) out.push("Scheme      " + u.scheme);
    if (u.host) out.push("Host        " + u.host);
    out.push("Path        " + (u.path || "/"));
    if (u.fragment) out.push("Fragment    " + u.fragment);

    const flags = [];
    if (req.followRedirects) flags.push("follow redirects (-L)");
    if (req.insecure) flags.push("insecure TLS (-k)");
    if (req.compressed) flags.push("compressed");
    if (req.silent) flags.push("silent (-s)");
    if (req.verbose) flags.push("verbose (-v)");
    if (req.maxTime) flags.push("max-time=" + req.maxTime + "s");
    if (req.connectTimeout) flags.push("connect-timeout=" + req.connectTimeout + "s");
    if (req.outputFile) flags.push("output=" + req.outputFile);
    if (flags.length > 0)
        out.push("Flags       " + flags.join(", "));

    if (u.queryParams.length > 0) {
        out.push("", "Query parameters (" + u.queryParams.length + ")");
        let w = 0;
        for (let i = 0; i < u.queryParams.length; i++)
            w = Math.max(w, u.queryParams[i].key.length);
        w = Math.min(20, w);
        for (let i = 0; i < u.queryParams.length; i++) {
            const p = u.queryParams[i];
            out.push("  " + p.key.padEnd(w) + "  " + p.value);
        }
    }

    if (req.headers.length > 0) {
        out.push("", "Headers (" + req.headers.length + ")");
        let w = 0;
        for (let i = 0; i < req.headers.length; i++)
            w = Math.max(w, req.headers[i].name.length);
        w = Math.min(20, w);
        for (let i = 0; i < req.headers.length; i++) {
            const h = req.headers[i];
            out.push("  " + h.name.padEnd(w) + "  " + h.value);
        }
    }

    if (req.auth) {
        out.push("", "Auth (Basic)");
        out.push("  User      " + req.auth.user);
        out.push("  Password  " + req.auth.password);
    }

    if (req.cookies.length > 0) {
        out.push("", "Cookies (" + req.cookies.length + ")");
        let w = 0;
        for (let i = 0; i < req.cookies.length; i++)
            w = Math.max(w, req.cookies[i].name.length);
        w = Math.min(20, w);
        for (let i = 0; i < req.cookies.length; i++) {
            const c = req.cookies[i];
            out.push("  " + c.name.padEnd(w) + "  " + c.value);
        }
    }

    if (req.hasForm && req.formFields.length > 0) {
        out.push("", "Form fields (" + req.formFields.length + ")");
        let w = 0;
        for (let i = 0; i < req.formFields.length; i++)
            w = Math.max(w, req.formFields[i].key.length);
        w = Math.min(20, w);
        for (let i = 0; i < req.formFields.length; i++) {
            const f = req.formFields[i];
            const desc = f.isFile
                ? ("<file: " + f.filePath + (f.mimeType ? "; " + f.mimeType : "") + ">")
                : f.value;
            out.push("  " + f.key.padEnd(w) + "  " + desc);
        }
    }

    if (req.body.length > 0) {
        const jsonCheck = curlcTryParseJson(req.body);
        if (jsonCheck.ok) {
            out.push("", "Body (JSON)");
            const pretty = JSON.stringify(jsonCheck.value, null, 2).split("\n");
            for (let i = 0; i < pretty.length; i++)
                out.push("  " + pretty[i]);
        } else {
            out.push("", "Body (" + req.body.length + " chars)");
            const bodyLines = req.body.split("\n");
            for (let i = 0; i < bodyLines.length; i++)
                out.push("  " + bodyLines[i]);
        }
    }

    if (req.warnings.length > 0) {
        out.push("", "Warnings (" + req.warnings.length + ")");
        for (let i = 0; i < req.warnings.length; i++)
            out.push("  ! " + req.warnings[i]);
    }

    return out.join("\n");
}

function curlcParseHttpRequest(text) {
    const normalized = String(text).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    const lines = normalized.split("\n");
    let firstIdx = 0;
    while (firstIdx < lines.length && lines[firstIdx].trim() === "")
        firstIdx++;
    if (firstIdx >= lines.length)
        return null;

    const reqLine = lines[firstIdx].trim();
    const withVer = reqLine.match(/^([A-Za-z]+)\s+(\S+)\s+HTTP\/\d+(?:\.\d+)?$/i);
    let method = "";
    let target = "";
    if (withVer) {
        method = withVer[1].toUpperCase();
        target = withVer[2];
    } else {
        const noVer = reqLine.match(/^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT)\s+(\S+)$/i);
        if (!noVer)
            return null;
        // Require either a full URL or at least one Header: Value line following
        const secondLine = firstIdx + 1 < lines.length ? lines[firstIdx + 1].trim() : "";
        if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(noVer[2]) && !/^[A-Za-z0-9-]+:\s*/.test(secondLine))
            return null;
        method = noVer[1].toUpperCase();
        target = noVer[2];
    }

    const headers = [];
    let hostHeader = "";
    let originOrRef = "";
    let bodyStart = lines.length;
    for (let i = firstIdx + 1; i < lines.length; i++) {
        const line = lines[i];
        if (line.trim() === "") {
            bodyStart = i + 1;
            break;
        }
        const colon = line.indexOf(":");
        if (colon <= 0)
            return { error: "Malformed HTTP header line: " + line };
        const name = line.slice(0, colon).trim();
        const value = line.slice(colon + 1).replace(/^\s+/, "");
        const lower = name.toLowerCase();
        if (lower === "host")
            hostHeader = value;
        else if (lower === "content-length")
            continue;
        else
            headers.push({ name, value });

        if (lower === "origin" || lower === "referer")
            originOrRef = value;
    }

    const body = bodyStart < lines.length ? lines.slice(bodyStart).join("\n") : "";

    let fullUrl = target;
    let host = hostHeader;
    if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(target)) {
        if (!hostHeader)
            return { error: "Raw HTTP request needs a Host header or full URL." };
        const scheme = (/:443$/.test(hostHeader) || originOrRef.toLowerCase().startsWith("https://")) ? "https" : "http";
        const path = target.startsWith("/") ? target : ("/" + target);
        fullUrl = scheme + "://" + hostHeader + path;
    } else {
        host = curlcParseUrl(target).host;
    }

    return { method, url: fullUrl, host, headers, body };
}

function curlcFormatCurlFromHttp(req) {
    const flags = [];
    if (req.method !== "GET" || req.body.length > 0)
        flags.push("-X " + req.method);
    for (let i = 0; i < req.headers.length; i++) {
        const h = req.headers[i];
        flags.push("-H " + curlcShellQuoteAlways(h.name + ": " + h.value));
    }
    if (req.body.length > 0)
        flags.push("-d " + curlcShellQuoteAlways(req.body));

    if (flags.length === 0)
        return "curl " + curlcShellQuoteAlways(req.url);

    const lines = ["curl " + flags[0] + " \\"];
    for (let i = 1; i < flags.length; i++)
        lines.push("  " + flags[i] + " \\");
    lines.push("  " + curlcShellQuoteAlways(req.url));
    return lines.join("\n");
}

function curlcTrimMeta(value) {
    const s = String(value || "");
    return s.length > 28 ? s.slice(0, 27) + "…" : s;
}

function curlcConvert(input = "", options = {}) {
    const text = String(input);
    if (text.trim().length === 0)
        return { output: "" };

    const tokenized = curlcTokenize(text);
    if (!tokenized.error && tokenized.tokens.length > 0) {
        const first = tokenized.tokens[0];
        const second = tokenized.tokens.length > 1 ? tokenized.tokens[1] : "";
        const headTok = (first === "$" && second) ? second : first;
        const headBase = headTok.slice(Math.max(headTok.lastIndexOf("/"), headTok.lastIndexOf("\\")) + 1).toLowerCase();
        if (headBase === "curl" || headBase === "curl.exe") {
            const req = curlcParseCommand(tokenized.tokens);
            if (req.error)
                return { output: "", error: req.error };

            const target = String(options.target || "fetch").toLowerCase();
            let output;
            switch (target) {
            case "python": output = curlcGenPython(req); break;
            case "httpie": output = curlcGenHttpie(req); break;
            case "wget": output = curlcGenWget(req); break;
            case "go": output = curlcGenGo(req); break;
            case "parsed": output = curlcGenParsed(req); break;
            default: output = curlcGenFetch(req);
            }

            const meta = {
                method: req.method,
                host: curlcTrimMeta(req.parsedUrl.host || "—"),
                headers: req.headers.length
            };
            return { output, meta };
        }
    }

    const httpReq = curlcParseHttpRequest(text);
    if (httpReq) {
        if (httpReq.error)
            return { output: "", error: httpReq.error };
        const output = curlcFormatCurlFromHttp(httpReq);
        const meta = {
            method: httpReq.method,
            host: curlcTrimMeta(httpReq.host || "—"),
            headers: httpReq.headers.length
        };
        return { output, meta };
    }

    if (tokenized.error)
        return { output: "", error: tokenized.error };

    return { output: "", error: "Enter a cURL command (starting with curl) or a raw HTTP request (e.g. GET /path HTTP/1.1)." };
}
// @slot-end curl_converter

// @slot-begin json_query
function jsonqIsPlainObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function jsonqHasOwn(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
}

function jsonqTypeOf(v) {
    if (v === null) return "null";
    if (Array.isArray(v)) return "array";
    return typeof v;
}

function jsonqDeepEqual(a, b) {
    if (a === b) return true;
    if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
        return false;
    const isArrA = Array.isArray(a);
    if (isArrA !== Array.isArray(b)) return false;
    if (isArrA) {
        if (a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) {
            if (!jsonqDeepEqual(a[i], b[i])) return false;
        }
        return true;
    }
    const keysA = Object.keys(a);
    const keysB = Object.keys(b);
    if (keysA.length !== keysB.length) return false;
    for (let i = 0; i < keysA.length; i++) {
        const k = keysA[i];
        if (!jsonqHasOwn(b, k) || !jsonqDeepEqual(a[k], b[k])) return false;
    }
    return true;
}

function jsonqCodepointLength(str) {
    let count = 0;
    for (let i = 0; i < str.length; i++) {
        const c = str.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
            const c2 = str.charCodeAt(i + 1);
            if (c2 >= 0xdc00 && c2 <= 0xdfff) i++;
        }
        count++;
    }
    return count;
}

function jsonqDecodeEscape(str, i) {
    if (i >= str.length) return null;
    const ch = str.charAt(i);
    switch (ch) {
    case "\"": return { ch: "\"", next: i + 1 };
    case "'": return { ch: "'", next: i + 1 };
    case "\\": return { ch: "\\", next: i + 1 };
    case "/": return { ch: "/", next: i + 1 };
    case "b": return { ch: "\b", next: i + 1 };
    case "f": return { ch: "\f", next: i + 1 };
    case "n": return { ch: "\n", next: i + 1 };
    case "r": return { ch: "\r", next: i + 1 };
    case "t": return { ch: "\t", next: i + 1 };
    case "u": {
        const hex = str.slice(i + 1, i + 5);
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) return null;
        return { ch: String.fromCharCode(parseInt(hex, 16)), next: i + 5 };
    }
    default:
        return { ch: ch, next: i + 1 };
    }
}

function jsonqDescendants(node, out) {
    out.push(node);
    if (Array.isArray(node)) {
        for (let i = 0; i < node.length; i++)
            jsonqDescendants(node[i], out);
    } else if (jsonqIsPlainObject(node)) {
        const keys = Object.keys(node);
        for (let i = 0; i < keys.length; i++)
            jsonqDescendants(node[keys[i]], out);
    }
}

function jsonqFlatten(arr, depth, out) {
    for (let i = 0; i < arr.length; i++) {
        const item = arr[i];
        if (depth > 0 && Array.isArray(item))
            jsonqFlatten(item, depth - 1, out);
        else
            out.push(item);
    }
}

// ── JSONPath Parser & Evaluator (Goessner / RFC 9535 subset) ──

const JSONQ_NOTHING = { __jsonqNothing: true };

function jsonqJpIsNameStart(ch) {
    const code = ch.charCodeAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code === 95 || code >= 128;
}

function jsonqJpIsNameChar(ch) {
    const code = ch.charCodeAt(0);
    return jsonqJpIsNameStart(ch) || (code >= 48 && code <= 57);
}

function jsonqJpParse(expr) {
    const s = String(expr);
    let pos = 0;
    const len = s.length;

    function err(msg, atPos) {
        const p = atPos !== undefined ? atPos : pos;
        throw new Error(`JSONPath syntax error at column ${p + 1}: ${msg}`);
    }
    function skipWs() {
        while (pos < len && /\s/.test(s.charAt(pos))) pos++;
    }
    function readString(quote) {
        const startPos = pos;
        pos++; // opening quote
        let out = "";
        while (pos < len) {
            const ch = s.charAt(pos);
            if (ch === quote) {
                pos++;
                return out;
            }
            if (ch === "\\") {
                const dec = jsonqDecodeEscape(s, pos + 1);
                if (!dec) err("invalid escape sequence", pos);
                out += dec.ch;
                pos = dec.next;
            } else {
                out += ch;
                pos++;
            }
        }
        err("unterminated string", startPos);
    }
    function readNumber() {
        const sub = s.slice(pos);
        const m = sub.match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/);
        if (!m) return null;
        pos += m[0].length;
        return Number(m[0]);
    }
    function readInt() {
        const sub = s.slice(pos);
        const m = sub.match(/^-?(?:0|[1-9]\d*)/);
        if (!m) return null;
        pos += m[0].length;
        return parseInt(m[0], 10);
    }
    function readIdent() {
        if (pos >= len || !jsonqJpIsNameStart(s.charAt(pos))) return null;
        const start = pos;
        pos++;
        while (pos < len && jsonqJpIsNameChar(s.charAt(pos))) pos++;
        return s.slice(start, pos);
    }
    function readRegex() {
        const startPos = pos;
        pos++; // '/'
        let pattern = "";
        let escaped = false;
        while (pos < len) {
            const ch = s.charAt(pos);
            if (escaped) {
                pattern += "\\" + ch;
                escaped = false;
                pos++;
            } else if (ch === "\\") {
                escaped = true;
                pos++;
            } else if (ch === "/") {
                pos++;
                let flags = "";
                while (pos < len && /[a-zA-Z]/.test(s.charAt(pos))) {
                    flags += s.charAt(pos++);
                }
                let finalPat = pattern;
                if (flags.indexOf("s") !== -1) {
                    finalPat = jsonqRewriteDotAll(finalPat);
                }
                const cleanFlags = flags.replace(/[^im]/g, "");
                try {
                    return new RegExp(finalPat, cleanFlags);
                } catch (e) {
                    err("invalid regex: " + e.message, startPos);
                }
            } else {
                pattern += ch;
                pos++;
            }
        }
        err("unterminated regex literal", startPos);
    }

    function parseSegments(stopInFilter) {
        const segments = [];
        while (pos < len) {
            if (stopInFilter) {
                const ch = s.charAt(pos);
                if (/[\s)\]&|=!<>+\-*\/,]/.test(ch)) break;
            } else {
                skipWs();
                if (pos >= len) break;
            }
            if (s.slice(pos, pos + 2) === "..") {
                pos += 2;
                if (!stopInFilter) skipWs();
                if (pos >= len) err("expected child selector after '..'");
                let sel;
                if (s.charAt(pos) === "*") {
                    pos++;
                    sel = [{ kind: "wildcard" }];
                } else if (s.charAt(pos) === "[") {
                    sel = parseBracket();
                } else {
                    const name = readIdent();
                    if (name === null) err("expected property name, '*', or '[' after '..'");
                    sel = [{ kind: "name", name: name }];
                }
                segments.push({ kind: "descendant", selectors: sel });
            } else if (s.charAt(pos) === ".") {
                pos++;
                if (!stopInFilter) skipWs();
                if (s.charAt(pos) === "*") {
                    pos++;
                    segments.push({ kind: "child", selectors: [{ kind: "wildcard" }] });
                } else {
                    const name = readIdent();
                    if (name === null) err("expected property name or '*' after '.'");
                    segments.push({ kind: "child", selectors: [{ kind: "name", name: name }] });
                }
            } else if (s.charAt(pos) === "[") {
                segments.push({ kind: "child", selectors: parseBracket() });
            } else {
                if (stopInFilter) break;
                err(`unexpected character '${s.charAt(pos)}'`);
            }
        }
        return segments;
    }

    function parseBracket() {
        pos++; // '['
        const selectors = [];
        while (true) {
            skipWs();
            if (pos >= len) err("expected ']'");
            const ch = s.charAt(pos);
            if (ch === "*") {
                pos++;
                selectors.push({ kind: "wildcard" });
            } else if (ch === "'" || ch === "\"") {
                selectors.push({ kind: "name", name: readString(ch) });
            } else if (ch === "?") {
                pos++;
                skipWs();
                const filterExpr = parseFilterOr();
                selectors.push({ kind: "filter", expr: filterExpr });
            } else if (ch === ":" || ch === "-" || (ch >= "0" && ch <= "9")) {
                let start = null;
                if (ch !== ":") {
                    const n = readInt();
                    if (n === null) err("expected integer index or slice");
                    skipWs();
                    if (s.charAt(pos) !== ":") {
                        selectors.push({ kind: "index", index: n });
                        skipWs();
                        if (s.charAt(pos) === ",") { pos++; continue; }
                        if (s.charAt(pos) === "]") { pos++; return selectors; }
                        err("expected ',' or ']'");
                    }
                    start = n;
                }
                pos++; // ':'
                skipWs();
                let end = null;
                if (s.charAt(pos) !== ":" && s.charAt(pos) !== "," && s.charAt(pos) !== "]") {
                    end = readInt();
                    if (end === null) err("expected slice end integer");
                    skipWs();
                }
                let step = null;
                if (s.charAt(pos) === ":") {
                    pos++;
                    skipWs();
                    if (s.charAt(pos) !== "," && s.charAt(pos) !== "]") {
                        step = readInt();
                        if (step === null) err("expected slice step integer");
                    }
                }
                selectors.push({ kind: "slice", start: start, end: end, step: step });
            } else {
                err(`unexpected token '${ch}' inside '['`);
            }
            skipWs();
            if (s.charAt(pos) === ",") {
                pos++;
                continue;
            }
            if (s.charAt(pos) === "]") {
                pos++;
                return selectors;
            }
            err("expected ',' or ']'");
        }
    }

    function parseFilterOr() {
        let left = parseFilterAnd();
        while (true) {
            skipWs();
            if (s.slice(pos, pos + 2) === "||") {
                pos += 2;
                left = { type: "or", left: left, right: parseFilterAnd() };
            } else {
                return left;
            }
        }
    }

    function parseFilterAnd() {
        let left = parseFilterComp();
        while (true) {
            skipWs();
            if (s.slice(pos, pos + 2) === "&&") {
                pos += 2;
                left = { type: "and", left: left, right: parseFilterComp() };
            } else {
                return left;
            }
        }
    }

    function parseFilterComp() {
        let left = parseFilterUnary();
        skipWs();
        const two = s.slice(pos, pos + 2);
        const one = s.charAt(pos);
        if (two === "=~") {
            pos += 2;
            skipWs();
            let rx;
            if (s.charAt(pos) === "/") {
                rx = readRegex();
            } else if (s.charAt(pos) === "'" || s.charAt(pos) === "\"") {
                const pat = readString(s.charAt(pos));
                try { rx = new RegExp(pat); }
                catch (e) { err("invalid regex: " + e.message); }
            } else {
                err("expected /regex/ after '=~'");
            }
            return { type: "regex", left: left, regex: rx };
        }
        let op = null;
        if (two === "==" || two === "!=" || two === "<=" || two === ">=") {
            op = two;
            pos += 2;
        } else if (one === "<" || one === ">") {
            op = one;
            pos += 1;
        }
        if (op !== null) {
            const right = parseFilterUnary();
            return { type: "cmp", op: op, left: left, right: right };
        }
        return left;
    }

    function parseFilterUnary() {
        skipWs();
        if (s.charAt(pos) === "!") {
            pos++;
            return { type: "not", expr: parseFilterUnary() };
        }
        return parseFilterPrimary();
    }

    function parseFilterPrimary() {
        skipWs();
        if (pos >= len) err("unexpected end of filter expression");
        const ch = s.charAt(pos);
        if (ch === "(") {
            pos++;
            const inner = parseFilterOr();
            skipWs();
            if (s.charAt(pos) !== ")") err("expected ')'");
            pos++;
            return inner;
        }
        if (ch === "@" || ch === "$") {
            pos++;
            const segments = parseSegments(true);
            return { type: "path", isRoot: ch === "$", segments: segments };
        }
        if (ch === "'" || ch === "\"") {
            return { type: "lit", value: readString(ch) };
        }
        if (ch === "-" || (ch >= "0" && ch <= "9")) {
            const num = readNumber();
            if (num === null) err("invalid number literal");
            return { type: "lit", value: num };
        }
        const ident = readIdent();
        if (ident !== null) {
            skipWs();
            if (s.charAt(pos) === "(") {
                pos++;
                const args = [];
                skipWs();
                if (s.charAt(pos) !== ")") {
                    while (true) {
                        args.push(parseFilterOr());
                        skipWs();
                        if (s.charAt(pos) === ",") { pos++; continue; }
                        break;
                    }
                }
                if (s.charAt(pos) !== ")") err("expected ')' after function arguments");
                pos++;
                if (ident !== "length" && ident !== "count")
                    err(`unsupported JSONPath function '${ident}'`);
                if (args.length !== 1)
                    err(`JSONPath function '${ident}' expects 1 argument`);
                return { type: "func", name: ident, arg: args[0] };
            }
            if (ident === "true") return { type: "lit", value: true };
            if (ident === "false") return { type: "lit", value: false };
            if (ident === "null") return { type: "lit", value: null };
            err(`unexpected identifier '${ident}' in filter`);
        }
        err(`unexpected token '${ch}' in filter`);
    }

    skipWs();
    if (pos >= len || s.charAt(pos) !== "$")
        err("JSONPath expression must start with '$'", 0);
    pos++; // '$'
    const segments = parseSegments(false);
    skipWs();
    if (pos < len) err(`unexpected trailing token '${s.slice(pos)}'`);
    return { type: "root", segments: segments };
}

function jsonqJpApplySelector(node, sel, root, current) {
    const out = [];
    switch (sel.kind) {
    case "name":
        if (jsonqIsPlainObject(node) && jsonqHasOwn(node, sel.name))
            out.push(node[sel.name]);
        break;
    case "index":
        if (Array.isArray(node)) {
            const idx = sel.index < 0 ? node.length + sel.index : sel.index;
            if (idx >= 0 && idx < node.length) out.push(node[idx]);
        }
        break;
    case "slice":
        if (Array.isArray(node)) {
            const nLen = node.length;
            const step = sel.step === null ? 1 : sel.step;
            if (step === 0) break;
            if (step > 0) {
                let start = sel.start === null ? 0 : (sel.start < 0 ? nLen + sel.start : sel.start);
                let end = sel.end === null ? nLen : (sel.end < 0 ? nLen + sel.end : sel.end);
                if (start < 0) start = 0;
                if (start > nLen) start = nLen;
                if (end < 0) end = 0;
                if (end > nLen) end = nLen;
                for (let i = start; i < end; i += step) out.push(node[i]);
            } else {
                let start = sel.start === null ? nLen - 1 : (sel.start < 0 ? nLen + sel.start : sel.start);
                let end = sel.end === null ? -1 : (sel.end < 0 ? nLen + sel.end : sel.end);
                if (start < -1) start = -1;
                if (start >= nLen) start = nLen - 1;
                if (end < -1) end = -1;
                if (end >= nLen) end = nLen - 1;
                for (let i = start; i > end; i += step) out.push(node[i]);
            }
        }
        break;
    case "wildcard":
        if (Array.isArray(node)) {
            for (let i = 0; i < node.length; i++) out.push(node[i]);
        } else if (jsonqIsPlainObject(node)) {
            const keys = Object.keys(node);
            for (let i = 0; i < keys.length; i++) out.push(node[keys[i]]);
        }
        break;
    case "filter":
        if (Array.isArray(node)) {
            for (let i = 0; i < node.length; i++) {
                if (jsonqJpEvalTest(sel.expr, root, node[i])) out.push(node[i]);
            }
        } else if (jsonqIsPlainObject(node)) {
            const keys = Object.keys(node);
            for (let i = 0; i < keys.length; i++) {
                const v = node[keys[i]];
                if (jsonqJpEvalTest(sel.expr, root, v)) out.push(v);
            }
        }
        break;
    }
    return out;
}

function jsonqJpEvalSegments(nodes, segments, root, current) {
    let cur = nodes;
    for (let s = 0; s < segments.length; s++) {
        const seg = segments[s];
        const next = [];
        for (let i = 0; i < cur.length; i++) {
            const base = cur[i];
            const targets = [];
            if (seg.kind === "descendant")
                jsonqDescendants(base, targets);
            else
                targets.push(base);
            for (let t = 0; t < targets.length; t++) {
                for (let k = 0; k < seg.selectors.length; k++) {
                    const matched = jsonqJpApplySelector(targets[t], seg.selectors[k], root, current);
                    for (let m = 0; m < matched.length; m++) next.push(matched[m]);
                }
            }
        }
        cur = next;
    }
    return cur;
}

function jsonqJpEvalValue(expr, root, current) {
    switch (expr.type) {
    case "lit":
        return expr.value;
    case "path": {
        const start = expr.isRoot ? root : current;
        const nodes = jsonqJpEvalSegments([start], expr.segments, root, current);
        return nodes.length === 1 ? nodes[0] : JSONQ_NOTHING;
    }
    case "func": {
        if (expr.name === "count") {
            if (expr.arg.type !== "path") return JSONQ_NOTHING;
            const start = expr.arg.isRoot ? root : current;
            return jsonqJpEvalSegments([start], expr.arg.segments, root, current).length;
        }
        const v = jsonqJpEvalValue(expr.arg, root, current);
        if (v === JSONQ_NOTHING) return JSONQ_NOTHING;
        if (typeof v === "string") return jsonqCodepointLength(v);
        if (Array.isArray(v)) return v.length;
        if (jsonqIsPlainObject(v)) return Object.keys(v).length;
        return JSONQ_NOTHING;
    }
    default:
        return jsonqJpEvalTest(expr, root, current);
    }
}

function jsonqJpEvalTest(expr, root, current) {
    switch (expr.type) {
    case "or":
        return jsonqJpEvalTest(expr.left, root, current) || jsonqJpEvalTest(expr.right, root, current);
    case "and":
        return jsonqJpEvalTest(expr.left, root, current) && jsonqJpEvalTest(expr.right, root, current);
    case "not":
        return !jsonqJpEvalTest(expr.expr, root, current);
    case "path": {
        const start = expr.isRoot ? root : current;
        const nodes = jsonqJpEvalSegments([start], expr.segments, root, current);
        if (nodes.length === 0) return false;
        if (nodes.length === 1) return Boolean(nodes[0]);
        return true;
    }
    case "regex": {
        const v = jsonqJpEvalValue(expr.left, root, current);
        return typeof v === "string" ? expr.regex.test(v) : false;
    }
    case "cmp": {
        const a = jsonqJpEvalValue(expr.left, root, current);
        const b = jsonqJpEvalValue(expr.right, root, current);
        if (expr.op === "==" || expr.op === "!=") {
            const aMiss = a === JSONQ_NOTHING;
            const bMiss = b === JSONQ_NOTHING;
            let eq;
            if (aMiss || bMiss) eq = aMiss && bMiss;
            else eq = jsonqDeepEqual(a, b);
            return expr.op === "==" ? eq : !eq;
        }
        if (a === JSONQ_NOTHING || b === JSONQ_NOTHING) return false;
        const bothNum = typeof a === "number" && typeof b === "number" && !isNaN(a) && !isNaN(b);
        const bothStr = typeof a === "string" && typeof b === "string";
        if (!bothNum && !bothStr) return false;
        switch (expr.op) {
        case "<": return a < b;
        case "<=": return a <= b;
        case ">": return a > b;
        case ">=": return a >= b;
        }
        return false;
    }
    case "lit":
        return Boolean(expr.value);
    case "func": {
        const v = jsonqJpEvalValue(expr, root, current);
        return v !== JSONQ_NOTHING && Boolean(v);
    }
    }
    return false;
}

function jsonqJpEval(ast, root) {
    return jsonqJpEvalSegments([root], ast.segments, root, root);
}

function jsonqRewriteDotAll(pattern) {
    let out = "";
    let inClass = false;
    for (let i = 0; i < pattern.length; i++) {
        const ch = pattern.charAt(i);
        if (ch === "\\" && i + 1 < pattern.length) {
            out += ch + pattern.charAt(i + 1);
            i++;
            continue;
        }
        if (ch === "[" && !inClass) {
            inClass = true;
            out += ch;
        } else if (ch === "]" && inClass) {
            inClass = false;
            out += ch;
        } else if (ch === "." && !inClass) {
            out += "[\\s\\S]";
        } else {
            out += ch;
        }
    }
    return out;
}

// ── jq Tokenizer, Parser & Stream Evaluator ──

const JSONQ_JQ_KEYWORDS = {
    "and": "AND", "or": "OR", "if": "IF", "then": "THEN", "elif": "ELIF",
    "else": "ELSE", "end": "END", "as": "AS", "reduce": "REDUCE",
    "foreach": "FOREACH", "label": "LABEL", "break": "BREAK",
    "try": "TRY", "catch": "CATCH", "def": "DEF",
    "true": "TRUE", "false": "FALSE", "null": "NULL"
};

function jsonqSafeStringify(v, space) {
    const root = v === undefined ? null : v;
    return JSON.stringify(root, function (k, x) {
        if (x === Infinity) return 1.7976931348623157e+308;
        if (x === -Infinity) return -1.7976931348623157e+308;
        if (x === undefined) return null;
        return x;
    }, space);
}

function jsonqClone(v) {
    if (v === null || typeof v !== "object") return v;
    if (Array.isArray(v)) {
        const out = new Array(v.length);
        for (let i = 0; i < v.length; i++) out[i] = jsonqClone(v[i]);
        return out;
    }
    const out = {};
    const keys = Object.keys(v);
    for (let i = 0; i < keys.length; i++) out[keys[i]] = jsonqClone(v[keys[i]]);
    return out;
}

function jsonqCodepoints(str) {
    const out = [];
    for (let i = 0; i < str.length; i++) {
        const c = str.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
            const c2 = str.charCodeAt(i + 1);
            if (c2 >= 0xdc00 && c2 <= 0xdfff) {
                out.push(0x10000 + (((c & 0x3ff) << 10) | (c2 & 0x3ff)));
                i++;
                continue;
            }
        }
        out.push(c);
    }
    return out;
}

function jsonqFromCodepoints(cps) {
    let out = "";
    for (let i = 0; i < cps.length; i++) {
        const cp = cps[i];
        if (typeof cp !== "number" || !isFinite(cp))
            throw new Error("jq runtime error: implode requires integer codepoints");
        const n = Math.trunc(cp);
        if (n < 0 || n > 0x10ffff)
            throw new Error(`jq runtime error: invalid Unicode codepoint ${n}`);
        if (n <= 0xffff) {
            out += String.fromCharCode(n);
        } else {
            const u = n - 0x10000;
            out += String.fromCharCode(0xd800 + (u >> 10), 0xdc00 + (u & 0x3ff));
        }
    }
    return out;
}

/**
 * Translate jq/Oniguruma regex syntax & flags into QV4-safe RegExp + capture group names.
 * Supports flags: i (ignore case), m (dotall via [\s\S]), x (extended), g (global).
 */
function jsonqJqBuildRegex(pattern, flagsStr, forceGlobal) {
    const f = String(flagsStr || "");
    const dotAll = f.indexOf("m") !== -1 || f.indexOf("p") !== -1;
    const extended = f.indexOf("x") !== -1;
    const isGlobal = Boolean(forceGlobal) || f.indexOf("g") !== -1;
    const jsFlags = (f.indexOf("i") !== -1 ? "i" : "") + (isGlobal ? "g" : "");

    let translated = "";
    const groupNames = [];
    let inClass = false;
    for (let i = 0; i < pattern.length; i++) {
        const ch = pattern.charAt(i);
        if (ch === "\\" && i + 1 < pattern.length) {
            translated += ch + pattern.charAt(i + 1);
            i++;
            continue;
        }
        if (inClass) {
            if (ch === "]") inClass = false;
            translated += ch;
            continue;
        }
        if (extended) {
            if (/\s/.test(ch)) continue;
            if (ch === "#") {
                while (i + 1 < pattern.length && pattern.charAt(i + 1) !== "\n") i++;
                continue;
            }
        }
        if (ch === "[") {
            inClass = true;
            translated += ch;
            continue;
        }
        if (ch === "." && dotAll) {
            translated += "[\\s\\S]";
            continue;
        }
        if (ch === "(") {
            if (pattern.slice(i, i + 3) === "(?<" && pattern.charAt(i + 3) !== "=" && pattern.charAt(i + 3) !== "!") {
                const closeAngle = pattern.indexOf(">", i + 3);
                if (closeAngle !== -1) {
                    const gName = pattern.slice(i + 3, closeAngle);
                    groupNames.push(gName);
                    translated += "(";
                    i = closeAngle;
                    continue;
                }
            }
            if (pattern.charAt(i + 1) !== "?") {
                groupNames.push(null);
            }
            translated += ch;
            continue;
        }
        translated += ch;
    }

    let rx;
    try {
        rx = new RegExp(translated, jsFlags);
    } catch (e) {
        throw new Error("jq runtime error: invalid regex: " + e.message);
    }
    return { regex: rx, groupNames: groupNames };
}

function jsonqJqTokenize(expr, baseOffset) {
    const s = String(expr);
    const len = s.length;
    const off = baseOffset || 0;
    const tokens = [];
    let i = 0;

    function tokErr(msg, p) {
        throw new Error(`jq parse error at column ${(p !== undefined ? p : i) + off + 1}: ${msg}`);
    }

    function scanInterpExpr(startIdx) {
        let p = startIdx;
        let depth = 1;
        while (p < len) {
            const ch = s.charAt(p);
            if (ch === "\"") {
                p++;
                while (p < len) {
                    if (s.charAt(p) === "\\") {
                        if (p + 1 < len && s.charAt(p + 1) === "(") {
                            p = scanInterpExpr(p + 2);
                        } else {
                            p += 2;
                        }
                    } else if (s.charAt(p) === "\"") {
                        p++;
                        break;
                    } else {
                        p++;
                    }
                }
            } else if (ch === "(") {
                depth++;
                p++;
            } else if (ch === ")") {
                depth--;
                if (depth === 0) return p + 1;
                p++;
            } else {
                p++;
            }
        }
        tokErr("unterminated string interpolation '\\(...)'", startIdx - 2);
    }

    while (i < len) {
        const ch = s.charAt(i);
        if (/\s/.test(ch)) { i++; continue; }
        if (ch === "#") {
            while (i < len && s.charAt(i) !== "\n") i++;
            continue;
        }
        const start = i;
        const three = s.slice(i, i + 3);
        if (three === "//=") {
            tokens.push({ type: "ASSIGN", value: "//=", pos: start + off, end: i + 3 + off });
            i += 3;
            continue;
        }
        const two = s.slice(i, i + 2);
        if (two === "..") { tokens.push({ type: "DOTDOT", value: "..", pos: start + off, end: i + 2 + off }); i += 2; continue; }
        if (two === "//") { tokens.push({ type: "ALT", value: "//", pos: start + off, end: i + 2 + off }); i += 2; continue; }
        if (two === "==" || two === "!=" || two === "<=" || two === ">=") {
            tokens.push({ type: "OP", value: two, pos: start + off, end: i + 2 + off });
            i += 2;
            continue;
        }
        if (two === "|=" || two === "+=" || two === "-=" || two === "*=" || two === "/=" || two === "%=") {
            tokens.push({ type: "ASSIGN", value: two, pos: start + off, end: i + 2 + off });
            i += 2;
            continue;
        }
        if (ch === "=") {
            tokens.push({ type: "ASSIGN", value: "=", pos: start + off, end: i + 1 + off });
            i++;
            continue;
        }
        const singleOps = {
            ".": "DOT", "|": "PIPE", ",": "COMMA", ":": "COLON", ";": "SEMI",
            "(": "LPAREN", ")": "RPAREN", "[": "LBRACKET", "]": "RBRACKET",
            "{": "LBRACE", "}": "RBRACE", "?": "QUESTION",
            "+": "PLUS", "-": "MINUS", "*": "STAR", "/": "SLASH", "%": "MOD",
            "<": "LT", ">": "GT"
        };
        if (jsonqHasOwn(singleOps, ch)) {
            tokens.push({ type: singleOps[ch], value: ch, pos: start + off, end: i + 1 + off });
            i++;
            continue;
        }
        if (ch === "@") {
            const m = s.slice(i).match(/^@([A-Za-z_][A-Za-z0-9_]*)/);
            if (!m) tokErr("expected format name after '@'", i);
            tokens.push({ type: "FORMAT", value: m[1], pos: start + off, end: i + m[0].length + off });
            i += m[0].length;
            continue;
        }
        if (ch === "\"") {
            i++;
            const parts = [];
            let buf = "";
            let hasExpr = false;
            while (i < len) {
                const c = s.charAt(i);
                if (c === "\"") {
                    i++;
                    if (hasExpr) {
                        if (buf.length > 0) parts.push({ kind: "lit", text: buf });
                        tokens.push({ type: "INTERP", parts: parts, pos: start + off, end: i + off });
                    } else {
                        tokens.push({ type: "STRING", value: buf, pos: start + off, end: i + off });
                    }
                    buf = null;
                    break;
                }
                if (c === "\\") {
                    if (i + 1 < len && s.charAt(i + 1) === "(") {
                        hasExpr = true;
                        if (buf.length > 0) {
                            parts.push({ kind: "lit", text: buf });
                            buf = "";
                        }
                        const exprStart = i + 2;
                        const afterClose = scanInterpExpr(exprStart);
                        parts.push({ kind: "expr", raw: s.slice(exprStart, afterClose - 1), offset: exprStart + off });
                        i = afterClose;
                    } else {
                        const dec = jsonqDecodeEscape(s, i + 1);
                        if (!dec) tokErr("invalid escape sequence in string", i);
                        buf += dec.ch;
                        i = dec.next;
                    }
                } else {
                    buf += c;
                    i++;
                }
            }
            if (buf !== null) tokErr("unterminated string literal", start);
            continue;
        }
        if (ch === "$") {
            const m = s.slice(i).match(/^\$([A-Za-z_][A-Za-z0-9_]*)/);
            if (!m) tokErr("expected variable name after '$'", i);
            tokens.push({ type: "VAR", value: m[1], pos: start + off, end: i + m[0].length + off });
            i += m[0].length;
            continue;
        }
        if (ch >= "0" && ch <= "9") {
            const m = s.slice(i).match(/^(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/);
            if (!m) tokErr("invalid number literal", i);
            tokens.push({ type: "NUMBER", value: Number(m[0]), pos: start + off, end: i + m[0].length + off });
            i += m[0].length;
            continue;
        }
        if ((ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || ch === "_") {
            const m = s.slice(i).match(/^[A-Za-z_][A-Za-z0-9_]*/);
            const word = m[0];
            const type = jsonqHasOwn(JSONQ_JQ_KEYWORDS, word) ? JSONQ_JQ_KEYWORDS[word] : "IDENT";
            tokens.push({ type: type, value: word, pos: start + off, end: i + word.length + off });
            i += word.length;
            continue;
        }
        tokErr(`unexpected character '${ch}'`, i);
    }
    tokens.push({ type: "EOF", value: "", pos: len + off, end: len + off });
    return tokens;
}

function jsonqJqIsIdentLike(tok) {
    return tok.type === "IDENT" || jsonqHasOwn(JSONQ_JQ_KEYWORDS, tok.value);
}

function jsonqJqParse(expr, baseOffset, initialLabels) {
    const tokens = jsonqJqTokenize(expr, baseOffset || 0);
    let idx = 0;
    let lastEnd = baseOffset || 0;
    const activeLabels = initialLabels ? Object.assign({}, initialLabels) : {};

    function peek(offset) {
        const j = idx + (offset || 0);
        return j < tokens.length ? tokens[j] : tokens[tokens.length - 1];
    }
    function advance() {
        const t = tokens[idx++];
        lastEnd = t.end;
        return t;
    }
    function parseErr(msg, tok) {
        const t = tok || peek();
        throw new Error(`jq parse error at column ${t.pos + 1}: ${msg}`);
    }
    function expect(type, label) {
        const t = peek();
        if (t.type !== type) parseErr(`expected ${label}, got '${t.value || t.type}'`, t);
        return advance();
    }

    function parsePipe(allowComma) {
        if (peek().type === "DEF") {
            advance();
            const nameTok = expect("IDENT", "function name");
            const params = [];
            if (peek().type === "LPAREN") {
                advance();
                if (peek().type !== "RPAREN") {
                    while (true) {
                        const pt = peek();
                        if (pt.type === "VAR") {
                            advance();
                            params.push({ kind: "var", name: pt.value });
                        } else if (pt.type === "IDENT") {
                            advance();
                            params.push({ kind: "filter", name: pt.value });
                        } else {
                            parseErr("expected parameter name or $var", pt);
                        }
                        if (peek().type === "SEMI") { advance(); continue; }
                        break;
                    }
                }
                expect("RPAREN", "')'");
            }
            expect("COLON", "':'");
            const body = parsePipe(true);
            expect("SEMI", "';'");
            const next = parsePipe(allowComma);
            return { type: "def", name: nameTok.value, params: params, body: body, next: next };
        }
        if (peek().type === "LABEL") {
            advance();
            const varTok = expect("VAR", "label name ($var)");
            expect("PIPE", "'|'");
            activeLabels[varTok.value] = (activeLabels[varTok.value] || 0) + 1;
            let body;
            try {
                body = parsePipe(allowComma);
            } finally {
                activeLabels[varTok.value]--;
            }
            return { type: "label", name: varTok.value, body: body };
        }
        const left = allowComma ? parseComma() : parseAssign();
        if (peek().type === "AS") {
            advance();
            const varTok = expect("VAR", "variable name ($var)");
            expect("PIPE", "'|'");
            const body = parsePipe(allowComma);
            return { type: "bind", expr: left, name: varTok.value, body: body };
        }
        if (peek().type === "PIPE") {
            advance();
            const right = parsePipe(allowComma);
            return { type: "pipe", left: left, right: right };
        }
        return left;
    }

    function parseComma() {
        let left = parseAssign();
        while (peek().type === "COMMA") {
            advance();
            const right = parseAssign();
            left = { type: "comma", left: left, right: right };
        }
        return left;
    }

    function parseAssign() {
        const left = parseAlt();
        if (peek().type === "ASSIGN") {
            const op = advance().value;
            const right = parseAssign();
            return { type: "assign", op: op, target: left, expr: right };
        }
        return left;
    }

    function parseAlt() {
        let left = parseOr();
        while (peek().type === "ALT") {
            advance();
            left = { type: "alt", left: left, right: parseOr() };
        }
        return left;
    }

    function parseOr() {
        let left = parseAnd();
        while (peek().type === "OR") {
            advance();
            left = { type: "or", left: left, right: parseAnd() };
        }
        return left;
    }

    function parseAnd() {
        let left = parseCmp();
        while (peek().type === "AND") {
            advance();
            left = { type: "and", left: left, right: parseCmp() };
        }
        return left;
    }

    function parseCmp() {
        let left = parseAdd();
        const t = peek();
        if (t.type === "OP" || t.type === "LT" || t.type === "GT") {
            const op = advance().value;
            const right = parseAdd();
            return { type: "cmp", op: op, left: left, right: right };
        }
        return left;
    }

    function parseAdd() {
        let left = parseMul();
        while (peek().type === "PLUS" || peek().type === "MINUS") {
            const op = advance().value;
            left = { type: "binop", op: op, left: left, right: parseMul() };
        }
        return left;
    }

    function parseMul() {
        let left = parseUnary();
        while (peek().type === "STAR" || peek().type === "SLASH" || peek().type === "MOD") {
            const op = advance().value;
            left = { type: "binop", op: op, left: left, right: parseUnary() };
        }
        return left;
    }

    function parseUnary() {
        if (peek().type === "MINUS") {
            advance();
            return { type: "neg", expr: parseUnary() };
        }
        return parsePostfix();
    }

    function parseBracketPostfix(target) {
        advance(); // '['
        if (peek().type === "RBRACKET") {
            advance();
            return { type: "iterate", target: target, optional: false };
        }
        if (peek().type === "COLON") {
            advance();
            if (peek().type === "RBRACKET") {
                advance();
                return { type: "slice", target: target, start: null, end: null, optional: false };
            }
            const endExpr = parsePipe(true);
            expect("RBRACKET", "']'");
            return { type: "slice", target: target, start: null, end: endExpr, optional: false };
        }
        const firstExpr = parsePipe(true);
        if (peek().type === "COLON") {
            advance();
            if (peek().type === "RBRACKET") {
                advance();
                return { type: "slice", target: target, start: firstExpr, end: null, optional: false };
            }
            const endExpr = parsePipe(true);
            expect("RBRACKET", "']'");
            return { type: "slice", target: target, start: firstExpr, end: endExpr, optional: false };
        }
        expect("RBRACKET", "']'");
        return { type: "index", target: target, index: firstExpr, optional: false };
    }

    function parseDotField(target, dotTok) {
        const nxt = peek();
        if (nxt.pos === dotTok.end && jsonqJqIsIdentLike(nxt)) {
            advance();
            return { type: "field", target: target, key: { type: "lit", value: nxt.value }, optional: false };
        }
        if (nxt.pos === dotTok.end && (nxt.type === "STRING" || nxt.type === "INTERP")) {
            advance();
            return { type: "field", target: target, key: buildStringNode(nxt), optional: false };
        }
        return null;
    }

    function buildStringNode(tok, fmtName) {
        if (tok.type === "STRING") {
            return { type: "lit", value: tok.value };
        }
        const parts = tok.parts.map(p => p.kind === "lit"
            ? { kind: "lit", text: p.text }
            : { kind: "expr", ast: jsonqJqParse(p.raw, p.offset, activeLabels) }
        );
        return { type: "interp", parts: parts, format: fmtName || null };
    }

    function parsePostfix() {
        let node = parsePrimary();
        while (true) {
            const t = peek();
            if (t.type === "QUESTION") {
                advance();
                if (node.type === "field" || node.type === "index" || node.type === "slice" || node.type === "iterate") {
                    node.optional = true;
                } else {
                    node = { type: "try", expr: node, handler: null };
                }
            } else if (t.type === "LBRACKET" && t.pos === lastEnd) {
                node = parseBracketPostfix(node);
            } else if (t.type === "DOT" && t.pos === lastEnd) {
                const dotTok = advance();
                const fieldNode = parseDotField(node, dotTok);
                if (!fieldNode) parseErr("expected field name after '.'", peek());
                node = fieldNode;
            } else {
                break;
            }
        }
        return node;
    }

    function parseIf() {
        advance(); // 'if'
        const cond = parsePipe(true);
        expect("THEN", "'then'");
        const thenBr = parsePipe(true);
        const branches = [{ cond: cond, body: thenBr }];
        while (peek().type === "ELIF") {
            advance();
            const c = parsePipe(true);
            expect("THEN", "'then'");
            const b = parsePipe(true);
            branches.push({ cond: c, body: b });
        }
        let elseBr = { type: "identity" };
        if (peek().type === "ELSE") {
            advance();
            elseBr = parsePipe(true);
        }
        expect("END", "'end'");
        return { type: "if", branches: branches, elseBranch: elseBr };
    }

    function parseObject() {
        advance(); // '{'
        const entries = [];
        if (peek().type === "RBRACE") {
            advance();
            return { type: "object", entries: entries };
        }
        while (true) {
            const t = peek();
            let keyAst;
            let valAst;
            if (t.type === "LPAREN") {
                advance();
                keyAst = parsePipe(true);
                expect("RPAREN", "')'");
                expect("COLON", "':'");
                valAst = parsePipe(false);
            } else if (t.type === "STRING" || t.type === "INTERP") {
                advance();
                keyAst = buildStringNode(t);
                expect("COLON", "':'");
                valAst = parsePipe(false);
            } else if (t.type === "VAR") {
                advance();
                keyAst = { type: "lit", value: t.value };
                if (peek().type === "COLON") {
                    advance();
                    valAst = parsePipe(false);
                } else {
                    valAst = { type: "var", name: t.value };
                }
            } else if (jsonqJqIsIdentLike(t)) {
                advance();
                keyAst = { type: "lit", value: t.value };
                if (peek().type === "COLON") {
                    advance();
                    valAst = parsePipe(false);
                } else {
                    valAst = { type: "field", target: { type: "identity" }, key: { type: "lit", value: t.value }, optional: false };
                }
            } else {
                parseErr(`expected object key, got '${t.value || t.type}'`, t);
            }
            entries.push({ key: keyAst, val: valAst });
            if (peek().type === "COMMA") {
                advance();
                continue;
            }
            expect("RBRACE", "'}' or ','");
            return { type: "object", entries: entries };
        }
    }

    function parsePrimary() {
        const t = peek();
        switch (t.type) {
        case "DOTDOT":
            advance();
            return { type: "call", name: "recurse", args: [], pos: t.pos };
        case "DOT": {
            const dotTok = advance();
            const fieldNode = parseDotField({ type: "identity" }, dotTok);
            if (fieldNode) return fieldNode;
            return { type: "identity" };
        }
        case "NUMBER":
            advance();
            return { type: "lit", value: t.value };
        case "TRUE":
            advance();
            return { type: "lit", value: true };
        case "FALSE":
            advance();
            return { type: "lit", value: false };
        case "NULL":
            advance();
            return { type: "lit", value: null };
        case "STRING":
        case "INTERP":
            advance();
            return buildStringNode(t);
        case "FORMAT": {
            advance();
            const nxt = peek();
            if (nxt.type === "STRING" || nxt.type === "INTERP") {
                return buildStringNode(advance(), t.value);
            }
            return { type: "format", name: t.value, pos: t.pos };
        }
        case "VAR":
            advance();
            return { type: "var", name: t.value };
        case "LPAREN": {
            advance();
            const inner = parsePipe(true);
            expect("RPAREN", "')'");
            return inner;
        }
        case "LBRACKET": {
            advance();
            if (peek().type === "RBRACKET") {
                advance();
                return { type: "array", expr: null };
            }
            const inner = parsePipe(true);
            expect("RBRACKET", "']'");
            return { type: "array", expr: inner };
        }
        case "LBRACE":
            return parseObject();
        case "IF":
            return parseIf();
        case "TRY": {
            advance();
            const tryExpr = parseOr();
            let catchExpr = null;
            if (peek().type === "CATCH") {
                advance();
                catchExpr = parseUnary();
            }
            return { type: "try", expr: tryExpr, handler: catchExpr };
        }
        case "REDUCE": {
            advance();
            const streamExpr = parseComma();
            expect("AS", "'as'");
            const varTok = expect("VAR", "variable name ($var)");
            expect("LPAREN", "'('");
            const initExpr = parsePipe(true);
            expect("SEMI", "';'");
            const updateExpr = parsePipe(true);
            expect("RPAREN", "')'");
            return { type: "reduce", stream: streamExpr, name: varTok.value, init: initExpr, update: updateExpr };
        }
        case "FOREACH": {
            advance();
            const streamExpr = parseComma();
            expect("AS", "'as'");
            const varTok = expect("VAR", "variable name ($var)");
            expect("LPAREN", "'('");
            const initExpr = parsePipe(true);
            expect("SEMI", "';'");
            const updateExpr = parsePipe(true);
            let extractExpr = null;
            if (peek().type === "SEMI") {
                advance();
                extractExpr = parsePipe(true);
            }
            expect("RPAREN", "')'");
            return {
                type: "foreach",
                stream: streamExpr,
                name: varTok.value,
                init: initExpr,
                update: updateExpr,
                extract: extractExpr
            };
        }
        case "BREAK": {
            advance();
            const varTok = expect("VAR", "label name ($var)");
            if (!(activeLabels[varTok.value] > 0))
                parseErr(`$*label-${varTok.value} is not defined`, t);
            return { type: "break", name: varTok.value, pos: t.pos };
        }
        case "IDENT": {
            advance();
            if (peek().type === "LPAREN") {
                advance();
                const args = [];
                if (peek().type !== "RPAREN") {
                    args.push(parsePipe(true));
                    while (peek().type === "SEMI") {
                        advance();
                        args.push(parsePipe(true));
                    }
                }
                expect("RPAREN", "')'");
                return { type: "call", name: t.value, args: args, pos: t.pos };
            }
            return { type: "call", name: t.value, args: [], pos: t.pos };
        }
        default:
            parseErr(`unexpected token '${t.value || t.type}'`, t);
        }
    }

    if (peek().type === "EOF") parseErr("empty expression");
    const ast = parsePipe(true);
    if (peek().type !== "EOF") parseErr(`unexpected trailing token '${peek().value || peek().type}'`);
    return ast;
}

function jsonqJqCompare(a, b) {
    const rank = v => {
        if (v === null) return 0;
        if (v === false) return 1;
        if (v === true) return 2;
        if (typeof v === "number") return 3;
        if (typeof v === "string") return 4;
        if (Array.isArray(v)) return 5;
        return 6;
    };
    const ra = rank(a);
    const rb = rank(b);
    if (ra !== rb) return ra - rb;
    if (ra <= 2) return 0;
    if (ra === 3) return a < b ? -1 : (a > b ? 1 : 0);
    if (ra === 4) return a < b ? -1 : (a > b ? 1 : 0);
    if (ra === 5) {
        const minLen = Math.min(a.length, b.length);
        for (let i = 0; i < minLen; i++) {
            const c = jsonqJqCompare(a[i], b[i]);
            if (c !== 0) return c;
        }
        return a.length - b.length;
    }
    const ka = Object.keys(a).sort();
    const kb = Object.keys(b).sort();
    const keyCmp = jsonqJqCompare(ka, kb);
    if (keyCmp !== 0) return keyCmp;
    for (let i = 0; i < ka.length; i++) {
        const c = jsonqJqCompare(a[ka[i]], b[ka[i]]);
        if (c !== 0) return c;
    }
    return 0;
}

function jsonqJqAdd(a, b) {
    if (a === null) return b;
    if (b === null) return a;
    if (typeof a === "number" && typeof b === "number") return a + b;
    if (typeof a === "string" && typeof b === "string") return a + b;
    if (Array.isArray(a) && Array.isArray(b)) return a.concat(b);
    if (jsonqIsPlainObject(a) && jsonqIsPlainObject(b)) {
        const out = {};
        const ka = Object.keys(a);
        for (let i = 0; i < ka.length; i++) out[ka[i]] = a[ka[i]];
        const kb = Object.keys(b);
        for (let i = 0; i < kb.length; i++) out[kb[i]] = b[kb[i]];
        return out;
    }
    throw new Error(`Cannot add ${jsonqTypeOf(a)} and ${jsonqTypeOf(b)}`);
}

function jsonqJqMultiply(a, b) {
    if (typeof a === "number" && typeof b === "number") return a * b;
    if ((typeof a === "string" && typeof b === "number") || (typeof a === "number" && typeof b === "string")) {
        const str = typeof a === "string" ? a : b;
        const n = Math.trunc(typeof a === "string" ? b : a);
        if (n < 0) return null;
        if (n === 0 || str.length === 0) return "";
        if (str.length * n > 1000000)
            throw new Error("jq runtime error: string repeat length limit exceeded");
        let res = "";
        for (let i = 0; i < n; i++) res += str;
        return res;
    }
    if (jsonqIsPlainObject(a) && jsonqIsPlainObject(b)) {
        const out = {};
        const ka = Object.keys(a);
        for (let i = 0; i < ka.length; i++) out[ka[i]] = a[ka[i]];
        const kb = Object.keys(b);
        for (let i = 0; i < kb.length; i++) {
            const k = kb[i];
            if (jsonqHasOwn(out, k) && jsonqIsPlainObject(out[k]) && jsonqIsPlainObject(b[k]))
                out[k] = jsonqJqMultiply(out[k], b[k]);
            else
                out[k] = b[k];
        }
        return out;
    }
    throw new Error(`jq runtime error: cannot multiply ${jsonqTypeOf(a)} and ${jsonqTypeOf(b)}`);
}

function jsonqJqBinop(op, a, b) {
    switch (op) {
    case "+":
        return jsonqJqAdd(a, b);
    case "-":
        if (typeof a === "number" && typeof b === "number") return a - b;
        if (Array.isArray(a) && Array.isArray(b))
            return a.filter(x => !b.some(y => jsonqDeepEqual(x, y)));
        throw new Error(`jq runtime error: cannot subtract ${jsonqTypeOf(b)} from ${jsonqTypeOf(a)}`);
    case "*":
        return jsonqJqMultiply(a, b);
    case "/":
        if (typeof a === "number" && typeof b === "number") {
            if (b === 0) throw new Error("jq runtime error: division by zero");
            return a / b;
        }
        if (typeof a === "string" && typeof b === "string") return a.split(b);
        throw new Error(`jq runtime error: cannot divide ${jsonqTypeOf(a)} by ${jsonqTypeOf(b)}`);
    case "%":
        if (typeof a === "number" && typeof b === "number") {
            const ib = Math.trunc(b);
            if (ib === 0) throw new Error("jq runtime error: modulo by zero");
            return Math.trunc(a) % ib;
        }
        throw new Error(`jq runtime error: cannot compute modulo of ${jsonqTypeOf(a)} and ${jsonqTypeOf(b)}`);
    }
    throw new Error(`jq runtime error: unknown operator ${op}`);
}

function jsonqJqContains(a, b) {
    if (typeof a === "string" && typeof b === "string") return a.indexOf(b) !== -1;
    if (Array.isArray(a) && Array.isArray(b)) {
        for (let i = 0; i < b.length; i++) {
            let found = false;
            for (let j = 0; j < a.length; j++) {
                if (jsonqJqContains(a[j], b[i])) { found = true; break; }
            }
            if (!found) return false;
        }
        return true;
    }
    if (jsonqIsPlainObject(a) && jsonqIsPlainObject(b)) {
        const keys = Object.keys(b);
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i];
            if (!jsonqHasOwn(a, k) || !jsonqJqContains(a[k], b[k])) return false;
        }
        return true;
    }
    return jsonqDeepEqual(a, b);
}

function jsonqJqHasKey(container, key) {
    if (container === null) return false;
    if (jsonqIsPlainObject(container)) {
        if (typeof key !== "string")
            throw new Error(`Cannot check whether object has a ${jsonqTypeOf(key)} key`);
        return jsonqHasOwn(container, key);
    }
    if (Array.isArray(container)) {
        if (typeof key !== "number")
            throw new Error(`Cannot check whether array has a ${jsonqTypeOf(key)} index`);
        return key >= 0 && key < container.length && Math.floor(key) === key;
    }
    throw new Error(`Cannot check whether ${jsonqTypeOf(container)} has a key`);
}

function jsonqJqSortByKeys(arr, keyFn) {
    const pairs = [];
    for (let i = 0; i < arr.length; i++) {
        pairs.push({ item: arr[i], key: keyFn(arr[i]), idx: i });
    }
    pairs.sort((a, b) => {
        const len = Math.min(a.key.length, b.key.length);
        for (let i = 0; i < len; i++) {
            const c = jsonqJqCompare(a.key[i], b.key[i]);
            if (c !== 0) return c;
        }
        return (a.key.length - b.key.length) || (a.idx - b.idx);
    });
    return pairs;
}

function jsonqJqGetPath(root, path) {
    if (!Array.isArray(path)) throw new Error("jq runtime error: path must be an array");
    let cur = root;
    for (let i = 0; i < path.length; i++) {
        const seg = path[i];
        if (cur === null) {
            if (typeof seg !== "string" && typeof seg !== "number" && !jsonqIsPlainObject(seg))
                throw new Error(`jq runtime error: cannot index null with ${jsonqTypeOf(seg)}`);
            cur = null;
        } else if (jsonqIsPlainObject(cur)) {
            if (typeof seg !== "string")
                throw new Error(`jq runtime error: cannot index object with ${jsonqTypeOf(seg)}`);
            cur = jsonqHasOwn(cur, seg) ? cur[seg] : null;
        } else if (Array.isArray(cur)) {
            if (typeof seg === "number") {
                const n = Math.trunc(seg);
                const pos = n < 0 ? cur.length + n : n;
                cur = pos >= 0 && pos < cur.length ? cur[pos] : null;
            } else if (jsonqIsPlainObject(seg) && (jsonqHasOwn(seg, "start") || jsonqHasOwn(seg, "end"))) {
                const len = cur.length;
                let a = seg.start === null || seg.start === undefined ? 0 : Math.trunc(seg.start);
                let b = seg.end === null || seg.end === undefined ? len : Math.trunc(seg.end);
                if (a < 0) a = Math.max(0, len + a);
                if (b < 0) b = Math.max(0, len + b);
                cur = cur.slice(a, b);
            } else {
                throw new Error(`jq runtime error: cannot index array with ${jsonqTypeOf(seg)}`);
            }
        } else {
            throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(cur)} with ${jsonqTypeOf(seg)}`);
        }
    }
    return cur;
}

function jsonqJqSetPath(root, path, newVal) {
    if (!Array.isArray(path)) throw new Error("jq runtime error: path must be an array");
    if (path.length === 0) return jsonqClone(newVal);

    function setAt(cur, idx) {
        const seg = path[idx];
        const isLast = idx === path.length - 1;
        if (typeof seg === "string") {
            let obj;
            if (cur === null || cur === undefined) obj = {};
            else if (jsonqIsPlainObject(cur)) obj = Object.assign({}, cur);
            else throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(cur)} with string "${seg}"`);
            obj[seg] = isLast ? jsonqClone(newVal) : setAt(jsonqHasOwn(obj, seg) ? obj[seg] : null, idx + 1);
            return obj;
        }
        if (typeof seg === "number") {
            const n = Math.trunc(seg);
            let arr;
            if (cur === null || cur === undefined) arr = [];
            else if (Array.isArray(cur)) arr = cur.slice();
            else throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(cur)} with number`);
            const pos = n < 0 ? arr.length + n : n;
            if (pos < 0) throw new Error("jq runtime error: array index out of bounds");
            if (pos > 100000) throw new Error("jq runtime error: array index too large");
            while (arr.length <= pos) arr.push(null);
            arr[pos] = isLast ? jsonqClone(newVal) : setAt(arr[pos], idx + 1);
            return arr;
        }
        if (jsonqIsPlainObject(seg) && (jsonqHasOwn(seg, "start") || jsonqHasOwn(seg, "end"))) {
            if (!isLast) throw new Error("jq runtime error: slice must be at end of path");
            let arr;
            if (cur === null || cur === undefined) arr = [];
            else if (Array.isArray(cur)) arr = cur.slice();
            else throw new Error(`jq runtime error: cannot slice ${jsonqTypeOf(cur)}`);
            if (!Array.isArray(newVal))
                throw new Error("jq runtime error: slice assignment value must be an array");
            const len = arr.length;
            let a = seg.start === null || seg.start === undefined ? 0 : Math.trunc(seg.start);
            let b = seg.end === null || seg.end === undefined ? len : Math.trunc(seg.end);
            if (a < 0) a = Math.max(0, len + a);
            if (b < 0) b = Math.max(0, len + b);
            if (a > len) a = len;
            if (b < a) b = a;
            return arr.slice(0, a).concat(jsonqClone(newVal), arr.slice(b));
        }
        throw new Error(`jq runtime error: invalid path segment of type ${jsonqTypeOf(seg)}`);
    }

    return setAt(root, 0);
}

const JSONQ_DELETED = { __jsonqDeleted: true };

function jsonqJqDelPaths(root, paths) {
    if (!Array.isArray(paths)) throw new Error("jq runtime error: delpaths requires array of paths");
    if (paths.length === 0) return jsonqClone(root);
    let doc = jsonqClone(root);
    for (let p = 0; p < paths.length; p++) {
        const path = paths[p];
        if (!Array.isArray(path)) throw new Error("jq runtime error: each path in delpaths must be an array");
        if (path.length === 0) return null;
        let cur = doc;
        let ok = true;
        for (let i = 0; i < path.length - 1; i++) {
            const seg = path[i];
            if (cur === null || cur === undefined) { ok = false; break; }
            if (jsonqIsPlainObject(cur) && typeof seg === "string") {
                if (!jsonqHasOwn(cur, seg)) { ok = false; break; }
                cur = cur[seg];
            } else if (Array.isArray(cur) && typeof seg === "number") {
                const n = Math.trunc(seg);
                const pos = n < 0 ? cur.length + n : n;
                if (pos < 0 || pos >= cur.length) { ok = false; break; }
                cur = cur[pos];
            } else {
                ok = false;
                break;
            }
        }
        if (!ok || cur === null || cur === undefined) continue;
        const lastSeg = path[path.length - 1];
        if (jsonqIsPlainObject(cur) && typeof lastSeg === "string") {
            delete cur[lastSeg];
        } else if (Array.isArray(cur)) {
            if (typeof lastSeg === "number") {
                const n = Math.trunc(lastSeg);
                const pos = n < 0 ? cur.length + n : n;
                if (pos >= 0 && pos < cur.length) cur[pos] = JSONQ_DELETED;
            } else if (jsonqIsPlainObject(lastSeg) && (jsonqHasOwn(lastSeg, "start") || jsonqHasOwn(lastSeg, "end"))) {
                const len = cur.length;
                let a = lastSeg.start === null || lastSeg.start === undefined ? 0 : Math.trunc(lastSeg.start);
                let b = lastSeg.end === null || lastSeg.end === undefined ? len : Math.trunc(lastSeg.end);
                if (a < 0) a = Math.max(0, len + a);
                if (b < 0) b = Math.max(0, len + b);
                for (let k = a; k < Math.min(b, len); k++) cur[k] = JSONQ_DELETED;
            }
        }
    }
    function compact(node) {
        if (Array.isArray(node)) {
            const out = [];
            for (let i = 0; i < node.length; i++) {
                if (node[i] !== JSONQ_DELETED) out.push(compact(node[i]));
            }
            return out;
        }
        if (jsonqIsPlainObject(node)) {
            const keys = Object.keys(node);
            for (let i = 0; i < keys.length; i++) node[keys[i]] = compact(node[keys[i]]);
        }
        return node;
    }
    return compact(doc);
}

function jsonqJqFormat(fmtName, val) {
    const toText = v => typeof v === "string" ? v : jsonqSafeStringify(v);
    switch (fmtName) {
    case "text":
        return toText(val);
    case "json":
        return jsonqSafeStringify(val);
    case "html":
        return toText(val)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&apos;");
    case "uri":
        return encodeURIComponent(toText(val))
            .replace(/[!'()*]/g, c => "%" + c.charCodeAt(0).toString(16).toUpperCase());
    case "base64":
        return bytesToBase64(utf8Encode(toText(val)));
    case "base64d":
        if (typeof val !== "string")
            throw new Error(`jq runtime error: @base64d requires string, got ${jsonqTypeOf(val)}`);
        return utf8Decode(base64ToBytes(val));
    case "sh": {
        const s = toText(val);
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }
    case "csv":
    case "tsv": {
        if (!Array.isArray(val))
            throw new Error(`jq runtime error: @${fmtName} requires array, got ${jsonqTypeOf(val)}`);
        const isCsv = fmtName === "csv";
        const parts = [];
        for (let i = 0; i < val.length; i++) {
            const el = val[i];
            if (el === null) parts.push("");
            else if (typeof el === "number" || typeof el === "boolean") parts.push(String(el));
            else if (typeof el === "string") {
                if (isCsv) parts.push("\"" + el.replace(/"/g, "\"\"") + "\"");
                else parts.push(el.replace(/\\/g, "\\\\").replace(/\t/g, "\\t").replace(/\r/g, "\\r").replace(/\n/g, "\\n"));
            } else {
                throw new Error(`jq runtime error: @${fmtName} cannot format ${jsonqTypeOf(el)}`);
            }
        }
        return parts.join(isCsv ? "," : "\t");
    }
    default:
        throw new Error(`jq runtime error: unknown format @${fmtName}`);
    }
}

function jsonqJqEval(ast, input, env) {
    const MAX_OUT = 50000;
    const MAX_DEPTH = 256;
    const isTruthy = v => v !== false && v !== null;
    const toStr = v => typeof v === "string" ? v : jsonqSafeStringify(v);

    function errorMessage(e) {
        if (e && jsonqHasOwn(e, "jqVal")) return e.jqVal;
        const msg = e && e.message ? e.message : String(e);
        return msg.replace(/^jq (?:runtime |error: )+/, "");
    }

    function evalCollect(node, val, vars, fns, depth) {
        const out = [];
        evalStream(node, val, vars, fns, depth, item => {
            out.push(item);
            if (out.length > MAX_OUT)
                throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
        });
        return out;
    }

    function evalSomeTruthy(node, val, vars, fns, depth) {
        const stop = { __jsonqStop: true };
        let hit = false;
        try {
            evalStream(node, val, vars, fns, depth, v => {
                if (isTruthy(v)) {
                    hit = true;
                    throw stop;
                }
            });
        } catch (e) {
            if (e !== stop) throw e;
        }
        return hit;
    }

    function evalStream(node, val, vars, fns, depth, emit) {
        switch (node.type) {
        case "identity":
            emit(val);
            return;
        case "lit":
            emit(node.value);
            return;
        case "var":
            if (jsonqHasOwn(vars, node.name)) {
                emit(vars[node.name]);
                return;
            }
            if (node.name === "ENV") {
                emit({});
                return;
            }
            throw new Error(`jq runtime error: undefined variable $${node.name}`);
        case "format":
            emit(jsonqJqFormat(node.name, val));
            return;
        case "interp": {
            let acc = [""];
            for (let i = 0; i < node.parts.length; i++) {
                const p = node.parts[i];
                if (p.kind === "lit") {
                    for (let j = 0; j < acc.length; j++) acc[j] += p.text;
                } else {
                    const vals = evalCollect(p.ast, val, vars, fns, depth);
                    const next = [];
                    for (let j = 0; j < acc.length; j++) {
                        for (let k = 0; k < vals.length; k++) {
                            const piece = node.format ? jsonqJqFormat(node.format, vals[k]) : toStr(vals[k]);
                            next.push(acc[j] + piece);
                            if (next.length > MAX_OUT)
                                throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                        }
                    }
                    acc = next;
                }
            }
            for (let i = 0; i < acc.length; i++) emit(acc[i]);
            return;
        }
        case "def": {
            const childFns = Object.assign({}, fns);
            const fnKey = node.name + "/" + node.params.length;
            childFns[fnKey] = {
                params: node.params,
                body: node.body,
                vars: vars,
                fns: childFns
            };
            evalStream(node.next, val, vars, childFns, depth, emit);
            return;
        }
        case "comma":
            evalStream(node.left, val, vars, fns, depth, emit);
            evalStream(node.right, val, vars, fns, depth, emit);
            return;
        case "pipe":
            evalStream(node.left, val, vars, fns, depth, mid => {
                evalStream(node.right, mid, vars, fns, depth, emit);
            });
            return;
        case "bind":
            evalStream(node.expr, val, vars, fns, depth, boundVal => {
                const childVars = Object.assign({}, vars);
                childVars[node.name] = boundVal;
                evalStream(node.body, val, childVars, fns, depth, emit);
            });
            return;
        case "reduce": {
            const streamVals = evalCollect(node.stream, val, vars, fns, depth);
            evalStream(node.init, val, vars, fns, depth, initVal => {
                let acc = initVal;
                for (let i = 0; i < streamVals.length; i++) {
                    const childVars = Object.assign({}, vars);
                    childVars[node.name] = streamVals[i];
                    let last = acc;
                    let hasNext = false;
                    evalStream(node.update, acc, childVars, fns, depth, n => {
                        last = n;
                        hasNext = true;
                    });
                    if (hasNext) acc = last;
                }
                emit(acc);
            });
            return;
        }
        case "foreach": {
            evalStream(node.init, val, vars, fns, depth, initVal => {
                let state = initVal;
                evalStream(node.stream, val, vars, fns, depth, item => {
                    const childVars = Object.assign({}, vars);
                    childVars[node.name] = item;
                    evalStream(node.update, state, childVars, fns, depth, nextState => {
                        state = nextState;
                        if (node.extract) {
                            evalStream(node.extract, state, childVars, fns, depth, emit);
                        } else {
                            emit(state);
                        }
                    });
                });
            });
            return;
        }
        case "label": {
            const token = { __jsonqBreak: true, name: node.name };
            const childVars = Object.assign({}, vars);
            childVars["\0label:" + node.name] = token;
            try {
                evalStream(node.body, val, childVars, fns, depth, emit);
            } catch (e) {
                if (e !== token) throw e;
            }
            return;
        }
        case "break": {
            const key = "\0label:" + node.name;
            if (!jsonqHasOwn(vars, key))
                throw new Error(`jq parse error at column ${(node.pos || 0) + 1}: $*label-${node.name} is not defined`);
            throw vars[key];
        }
        case "array":
            if (!node.expr) { emit([]); return; }
            emit(evalCollect(node.expr, val, vars, fns, depth));
            return;
        case "object": {
            let objs = [{}];
            for (let e = 0; e < node.entries.length; e++) {
                const entry = node.entries[e];
                const keys = evalCollect(entry.key, val, vars, fns, depth);
                const vals = evalCollect(entry.val, val, vars, fns, depth);
                const next = [];
                for (let o = 0; o < objs.length; o++) {
                    for (let k = 0; k < keys.length; k++) {
                        if (typeof keys[k] !== "string")
                            throw new Error(`jq runtime error: object key must be a string, got ${jsonqTypeOf(keys[k])}`);
                        for (let v = 0; v < vals.length; v++) {
                            const copy = Object.assign({}, objs[o]);
                            copy[keys[k]] = vals[v];
                            next.push(copy);
                            if (next.length > MAX_OUT)
                                throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                        }
                    }
                }
                objs = next;
            }
            for (let i = 0; i < objs.length; i++) emit(objs[i]);
            return;
        }
        case "field":
            evalStream(node.target, val, vars, fns, depth, t => {
                evalStream(node.key, val, vars, fns, depth, key => {
                    try {
                        if (typeof key !== "string")
                            throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(t)} with ${jsonqTypeOf(key)}`);
                        if (t === null) emit(null);
                        else if (jsonqIsPlainObject(t)) emit(jsonqHasOwn(t, key) ? t[key] : null);
                        else throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(t)} with string "${key}"`);
                    } catch (e) {
                        if (e && (e.__jsonqStop || e.__jsonqBreak)) throw e;
                        if (!node.optional) throw e;
                    }
                });
            });
            return;
        case "index":
            evalStream(node.target, val, vars, fns, depth, t => {
                evalStream(node.index, val, vars, fns, depth, idx => {
                    try {
                        if (t === null) {
                            emit(null);
                        } else if (Array.isArray(t) && typeof idx === "number") {
                            const n = Math.trunc(idx);
                            const pos = n < 0 ? t.length + n : n;
                            emit(pos >= 0 && pos < t.length ? t[pos] : null);
                        } else if (jsonqIsPlainObject(t) && typeof idx === "string") {
                            emit(jsonqHasOwn(t, idx) ? t[idx] : null);
                        } else {
                            throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(t)} with ${jsonqTypeOf(idx)}`);
                        }
                    } catch (e) {
                        if (e && (e.__jsonqStop || e.__jsonqBreak)) throw e;
                        if (!node.optional) throw e;
                    }
                });
            });
            return;
        case "slice":
            evalStream(node.target, val, vars, fns, depth, t => {
                const starts = node.start ? evalCollect(node.start, val, vars, fns, depth) : [null];
                const ends = node.end ? evalCollect(node.end, val, vars, fns, depth) : [null];
                for (let s = 0; s < starts.length; s++) {
                    for (let e = 0; e < ends.length; e++) {
                        try {
                            if (t === null) { emit(null); continue; }
                            if (!Array.isArray(t) && typeof t !== "string")
                                throw new Error(`jq runtime error: cannot slice ${jsonqTypeOf(t)}`);
                            const st = starts[s];
                            const en = ends[e];
                            if ((st !== null && typeof st !== "number") || (en !== null && typeof en !== "number"))
                                throw new Error("jq runtime error: slice indices must be numbers");
                            const len = t.length;
                            let a = st === null ? 0 : Math.trunc(st);
                            let b = en === null ? len : Math.trunc(en);
                            if (a < 0) a = Math.max(0, len + a);
                            if (b < 0) b = Math.max(0, len + b);
                            emit(t.slice(a, b));
                        } catch (err) {
                            if (err && (err.__jsonqStop || err.__jsonqBreak)) throw err;
                            if (!node.optional) throw err;
                        }
                    }
                }
            });
            return;
        case "iterate":
            evalStream(node.target, val, vars, fns, depth, t => {
                if (Array.isArray(t)) {
                    for (let j = 0; j < t.length; j++) emit(t[j]);
                } else if (jsonqIsPlainObject(t)) {
                    const keys = Object.keys(t);
                    for (let j = 0; j < keys.length; j++) emit(t[keys[j]]);
                } else if (!node.optional) {
                    throw new Error(`jq runtime error: cannot iterate over ${jsonqTypeOf(t)}`);
                }
            });
            return;
        case "try":
            try {
                evalStream(node.expr, val, vars, fns, depth, emit);
            } catch (e) {
                if (e && (e.__jsonqStop || e.__jsonqBreak)) throw e;
                if (node.handler) {
                    evalStream(node.handler, errorMessage(e), vars, fns, depth, emit);
                }
            }
            return;
        case "assign": {
            const paths = [];
            evalPaths(node.target, val, vars, fns, depth, p => paths.push(p));
            if (node.op === "|=") {
                let doc = jsonqClone(val);
                const toDelete = [];
                for (let i = 0; i < paths.length; i++) {
                    const p = paths[i];
                    const cur = jsonqJqGetPath(val, p);
                    const stop = { __jsonqStop: true };
                    let hasVal = false;
                    let firstVal;
                    try {
                        evalStream(node.expr, cur, vars, fns, depth, v => {
                            if (!hasVal) {
                                firstVal = v;
                                hasVal = true;
                                throw stop;
                            }
                        });
                    } catch (e) {
                        if (e !== stop) throw e;
                    }
                    if (!hasVal) toDelete.push(p);
                    else doc = jsonqJqSetPath(doc, p, firstVal);
                }
                if (toDelete.length > 0) doc = jsonqJqDelPaths(doc, toDelete);
                emit(doc);
                return;
            }
            const binOp = node.op.length === 2 ? node.op.charAt(0) : null;
            evalStream(node.expr, val, vars, fns, depth, rVal => {
                let doc = jsonqClone(val);
                for (let i = 0; i < paths.length; i++) {
                    const p = paths[i];
                    if (node.op === "=") {
                        doc = jsonqJqSetPath(doc, p, rVal);
                    } else if (node.op === "//=") {
                        const cur = jsonqJqGetPath(doc, p);
                        doc = jsonqJqSetPath(doc, p, isTruthy(cur) ? cur : rVal);
                    } else {
                        const cur = jsonqJqGetPath(doc, p);
                        doc = jsonqJqSetPath(doc, p, jsonqJqBinop(binOp, cur, rVal));
                    }
                }
                emit(doc);
            });
            return;
        }
        case "alt": {
            let emitted = false;
            evalStream(node.left, val, vars, fns, depth, v => {
                if (isTruthy(v)) {
                    emitted = true;
                    emit(v);
                }
            });
            if (!emitted) evalStream(node.right, val, vars, fns, depth, emit);
            return;
        }
        case "or":
            evalStream(node.left, val, vars, fns, depth, lv => {
                if (isTruthy(lv)) emit(true);
                else evalStream(node.right, val, vars, fns, depth, rv => emit(isTruthy(rv)));
            });
            return;
        case "and":
            evalStream(node.left, val, vars, fns, depth, lv => {
                if (!isTruthy(lv)) emit(false);
                else evalStream(node.right, val, vars, fns, depth, rv => emit(isTruthy(rv)));
            });
            return;
        case "cmp": {
            const lhs = evalCollect(node.left, val, vars, fns, depth);
            const rhs = evalCollect(node.right, val, vars, fns, depth);
            for (let j = 0; j < rhs.length; j++) {
                for (let i = 0; i < lhs.length; i++) {
                    const c = jsonqJqCompare(lhs[i], rhs[j]);
                    let res = false;
                    switch (node.op) {
                    case "==": res = jsonqDeepEqual(lhs[i], rhs[j]); break;
                    case "!=": res = !jsonqDeepEqual(lhs[i], rhs[j]); break;
                    case "<": res = c < 0; break;
                    case "<=": res = c <= 0; break;
                    case ">": res = c > 0; break;
                    case ">=": res = c >= 0; break;
                    }
                    emit(res);
                }
            }
            return;
        }
        case "neg":
            evalStream(node.expr, val, vars, fns, depth, v => {
                if (typeof v !== "number")
                    throw new Error(`jq runtime error: cannot negate ${jsonqTypeOf(v)}`);
                emit(-v);
            });
            return;
        case "binop": {
            const lhs = evalCollect(node.left, val, vars, fns, depth);
            const rhs = evalCollect(node.right, val, vars, fns, depth);
            for (let j = 0; j < rhs.length; j++) {
                for (let i = 0; i < lhs.length; i++) {
                    emit(jsonqJqBinop(node.op, lhs[i], rhs[j]));
                }
            }
            return;
        }
        case "if": {
            function runBranch(branchIdx) {
                if (branchIdx >= node.branches.length) {
                    evalStream(node.elseBranch, val, vars, fns, depth, emit);
                    return;
                }
                const br = node.branches[branchIdx];
                evalStream(br.cond, val, vars, fns, depth, condVal => {
                    if (isTruthy(condVal)) {
                        evalStream(br.body, val, vars, fns, depth, emit);
                    } else {
                        runBranch(branchIdx + 1);
                    }
                });
            }
            runBranch(0);
            return;
        }
        case "call":
            evalCall(node, val, vars, fns, depth, emit);
            return;
        }
        throw new Error("jq runtime error: unknown AST node");
    }

    function evalPaths(node, val, vars, fns, depth, emitPath) {
        switch (node.type) {
        case "identity":
            emitPath([]);
            return;
        case "field":
            evalPaths(node.target, val, vars, fns, depth, p => {
                const cur = jsonqJqGetPath(val, p);
                evalStream(node.key, val, vars, fns, depth, key => {
                    try {
                        if (typeof key !== "string")
                            throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(cur)} with ${jsonqTypeOf(key)}`);
                        if (cur !== null && !jsonqIsPlainObject(cur))
                            throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(cur)} with string "${key}"`);
                        emitPath(p.concat([key]));
                    } catch (e) {
                        if (e && e.__jsonqStop) throw e;
                        if (!node.optional) throw e;
                    }
                });
            });
            return;
        case "index":
            evalPaths(node.target, val, vars, fns, depth, p => {
                const cur = jsonqJqGetPath(val, p);
                evalStream(node.index, val, vars, fns, depth, idx => {
                    try {
                        if (cur === null) {
                            if (typeof idx !== "number" && typeof idx !== "string")
                                throw new Error(`jq runtime error: cannot index null with ${jsonqTypeOf(idx)}`);
                            emitPath(p.concat([typeof idx === "number" ? Math.trunc(idx) : idx]));
                        } else if (Array.isArray(cur) && typeof idx === "number") {
                            const n = Math.trunc(idx);
                            const pos = n < 0 ? cur.length + n : n;
                            emitPath(p.concat([pos]));
                        } else if (jsonqIsPlainObject(cur) && typeof idx === "string") {
                            emitPath(p.concat([idx]));
                        } else {
                            throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(cur)} with ${jsonqTypeOf(idx)}`);
                        }
                    } catch (e) {
                        if (e && e.__jsonqStop) throw e;
                        if (!node.optional) throw e;
                    }
                });
            });
            return;
        case "slice":
            evalPaths(node.target, val, vars, fns, depth, p => {
                const cur = jsonqJqGetPath(val, p);
                const starts = node.start ? evalCollect(node.start, val, vars, fns, depth) : [null];
                const ends = node.end ? evalCollect(node.end, val, vars, fns, depth) : [null];
                for (let s = 0; s < starts.length; s++) {
                    for (let e = 0; e < ends.length; e++) {
                        try {
                            if (cur !== null && !Array.isArray(cur))
                                throw new Error(`jq runtime error: cannot slice ${jsonqTypeOf(cur)}`);
                            const st = starts[s], en = ends[e];
                            if ((st !== null && typeof st !== "number") || (en !== null && typeof en !== "number"))
                                throw new Error("jq runtime error: slice indices must be numbers");
                            emitPath(p.concat([{ start: st, end: en }]));
                        } catch (err) {
                            if (err && err.__jsonqStop) throw err;
                            if (!node.optional) throw err;
                        }
                    }
                }
            });
            return;
        case "iterate":
            evalPaths(node.target, val, vars, fns, depth, p => {
                const cur = jsonqJqGetPath(val, p);
                if (Array.isArray(cur)) {
                    for (let i = 0; i < cur.length; i++) emitPath(p.concat([i]));
                } else if (jsonqIsPlainObject(cur)) {
                    const keys = Object.keys(cur);
                    for (let i = 0; i < keys.length; i++) emitPath(p.concat([keys[i]]));
                } else if (!node.optional) {
                    throw new Error(`jq runtime error: cannot iterate over ${jsonqTypeOf(cur)}`);
                }
            });
            return;
        case "comma":
            evalPaths(node.left, val, vars, fns, depth, emitPath);
            evalPaths(node.right, val, vars, fns, depth, emitPath);
            return;
        case "pipe":
            evalPaths(node.left, val, vars, fns, depth, p1 => {
                const v1 = jsonqJqGetPath(val, p1);
                evalPaths(node.right, v1, vars, fns, depth, p2 => {
                    emitPath(p1.concat(p2));
                });
            });
            return;
        case "bind":
            evalStream(node.expr, val, vars, fns, depth, boundVal => {
                const childVars = Object.assign({}, vars);
                childVars[node.name] = boundVal;
                evalPaths(node.body, val, childVars, fns, depth, emitPath);
            });
            return;
        case "if": {
            function runBranch(branchIdx) {
                if (branchIdx >= node.branches.length) {
                    evalPaths(node.elseBranch, val, vars, fns, depth, emitPath);
                    return;
                }
                const br = node.branches[branchIdx];
                evalStream(br.cond, val, vars, fns, depth, condVal => {
                    if (isTruthy(condVal)) evalPaths(br.body, val, vars, fns, depth, emitPath);
                    else runBranch(branchIdx + 1);
                });
            }
            runBranch(0);
            return;
        }
        case "try":
            try {
                evalPaths(node.expr, val, vars, fns, depth, emitPath);
            } catch (e) {
                if (e && e.__jsonqStop) throw e;
                if (node.handler) evalPaths(node.handler, errorMessage(e), vars, fns, depth, emitPath);
            }
            return;
        case "call": {
            const fnKey = node.name + "/" + node.args.length;
            if (jsonqHasOwn(fns, fnKey)) {
                const fn = fns[fnKey];
                if (fn.builtinClosure) {
                    evalPaths(fn.builtinClosure, val, fn.vars, fn.fns, depth + 1, emitPath);
                    return;
                }
                const nextFns = Object.assign({}, fn.fns);
                nextFns[fnKey] = fn;
                for (let i = 0; i < fn.params.length; i++) {
                    if (fn.params[i].kind === "filter") {
                        nextFns[fn.params[i].name + "/0"] = {
                            builtinClosure: node.args[i],
                            vars: vars,
                            fns: fns,
                            params: []
                        };
                    }
                }
                evalPaths(fn.body, val, fn.vars, nextFns, depth + 1, emitPath);
                return;
            }
            switch (node.name) {
            case "empty":
                return;
            case "select":
                checkArity(node, 1);
                evalStream(node.args[0], val, vars, fns, depth, c => {
                    if (isTruthy(c)) emitPath([]);
                });
                return;
            case "values":
                checkArity(node, 0);
                if (val !== null) emitPath([]);
                return;
            case "nulls":
                checkArity(node, 0);
                if (val === null) emitPath([]);
                return;
            case "booleans":
                checkArity(node, 0);
                if (typeof val === "boolean") emitPath([]);
                return;
            case "numbers":
                checkArity(node, 0);
                if (typeof val === "number") emitPath([]);
                return;
            case "strings":
                checkArity(node, 0);
                if (typeof val === "string") emitPath([]);
                return;
            case "arrays":
                checkArity(node, 0);
                if (Array.isArray(val)) emitPath([]);
                return;
            case "objects":
                checkArity(node, 0);
                if (jsonqIsPlainObject(val)) emitPath([]);
                return;
            case "iterables":
                checkArity(node, 0);
                if (Array.isArray(val) || jsonqIsPlainObject(val)) emitPath([]);
                return;
            case "scalars":
                checkArity(node, 0);
                if (!Array.isArray(val) && !jsonqIsPlainObject(val)) emitPath([]);
                return;
            case "getpath":
                checkArity(node, 1);
                evalStream(node.args[0], val, vars, fns, depth, p => {
                    if (!Array.isArray(p)) throw new Error("jq runtime error: getpath requires array");
                    emitPath(p);
                });
                return;
            case "recurse": {
                checkArity(node, 0, 2);
                let count = 0;
                function walkPaths(curPath, curVal) {
                    if (++count > MAX_OUT)
                        throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                    if (node.args.length === 2) {
                        if (!evalSomeTruthy(node.args[1], curVal, vars, fns, depth)) return;
                    }
                    emitPath(curPath);
                    if (node.args.length === 0) {
                        if (Array.isArray(curVal)) {
                            for (let i = 0; i < curVal.length; i++) walkPaths(curPath.concat([i]), curVal[i]);
                        } else if (jsonqIsPlainObject(curVal)) {
                            const keys = Object.keys(curVal);
                            for (let i = 0; i < keys.length; i++) walkPaths(curPath.concat([keys[i]]), curVal[keys[i]]);
                        }
                    } else {
                        evalPaths(node.args[0], curVal, vars, fns, depth, dp => {
                            const nextPath = curPath.concat(dp);
                            walkPaths(nextPath, jsonqJqGetPath(val, nextPath));
                        });
                    }
                }
                walkPaths([], val);
                return;
            }
            case "first":
                if (node.args.length === 1) {
                    const stop = { __jsonqStop: true };
                    try {
                        evalPaths(node.args[0], val, vars, fns, depth, p => {
                            emitPath(p);
                            throw stop;
                        });
                    } catch (e) {
                        if (e !== stop) throw e;
                    }
                    return;
                }
                break;
            case "limit":
                if (node.args.length === 2) {
                    evalStream(node.args[0], val, vars, fns, depth, n => {
                        if (typeof n !== "number") throw new Error("jq runtime error: limit count must be a number");
                        const count = Math.trunc(n);
                        if (count < 0) throw new Error("jq runtime error: limit count must be non-negative");
                        if (count === 0) return;
                        const stop = { __jsonqStop: true };
                        let seen = 0;
                        try {
                            evalPaths(node.args[1], val, vars, fns, depth, p => {
                                emitPath(p);
                                if (++seen >= count) throw stop;
                            });
                        } catch (e) {
                            if (e !== stop) throw e;
                        }
                    });
                    return;
                }
                break;
            }
            throw new Error(`jq runtime error: invalid path expression '${node.name}'`);
        }
        default:
            throw new Error("jq runtime error: invalid path expression");
        }
    }

    function checkArity(node, minArgs, maxArgs) {
        const n = node.args.length;
        const max = maxArgs !== undefined ? maxArgs : minArgs;
        if (n < minArgs || n > max) {
            const expected = minArgs === max ? String(minArgs) : `${minArgs}-${max}`;
            throw new Error(`jq runtime error: ${node.name}() expects ${expected} argument(s), got ${n}`);
        }
    }

    function evalUserDef(fn, fnKey, argNodes, val, callerVars, callerFns, depth, emit) {
        if (depth >= MAX_DEPTH)
            throw new Error("jq runtime error: maximum recursion depth exceeded");
        if (fn.builtinClosure) {
            evalStream(fn.builtinClosure, val, fn.vars, fn.fns, depth + 1, emit);
            return;
        }
        const baseFns = Object.assign({}, fn.fns);
        baseFns[fnKey] = fn;
        const varParamIdxs = [];
        for (let i = 0; i < fn.params.length; i++) {
            const param = fn.params[i];
            if (param.kind === "filter") {
                baseFns[param.name + "/0"] = {
                    builtinClosure: argNodes[i],
                    vars: callerVars,
                    fns: callerFns,
                    params: []
                };
            } else {
                varParamIdxs.push(i);
            }
        }
        function bindVarParam(vIdx, curVars) {
            if (vIdx >= varParamIdxs.length) {
                evalStream(fn.body, val, curVars, baseFns, depth + 1, emit);
                return;
            }
            const pIdx = varParamIdxs[vIdx];
            const pName = fn.params[pIdx].name;
            evalStream(argNodes[pIdx], val, callerVars, callerFns, depth, argVal => {
                const nextVars = Object.assign({}, curVars);
                nextVars[pName] = argVal;
                bindVarParam(vIdx + 1, nextVars);
            });
        }
        bindVarParam(0, fn.vars);
    }

    function evalRegexReplace(val, reAst, replAst, flagsAst, isGlobal, vars, fns, depth, emit) {
        if (typeof val !== "string")
            throw new Error(`jq runtime error: ${isGlobal ? "gsub" : "sub"}() requires string, got ${jsonqTypeOf(val)}`);
        const patterns = evalCollect(reAst, val, vars, fns, depth);
        const flagList = flagsAst ? evalCollect(flagsAst, val, vars, fns, depth) : [""];
        for (let r = 0; r < patterns.length; r++) {
            for (let f = 0; f < flagList.length; f++) {
                if (typeof patterns[r] !== "string" || typeof flagList[f] !== "string")
                    throw new Error(`jq runtime error: ${isGlobal ? "gsub" : "sub"}() pattern and flags must be strings`);
                const built = jsonqJqBuildRegex(patterns[r], flagList[f], isGlobal);
                const rx = built.regex;
                const groupNames = built.groupNames;

                function matchToCaps(m) {
                    const caps = {};
                    for (let g = 0; g < groupNames.length; g++) {
                        if (groupNames[g]) {
                            caps[groupNames[g]] = m[g + 1] !== undefined ? m[g + 1] : null;
                        }
                    }
                    return caps;
                }

                if (!isGlobal) {
                    const m = rx.exec(val);
                    if (!m) {
                        emit(val);
                    } else {
                        const caps = matchToCaps(m);
                        const repls = evalCollect(replAst, caps, vars, fns, depth);
                        const prefix = val.slice(0, m.index);
                        const suffix = val.slice(m.index + m[0].length);
                        for (let k = 0; k < repls.length; k++) {
                            if (typeof repls[k] !== "string")
                                throw new Error("jq runtime error: sub() replacement must be string");
                            emit(prefix + repls[k] + suffix);
                        }
                    }
                } else {
                    const matches = [];
                    let m;
                    rx.lastIndex = 0;
                    while ((m = rx.exec(val)) !== null) {
                        matches.push({ index: m.index, text: m[0], caps: matchToCaps(m) });
                        if (m[0].length === 0) {
                            if (rx.lastIndex >= val.length) break;
                            rx.lastIndex++;
                        }
                    }
                    if (matches.length === 0) {
                        emit(val);
                    } else {
                        let outs = [""];
                        let cursor = 0;
                        for (let mi = 0; mi < matches.length; mi++) {
                            const hit = matches[mi];
                            const litGap = val.slice(cursor, hit.index);
                            cursor = hit.index + hit.text.length;
                            const repls = evalCollect(replAst, hit.caps, vars, fns, depth);
                            const nextOuts = [];
                            for (let oi = 0; oi < outs.length; oi++) {
                                for (let ri = 0; ri < repls.length; ri++) {
                                    if (typeof repls[ri] !== "string")
                                        throw new Error("jq runtime error: gsub() replacement must be string");
                                    nextOuts.push(outs[oi] + litGap + repls[ri]);
                                    if (nextOuts.length > MAX_OUT)
                                        throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                                }
                            }
                            outs = nextOuts;
                        }
                        const tail = val.slice(cursor);
                        for (let oi = 0; oi < outs.length; oi++) emit(outs[oi] + tail);
                    }
                }
            }
        }
    }

    function computeIndices(val, needle) {
        if (val === null) return null;
        if (typeof val === "string") {
            if (typeof needle !== "string")
                throw new Error(`jq runtime error: cannot search string for ${jsonqTypeOf(needle)}`);
            if (needle.length === 0) return [];
            const out = [];
            let idx = val.indexOf(needle);
            while (idx !== -1) {
                out.push(idx);
                idx = val.indexOf(needle, idx + 1);
            }
            return out;
        }
        if (Array.isArray(val)) {
            const out = [];
            if (Array.isArray(needle)) {
                if (needle.length === 0) return [];
                for (let i = 0; i <= val.length - needle.length; i++) {
                    let ok = true;
                    for (let j = 0; j < needle.length; j++) {
                        if (!jsonqDeepEqual(val[i + j], needle[j])) { ok = false; break; }
                    }
                    if (ok) out.push(i);
                }
            } else {
                for (let i = 0; i < val.length; i++) {
                    if (jsonqDeepEqual(val[i], needle)) out.push(i);
                }
            }
            return out;
        }
        throw new Error(`jq runtime error: cannot index ${jsonqTypeOf(val)} in indices()`);
    }

    function evalCall(node, val, vars, fns, depth, emit) {
        const args = node.args;
        const fnKey = node.name + "/" + args.length;
        if (jsonqHasOwn(fns, fnKey)) {
            evalUserDef(fns[fnKey], fnKey, args, val, vars, fns, depth, emit);
            return;
        }

        switch (node.name) {
        case "empty":
            checkArity(node, 0);
            return;
        case "not":
            checkArity(node, 0);
            emit(isTruthy(val) ? false : true);
            return;
        case "type":
            checkArity(node, 0);
            emit(jsonqTypeOf(val));
            return;
        case "tostring":
            checkArity(node, 0);
            emit(toStr(val));
            return;
        case "tojson":
            checkArity(node, 0);
            emit(jsonqSafeStringify(val));
            return;
        case "fromjson":
            checkArity(node, 0);
            if (typeof val !== "string")
                throw new Error(`jq runtime error: ${jsonqTypeOf(val)} cannot be parsed as JSON`);
            try { emit(JSON.parse(val)); }
            catch (e) { throw new Error("jq runtime error: invalid JSON in fromjson"); }
            return;
        case "tonumber":
            checkArity(node, 0);
            if (typeof val === "number") { emit(val); return; }
            if (typeof val === "string") {
                const trimmed = val.trim();
                if (/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(trimmed)) {
                    emit(Number(trimmed));
                    return;
                }
                throw new Error(`jq runtime error: string ${JSON.stringify(val)} cannot be parsed as a number`);
            }
            throw new Error(`jq runtime error: ${jsonqTypeOf(val)} cannot be parsed as a number`);
        case "ascii_downcase":
            checkArity(node, 0);
            if (typeof val !== "string") throw new Error(`jq runtime error: ascii_downcase requires string, got ${jsonqTypeOf(val)}`);
            emit(val.replace(/[A-Z]/g, ch => String.fromCharCode(ch.charCodeAt(0) + 32)));
            return;
        case "ascii_upcase":
            checkArity(node, 0);
            if (typeof val !== "string") throw new Error(`jq runtime error: ascii_upcase requires string, got ${jsonqTypeOf(val)}`);
            emit(val.replace(/[a-z]/g, ch => String.fromCharCode(ch.charCodeAt(0) - 32)));
            return;
        case "explode":
            checkArity(node, 0);
            if (typeof val !== "string") throw new Error(`jq runtime error: explode requires string, got ${jsonqTypeOf(val)}`);
            emit(jsonqCodepoints(val));
            return;
        case "implode":
            checkArity(node, 0);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: implode requires array, got ${jsonqTypeOf(val)}`);
            emit(jsonqFromCodepoints(val));
            return;
        case "length":
            checkArity(node, 0);
            if (val === null) emit(0);
            else if (typeof val === "string") emit(jsonqCodepointLength(val));
            else if (Array.isArray(val)) emit(val.length);
            else if (jsonqIsPlainObject(val)) emit(Object.keys(val).length);
            else if (typeof val === "number") emit(Math.abs(val));
            else throw new Error(`jq runtime error: ${jsonqTypeOf(val)} has no length`);
            return;
        case "keys":
        case "keys_unsorted":
            checkArity(node, 0);
            if (jsonqIsPlainObject(val)) {
                const k = Object.keys(val);
                emit(node.name === "keys" ? k.sort() : k);
                return;
            }
            if (Array.isArray(val)) {
                const out = [];
                for (let i = 0; i < val.length; i++) out.push(i);
                emit(out);
                return;
            }
            throw new Error(`jq runtime error: ${jsonqTypeOf(val)} has no keys`);
        case "values":
            checkArity(node, 0);
            if (val !== null) emit(val);
            return;
        case "nulls":
            checkArity(node, 0);
            if (val === null) emit(val);
            return;
        case "booleans":
            checkArity(node, 0);
            if (typeof val === "boolean") emit(val);
            return;
        case "numbers":
            checkArity(node, 0);
            if (typeof val === "number") emit(val);
            return;
        case "strings":
            checkArity(node, 0);
            if (typeof val === "string") emit(val);
            return;
        case "arrays":
            checkArity(node, 0);
            if (Array.isArray(val)) emit(val);
            return;
        case "objects":
            checkArity(node, 0);
            if (jsonqIsPlainObject(val)) emit(val);
            return;
        case "iterables":
            checkArity(node, 0);
            if (Array.isArray(val) || jsonqIsPlainObject(val)) emit(val);
            return;
        case "scalars":
            checkArity(node, 0);
            if (!Array.isArray(val) && !jsonqIsPlainObject(val)) emit(val);
            return;
        case "select":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, c => {
                if (isTruthy(c)) emit(val);
            });
            return;
        case "map": {
            checkArity(node, 1);
            const items = Array.isArray(val)
                ? val
                : (jsonqIsPlainObject(val) ? Object.keys(val).map(k => val[k]) : null);
            if (!items) throw new Error(`jq runtime error: cannot iterate over ${jsonqTypeOf(val)} in map()`);
            const out = [];
            for (let i = 0; i < items.length; i++) {
                evalStream(args[0], items[i], vars, fns, depth, mapped => {
                    out.push(mapped);
                    if (out.length > MAX_OUT)
                        throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                });
            }
            emit(out);
            return;
        }
        case "map_values":
            checkArity(node, 1);
            if (jsonqIsPlainObject(val)) {
                const res = {};
                const keys = Object.keys(val);
                for (let i = 0; i < keys.length; i++) {
                    const k = keys[i];
                    const stop = { __jsonqStop: true };
                    try {
                        evalStream(args[0], val[k], vars, fns, depth, mv => {
                            res[k] = mv;
                            throw stop;
                        });
                    } catch (e) {
                        if (e !== stop) throw e;
                    }
                }
                emit(res);
                return;
            }
            if (Array.isArray(val)) {
                const out = [];
                for (let i = 0; i < val.length; i++) {
                    evalStream(args[0], val[i], vars, fns, depth, mv => out.push(mv));
                }
                emit(out);
                return;
            }
            throw new Error(`jq runtime error: cannot iterate over ${jsonqTypeOf(val)} in map_values()`);
        case "has":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, k => emit(jsonqJqHasKey(val, k)));
            return;
        case "in":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, t => emit(jsonqJqHasKey(t, val)));
            return;
        case "to_entries":
            checkArity(node, 0);
            if (jsonqIsPlainObject(val)) {
                emit(Object.keys(val).map(k => ({ key: k, value: val[k] })));
                return;
            }
            if (Array.isArray(val)) {
                emit(val.map((v, idx) => ({ key: idx, value: v })));
                return;
            }
            throw new Error(`jq runtime error: ${jsonqTypeOf(val)} cannot be converted with to_entries`);
        case "from_entries": {
            checkArity(node, 0);
            if (!Array.isArray(val))
                throw new Error(`jq runtime error: from_entries requires array, got ${jsonqTypeOf(val)}`);
            const obj = {};
            for (let i = 0; i < val.length; i++) {
                const item = val[i];
                if (!jsonqIsPlainObject(item))
                    throw new Error("jq runtime error: from_entries elements must be objects");
                let k;
                if (jsonqHasOwn(item, "key")) k = item.key;
                else if (jsonqHasOwn(item, "Key")) k = item.Key;
                else if (jsonqHasOwn(item, "name")) k = item.name;
                else if (jsonqHasOwn(item, "Name")) k = item.Name;
                if (typeof k !== "string")
                    throw new Error("jq runtime error: from_entries entry missing string key/name");
                let v = null;
                if (jsonqHasOwn(item, "value")) v = item.value;
                else if (jsonqHasOwn(item, "Value")) v = item.Value;
                obj[k] = v;
            }
            emit(obj);
            return;
        }
        case "with_entries": {
            checkArity(node, 1);
            const entries = evalCollect({ type: "call", name: "to_entries", args: [] }, val, vars, fns, depth)[0];
            const mapped = [];
            for (let i = 0; i < entries.length; i++) {
                evalStream(args[0], entries[i], vars, fns, depth, r => mapped.push(r));
            }
            evalCall({ type: "call", name: "from_entries", args: [] }, mapped, vars, fns, depth, emit);
            return;
        }
        case "sort":
            checkArity(node, 0);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot sort ${jsonqTypeOf(val)}`);
            emit(val.slice().sort(jsonqJqCompare));
            return;
        case "sort_by": {
            checkArity(node, 1);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot sort_by ${jsonqTypeOf(val)}`);
            const pairs = jsonqJqSortByKeys(val, el => evalCollect(args[0], el, vars, fns, depth));
            emit(pairs.map(p => p.item));
            return;
        }
        case "group_by": {
            checkArity(node, 1);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot group_by ${jsonqTypeOf(val)}`);
            if (val.length === 0) { emit([]); return; }
            const pairs = jsonqJqSortByKeys(val, el => evalCollect(args[0], el, vars, fns, depth));
            const groups = [];
            let curGroup = [pairs[0].item];
            let curKey = pairs[0].key;
            for (let i = 1; i < pairs.length; i++) {
                if (jsonqDeepEqual(curKey, pairs[i].key)) {
                    curGroup.push(pairs[i].item);
                } else {
                    groups.push(curGroup);
                    curGroup = [pairs[i].item];
                    curKey = pairs[i].key;
                }
            }
            groups.push(curGroup);
            emit(groups);
            return;
        }
        case "unique": {
            checkArity(node, 0);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot unique ${jsonqTypeOf(val)}`);
            const sorted = val.slice().sort(jsonqJqCompare);
            const out = [];
            for (let i = 0; i < sorted.length; i++) {
                if (i === 0 || !jsonqDeepEqual(sorted[i], sorted[i - 1])) out.push(sorted[i]);
            }
            emit(out);
            return;
        }
        case "unique_by": {
            checkArity(node, 1);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot unique_by ${jsonqTypeOf(val)}`);
            const pairs = jsonqJqSortByKeys(val, el => evalCollect(args[0], el, vars, fns, depth));
            const out = [];
            for (let i = 0; i < pairs.length; i++) {
                if (i === 0 || !jsonqDeepEqual(pairs[i].key, pairs[i - 1].key)) out.push(pairs[i].item);
            }
            emit(out);
            return;
        }
        case "min":
        case "max": {
            checkArity(node, 0);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot compute ${node.name} of ${jsonqTypeOf(val)}`);
            if (val.length === 0) { emit(null); return; }
            const isMax = node.name === "max";
            let best = val[0];
            for (let i = 1; i < val.length; i++) {
                const c = jsonqJqCompare(val[i], best);
                if (isMax ? c > 0 : c < 0) best = val[i];
            }
            emit(best);
            return;
        }
        case "min_by":
        case "max_by": {
            checkArity(node, 1);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot compute ${node.name} of ${jsonqTypeOf(val)}`);
            if (val.length === 0) { emit(null); return; }
            const isMax = node.name === "max_by";
            let bestItem = val[0];
            let bestKey = evalCollect(args[0], val[0], vars, fns, depth);
            for (let i = 1; i < val.length; i++) {
                const k = evalCollect(args[0], val[i], vars, fns, depth);
                const len = Math.min(k.length, bestKey.length);
                let cmp = k.length - bestKey.length;
                for (let j = 0; j < len; j++) {
                    const c = jsonqJqCompare(k[j], bestKey[j]);
                    if (c !== 0) { cmp = c; break; }
                }
                if (isMax ? cmp > 0 : cmp < 0) {
                    bestItem = val[i];
                    bestKey = k;
                }
            }
            emit(bestItem);
            return;
        }
        case "add": {
            checkArity(node, 0);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot add elements of ${jsonqTypeOf(val)}`);
            let acc = null;
            for (let i = 0; i < val.length; i++) acc = jsonqJqAdd(acc, val[i]);
            emit(acc);
            return;
        }
        case "any":
        case "all": {
            checkArity(node, 0, 2);
            const isAll = node.name === "all";
            if (args.length === 2) {
                const stop = { __jsonqStop: true };
                let result = isAll;
                try {
                    evalStream(args[0], val, vars, fns, depth, item => {
                        const truth = evalSomeTruthy(args[1], item, vars, fns, depth);
                        if (isAll && !truth) { result = false; throw stop; }
                        if (!isAll && truth) { result = true; throw stop; }
                    });
                } catch (e) {
                    if (e !== stop) throw e;
                }
                emit(result);
                return;
            }
            if (!Array.isArray(val)) throw new Error(`jq runtime error: ${node.name} requires array, got ${jsonqTypeOf(val)}`);
            for (let i = 0; i < val.length; i++) {
                const truth = args.length === 1
                    ? evalSomeTruthy(args[0], val[i], vars, fns, depth)
                    : isTruthy(val[i]);
                if (isAll && !truth) { emit(false); return; }
                if (!isAll && truth) { emit(true); return; }
            }
            emit(isAll);
            return;
        }
        case "limit":
            checkArity(node, 2);
            evalStream(args[0], val, vars, fns, depth, n => {
                if (typeof n !== "number") throw new Error("jq runtime error: limit() count must be a number");
                const count = Math.trunc(n);
                if (count < 0) throw new Error("jq runtime error: limit() doesn't support negative count");
                if (count === 0) return;
                const stop = { __jsonqStop: true };
                let seen = 0;
                try {
                    evalStream(args[1], val, vars, fns, depth, item => {
                        emit(item);
                        if (++seen >= count) throw stop;
                    });
                } catch (e) {
                    if (e !== stop) throw e;
                }
            });
            return;
        case "first":
        case "last": {
            checkArity(node, 0, 1);
            const isLast = node.name === "last";
            if (args.length === 1) {
                if (!isLast) {
                    const stop = { __jsonqStop: true };
                    try {
                        evalStream(args[0], val, vars, fns, depth, item => {
                            emit(item);
                            throw stop;
                        });
                    } catch (e) {
                        if (e !== stop) throw e;
                    }
                    return;
                }
                let hasLast = false;
                let lastVal;
                evalStream(args[0], val, vars, fns, depth, item => {
                    hasLast = true;
                    lastVal = item;
                });
                if (hasLast) emit(lastVal);
                return;
            }
            if (!Array.isArray(val)) throw new Error(`jq runtime error: ${node.name} requires array, got ${jsonqTypeOf(val)}`);
            if (val.length === 0) { emit(null); return; }
            emit(isLast ? val[val.length - 1] : val[0]);
            return;
        }
        case "nth": {
            checkArity(node, 1, 2);
            if (args.length === 1) {
                if (!Array.isArray(val)) throw new Error(`jq runtime error: nth() requires array, got ${jsonqTypeOf(val)}`);
                evalStream(args[0], val, vars, fns, depth, n => {
                    if (typeof n !== "number") throw new Error("jq runtime error: nth() index must be number");
                    const idx = Math.trunc(n);
                    emit(idx >= 0 && idx < val.length ? val[idx] : null);
                });
                return;
            }
            evalStream(args[0], val, vars, fns, depth, n => {
                if (typeof n !== "number") throw new Error("jq runtime error: nth() index must be number");
                const targetIdx = Math.trunc(n);
                if (targetIdx < 0) return;
                const stop = { __jsonqStop: true };
                let curIdx = 0;
                try {
                    evalStream(args[1], val, vars, fns, depth, item => {
                        if (curIdx === targetIdx) {
                            emit(item);
                            throw stop;
                        }
                        curIdx++;
                    });
                } catch (e) {
                    if (e !== stop) throw e;
                }
            });
            return;
        }
        case "while":
        case "until": {
            checkArity(node, 2);
            const isUntil = node.name === "until";
            let steps = 0;
            function step(cur) {
                if (++steps > MAX_OUT)
                    throw new Error(`jq runtime error: ${node.name}() exceeded ${MAX_OUT} iterations`);
                const cond = evalSomeTruthy(args[0], cur, vars, fns, depth);
                if (isUntil) {
                    if (cond) { emit(cur); return; }
                } else {
                    if (!cond) return;
                    emit(cur);
                }
                evalStream(args[1], cur, vars, fns, depth, nextVal => step(nextVal));
            }
            step(val);
            return;
        }
        case "recurse": {
            checkArity(node, 0, 2);
            let count = 0;
            function walk(cur) {
                if (++count > MAX_OUT)
                    throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                if (args.length === 2) {
                    if (!evalSomeTruthy(args[1], cur, vars, fns, depth)) return;
                }
                emit(cur);
                if (args.length === 0) {
                    if (Array.isArray(cur)) {
                        for (let i = 0; i < cur.length; i++) walk(cur[i]);
                    } else if (jsonqIsPlainObject(cur)) {
                        const keys = Object.keys(cur);
                        for (let i = 0; i < keys.length; i++) walk(cur[keys[i]]);
                    }
                } else {
                    evalStream(args[0], cur, vars, fns, depth, nextVal => walk(nextVal));
                }
            }
            walk(val);
            return;
        }
        case "path":
            checkArity(node, 1);
            evalPaths(args[0], val, vars, fns, depth, emit);
            return;
        case "paths":
        case "leaf_paths": {
            const isLeaf = node.name === "leaf_paths";
            checkArity(node, isLeaf ? 0 : 0, isLeaf ? 0 : 1);
            const hasFilter = !isLeaf && args.length === 1;
            let count = 0;
            function walkAllPaths(cur, prefix) {
                if (Array.isArray(cur)) {
                    for (let i = 0; i < cur.length; i++) {
                        const p = prefix.concat([i]);
                        const child = cur[i];
                        if (isLeaf) {
                            if (!Array.isArray(child) && !jsonqIsPlainObject(child)) emit(p);
                        } else if (!hasFilter || evalSomeTruthy(args[0], child, vars, fns, depth)) {
                            emit(p);
                        }
                        if (++count > MAX_OUT)
                            throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                        walkAllPaths(child, p);
                    }
                } else if (jsonqIsPlainObject(cur)) {
                    const keys = Object.keys(cur);
                    for (let i = 0; i < keys.length; i++) {
                        const k = keys[i];
                        const p = prefix.concat([k]);
                        const child = cur[k];
                        if (isLeaf) {
                            if (!Array.isArray(child) && !jsonqIsPlainObject(child)) emit(p);
                        } else if (!hasFilter || evalSomeTruthy(args[0], child, vars, fns, depth)) {
                            emit(p);
                        }
                        if (++count > MAX_OUT)
                            throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                        walkAllPaths(child, p);
                    }
                }
            }
            walkAllPaths(val, []);
            return;
        }
        case "getpath":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, p => emit(jsonqJqGetPath(val, p)));
            return;
        case "setpath":
            checkArity(node, 2);
            evalStream(args[0], val, vars, fns, depth, p => {
                evalStream(args[1], val, vars, fns, depth, v => {
                    emit(jsonqJqSetPath(val, p, v));
                });
            });
            return;
        case "delpaths":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, ps => emit(jsonqJqDelPaths(val, ps)));
            return;
        case "del": {
            checkArity(node, 1);
            const paths = [];
            evalPaths(args[0], val, vars, fns, depth, p => paths.push(p));
            emit(jsonqJqDelPaths(val, paths));
            return;
        }
        case "reverse":
            checkArity(node, 0);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot reverse ${jsonqTypeOf(val)}`);
            emit(val.slice().reverse());
            return;
        case "flatten": {
            checkArity(node, 0, 1);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: cannot flatten ${jsonqTypeOf(val)}`);
            if (args.length === 0) {
                const out = [];
                jsonqFlatten(val, Infinity, out);
                emit(out);
                return;
            }
            evalStream(args[0], val, vars, fns, depth, d => {
                if (typeof d !== "number" || d < 0)
                    throw new Error("jq runtime error: flatten depth must be a non-negative number");
                const out = [];
                jsonqFlatten(val, Math.floor(d), out);
                emit(out);
            });
            return;
        }
        case "range": {
            checkArity(node, 1, 3);
            let emitted = 0;
            const pushRange = x => {
                if (++emitted > MAX_OUT)
                    throw new Error(`jq runtime error: output exceeded ${MAX_OUT} items`);
                emit(x);
            };
            if (args.length === 1) {
                evalStream(args[0], val, vars, fns, depth, endVal => {
                    if (typeof endVal !== "number") throw new Error("jq runtime error: range() requires number");
                    for (let i = 0; i < endVal; i++) pushRange(i);
                });
                return;
            }
            const starts = evalCollect(args[0], val, vars, fns, depth);
            const ends = evalCollect(args[1], val, vars, fns, depth);
            const steps = args.length === 3 ? evalCollect(args[2], val, vars, fns, depth) : [1];
            for (let s = 0; s < starts.length; s++) {
                for (let e = 0; e < ends.length; e++) {
                    for (let st = 0; st < steps.length; st++) {
                        const a = starts[s], b = ends[e], step = steps[st];
                        if (typeof a !== "number" || typeof b !== "number" || typeof step !== "number")
                            throw new Error("jq runtime error: range() bounds and step must be numbers");
                        if (step === 0) continue;
                        if (step > 0) {
                            for (let x = a; x < b; x += step) pushRange(x);
                        } else {
                            for (let x = a; x > b; x += step) pushRange(x);
                        }
                    }
                }
            }
            return;
        }
        case "split": {
            checkArity(node, 1, 2);
            if (typeof val !== "string") throw new Error(`jq runtime error: split() requires string, got ${jsonqTypeOf(val)}`);
            if (args.length === 1) {
                evalStream(args[0], val, vars, fns, depth, sep => {
                    if (typeof sep !== "string") throw new Error("jq runtime error: split() separator must be a string");
                    emit(val.split(sep));
                });
                return;
            }
            const patterns = evalCollect(args[0], val, vars, fns, depth);
            const flagList = evalCollect(args[1], val, vars, fns, depth);
            for (let r = 0; r < patterns.length; r++) {
                for (let f = 0; f < flagList.length; f++) {
                    if (typeof patterns[r] !== "string" || typeof flagList[f] !== "string")
                        throw new Error("jq runtime error: split() pattern and flags must be strings");
                    const rx = jsonqJqBuildRegex(patterns[r], flagList[f], false).regex;
                    emit(val.split(rx));
                }
            }
            return;
        }
        case "splits": {
            checkArity(node, 1, 2);
            if (typeof val !== "string") throw new Error(`jq runtime error: splits() requires string, got ${jsonqTypeOf(val)}`);
            const patterns = evalCollect(args[0], val, vars, fns, depth);
            const flagList = args.length === 2 ? evalCollect(args[1], val, vars, fns, depth) : [""];
            for (let r = 0; r < patterns.length; r++) {
                for (let f = 0; f < flagList.length; f++) {
                    if (typeof patterns[r] !== "string" || typeof flagList[f] !== "string")
                        throw new Error("jq runtime error: splits() pattern and flags must be strings");
                    const rx = jsonqJqBuildRegex(patterns[r], flagList[f], false).regex;
                    const parts = val.split(rx);
                    for (let i = 0; i < parts.length; i++) emit(parts[i]);
                }
            }
            return;
        }
        case "join":
            checkArity(node, 1);
            if (!Array.isArray(val)) throw new Error(`jq runtime error: join() requires array, got ${jsonqTypeOf(val)}`);
            evalStream(args[0], val, vars, fns, depth, sep => {
                if (typeof sep !== "string") throw new Error("jq runtime error: join() separator must be a string");
                const parts = [];
                for (let i = 0; i < val.length; i++) {
                    const el = val[i];
                    if (el === null) parts.push("");
                    else if (typeof el === "string" || typeof el === "number" || typeof el === "boolean") parts.push(String(el));
                    else throw new Error(`jq runtime error: cannot join ${jsonqTypeOf(el)}`);
                }
                emit(parts.join(sep));
            });
            return;
        case "test": {
            checkArity(node, 1, 2);
            if (typeof val !== "string") throw new Error(`jq runtime error: test() requires string, got ${jsonqTypeOf(val)}`);
            const res = evalCollect(args[0], val, vars, fns, depth);
            const flagList = args.length === 2 ? evalCollect(args[1], val, vars, fns, depth) : [""];
            for (let r = 0; r < res.length; r++) {
                for (let f = 0; f < flagList.length; f++) {
                    if (typeof res[r] !== "string" || typeof flagList[f] !== "string")
                        throw new Error("jq runtime error: test() pattern and flags must be strings");
                    const rx = jsonqJqBuildRegex(res[r], flagList[f], false).regex;
                    emit(rx.test(val));
                }
            }
            return;
        }
        case "sub":
        case "gsub":
            checkArity(node, 2, 3);
            evalRegexReplace(val, args[0], args[1], args.length === 3 ? args[2] : null, node.name === "gsub", vars, fns, depth, emit);
            return;
        case "indices":
        case "index":
        case "rindex":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, needle => {
                const idxs = computeIndices(val, needle);
                if (node.name === "indices") emit(idxs);
                else if (!idxs || idxs.length === 0) emit(null);
                else emit(node.name === "index" ? idxs[0] : idxs[idxs.length - 1]);
            });
            return;
        case "startswith":
        case "endswith":
        case "ltrimstr":
        case "rtrimstr":
            checkArity(node, 1);
            if (typeof val !== "string") throw new Error(`jq runtime error: ${node.name}() requires string, got ${jsonqTypeOf(val)}`);
            evalStream(args[0], val, vars, fns, depth, p => {
                if (typeof p !== "string") throw new Error(`jq runtime error: ${node.name}() argument must be string`);
                if (node.name === "startswith") emit(val.startsWith(p));
                else if (node.name === "endswith") emit(val.endsWith(p));
                else if (node.name === "ltrimstr") emit(val.startsWith(p) ? val.slice(p.length) : val);
                else emit(val.endsWith(p) ? val.slice(0, val.length - p.length) : val);
            });
            return;
        case "contains":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, o => emit(jsonqJqContains(val, o)));
            return;
        case "inside":
            checkArity(node, 1);
            evalStream(args[0], val, vars, fns, depth, o => emit(jsonqJqContains(o, val)));
            return;
        case "floor":
        case "ceil":
        case "round":
        case "sqrt":
        case "log":
        case "log2":
        case "log10":
        case "exp":
        case "exp10":
        case "fabs":
        case "trunc": {
            checkArity(node, 0);
            if (typeof val !== "number")
                throw new Error(`jq runtime error: ${node.name}() requires number, got ${jsonqTypeOf(val)}`);
            let res;
            switch (node.name) {
            case "floor": res = Math.floor(val); break;
            case "ceil": res = Math.ceil(val); break;
            case "round": res = val < 0 ? -Math.round(-val) : Math.round(val); break;
            case "sqrt": res = Math.sqrt(val); break;
            case "log": res = Math.log(val); break;
            case "log2": res = typeof Math.log2 === "function" ? Math.log2(val) : Math.log(val) / Math.LN2; break;
            case "log10": res = typeof Math.log10 === "function" ? Math.log10(val) : Math.log(val) / Math.LN10; break;
            case "exp": res = Math.exp(val); break;
            case "exp10": res = Math.pow(10, val); break;
            case "fabs": res = Math.abs(val); break;
            case "trunc": res = Math.trunc(val); break;
            }
            emit(res);
            return;
        }
        case "pow": {
            checkArity(node, 2);
            const bases = evalCollect(args[0], val, vars, fns, depth);
            const exps = evalCollect(args[1], val, vars, fns, depth);
            for (let j = 0; j < exps.length; j++) {
                for (let i = 0; i < bases.length; i++) {
                    if (typeof bases[i] !== "number" || typeof exps[j] !== "number")
                        throw new Error(`jq runtime error: pow() requires number arguments, got ${jsonqTypeOf(bases[i])} and ${jsonqTypeOf(exps[j])}`);
                    emit(Math.pow(bases[i], exps[j]));
                }
            }
            return;
        }
        case "infinite":
            checkArity(node, 0);
            emit(Infinity);
            return;
        case "nan":
            checkArity(node, 0);
            emit(NaN);
            return;
        case "isinfinite":
            checkArity(node, 0);
            emit(val === Infinity || val === -Infinity);
            return;
        case "isnan":
            checkArity(node, 0);
            emit(typeof val === "number" && isNaN(val));
            return;
        case "isnormal":
            checkArity(node, 0);
            emit(typeof val === "number" && isFinite(val) && val !== 0 && Math.abs(val) >= 2.2250738585072014e-308);
            return;
        case "INDEX": {
            checkArity(node, 1, 2);
            const obj = {};
            if (args.length === 1) {
                if (Array.isArray(val)) {
                    for (let i = 0; i < val.length; i++) {
                        evalStream(args[0], val[i], vars, fns, depth, k => {
                            obj[toStr(k)] = val[i];
                        });
                    }
                } else if (jsonqIsPlainObject(val)) {
                    const keys = Object.keys(val);
                    for (let i = 0; i < keys.length; i++) {
                        const row = val[keys[i]];
                        evalStream(args[0], row, vars, fns, depth, k => {
                            obj[toStr(k)] = row;
                        });
                    }
                } else {
                    throw new Error(`jq runtime error: cannot iterate over ${jsonqTypeOf(val)} in INDEX()`);
                }
            } else {
                evalStream(args[0], val, vars, fns, depth, row => {
                    evalStream(args[1], row, vars, fns, depth, k => {
                        obj[toStr(k)] = row;
                    });
                });
            }
            emit(obj);
            return;
        }
        case "IN": {
            checkArity(node, 1, 2);
            const stop = { __jsonqStop: true };
            let found = false;
            try {
                if (args.length === 1) {
                    evalStream(args[0], val, vars, fns, depth, item => {
                        if (jsonqDeepEqual(val, item)) {
                            found = true;
                            throw stop;
                        }
                    });
                } else {
                    evalStream(args[1], val, vars, fns, depth, target => {
                        evalStream(args[0], val, vars, fns, depth, item => {
                            if (jsonqDeepEqual(item, target)) {
                                found = true;
                                throw stop;
                            }
                        });
                    });
                }
            } catch (e) {
                if (e !== stop) throw e;
            }
            emit(found);
            return;
        }
        case "error": {
            checkArity(node, 0, 1);
            if (args.length === 0) {
                const err = new Error(val === null ? "jq runtime error" : `jq error: ${toStr(val)}`);
                err.jqVal = val === null ? null : toStr(val);
                throw err;
            }
            const msgs = evalCollect(args[0], val, vars, fns, depth);
            const msg = msgs.length > 0 ? toStr(msgs[0]) : "error";
            const err = new Error(`jq error: ${msg}`);
            err.jqVal = msg;
            throw err;
        }
        default:
            throw new Error(`jq parse error at column ${(node.pos || 0) + 1}: unknown function '${node.name}/${args.length}'`);
        }
    }

    return evalCollect(ast, input, env || {}, {}, 0);
}

function jsonqTool(input = "", options = {}) {
    const text = String(input);
    if (text.trim().length === 0)
        return { output: "" };

    let data;
    try {
        data = JSON.parse(text);
    } catch (err) {
        return { output: "", error: "Invalid JSON: expected a valid JSON value (object, array, string, number, boolean, or null)." };
    }

    const query = options.query === undefined ? "." : String(options.query);
    const trimmedQuery = query.trim();
    if (trimmedQuery.length === 0)
        return { output: "", error: "Enter a JSONPath ($...) or jq expression in the Query option." };

    const requestedSyntax = String(options.syntax || "auto");
    let useJsonPath;
    if (requestedSyntax === "jsonpath") useJsonPath = true;
    else if (requestedSyntax === "jq") useJsonPath = false;
    else useJsonPath = /^\$(?:\s*(?:\.\.?|\[)|$)/.test(trimmedQuery);

    let results;
    try {
        if (useJsonPath) {
            const ast = jsonqJpParse(trimmedQuery);
            results = jsonqJpEval(ast, data);
        } else {
            const ast = jsonqJqParse(query, 0);
            results = jsonqJqEval(ast, data, {});
        }
    } catch (err) {
        return { output: "", error: err.message };
    }

    const asArray = Boolean(options.asArray);
    const output = asArray
        ? jsonqSafeStringify(results, 2)
        : results.map(r => jsonqSafeStringify(r, 2)).join("\n");

    return {
        output: output,
        meta: {
            results: results.length,
            syntax: useJsonPath ? "JSONPath" : "jq"
        }
    };
}
// @slot-end json_query

// @slot-begin json_types
const JTYPES_TARGET_NAMES = {
    typescript: "TypeScript",
    zod: "Zod",
    python: "Python",
    go: "Go",
    rust: "Rust",
    jsonschema: "JSON Schema"
};

const JTYPES_GO_INITIALISMS = {
    id: "ID",
    ids: "IDs",
    url: "URL",
    urls: "URLs",
    http: "HTTP",
    https: "HTTPS",
    api: "API",
    apis: "APIs",
    json: "JSON",
    xml: "XML",
    sql: "SQL",
    uuid: "UUID",
    uuids: "UUIDs",
    ip: "IP",
    ips: "IPs",
    html: "HTML",
    css: "CSS",
    ui: "UI",
    tcp: "TCP",
    udp: "UDP",
    dns: "DNS",
    eof: "EOF",
    os: "OS",
    ok: "OK"
};

const JTYPES_PY_KEYWORDS = {
    False: true, None: true, True: true, and: true, as: true, assert: true,
    async: true, await: true, break: true, class: true, continue: true,
    def: true, del: true, elif: true, else: true, except: true, finally: true,
    for: true, from: true, global: true, if: true, import: true, in: true,
    is: true, lambda: true, nonlocal: true, not: true, or: true, pass: true,
    raise: true, return: true, try: true, while: true, with: true, yield: true
};

const JTYPES_RUST_KEYWORDS = {
    as: true, async: true, await: true, break: true, const: true, continue: true,
    crate: true, dyn: true, else: true, enum: true, extern: true, false: true,
    fn: true, for: true, if: true, impl: true, in: true, let: true, loop: true,
    match: true, mod: true, move: true, mut: true, pub: true, ref: true,
    return: true, self: true, Self: true, static: true, struct: true,
    super: true, trait: true, true: true, type: true, unsafe: true, use: true,
    where: true, while: true, abstract: true, become: true, box: true, do: true,
    final: true, macro: true, override: true, priv: true, try: true,
    typeof: true, unsized: true, virtual: true, yield: true
};

const JTYPES_IRREGULAR_SINGULARS = {
    people: "person",
    children: "child",
    men: "man",
    women: "woman",
    mice: "mouse",
    geese: "goose",
    teeth: "tooth",
    feet: "foot",
    oxen: "ox",
    indices: "index",
    matrices: "matrix",
    vertices: "vertex",
    statuses: "status",
    aliases: "alias",
    quizzes: "quiz"
};

const JTYPES_UNCOUNTABLE = {
    data: true,
    info: true,
    media: true,
    metadata: true,
    news: true,
    series: true,
    species: true,
    status: true,
    canvas: true,
    alias: true
};

function jtypesSplitWords(raw) {
    const parts = String(raw || "").split(/[^A-Za-z0-9]+/);
    const words = [];
    for (let i = 0; i < parts.length; i++) {
        const seg = parts[i];
        if (!seg) continue;
        const spaced = seg
            .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
            .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2");
        const sub = spaced.split(" ");
        for (let j = 0; j < sub.length; j++) {
            if (sub[j]) words.push(sub[j]);
        }
    }
    return words;
}

function jtypesSingularizeWord(word) {
    const lower = word.toLowerCase();
    if (Object.prototype.hasOwnProperty.call(JTYPES_IRREGULAR_SINGULARS, lower)) {
        return JTYPES_IRREGULAR_SINGULARS[lower];
    }
    if (Object.prototype.hasOwnProperty.call(JTYPES_UNCOUNTABLE, lower)) {
        return word;
    }
    if (/(?:ss|us|is)$/i.test(lower)) {
        return word;
    }
    if (word.length > 3 && /[^aeiou]ies$/i.test(lower)) {
        return word.slice(0, -3) + "y";
    }
    if (/(?:ss|x|z|ch|sh)es$/i.test(lower)) {
        return word.slice(0, -2);
    }
    if (/(?:lea|loa|shea|thie|wol|cal|hal|el|sel|shel)ves$/i.test(lower)) {
        return word.slice(0, -3) + "f";
    }
    if (/(?:kni|wi|li)ves$/i.test(lower)) {
        return word.slice(0, -3) + "fe";
    }
    if (word.length > 2 && /s$/i.test(lower)) {
        return word.slice(0, -1);
    }
    return word;
}

function jtypesToPascalCase(raw, goInitialisms, fallback) {
    const words = jtypesSplitWords(raw);
    if (words.length === 0) return fallback || "Root";
    let out = "";
    for (let i = 0; i < words.length; i++) {
        const w = words[i];
        const lower = w.toLowerCase();
        if (goInitialisms && Object.prototype.hasOwnProperty.call(JTYPES_GO_INITIALISMS, lower)) {
            out += JTYPES_GO_INITIALISMS[lower];
        } else {
            out += lower.charAt(0).toUpperCase() + lower.slice(1);
        }
    }
    if (/^[0-9]/.test(out)) out = "T" + out;
    return out || fallback || "Root";
}

function jtypesToSnakeCase(raw, keywordMap, fallback) {
    const words = jtypesSplitWords(raw);
    let out = words.map(w => w.toLowerCase()).join("_");
    if (!out) out = fallback || "field";
    if (/^[0-9]/.test(out)) out = "f_" + out;
    if (keywordMap && Object.prototype.hasOwnProperty.call(keywordMap, out)) {
        out += "_";
    }
    return out;
}

function jtypesArrayElementName(raw, goInitialisms) {
    const words = jtypesSplitWords(raw);
    if (words.length === 0) return "Item";
    const origPascal = jtypesToPascalCase(raw, goInitialisms, "Item");
    const last = words[words.length - 1];
    const singularLast = jtypesSingularizeWord(last);
    const nextWords = words.slice(0, -1);
    nextWords.push(singularLast);
    const singPascal = jtypesToPascalCase(nextWords.join(" "), goInitialisms, "Item");
    if (singPascal === origPascal) {
        return singPascal + "Item";
    }
    return singPascal;
}

function jtypesIsIsoDate(str) {
    if (str.length < 10 || str.length > 35) return false;
    const m = str.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?$/i);
    if (!m) return false;
    const month = parseInt(m[2], 10);
    const day = parseInt(m[3], 10);
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    if (m[4] !== undefined) {
        const hour = parseInt(m[4], 10);
        const min = parseInt(m[5], 10);
        const sec = m[6] !== undefined ? parseInt(m[6], 10) : 0;
        if (hour > 23 || min > 59 || sec > 59) return false;
    }
    return true;
}

function jtypesCreateSpec() {
    return {
        nullable: false,
        hasInt: false,
        hasFloat: false,
        hasString: false,
        allStringsIso: true,
        hasBoolean: false,
        hasArray: false,
        arrayElem: null,
        hasObject: false,
        objSamples: 0,
        fieldOrder: [],
        fields: Object.create(null),
        objectType: null
    };
}

function jtypesObserveValue(spec, val) {
    if (val === null) {
        spec.nullable = true;
        return;
    }
    const t = typeof val;
    if (t === "boolean") {
        spec.hasBoolean = true;
    } else if (t === "number") {
        if (isFinite(val) && Math.floor(val) === val) {
            spec.hasInt = true;
        } else {
            spec.hasFloat = true;
        }
    } else if (t === "string") {
        spec.hasString = true;
        if (!jtypesIsIsoDate(val)) {
            spec.allStringsIso = false;
        }
    } else if (Array.isArray(val)) {
        spec.hasArray = true;
        if (val.length > 0) {
            if (!spec.arrayElem) spec.arrayElem = jtypesCreateSpec();
            for (let i = 0; i < val.length; i++) {
                jtypesObserveValue(spec.arrayElem, val[i]);
            }
        }
    } else if (t === "object") {
        spec.hasObject = true;
        spec.objSamples += 1;
        const keys = Object.keys(val);
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i];
            if (!Object.prototype.hasOwnProperty.call(spec.fields, k)) {
                spec.fieldOrder.push(k);
                spec.fields[k] = { count: 0, spec: jtypesCreateSpec() };
            }
            spec.fields[k].count += 1;
            jtypesObserveValue(spec.fields[k].spec, val[k]);
        }
    }
}

function jtypesTypeSig(spec) {
    const parts = [];
    if (spec.hasInt && !spec.hasFloat) parts.push("int");
    if (spec.hasFloat) parts.push("float");
    if (spec.hasString) parts.push("str");
    if (spec.hasBoolean) parts.push("bool");
    if (spec.hasArray) {
        parts.push("arr(" + (spec.arrayElem ? jtypesTypeSig(spec.arrayElem) : "empty") + ")");
    }
    if (spec.hasObject && spec.objectType) {
        parts.push("obj(" + spec.objectType.name + ")");
    }
    if (spec.nullable) parts.push("null");
    return parts.join("|");
}

function jtypesAllocateName(base, usedNames) {
    if (!Object.prototype.hasOwnProperty.call(usedNames, base)) {
        usedNames[base] = true;
        return base;
    }
    let idx = 2;
    while (Object.prototype.hasOwnProperty.call(usedNames, base + idx)) {
        idx += 1;
    }
    const candidate = base + idx;
    usedNames[candidate] = true;
    return candidate;
}

function jtypesBuildModel(rootSpec, rootNameRaw, goInitialisms) {
    const rootTypeName = jtypesToPascalCase(rootNameRaw || "Root", goInitialisms, "Root");
    const usedNames = Object.create(null);
    usedNames[rootTypeName] = true;
    const shapeRegistry = Object.create(null);
    const orderedTypes = [];

    function finalizeSpec(spec, suggestedName, isRoot) {
        if (spec.hasArray && spec.arrayElem !== null) {
            finalizeSpec(spec.arrayElem, jtypesArrayElementName(suggestedName, goInitialisms), false);
        }
        if (spec.hasObject) {
            for (let i = 0; i < spec.fieldOrder.length; i++) {
                const key = spec.fieldOrder[i];
                finalizeSpec(spec.fields[key].spec, jtypesToPascalCase(key, goInitialisms, "Nested"), false);
            }
            const sortedKeys = spec.fieldOrder.slice().sort();
            const sigParts = [];
            for (let i = 0; i < sortedKeys.length; i++) {
                const k = sortedKeys[i];
                const entry = spec.fields[k];
                const optional = entry.count < spec.objSamples;
                sigParts.push(JSON.stringify(k) + (optional ? "?:" : ":") + jtypesTypeSig(entry.spec));
            }
            const sig = "{" + sigParts.join(",") + "}";
            if (!isRoot && Object.prototype.hasOwnProperty.call(shapeRegistry, sig)) {
                spec.objectType = shapeRegistry[sig];
                return;
            }
            const name = isRoot
                ? rootTypeName
                : jtypesAllocateName(jtypesToPascalCase(suggestedName, goInitialisms, "Item"), usedNames);
            const fields = [];
            for (let i = 0; i < spec.fieldOrder.length; i++) {
                const k = spec.fieldOrder[i];
                const entry = spec.fields[k];
                fields.push({
                    key: k,
                    optional: entry.count < spec.objSamples,
                    spec: entry.spec
                });
            }
            const typeDef = { name: name, isRoot: isRoot, fields: fields, signature: sig };
            if (!isRoot) {
                shapeRegistry[sig] = typeDef;
            }
            orderedTypes.push(typeDef);
            spec.objectType = typeDef;
        }
    }

    finalizeSpec(rootSpec, rootTypeName, true);
    return {
        rootTypeName: rootTypeName,
        rootSpec: rootSpec,
        orderedTypes: orderedTypes
    };
}

function jtypesIsValidTsIdent(key) {
    return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key);
}

function jtypesTsFormatKey(key) {
    return jtypesIsValidTsIdent(key) ? key : JSON.stringify(key);
}

function jtypesSpecAnnotations(spec) {
    const notes = [];
    if (spec.hasString && spec.allStringsIso) notes.push("ISO date");
    if (spec.hasArray && spec.arrayElem === null) notes.push("empty array");
    return notes;
}

function jtypesEmitTypeScript(model) {
    function renderSpec(spec) {
        const parts = [];
        if (spec.hasInt || spec.hasFloat) parts.push("number");
        if (spec.hasString) parts.push("string");
        if (spec.hasBoolean) parts.push("boolean");
        if (spec.hasArray) {
            if (spec.arrayElem === null) {
                parts.push("unknown[]");
            } else {
                const elem = renderSpec(spec.arrayElem);
                parts.push(elem.isUnion ? "(" + elem.code + ")[]" : elem.code + "[]");
            }
        }
        if (spec.hasObject && spec.objectType) {
            parts.push(spec.objectType.name);
        }
        if (spec.nullable) {
            if (parts.length === 0) parts.push("unknown");
            parts.push("null");
        }
        if (parts.length === 0) parts.push("unknown");
        return {
            code: parts.join(" | "),
            isUnion: parts.length > 1
        };
    }

    const blocks = [];
    for (let i = 0; i < model.orderedTypes.length; i++) {
        const t = model.orderedTypes[i];
        if (t.fields.length === 0) {
            blocks.push("export interface " + t.name + " {}");
            continue;
        }
        const lines = ["export interface " + t.name + " {"];
        for (let j = 0; j < t.fields.length; j++) {
            const f = t.fields[j];
            const rendered = renderSpec(f.spec);
            const notes = jtypesSpecAnnotations(f.spec);
            const comment = notes.length > 0 ? " // " + notes.join("; ") : "";
            lines.push("  " + jtypesTsFormatKey(f.key) + (f.optional ? "?: " : ": ") + rendered.code + ";" + comment);
        }
        lines.push("}");
        blocks.push(lines.join("\n"));
    }

    let typesCount = model.orderedTypes.length;
    if (!model.rootSpec.hasObject || !model.rootSpec.objectType || !model.rootSpec.objectType.isRoot) {
        const rootRendered = renderSpec(model.rootSpec);
        const notes = jtypesSpecAnnotations(model.rootSpec);
        const comment = notes.length > 0 ? " // " + notes.join("; ") : "";
        blocks.push("export type " + model.rootTypeName + " = " + rootRendered.code + ";" + comment);
        typesCount += 1;
    }

    return { output: blocks.join("\n\n"), typesCount: typesCount };
}

function jtypesEmitZod(model) {
    function renderSpec(spec) {
        const parts = [];
        if (spec.hasFloat) {
            parts.push("z.number()");
        } else if (spec.hasInt) {
            parts.push("z.number().int()");
        }
        if (spec.hasString) parts.push("z.string()");
        if (spec.hasBoolean) parts.push("z.boolean()");
        if (spec.hasArray) {
            if (spec.arrayElem === null) {
                parts.push("z.array(z.unknown())");
            } else {
                parts.push("z.array(" + renderSpec(spec.arrayElem) + ")");
            }
        }
        if (spec.hasObject && spec.objectType) {
            parts.push(spec.objectType.name + "Schema");
        }

        let expr;
        if (parts.length === 0) {
            expr = spec.nullable ? "z.unknown().nullable()" : "z.unknown()";
        } else {
            expr = parts.length === 1 ? parts[0] : "z.union([" + parts.join(", ") + "])";
            if (spec.nullable) expr += ".nullable()";
        }
        return expr;
    }

    const blocks = ["import { z } from \"zod\";"];
    for (let i = 0; i < model.orderedTypes.length; i++) {
        const t = model.orderedTypes[i];
        const schemaName = t.name + "Schema";
        const lines = [];
        if (t.fields.length === 0) {
            lines.push("export const " + schemaName + " = z.object({});");
        } else {
            lines.push("export const " + schemaName + " = z.object({");
            for (let j = 0; j < t.fields.length; j++) {
                const f = t.fields[j];
                let expr = renderSpec(f.spec);
                if (f.optional) expr += ".optional()";
                const notes = jtypesSpecAnnotations(f.spec);
                const comment = notes.length > 0 ? " // " + notes.join("; ") : "";
                lines.push("  " + jtypesTsFormatKey(f.key) + ": " + expr + "," + comment);
            }
            lines.push("});");
        }
        lines.push("export type " + t.name + " = z.infer<typeof " + schemaName + ">;");
        blocks.push(lines.join("\n"));
    }

    let typesCount = model.orderedTypes.length;
    if (!model.rootSpec.hasObject || !model.rootSpec.objectType || !model.rootSpec.objectType.isRoot) {
        const schemaName = model.rootTypeName + "Schema";
        const notes = jtypesSpecAnnotations(model.rootSpec);
        const comment = notes.length > 0 ? " // " + notes.join("; ") : "";
        blocks.push(
            "export const " + schemaName + " = " + renderSpec(model.rootSpec) + ";" + comment + "\n" +
            "export type " + model.rootTypeName + " = z.infer<typeof " + schemaName + ">;"
        );
        typesCount += 1;
    }

    return { output: blocks.join("\n\n"), typesCount: typesCount };
}

function jtypesEmitPython(model) {
    const usedTyping = { Any: false, Optional: false, Union: false };

    function renderSpec(spec) {
        const parts = [];
        if (spec.hasFloat) {
            parts.push("float");
        } else if (spec.hasInt) {
            parts.push("int");
        }
        if (spec.hasString) parts.push("str");
        if (spec.hasBoolean) parts.push("bool");
        if (spec.hasArray) {
            if (spec.arrayElem === null) {
                usedTyping.Any = true;
                parts.push("list[Any]");
            } else {
                parts.push("list[" + renderSpec(spec.arrayElem).type + "]");
            }
        }
        if (spec.hasObject && spec.objectType) {
            parts.push(spec.objectType.name);
        }

        if (parts.length === 0) {
            usedTyping.Any = true;
            if (spec.nullable) {
                usedTyping.Optional = true;
                return { type: "Optional[Any]", isOptionalWrapped: true };
            }
            return { type: "Any", isOptionalWrapped: false };
        }
        let base;
        if (parts.length === 1) {
            base = parts[0];
        } else {
            usedTyping.Union = true;
            base = "Union[" + parts.join(", ") + "]";
        }
        if (spec.nullable) {
            usedTyping.Optional = true;
            return { type: "Optional[" + base + "]", isOptionalWrapped: true };
        }
        return { type: base, isOptionalWrapped: false };
    }

    const classBlocks = [];
    for (let i = 0; i < model.orderedTypes.length; i++) {
        const t = model.orderedTypes[i];
        const lines = ["@dataclass", "class " + t.name + ":"];
        if (t.fields.length === 0) {
            lines.push("    pass");
            classBlocks.push(lines.join("\n"));
            continue;
        }
        const usedFieldNames = Object.create(null);
        const requiredLines = [];
        const optionalLines = [];
        for (let j = 0; j < t.fields.length; j++) {
            const f = t.fields[j];
            const basePyName = jtypesToSnakeCase(f.key, JTYPES_PY_KEYWORDS, "field");
            const pyName = jtypesAllocateName(basePyName, usedFieldNames);
            const rendered = renderSpec(f.spec);
            let typeStr = rendered.type;
            let suffix = "";
            if (f.optional) {
                if (!rendered.isOptionalWrapped) {
                    usedTyping.Optional = true;
                    typeStr = "Optional[" + typeStr + "]";
                }
                suffix = " = None";
            }
            const notes = [];
            if (pyName !== f.key) notes.push("json: " + JSON.stringify(f.key));
            if (f.spec.hasArray && f.spec.arrayElem === null) notes.push("empty array");
            const comment = notes.length > 0 ? "  # " + notes.join("; ") : "";
            const line = "    " + pyName + ": " + typeStr + suffix + comment;
            if (f.optional) {
                optionalLines.push(line);
            } else {
                requiredLines.push(line);
            }
        }
        for (let r = 0; r < requiredLines.length; r++) lines.push(requiredLines[r]);
        for (let o = 0; o < optionalLines.length; o++) lines.push(optionalLines[o]);
        classBlocks.push(lines.join("\n"));
    }

    let typesCount = model.orderedTypes.length;
    let aliasBlock = null;
    if (!model.rootSpec.hasObject || !model.rootSpec.objectType || !model.rootSpec.objectType.isRoot) {
        const rendered = renderSpec(model.rootSpec);
        const comment = (model.rootSpec.hasArray && model.rootSpec.arrayElem === null) ? "  # empty array" : "";
        aliasBlock = model.rootTypeName + " = " + rendered.type + comment;
        typesCount += 1;
    }

    const importLines = [];
    if (model.orderedTypes.length > 0) {
        importLines.push("from dataclasses import dataclass");
    }
    const typingNames = ["Any", "Optional", "Union"].filter(name => usedTyping[name]);
    if (typingNames.length > 0) {
        importLines.push("from typing import " + typingNames.join(", "));
    }

    const sections = [];
    if (importLines.length > 0) sections.push(importLines.join("\n"));
    for (let i = 0; i < classBlocks.length; i++) sections.push(classBlocks[i]);
    if (aliasBlock !== null) sections.push(aliasBlock);

    return { output: sections.join("\n\n"), typesCount: typesCount };
}

function jtypesGoTag(key, omitempty) {
    const suffix = omitempty ? ",omitempty" : "";
    const escaped = String(key)
        .replace(/\\/g, "\\\\")
        .replace(/"/g, "\\\"")
        .replace(/\n/g, "\\n")
        .replace(/\r/g, "\\r")
        .replace(/\t/g, "\\t")
        .replace(/[\x00-\x1f\x7f]/g, ch => "\\u00" + ("0" + ch.charCodeAt(0).toString(16)).slice(-2));
    const inner = "json:\"" + escaped + suffix + "\"";
    if (inner.indexOf("`") !== -1) {
        return JSON.stringify(inner);
    }
    return "`" + inner + "`";
}

function jtypesEmitGo(model) {
    function renderSpec(spec, optional) {
        const kinds = [];
        if (spec.hasFloat) kinds.push("float64");
        else if (spec.hasInt) kinds.push("int64");
        if (spec.hasString) kinds.push("string");
        if (spec.hasBoolean) kinds.push("bool");
        const notes = [];
        if (spec.hasArray) {
            if (spec.arrayElem === null) {
                kinds.push("[]any");
                notes.push("empty array");
            } else {
                const elem = renderSpec(spec.arrayElem, false);
                kinds.push("[]" + elem.type);
                for (let n = 0; n < elem.notes.length; n++) {
                    notes.push(elem.notes[n]);
                }
            }
        }
        if (spec.hasObject && spec.objectType) {
            kinds.push(spec.objectType.name);
        }

        let baseType;
        let canPointer = false;
        if (kinds.length === 0) {
            baseType = "any";
            if (spec.nullable) notes.push("null only");
        } else if (kinds.length > 1) {
            baseType = "any";
            notes.push("mixed: " + kinds.join(" | "));
        } else {
            baseType = kinds[0];
            canPointer = baseType !== "any" && baseType.indexOf("[]") !== 0;
        }

        const usePointer = canPointer && (spec.nullable || optional);
        return {
            type: (usePointer ? "*" : "") + baseType,
            notes: notes
        };
    }

    const blocks = [];
    for (let i = 0; i < model.orderedTypes.length; i++) {
        const t = model.orderedTypes[i];
        if (t.fields.length === 0) {
            blocks.push("type " + t.name + " struct{}");
            continue;
        }
        const usedFieldNames = Object.create(null);
        const rows = [];
        let maxName = 0;
        let maxType = 0;
        for (let j = 0; j < t.fields.length; j++) {
            const f = t.fields[j];
            const baseGoName = jtypesToPascalCase(f.key, true, "Field");
            const goName = jtypesAllocateName(baseGoName, usedFieldNames);
            const rendered = renderSpec(f.spec, f.optional);
            const tag = jtypesGoTag(f.key, f.optional);
            if (goName.length > maxName) maxName = goName.length;
            if (rendered.type.length > maxType) maxType = rendered.type.length;
            rows.push({
                name: goName,
                type: rendered.type,
                tag: tag,
                notes: rendered.notes
            });
        }
        const lines = ["type " + t.name + " struct {"];
        const tagPad = new Array(rows.length);
        let idx = 0;
        while (idx < rows.length) {
            if (rows[idx].notes.length === 0) {
                tagPad[idx] = 0;
                idx += 1;
                continue;
            }
            let end = idx;
            let maxTag = 0;
            while (end < rows.length && rows[end].notes.length > 0) {
                if (rows[end].tag.length > maxTag) maxTag = rows[end].tag.length;
                end += 1;
            }
            for (let k = idx; k < end; k++) {
                tagPad[k] = maxTag - rows[k].tag.length + 1;
            }
            idx = end;
        }
        for (let j = 0; j < rows.length; j++) {
            const r = rows[j];
            const comment = r.notes.length > 0
                ? " ".repeat(tagPad[j]) + "// " + r.notes.join("; ")
                : "";
            lines.push(
                "\t" +
                r.name + " ".repeat(maxName - r.name.length + 1) +
                r.type + " ".repeat(maxType - r.type.length + 1) +
                r.tag + comment
            );
        }
        lines.push("}");
        blocks.push(lines.join("\n"));
    }

    let typesCount = model.orderedTypes.length;
    if (!model.rootSpec.hasObject || !model.rootSpec.objectType || !model.rootSpec.objectType.isRoot) {
        const rendered = renderSpec(model.rootSpec, false);
        const comment = rendered.notes.length > 0 ? " // " + rendered.notes.join("; ") : "";
        blocks.push("type " + model.rootTypeName + " " + rendered.type + comment);
        typesCount += 1;
    }

    return { output: blocks.join("\n\n"), typesCount: typesCount };
}

function jtypesEmitRust(model) {
    function renderSpec(spec, optional) {
        const kinds = [];
        if (spec.hasFloat) kinds.push("f64");
        else if (spec.hasInt) kinds.push("i64");
        if (spec.hasString) kinds.push("String");
        if (spec.hasBoolean) kinds.push("bool");
        const notes = [];
        if (spec.hasArray) {
            if (spec.arrayElem === null) {
                kinds.push("Vec<serde_json::Value>");
                notes.push("empty array");
            } else {
                const elem = renderSpec(spec.arrayElem, false);
                kinds.push("Vec<" + elem.type + ">");
                for (let n = 0; n < elem.notes.length; n++) {
                    notes.push(elem.notes[n]);
                }
            }
        }
        if (spec.hasObject && spec.objectType) {
            kinds.push(spec.objectType.name);
        }

        let baseType;
        if (kinds.length === 0) {
            baseType = "serde_json::Value";
        } else if (kinds.length > 1) {
            baseType = "serde_json::Value";
            notes.push("mixed: " + kinds.join(" | "));
        } else {
            baseType = kinds[0];
        }

        const isOption = spec.nullable || optional;
        return {
            type: isOption ? "Option<" + baseType + ">" : baseType,
            notes: notes
        };
    }

    const blocks = [];
    if (model.orderedTypes.length > 0) {
        blocks.push("use serde::{Deserialize, Serialize};");
    }

    for (let i = 0; i < model.orderedTypes.length; i++) {
        const t = model.orderedTypes[i];
        const lines = ["#[derive(Debug, Clone, Serialize, Deserialize)]"];
        if (t.fields.length === 0) {
            lines.push("pub struct " + t.name + " {}");
            blocks.push(lines.join("\n"));
            continue;
        }
        lines.push("pub struct " + t.name + " {");
        const usedFieldNames = Object.create(null);
        for (let j = 0; j < t.fields.length; j++) {
            const f = t.fields[j];
            const baseRustName = jtypesToSnakeCase(f.key, JTYPES_RUST_KEYWORDS, "field");
            const rustName = jtypesAllocateName(baseRustName, usedFieldNames);
            if (rustName !== f.key) {
                lines.push("    #[serde(rename = " + JSON.stringify(f.key) + ")]");
            }
            const rendered = renderSpec(f.spec, f.optional);
            const comment = rendered.notes.length > 0 ? " // " + rendered.notes.join("; ") : "";
            lines.push("    pub " + rustName + ": " + rendered.type + "," + comment);
        }
        lines.push("}");
        blocks.push(lines.join("\n"));
    }

    let typesCount = model.orderedTypes.length;
    if (!model.rootSpec.hasObject || !model.rootSpec.objectType || !model.rootSpec.objectType.isRoot) {
        const rendered = renderSpec(model.rootSpec, false);
        const comment = rendered.notes.length > 0 ? " // " + rendered.notes.join("; ") : "";
        blocks.push("pub type " + model.rootTypeName + " = " + rendered.type + ";" + comment);
        typesCount += 1;
    }

    return { output: blocks.join("\n\n"), typesCount: typesCount };
}

function jtypesEmitJsonSchema(model) {
    function buildSpecSchema(spec) {
        const primTypes = [];
        if (spec.hasFloat) primTypes.push("number");
        else if (spec.hasInt) primTypes.push("integer");
        if (spec.hasString) primTypes.push("string");
        if (spec.hasBoolean) primTypes.push("boolean");

        const complexSchemas = [];
        if (spec.hasArray) {
            if (spec.arrayElem === null) {
                complexSchemas.push({ type: "array", items: {}, $comment: "empty array" });
            } else {
                complexSchemas.push({ type: "array", items: buildSpecSchema(spec.arrayElem) });
            }
        }
        if (spec.hasObject && spec.objectType) {
            complexSchemas.push({ $ref: "#/$defs/" + spec.objectType.name });
        }

        if (complexSchemas.length === 0) {
            if (primTypes.length === 0) {
                return spec.nullable ? { type: "null" } : {};
            }
            if (spec.nullable) primTypes.push("null");
            return { type: primTypes.length === 1 ? primTypes[0] : primTypes };
        }

        if (primTypes.length === 0 && complexSchemas.length === 1 && !spec.nullable) {
            return complexSchemas[0];
        }

        const branches = [];
        for (let i = 0; i < primTypes.length; i++) {
            branches.push({ type: primTypes[i] });
        }
        for (let i = 0; i < complexSchemas.length; i++) {
            branches.push(complexSchemas[i]);
        }
        if (spec.nullable) {
            branches.push({ type: "null" });
        }
        return { anyOf: branches };
    }

    function buildObjectBody(typeDef) {
        const props = {};
        const required = [];
        for (let i = 0; i < typeDef.fields.length; i++) {
            const f = typeDef.fields[i];
            props[f.key] = buildSpecSchema(f.spec);
            if (!f.optional) required.push(f.key);
        }
        const obj = {
            type: "object",
            properties: props
        };
        if (required.length > 0) {
            obj.required = required;
        }
        obj.additionalProperties = false;
        return obj;
    }

    const rootObj = {
        $schema: "https://json-schema.org/draft/2020-12/schema",
        title: model.rootTypeName
    };
    const defs = {};
    let defsCount = 0;

    for (let i = 0; i < model.orderedTypes.length; i++) {
        const t = model.orderedTypes[i];
        if (t.isRoot) {
            const body = buildObjectBody(t);
            rootObj.type = body.type;
            rootObj.properties = body.properties;
            if (body.required) rootObj.required = body.required;
            rootObj.additionalProperties = body.additionalProperties;
        } else {
            defs[t.name] = buildObjectBody(t);
            defsCount += 1;
        }
    }

    if (!model.rootSpec.hasObject || !model.rootSpec.objectType || !model.rootSpec.objectType.isRoot) {
        const rootBody = buildSpecSchema(model.rootSpec);
        const keys = Object.keys(rootBody);
        for (let i = 0; i < keys.length; i++) {
            rootObj[keys[i]] = rootBody[keys[i]];
        }
    }

    if (defsCount > 0) {
        rootObj.$defs = defs;
    }

    return {
        output: JSON.stringify(rootObj, null, 2),
        typesCount: 1 + defsCount
    };
}

function toolJsonTypes(input = "", options = {}) {
    const text = String(input).trim();
    if (text.length === 0) {
        return { output: "" };
    }

    const target = String(options.target || "typescript");
    if (!Object.prototype.hasOwnProperty.call(JTYPES_TARGET_NAMES, target)) {
        return { output: "", error: "Unsupported target: " + target };
    }

    let parsed;
    try {
        parsed = JSON.parse(text);
    } catch (err) {
        return { output: "", error: "Invalid JSON: expected a valid JSON object or array" };
    }

    if (parsed === null || typeof parsed !== "object") {
        return { output: "", error: "Expected a JSON object or array at root" };
    }

    const rootSpec = jtypesCreateSpec();
    jtypesObserveValue(rootSpec, parsed);

    const rootNameRaw = options.rootName !== undefined ? String(options.rootName).trim() : "Root";
    const model = jtypesBuildModel(rootSpec, rootNameRaw || "Root", target === "go");

    let result;
    switch (target) {
    case "typescript":
        result = jtypesEmitTypeScript(model);
        break;
    case "zod":
        result = jtypesEmitZod(model);
        break;
    case "python":
        result = jtypesEmitPython(model);
        break;
    case "go":
        result = jtypesEmitGo(model);
        break;
    case "rust":
        result = jtypesEmitRust(model);
        break;
    case "jsonschema":
        result = jtypesEmitJsonSchema(model);
        break;
    }

    return {
        output: result.output,
        meta: {
            types: result.typesCount,
            target: JTYPES_TARGET_NAMES[target]
        }
    };
}
// @slot-end json_types

// @slot-begin glob_tester
function globtEscapeRegexChar(ch) {
    return /[\\^$.*+?()[\]{}|]/.test(ch) ? "\\" + ch : ch;
}

function globtStripTrailingSpaces(line) {
    let lastKeep = 0;
    for (let i = 0; i < line.length; i++) {
        if (line[i] === "\\" && i + 1 < line.length) {
            i++;
            lastKeep = i + 1;
        } else if (line[i] !== " ") {
            lastKeep = i + 1;
        }
    }
    return line.slice(0, lastKeep);
}

function globtFindClosingBracket(str, startIdx, lineNum) {
    let i = startIdx + 1;
    if (i < str.length && (str[i] === "!" || str[i] === "^"))
        i++;
    if (i < str.length && str[i] === "]")
        i++;
    while (i < str.length) {
        if (str[i] === "\\") {
            if (i + 1 >= str.length)
                throw new Error("Line " + lineNum + ": trailing backslash in pattern.");
            i += 2;
            continue;
        }
        if (str[i] === "]")
            return i;
        i++;
    }
    throw new Error("Line " + lineNum + ": unclosed '[' in pattern.");
}

function globtCompileCharClass(rawClass, lineNum) {
    let idx = 0;
    let negated = false;
    if (rawClass[0] === "!" || rawClass[0] === "^") {
        negated = true;
        idx = 1;
    }
    if (idx >= rawClass.length)
        throw new Error("Line " + lineNum + ": empty character class in pattern.");

    let body = "";
    let hasSlash = false;
    while (idx < rawClass.length) {
        const ch = rawClass[idx];
        if (ch === "\\") {
            const next = rawClass[idx + 1];
            if (next === "/")
                hasSlash = true;
            body += (next === "\\" || next === "]" || next === "-" || next === "^")
                ? "\\" + next
                : next;
            idx += 2;
        } else {
            if (ch === "/")
                hasSlash = true;
            if (ch === "]")
                body += "\\]";
            else if (ch === "^" && body.length === 0 && !negated)
                body += "\\^";
            else
                body += ch;
            idx++;
        }
    }
    if (negated && !hasSlash)
        body += "/";
    return "[" + (negated ? "^" : "") + body + "]";
}

function globtFindClosingBrace(str, startIdx, lineNum) {
    let i = startIdx + 1;
    let depth = 1;
    const parts = [];
    let partStart = i;
    while (i < str.length) {
        const ch = str[i];
        if (ch === "\\") {
            if (i + 1 >= str.length)
                throw new Error("Line " + lineNum + ": trailing backslash in pattern.");
            i += 2;
            continue;
        }
        if (ch === "[") {
            i = globtFindClosingBracket(str, i, lineNum) + 1;
            continue;
        }
        if (ch === "{") {
            depth++;
            i++;
            continue;
        }
        if (ch === "}") {
            depth--;
            if (depth === 0) {
                parts.push(str.slice(partStart, i));
                return { endIdx: i, parts };
            }
            i++;
            continue;
        }
        if (ch === "," && depth === 1) {
            parts.push(str.slice(partStart, i));
            partStart = i + 1;
        }
        i++;
    }
    throw new Error("Line " + lineNum + ": unclosed '{' in pattern.");
}

function globtCompileSegment(str, braces, lineNum, atSegmentStart) {
    let out = "";
    let i = 0;
    let segStart = atSegmentStart;
    while (i < str.length) {
        const ch = str[i];
        if (ch === "\\") {
            if (i + 1 >= str.length)
                throw new Error("Line " + lineNum + ": trailing backslash in pattern.");
            out += globtEscapeRegexChar(str[i + 1]);
            segStart = false;
            i += 2;
            continue;
        }
        if (ch === "[") {
            const endIdx = globtFindClosingBracket(str, i, lineNum);
            out += globtCompileCharClass(str.slice(i + 1, endIdx), lineNum);
            segStart = false;
            i = endIdx + 1;
            continue;
        }
        if (braces && ch === "{") {
            const info = globtFindClosingBrace(str, i, lineNum);
            if (info.parts.length >= 2) {
                const compiled = info.parts.map(part => globtCompileSegment(part, true, lineNum, segStart));
                out += "(?:" + compiled.join("|") + ")";
                segStart = info.parts.every(part => part.endsWith("/"));
            } else {
                out += "\\{" + globtCompileSegment(info.parts[0], true, lineNum, false) + "\\}";
                segStart = false;
            }
            i = info.endIdx + 1;
            continue;
        }
        if (ch === "*") {
            if (segStart && str[i + 1] === "*" && (i + 2 === str.length || str[i + 2] === "/")) {
                if (i + 2 < str.length && str[i + 2] === "/") {
                    let j = i + 3;
                    while (str.slice(j, j + 3) === "**/")
                        j += 3;
                    if (str.slice(j) === "**") {
                        out += (i > 0 && str[i - 1] === "/") ? ".+" : ".*";
                        i = str.length;
                        segStart = false;
                    } else {
                        out += "(?:.+/)?";
                        i = j;
                        segStart = true;
                    }
                } else {
                    out += (i > 0 && str[i - 1] === "/") ? ".+" : ".*";
                    i += 2;
                    segStart = false;
                }
                continue;
            }
            while (i < str.length && str[i] === "*")
                i++;
            out += "[^/]*";
            segStart = false;
            continue;
        }
        if (ch === "?") {
            out += "[^/]";
            segStart = false;
            i++;
            continue;
        }
        if (ch === "/") {
            out += "/";
            segStart = true;
            i++;
            continue;
        }
        out += globtEscapeRegexChar(ch);
        segStart = false;
        i++;
    }
    return out;
}

function globtCompilePattern(pattern, options = {}) {
    const mode = options.mode === "glob" ? "glob" : "gitignore";
    const lineNum = options.lineNum || 1;
    if (mode === "glob") {
        let body = String(pattern);
        let negated = false;
        if (body.startsWith("!")) {
            negated = true;
            body = body.slice(1);
            if (body.length === 0)
                throw new Error("Line " + lineNum + ": negated pattern '!' has no pattern.");
        }
        const core = globtCompileSegment(body, true, lineNum, true);
        const regexSource = "^" + core + "$";
        let regex;
        try {
            regex = new RegExp(regexSource);
        } catch (err) {
            throw new Error("Line " + lineNum + ": invalid pattern (" + err.message + ").");
        }
        return {
            line: lineNum,
            pattern: String(pattern),
            negated,
            dirOnly: false,
            anchored: true,
            regexSource,
            regex
        };
    }

    // gitignore(5) mode
    let body = globtStripTrailingSpaces(String(pattern));
    let negated = false;
    if (body.startsWith("!")) {
        negated = true;
        body = body.slice(1);
        if (body.length === 0)
            throw new Error("Line " + lineNum + ": negated pattern '!' has no pattern.");
    }
    let dirOnly = false;
    if (body.endsWith("/")) {
        dirOnly = true;
        body = body.replace(/\/+$/, "");
        if (body.length === 0)
            throw new Error("Line " + lineNum + ": pattern '/' has no path.");
    }
    const anchored = body.indexOf("/") !== -1;
    if (body.startsWith("/")) {
        body = body.replace(/^\/+/, "");
        if (body.length === 0)
            throw new Error("Line " + lineNum + ": pattern '/' has no path.");
    }
    const core = globtCompileSegment(body, false, lineNum, true);
    const regexSource = (anchored || core === ".*")
        ? "^" + core + "$"
        : "^(?:.+/)?" + core + "$";
    let regex;
    try {
        regex = new RegExp(regexSource);
    } catch (err) {
        throw new Error("Line " + lineNum + ": invalid pattern (" + err.message + ").");
    }
    return {
        line: lineNum,
        pattern: (negated ? "!" : "") + (anchored && String(pattern).replace(/^!?/, "").startsWith("/") ? "/" : "") + body + (dirOnly ? "/" : ""),
        displayPattern: globtStripTrailingSpaces(String(pattern)),
        negated,
        dirOnly,
        anchored,
        regexSource,
        regex
    };
}

function globtEvalGitignore(rules, rawPath) {
    const isDir = rawPath.endsWith("/");
    const cleanPath = rawPath.replace(/^(?:\.\/|\/)+/, "").replace(/\/+$/, "");
    if (cleanPath.length === 0)
        return { ignored: false, rule: null, viaParent: null };

    const parts = cleanPath.split("/");
    // gitignore(5): a file cannot be re-included if a parent directory is excluded.
    for (let k = 1; k < parts.length; k++) {
        const ancPath = parts.slice(0, k).join("/");
        let ancIgnored = false;
        let ancRule = null;
        for (let r = 0; r < rules.length; r++) {
            const rule = rules[r];
            if (rule.regex.test(ancPath)) {
                ancIgnored = !rule.negated;
                ancRule = rule;
            }
        }
        if (ancIgnored)
            return { ignored: true, rule: ancRule, viaParent: ancPath + "/" };
    }

    let ignored = false;
    let decidingRule = null;
    for (let r = 0; r < rules.length; r++) {
        const rule = rules[r];
        if (rule.dirOnly && !isDir)
            continue;
        if (rule.regex.test(cleanPath)) {
            ignored = !rule.negated;
            decidingRule = rule;
        }
    }
    return { ignored, rule: decidingRule, viaParent: null };
}

function globtEvalGlob(rules, rawPath, hasPositive) {
    let matched = !hasPositive;
    let decidingRule = null;
    const matchedRules = [];
    for (let r = 0; r < rules.length; r++) {
        const rule = rules[r];
        if (rule.regex.test(rawPath)) {
            matchedRules.push(rule);
            matched = !rule.negated;
            decidingRule = rule;
        }
    }
    return { matched, rule: decidingRule, matchedRules };
}

function globtTool(input = "", options = {}) {
    const text = String(input);
    if (text.trim().length === 0)
        return { output: "" };

    const mode = options.mode === "glob" ? "glob" : "gitignore";
    const lines = text.split(/\r?\n/);
    let splitIdx = -1;
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].trim() === "---") {
            splitIdx = i;
            break;
        }
    }
    if (splitIdx === -1)
        return { output: "", error: "Separate patterns and paths with a line containing only ---." };

    const patternLines = lines.slice(0, splitIdx);
    const pathLines = lines.slice(splitIdx + 1);
    if (patternLines.every(line => line.trim().length === 0))
        return { output: "", error: "Add at least one pattern before ---." };

    const paths = [];
    for (let i = 0; i < pathLines.length; i++) {
        if (pathLines[i].trim().length > 0)
            paths.push(pathLines[i]);
    }
    if (paths.length === 0)
        return { output: "", error: "Add at least one path after --- to test." };

    const rules = [];
    try {
        for (let i = 0; i < patternLines.length; i++) {
            const raw = patternLines[i];
            if (mode === "gitignore") {
                if (raw.startsWith("#"))
                    continue;
                const stripped = globtStripTrailingSpaces(raw);
                if (stripped.length === 0)
                    continue;
                rules.push(globtCompilePattern(raw, { mode: "gitignore", lineNum: i + 1 }));
            } else {
                const trimmed = raw.trim();
                if (trimmed.length === 0)
                    continue;
                rules.push(globtCompilePattern(trimmed, { mode: "glob", lineNum: i + 1 }));
            }
        }
    } catch (err) {
        return { output: "", error: err.message };
    }

    const maxLineW = 57;
    const out = [];
    out.push("Patterns (" + mode + ")");
    if (rules.length === 0) {
        out.push("  (no active patterns)");
    } else {
        const lineColW = Math.max(2, ...rules.map(r => ("#" + r.line).length));
        const patPrefixW = 2 + lineColW + 2;
        const patRows = rules.map(r => {
            const patText = r.displayPattern ?? r.pattern;
            const tags = [];
            if (r.dirOnly) tags.push("dir");
            if (r.negated) tags.push("negate");
            const suffix = tags.length > 0 ? " (" + tags.join(", ") + ")" : "";
            return {
                lineLabel: "#" + r.line,
                patText,
                rhs: r.regexSource + suffix
            };
        });
        const fitPatRows = patRows.filter(row => patPrefixW + row.patText.length + 2 + row.rhs.length <= maxLineW);
        const patColW = Math.min(22, Math.max(7, ...(fitPatRows.length > 0 ? fitPatRows : patRows).map(row => row.patText.length)));
        out.push("  " + "#".padEnd(lineColW) + "  " + "Pattern".padEnd(patColW) + "  Regex");
        for (let i = 0; i < patRows.length; i++) {
            const row = patRows[i];
            const head = "  " + row.lineLabel.padEnd(lineColW) + "  ";
            if (row.patText.length <= patColW && patPrefixW + patColW + 2 + row.rhs.length <= maxLineW) {
                out.push(head + row.patText.padEnd(patColW) + "  " + row.rhs);
            } else {
                out.push(head + row.patText);
                out.push(" ".repeat(patPrefixW) + row.rhs);
            }
        }
    }

    out.push("");
    out.push("Paths");
    let matchedCount = 0;
    const hasPositive = rules.some(r => !r.negated);
    const pathRows = [];

    for (let i = 0; i < paths.length; i++) {
        const p = paths[i];
        if (mode === "gitignore") {
            const res = globtEvalGitignore(rules, p);
            if (res.ignored)
                matchedCount++;
            const status = res.ignored ? "✓ ignored" : "· kept   ";
            let reason = "—";
            if (res.rule) {
                const patText = res.rule.displayPattern ?? res.rule.pattern;
                if (res.viaParent) {
                    reason = "#" + res.rule.line + (patText === res.viaParent
                        ? " via " + res.viaParent
                        : " " + patText + " (via " + res.viaParent + ")");
                } else {
                    reason = "#" + res.rule.line + " " + patText;
                }
            }
            pathRows.push({ status, path: p, reason });
        } else {
            const res = globtEvalGlob(rules, p, hasPositive);
            if (res.matched)
                matchedCount++;
            const status = res.matched ? "✓ match   " : "· no match";
            let reason = "—";
            if (res.rule) {
                reason = "#" + res.rule.line + " " + res.rule.pattern;
                const others = res.matchedRules.filter(r => r.line !== res.rule.line);
                if (others.length > 0)
                    reason += " (also: " + others.map(r => "#" + r.line).join(", ") + ")";
            } else if (res.matched && !hasPositive && rules.length > 0) {
                reason = "(passed negations)";
            }
            pathRows.push({ status, path: p, reason });
        }
    }

    const statusW = mode === "gitignore" ? 9 : 10;
    const pathPrefixW = 2 + statusW + 2;
    const fitPathRows = pathRows.filter(row => pathPrefixW + row.path.length + 2 + row.reason.length <= maxLineW);
    const pathColW = Math.min(22, Math.max(12, ...(fitPathRows.length > 0 ? fitPathRows : pathRows).map(row => row.path.length)));
    for (let i = 0; i < pathRows.length; i++) {
        const row = pathRows[i];
        const head = "  " + row.status + "  ";
        if (row.path.length <= pathColW && pathPrefixW + pathColW + 2 + row.reason.length <= maxLineW) {
            out.push(head + row.path.padEnd(pathColW) + "  " + row.reason);
        } else {
            out.push(head + row.path);
            out.push(" ".repeat(pathPrefixW) + row.reason);
        }
    }

    return {
        output: out.join("\n"),
        meta: {
            mode,
            matched: matchedCount + "/" + paths.length,
            patterns: rules.length
        }
    };
}
// @slot-end glob_tester

// @slot-begin semver_tool
const SEMV_MAX_SAFE = 9007199254740991;
const SEMV_STRICT_RE = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/;
const SEMV_LOOSE_RE = /^[=v\s]*(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.\d+)*(?:-((?:0|\d+|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|\d+|\d*[a-zA-Z-][0-9a-zA-Z-]*))*)|([a-zA-Z][0-9a-zA-Z-]*(?:\.(?:0|\d+|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/;
const SEMV_PRE_ID_RE = /^[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*$/;

function semvStripLeadingZeros(digits) {
    const stripped = digits.replace(/^0+/, "");
    return stripped.length > 0 ? stripped : "0";
}

function semvParsePreList(raw, loose) {
    if (!raw)
        return [];
    return raw.split(".").map(part => {
        if (/^\d+$/.test(part)) {
            const norm = loose ? semvStripLeadingZeros(part) : part;
            return { num: true, str: norm, val: norm.length <= 15 ? Number(norm) : -1 };
        }
        return { num: false, str: part, val: -1 };
    });
}

function semvFormatPreList(pre) {
    return pre.map(id => id.str).join(".");
}

function semvFormatVersion(v, includeBuild = true) {
    let out = v.major + "." + v.minor + "." + v.patch;
    if (v.prerelease.length > 0)
        out += "-" + semvFormatPreList(v.prerelease);
    if (includeBuild && v.build.length > 0)
        out += "+" + v.build.join(".");
    return out;
}

function semvParseVersion(raw, loose = false) {
    const text = String(raw || "").trim();
    if (!text || text.length > 256)
        return null;
    const match = text.match(loose ? SEMV_LOOSE_RE : SEMV_STRICT_RE);
    if (!match)
        return null;
    const majorStr = loose ? semvStripLeadingZeros(match[1]) : match[1];
    const minorStr = match[2] !== undefined ? (loose ? semvStripLeadingZeros(match[2]) : match[2]) : "0";
    const patchStr = match[3] !== undefined ? (loose ? semvStripLeadingZeros(match[3]) : match[3]) : "0";
    const major = Number(majorStr);
    const minor = Number(minorStr);
    const patch = Number(patchStr);
    if (!isFinite(major) || !isFinite(minor) || !isFinite(patch) ||
        major > SEMV_MAX_SAFE || minor > SEMV_MAX_SAFE || patch > SEMV_MAX_SAFE)
        return null;
    const preRaw = loose ? (match[4] || match[5] || "") : (match[4] || "");
    const buildRaw = loose ? (match[6] || "") : (match[5] || "");
    const prerelease = semvParsePreList(preRaw, loose);
    const build = buildRaw ? buildRaw.split(".") : [];
    const obj = {
        major,
        minor,
        patch,
        prerelease,
        build,
        version: "",
        full: ""
    };
    obj.version = semvFormatVersion(obj, false);
    obj.full = semvFormatVersion(obj, true);
    return obj;
}

function semvComparePreId(a, b) {
    if (a.num && b.num) {
        if (a.val >= 0 && b.val >= 0)
            return a.val < b.val ? -1 : (a.val > b.val ? 1 : 0);
        if (a.str.length !== b.str.length)
            return a.str.length < b.str.length ? -1 : 1;
        return a.str < b.str ? -1 : (a.str > b.str ? 1 : 0);
    }
    if (a.num !== b.num)
        return a.num ? -1 : 1;
    return a.str < b.str ? -1 : (a.str > b.str ? 1 : 0);
}

function semvCompare(a, b) {
    if (a.major !== b.major)
        return a.major < b.major ? -1 : 1;
    if (a.minor !== b.minor)
        return a.minor < b.minor ? -1 : 1;
    if (a.patch !== b.patch)
        return a.patch < b.patch ? -1 : 1;
    const al = a.prerelease.length;
    const bl = b.prerelease.length;
    if (al === 0 && bl === 0)
        return 0;
    if (al === 0)
        return 1;
    if (bl === 0)
        return -1;
    const limit = Math.min(al, bl);
    for (let i = 0; i < limit; i++) {
        const cmp = semvComparePreId(a.prerelease[i], b.prerelease[i]);
        if (cmp !== 0)
            return cmp;
    }
    return al < bl ? -1 : (al > bl ? 1 : 0);
}

function semvDiff(a, b) {
    const cmp = semvCompare(a, b);
    if (cmp === 0)
        return null;
    const high = cmp > 0 ? a : b;
    const low = cmp > 0 ? b : a;
    const highHasPre = high.prerelease.length > 0;
    const lowHasPre = low.prerelease.length > 0;
    if (lowHasPre && !highHasPre &&
        high.major === low.major && high.minor === low.minor && high.patch === low.patch) {
        if (low.minor === 0 && low.patch === 0)
            return "major";
        if (low.patch === 0)
            return "minor";
        return "patch";
    }
    const prefix = highHasPre ? "pre" : "";
    if (high.major !== low.major)
        return prefix + "major";
    if (high.minor !== low.minor)
        return prefix + "minor";
    if (high.patch !== low.patch)
        return prefix + "patch";
    return "prerelease";
}

function semvIncDigits(digits) {
    if (digits.length <= 15) {
        const n = Number(digits) + 1;
        return { num: true, str: String(n), val: n <= SEMV_MAX_SAFE ? n : -1 };
    }
    const arr = digits.split("").map(c => Number(c));
    let carry = 1;
    for (let i = arr.length - 1; i >= 0 && carry; i--) {
        const sum = arr[i] + carry;
        arr[i] = sum % 10;
        carry = sum >= 10 ? 1 : 0;
    }
    if (carry)
        arr.unshift(1);
    return { num: true, str: arr.join(""), val: -1 };
}

function semvClonePre(pre) {
    return pre.map(id => ({ num: id.num, str: id.str, val: id.val }));
}

function semvInc(v, release, preId = "rc") {
    let major = v.major;
    let minor = v.minor;
    let patch = v.patch;
    let prerelease = semvClonePre(v.prerelease);
    const idRaw = String(preId || "").trim();
    const idParts = idRaw ? semvParsePreList(idRaw, false) : [];

    switch (release) {
    case "premajor":
        prerelease = [];
        patch = 0;
        minor = 0;
        major += 1;
        return semvInc({ major, minor, patch, prerelease, build: [] }, "pre", idRaw);
    case "preminor":
        prerelease = [];
        patch = 0;
        minor += 1;
        return semvInc({ major, minor, patch, prerelease, build: [] }, "pre", idRaw);
    case "prepatch":
        prerelease = [];
        patch += 1;
        return semvInc({ major, minor, patch, prerelease, build: [] }, "pre", idRaw);
    case "prerelease":
        if (prerelease.length === 0) {
            patch += 1;
            return semvInc({ major, minor, patch, prerelease: [], build: [] }, "pre", idRaw);
        }
        return semvInc({ major, minor, patch, prerelease, build: [] }, "pre", idRaw);
    case "major":
        if (minor !== 0 || patch !== 0 || prerelease.length === 0)
            major += 1;
        minor = 0;
        patch = 0;
        prerelease = [];
        break;
    case "minor":
        if (patch !== 0 || prerelease.length === 0)
            minor += 1;
        patch = 0;
        prerelease = [];
        break;
    case "patch":
        if (prerelease.length === 0)
            patch += 1;
        prerelease = [];
        break;
    case "pre": {
        const base = { num: true, str: "0", val: 0 };
        if (prerelease.length === 0) {
            prerelease = idParts.concat([base]);
        } else {
            let i = prerelease.length - 1;
            for (; i >= 0; i--) {
                if (prerelease[i].num) {
                    prerelease[i] = semvIncDigits(prerelease[i].str);
                    break;
                }
            }
            if (i === -1)
                prerelease.push(base);
            if (idRaw) {
                const curPrefix = prerelease.slice(0, idParts.length).map(x => x.str).join(".");
                if (curPrefix !== idRaw || prerelease.length === idParts.length || !prerelease[idParts.length].num) {
                    if (prerelease[0].str === idRaw && idParts.length === 1) {
                        if (prerelease.length < 2 || !prerelease[1].num)
                            prerelease = [idParts[0], base];
                    } else if (curPrefix !== idRaw) {
                        prerelease = idParts.concat([base]);
                    }
                }
            }
        }
        break;
    }
    default:
        return null;
    }

    const out = { major, minor, patch, prerelease, build: [], version: "", full: "" };
    out.version = semvFormatVersion(out, false);
    out.full = semvFormatVersion(out, true);
    return out;
}

function semvIsWildcard(part) {
    return part === undefined || part === "" || part === "x" || part === "X" || part === "*";
}

function semvMakeComp(op, major, minor, patch, pre) {
    const semver = {
        major,
        minor,
        patch,
        prerelease: pre || [],
        build: [],
        version: "",
        full: ""
    };
    semver.version = semvFormatVersion(semver, false);
    semver.full = semvFormatVersion(semver, true);
    return { op, semver, any: false };
}

function semvAnyComp() {
    return { op: "", semver: null, any: true };
}

function semvParsePartialToken(raw, loose) {
    const strictRe = /^v?(0|[1-9]\d*|[xX*])(?:\.(0|[1-9]\d*|[xX*]))?(?:\.(0|[1-9]\d*|[xX*]))?(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/;
    const looseRe = /^[=v]*(\d+|[xX*])(?:\.(\d+|[xX*]))?(?:\.(\d+|[xX*]))?(?:\.(?:\d+|[xX*]))*(?:-((?:0|\d+|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|\d+|\d*[a-zA-Z-][0-9a-zA-Z-]*))*)|([a-zA-Z][0-9a-zA-Z-]*(?:\.(?:0|\d+|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/;
    const m = raw.match(loose ? looseRe : strictRe);
    if (!m)
        return null;
    const parseNum = s => {
        if (semvIsWildcard(s))
            return null;
        const norm = loose ? semvStripLeadingZeros(s) : s;
        const n = Number(norm);
        return isFinite(n) && n <= SEMV_MAX_SAFE ? n : NaN;
    };
    const M = parseNum(m[1]);
    const mm = parseNum(m[2]);
    const p = parseNum(m[3]);
    if (isNaN(M) || isNaN(mm) || isNaN(p))
        return null;
    const preRaw = loose ? (m[4] || m[5] || "") : (m[4] || "");
    const pre = semvParsePreList(preRaw, loose);
    if ((M === null || mm === null || p === null) && pre.length > 0 && !loose)
        return null;
    return { M, m: mm, p, pre };
}

function semvExpandCaret(t) {
    if (t.M === null)
        return [semvAnyComp()];
    const pre0 = [{ num: true, str: "0", val: 0 }];
    if (t.m === null) {
        return [
            semvMakeComp(">=", t.M, 0, 0),
            semvMakeComp("<", t.M + 1, 0, 0, pre0)
        ];
    }
    if (t.p === null) {
        if (t.M === 0) {
            return [
                semvMakeComp(">=", 0, t.m, 0),
                semvMakeComp("<", 0, t.m + 1, 0, pre0)
            ];
        }
        return [
            semvMakeComp(">=", t.M, t.m, 0),
            semvMakeComp("<", t.M + 1, 0, 0, pre0)
        ];
    }
    const lower = semvMakeComp(">=", t.M, t.m, t.p, t.pre);
    if (t.M > 0)
        return [lower, semvMakeComp("<", t.M + 1, 0, 0, pre0)];
    if (t.m > 0)
        return [lower, semvMakeComp("<", 0, t.m + 1, 0, pre0)];
    return [lower, semvMakeComp("<", 0, 0, t.p + 1, pre0)];
}

function semvExpandTilde(t) {
    if (t.M === null)
        return [semvAnyComp()];
    const pre0 = [{ num: true, str: "0", val: 0 }];
    if (t.m === null) {
        return [
            semvMakeComp(">=", t.M, 0, 0),
            semvMakeComp("<", t.M + 1, 0, 0, pre0)
        ];
    }
    if (t.p === null) {
        return [
            semvMakeComp(">=", t.M, t.m, 0),
            semvMakeComp("<", t.M, t.m + 1, 0, pre0)
        ];
    }
    return [
        semvMakeComp(">=", t.M, t.m, t.p, t.pre),
        semvMakeComp("<", t.M, t.m + 1, 0, pre0)
    ];
}

function semvExpandXRange(op, t) {
    const pre0 = [{ num: true, str: "0", val: 0 }];
    const eqOp = op === "" || op === "=";
    if (t.M === null) {
        if (op === "<" || op === ">")
            return [semvMakeComp("<", 0, 0, 0, pre0)];
        return [semvAnyComp()];
    }
    if (t.m === null) {
        if (eqOp)
            return [semvMakeComp(">=", t.M, 0, 0), semvMakeComp("<", t.M + 1, 0, 0, pre0)];
        if (op === ">=")
            return [semvMakeComp(">=", t.M, 0, 0)];
        if (op === "<")
            return [semvMakeComp("<", t.M, 0, 0, pre0)];
        if (op === "<=")
            return [semvMakeComp("<", t.M + 1, 0, 0, pre0)];
        return [semvMakeComp(">=", t.M + 1, 0, 0)];
    }
    if (t.p === null) {
        if (eqOp)
            return [semvMakeComp(">=", t.M, t.m, 0), semvMakeComp("<", t.M, t.m + 1, 0, pre0)];
        if (op === ">=")
            return [semvMakeComp(">=", t.M, t.m, 0)];
        if (op === "<")
            return [semvMakeComp("<", t.M, t.m, 0, pre0)];
        if (op === "<=")
            return [semvMakeComp("<", t.M, t.m + 1, 0, pre0)];
        return [semvMakeComp(">=", t.M, t.m + 1, 0)];
    }
    return [semvMakeComp(op === "=" ? "" : op, t.M, t.m, t.p, t.pre)];
}

function semvExpandHyphen(leftRaw, rightRaw, loose) {
    const left = semvParsePartialToken(leftRaw, loose);
    const right = semvParsePartialToken(rightRaw, loose);
    if (!left || !right)
        return null;
    const out = [];
    if (left.M !== null) {
        out.push(semvMakeComp(">=", left.M, left.m === null ? 0 : left.m, left.p === null ? 0 : left.p, left.pre));
    }
    const pre0 = [{ num: true, str: "0", val: 0 }];
    if (right.M === null) {
        if (out.length === 0)
            out.push(semvAnyComp());
    } else if (right.m === null) {
        out.push(semvMakeComp("<", right.M + 1, 0, 0, pre0));
    } else if (right.p === null) {
        out.push(semvMakeComp("<", right.M, right.m + 1, 0, pre0));
    } else {
        out.push(semvMakeComp("<=", right.M, right.m, right.p, right.pre));
    }
    return out;
}

function semvFormatComp(c) {
    if (c.any)
        return ">=0.0.0";
    return c.op + c.semver.version;
}

function semvParseRange(raw, loose = false) {
    const text = String(raw || "").trim();
    if (!text)
        return null;
    const clauses = text.split(/\s*\|\|\s*/);
    const sets = [];
    for (let i = 0; i < clauses.length; i++) {
        let clause = clauses[i].trim();
        if (!clause)
            return { error: "Empty clause around '||'." };
        if (loose)
            clause = clause.replace(/~>/g, "~");
        clause = clause.replace(/([<>]=?|\^|~|=)\s+/g, "$1");
        const comps = [];
        const hyphenMatch = clause.match(/^(\S+)\s+-\s+(\S+)$/);
        if (hyphenMatch) {
            const expanded = semvExpandHyphen(hyphenMatch[1], hyphenMatch[2], loose);
            if (!expanded)
                return { error: "Invalid hyphen range: " + clause };
            for (let k = 0; k < expanded.length; k++)
                comps.push(expanded[k]);
        } else {
            const tokens = clause.split(/\s+/);
            for (let j = 0; j < tokens.length; j++) {
                const tok = tokens[j];
                const opMatch = tok.match(/^([<>]=?|\^|~|=)?(.*)$/);
                const op = opMatch[1] || "";
                const body = opMatch[2];
                if (!body)
                    return { error: "Missing version after operator '" + op + "'." };
                const partial = semvParsePartialToken(body, loose);
                if (!partial)
                    return { error: "Invalid comparator '" + tok + "'." };
                let expanded;
                if (op === "^")
                    expanded = semvExpandCaret(partial);
                else if (op === "~")
                    expanded = semvExpandTilde(partial);
                else
                    expanded = semvExpandXRange(op, partial);
                for (let k = 0; k < expanded.length; k++)
                    comps.push(expanded[k]);
            }
        }
        // Collapse redundant ANY comparators when concrete comparators exist in the set
        const concrete = comps.filter(c => !c.any);
        sets.push(concrete.length > 0 ? concrete : [semvAnyComp()]);
    }
    return {
        sets,
        expanded: sets.map(set => set.map(semvFormatComp).join(" ")).join(" || ")
    };
}

function semvTestComp(c, v) {
    if (c.any)
        return true;
    const cmp = semvCompare(v, c.semver);
    switch (c.op) {
    case "":
    case "=":
        return cmp === 0;
    case ">":
        return cmp > 0;
    case ">=":
        return cmp >= 0;
    case "<":
        return cmp < 0;
    case "<=":
        return cmp <= 0;
    default:
        return false;
    }
}

function semvTestSet(set, v, includePrerelease) {
    for (let i = 0; i < set.length; i++) {
        if (!semvTestComp(set[i], v))
            return { pass: false, preExcluded: false };
    }
    if (v.prerelease.length > 0 && !includePrerelease) {
        let allowed = false;
        for (let i = 0; i < set.length; i++) {
            const sv = set[i].semver;
            if (sv && sv.prerelease.length > 0 &&
                sv.major === v.major && sv.minor === v.minor && sv.patch === v.patch) {
                allowed = true;
                break;
            }
        }
        if (!allowed)
            return { pass: false, preExcluded: true };
    }
    return { pass: true, preExcluded: false };
}

function semvSatisfies(parsedRange, v, includePrerelease = false) {
    let sawPreExcluded = false;
    for (let i = 0; i < parsedRange.sets.length; i++) {
        const res = semvTestSet(parsedRange.sets[i], v, includePrerelease);
        if (res.pass)
            return { pass: true, preExcluded: false };
        if (res.preExcluded)
            sawPreExcluded = true;
    }
    return { pass: false, preExcluded: sawPreExcluded };
}

function semvIsRangeLine(line) {
    if (/[~^><=*]|(\|\|)/.test(line))
        return true;
    if (/\s+-\s+/.test(line))
        return true;
    const main = line.split(/[-+]/)[0];
    return /(?:^|[.\s])[xX](?:$|[.\s])/.test(main);
}

function semvParseComparisonLine(line, loose) {
    const cleaned = line.replace(/\s*\?\s*$/, "").trim();
    const m = cleaned.match(/^(.+?)\s+(vs\.?|<=|>=|===|!==|==|!=|<|>|=)\s+(.+)$/i);
    if (!m)
        return null;
    const leftRaw = m[1].trim();
    const op = m[2].toLowerCase().replace(/\.$/, "");
    const rightRaw = m[3].trim();
    const left = semvParseVersion(leftRaw, loose);
    const right = semvParseVersion(rightRaw, loose);
    return { leftRaw, rightRaw, op, left, right };
}

function semvChipText(text) {
    const s = String(text);
    return s.length <= 40 ? s : s.slice(0, 37) + "...";
}

function semvRenderSingle(raw, v, preId) {
    const out = [];
    if (raw.trim() !== v.full)
        out.push(`Input       ${raw.trim()}`);
    out.push(`Version     ${v.full}`);
    out.push(`Major       ${v.major}`);
    out.push(`Minor       ${v.minor}`);
    out.push(`Patch       ${v.patch}`);
    out.push(`Prerelease  ${v.prerelease.length > 0 ? v.prerelease.map(p => p.str).join(", ") : "none"}`);
    out.push(`Build       ${v.build.length > 0 ? v.build.join(", ") : "none"}`);
    const channel = v.prerelease.length > 0 ? "prerelease" : (v.major === 0 ? "0.x dev" : "stable");
    out.push(`Channel     ${channel}`);

    const labelPre = preId ? ` (pre: ${preId})` : " (numeric pre)";
    out.push("", `Next versions${labelPre}`);
    const bumps = ["major", "minor", "patch", "premajor", "preminor", "prepatch", "prerelease"];
    for (let i = 0; i < bumps.length; i++) {
        const kind = bumps[i];
        const next = semvInc(v, kind, preId);
        out.push(`  ${kind.padEnd(11)} ${next.full}`);
    }
    return {
        output: out.join("\n"),
        meta: {
            version: semvChipText(v.full),
            channel,
            nextPatch: semvChipText(semvInc(v, "patch", preId).full)
        }
    };
}

function semvRenderCompare(left, right, op) {
    const cmp = semvCompare(left, right);
    const rel = cmp < 0 ? "<" : (cmp > 0 ? ">" : "==");
    const diff = semvDiff(left, right);
    const out = [
        `Left        ${left.full}`,
        `Right       ${right.full}`,
        `Order       ${left.full} ${rel} ${right.full}${cmp === 0 && left.full !== right.full ? " (equal precedence)" : ""}`,
        `Diff        ${diff ? diff : (left.full === right.full ? "none (identical)" : "none (build metadata ignored)")}`
    ];
    let assertion = null;
    if (op && op !== "vs") {
        if (op === "<") assertion = cmp < 0;
        else if (op === "<=") assertion = cmp <= 0;
        else if (op === ">") assertion = cmp > 0;
        else if (op === ">=") assertion = cmp >= 0;
        else if (op === "==" || op === "===" || op === "=") assertion = cmp === 0;
        else if (op === "!=" || op === "!==") assertion = cmp !== 0;
        if (assertion !== null)
            out.push(`Assertion   ${left.full} ${op} ${right.full}  ->  ${assertion ? "true (✓)" : "false (✗)"}`);
    }
    if (cmp !== 0) {
        const higher = cmp > 0 ? left : right;
        const lower = cmp > 0 ? right : left;
        out.push(`Higher      ${higher.full}`);
        out.push(`Lower       ${lower.full}`);
    }
    const meta = {
        order: rel,
        diff: diff || "none"
    };
    if (assertion !== null)
        meta.result = assertion;
    else if (cmp !== 0)
        meta.higher = semvChipText((cmp > 0 ? left : right).full);
    return { output: out.join("\n"), meta };
}

function semvRenderRange(rangeLine, candidateLines, options) {
    const loose = !!options.loose;
    const includePre = !!options.includePrerelease;
    const parsed = semvParseRange(rangeLine, loose);
    if (!parsed)
        return { output: "", error: "Enter a SemVer range like ^1.2.3, ~1.2, 1.x, 1.2.3 - 2.3.4, or >=1.0.0 <2.0.0 || >=3." };
    if (parsed.error)
        return { output: "", error: parsed.error + " Expected e.g. ^1.2.3, ~1.2, 1.2.3 - 2.3.4." };

    const out = [
        `Range       ${rangeLine}`,
        `Expanded    ${parsed.expanded}`,
        `Prerelease  ${includePre ? "included" : "strict (same [major.minor.patch] only)"}`
    ];

    if (candidateLines.length === 0) {
        out.push("", "Add version lines below the range to test satisfaction.");
        return {
            output: out.join("\n"),
            meta: {
                clauses: parsed.sets.length,
                prereleases: includePre ? "included" : "strict"
            }
        };
    }

    const satisfying = [];
    const rows = [];
    let maxLen = 0;
    for (let i = 0; i < candidateLines.length; i++) {
        const raw = candidateLines[i];
        const v = semvParseVersion(raw, loose);
        if (!v) {
            rows.push({ mark: "?", text: raw, note: "invalid semver" });
            if (raw.length > maxLen) maxLen = raw.length;
            continue;
        }
        const res = semvSatisfies(parsed, v, includePre);
        let note = "";
        if (res.pass) {
            satisfying.push(v);
        } else {
            note = res.preExcluded ? "prerelease excluded" : "outside range";
        }
        rows.push({ mark: res.pass ? "✓" : "✗", text: v.full, note });
        if (v.full.length > maxLen) maxLen = v.full.length;
    }

    const colW = Math.min(Math.max(maxLen, 8), 32);
    out.push("", `Versions (${satisfying.length} of ${candidateLines.length} satisfied)`);
    for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const line = r.note
            ? `  ${r.mark}  ${r.text.padEnd(colW)}  ${r.note}`
            : `  ${r.mark}  ${r.text}`;
        out.push(line);
    }

    const meta = {
        satisfying: `${satisfying.length}/${candidateLines.length}`
    };
    if (satisfying.length > 0) {
        const sorted = satisfying.slice().sort(semvCompare);
        const minV = sorted[0];
        const maxV = sorted[sorted.length - 1];
        out.push("", `Min         ${minV.full}`, `Max         ${maxV.full}`);
        meta.min = semvChipText(minV.full);
        meta.max = semvChipText(maxV.full);
    } else {
        out.push("", "Min         none", "Max         none");
    }
    return { output: out.join("\n"), meta };
}

function semvRenderList(lines, options) {
    const loose = !!options.loose;
    const desc = options.order === "desc";
    const valid = [];
    const invalid = [];
    for (let i = 0; i < lines.length; i++) {
        const v = semvParseVersion(lines[i], loose);
        if (v)
            valid.push(v);
        else
            invalid.push({ line: i + 1, text: lines[i] });
    }
    if (valid.length === 0)
        return { output: "", error: "No valid SemVer versions found. Expected e.g. 1.2.3 (or enable Loose / coerce for v1.2, =1.2.3, 1.2.3.4)." };

    valid.sort((a, b) => desc ? semvCompare(b, a) : semvCompare(a, b));
    const minV = desc ? valid[valid.length - 1] : valid[0];
    const maxV = desc ? valid[0] : valid[valid.length - 1];

    const orderLabel = desc ? "desc" : "asc";
    const headerParts = [orderLabel, `${valid.length} valid`];
    if (invalid.length > 0)
        headerParts.push(`${invalid.length} invalid`);

    const padW = String(valid.length).length + 1;
    const out = [`Sorted (${headerParts.join(", ")})`];
    for (let i = 0; i < valid.length; i++)
        out.push(`  ${(String(i + 1) + ".").padEnd(padW)} ${valid[i].full}`);
    out.push("", `Min         ${minV.full}`, `Max         ${maxV.full}`);

    if (invalid.length > 0) {
        out.push("", `Invalid lines (${invalid.length})`);
        for (let i = 0; i < invalid.length; i++)
            out.push(`  line ${invalid[i].line}: ${invalid[i].text}`);
    }

    const meta = {
        count: invalid.length > 0 ? `${valid.length}/${lines.length}` : valid.length,
        min: semvChipText(minV.full),
        max: semvChipText(maxV.full)
    };
    return { output: out.join("\n"), meta };
}

function semvTool(input = "", options = {}) {
    const lines = String(input).split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length === 0)
        return { output: "" };

    const loose = !!options.loose;
    const preId = options.pre !== undefined ? String(options.pre).trim() : "rc";
    if (preId && !SEMV_PRE_ID_RE.test(preId))
        return { output: "", error: "Invalid prerelease identifier '" + preId + "'. Use ASCII letters, digits, hyphens, or dots (e.g. rc, alpha.1)." };

    if (lines.length === 1) {
        const cmp = semvParseComparisonLine(lines[0], loose);
        if (cmp) {
            if (!cmp.left)
                return { output: "", error: "Invalid SemVer '" + cmp.leftRaw + "'. Expected e.g. 1.2.3 (or enable Loose / coerce)." };
            if (!cmp.right)
                return { output: "", error: "Invalid SemVer '" + cmp.rightRaw + "'. Expected e.g. 1.10.0 (or enable Loose / coerce)." };
            return semvRenderCompare(cmp.left, cmp.right, cmp.op);
        }
        // In loose mode, "=1.2.3" alone coerces as a single version; in strict mode it is rejected unless used as a multi-line range.
        const single = semvParseVersion(lines[0], loose);
        if (single)
            return semvRenderSingle(lines[0], single, preId);

        if (semvIsRangeLine(lines[0])) {
            if (/^=/.test(lines[0]) && !/[~^><*]|(\|\|)|(\s+-\s+)|(\s+)/.test(lines[0]))
                return { output: "", error: "Invalid SemVer '" + lines[0] + "'. Enable Loose / coerce to parse '=1.2.3', or add versions below to test it as a range." };
            return semvRenderRange(lines[0], [], options);
        }
        return { output: "", error: "Invalid SemVer '" + lines[0] + "'. Enter a version (1.2.3), comparison (1.2.3 vs 1.10.0), range (^1.2.3), or list; or enable Loose / coerce." };
    }

    if (semvIsRangeLine(lines[0]))
        return semvRenderRange(lines[0], lines.slice(1), options);

    if (lines.length === 2) {
        const left = semvParseVersion(lines[0], loose);
        if (!left)
            return { output: "", error: "Invalid SemVer on line 1: '" + lines[0] + "'. Expected e.g. 1.2.3 (or enable Loose / coerce)." };
        const right = semvParseVersion(lines[1], loose);
        if (!right)
            return { output: "", error: "Invalid SemVer on line 2: '" + lines[1] + "'. Expected e.g. 1.10.0 (or enable Loose / coerce)." };
        return semvRenderCompare(left, right, null);
    }

    return semvRenderList(lines, options);
}
// @slot-end semver_tool

// @slot-begin commit_lint
const CCMT_DEFAULT_TYPES = [
    "feat", "fix", "docs", "style", "refactor",
    "perf", "test", "build", "ci", "chore", "revert"
];

const CCMT_SECTIONS = [
    { key: "breaking", title: "⚠ Breaking changes" },
    { key: "feat", title: "Features" },
    { key: "fix", title: "Bug fixes" },
    { key: "perf", title: "Performance" },
    { key: "revert", title: "Reverts" },
    { key: "refactor", title: "Refactoring" },
    { key: "docs", title: "Documentation" },
    { key: "test", title: "Tests" },
    { key: "build_ci", title: "Build & CI" },
    { key: "chore", title: "Chores" }
];

const CCMT_TYPE_TO_SECTION = {
    feat: "feat",
    fix: "fix",
    perf: "perf",
    revert: "revert",
    refactor: "refactor",
    docs: "docs",
    test: "test",
    build: "build_ci",
    ci: "build_ci",
    chore: "chore",
    style: "chore"
};

const CCMT_IMPERATIVE_NON_BASE = {
    added: "add", adds: "add", adding: "add",
    adjusted: "adjust", adjusts: "adjust", adjusting: "adjust",
    allowed: "allow", allows: "allow", allowing: "allow",
    applied: "apply", applies: "apply", applying: "apply",
    avoided: "avoid", avoids: "avoid", avoiding: "avoid",
    broke: "break", breaks: "break", breaking: "break",
    built: "build", builds: "build", building: "build",
    bumped: "bump", bumps: "bump", bumping: "bump",
    caught: "catch", catches: "catch", catching: "catch",
    changed: "change", changes: "change", changing: "change",
    checked: "check", checks: "check", checking: "check",
    cleaned: "clean", cleans: "clean", cleaning: "clean",
    cleared: "clear", clears: "clear", clearing: "clear",
    closed: "close", closes: "close", closing: "close",
    configured: "configure", configures: "configure", configuring: "configure",
    corrected: "correct", corrects: "correct", correcting: "correct",
    created: "create", creates: "create", creating: "create",
    deleted: "delete", deletes: "delete", deleting: "delete",
    deployed: "deploy", deploys: "deploy", deploying: "deploy",
    deprecated: "deprecate", deprecates: "deprecate", deprecating: "deprecate",
    disabled: "disable", disables: "disable", disabling: "disable",
    documented: "document", documents: "document", documenting: "document",
    downgraded: "downgrade", downgrades: "downgrade", downgrading: "downgrade",
    dropped: "drop", drops: "drop", dropping: "drop",
    enabled: "enable", enables: "enable", enabling: "enable",
    ensured: "ensure", ensures: "ensure", ensuring: "ensure",
    exported: "export", exports: "export", exporting: "export",
    exposed: "expose", exposes: "expose", exposing: "expose",
    extracted: "extract", extracts: "extract", extracting: "extract",
    fetched: "fetch", fetches: "fetch", fetching: "fetch",
    filtered: "filter", filters: "filter", filtering: "filter",
    fixed: "fix", fixes: "fix", fixing: "fix",
    formatted: "format", formats: "format", formatting: "format",
    generated: "generate", generates: "generate", generating: "generate",
    got: "get", gets: "get", getting: "get",
    handled: "handle", handles: "handle", handling: "handle",
    hid: "hide", hidden: "hide", hides: "hide", hiding: "hide",
    implemented: "implement", implements: "implement", implementing: "implement",
    imported: "import", imports: "import", importing: "import",
    improved: "improve", improves: "improve", improving: "improve",
    initialized: "initialize", initializes: "initialize", initializing: "initialize",
    installed: "install", installs: "install", installing: "install",
    introduced: "introduce", introduces: "introduce", introducing: "introduce",
    joined: "join", joins: "join", joining: "join",
    kept: "keep", keeps: "keep", keeping: "keep",
    loaded: "load", loads: "load", loading: "load",
    locked: "lock", locks: "lock", locking: "lock",
    logged: "log", logs: "log", logging: "log",
    made: "make", makes: "make", making: "make",
    mapped: "map", maps: "map", mapping: "map",
    merged: "merge", merges: "merge", merging: "merge",
    migrated: "migrate", migrates: "migrate", migrating: "migrate",
    modified: "modify", modifies: "modify", modifying: "modify",
    moved: "move", moves: "move", moving: "move",
    opened: "open", opens: "open", opening: "open",
    parsed: "parse", parses: "parse", parsing: "parse",
    passed: "pass", passes: "pass", passing: "pass",
    pinned: "pin", pins: "pin", pinning: "pin",
    prevented: "prevent", prevents: "prevent", preventing: "prevent",
    printed: "print", prints: "print", printing: "print",
    published: "publish", publishes: "publish", publishing: "publish",
    pushed: "push", pushes: "push", pushing: "push",
    ran: "run", runs: "run", running: "run",
    refactored: "refactor", refactors: "refactor", refactoring: "refactor",
    released: "release", releases: "release", releasing: "release",
    removed: "remove", removes: "remove", removing: "remove",
    renamed: "rename", renames: "rename", renaming: "rename",
    replaced: "replace", replaces: "replace", replacing: "replace",
    resolved: "resolve", resolves: "resolve", resolving: "resolve",
    restored: "restore", restores: "restore", restoring: "restore",
    retried: "retry", retries: "retry", retrying: "retry",
    returned: "return", returns: "return", returning: "return",
    reverted: "revert", reverts: "revert", reverting: "revert",
    saved: "save", saves: "save", saving: "save",
    sent: "send", sends: "send", sending: "send",
    sets: "set", setting: "set",
    showed: "show", shown: "show", shows: "show", showing: "show",
    simplified: "simplify", simplifies: "simplify", simplifying: "simplify",
    skipped: "skip", skips: "skip", skipping: "skip",
    sorted: "sort", sorts: "sort", sorting: "sort",
    started: "start", starts: "start", starting: "start",
    stopped: "stop", stops: "stop", stopping: "stop",
    supported: "support", supports: "support", supporting: "support",
    switched: "switch", switches: "switch", switching: "switch",
    tagged: "tag", tags: "tag", tagging: "tag",
    tested: "test", tests: "test", testing: "test",
    threw: "throw", thrown: "throw", throws: "throw", throwing: "throw",
    tracked: "track", tracks: "track", tracking: "track",
    updated: "update", updates: "update", updating: "update",
    upgraded: "upgrade", upgrades: "upgrade", upgrading: "upgrade",
    used: "use", uses: "use", using: "use",
    validated: "validate", validates: "validate", validating: "validate",
    verified: "verify", verifies: "verify", verifying: "verify",
    warned: "warn", warns: "warn", warning: "warn",
    wrote: "write", written: "write", writes: "write", writing: "write"
};

const CCMT_ALLOWED_ED_ING = {
    embed: true, need: true, feed: true, seed: true, speed: true, heed: true,
    bleed: true, breed: true, weed: true, shed: true, shred: true, wed: true,
    bring: true, string: true, swing: true, spring: true, cling: true, fling: true,
    sling: true, sting: true, wring: true, sing: true, ring: true, ping: true, wing: true
};

const CCMT_STRICT_TRAILERS = {
    "refs": true, "fixes": true, "closes": true, "resolves": true, "see": true,
    "signed-off-by": true, "co-authored-by": true, "acked-by": true,
    "reviewed-by": true, "tested-by": true, "reported-by": true, "helped-by": true,
    "change-id": true, "breaking-change": true, "breaking change": true
};

function ccmtParseTypesOption(raw) {
    let list;
    if (Array.isArray(raw)) {
        list = raw.map(v => String(v).trim().toLowerCase());
    } else if (typeof raw === "string" && raw.trim().length > 0) {
        list = raw.split(/[,;\s]+/).map(v => v.trim().toLowerCase());
    } else {
        list = CCMT_DEFAULT_TYPES.slice();
    }
    const out = [];
    const seen = {};
    for (let i = 0; i < list.length; i++) {
        const t = list[i];
        if (t.length > 0 && !seen[t]) {
            seen[t] = true;
            out.push(t);
        }
    }
    return out.length > 0 ? out : CCMT_DEFAULT_TYPES.slice();
}

function ccmtParseSemver(raw) {
    const text = String(raw || "").trim();
    if (text.length === 0)
        return null;
    const m = text.match(/^(v)?(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/);
    if (!m)
        return { invalid: true, raw: text };
    return {
        invalid: false,
        prefix: m[1] || "",
        major: Number(m[2]),
        minor: Number(m[3]),
        patch: Number(m[4]),
        raw: text
    };
}

function ccmtBumpSemver(parsed, bump) {
    if (!parsed || parsed.invalid)
        return null;
    if (bump === "major")
        return `${parsed.prefix}${parsed.major + 1}.0.0`;
    if (bump === "minor")
        return `${parsed.prefix}${parsed.major}.${parsed.minor + 1}.0`;
    if (bump === "patch")
        return `${parsed.prefix}${parsed.major}.${parsed.minor}.${parsed.patch + 1}`;
    return parsed.raw;
}

function ccmtMaxBump(a, b) {
    const rank = { none: 0, patch: 1, minor: 2, major: 3 };
    return (rank[b] || 0) > (rank[a] || 0) ? b : a;
}

function ccmtIsHashLogLine(line) {
    const m = line.match(/^([0-9a-f]{7,40})\s+\S/);
    if (!m)
        return false;
    // Almost every real git hash contains at least one digit or is >= 8 chars.
    return /\d/.test(m[1]) || m[1].length >= 8;
}

function ccmtMatchesCommitHeader(line, allowedTypes) {
    const stripped = line.replace(/^[0-9a-f]{7,40}\s+/, "");
    const m = stripped.match(/^([a-zA-Z][a-zA-Z0-9_-]*)(?:\([^)\r\n]+\))?!?:[ \t]+\S/);
    if (!m)
        return false;
    const lower = m[1].toLowerCase();
    return allowedTypes.indexOf(lower) !== -1;
}

function ccmtDetectMultiMode(rawLines, allowedTypes) {
    const nonEmpty = rawLines.filter(l => l.trim().length > 0);
    if (nonEmpty.length < 2)
        return false;

    let hashCount = 0;
    let commitHeaderCount = 0;
    for (let i = 0; i < nonEmpty.length; i++) {
        if (ccmtIsHashLogLine(nonEmpty[i]))
            hashCount++;
        if (ccmtMatchesCommitHeader(nonEmpty[i], allowedTypes))
            commitHeaderCount++;
    }

    if (hashCount >= 2 || (hashCount >= 1 && ccmtIsHashLogLine(nonEmpty[0])))
        return true;

    const hasBlankLine = rawLines.some(l => l.trim().length === 0);
    if (!hasBlankLine)
        return commitHeaderCount >= 2;

    // Blank-line-separated list only counts as multi-commit if every line looks like a header.
    return commitHeaderCount === nonEmpty.length && commitHeaderCount >= 2;
}

function ccmtParseHeader(header, allowedTypes) {
    const result = {
        raw: header,
        hasColon: false,
        type: "",
        typeSyntaxError: "",
        hasScope: false,
        scope: "",
        scopeError: "",
        scopeHasUpper: false,
        bang: false,
        bangBeforeScope: false,
        spaceBeforeColon: false,
        hasSpaceAfterColon: false,
        extraSpaceAfterColon: false,
        description: ""
    };

    const colonIdx = header.indexOf(":");
    if (colonIdx === -1) {
        result.description = "";
        return result;
    }

    result.hasColon = true;
    const left = header.slice(0, colonIdx);
    const right = header.slice(colonIdx + 1);

    if (right.length > 0 && (right[0] === " " || right[0] === "\t")) {
        result.hasSpaceAfterColon = true;
        if (right.length > 1 && (right[1] === " " || right[1] === "\t"))
            result.extraSpaceAfterColon = true;
    }
    result.description = right.trim();

    if (/^\s/.test(left)) {
        result.typeSyntaxError = "Leading whitespace before commit type";
    }
    const leftTrim = left.trim();
    const typeMatch = leftTrim.match(/^([a-zA-Z0-9_-]+)(.*)$/);
    if (!typeMatch) {
        result.typeSyntaxError = leftTrim.length === 0
            ? "Missing commit type before ':'"
            : "Single word required before (scope)";
        return result;
    }

    result.type = typeMatch[1];
    const tail = typeMatch[2];
    if (tail.length === 0)
        return result;

    if (/\s$/.test(left))
        result.spaceBeforeColon = true;

    const openIdx = tail.indexOf("(");
    const closeIdx = tail.lastIndexOf(")");
    if (openIdx !== -1) {
        result.hasScope = true;
        const beforeParen = tail.slice(0, openIdx);
        if (beforeParen.indexOf("!") !== -1) {
            result.bang = true;
            result.bangBeforeScope = true;
        } else if (beforeParen.trim().length > 0) {
            result.typeSyntaxError = "Unexpected text between type and scope";
        } else if (beforeParen.length > 0) {
            result.scopeError = "No space allowed between type and '('";
        }

        if (closeIdx === -1 || closeIdx < openIdx) {
            result.scope = tail.slice(openIdx + 1);
            result.scopeError = "Unclosed scope parentheses";
            return result;
        }

        result.scope = tail.slice(openIdx + 1, closeIdx);
        const afterParen = tail.slice(closeIdx + 1);
        if (afterParen.indexOf("!") !== -1)
            result.bang = true;
        if (/\s/.test(afterParen))
            result.spaceBeforeColon = true;
        const leftover = afterParen.replace(/!/g, "").trim();
        if (leftover.length > 0)
            result.scopeError = `Unexpected characters "${leftover}" after scope`;

        if (result.scope.length === 0) {
            result.scopeError = "Scope cannot be empty";
        } else if (!/^[a-zA-Z0-9._\/-]+$/.test(result.scope)) {
            result.scopeError = "only letters, digits, - _ . /";
        } else if (/[A-Z]/.test(result.scope)) {
            result.scopeHasUpper = true;
        }
    } else {
        if (tail.indexOf(")") !== -1) {
            result.hasScope = true;
            result.scope = tail;
            result.scopeError = "Unmatched ')' in scope";
        }
        if (tail.indexOf("!") !== -1)
            result.bang = true;
        if (/\s/.test(tail))
            result.spaceBeforeColon = true;
        const leftover = tail.replace(/[!)\s]/g, "").trim();
        if (leftover.length > 0 && !result.scopeError) {
            if (allowedTypes.indexOf(result.type.toLowerCase()) !== -1)
                result.typeSyntaxError = `Unexpected "${leftover}" after type`;
            else
                result.typeSyntaxError = "No spaces or punctuation in type";
        }
    }

    return result;
}

function ccmtMatchFooterStart(line) {
    const m = line.match(/^(BREAKING CHANGE|BREAKING-CHANGE|[A-Za-z][A-Za-z0-9-]*)(:\s|\s#)(.*)$/);
    if (!m)
        return null;
    const rawToken = m[1];
    const sep = m[2];
    const rest = m[3];
    const isBreaking = rawToken === "BREAKING CHANGE" || rawToken === "BREAKING-CHANGE";
    const isBreakingCaseIssue = !isBreaking && (rawToken.toLowerCase() === "breaking-change");
    return {
        token: rawToken,
        separator: sep.charAt(1) === "#" ? " #" : ": ",
        value: rest,
        isBreaking,
        isBreakingCaseIssue
    };
}

function ccmtIsBreakingLooseLine(line) {
    return /^breaking[\s-]+change:\s*/i.test(line);
}

function ccmtIsStrictTrailingFooter(line) {
    const f = ccmtMatchFooterStart(line);
    if (!f)
        return false;
    if (f.isBreaking || f.separator === " #")
        return true;
    const lower = f.token.toLowerCase();
    if (CCMT_STRICT_TRAILERS[lower])
        return true;
    return f.token.indexOf("-") !== -1;
}

function ccmtParseBodyAndFooters(restLines) {
    const info = {
        hasAfterHeader: false,
        missingBlankAfterHeader: false,
        missingBlankBeforeFooters: false,
        body: "",
        footers: [],
        breakingCaseWarning: false
    };

    if (restLines.length === 0)
        return info;

    info.hasAfterHeader = restLines.some(l => l.trim().length > 0);
    if (!info.hasAfterHeader)
        return info;

    info.missingBlankAfterHeader = restLines[0].trim().length > 0;

    // Group restLines into non-empty paragraph blocks.
    const paragraphs = [];
    let i = 0;
    while (i < restLines.length) {
        while (i < restLines.length && restLines[i].trim().length === 0)
            i++;
        if (i >= restLines.length)
            break;
        const start = i;
        while (i < restLines.length && restLines[i].trim().length > 0)
            i++;
        paragraphs.push({ start, end: i, lines: restLines.slice(start, i) });
    }

    // Find first paragraph where the trailing footer section starts.
    let footerParaIdx = paragraphs.length;
    for (let p = 0; p < paragraphs.length; p++) {
        const firstLine = paragraphs[p].lines[0];
        const isFooterPara = ccmtMatchFooterStart(firstLine) !== null || ccmtIsBreakingLooseLine(firstLine);
        if (!isFooterPara)
            continue;
        let allTrailingValid = true;
        for (let q = p + 1; q < paragraphs.length; q++) {
            const qFirst = paragraphs[q].lines[0];
            const qFooter = ccmtMatchFooterStart(qFirst) !== null || ccmtIsBreakingLooseLine(qFirst);
            const prevIsBreaking = (paragraphs[q - 1].lines[0].indexOf("BREAKING CHANGE") === 0
                || paragraphs[q - 1].lines[0].indexOf("BREAKING-CHANGE") === 0);
            if (!qFooter && !prevIsBreaking) {
                allTrailingValid = false;
                break;
            }
        }
        if (allTrailingValid) {
            footerParaIdx = p;
            break;
        }
    }

    const bodyParagraphs = paragraphs.slice(0, footerParaIdx);
    const footerLines = [];
    for (let p = footerParaIdx; p < paragraphs.length; p++) {
        if (p > footerParaIdx)
            footerLines.push("");
        for (let k = 0; k < paragraphs[p].lines.length; k++)
            footerLines.push(paragraphs[p].lines[k]);
    }

    // If the last body paragraph has trailing strict trailers (missing blank line before footers), split them out.
    if (bodyParagraphs.length > 0) {
        const lastPara = bodyParagraphs[bodyParagraphs.length - 1];
        let splitIdx = lastPara.lines.length;
        for (let k = 1; k < lastPara.lines.length; k++) {
            const line = lastPara.lines[k];
            if (!(ccmtIsStrictTrailingFooter(line) || ccmtIsBreakingLooseLine(line)))
                continue;
            let allFollowingValid = true;
            for (let m = k + 1; m < lastPara.lines.length; m++) {
                const nextLine = lastPara.lines[m];
                const isCont = /^\s+\S/.test(nextLine);
                if (!isCont && !(ccmtIsStrictTrailingFooter(nextLine) || ccmtIsBreakingLooseLine(nextLine))) {
                    allFollowingValid = false;
                    break;
                }
            }
            if (allFollowingValid) {
                splitIdx = k;
                break;
            }
        }
        if (splitIdx < lastPara.lines.length) {
            info.missingBlankBeforeFooters = true;
            const moved = lastPara.lines.slice(splitIdx);
            lastPara.lines = lastPara.lines.slice(0, splitIdx);
            for (let m = moved.length - 1; m >= 0; m--)
                footerLines.unshift(moved[m]);
        }
    }

    info.body = bodyParagraphs
        .map(p => p.lines.join("\n"))
        .filter(s => s.length > 0)
        .join("\n\n");

    let current = null;
    for (let k = 0; k < footerLines.length; k++) {
        const line = footerLines[k];
        if (line.trim().length === 0) {
            if (current)
                current.value += "\n";
            continue;
        }
        const match = ccmtMatchFooterStart(line);
        if (match) {
            if (match.isBreakingCaseIssue)
                info.breakingCaseWarning = true;
            current = {
                token: match.token,
                separator: match.separator,
                value: match.value.trim(),
                isBreaking: match.isBreaking
            };
            info.footers.push(current);
        } else if (ccmtIsBreakingLooseLine(line)) {
            info.breakingCaseWarning = true;
            const colonPos = line.indexOf(":");
            current = {
                token: line.slice(0, colonPos).trim(),
                separator: ": ",
                value: line.slice(colonPos + 1).trim(),
                isBreaking: false
            };
            info.footers.push(current);
        } else if (current) {
            current.value = current.value.length > 0
                ? current.value + "\n" + line.trim()
                : line.trim();
        }
    }
    for (let k = 0; k < info.footers.length; k++) {
        info.footers[k].value = info.footers[k].value.replace(/\n+$/, "");
    }

    return info;
}

function ccmtCheckImperative(description) {
    const trimmed = description.trim();
    if (trimmed.length === 0)
        return { ok: true };
    const firstRaw = trimmed.split(/\s+/)[0];
    const clean = firstRaw.toLowerCase().replace(/^[^a-z]+|[^a-z]+$/g, "");
    if (clean.length === 0)
        return { ok: true };
    if (CCMT_IMPERATIVE_NON_BASE[clean])
        return { ok: false, word: firstRaw, suggestion: CCMT_IMPERATIVE_NON_BASE[clean] };
    if (!CCMT_ALLOWED_ED_ING[clean]) {
        if (clean.length > 4 && /ing$/.test(clean))
            return { ok: false, word: firstRaw, suggestion: "" };
        if (clean.length > 4 && /ed$/.test(clean) && !/(red|eed)$/.test(clean))
            return { ok: false, word: firstRaw, suggestion: "" };
    }
    return { ok: true };
}

function ccmtWrapLine(text, maxWidth) {
    const s = String(text || "");
    if (s.length <= maxWidth)
        return [s];
    const words = s.split(" ");
    const lines = [];
    let current = "";
    for (let i = 0; i < words.length; i++) {
        const w = words[i];
        if (current.length === 0) {
            current = w;
        } else if (current.length + 1 + w.length <= maxWidth) {
            current += " " + w;
        } else {
            lines.push(current);
            current = w;
        }
    }
    if (current.length > 0)
        lines.push(current);
    return lines.length > 0 ? lines : [s];
}

function ccmtLintSingle(rawLines, options, allowedTypes) {
    const maxHeader = [50, 72, 100].indexOf(Number(options.maxHeader)) !== -1
        ? Number(options.maxHeader)
        : (Number(options.maxHeader) > 0 ? Math.floor(Number(options.maxHeader)) : 72);

    const header = rawLines[0];
    const parsed = ccmtParseHeader(header, allowedTypes);
    const bf = ccmtParseBodyAndFooters(rawLines.slice(1));

    const hasFooterBreaking = bf.footers.some(f => f.isBreaking);
    const isBreaking = parsed.bang || hasFooterBreaking;

    const lowerType = parsed.type.toLowerCase();
    const isKnownType = parsed.type.length > 0 && allowedTypes.indexOf(lowerType) !== -1;

    let bump = "none";
    if (isBreaking)
        bump = "major";
    else if (lowerType === "feat")
        bump = "minor";
    else if (lowerType === "fix")
        bump = "patch";

    const errorChecks = [];
    const warnChecks = [];
    const okChecks = [];
    let errors = 0;
    let warnings = 0;
    const formatCheck = (symbol, text) => {
        const wrapped = ccmtWrapLine(text, 50);
        const lines = [`  ${symbol}  ${wrapped[0]}`];
        for (let i = 1; i < wrapped.length; i++)
            lines.push(`     ${wrapped[i]}`);
        return lines.join("\n");
    };
    const addCheck = (level, text) => {
        if (level === "error") {
            errors++;
            errorChecks.push(formatCheck("✗", text));
        } else if (level === "warn") {
            warnings++;
            warnChecks.push(formatCheck("⚠", text));
        } else {
            okChecks.push(formatCheck("✓", text));
        }
    };

    // 1. Known type
    if (parsed.typeSyntaxError) {
        addCheck("error", `Commit type: ${parsed.typeSyntaxError}`);
    } else if (!parsed.hasColon || parsed.type.length === 0) {
        addCheck("error", `Missing commit type (expected one of: ${allowedTypes.join(", ")})`);
    } else if (isKnownType) {
        addCheck("ok", `Known type (${lowerType})`);
    } else {
        addCheck("error", `Unknown type "${parsed.type}" (allowed: ${allowedTypes.join(", ")})`);
    }

    // 2. Lowercase type
    if (parsed.type.length > 0 && !parsed.typeSyntaxError) {
        if (parsed.type === lowerType && /^[a-z][a-z0-9_-]*$/.test(parsed.type))
            addCheck("ok", "Lowercase type");
        else
            addCheck("error", `Type "${parsed.type}" must be lowercase`);
    }

    // 3. Scope format
    if (!parsed.hasScope) {
        addCheck("ok", "Scope format (none)");
    } else if (parsed.scopeError) {
        addCheck("error", `Scope format (${parsed.scopeError})`);
    } else if (parsed.scopeHasUpper) {
        addCheck("warn", `Scope "${parsed.scope}" should be lowercase`);
    } else {
        addCheck("ok", `Scope format (${parsed.scope})`);
    }

    // 4. ": " separator
    if (!parsed.hasColon) {
        addCheck("error", 'Separator ": " missing');
    } else if (parsed.bangBeforeScope) {
        addCheck("error", 'Place "!" after scope, directly before ":"');
    } else if (parsed.spaceBeforeColon) {
        addCheck("error", 'Separator ": " must not have space before ":"');
    } else if (!parsed.hasSpaceAfterColon) {
        addCheck("error", 'Separator ": " requires a space after ":"');
    } else if (parsed.extraSpaceAfterColon) {
        addCheck("warn", 'Extra whitespace after ": "');
    } else {
        addCheck("ok", 'Separator ": "');
    }

    // 5. Non-empty description
    if (parsed.description.length > 0)
        addCheck("ok", "Non-empty description");
    else
        addCheck("error", "Description cannot be empty");

    // 6. Header length (warning)
    if (header.length <= maxHeader)
        addCheck("ok", `Header length (${header.length}/${maxHeader})`);
    else
        addCheck("warn", `Header exceeds ${maxHeader} chars (${header.length})`);

    // 7. No trailing period
    if (parsed.description.length > 0) {
        if (/\.\s*$/.test(parsed.description))
            addCheck("error", "Description must not end with a period");
        else
            addCheck("ok", "No trailing period");

        // 8. Description not starting uppercase (warning)
        if (/^[A-Z]/.test(parsed.description))
            addCheck("warn", "Description starts with uppercase");
        else
            addCheck("ok", "Description starts lowercase");

        // 9. Imperative mood heuristic (warning)
        const imp = ccmtCheckImperative(parsed.description);
        if (imp.ok) {
            addCheck("ok", "Imperative mood");
        } else {
            const hint = imp.suggestion ? ` → "${imp.suggestion}"` : " (use base verb, e.g. \"add\", \"fix\")";
            addCheck("warn", `Use imperative mood for "${imp.word}"${hint}`);
        }
    }

    // 10. Blank line before body / footers
    if (bf.hasAfterHeader) {
        if (bf.missingBlankAfterHeader)
            addCheck("error", "Blank line required after header");
        else
            addCheck("ok", "Blank line after header");

        if (bf.body.length > 0 && bf.footers.length > 0) {
            if (bf.missingBlankBeforeFooters)
                addCheck("error", "Blank line required before footers");
            else
                addCheck("ok", "Blank line before footers");
        }
    }

    if (bf.breakingCaseWarning)
        addCheck("warn", 'Breaking change footer must be uppercase "BREAKING CHANGE:"');

    // 11. revert: referencing a hash
    if (lowerType === "revert") {
        const footerText = bf.footers.map(f => `${f.token}: ${f.value}`).join("\n");
        const combined = `${parsed.description}\n${bf.body}\n${footerText}`;
        const hashMatches = combined.match(/\b[0-9a-f]{7,40}\b/gi) || [];
        let foundHash = "";
        for (let i = 0; i < hashMatches.length; i++) {
            if (/\d/.test(hashMatches[i]) || hashMatches[i].length >= 8) {
                foundHash = hashMatches[i];
                break;
            }
        }
        if (foundHash)
            addCheck("ok", `Revert references commit hash (${foundHash})`);
        else
            addCheck("warn", "Revert should reference a commit hash (e.g. Refs: a1b2c3d)");
    }

    const versionParsed = ccmtParseSemver(options.version);
    let bumpLine = bump;
    if (versionParsed) {
        if (versionParsed.invalid) {
            bumpLine += `  (invalid version "${versionParsed.raw}", expected X.Y.Z)`;
        } else {
            const nextVer = ccmtBumpSemver(versionParsed, bump);
            bumpLine += bump === "none"
                ? `  (${versionParsed.raw} unchanged)`
                : `  (${versionParsed.raw} -> ${nextVer})`;
        }
    }

    const statusLabel = errors > 0
        ? `Invalid (${errors} ${errors === 1 ? "error" : "errors"}, ${warnings} ${warnings === 1 ? "warning" : "warnings"})`
        : (warnings > 0
            ? `Valid with warnings (0 errors, ${warnings} ${warnings === 1 ? "warning" : "warnings"})`
            : "Valid (0 errors, 0 warnings)");

    let breakingDesc = "no";
    if (parsed.bang && hasFooterBreaking)
        breakingDesc = "yes (! in header + footer)";
    else if (parsed.bang)
        breakingDesc = "yes (! in header)";
    else if (hasFooterBreaking)
        breakingDesc = "yes (BREAKING CHANGE footer)";

    const checks = errorChecks.concat(warnChecks, okChecks);
    const out = [
        `Mode         Single commit`,
        `Status       ${statusLabel}`,
        `Semver bump  ${bumpLine}`,
        "",
        "Checklist"
    ];
    for (let i = 0; i < checks.length; i++)
        out.push(checks[i]);

    const pushField = (label, valueLines) => {
        const prefix = `  ${label}${" ".repeat(Math.max(1, 13 - label.length))}`;
        let first = true;
        for (let i = 0; i < valueLines.length; i++) {
            const wrapped = ccmtWrapLine(valueLines[i], 40);
            for (let j = 0; j < wrapped.length; j++) {
                out.push(`${first ? prefix : "               "}${wrapped[j]}`);
                first = false;
            }
        }
    };

    out.push(
        "",
        "Parsed",
        `  Type         ${parsed.type || "(none)"}`,
        `  Scope        ${parsed.hasScope ? (parsed.scope || "(empty)") : "(none)"}`,
        `  Breaking     ${breakingDesc}`
    );
    pushField("Description", [parsed.description || "(empty)"]);

    if (bf.body.length > 0) {
        pushField("Body", bf.body.split("\n"));
    } else {
        out.push("  Body         (none)");
    }

    if (bf.footers.length > 0) {
        const footerLines = [];
        for (let i = 0; i < bf.footers.length; i++) {
            const f = bf.footers[i];
            const valLines = f.value.split("\n");
            const sep = f.separator || ": ";
            footerLines.push(`${f.token}${sep}${valLines[0]}`);
            for (let j = 1; j < valLines.length; j++)
                footerLines.push(valLines[j]);
        }
        pushField("Footers", footerLines);
    } else {
        out.push("  Footers      (none)");
    }

    return {
        output: out.join("\n"),
        meta: { bump, errors, warnings }
    };
}

function ccmtBuildChangelog(rawLines, options, allowedTypes) {
    const nonEmpty = rawLines.filter(l => l.trim().length > 0);
    const buckets = {};
    for (let i = 0; i < CCMT_SECTIONS.length; i++)
        buckets[CCMT_SECTIONS[i].key] = [];
    const customSectionOrder = [];
    const customBuckets = {};
    const otherBucket = [];

    let overallBump = "none";
    let breakingCount = 0;

    for (let idx = 0; idx < nonEmpty.length; idx++) {
        const line = nonEmpty[idx].trim();
        let hash = "";
        let message = line;
        const hashMatch = line.match(/^([0-9a-f]{7,40})\s+(.+)$/);
        if (hashMatch && (/\d/.test(hashMatch[1]) || hashMatch[1].length >= 8)) {
            hash = hashMatch[1];
            message = hashMatch[2].trim();
        }

        const m = message.match(/^([a-z][a-z0-9_-]*)(?:\(([^)\r\n]+)\))?(!)?:\s+(.+)$/);
        if (m && allowedTypes.indexOf(m[1]) !== -1) {
            const type = m[1];
            const scope = (m[2] || "").trim();
            const breaking = m[3] === "!";
            const description = m[4].trim();

            if (breaking) {
                overallBump = "major";
                breakingCount++;
            } else if (type === "feat") {
                overallBump = ccmtMaxBump(overallBump, "minor");
            } else if (type === "fix") {
                overallBump = ccmtMaxBump(overallBump, "patch");
            }

            const entry = { scope, description, hash, index: idx };
            if (breaking) {
                buckets.breaking.push(entry);
            } else if (CCMT_TYPE_TO_SECTION[type]) {
                buckets[CCMT_TYPE_TO_SECTION[type]].push(entry);
            } else {
                const customKey = "custom_" + type;
                if (!customBuckets[customKey]) {
                    customBuckets[customKey] = {
                        title: type.charAt(0).toUpperCase() + type.slice(1),
                        items: []
                    };
                    customSectionOrder.push(customKey);
                }
                customBuckets[customKey].items.push(entry);
            }
        } else {
            otherBucket.push({ scope: "", description: message, hash, index: idx });
        }
    }

    const sortEntries = list => list.slice().sort((a, b) => {
        const aHas = a.scope.length > 0;
        const bHas = b.scope.length > 0;
        if (aHas !== bHas)
            return aHas ? -1 : 1;
        if (aHas && bHas) {
            const sa = a.scope.toLowerCase();
            const sb = b.scope.toLowerCase();
            if (sa < sb) return -1;
            if (sa > sb) return 1;
        }
        return a.index - b.index;
    });

    const formatEntry = item => {
        const scopePart = item.scope ? `**${item.scope}:** ` : "";
        const hashPart = item.hash ? ` (${item.hash})` : "";
        return `- ${scopePart}${item.description}${hashPart}`;
    };

    const versionParsed = ccmtParseSemver(options.version);
    let summary = `Suggested bump: **${overallBump}** (${nonEmpty.length} commits)`;
    let nextVer = "";
    if (versionParsed) {
        if (versionParsed.invalid) {
            summary = `Suggested bump: **${overallBump}** (${nonEmpty.length} commits) · Invalid version "${versionParsed.raw}"`;
        } else {
            nextVer = ccmtBumpSemver(versionParsed, overallBump);
            summary = overallBump === "none"
                ? `Suggested bump: **none** · Next version: **${nextVer}** (unchanged, ${nonEmpty.length} commits)`
                : `Suggested bump: **${overallBump}** · Next version: **${nextVer}** (from ${versionParsed.raw}, ${nonEmpty.length} commits)`;
        }
    }

    const out = ["## Changelog", "", summary];
    const appendSection = (title, items) => {
        if (items.length === 0)
            return;
        out.push("", `### ${title}`);
        const sorted = sortEntries(items);
        for (let i = 0; i < sorted.length; i++)
            out.push(formatEntry(sorted[i]));
    };

    for (let i = 0; i < CCMT_SECTIONS.length; i++) {
        const sec = CCMT_SECTIONS[i];
        appendSection(sec.title, buckets[sec.key]);
    }
    for (let i = 0; i < customSectionOrder.length; i++) {
        const custom = customBuckets[customSectionOrder[i]];
        appendSection(custom.title, custom.items);
    }
    appendSection("Other", otherBucket);

    const meta = { bump: overallBump, commits: nonEmpty.length };
    if (nextVer)
        meta.next = nextVer;
    else if (breakingCount > 0)
        meta.breaking = breakingCount;

    return {
        output: out.join("\n"),
        meta
    };
}

function ccmtCommitLint(input = "", options = {}) {
    const text = String(input ?? "");
    const lines = text.split(/\r?\n/);
    let first = 0;
    let last = lines.length - 1;
    while (first <= last && lines[first].trim().length === 0)
        first++;
    while (last >= first && lines[last].trim().length === 0)
        last--;
    if (first > last)
        return { output: "" };

    const trimmedLines = lines.slice(first, last + 1);
    const allowedTypes = ccmtParseTypesOption(options.types);

    if (ccmtDetectMultiMode(trimmedLines, allowedTypes))
        return ccmtBuildChangelog(trimmedLines, options, allowedTypes);

    return ccmtLintSingle(trimmedLines, options, allowedTypes);
}
// @slot-end commit_lint

// @slot-begin regex_explainer
// ─── Regex Explainer (ES2024 text parser & analyzer) ──────────────────────────

const RXE_FLAG_INFO = [
    ["g", "global", "find all matches (don't stop at first)"],
    ["i", "ignoreCase", "case-insensitive matching"],
    ["m", "multiline", "^ and $ match start/end of each line"],
    ["s", "dotAll", "dot (.) matches newlines as well"],
    ["u", "unicode", "full Unicode (\\p{}, \\u{}, strict)"],
    ["v", "unicodeSets", "Unicode sets (nested [], &&, --, \\q{})"],
    ["y", "sticky", "match only at lastIndex"],
    ["d", "hasIndices", "include match indices for captures"]
];

const RXE_SYNTAX_CHARS = "^$\\.*+?()[]{}|/";
const RXE_V_DOUBLE_PUNCT = ["&&", "--", "^^", "!!", "##", "$$", "%%", "**", "++", ",,", "..", "::", ";;", "<<", "==", ">>", "??", "@@", "~~", "``"];
const RXE_V_SINGLE_PUNCT = "()[]{}/-|\\";

function rxeFromCodePoint(cp) {
    if (cp <= 0xffff)
        return String.fromCharCode(cp);
    const u = cp - 0x10000;
    return String.fromCharCode(0xd800 + (u >> 10), 0xdc00 + (u & 0x3ff));
}

function rxeFormatCharPreview(cp) {
    if (cp === 0x20) return "' ' (space)";
    if (cp === 0x09) return "\\t";
    if (cp === 0x0a) return "\\n";
    if (cp === 0x0d) return "\\r";
    if (cp < 0x20 || cp === 0x7f)
        return "U+" + cp.toString(16).toUpperCase().padStart(4, "0");
    return "'" + rxeFromCodePoint(cp) + "'";
}

function rxeIsHexDigit(ch) {
    return (ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f") || (ch >= "A" && ch <= "F");
}

function rxeIsDigit(ch) {
    return ch >= "0" && ch <= "9";
}

function rxeIsWordChar(ch) {
    return (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch === "_";
}

function rxeIsValidGroupNameStart(ch) {
    if (!ch) return false;
    const code = ch.charCodeAt(0);
    return (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch === "_" || ch === "$" || code >= 0x80;
}

function rxeIsValidGroupNamePart(ch) {
    return rxeIsValidGroupNameStart(ch) || rxeIsDigit(ch);
}

function rxeMakeError(message, inputStr, colZeroBased) {
    const col = Math.max(0, Math.min(inputStr.length, colZeroBased));
    const start = Math.max(0, col - 18);
    const end = Math.min(inputStr.length, col + 18);
    const before = (start > 0 ? "..." : "") + inputStr.slice(start, col);
    const after = inputStr.slice(col, end) + (end < inputStr.length ? "..." : "");
    const snippet = col >= inputStr.length
        ? before + "<end>"
        : before + "▸" + after;
    const err = new Error(
        "Syntax error at column " + (col + 1) + ": " + message + " Near: " + snippet
    );
    err.rxeCol = col + 1;
    return err;
}

function rxeExtractLiteral(trimmed) {
    if (trimmed.indexOf("\n") !== -1 || trimmed.indexOf("\r") !== -1)
        throw rxeMakeError("Regex input must be a single line (bare pattern or /pattern/flags).", trimmed, trimmed.search(/[\r\n]/));

    if (trimmed[0] !== "/") {
        return { pattern: trimmed, flags: "", isLiteral: false, offset: 0 };
    }

    let inClass = false;
    let closeIdx = -1;
    for (let i = 1; i < trimmed.length; i++) {
        const ch = trimmed[i];
        if (ch === "\\") {
            if (i + 1 >= trimmed.length)
                throw rxeMakeError("Trailing backslash in regex literal.", trimmed, i);
            i++;
            continue;
        }
        if (!inClass && ch === "[") {
            inClass = true;
        } else if (inClass && ch === "]") {
            inClass = false;
        } else if (!inClass && ch === "/") {
            closeIdx = i;
            break;
        }
    }

    if (closeIdx === -1)
        throw rxeMakeError("Unterminated regex literal (missing closing '/').", trimmed, 0);

    const pattern = trimmed.slice(1, closeIdx);
    const flags = trimmed.slice(closeIdx + 1);
    const seen = {};
    for (let i = 0; i < flags.length; i++) {
        const f = flags[i];
        let known = false;
        for (let j = 0; j < RXE_FLAG_INFO.length; j++) {
            if (RXE_FLAG_INFO[j][0] === f) {
                known = true;
                break;
            }
        }
        if (!known)
            throw rxeMakeError("Unknown regex flag '" + f + "' (valid flags: g, i, m, s, u, v, y, d).", trimmed, closeIdx + 1 + i);
        if (seen[f])
            throw rxeMakeError("Duplicate regex flag '" + f + "'.", trimmed, closeIdx + 1 + i);
        seen[f] = true;
    }
    if (seen.u && seen.v)
        throw rxeMakeError("Flags 'u' and 'v' cannot be combined.", trimmed, closeIdx + 1 + flags.indexOf("v"));

    return { pattern: pattern, flags: flags, isLiteral: true, offset: 1 };
}

function rxeParsePattern(pattern, flags, fullInput, offset) {
    const flagMap = {};
    for (let i = 0; i < flags.length; i++) flagMap[flags[i]] = true;
    const isUnicode = Boolean(flagMap.u || flagMap.v);
    const isVMode = Boolean(flagMap.v);

    const state = {
        pos: 0,
        len: pattern.length,
        groups: [],
        warnings: [],
        deferredChecks: [],
        seenNamedGroups: {}
    };

    function fail(msg, patPos) {
        throw rxeMakeError(msg, fullInput, offset + patPos);
    }

    function addWarn(level, msg, patPos) {
        state.warnings.push({ level: level, message: msg, col: offset + patPos + 1 });
    }

    function peek(delta) {
        const idx = state.pos + (delta || 0);
        return idx < state.len ? pattern[idx] : "";
    }

    function parseEscape(inClass) {
        const start = state.pos;
        state.pos++; // skip '\'
        if (state.pos >= state.len)
            fail("Trailing backslash '\\'.", start);

        const ch = pattern[state.pos];
        state.pos++;

        // Shorthand character classes
        const shorthands = {
            d: "a digit (0-9)",
            D: "a non-digit",
            w: "a word character (a-z, A-Z, 0-9, _)",
            W: "a non-word character",
            s: "a whitespace character",
            S: "a non-whitespace character"
        };
        if (shorthands[ch]) {
            return {
                kind: "escape",
                escapeKind: "shorthand",
                code: ch,
                desc: shorthands[ch],
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Word boundaries vs backspace inside [...]
        if (ch === "b") {
            if (inClass) {
                return {
                    kind: "escape",
                    escapeKind: "control",
                    code: "b",
                    charCode: 0x08,
                    desc: "backspace (U+0008)",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            return {
                kind: "anchor",
                symbol: "\\b",
                desc: "word boundary",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }
        if (ch === "B" && !inClass) {
            return {
                kind: "anchor",
                symbol: "\\B",
                desc: "non-word boundary",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Standard character escapes
        const charEscapes = {
            n: [0x0a, "newline (LF)"],
            r: [0x0d, "carriage return (CR)"],
            t: [0x09, "tab"],
            f: [0x0c, "form feed"],
            v: [0x0b, "vertical tab"]
        };
        if (charEscapes[ch]) {
            return {
                kind: "escape",
                escapeKind: "control",
                code: ch,
                charCode: charEscapes[ch][0],
                desc: charEscapes[ch][1],
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Null or numeric backreference / octal
        if (ch >= "0" && ch <= "9") {
            let numStr = ch;
            if (ch === "0") {
                if (!rxeIsDigit(peek(0))) {
                    return {
                        kind: "escape",
                        escapeKind: "control",
                        code: "0",
                        charCode: 0,
                        desc: "null character (U+0000)",
                        start: start,
                        end: state.pos,
                        raw: pattern.slice(start, state.pos)
                    };
                }
                while (rxeIsDigit(peek(0))) {
                    numStr += pattern[state.pos++];
                }
                if (isUnicode)
                    fail("Invalid octal escape '\\" + numStr + "' in Unicode mode.", start);
                const octVal = parseInt(numStr, 8);
                addWarn("warn", "Legacy octal escape '\\" + numStr + "' (forbidden in Unicode mode).", start);
                return {
                    kind: "escape",
                    escapeKind: "octal",
                    code: numStr,
                    charCode: octVal,
                    desc: "octal character U+" + octVal.toString(16).toUpperCase().padStart(4, "0"),
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }

            while (rxeIsDigit(peek(0))) {
                numStr += pattern[state.pos++];
            }
            const refNum = parseInt(numStr, 10);
            if (inClass) {
                if (isUnicode)
                    fail("Decimal escape '\\" + numStr + "' is not allowed inside a character class in Unicode mode.", start);
                addWarn("warn", "Legacy decimal escape '\\" + numStr + "' inside character class (not a backreference).", start);
                const octVal = /^[0-7]+$/.test(numStr) ? parseInt(numStr, 8) : null;
                return {
                    kind: "escape",
                    escapeKind: "octal",
                    code: numStr,
                    charCode: octVal,
                    desc: "legacy escape inside character class",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            const node = {
                kind: "escape",
                escapeKind: "backref",
                code: numStr,
                backrefNum: refNum,
                desc: "backreference to capture group #" + refNum,
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
            state.deferredChecks.push(function () {
                if (refNum > state.groups.length) {
                    if (isUnicode)
                        fail("Backreference '\\" + refNum + "' refers to a non-existent group.", start);
                    addWarn("warn", "Backreference '\\" + refNum + "' exceeds capture group count (" + state.groups.length + ").", start);
                }
            });
            return node;
        }

        // Control escape \cX
        if (ch === "c") {
            const ctrl = peek(0);
            if ((ctrl >= "a" && ctrl <= "z") || (ctrl >= "A" && ctrl <= "Z")) {
                state.pos++;
                const cp = ctrl.toUpperCase().charCodeAt(0) - 64;
                return {
                    kind: "escape",
                    escapeKind: "control",
                    code: "c" + ctrl,
                    charCode: cp,
                    desc: "control character Ctrl+" + ctrl.toUpperCase() + " (U+" + cp.toString(16).toUpperCase().padStart(4, "0") + ")",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            if (isUnicode)
                fail("Invalid control escape '\\c' (expected A-Z).", start);
            addWarn("warn", "Incomplete control escape '\\c' (matches literal 'c' in non-Unicode mode).", start);
            return {
                kind: "escape",
                escapeKind: "useless",
                code: "c",
                charCode: 99,
                desc: "literal \"c\" (incomplete \\c escape)",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Hex escape \xHH
        if (ch === "x") {
            if (rxeIsHexDigit(peek(0)) && rxeIsHexDigit(peek(1))) {
                const hex = pattern.slice(state.pos, state.pos + 2);
                state.pos += 2;
                const cp = parseInt(hex, 16);
                return {
                    kind: "escape",
                    escapeKind: "hex",
                    code: "x" + hex,
                    charCode: cp,
                    desc: "hex character U+00" + hex.toUpperCase() + " (" + rxeFormatCharPreview(cp) + ")",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            if (isUnicode)
                fail("Invalid hex escape '\\x' (expected 2 hex digits).", start);
            addWarn("warn", "Incomplete hex escape '\\x' (matches literal 'x' in non-Unicode mode).", start);
            return {
                kind: "escape",
                escapeKind: "useless",
                code: "x",
                charCode: 120,
                desc: "literal \"x\" (incomplete \\x escape)",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Unicode escape \uHHHH or \u{H...}
        if (ch === "u") {
            if (peek(0) === "{") {
                const braceStart = state.pos;
                state.pos++;
                let hex = "";
                while (state.pos < state.len && pattern[state.pos] !== "}") {
                    const hc = pattern[state.pos++];
                    if (!rxeIsHexDigit(hc)) {
                        if (isUnicode)
                            fail("Invalid character in \\u{...} escape.", braceStart);
                        break;
                    }
                    hex += hc;
                }
                if (state.pos >= state.len || pattern[state.pos] !== "}") {
                    if (isUnicode)
                        fail("Unterminated Unicode escape '\\u{...}'.", start);
                    state.pos = braceStart;
                    addWarn("warn", "Useless escape '\\u' (\\u{...} requires the 'u' or 'v' flag).", start);
                    return {
                        kind: "escape",
                        escapeKind: "useless",
                        code: "u",
                        charCode: 117,
                        desc: "literal \"u\" (\\u{...} needs 'u' flag)",
                        start: start,
                        end: state.pos,
                        raw: pattern.slice(start, state.pos)
                    };
                }
                if (hex.length === 0)
                    fail("Empty Unicode escape '\\u{}'.", start);
                state.pos++; // skip '}'
                const cp = parseInt(hex, 16);
                if (cp > 0x10ffff)
                    fail("Unicode code point U+" + hex.toUpperCase() + " exceeds U+10FFFF.", start);
                if (!isUnicode) {
                    // In non-u mode \u{n} is parsed as literal 'u' repeated n times!
                    state.pos = braceStart;
                    addWarn("warn", "\\u{...} requires the 'u' or 'v' flag (without it, \\u matches literal 'u').", start);
                    return {
                        kind: "escape",
                        escapeKind: "useless",
                        code: "u",
                        charCode: 117,
                        desc: "literal \"u\" (\\u{...} needs 'u' flag)",
                        start: start,
                        end: state.pos,
                        raw: pattern.slice(start, state.pos)
                    };
                }
                return {
                    kind: "escape",
                    escapeKind: "unicode",
                    code: "u{" + hex + "}",
                    charCode: cp,
                    desc: "Unicode code point U+" + cp.toString(16).toUpperCase().padStart(4, "0") + " (" + rxeFormatCharPreview(cp) + ")",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }

            if (rxeIsHexDigit(peek(0)) && rxeIsHexDigit(peek(1)) && rxeIsHexDigit(peek(2)) && rxeIsHexDigit(peek(3))) {
                const hex = pattern.slice(state.pos, state.pos + 4);
                state.pos += 4;
                const cp = parseInt(hex, 16);
                return {
                    kind: "escape",
                    escapeKind: "unicode",
                    code: "u" + hex,
                    charCode: cp,
                    desc: "Unicode character U+" + hex.toUpperCase() + " (" + rxeFormatCharPreview(cp) + ")",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            if (isUnicode)
                fail("Invalid Unicode escape '\\u' (expected 4 hex digits or \\u{...}).", start);
            addWarn("warn", "Incomplete Unicode escape '\\u' (matches literal 'u' in non-Unicode mode).", start);
            return {
                kind: "escape",
                escapeKind: "useless",
                code: "u",
                charCode: 117,
                desc: "literal \"u\" (incomplete \\u escape)",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Unicode property escape \p{...} or \P{...}
        if (ch === "p" || ch === "P") {
            const propNegated = ch === "P";
            if (peek(0) !== "{") {
                if (isUnicode)
                    fail("Expected '{...}' after '\\" + ch + "'.", start);
                addWarn("warn", "Useless escape '\\" + ch + "' (\\p{...} requires 'u' or 'v' flag).", start);
                return {
                    kind: "escape",
                    escapeKind: "useless",
                    code: ch,
                    charCode: ch.charCodeAt(0),
                    desc: "literal \"" + ch + "\" (useless escape)",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            state.pos++; // skip '{'
            const propStart = state.pos;
            while (state.pos < state.len && pattern[state.pos] !== "}") state.pos++;
            if (state.pos >= state.len)
                fail("Unterminated Unicode property escape '\\" + ch + "{...}'.", start);
            const propName = pattern.slice(propStart, state.pos);
            if (propName.length === 0)
                fail("Empty Unicode property escape '\\" + ch + "{}'.", start);
            if (!/^[A-Za-z0-9_=]+$/.test(propName))
                fail("Invalid Unicode property name '" + propName + "'.", propStart);
            state.pos++; // skip '}'
            if (!isUnicode) {
                addWarn("warn", "\\" + ch + "{" + propName + "} requires the 'u' or 'v' flag (otherwise matches literal '" + ch + "').", start);
            }
            return {
                kind: "escape",
                escapeKind: "unicodeProp",
                code: ch + "{" + propName + "}",
                propNegated: propNegated,
                propName: propName,
                desc: (propNegated ? "not " : "") + "Unicode property " + propName,
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // v-mode string disjunction \q{a|b} inside [...]
        if (ch === "q" && inClass && isVMode) {
            if (peek(0) !== "{")
                fail("Expected '{...}' after '\\q' in v-mode character class.", start);
            state.pos++;
            const qStart = state.pos;
            while (state.pos < state.len && pattern[state.pos] !== "}") {
                if (pattern[state.pos] === "\\") state.pos++;
                state.pos++;
            }
            if (state.pos >= state.len)
                fail("Unterminated '\\q{...}' string literal set.", start);
            const body = pattern.slice(qStart, state.pos);
            state.pos++;
            const parts = body.split("|");
            return {
                kind: "escape",
                escapeKind: "vStringSet",
                code: "q{" + body + "}",
                parts: parts,
                desc: "string literal set {" + parts.map(function (p) { return "\"" + p + "\""; }).join(", ") + "}",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Named backreference \k<name>
        if (ch === "k" && !inClass) {
            if (peek(0) === "<") {
                state.pos++; // skip '<'
                const nameStart = state.pos;
                while (state.pos < state.len && pattern[state.pos] !== ">") state.pos++;
                if (state.pos >= state.len)
                    fail("Unterminated named backreference '\\k<...>'.", start);
                const refName = pattern.slice(nameStart, state.pos);
                if (refName.length === 0)
                    fail("Empty group name in '\\k<>'.", start);
                state.pos++; // skip '>'
                state.deferredChecks.push(function () {
                    if (!state.seenNamedGroups[refName])
                        fail("Named backreference '\\k<" + refName + ">' refers to an unknown group.", start);
                });
                return {
                    kind: "escape",
                    escapeKind: "namedBackref",
                    code: "k<" + refName + ">",
                    backrefName: refName,
                    desc: "backreference to group '" + refName + "'",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            if (isUnicode)
                fail("Expected '<name>' after '\\k' in Unicode mode.", start);
            addWarn("warn", "Useless escape '\\k' (matches literal 'k').", start);
            return {
                kind: "escape",
                escapeKind: "useless",
                code: "k",
                charCode: 107,
                desc: "literal \"k\" (useless escape)",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Syntax escapes vs useless identity escapes
        const isSyntax = inClass
            ? (ch === "]" || ch === "\\" || ch === "^" || ch === "-" || (isVMode && RXE_V_SINGLE_PUNCT.indexOf(ch) !== -1))
            : RXE_SYNTAX_CHARS.indexOf(ch) !== -1;

        if (isSyntax) {
            return {
                kind: "escape",
                escapeKind: "syntax",
                code: ch,
                charCode: ch.charCodeAt(0),
                desc: "literal \"" + ch + "\" (escaped)",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        // Non-syntax escape inside [...] like [\.] or [\/]
        const classMildEscapes = ".+*?(){}|/";
        if (inClass && classMildEscapes.indexOf(ch) !== -1 && !isVMode) {
            addWarn("info", "Escaping '\\" + ch + "' inside [...] is unnecessary ('" + ch + "' is literal in character classes).", start);
            return {
                kind: "escape",
                escapeKind: "syntax",
                code: ch,
                charCode: ch.charCodeAt(0),
                desc: "literal \"" + ch + "\" (escaped)",
                start: start,
                end: state.pos,
                raw: pattern.slice(start, state.pos)
            };
        }

        if (isUnicode) {
            if (isVMode && "!#%&,:;<=>@~`".indexOf(ch) !== -1) {
                return {
                    kind: "escape",
                    escapeKind: "syntax",
                    code: ch,
                    charCode: ch.charCodeAt(0),
                    desc: "literal \"" + ch + "\" (escaped)",
                    start: start,
                    end: state.pos,
                    raw: pattern.slice(start, state.pos)
                };
            }
            fail("Invalid escape '\\" + ch + "' in Unicode mode.", start);
        }

        addWarn("warn", "Useless escape '\\" + ch + "' (matches literal '" + ch + "').", start);
        return {
            kind: "escape",
            escapeKind: "useless",
            code: ch,
            charCode: ch.charCodeAt(0),
            desc: "literal \"" + ch + "\" (useless escape)",
            start: start,
            end: state.pos,
            raw: pattern.slice(start, state.pos)
        };
    }

    function parseVClassBody(negated, classStart) {
        const operands = [];
        let op = null; // "&&" | "--" | null

        function readOperand() {
            if (state.pos >= state.len)
                fail("Unclosed character class '['.", classStart);
            if (pattern[state.pos] === "[")
                return parseCharClass();
            if (pattern[state.pos] === "\\")
                return parseEscape(true);

            const ch = pattern[state.pos];
            const two = pattern.slice(state.pos, state.pos + 2);
            if (RXE_V_DOUBLE_PUNCT.indexOf(two) !== -1)
                fail("Unescaped reserved operator '" + two + "' in v-mode character class.", state.pos);
            if (RXE_V_SINGLE_PUNCT.indexOf(ch) !== -1)
                fail("Unescaped '" + ch + "' in v-mode character class.", state.pos);

            const itemStart = state.pos;
            state.pos++;
            return {
                kind: "classChar",
                charCode: ch.charCodeAt(0),
                raw: ch,
                start: itemStart,
                end: state.pos
            };
        }

        while (state.pos < state.len && pattern[state.pos] !== "]") {
            const two = pattern.slice(state.pos, state.pos + 2);
            if (two === "&&" || two === "--") {
                if (operands.length === 0)
                    fail("Missing left operand before '" + two + "' in character class.", state.pos);
                if (op !== null && op !== two)
                    fail("Cannot mix '&&' and '--' in the same character class without brackets.", state.pos);
                op = two;
                state.pos += 2;
                if (state.pos >= state.len || pattern[state.pos] === "]")
                    fail("Missing right operand after '" + two + "' in character class.", state.pos - 2);
                operands.push(readOperand());
                continue;
            }

            if (op !== null)
                fail("Expected '" + op + "' or ']' in v-mode character class.", state.pos);

            const left = readOperand();
            // Check range a-z inside union
            if (pattern[state.pos] === "-" && pattern[state.pos + 1] !== "-" && pattern[state.pos + 1] !== "]" && state.pos + 1 < state.len) {
                if (left.charCode === undefined || left.kind === "charClass")
                    fail("Invalid range start in character class.", left.start);
                const dashPos = state.pos;
                state.pos++; // skip '-'
                const right = readOperand();
                if (right.charCode === undefined || right.kind === "charClass")
                    fail("Invalid range end in character class.", dashPos);
                if (left.charCode > right.charCode)
                    fail("Character class range out of order: " + left.raw + "-" + right.raw + ".", left.start);
                operands.push({
                    kind: "range",
                    from: left,
                    to: right,
                    start: left.start,
                    end: right.end,
                    raw: pattern.slice(left.start, right.end)
                });
            } else {
                operands.push(left);
            }
        }

        if (state.pos >= state.len || pattern[state.pos] !== "]")
            fail("Unclosed character class '['.", classStart);
        state.pos++; // skip ']'

        const setOp = op === "&&" ? "intersection" : (op === "--" ? "subtraction" : "union");
        return {
            kind: "charClass",
            negated: negated,
            isVMode: true,
            setOp: setOp,
            items: operands,
            start: classStart,
            end: state.pos,
            raw: pattern.slice(classStart, state.pos)
        };
    }

    function parseCharClass() {
        const start = state.pos;
        state.pos++; // skip '['
        let negated = false;
        if (peek(0) === "^") {
            negated = true;
            state.pos++;
        }

        if (isVMode)
            return parseVClassBody(negated, start);

        const items = [];
        while (state.pos < state.len && pattern[state.pos] !== "]") {
            let item;
            if (pattern[state.pos] === "\\") {
                item = parseEscape(true);
            } else {
                const ch = pattern[state.pos];
                const itemStart = state.pos;
                state.pos++;
                item = {
                    kind: "classChar",
                    charCode: ch.charCodeAt(0),
                    raw: ch,
                    start: itemStart,
                    end: state.pos
                };
            }

            // Check for range `a-b`
            if (pattern[state.pos] === "-" && state.pos + 1 < state.len && pattern[state.pos + 1] !== "]") {
                const dashPos = state.pos;
                const isLeftClassEscape = item.kind === "escape" && (item.escapeKind === "shorthand" || item.escapeKind === "unicodeProp");
                state.pos++; // skip '-'
                let right;
                if (pattern[state.pos] === "\\") {
                    right = parseEscape(true);
                } else {
                    const rch = pattern[state.pos];
                    const rStart = state.pos;
                    state.pos++;
                    right = {
                        kind: "classChar",
                        charCode: rch.charCodeAt(0),
                        raw: rch,
                        start: rStart,
                        end: state.pos
                    };
                }
                const isRightClassEscape = right.kind === "escape" && (right.escapeKind === "shorthand" || right.escapeKind === "unicodeProp");
                if (isLeftClassEscape || isRightClassEscape) {
                    if (isUnicode)
                        fail("Invalid character class range involving a character class escape.", dashPos);
                    addWarn("warn", "Hyphen '-' adjacent to a class escape inside [...] is treated as a literal '-'.", dashPos);
                    items.push(item);
                    items.push({ kind: "classChar", charCode: 45, raw: "-", start: dashPos, end: dashPos + 1 });
                    items.push(right);
                    continue;
                }
                if (item.charCode !== undefined && right.charCode !== undefined && item.charCode > right.charCode)
                    fail("Character class range out of order: " + item.raw + "-" + right.raw + ".", item.start);
                items.push({
                    kind: "range",
                    from: item,
                    to: right,
                    start: item.start,
                    end: right.end,
                    raw: pattern.slice(item.start, right.end)
                });
            } else {
                items.push(item);
            }
        }

        if (state.pos >= state.len || pattern[state.pos] !== "]")
            fail("Unclosed character class '['.", start);
        state.pos++; // skip ']'

        if (!negated && items.length === 0)
            addWarn("warn", "Empty character class [] never matches any character.", start);

        return {
            kind: "charClass",
            negated: negated,
            isVMode: false,
            setOp: "union",
            items: items,
            start: start,
            end: state.pos,
            raw: pattern.slice(start, state.pos)
        };
    }

    function parseModifierFlags(start) {
        let addFlags = "";
        let removeFlags = "";
        let seen = {};
        let inRemove = false;

        while (state.pos < state.len && pattern[state.pos] !== ":") {
            const ch = pattern[state.pos];
            if (ch === "-") {
                if (inRemove)
                    fail("Duplicate '-' in modifier group.", state.pos);
                inRemove = true;
                state.pos++;
                continue;
            }
            if (ch !== "i" && ch !== "m" && ch !== "s")
                fail("Invalid modifier flag '" + ch + "' in (?...:) (allowed: i, m, s).", state.pos);
            if (seen[ch])
                fail("Duplicate modifier flag '" + ch + "' in (?...:).", state.pos);
            seen[ch] = true;
            if (inRemove) removeFlags += ch;
            else addFlags += ch;
            state.pos++;
        }
        if (state.pos >= state.len || pattern[state.pos] !== ":")
            fail("Expected ':' in modifier group.", start);
        if (addFlags.length === 0 && removeFlags.length === 0)
            fail("Modifier group '(?" + (inRemove ? "-" : "") + ":...)' has no flags.", start);
        state.pos++; // skip ':'
        return { addFlags: addFlags, removeFlags: removeFlags };
    }

    function parseGroup() {
        const start = state.pos;
        state.pos++; // skip '('
        let groupType = "capture";
        let groupNum = null;
        let groupName = null;
        let addFlags = "";
        let removeFlags = "";

        if (peek(0) === "?") {
            state.pos++; // skip '?'
            const next = peek(0);
            if (next === ":") {
                groupType = "noncapture";
                state.pos++;
            } else if (next === "=") {
                groupType = "lookahead_pos";
                state.pos++;
            } else if (next === "!") {
                groupType = "lookahead_neg";
                state.pos++;
            } else if (next === "<") {
                const after = peek(1);
                if (after === "=") {
                    groupType = "lookbehind_pos";
                    state.pos += 2;
                } else if (after === "!") {
                    groupType = "lookbehind_neg";
                    state.pos += 2;
                } else {
                    groupType = "named";
                    state.pos++; // skip '<'
                    const nameStart = state.pos;
                    if (!rxeIsValidGroupNameStart(peek(0)))
                        fail("Invalid or empty capture group name after '(?<'.", nameStart);
                    while (state.pos < state.len && pattern[state.pos] !== ">") {
                        if (!rxeIsValidGroupNamePart(pattern[state.pos]))
                            fail("Invalid character '" + pattern[state.pos] + "' in capture group name.", state.pos);
                        state.pos++;
                    }
                    if (state.pos >= state.len || pattern[state.pos] !== ">")
                        fail("Unterminated capture group name '(?<...'.", start);
                    groupName = pattern.slice(nameStart, state.pos);
                    state.pos++; // skip '>'
                }
            } else if (next === "i" || next === "m" || next === "s" || next === "-") {
                groupType = "modifier";
                const mods = parseModifierFlags(start);
                addFlags = mods.addFlags;
                removeFlags = mods.removeFlags;
            } else {
                fail("Invalid group syntax '(?" + (next || "") + "'.", start);
            }
        }

        if (groupType === "capture" || groupType === "named") {
            groupNum = state.groups.length + 1;
            const entry = {
                number: groupNum,
                name: groupName,
                start: start,
                end: -1,
                raw: ""
            };
            state.groups.push(entry);
            if (groupName) {
                state.seenNamedGroups[groupName] = (state.seenNamedGroups[groupName] || 0) + 1;
            }
            const body = parseAlternation();
            if (state.pos >= state.len || pattern[state.pos] !== ")")
                fail("Unclosed capture group '('.", start);
            state.pos++;
            entry.end = state.pos;
            entry.raw = pattern.slice(start, state.pos);
            return {
                kind: "group",
                groupType: groupType,
                number: groupNum,
                name: groupName,
                body: body,
                start: start,
                end: state.pos,
                raw: entry.raw
            };
        }

        const body = parseAlternation();
        if (state.pos >= state.len || pattern[state.pos] !== ")")
            fail("Unclosed group '('.", start);
        state.pos++;
        return {
            kind: "group",
            groupType: groupType,
            addFlags: addFlags,
            removeFlags: removeFlags,
            body: body,
            start: start,
            end: state.pos,
            raw: pattern.slice(start, state.pos)
        };
    }

    function parseQuantifier(atom) {
        if (state.pos >= state.len) return atom;
        const qStart = state.pos;
        const ch = pattern[state.pos];
        let min = null;
        let max = null;
        let matched = false;

        if (ch === "*") {
            min = 0; max = null; matched = true; state.pos++;
        } else if (ch === "+") {
            min = 1; max = null; matched = true; state.pos++;
        } else if (ch === "?") {
            min = 0; max = 1; matched = true; state.pos++;
        } else if (ch === "{") {
            const m = pattern.slice(state.pos).match(/^\{(\d+)(?:,(\d*))?\}/);
            if (m) {
                min = parseInt(m[1], 10);
                if (m[2] === undefined) {
                    max = min;
                } else if (m[2] === "") {
                    max = null;
                } else {
                    max = parseInt(m[2], 10);
                }
                if (max !== null && min > max)
                    fail("Quantifier min (" + min + ") cannot exceed max (" + max + ").", qStart);
                matched = true;
                state.pos += m[0].length;
            } else if (isUnicode) {
                fail("Incomplete or invalid quantifier '{...}' in Unicode mode.", qStart);
            } else {
                addWarn("warn", "Unescaped '{' is not a valid quantifier and matches literally; use '\\{' if intended.", qStart);
            }
        }

        if (!matched) return atom;

        // Check if atom is an assertion (cannot be quantified)
        if (atom.kind === "anchor")
            fail("Assertion '" + atom.raw + "' cannot be quantified.", qStart);
        if (atom.kind === "group" && (atom.groupType === "lookahead_pos" || atom.groupType === "lookahead_neg" || atom.groupType === "lookbehind_pos" || atom.groupType === "lookbehind_neg")) {
            if (isUnicode || atom.groupType.indexOf("lookbehind") === 0)
                fail("Lookaround assertion cannot be quantified.", qStart);
            addWarn("warn", "Quantifying a lookahead is Annex B only (syntax error with 'u'/'v' flag).", qStart);
        }

        let lazy = false;
        if (peek(0) === "?") {
            lazy = true;
            state.pos++;
        }

        // Check chained quantifier like a++ or a{2}*
        const nextCh = peek(0);
        if (nextCh === "*" || nextCh === "+" || nextCh === "?" || (nextCh === "{" && /^\{\d+(?:,\d*)?\}/.test(pattern.slice(state.pos))))
            fail("Nothing to repeat (chained quantifier '" + nextCh + "').", state.pos);

        return {
            kind: "quantified",
            atom: atom,
            min: min,
            max: max,
            lazy: lazy,
            quantRaw: pattern.slice(qStart, state.pos),
            start: atom.start,
            end: state.pos,
            raw: pattern.slice(atom.start, state.pos)
        };
    }

    function parseAtom() {
        const ch = peek(0);
        const start = state.pos;

        if (ch === "*" || ch === "+" || ch === "?")
            fail("Nothing to repeat before quantifier '" + ch + "'.", start);
        if (ch === "{") {
            if (/^\{\d+(?:,\d*)?\}/.test(pattern.slice(start)))
                fail("Nothing to repeat before quantifier.", start);
            if (isUnicode)
                fail("Lone '{' is invalid in Unicode mode (escape as '\\{').", start);
            addWarn("warn", "Unescaped '{' matches literally; escape as '\\{' if intended.", start);
            state.pos++;
            return { kind: "literal", text: "{", start: start, end: state.pos, raw: "{" };
        }
        if (ch === "}") {
            if (isUnicode)
                fail("Lone '}' is invalid in Unicode mode (escape as '\\}').", start);
            addWarn("warn", "Unescaped '}' matches literally; escape as '\\}' if intended.", start);
            state.pos++;
            return { kind: "literal", text: "}", start: start, end: state.pos, raw: "}" };
        }
        if (ch === "]") {
            if (isUnicode)
                fail("Lone ']' is invalid in Unicode mode (escape as '\\]').", start);
            addWarn("warn", "Unescaped ']' matches literally; escape as '\\]' if intended.", start);
            state.pos++;
            return { kind: "literal", text: "]", start: start, end: state.pos, raw: "]" };
        }

        if (ch === "^" || ch === "$") {
            state.pos++;
            return {
                kind: "anchor",
                symbol: ch,
                desc: ch === "^"
                    ? (flagMap.m ? "start of line" : "start of string")
                    : (flagMap.m ? "end of line" : "end of string"),
                start: start,
                end: state.pos,
                raw: ch
            };
        }
        if (ch === ".") {
            state.pos++;
            return {
                kind: "dot",
                desc: flagMap.s ? "any character (including newline)" : "any character except newline",
                start: start,
                end: state.pos,
                raw: "."
            };
        }
        if (ch === "\\") {
            return parseQuantifier(parseEscape(false));
        }
        if (ch === "[") {
            return parseQuantifier(parseCharClass());
        }
        if (ch === "(") {
            return parseQuantifier(parseGroup());
        }

        state.pos++;
        return parseQuantifier({
            kind: "literal",
            text: ch,
            start: start,
            end: state.pos,
            raw: ch
        });
    }

    function parseSequence() {
        const start = state.pos;
        const items = [];
        while (state.pos < state.len) {
            const ch = pattern[state.pos];
            if (ch === "|" || ch === ")") break;
            const node = parseAtom();
            // Merge consecutive plain unquantified literals for a clean tree
            if (node.kind === "literal" && items.length > 0 && items[items.length - 1].kind === "literal") {
                const prev = items[items.length - 1];
                prev.text += node.text;
                prev.end = node.end;
                prev.raw = pattern.slice(prev.start, prev.end);
            } else {
                items.push(node);
            }
        }
        return {
            kind: "sequence",
            items: items,
            start: start,
            end: state.pos,
            raw: pattern.slice(start, state.pos)
        };
    }

    function parseAlternation() {
        const start = state.pos;
        const branches = [parseSequence()];
        while (state.pos < state.len && pattern[state.pos] === "|") {
            state.pos++;
            branches.push(parseSequence());
        }
        if (branches.length === 1)
            return branches[0];
        return {
            kind: "alternation",
            branches: branches,
            start: start,
            end: state.pos,
            raw: pattern.slice(start, state.pos)
        };
    }

    const root = parseAlternation();
    if (state.pos < state.len) {
        if (pattern[state.pos] === ")")
            fail("Unmatched closing parenthesis ')'.", state.pos);
        fail("Unexpected character '" + pattern[state.pos] + "'.", state.pos);
    }

    for (let i = 0; i < state.deferredChecks.length; i++)
        state.deferredChecks[i]();

    return {
        root: root,
        groups: state.groups,
        warnings: state.warnings
    };
}

function rxeDescribeQuantifier(node) {
    let part;
    if (node.min === 0 && node.max === null) part = "0 or more times";
    else if (node.min === 1 && node.max === null) part = "1 or more times";
    else if (node.min === 0 && node.max === 1) part = "optional (0 or 1 time)";
    else if (node.min === node.max) part = "exactly " + node.min + (node.min === 1 ? " time" : " times");
    else if (node.max === null) part = node.min + " or more times";
    else part = node.min + " to " + node.max + " times";
    if (node.lazy) part += ", lazy";
    return part;
}

function rxeFormatClassChar(cp) {
    if (cp === 0x20) return "space";
    if (cp === 0x09) return "\\t";
    if (cp === 0x0a) return "\\n";
    if (cp === 0x0d) return "\\r";
    if (cp < 0x20 || cp === 0x7f)
        return "U+" + cp.toString(16).toUpperCase().padStart(4, "0");
    const ch = rxeFromCodePoint(cp);
    if (ch === "," || ch === "'" || ch === "\\") return "'" + ch + "'";
    return ch;
}

function rxeDescribeCharClassItem(item) {
    if (item.kind === "range") {
        const left = item.from.kind === "escape" ? item.from.raw : rxeFormatClassChar(item.from.charCode);
        const right = item.to.kind === "escape" ? item.to.raw : rxeFormatClassChar(item.to.charCode);
        return left + "-" + right;
    }
    if (item.kind === "classChar")
        return rxeFormatClassChar(item.charCode);
    if (item.kind === "escape") {
        if (item.escapeKind === "shorthand") {
            if (item.code === "d") return "digit";
            if (item.code === "D") return "non-digit";
            if (item.code === "w") return "word char";
            if (item.code === "W") return "non-word char";
            if (item.code === "s") return "whitespace";
            if (item.code === "S") return "non-whitespace";
        }
        return item.desc;
    }
    if (item.kind === "charClass")
        return rxeDescribeCharClass(item);
    return item.raw;
}

function rxeHasVSetChildren(node) {
    if (!node || !node.isVMode) return false;
    if (node.setOp !== "union") return true;
    for (let i = 0; i < node.items.length; i++) {
        const it = node.items[i];
        if (it.kind === "charClass" || (it.kind === "escape" && it.escapeKind === "vStringSet"))
            return true;
    }
    return false;
}

function rxeDescribeCharClass(node) {
    if (node.items.length === 0) {
        return node.negated ? "any character (including newline)" : "nothing (empty character class)";
    }
    if (node.isVMode && node.setOp !== "union") {
        const opName = node.setOp === "intersection" ? "intersection (&&)" : "subtraction (--)";
        const parts = node.items.map(rxeDescribeCharClassItem);
        return (node.negated ? "anything EXCEPT " : "") + opName + ": " + parts.join(node.setOp === "intersection" ? " & " : " - ");
    }
    const parts = node.items.map(rxeDescribeCharClassItem);
    const prefix = node.negated ? "any character EXCEPT: " : "any of: ";
    if (parts.length <= 6)
        return prefix + parts.join(", ");
    return prefix + parts.slice(0, 5).join(", ") + ", ... (" + parts.length + " items)";
}

function rxeFormatLiteralText(text) {
    const escaped = text
        .replace(/\\/g, "\\\\")
        .replace(/"/g, "\\\"")
        .replace(/\t/g, "\\t");
    if (text === " ") return "literal \" \" (space)";
    return "literal \"" + escaped + "\"";
}

function rxeDescribeGroupHeader(group) {
    switch (group.groupType) {
    case "capture":
        return "capture group #" + group.number;
    case "named":
        return "capture group #" + group.number + " \"" + group.name + "\"";
    case "noncapture":
        return "non-capturing group";
    case "lookahead_pos":
        return "positive lookahead (followed by)";
    case "lookahead_neg":
        return "negative lookahead (not followed by)";
    case "lookbehind_pos":
        return "positive lookbehind (preceded by)";
    case "lookbehind_neg":
        return "negative lookbehind (not preceded by)";
    case "modifier": {
        const parts = [];
        if (group.addFlags) parts.push("enable " + group.addFlags);
        if (group.removeFlags) parts.push("disable " + group.removeFlags);
        return "modifier group (" + parts.join(", ") + ")";
    }
    default:
        return "group";
    }
}

function rxeCollectTreeRows(astRoot, showSpans) {
    const rows = [];

    function pushRow(depth, fragment, desc, node) {
        const span = showSpans && node ? " [" + node.start + ":" + node.end + "]" : "";
        rows.push({
            left: "  ".repeat(depth) + fragment,
            right: desc + span
        });
    }

    function walk(node, depth, quantSuffix) {
        if (!node) return;

        if (node.kind === "quantified") {
            const qDesc = rxeDescribeQuantifier(node);
            if (node.atom.kind === "group") {
                const g = node.atom;
                let desc = rxeDescribeGroupHeader(g) + ", " + qDesc;
                if (g.body.kind === "alternation")
                    desc += " (" + g.body.branches.length + " alternatives)";
                pushRow(depth, node.raw, desc, node);
                walkGroupBody(g.body, depth + 1);
            } else {
                walk(node.atom, depth, ", " + qDesc, node);
            }
            return;
        }

        if (node.kind === "alternation") {
            if (depth === 0) {
                pushRow(0, node.raw, "alternation (" + node.branches.length + " alternatives)", node);
                walkGroupBody(node, 1);
            } else {
                walkGroupBody(node, depth);
            }
            return;
        }

        if (node.kind === "sequence") {
            if (node.items.length === 0) {
                pushRow(depth, "(empty)", "empty match", node);
                return;
            }
            for (let i = 0; i < node.items.length; i++)
                walk(node.items[i], depth, "");
            return;
        }

        if (node.kind === "group") {
            let desc = rxeDescribeGroupHeader(node);
            if (node.body.kind === "alternation")
                desc += " (" + node.body.branches.length + " alternatives)";
            pushRow(depth, node.raw, desc, node);
            walkGroupBody(node.body, depth + 1);
            return;
        }

        if (node.kind === "charClass") {
            pushRow(depth, node.raw, rxeDescribeCharClass(node) + (quantSuffix || ""), node);
            if (rxeHasVSetChildren(node)) {
                for (let i = 0; i < node.items.length; i++) {
                    const it = node.items[i];
                    if (it.kind === "charClass" || (it.kind === "escape" && it.escapeKind === "vStringSet"))
                        walkNode(it, depth + 1);
                }
            }
            return;
        }

        if (node.kind === "literal") {
            pushRow(depth, node.raw, rxeFormatLiteralText(node.text) + (quantSuffix || ""), node);
            return;
        }

        if (node.kind === "anchor" || node.kind === "dot" || node.kind === "escape") {
            pushRow(depth, node.raw, node.desc + (quantSuffix || ""), node);
        }
    }

    // Separate optional third arg in walk(node, depth, quantSuffix, outerNode)
    function walkQuantAtom(atom, depth, quantSuffix, outerNode) {
        const frag = outerNode ? outerNode.raw : atom.raw;
        const spanNode = outerNode || atom;
        if (atom.kind === "charClass") {
            pushRow(depth, frag, rxeDescribeCharClass(atom) + quantSuffix, spanNode);
            if (rxeHasVSetChildren(atom)) {
                for (let i = 0; i < atom.items.length; i++) {
                    const it = atom.items[i];
                    if (it.kind === "charClass" || (it.kind === "escape" && it.escapeKind === "vStringSet"))
                        walkNode(it, depth + 1);
                }
            }
        } else if (atom.kind === "literal")
            pushRow(depth, frag, rxeFormatLiteralText(atom.text) + quantSuffix, spanNode);
        else
            pushRow(depth, frag, atom.desc + quantSuffix, spanNode);
    }

    // Override quantified leaf dispatch cleanly
    function walkNode(node, depth) {
        if (!node) return;
        if (node.kind === "quantified") {
            const qDesc = rxeDescribeQuantifier(node);
            if (node.atom.kind === "group") {
                const g = node.atom;
                let desc = rxeDescribeGroupHeader(g) + ", " + qDesc;
                if (g.body.kind === "alternation")
                    desc += " (" + g.body.branches.length + " alternatives)";
                pushRow(depth, node.raw, desc, node);
                walkGroupBody(g.body, depth + 1);
            } else {
                walkQuantAtom(node.atom, depth, ", " + qDesc, node);
            }
            return;
        }
        walk(node, depth, "");
    }

    function walkGroupBody(body, depth) {
        if (body.kind === "alternation") {
            for (let i = 0; i < body.branches.length; i++) {
                if (i > 0)
                    pushRow(depth, "|", "or", null);
                const br = body.branches[i];
                if (br.items.length === 0)
                    pushRow(depth, "(empty)", "empty alternative (matches empty string)", br);
                else {
                    for (let j = 0; j < br.items.length; j++)
                        walkNode(br.items[j], depth);
                }
            }
            return;
        }
        if (body.kind === "sequence") {
            if (body.items.length === 0) {
                pushRow(depth, "(empty)", "empty group", body);
            } else {
                for (let i = 0; i < body.items.length; i++)
                    walkNode(body.items[i], depth);
            }
        }
    }

    if (astRoot.kind === "alternation") {
        pushRow(0, astRoot.raw, "alternation (" + astRoot.branches.length + " alternatives)", astRoot);
        walkGroupBody(astRoot, 1);
    } else if (astRoot.kind === "sequence") {
        if (astRoot.items.length === 0) {
            pushRow(0, "(empty)", "empty pattern (matches empty string)", astRoot);
        } else {
            for (let i = 0; i < astRoot.items.length; i++)
                walkNode(astRoot.items[i], 0);
        }
    } else {
        walkNode(astRoot, 0);
    }

    return rows;
}

// ─── Static Analysis / Warnings ──────────────────────────────────────────────

function rxeIsUnboundedQuant(qNode) {
    if (!qNode || qNode.kind !== "quantified") return false;
    return qNode.max === null || (qNode.max - qNode.min >= 4);
}

function rxeIsNullable(node) {
    if (!node) return true;
    if (node.kind === "empty" || node.kind === "anchor") return true;
    if (node.kind === "quantified") return node.min === 0 || rxeIsNullable(node.atom);
    if (node.kind === "sequence") {
        for (let i = 0; i < node.items.length; i++) {
            if (!rxeIsNullable(node.items[i])) return false;
        }
        return true;
    }
    if (node.kind === "alternation") {
        for (let i = 0; i < node.branches.length; i++) {
            if (rxeIsNullable(node.branches[i])) return true;
        }
        return false;
    }
    if (node.kind === "group") {
        if (node.groupType.indexOf("look") === 0) return true;
        return rxeIsNullable(node.body);
    }
    return false;
}

// Coarse character-set summary for overlap / disjointness heuristics
function rxeCharProfile(node) {
    const p = {
        any: false,
        broadDigits: false,
        broadLower: false,
        broadUpper: false,
        broadUnder: false,
        broadSpace: false,
        broadNonWord: false,
        chars: {}
    };
    function mergeInto(dst, src) {
        if (src.any) dst.any = true;
        if (src.broadDigits) dst.broadDigits = true;
        if (src.broadLower) dst.broadLower = true;
        if (src.broadUpper) dst.broadUpper = true;
        if (src.broadUnder) dst.broadUnder = true;
        if (src.broadSpace) dst.broadSpace = true;
        if (src.broadNonWord) dst.broadNonWord = true;
        for (const k in src.chars) dst.chars[k] = true;
    }
    if (!node) return p;
    if (node.kind === "quantified") return rxeCharProfile(node.atom);
    if (node.kind === "dot") { p.any = true; return p; }
    if (node.kind === "literal") {
        if (node.text.length > 0) p.chars[node.text[0]] = true;
        return p;
    }
    if (node.kind === "escape") {
        if (node.escapeKind === "shorthand") {
            if (node.code === "d") p.broadDigits = true;
            else if (node.code === "w") { p.broadDigits = true; p.broadLower = true; p.broadUpper = true; p.broadUnder = true; }
            else if (node.code === "s") p.broadSpace = true;
            else if (node.code === "D") { p.broadLower = true; p.broadUpper = true; p.broadUnder = true; p.broadSpace = true; p.broadNonWord = true; }
            else if (node.code === "W") { p.broadSpace = true; p.broadNonWord = true; }
            else if (node.code === "S") { p.broadDigits = true; p.broadLower = true; p.broadUpper = true; p.broadUnder = true; p.broadNonWord = true; }
        } else if (node.escapeKind === "unicodeProp") {
            p.any = true;
        } else if (node.charCode !== undefined) {
            p.chars[rxeFromCodePoint(node.charCode)] = true;
        } else {
            p.any = true;
        }
        return p;
    }
    if (node.kind === "charClass") {
        if (node.negated) { p.any = true; return p; }
        for (let i = 0; i < node.items.length; i++) {
            const it = node.items[i];
            if (it.kind === "range") {
                const a = it.from.charCode;
                const b = it.to.charCode;
                if (b - a <= 64) {
                    for (let c = a; c <= b; c++)
                        p.chars[rxeFromCodePoint(c)] = true;
                } else {
                    if (a <= 57 && b >= 48) p.broadDigits = true;
                    if (a <= 122 && b >= 97) p.broadLower = true;
                    if (a <= 90 && b >= 65) p.broadUpper = true;
                    if (a <= 95 && b >= 95) p.broadUnder = true;
                    p.broadNonWord = true;
                }
            } else {
                const sub = rxeCharProfile(it.kind === "classChar" ? { kind: "literal", text: it.raw } : it);
                mergeInto(p, sub);
            }
        }
        return p;
    }
    if (node.kind === "sequence") {
        for (let i = 0; i < node.items.length; i++) {
            const item = node.items[i];
            if (item.kind === "anchor") continue;
            mergeInto(p, rxeCharProfile(item));
            if (!rxeIsNullable(item)) break;
        }
        return p;
    }
    if (node.kind === "group") return rxeCharProfile(node.body);
    if (node.kind === "alternation") {
        for (let i = 0; i < node.branches.length; i++)
            mergeInto(p, rxeCharProfile(node.branches[i]));
        return p;
    }
    return p;
}

function rxeBroadMatchesChar(p, ch) {
    if (ch >= "0" && ch <= "9") return p.broadDigits;
    if (ch >= "a" && ch <= "z") return p.broadLower;
    if (ch >= "A" && ch <= "Z") return p.broadUpper;
    if (ch === "_") return p.broadUnder;
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r" || ch === "\f" || ch === "\v") return p.broadSpace;
    return p.broadNonWord;
}

function rxeProfilesOverlap(a, b) {
    if (a.any || b.any) return true;
    for (const k in a.chars) {
        if (b.chars[k] || rxeBroadMatchesChar(b, k)) return true;
    }
    for (const k in b.chars) {
        if (rxeBroadMatchesChar(a, k)) return true;
    }
    if (a.broadDigits && b.broadDigits) return true;
    if (a.broadLower && b.broadLower) return true;
    if (a.broadUpper && b.broadUpper) return true;
    if (a.broadUnder && b.broadUnder) return true;
    if (a.broadSpace && b.broadSpace) return true;
    if (a.broadNonWord && b.broadNonWord) return true;
    return false;
}

function rxeAnalyzeWarnings(astRoot, flags, baseWarnings, offset) {
    const warnings = baseWarnings.slice();
    const seenMsg = {};
    let hasNamedGroup = false;
    let hasLookbehind = false;
    let hasModifierGroup = false;

    function add(level, message, patPos) {
        const key = level + ":" + message;
        if (seenMsg[key]) return;
        seenMsg[key] = true;
        warnings.push({
            level: level,
            message: message,
            col: patPos !== undefined ? offset + patPos + 1 : null
        });
    }

    for (let i = 0; i < warnings.length; i++)
        seenMsg[warnings[i].level + ":" + warnings[i].message] = true;

    function seqHasMandatoryDisjointTail(items, fromIdx, prevNode) {
        const prevProfile = rxeCharProfile(prevNode);
        for (let i = fromIdx + 1; i < items.length; i++) {
            const next = items[i];
            if (next.kind === "anchor") continue;
            if (rxeIsNullable(next)) continue;
            const nextProfile = rxeCharProfile(next);
            if (!rxeProfilesOverlap(prevProfile, nextProfile))
                return true;
            return false;
        }
        return false;
    }

    function containsUnboundedQuantWithoutDisjointTail(node) {
        if (!node) return false;
        if (node.kind === "quantified") {
            if (rxeIsUnboundedQuant(node)) return true;
            return containsUnboundedQuantWithoutDisjointTail(node.atom);
        }
        if (node.kind === "group") {
            if (node.groupType.indexOf("look") === 0) return false;
            return containsUnboundedQuantWithoutDisjointTail(node.body);
        }
        if (node.kind === "alternation") {
            for (let i = 0; i < node.branches.length; i++) {
                if (containsUnboundedQuantWithoutDisjointTail(node.branches[i])) return true;
            }
            return false;
        }
        if (node.kind === "sequence") {
            for (let i = 0; i < node.items.length; i++) {
                const it = node.items[i];
                if (containsUnboundedQuantWithoutDisjointTail(it)) {
                    if (!seqHasMandatoryDisjointTail(node.items, i, it))
                        return true;
                }
            }
            return false;
        }
        return false;
    }

    function checkOverlappingAlternation(altNode) {
        for (let i = 0; i < altNode.branches.length; i++) {
            for (let j = i + 1; j < altNode.branches.length; j++) {
                const pA = rxeCharProfile(altNode.branches[i]);
                const pB = rxeCharProfile(altNode.branches[j]);
                if (rxeProfilesOverlap(pA, pB)) return true;
            }
        }
        return false;
    }

    function visit(node, underOuterQuant) {
        if (!node) return;

        if (node.kind === "quantified") {
            const unbounded = rxeIsUnboundedQuant(node);
            if (unbounded && node.atom.kind === "group") {
                const g = node.atom;
                if (containsUnboundedQuantWithoutDisjointTail(g.body)) {
                    add("warn", "Nested quantifiers in '" + node.raw + "' can cause catastrophic backtracking (ReDoS).", node.start);
                } else if (g.body.kind === "alternation" && checkOverlappingAlternation(g.body)) {
                    add("warn", "Overlapping alternation branches under quantifier '" + node.raw + "' can backtrack catastrophically.", node.start);
                }
            }
            visit(node.atom, underOuterQuant || unbounded);
            return;
        }

        if (node.kind === "group") {
            if (node.groupType === "named") hasNamedGroup = true;
            if (node.groupType === "lookbehind_pos" || node.groupType === "lookbehind_neg") hasLookbehind = true;
            if (node.groupType === "modifier") hasModifierGroup = true;
            visit(node.body, underOuterQuant);
            return;
        }

        if (node.kind === "alternation") {
            for (let i = 0; i < node.branches.length; i++) {
                const br = node.branches[i];
                if (br.items.length === 0)
                    add("warn", "Empty alternative in '" + node.raw + "' matches the empty string.", br.start);
                visit(br, underOuterQuant);
            }
            return;
        }

        if (node.kind === "sequence") {
            for (let i = 0; i < node.items.length; i++) {
                const item = node.items[i];
                // Detect unescaped '.' between word characters (e.g., example.com, v1.2)
                if (item.kind === "dot") {
                    const prev = i > 0 ? node.items[i - 1] : null;
                    const next = i + 1 < node.items.length ? node.items[i + 1] : null;
                    const prevWord = prev && prev.kind === "literal" && prev.text.length > 0 && rxeIsWordChar(prev.text[prev.text.length - 1]);
                    const nextWord = next && next.kind === "literal" && next.text.length > 0 && rxeIsWordChar(next.text[0]);
                    if (prevWord && nextWord) {
                        const snippet = prev.text.slice(-12) + "." + next.text.slice(0, 12);
                        add("warn", "Unescaped '.' in '" + snippet + "' matches any character; use '\\.' for a literal dot.", item.start);
                    }
                }
                visit(item, underOuterQuant);
            }
        }
    }

    visit(astRoot, false);

    if (hasNamedGroup)
        add("info", "Named capture groups (?<name>...) require ES2018+ (modern JS/PCRE engines).");
    if (hasLookbehind)
        add("info", "Lookbehind assertions (?<=... / ?<!...) require ES2018+ (modern JS/Safari 16.4+).");
    if (hasModifierGroup)
        add("info", "Inline modifier groups (?ims:...) require ES2025+.");
    if (flags.indexOf("v") !== -1)
        add("info", "Flag 'v' (unicodeSets) requires ES2024+.");
    if (flags.indexOf("d") !== -1)
        add("info", "Flag 'd' (hasIndices) requires ES2022+.");

    return warnings;
}

const RXE_PAGE_LINE_MAX = 58;

function rxeWrapTextWithPrefix(firstPrefix, contIndent, text, maxWidth) {
    const out = [];
    const words = text.split(" ");
    const indentStr = " ".repeat(contIndent);
    let line = firstPrefix;
    let hasWord = false;
    for (let i = 0; i < words.length; i++) {
        const w = words[i];
        if (!hasWord) {
            line += w;
            hasWord = true;
        } else if (line.length + 1 + w.length <= maxWidth) {
            line += " " + w;
        } else {
            out.push(line);
            line = indentStr + w;
        }
    }
    if (hasWord)
        out.push(line);
    else if (firstPrefix.length > 0)
        out.push(firstPrefix);
    return out;
}

function rxeFormatTreeRow(left, right, padWidth, maxWidth) {
    const gapLen = left.length < padWidth ? padWidth - left.length : 2;
    const prefix = left + " ".repeat(gapLen);
    if (prefix.length + right.length <= maxWidth)
        return [prefix + right];
    if (left.length + 2 > padWidth) {
        const lines = [left];
        const wrapped = rxeWrapTextWithPrefix(" ".repeat(padWidth), padWidth, right, maxWidth);
        for (let i = 0; i < wrapped.length; i++)
            lines.push(wrapped[i]);
        return lines;
    }
    return rxeWrapTextWithPrefix(prefix, padWidth, right, maxWidth);
}

function rxeToolRegexExplainer(input = "", options = {}) {
    const raw = String(input ?? "");
    const trimmed = raw.trim();
    if (trimmed.length === 0)
        return { output: "" };

    let extracted;
    let parsed;
    try {
        extracted = rxeExtractLiteral(trimmed);
        parsed = rxeParsePattern(extracted.pattern, extracted.flags, trimmed, extracted.offset);
    } catch (err) {
        return { output: "", error: err.message };
    }

    const view = options.view || "full";
    const showSpans = Boolean(options.showSpans);
    const warnings = rxeAnalyzeWarnings(parsed.root, extracted.flags, parsed.warnings, extracted.offset);
    const out = [];

    if (view !== "summary") {
        const rows = rxeCollectTreeRows(parsed.root, showSpans);
        let padWidth = 16;
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].left.length <= 18 && rows[i].left.length + 2 > padWidth)
                padWidth = rows[i].left.length + 2;
        }
        for (let i = 0; i < rows.length; i++) {
            const formatted = rxeFormatTreeRow(rows[i].left, rows[i].right, padWidth, RXE_PAGE_LINE_MAX);
            for (let j = 0; j < formatted.length; j++)
                out.push(formatted[j]);
        }
    }

    if (view !== "tree") {
        if (extracted.flags.length > 0) {
            if (out.length > 0) out.push("");
            out.push("Flags");
            for (let i = 0; i < extracted.flags.length; i++) {
                const f = extracted.flags[i];
                for (let j = 0; j < RXE_FLAG_INFO.length; j++) {
                    if (RXE_FLAG_INFO[j][0] === f) {
                        const prefix = "  " + f + "  " + RXE_FLAG_INFO[j][1].padEnd(13);
                        const wrapped = rxeWrapTextWithPrefix(prefix, 18, RXE_FLAG_INFO[j][2], RXE_PAGE_LINE_MAX);
                        for (let k = 0; k < wrapped.length; k++)
                            out.push(wrapped[k]);
                        break;
                    }
                }
            }
        }

        if (parsed.groups.length > 0) {
            if (out.length > 0) out.push("");
            out.push("Groups");
            let numW = 1;
            let nameW = 4;
            for (let i = 0; i < parsed.groups.length; i++) {
                const g = parsed.groups[i];
                const ns = "#" + g.number;
                if (ns.length > numW) numW = ns.length;
                const nm = g.name || "-";
                if (nm.length > nameW) nameW = nm.length;
            }
            out.push("  " + "#".padEnd(numW + 2) + "Name".padEnd(nameW + 2) + "Fragment");
            for (let i = 0; i < parsed.groups.length; i++) {
                const g = parsed.groups[i];
                out.push("  " + ("#" + g.number).padEnd(numW + 2) + (g.name || "-").padEnd(nameW + 2) + g.raw);
            }
        }

        if (warnings.length > 0) {
            if (out.length > 0) out.push("");
            out.push("Warnings");
            for (let i = 0; i < warnings.length; i++) {
                const w = warnings[i];
                const tag = w.level === "info" ? "[info]" : "[warn]";
                const prefix = "  " + tag + " ";
                const text = w.message + (w.col ? " (col\u00a0" + w.col + ")" : "");
                const wrapped = rxeWrapTextWithPrefix(prefix, 9, text, RXE_PAGE_LINE_MAX);
                for (let k = 0; k < wrapped.length; k++)
                    out.push(wrapped[k].replace(/\u00a0/g, " "));
            }
        }
    }

    let warnCount = 0;
    for (let i = 0; i < warnings.length; i++) {
        if (warnings[i].level !== "info") warnCount++;
    }

    return {
        output: out.join("\n"),
        meta: {
            groups: parsed.groups.length,
            flags: extracted.flags.length > 0 ? extracted.flags : "none",
            warnings: warnCount
        }
    };
}
// @slot-end regex_explainer

// @slot-begin log_formatter
const LOGF_LEVEL_INFO = {
    trace: { rank: 0, tag: "TRC " },
    debug: { rank: 1, tag: "DBG " },
    info:  { rank: 2, tag: "INFO" },
    warn:  { rank: 3, tag: "WARN" },
    error: { rank: 4, tag: "ERR " }
};

const LOGF_FILTER_MIN = {
    all:   0,
    debug: 1,
    info:  2,
    warn:  3,
    error: 4
};

const LOGF_TOKEN_TO_LEVEL = {
    ERROR: "error",
    ERR: "error",
    FATAL: "error",
    CRITICAL: "error",
    CRIT: "error",
    PANIC: "error",
    WARN: "warn",
    WARNING: "warn",
    INFO: "info",
    DEBUG: "debug",
    DBG: "debug",
    TRACE: "trace",
    TRC: "trace"
};

const LOGF_MONTHS = {
    jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
    jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11
};

function logfStripAnsi(text) {
    return text
        .replace(/\r\n|\r/g, "\n")
        .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
        .replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "")
        .replace(/\x1b[@-_a-zA-Z0-9]/g, "")
        .replace(/\x9b[0-9;?]*[@-~]/g, "");
}

function logfSubMs(frac) {
    if (!frac) return 0;
    const padded = (frac + "000").slice(0, 3);
    return parseInt(padded, 10) || 0;
}

function logfParseTzOffsetMs(tz) {
    if (!tz || tz === "Z" || tz === "z") return 0;
    const m = tz.match(/^([+-])(\d{2}):?(\d{2})$/);
    if (!m) return 0;
    const sign = m[1] === "-" ? -1 : 1;
    const mins = (parseInt(m[2], 10) * 60) + parseInt(m[3], 10);
    return sign * mins * 60000;
}

function logfParseTimestamp(line) {
    const trimmed = line.replace(/^\s+/, "");
    if (!trimmed) return null;

    // 1. ISO 8601 (with optional brackets)
    let m = trimmed.match(/^(\[?)(\d{4})[-/](\d{2})[-/](\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:[.,](\d{1,9}))?(Z|[+-]\d{2}:?\d{2})?(\]?)(?:\s+|(?=\[)|$)/);
    if (m) {
        const openB = m[1] === "[";
        const closeB = m[10] === "]";
        if (openB === closeB) {
            const yr = parseInt(m[2], 10);
            const mo = parseInt(m[3], 10);
            const da = parseInt(m[4], 10);
            const hh = parseInt(m[5], 10);
            const mm = parseInt(m[6], 10);
            const ss = parseInt(m[7], 10);
            if (mo >= 1 && mo <= 12 && da >= 1 && da <= 31 && hh <= 23 && mm <= 59 && ss <= 59) {
                const sub = logfSubMs(m[8]);
                const tzMs = logfParseTzOffsetMs(m[9]);
                const ms = Date.UTC(yr, mo - 1, da, hh, mm, ss, sub) - tzMs;
                const raw = trimmed.slice(0, m[0].length).trim();
                const display = raw.replace(/^\[/, "").replace(/\]$/, "");
                return {
                    ms,
                    raw,
                    display,
                    rest: trimmed.slice(m[0].length),
                    hasDate: true,
                    isTimeOnly: false
                };
            }
        }
    }

    // 2. Syslog timestamp: Nov 24 15:04:50(.mmm)
    m = trimmed.match(/^(\[?)(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})(?:[.,](\d{1,6}))?(\]?)(?:\s+|(?=\[)|$)/i);
    if (m) {
        const openB = m[1] === "[";
        const closeB = m[8] === "]";
        if (openB === closeB) {
            const mo = LOGF_MONTHS[m[2].toLowerCase()];
            const da = parseInt(m[3], 10);
            const hh = parseInt(m[4], 10);
            const mm = parseInt(m[5], 10);
            const ss = parseInt(m[6], 10);
            if (mo !== undefined && da >= 1 && da <= 31 && hh <= 23 && mm <= 59 && ss <= 59) {
                const sub = logfSubMs(m[7]);
                const ms = Date.UTC(2024, mo, da, hh, mm, ss, sub);
                const raw = trimmed.slice(0, m[0].length).trim();
                const display = raw.replace(/^\[/, "").replace(/\]$/, "");
                return {
                    ms,
                    raw,
                    display,
                    rest: trimmed.slice(m[0].length),
                    hasDate: true,
                    isTimeOnly: false,
                    isSyslog: true,
                    syslogMonth: mo,
                    syslogDay: da,
                    syslogTimeMs: ((hh * 3600) + (mm * 60) + ss) * 1000 + sub
                };
            }
        }
    }

    // 3. Epoch ms or s in brackets: [1732460690123] or [1732460690] or [1732460690.123]
    m = trimmed.match(/^\[(\d{13}|\d{10}(?:\.\d{1,6})?)\](?:\s+|$)/);
    if (m) {
        const token = m[1];
        const ms = token.indexOf(".") === -1 && token.length === 13
            ? parseInt(token, 10)
            : Math.round(parseFloat(token) * 1000);
        const raw = trimmed.slice(0, m[0].length).trim();
        return {
            ms,
            raw,
            display: logfFormatIsoUtc(ms),
            rest: trimmed.slice(m[0].length),
            hasDate: true,
            isTimeOnly: false
        };
    }

    // 4. Time-only: HH:MM:SS(.mmm)
    m = trimmed.match(/^(\[?)(\d{2}):(\d{2}):(\d{2})(?:[.,](\d{1,6}))?(\]?)(?:\s+|(?=\[)|$)/);
    if (m) {
        const openB = m[1] === "[";
        const closeB = m[6] === "]";
        if (openB === closeB) {
            const hh = parseInt(m[2], 10);
            const mm = parseInt(m[3], 10);
            const ss = parseInt(m[4], 10);
            if (hh <= 23 && mm <= 59 && ss <= 59) {
                const sub = logfSubMs(m[5]);
                const ms = ((hh * 3600) + (mm * 60) + ss) * 1000 + sub;
                const raw = trimmed.slice(0, m[0].length).trim();
                const display = raw.replace(/^\[/, "").replace(/\]$/, "");
                return {
                    ms,
                    raw,
                    display,
                    rest: trimmed.slice(m[0].length),
                    hasDate: false,
                    isTimeOnly: true
                };
            }
        }
    }

    return null;
}

function logfFormatIsoUtc(ms) {
    const d = new Date(ms);
    const pad2 = n => String(n).padStart(2, "0");
    const pad3 = n => String(n).padStart(3, "0");
    return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())} ${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}:${pad2(d.getUTCSeconds())}.${pad3(d.getUTCMilliseconds())}Z`;
}

function logfFormatDuration(ms) {
    if (ms < 0) ms = 0;
    if (ms < 1000) return `${Math.round(ms)}ms`;
    if (ms < 60000) {
        const s = (ms / 1000).toFixed(2).replace(/\.?0+$/, "");
        return `${s}s`;
    }
    const totalSec = Math.floor(ms / 1000);
    const d = Math.floor(totalSec / 86400);
    const h = Math.floor((totalSec % 86400) / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    const parts = [];
    if (d > 0) parts.push(`${d}d`);
    if (h > 0) parts.push(`${h}h`);
    if (m > 0) parts.push(`${m}m`);
    if (s > 0 && d === 0) parts.push(`${s}s`);
    return parts.join(" ") || "0s";
}

function logfParseLevelToken(word) {
    return LOGF_TOKEN_TO_LEVEL[String(word || "").toUpperCase()] || null;
}

function logfParseLevel(text, hadTimestamp) {
    const trimmed = text.replace(/^\s+/, "");
    if (!trimmed) return null;

    // Bracketed or parenthesized: [WARN], (error), [ INFO ]:
    let m = trimmed.match(/^[\[\(]\s*(ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|WARNING|WARN|INFO|DEBUG|DBG|TRACE|TRC)\s*[\]\)]\s*[:\-|]?\s*(.*)$/i);
    if (m) {
        return { level: logfParseLevelToken(m[1]), rest: m[2], explicit: true };
    }

    // Colon/dash/pipe form: ERROR: msg, warn: msg, INFO - msg
    // Preserve mixed-case "Error: ..." / "Panic: ..." / Go "panic: ..." text as an exception message.
    m = trimmed.match(/^(ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|WARNING|WARN|INFO|DEBUG|DBG|TRACE|TRC)\s*([:\-|])\s*(.*)$/i);
    if (m) {
        const rawTok = m[1];
        const lvl = logfParseLevelToken(rawTok);
        if ((rawTok === "Error" || rawTok === "Panic" || rawTok === "panic") && m[2] === ":") {
            return { level: lvl, rest: trimmed, explicit: true };
        }
        return { level: lvl, rest: m[3], explicit: true };
    }

    // All-caps standalone level word followed by whitespace: INFO msg, WARN scene: msg
    m = trimmed.match(/^(ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|WARNING|WARN|INFO|DEBUG|DBG|TRACE|TRC)(?:\s+(.*)|$)$/);
    if (m) {
        return { level: logfParseLevelToken(m[1]), rest: m[2] ?? "", explicit: true };
    }

    // Lowercase/mixed standalone level word immediately after a timestamp
    if (hadTimestamp) {
        m = trimmed.match(/^(error|err|fatal|critical|crit|panic|warning|warn|info|debug|dbg|trace|trc)(?:\s+(.*)|$)$/i);
        if (m) {
            return { level: logfParseLevelToken(m[1]), rest: m[2] ?? "", explicit: true };
        }
    }

    // Syslog host proc[pid]: LEVEL ...
    m = trimmed.match(/^((?:[A-Za-z0-9_.-]+\s+)?[A-Za-z0-9_.\/-]+(?:\[\d+\])?:\s*)(.*)$/);
    if (m) {
        const prefix = m[1];
        const after = m[2];
        const inner = after.match(/^(?:[\[\(]\s*(ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|WARNING|WARN|INFO|DEBUG|DBG|TRACE|TRC)\s*[\]\)]|(ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|WARNING|WARN|INFO|DEBUG|DBG|TRACE|TRC)\b)\s*[:\-|]?\s*(.*)$/i);
        if (inner) {
            const lvl = logfParseLevelToken(inner[1] || inner[2]);
            return { level: lvl, rest: prefix + (inner[3] || ""), explicit: true };
        }
    }

    // Logfmt key=value: level=warn / lvl=error / severity=info
    m = trimmed.match(/\b(?:level|lvl|severity)=["']?(error|err|fatal|critical|crit|panic|warning|warn|info|debug|dbg|trace|trc)["']?\b/i);
    if (m) {
        return { level: logfParseLevelToken(m[1]), rest: trimmed, explicit: true };
    }

    return null;
}

function logfIsLibraryFrame(file, fnName) {
    const f = String(file || "").toLowerCase();
    const fn = String(fnName || "").toLowerCase();
    if (!f || f === "<anonymous>" || f === "native" || f === "unknown source" || f === "native method") {
        return true;
    }
    // JS / Node
    if (f.indexOf("node_modules/") !== -1 || f.indexOf("node_modules\\") !== -1 || f.indexOf("node:internal/") === 0 || f.indexOf("internal/") === 0 || f.indexOf("node:") === 0) {
        return true;
    }
    // Python
    if (f.indexOf("site-packages/") !== -1 || f.indexOf("site-packages\\") !== -1 || f.indexOf("dist-packages/") !== -1 || f.indexOf("/lib/python") !== -1 || f.indexOf("\\lib\\python") !== -1 || f.indexOf("<frozen ") === 0) {
        return true;
    }
    // Java / Kotlin
    if (/^(?:java\.|javax\.|jakarta\.|sun\.|jdk\.|java\.base\/|kotlin\.|kotlinx\.|org\.springframework\.|org\.apache\.|io\.netty\.|org\.hibernate\.|org\.junit\.)/.test(fn)) {
        return true;
    }
    // Rust
    if (f.indexOf("/rustc/") !== -1 || f.indexOf("library/std/") !== -1 || f.indexOf("library/core/") !== -1 || f.indexOf("library/alloc/") !== -1 || f.indexOf(".cargo/registry/") !== -1) {
        return true;
    }
    if (/^(?:std::|core::|alloc::|tokio::|rust_begin_unwind)/.test(fn)) {
        return true;
    }
    // Go
    if (f.indexOf("/usr/local/go/src/") !== -1 || f.indexOf("/usr/lib/go/") !== -1 || f.indexOf("/pkg/mod/") !== -1 || fn.indexOf("runtime.") === 0 || fn.indexOf("runtime/") === 0) {
        return true;
    }
    // QML / Qt
    if (f.indexOf("qrc:/qt/") === 0 || f.indexOf("qrc:/qt") === 0 || f.indexOf("/usr/lib/qt6/") !== -1 || f.indexOf("/usr/lib64/qt6/") !== -1) {
        return true;
    }
    return false;
}

function logfFormatFileLine(file, line) {
    let clean = String(file || "").trim();
    if (clean.indexOf("file:///") === 0) {
        clean = clean.slice(7);
    } else if (clean.indexOf("file://") === 0) {
        clean = clean.slice(7);
    }
    if (clean.length > 42) {
        const sep = clean.indexOf("\\") !== -1 && clean.indexOf("/") === -1 ? "\\" : "/";
        const parts = clean.split(sep).filter(p => p.length > 0);
        if (parts.length > 2) {
            clean = "..." + sep + parts[parts.length - 2] + sep + parts[parts.length - 1];
        }
    }
    return line !== undefined && line !== null ? `${clean}:${line}` : clean;
}

function logfMatchQmlLocation(text) {
    const m = text.match(/((?:file:\/\/|qrc:\/)[^\s:\[]+\.qml)(?:\[(\d+):(\d+)\]|(?::(\d+)(?::(\d+))?)):\s*(.+)$/);
    if (!m) return null;
    const file = m[1];
    const line = m[2] || m[4] || "1";
    const detail = m[6].trim();
    let exceptionType = "QML Warning";
    let exceptionMsg = detail;
    const errMatch = detail.match(/^([A-Z][A-Za-z0-9_]*Error):\s*(.*)$/);
    if (errMatch) {
        exceptionType = errMatch[1];
        exceptionMsg = errMatch[2];
    } else if (/unavailable|cannot|failed|error/i.test(detail)) {
        exceptionType = "QML Error";
    }
    return {
        file,
        line,
        detail,
        exceptionType,
        exceptionMsg,
        isError: Boolean(errMatch) || /unavailable/i.test(detail),
        isLib: logfIsLibraryFrame(file, "")
    };
}

function logfMatchQmlStackFrame(trimmed) {
    let m = trimmed.match(/^([^\s(]+(?:\s+for\s+[^\s(]+)?)\s+\(((?:file:\/\/|qrc:\/)[^\s:()]+\.qml):(\d+)(?::(\d+))?\)$/);
    if (m) {
        return { fn: m[1], file: m[2], line: m[3], raw: trimmed, isLib: logfIsLibraryFrame(m[2], m[1]) };
    }
    m = trimmed.match(/^((?:file:\/\/|qrc:\/)[^\s:\[]+\.qml)(?:\[(\d+):(\d+)\]|(?::(\d+)(?::(\d+))?))(?::\s*(.*))?$/);
    if (m) {
        return { fn: "", file: m[1], line: m[2] || m[4] || "1", raw: trimmed, isLib: logfIsLibraryFrame(m[1], "") };
    }
    return null;
}

function logfMatchJsOrJavaFrame(trimmed) {
    // Java / Kotlin: at a.b.C.m(C.java:12) or (Unknown Source) / (Native Method)
    let m = trimmed.match(/^at\s+([A-Za-z0-9_.$<>\/-]+)\(([^():\s]+\.(?:java|kt|kts|scala|groovy)):(\d+)\)$/);
    if (m) {
        return { kind: "java", fn: m[1], file: m[2], line: m[3], raw: trimmed, isLib: logfIsLibraryFrame(m[2], m[1]) };
    }
    m = trimmed.match(/^at\s+([A-Za-z0-9_.$<>\/-]+)\((Unknown Source|Native Method)\)$/);
    if (m) {
        return { kind: "java", fn: m[1], file: m[2], line: null, raw: trimmed, isLib: true };
    }

    // JavaScript: at fn (file:line:col) or at file:line:col
    m = trimmed.match(/^at\s+(?:(.+?)\s+\()?((?:file:\/\/|node:|[A-Za-z]:\\|\/|\.{0,2}\/|[^()\s]+?)[^()\s]*):(\d+):(\d+)\)?$/);
    if (m) {
        const fn = (m[1] || "").trim();
        const file = m[2];
        return { kind: "js", fn, file, line: m[3], raw: trimmed, isLib: logfIsLibraryFrame(file, fn) };
    }
    m = trimmed.match(/^at\s+(?:(.+?)\s+\()?(?:<anonymous>|native)(?:\))?$/);
    if (m) {
        return { kind: "js", fn: (m[1] || "").trim(), file: "<anonymous>", line: null, raw: trimmed, isLib: true };
    }
    return null;
}

function logfMatchExceptionHeader(trimmed) {
    // Uncaught JS/browser exception header: Uncaught TypeError: ..., Uncaught (in promise) Error: ...
    let m = trimmed.match(/^Uncaught\s+(?:\([^)]+\)\s+)?([A-Za-z0-9_.]+)(?::\s*(.*))?$/);
    if (m) {
        return { kind: "js", exceptionType: "Uncaught " + m[1], exceptionMsg: m[2] || "", noAttach: true };
    }
    // Java Exception header: Exception in thread "main" java.lang.NullPointerException: msg
    m = trimmed.match(/^Exception in thread\s+"[^"]+"\s+([A-Za-z0-9_.$]+(?:\.[A-Za-z0-9_$]+)*)(?::\s*(.*))?$/);
    if (m) {
        return { kind: "java", exceptionType: m[1], exceptionMsg: m[2] || "", noAttach: true };
    }
    // JavaScript / generic Error header: TypeError: ..., ReferenceError: ..., Error: ...
    m = trimmed.match(/^([A-Z][A-Za-z0-9_]+(?:Error|Exception)|(?:Error|Exception)(?=:))(?::\s*(.*))?$/);
    if (m) {
        return { kind: "js", exceptionType: m[1], exceptionMsg: m[2] || "" };
    }
    // Tagged QML/JS error line without explicit log level: qml: ReferenceError: ..., scene: TypeError: ...
    m = trimmed.match(/^(?:[a-z_][a-z0-9_.-]*:\s+)(ReferenceError|TypeError|SyntaxError|RangeError)(?::\s*(.*))?$/);
    if (m) {
        return { kind: "qml", exceptionType: m[1], exceptionMsg: m[2] || "", noAttach: true };
    }
    // Java FQN Exception/Error: java.lang.IllegalStateException: msg
    m = trimmed.match(/^([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+\.[A-Z][A-Za-z0-9_$]*(?:Exception|Error))(?::\s*(.*))?$/);
    if (m) {
        return { kind: "java", exceptionType: m[1], exceptionMsg: m[2] || "" };
    }
    return null;
}

function logfMatchRustPanic(trimmed) {
    const m = trimmed.match(/^thread\s+'([^']+)'\s+panicked\s+at\s+(?:'([^']*)',\s*)?([^\s:]+):(\d+)(?::(\d+))?:?$/);
    if (!m) return null;
    return {
        thread: m[1],
        msg: m[2] !== undefined ? m[2] : "",
        file: m[3],
        line: m[4],
        isLib: logfIsLibraryFrame(m[3], "")
    };
}

function logfMatchGoStart(trimmed) {
    let m = trimmed.match(/^(panic|fatal error):\s*(.+)$/);
    if (m) {
        return { kind: "panic", exceptionType: m[1] === "fatal error" ? "Fatal Error" : "Panic", exceptionMsg: m[2] };
    }
    m = trimmed.match(/^goroutine\s+\d+\s+\[[^\]]+\]:$/);
    if (m) {
        return { kind: "goroutine", exceptionType: "Panic", exceptionMsg: trimmed };
    }
    return null;
}

function logfPickTopFrame(trace) {
    if (!trace || !trace.frames || trace.frames.length === 0) return null;
    const frames = trace.frames;
    if (trace.kind === "python") {
        // Python prints most-recent call last.
        for (let i = frames.length - 1; i >= 0; i--) {
            if (!frames[i].isLib && frames[i].line !== null) return frames[i];
        }
        for (let i = frames.length - 1; i >= 0; i--) {
            if (frames[i].line !== null) return frames[i];
        }
        return frames[frames.length - 1];
    }
    for (let i = 0; i < frames.length; i++) {
        if (!frames[i].isLib && frames[i].line !== null) return frames[i];
    }
    for (let i = 0; i < frames.length; i++) {
        if (frames[i].line !== null) return frames[i];
    }
    return frames[0];
}

function logfFormatTraceSummary(trace, index) {
    const type = trace.exceptionType || "Error";
    const msg = trace.exceptionMsg || "";
    const title = msg
        ? (msg.indexOf(type) === 0 ? msg : `${type}: ${msg}`)
        : type;
    const top = logfPickTopFrame(trace);
    const loc = top ? logfFormatFileLine(top.file, top.line) : "unknown";
    const libNote = top && top.isLib && top.line !== null ? " (internal)" : "";
    const clippedTitle = title.length > 60 ? title.slice(0, 57) + "..." : title;
    return `${index + 1}. ${clippedTitle}  @ ${loc}${libNote}`;
}

function logfParseEntries(rawText) {
    const cleaned = logfStripAnsi(rawText);
    const rawLines = cleaned.split("\n");
    while (rawLines.length > 0 && rawLines[rawLines.length - 1].trim() === "") rawLines.pop();
    while (rawLines.length > 0 && rawLines[0].trim() === "") rawLines.shift();

    const entries = [];
    const traces = [];
    const timestamps = [];
    let nonEmptyLines = 0;
    let prevLevel = "info";
    let activeTrace = null; // { entry, kind, state, ... }

    const finishActiveTrace = () => {
        if (!activeTrace) return;
        const tr = activeTrace.trace;
        if (tr.kind === "python" && !activeTrace.attachedToParent && tr.exceptionType) {
            activeTrace.entry.message = tr.exceptionMsg
                ? `${tr.exceptionType}: ${tr.exceptionMsg}`
                : tr.exceptionType;
        }
        prevLevel = "info";
        activeTrace = null;
    };

    const pushEntry = (level, message, tsObj, traceObj, preserveIndent, updatePrevLevel) => {
        const entry = {
            level,
            message: preserveIndent ? message : message.trim(),
            timestamp: tsObj ? tsObj.display : null,
            trace: traceObj || null,
            count: 1
        };
        entries.push(entry);
        if (updatePrevLevel !== false) {
            prevLevel = level;
        }
        if (traceObj) traces.push(traceObj);
        return entry;
    };

    for (let i = 0; i < rawLines.length; i++) {
        const line = rawLines[i];
        const trimmed = line.trim();
        if (trimmed.length === 0) {
            if (activeTrace && activeTrace.trace.kind === "go" && activeTrace.waitingGoroutine) {
                activeTrace.trace.lines.push("");
                continue;
            }
            finishActiveTrace();
            continue;
        }
        nonEmptyLines++;

        // 1. Inside an active Python traceback
        if (activeTrace && activeTrace.trace.kind === "python") {
            const tr = activeTrace.trace;
            if (/^(?:During handling of the above exception|The above exception was the direct cause)/.test(trimmed)
                || /^Traceback \(most recent call last\):$/.test(trimmed)) {
                tr.lines.push(trimmed);
                activeTrace.expectCode = false;
                continue;
            }
            const fileMatch = trimmed.match(/^File\s+"(.+?)",\s+line\s+(\d+)(?:,\s+in\s+(.+))?$/);
            if (fileMatch) {
                const frame = {
                    kind: "python",
                    file: fileMatch[1],
                    line: fileMatch[2],
                    fn: fileMatch[3] || "",
                    raw: trimmed,
                    codeLines: [],
                    isLib: logfIsLibraryFrame(fileMatch[1], fileMatch[3] || "")
                };
                tr.frames.push(frame);
                tr.lines.push(trimmed);
                activeTrace.expectCode = true;
                continue;
            }
            if (/^\s+/.test(line) && activeTrace.expectCode && tr.frames.length > 0) {
                tr.frames[tr.frames.length - 1].codeLines.push(trimmed);
                tr.lines.push("  " + trimmed);
                continue;
            }
            // Final Python exception line (non-indented, no timestamp, not a log level line)
            const isLogLevelLine = /^(?:[\[\(]\s*(?:ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|WARNING|WARN|INFO|DEBUG|DBG|TRACE|TRC)\s*[\]\)]|(?:ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|WARNING|WARN|INFO|DEBUG|DBG|TRACE|TRC)(?:[:\-|\s]|$))/i.test(trimmed)
                && !/^(?:Error|Warning):/.test(trimmed);
            if (!logfParseTimestamp(line) && !isLogLevelLine) {
                const exc = trimmed.match(/^((?:[a-z_][a-z0-9_]*\.)*[A-Z][A-Za-z0-9_]*):\s*(.*)$/)
                    || trimmed.match(/^((?:[a-z_][a-z0-9_]*\.)*[A-Z][A-Za-z0-9_]*(?:Error|Exception|Warning|Exit|Interrupt|Iteration))$/);
                if (exc) {
                    tr.exceptionType = exc[1];
                    tr.exceptionMsg = exc[2] || "";
                    if (activeTrace.attachedToParent) {
                        tr.lines.push(trimmed);
                    }
                    finishActiveTrace();
                    continue;
                }
            }
            finishActiveTrace();
        }

        // 2. Inside an active Rust panic
        if (activeTrace && activeTrace.trace.kind === "rust") {
            const tr = activeTrace.trace;
            if (/^stack backtrace:$/.test(trimmed)) {
                tr.inBacktrace = true;
                tr.lines.push(trimmed);
                continue;
            }
            if (tr.inBacktrace) {
                const numM = trimmed.match(/^(\d+):\s+(.+)$/);
                if (numM) {
                    tr.pendingFn = numM[2];
                    tr.lines.push(trimmed);
                    continue;
                }
                const atM = trimmed.match(/^at\s+([^\s:]+):(\d+)(?::(\d+))?$/);
                if (atM) {
                    const fn = tr.pendingFn || "";
                    tr.frames.push({
                        kind: "rust",
                        fn,
                        file: atM[1],
                        line: atM[2],
                        raw: (fn ? fn + " @ " : "") + logfFormatFileLine(atM[1], atM[2]),
                        isLib: logfIsLibraryFrame(atM[1], fn)
                    });
                    tr.lines.push("  " + trimmed);
                    tr.pendingFn = null;
                    continue;
                }
                if (/^note:\s+/.test(trimmed)) {
                    tr.lines.push(trimmed);
                    continue;
                }
            } else if (!logfParseTimestamp(line)
                && !logfParseLevel(line, false)
                && !logfMatchRustPanic(trimmed)
                && !logfMatchGoStart(trimmed)
                && !logfMatchExceptionHeader(trimmed)
                && !logfMatchQmlLocation(trimmed)
                && !/^Traceback \(most recent call last\):$/.test(trimmed)) {
                if (!tr.exceptionMsg) {
                    tr.exceptionMsg = trimmed;
                } else {
                    tr.exceptionMsg += " " + trimmed;
                }
                tr.lines.push(trimmed);
                continue;
            }
            finishActiveTrace();
        }

        // 3. Inside an active Go trace
        if (activeTrace && activeTrace.trace.kind === "go") {
            const tr = activeTrace.trace;
            if (/^goroutine\s+\d+\s+\[[^\]]+\]:$/.test(trimmed)) {
                activeTrace.waitingGoroutine = false;
                tr.lines.push(trimmed);
                continue;
            }
            const goFile = line.match(/^\s+([^\s:]+\.go):(\d+)(?:\s+\+0x[0-9a-f]+)?\s*$/);
            if (goFile && tr.pendingGoFn) {
                const fn = tr.pendingGoFn;
                tr.frames.push({
                    kind: "go",
                    fn,
                    file: goFile[1],
                    line: goFile[2],
                    raw: `${fn} (${goFile[1]}:${goFile[2]})`,
                    isLib: logfIsLibraryFrame(goFile[1], fn)
                });
                tr.lines.push("  " + trimmed);
                tr.pendingGoFn = null;
                continue;
            }
            if (!logfParseTimestamp(line) && !logfParseLevel(line, false) && (/^[A-Za-z0-9_.*\/()-]+\([^)]*\)$/.test(trimmed) || /^[A-Za-z0-9_.*\/()-]+\.\.\.$/.test(trimmed) || /^created by\s+/.test(trimmed))) {
                tr.pendingGoFn = trimmed;
                tr.lines.push(trimmed);
                activeTrace.waitingGoroutine = false;
                continue;
            }
            finishActiveTrace();
        }

        // 4. Inside an active JS / Java / QML trace
        if (activeTrace && (activeTrace.trace.kind === "js" || activeTrace.trace.kind === "java" || activeTrace.trace.kind === "qml")) {
            const tr = activeTrace.trace;
            const frame = logfMatchJsOrJavaFrame(trimmed);
            if (frame) {
                if (frame.kind === "java" && tr.kind !== "java") tr.kind = "java";
                tr.frames.push(frame);
                tr.lines.push(trimmed);
                continue;
            }
            if (/^\.\.\.\s+\d+\s+more$/.test(trimmed)) {
                tr.lines.push(trimmed);
                continue;
            }
            const caused = trimmed.match(/^Caused by:\s*(.+)$/);
            if (caused) {
                tr.kind = "java";
                tr.lines.push(trimmed);
                continue;
            }
            const qmlFrame = logfMatchQmlStackFrame(trimmed);
            if (qmlFrame && /^\s+/.test(line)) {
                tr.frames.push(qmlFrame);
                tr.lines.push(trimmed);
                continue;
            }
            finishActiveTrace();
        }

        // Not in an active trace (or just closed one): parse timestamp + level
        let rest = trimmed;
        let tsObj = logfParseTimestamp(line);
        if (tsObj) {
            timestamps.push(tsObj);
            rest = tsObj.rest.trim();
        }

        let lvlObj = logfParseLevel(rest, Boolean(tsObj));
        if (lvlObj) {
            rest = lvlObj.rest.trim();
            // Also strip a timestamp that appeared *after* a level tag: [INFO] 15:04:50 msg
            if (!tsObj) {
                const postTs = logfParseTimestamp(rest);
                if (postTs) {
                    tsObj = postTs;
                    timestamps.push(tsObj);
                    rest = postTs.rest.trim();
                }
            }
        }

        // Check for stack trace starts
        // A. Python Traceback
        if (/^Traceback \(most recent call last\):$/.test(rest)) {
            const prev = entries.length > 0 ? entries[entries.length - 1] : null;
            const canAttach = !tsObj && !lvlObj && prev && !prev.trace && prev.level === "error";
            const traceObj = {
                kind: "python",
                exceptionType: "Traceback",
                exceptionMsg: "",
                frames: [],
                lines: [rest]
            };
            if (canAttach) {
                prev.trace = traceObj;
                traces.push(traceObj);
                activeTrace = { trace: traceObj, entry: prev, attachedToParent: true, expectCode: false };
            } else {
                const entry = pushEntry("error", rest, tsObj, traceObj, false, Boolean(lvlObj));
                activeTrace = { trace: traceObj, entry, attachedToParent: false, expectCode: false };
            }
            continue;
        }

        // B. Rust panic
        const rustPanic = logfMatchRustPanic(rest);
        if (rustPanic) {
            const traceObj = {
                kind: "rust",
                exceptionType: "Panic",
                exceptionMsg: rustPanic.msg,
                frames: [{
                    kind: "rust",
                    fn: `thread '${rustPanic.thread}'`,
                    file: rustPanic.file,
                    line: rustPanic.line,
                    raw: rest,
                    isLib: rustPanic.isLib
                }],
                lines: [],
                inBacktrace: false,
                pendingFn: null
            };
            const entry = pushEntry("error", rest, tsObj, traceObj, false, Boolean(lvlObj));
            activeTrace = { trace: traceObj, entry };
            continue;
        }

        // C. Go panic / goroutine
        const goStart = logfMatchGoStart(rest);
        if (goStart) {
            const traceObj = {
                kind: "go",
                exceptionType: goStart.exceptionType,
                exceptionMsg: goStart.exceptionMsg,
                frames: [],
                lines: goStart.kind === "goroutine" ? [rest] : [],
                pendingGoFn: null
            };
            const entry = pushEntry("error", rest, tsObj, traceObj, false, Boolean(lvlObj));
            activeTrace = { trace: traceObj, entry, waitingGoroutine: goStart.kind === "panic" };
            continue;
        }

        // D. JS / Java bare frame at top level (attach to preceding entry)
        const bareFrame = logfMatchJsOrJavaFrame(rest);
        if (bareFrame && entries.length > 0) {
            const prev = entries[entries.length - 1];
            if (!prev.trace) {
                const hdr = logfMatchExceptionHeader(prev.message);
                const traceObj = {
                    kind: bareFrame.kind,
                    exceptionType: hdr ? hdr.exceptionType : (prev.level === "warn" ? "Warning" : "Error"),
                    exceptionMsg: hdr ? hdr.exceptionMsg : prev.message,
                    frames: [bareFrame],
                    lines: [bareFrame.raw]
                };
                prev.trace = traceObj;
                if (!hdr && prev.level !== "warn") prev.level = "error";
                traces.push(traceObj);
                activeTrace = { trace: traceObj, entry: prev };
                continue;
            }
        }

        // E. Exception header (Uncaught ..., TypeError: ..., Error: ..., Exception in thread ..., java.lang.NullPointerException: ...)
        const isMixedErrorPrefix = Boolean(lvlObj && /^(?:Error|Panic):/.test(rest));
        const excHdr = (!lvlObj || isMixedErrorPrefix) ? logfMatchExceptionHeader(rest) : null;
        if (excHdr) {
            const nextTrimmed = i + 1 < rawLines.length ? rawLines[i + 1].trim() : "";
            const nextIsFrame = Boolean(logfMatchJsOrJavaFrame(nextTrimmed));
            const prev = entries.length > 0 ? entries[entries.length - 1] : null;
            if (!excHdr.noAttach && !isMixedErrorPrefix && !tsObj && nextIsFrame && prev && !prev.trace && prev.level === "error") {
                const traceObj = {
                    kind: excHdr.kind,
                    exceptionType: excHdr.exceptionType,
                    exceptionMsg: excHdr.exceptionMsg,
                    frames: [],
                    lines: [rest]
                };
                prev.trace = traceObj;
                traces.push(traceObj);
                activeTrace = { trace: traceObj, entry: prev };
                continue;
            }
            const entry = pushEntry("error", rest, tsObj, null, false, Boolean(lvlObj));
            if (nextIsFrame) {
                const traceObj = {
                    kind: excHdr.kind,
                    exceptionType: excHdr.exceptionType,
                    exceptionMsg: excHdr.exceptionMsg,
                    frames: [],
                    lines: []
                };
                entry.trace = traceObj;
                traces.push(traceObj);
                activeTrace = { trace: traceObj, entry };
            }
            continue;
        }

        // F. QML / Quickshell location line
        const qml = logfMatchQmlLocation(rest);
        if (qml) {
            const inferred = lvlObj ? lvlObj.level : (qml.isError ? "error" : "warn");
            const traceObj = {
                kind: "qml",
                exceptionType: qml.exceptionType,
                exceptionMsg: qml.exceptionMsg,
                frames: [{
                    kind: "qml",
                    fn: "",
                    file: qml.file,
                    line: qml.line,
                    raw: rest,
                    isLib: qml.isLib
                }],
                lines: [],
                isInlineQml: true
            };
            const entry = pushEntry(inferred, rest, tsObj, traceObj, false, Boolean(lvlObj));
            activeTrace = { trace: traceObj, entry };
            continue;
        }

        // G. Normal log line or continuation line
        let finalLevel = lvlObj ? lvlObj.level : prevLevel;
        if (!lvlObj && entries.length === 0) {
            finalLevel = "info";
        }
        // Preserve leading indentation for non-trace continuation lines
        const isContinuation = !tsObj && !lvlObj && /^\s+/.test(line);
        const msg = isContinuation ? "  " + rest : rest;
        pushEntry(finalLevel, msg, tsObj, null, isContinuation);
    }

    finishActiveTrace();
    return { entries, traces, timestamps, nonEmptyLines };
}

function logfComputeTimeSpan(timestamps) {
    if (!timestamps || timestamps.length === 0) return null;
    // Anchor syslog (yearless) and time-only timestamps to the nearest explicit-year date.
    let anchorYear = null;
    let anchorDayMs = null;
    for (let i = 0; i < timestamps.length; i++) {
        const t = timestamps[i];
        if (t.hasDate && !t.isSyslog) {
            anchorYear = new Date(t.ms).getUTCFullYear();
            anchorDayMs = Math.floor(t.ms / 86400000) * 86400000;
            break;
        }
    }

    let minTs = null;
    let maxTs = null;
    let dayCarry = 0;
    let prevTimeOnlyMs = null;

    for (let i = 0; i < timestamps.length; i++) {
        const t = timestamps[i];
        let effectiveMs = t.ms;
        if (t.isSyslog) {
            const yr = anchorYear !== null ? anchorYear : 2024;
            effectiveMs = Date.UTC(yr, t.syslogMonth, t.syslogDay, 0, 0, 0, 0) + t.syslogTimeMs;
            anchorDayMs = Math.floor(effectiveMs / 86400000) * 86400000;
        } else if (t.hasDate) {
            anchorYear = new Date(t.ms).getUTCFullYear();
            anchorDayMs = Math.floor(t.ms / 86400000) * 86400000;
        } else if (t.isTimeOnly) {
            if (prevTimeOnlyMs !== null && t.ms + dayCarry < prevTimeOnlyMs - 43200000) {
                dayCarry += 86400000;
            }
            const todMs = t.ms + dayCarry;
            prevTimeOnlyMs = todMs;
            effectiveMs = anchorDayMs !== null ? anchorDayMs + todMs : todMs;
        }
        if (!minTs || effectiveMs < minTs.ms) minTs = { display: t.display, ms: effectiveMs };
        if (!maxTs || effectiveMs > maxTs.ms) maxTs = { display: t.display, ms: effectiveMs };
    }

    const spanMs = Math.max(0, maxTs.ms - minTs.ms);
    if (timestamps.length === 1) {
        return `${minTs.display} (single entry)`;
    }
    return `${minTs.display} -> ${maxTs.display} (${logfFormatDuration(spanMs)})`;
}

function logfFormatTraceBody(trace, framesOnly) {
    if (!trace) return [];
    if (!framesOnly) {
        return trace.lines.slice();
    }
    if (trace.isInlineQml && trace.lines.length === 0) {
        return [];
    }
    const out = [];
    const top = logfPickTopFrame(trace);
    if ((trace.kind === "js" || trace.kind === "java") && trace.lines.length > 0 && logfMatchExceptionHeader(trace.lines[0])) {
        out.push(trace.lines[0]);
    }
    if (top) {
        if (trace.kind === "python") {
            out.push(top.raw);
        } else if (trace.kind === "rust") {
            if (trace.exceptionMsg) out.push(trace.exceptionMsg);
            out.push(`at ${logfFormatFileLine(top.file, top.line)}${top.isLib ? " (internal)" : ""}`);
        } else {
            out.push(top.raw + (top.isLib ? " (internal)" : ""));
        }
    }
    if (trace.kind === "python" && trace.lines.length > 0) {
        const lastLine = trace.lines[trace.lines.length - 1];
        if (trace.exceptionType && lastLine.indexOf(trace.exceptionType) === 0) {
            out.push(lastLine);
        }
    }
    return out;
}

function logfFormat(input = "", options = {}) {
    const raw = input === null || input === undefined ? "" : String(input);
    const levelOpt = String(options.level ?? "all").toLowerCase();
    if (LOGF_FILTER_MIN[levelOpt] === undefined) {
        return { output: "", error: `Unknown level filter "${levelOpt}". Use all, debug, info, warn or error.` };
    }
    if (raw.trim().length === 0) {
        return { output: "" };
    }
    const strippedCheck = logfStripAnsi(raw).trim();
    if (strippedCheck.length === 0) {
        return { output: "" };
    }

    const stripTimestamps = options.stripTimestamps !== false;
    const collapse = options.collapse !== false;
    const framesOnly = Boolean(options.framesOnly);
    const minRank = LOGF_FILTER_MIN[levelOpt];

    const parsed = logfParseEntries(raw);
    const entries = parsed.entries;
    const traces = parsed.traces;

    const counts = { error: 0, warn: 0, info: 0, debug: 0, trace: 0 };
    let firstError = null;
    const msgFreq = {};
    const msgOrder = [];

    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        counts[e.level] = (counts[e.level] || 0) + 1;
        if (e.level === "error" && firstError === null) {
            firstError = e.message;
        }
        const freqKey = `${e.level}\0${e.message}`;
        if (msgFreq[freqKey] === undefined) {
            msgFreq[freqKey] = { count: 0, level: e.level, message: e.message };
            msgOrder.push(freqKey);
        }
        msgFreq[freqKey].count++;
    }

    const repeated = [];
    for (let i = 0; i < msgOrder.length; i++) {
        const item = msgFreq[msgOrder[i]];
        if (item.count >= 2) repeated.push(item);
    }
    repeated.sort((a, b) => b.count - a.count);
    const topRepeated = repeated.slice(0, 5);

    const filtered = entries.filter(e => LOGF_LEVEL_INFO[e.level].rank >= minRank);

    let displayed = [];
    if (collapse) {
        for (let i = 0; i < filtered.length; i++) {
            const cur = filtered[i];
            const prev = displayed.length > 0 ? displayed[displayed.length - 1] : null;
            const curTraceSig = cur.trace ? cur.trace.lines.join("\n") : "";
            const prevTraceSig = prev && prev.trace ? prev.trace.lines.join("\n") : "";
            if (prev && prev.level === cur.level && prev.message === cur.message && prevTraceSig === curTraceSig && Boolean(prev.trace) === Boolean(cur.trace)) {
                prev.count++;
            } else {
                displayed.push({
                    level: cur.level,
                    message: cur.message,
                    timestamp: cur.timestamp,
                    trace: cur.trace,
                    count: 1
                });
            }
        }
    } else {
        displayed = filtered;
    }

    // Build summary header
    const countsStr = `ERR ${counts.error} · WARN ${counts.warn} · INFO ${counts.info} · DBG ${counts.debug} · TRC ${counts.trace}`;
    const filterNote = levelOpt === "all"
        ? `(${parsed.nonEmptyLines} lines)`
        : `(showing >= ${LOGF_LEVEL_INFO[levelOpt].tag.trim()}: ${filtered.length}/${entries.length})`;
    const header = [`SUMMARY  ${filterNote}`];
    header.push(`  Levels     ${countsStr}`);

    const timeSpan = logfComputeTimeSpan(parsed.timestamps);
    if (timeSpan) {
        header.push(`  Time span  ${timeSpan}`);
    }

    const firstErrText = firstError === null
        ? "none"
        : (firstError.length > 60 ? firstError.slice(0, 57) + "..." : firstError);
    header.push(`  First err  ${firstErrText}`);

    if (topRepeated.length > 0) {
        for (let i = 0; i < topRepeated.length; i++) {
            const rep = topRepeated[i];
            const msgClip = rep.message.length > 48 ? rep.message.slice(0, 45) + "..." : rep.message;
            const prefix = i === 0 ? "  Repeated   " : "             ";
            header.push(`${prefix}×${rep.count}  ${msgClip}`);
        }
    }

    if (traces.length > 0) {
        for (let i = 0; i < traces.length; i++) {
            const prefix = i === 0 ? "  Traces     " : "             ";
            header.push(`${prefix}${logfFormatTraceSummary(traces[i], i)}`);
        }
    }

    // Build cleaned log body
    const body = [];
    if (displayed.length === 0) {
        body.push(`(No entries matching level >= ${LOGF_LEVEL_INFO[levelOpt].tag.trim()})`);
    } else {
        for (let i = 0; i < displayed.length; i++) {
            const item = displayed[i];
            const tag = LOGF_LEVEL_INFO[item.level].tag;
            const tsPart = (!stripTimestamps && item.timestamp) ? `${item.timestamp} ` : "";
            const repeatSuffix = item.count > 1 ? ` ×${item.count}` : "";
            body.push(`${tag}  ${tsPart}${item.message}${repeatSuffix}`);
            if (item.trace) {
                const traceLines = logfFormatTraceBody(item.trace, framesOnly);
                for (let j = 0; j < traceLines.length; j++) {
                    body.push(traceLines[j] === "" ? "" : `        ${traceLines[j]}`);
                }
            }
        }
    }

    return {
        output: header.join("\n") + "\n\n" + body.join("\n"),
        meta: {
            errors: counts.error,
            warnings: counts.warn,
            lines: parsed.nonEmptyLines
        }
    };
}
// @slot-end log_formatter

// @slot-begin markdown_table
const MDT_FORMAT_NAMES = {
    markdown: "Markdown",
    csv: "CSV",
    tsv: "TSV",
    json: "JSON",
    spaces: "Spaces"
};

function mdtCodePointWidth(cp) {
    if (cp < 0x20 || (cp >= 0x7f && cp <= 0x9f))
        return 0;
    if ((cp >= 0x0300 && cp <= 0x036f)
        || (cp >= 0x1ab0 && cp <= 0x1aff)
        || (cp >= 0x1dc0 && cp <= 0x1dff)
        || (cp >= 0x200b && cp <= 0x200d)
        || cp === 0x2060
        || (cp >= 0x20d0 && cp <= 0x20ff)
        || (cp >= 0xfe00 && cp <= 0xfe0f)
        || (cp >= 0xfe20 && cp <= 0xfe2f)
        || cp === 0xfeff
        || (cp >= 0x1f3fb && cp <= 0x1f3ff)
        || (cp >= 0xe0100 && cp <= 0xe01ef)) {
        return 0;
    }
    if ((cp >= 0x1100 && cp <= 0x115f)
        || cp === 0x231a || cp === 0x231b
        || cp === 0x2329 || cp === 0x232a
        || (cp >= 0x23e9 && cp <= 0x23f3)
        || (cp >= 0x23f8 && cp <= 0x23fa)
        || cp === 0x25fd || cp === 0x25fe
        || cp === 0x2614 || cp === 0x2615
        || (cp >= 0x2648 && cp <= 0x2653)
        || cp === 0x267f || cp === 0x2693 || cp === 0x26a1
        || cp === 0x26aa || cp === 0x26ab
        || cp === 0x26bd || cp === 0x26be
        || cp === 0x26c4 || cp === 0x26c5
        || cp === 0x26ce || cp === 0x26d4 || cp === 0x26ea
        || cp === 0x26f2 || cp === 0x26f3 || cp === 0x26f5 || cp === 0x26fa || cp === 0x26fd
        || cp === 0x2705 || cp === 0x270a || cp === 0x270b || cp === 0x2728
        || cp === 0x274c || cp === 0x274e
        || (cp >= 0x2753 && cp <= 0x2755) || cp === 0x2757
        || (cp >= 0x2795 && cp <= 0x2797) || cp === 0x27b0 || cp === 0x27bf
        || cp === 0x2b1b || cp === 0x2b1c || cp === 0x2b50 || cp === 0x2b55
        || (cp >= 0x2e80 && cp <= 0x303e)
        || (cp >= 0x3041 && cp <= 0x33ff)
        || (cp >= 0x3400 && cp <= 0x4dbf)
        || (cp >= 0x4e00 && cp <= 0x9fff)
        || (cp >= 0xa000 && cp <= 0xa4cf)
        || (cp >= 0xa960 && cp <= 0xa97f)
        || (cp >= 0xac00 && cp <= 0xd7a3)
        || (cp >= 0xf900 && cp <= 0xfaff)
        || (cp >= 0xfe10 && cp <= 0xfe19)
        || (cp >= 0xfe30 && cp <= 0xfe6f)
        || (cp >= 0xff01 && cp <= 0xff60)
        || (cp >= 0xffe0 && cp <= 0xffe6)
        || cp === 0x1f004 || cp === 0x1f0cf || cp === 0x1f18e
        || (cp >= 0x1f191 && cp <= 0x1f19a)
        || (cp >= 0x1f1e6 && cp <= 0x1f1ff)
        || (cp >= 0x1f201 && cp <= 0x1f251)
        || (cp >= 0x1f300 && cp <= 0x1f64f)
        || (cp >= 0x1f680 && cp <= 0x1f6ff)
        || (cp >= 0x1f7e0 && cp <= 0x1f7eb)
        || (cp >= 0x1f900 && cp <= 0x1f9ff)
        || (cp >= 0x1fa70 && cp <= 0x1faff)
        || (cp >= 0x20000 && cp <= 0x3fffd)) {
        return 2;
    }
    return 1;
}

/// Computes terminal/monospace column width: CJK/emoji = 2, combining marks = 0.
function mdtDisplayWidth(str) {
    const s = String(str);
    let width = 0;
    let prevWidth = 0;
    let zwjJoin = false;
    for (let i = 0; i < s.length; i++) {
        let cp = s.charCodeAt(i);
        if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < s.length) {
            const lo = s.charCodeAt(i + 1);
            if (lo >= 0xdc00 && lo <= 0xdfff) {
                cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                i++;
            }
        }
        if (cp === 0x200d) {
            zwjJoin = true;
            continue;
        }
        if (cp === 0xfe0f) {
            if (prevWidth === 1) {
                width += 1;
                prevWidth = 2;
            }
            continue;
        }
        const w = mdtCodePointWidth(cp);
        if (zwjJoin) {
            zwjJoin = false;
            if (w > 0)
                continue;
        }
        width += w;
        if (w > 0)
            prevWidth = w;
    }
    return width;
}

function mdtPadCell(text, targetWidth, alignment) {
    const pad = Math.max(0, targetWidth - mdtDisplayWidth(text));
    if (pad === 0)
        return text;
    if (alignment === "right")
        return " ".repeat(pad) + text;
    if (alignment === "center") {
        const left = Math.floor(pad / 2);
        return " ".repeat(left) + text + " ".repeat(pad - left);
    }
    return text + " ".repeat(pad);
}

function mdtIsNumberCell(value) {
    const s = String(value).trim();
    if (s.length === 0)
        return false;
    return /^[+-]?(?:[$€£¥]\s*)?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?(?:[eE][+-]?\d+)?%?$/.test(s);
}

function mdtIsMdSeparatorRow(cells) {
    if (cells.length === 0)
        return false;
    for (let i = 0; i < cells.length; i++) {
        if (!/^:?-{1,}:?$/.test(cells[i]))
            return false;
    }
    return true;
}

function mdtSplitMdRow(line) {
    let s = line.trim();
    if (s.startsWith("|"))
        s = s.slice(1);
    // Only strip a trailing pipe when it is not escaped by a preceding backslash.
    if (s.endsWith("|") && !(s.length >= 2 && s.charAt(s.length - 2) === "\\"))
        s = s.slice(0, -1);

    const cells = [];
    let cur = "";
    for (let i = 0; i < s.length; i++) {
        const ch = s.charAt(i);
        if (ch === "\\" && i + 1 < s.length && s.charAt(i + 1) === "|") {
            cur += "|";
            i++;
        } else if (ch === "|") {
            cells.push(cur.trim().replace(/<br\s*\/?>/gi, "\n"));
            cur = "";
        } else {
            cur += ch;
        }
    }
    cells.push(cur.trim().replace(/<br\s*\/?>/gi, "\n"));
    return cells;
}

function mdtParseMarkdown(text) {
    const rawLines = text.split(/\r\n|\n|\r/);
    const rows = [];
    for (let i = 0; i < rawLines.length; i++) {
        const line = rawLines[i].trim();
        if (line.length === 0)
            continue;
        const cells = mdtSplitMdRow(line);
        // Drop standard GFM delimiter rows (row 1, or repeated separators).
        if (mdtIsMdSeparatorRow(cells) && rows.length > 0)
            continue;
        if (mdtIsMdSeparatorRow(cells) && rows.length === 0)
            continue;
        rows.push(cells);
    }
    if (rows.length === 0)
        throw new Error("Expected a Markdown table with at least one header row.");
    return rows;
}

function mdtParseDelimited(text, delimiter, formatLabel) {
    const rows = [];
    let row = [];
    let field = "";
    let quoted = false;
    let atFieldStart = true;

    for (let i = 0; i < text.length; i++) {
        const ch = text.charAt(i);
        if (quoted) {
            if (ch === "\"") {
                if (i + 1 < text.length && text.charAt(i + 1) === "\"") {
                    field += "\"";
                    i++;
                } else {
                    quoted = false;
                }
            } else {
                field += ch;
            }
        } else if (ch === "\"" && atFieldStart) {
            quoted = true;
            atFieldStart = false;
        } else if (ch === delimiter) {
            row.push(field);
            field = "";
            atFieldStart = true;
        } else if (ch === "\n" || ch === "\r") {
            if (ch === "\r" && i + 1 < text.length && text.charAt(i + 1) === "\n")
                i++;
            row.push(field);
            rows.push(row);
            row = [];
            field = "";
            atFieldStart = true;
        } else {
            field += ch;
            atFieldStart = false;
        }
    }
    if (quoted)
        throw new Error("Unclosed quote in " + formatLabel + " input.");
    if (!atFieldStart || row.length > 0) {
        row.push(field);
        rows.push(row);
    }
    return rows.filter(r => !(r.length === 1 && r[0] === ""));
}

function mdtParseJson(text) {
    let data;
    try {
        data = JSON.parse(text);
    } catch (err) {
        throw new Error("Invalid JSON: expected a JSON array of objects, e.g. [{\"name\": \"Ada\"}].");
    }
    if (!Array.isArray(data) || data.length === 0)
        throw new Error("Expected a non-empty JSON array of objects, e.g. [{\"name\": \"Ada\"}].");
    for (let i = 0; i < data.length; i++) {
        const item = data[i];
        if (item === null || typeof item !== "object" || Array.isArray(item))
            throw new Error("Expected a JSON array of objects, e.g. [{\"name\": \"Ada\"}].");
    }
    const keys = [];
    for (let i = 0; i < data.length; i++) {
        const objKeys = Object.keys(data[i]);
        for (let k = 0; k < objKeys.length; k++) {
            if (keys.indexOf(objKeys[k]) === -1)
                keys.push(objKeys[k]);
        }
    }
    if (keys.length === 0)
        throw new Error("JSON objects have no properties to tabulate.");

    const rows = [keys];
    for (let i = 0; i < data.length; i++) {
        const obj = data[i];
        const row = [];
        for (let k = 0; k < keys.length; k++) {
            const val = obj[keys[k]];
            if (val === null || val === undefined)
                row.push("");
            else if (typeof val === "object")
                row.push(JSON.stringify(val));
            else
                row.push(String(val));
        }
        rows.push(row);
    }
    return rows;
}

/// Parses fixed-width CLI output (docker ps, kubectl get) via vertical space gutters,
/// falling back to 2+ space splitting when columns are not vertically aligned.
function mdtParseSpaces(text) {
    const lines = text.split(/\r\n|\n|\r/).filter(l => l.trim().length > 0);
    if (lines.length === 0)
        return [];
    if (lines.length === 1)
        return [lines[0].trim().split(/ {2,}/)];

    let maxLen = 0;
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].length > maxLen)
            maxLen = lines[i].length;
    }

    const blankCol = new Array(maxLen);
    for (let x = 0; x < maxLen; x++) {
        let allSpace = true;
        for (let r = 0; r < lines.length; r++) {
            const ch = x < lines[r].length ? lines[r].charAt(x) : " ";
            if (ch !== " " && ch !== "\t") {
                allSpace = false;
                break;
            }
        }
        blankCol[x] = allSpace;
    }

    let firstNonSpace = 0;
    while (firstNonSpace < maxLen && blankCol[firstNonSpace])
        firstNonSpace++;
    let lastNonSpace = maxLen - 1;
    while (lastNonSpace >= 0 && blankCol[lastNonSpace])
        lastNonSpace--;

    // Identify vertical gutters inside [firstNonSpace, lastNonSpace].
    const header = lines[0];
    const gutters = [];
    let x = firstNonSpace;
    while (x <= lastNonSpace) {
        if (!blankCol[x]) {
            x++;
            continue;
        }
        const start = x;
        while (x <= lastNonSpace && blankCol[x])
            x++;
        const end = x;
        const width = end - start;
        let headerRun = 0;
        if (width === 1) {
            let l = start;
            while (l > 0 && l - 1 < header.length && header.charAt(l - 1) === " ")
                l--;
            let r = end;
            while (r < header.length && header.charAt(r) === " ")
                r++;
            headerRun = r - l;
        }
        if (width >= 2 || (width === 1 && headerRun >= 2 && end < header.length && header.charAt(end) !== " "))
            gutters.push({ start, end });
    }

    const headerChunks = header.trim().split(/ {2,}/);
    if (gutters.length > 0 && gutters.length + 1 >= headerChunks.length) {
        const bounds = [0];
        for (let i = 0; i < gutters.length; i++)
            bounds.push(gutters[i].end);
        bounds.push(maxLen);

        const rows = [];
        for (let r = 0; r < lines.length; r++) {
            const line = lines[r];
            const row = [];
            for (let c = 0; c < bounds.length - 1; c++) {
                const fromIdx = bounds[c];
                const toIdx = c + 1 === bounds.length - 1 ? line.length : bounds[c + 1];
                row.push(fromIdx < line.length ? line.slice(fromIdx, toIdx).trim() : "");
            }
            rows.push(row);
        }
        return rows;
    }

    return lines.map(l => l.trim().split(/ {2,}/));
}

function mdtDetectFormat(text) {
    const trimmed = text.trim();
    if (trimmed.startsWith("[")) {
        try {
            const parsed = JSON.parse(trimmed);
            if (Array.isArray(parsed))
                return "json";
        } catch (err) {
            if (/^\[\s*\{/.test(trimmed))
                return "json";
        }
    }

    const lines = trimmed.split(/\r\n|\n|\r/).filter(l => l.trim().length > 0);
    const hasMdSep = lines.some(l => {
        const t = l.trim();
        return t.indexOf("|") !== -1 && mdtIsMdSeparatorRow(mdtSplitMdRow(t));
    });
    if (hasMdSep)
        return "markdown";

    const allHavePipe = lines.length > 0 && lines.every(l => {
        // Check for unescaped pipe.
        for (let i = 0; i < l.length; i++) {
            if (l.charAt(i) === "\\" && i + 1 < l.length) {
                i++;
                continue;
            }
            if (l.charAt(i) === "|")
                return true;
        }
        return false;
    });
    if (allHavePipe) {
        const firstCount = mdtSplitMdRow(lines[0]).length;
        if (firstCount >= 2 || lines[0].trim().startsWith("|"))
            return "markdown";
    }

    const tabLines = lines.filter(l => l.indexOf("\t") !== -1).length;
    if (tabLines > 0 && tabLines >= Math.ceil(lines.length / 2))
        return "tsv";

    const spaceSepLines = lines.filter(l => /\S {2,}\S/.test(l)).length;
    const firstLineHasComma = lines.length > 0 && lines[0].indexOf(",") !== -1;
    const firstLineHasQuote = lines.length > 0 && /(?:^|,)\s*"/.test(lines[0]);
    if (!firstLineHasComma && !firstLineHasQuote && spaceSepLines > 0 && spaceSepLines >= Math.ceil(lines.length / 2))
        return "spaces";

    if (trimmed.indexOf(",") !== -1)
        return "csv";

    if (spaceSepLines > 0)
        return "spaces";

    return "csv";
}

function mdtNormalizeCellForMd(value) {
    return String(value).replace(/\r\n|\r|\n/g, "<br>").replace(/\|/g, "\\|");
}

function mdtEscapeCsvCell(value, delimiter) {
    const s = String(value);
    if (s.indexOf("\"") !== -1 || s.indexOf("\n") !== -1 || s.indexOf("\r") !== -1 || s.indexOf(delimiter) !== -1)
        return "\"" + s.replace(/"/g, "\"\"") + "\"";
    return s;
}

function mdtEscapeHtml(value) {
    return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/\r\n|\r|\n/g, "<br>");
}

function mdtUniqueKeys(headers) {
    const seen = {};
    const keys = [];
    for (let i = 0; i < headers.length; i++) {
        let base = String(headers[i]).trim();
        if (base.length === 0)
            base = "Column " + (i + 1);
        let candidate = base;
        let suffix = 2;
        while (seen[candidate]) {
            candidate = base + "_" + suffix;
            suffix++;
        }
        seen[candidate] = true;
        keys.push(candidate);
    }
    return keys;
}

function mdtFormatMarkdown(headers, dataRows, alignments, compact) {
    const colCount = headers.length;
    const normHeaders = headers.map(mdtNormalizeCellForMd);
    const normData = dataRows.map(r => r.map(mdtNormalizeCellForMd));

    if (compact) {
        const sep = [];
        for (let c = 0; c < colCount; c++) {
            const a = alignments[c];
            sep.push(a === "right" ? "-:" : (a === "center" ? ":-:" : ":-"));
        }
        const lines = ["|" + normHeaders.join("|") + "|", "|" + sep.join("|") + "|"];
        for (let r = 0; r < normData.length; r++)
            lines.push("|" + normData[r].join("|") + "|");
        return lines.join("\n");
    }

    const widths = new Array(colCount);
    for (let c = 0; c < colCount; c++) {
        let w = alignments[c] === "center" ? 5 : 4;
        const hw = mdtDisplayWidth(normHeaders[c]);
        if (hw > w) w = hw;
        for (let r = 0; r < normData.length; r++) {
            const cw = mdtDisplayWidth(normData[r][c]);
            if (cw > w) w = cw;
        }
        widths[c] = w;
    }

    const formatRow = row => {
        const padded = [];
        for (let c = 0; c < colCount; c++)
            padded.push(mdtPadCell(row[c], widths[c], alignments[c]));
        return "| " + padded.join(" | ") + " |";
    };

    const sepCells = [];
    for (let c = 0; c < colCount; c++) {
        const w = widths[c];
        if (alignments[c] === "right")
            sepCells.push("-".repeat(w - 1) + ":");
        else if (alignments[c] === "center")
            sepCells.push(":" + "-".repeat(w - 2) + ":");
        else
            sepCells.push(":" + "-".repeat(w - 1));
    }

    const lines = [formatRow(normHeaders), "| " + sepCells.join(" | ") + " |"];
    for (let r = 0; r < normData.length; r++)
        lines.push(formatRow(normData[r]));
    return lines.join("\n");
}

function mdtFormatDelimited(headers, dataRows, delimiter) {
    const all = [headers].concat(dataRows);
    return all.map(row => row.map(cell => mdtEscapeCsvCell(cell, delimiter)).join(delimiter)).join("\n");
}

function mdtFormatJson(headers, dataRows) {
    const keys = mdtUniqueKeys(headers);
    const records = [];
    for (let r = 0; r < dataRows.length; r++) {
        const obj = {};
        for (let c = 0; c < keys.length; c++)
            obj[keys[c]] = dataRows[r][c];
        records.push(obj);
    }
    return JSON.stringify(records, null, 2);
}

function mdtFormatHtml(headers, dataRows, alignments) {
    const alignAttr = a => a === "right" ? " style=\"text-align: right\"" : (a === "center" ? " style=\"text-align: center\"" : "");
    const lines = ["<table>", "  <thead>", "    <tr>"];
    for (let c = 0; c < headers.length; c++)
        lines.push("      <th" + alignAttr(alignments[c]) + ">" + mdtEscapeHtml(headers[c]) + "</th>");
    lines.push("    </tr>", "  </thead>");
    if (dataRows.length > 0) {
        lines.push("  <tbody>");
        for (let r = 0; r < dataRows.length; r++) {
            lines.push("    <tr>");
            for (let c = 0; c < headers.length; c++)
                lines.push("      <td" + alignAttr(alignments[c]) + ">" + mdtEscapeHtml(dataRows[r][c]) + "</td>");
            lines.push("    </tr>");
        }
        lines.push("  </tbody>");
    }
    lines.push("</table>");
    return lines.join("\n");
}

function mdtMarkdownTable(input = "", options = {}) {
    let text = String(input);
    if (text.charCodeAt(0) === 0xfeff)
        text = text.slice(1);
    if (text.trim().length === 0)
        return { output: "" };

    const validFrom = ["auto", "markdown", "csv", "tsv", "json", "spaces"];
    const requestedFrom = validFrom.indexOf(options.from) !== -1 ? options.from : "auto";
    const from = requestedFrom === "auto" ? mdtDetectFormat(text) : requestedFrom;

    let rawRows;
    try {
        switch (from) {
        case "markdown":
            rawRows = mdtParseMarkdown(text);
            break;
        case "tsv":
            rawRows = mdtParseDelimited(text, "\t", "TSV");
            break;
        case "json":
            rawRows = mdtParseJson(text);
            break;
        case "spaces":
            rawRows = mdtParseSpaces(text);
            break;
        default:
            rawRows = mdtParseDelimited(text, ",", "CSV");
            break;
        }
    } catch (err) {
        return { output: "", error: err.message };
    }

    if (!rawRows || rawRows.length === 0)
        return { output: "", error: "No table rows found in input." };

    let colCount = 0;
    for (let i = 0; i < rawRows.length; i++) {
        if (rawRows[i].length > colCount)
            colCount = rawRows[i].length;
    }
    if (colCount === 0)
        return { output: "", error: "No table columns found in input." };

    let paddedCount = 0;
    const normalized = [];
    for (let i = 0; i < rawRows.length; i++) {
        const row = rawRows[i].slice();
        if (row.length < colCount) {
            paddedCount++;
            while (row.length < colCount)
                row.push("");
        }
        normalized.push(row);
    }

    const hasHeader = options.header !== false;
    let headers;
    let dataRows;
    if (hasHeader) {
        headers = normalized[0];
        dataRows = normalized.slice(1);
    } else {
        headers = [];
        for (let c = 0; c < colCount; c++)
            headers.push("Column " + (c + 1));
        dataRows = normalized;
    }

    const validAlign = ["auto", "left", "center", "right"];
    const alignOpt = validAlign.indexOf(options.align) !== -1 ? options.align : "auto";
    const alignments = [];
    for (let c = 0; c < colCount; c++) {
        if (alignOpt !== "auto") {
            alignments.push(alignOpt);
            continue;
        }
        let nonEmpty = 0;
        let allNumeric = true;
        for (let r = 0; r < dataRows.length; r++) {
            const cell = String(dataRows[r][c]).trim();
            if (cell.length === 0)
                continue;
            nonEmpty++;
            if (!mdtIsNumberCell(cell)) {
                allNumeric = false;
                break;
            }
        }
        alignments.push(nonEmpty > 0 && allNumeric ? "right" : "left");
    }

    const validTo = ["markdown", "csv", "tsv", "json", "html"];
    const to = validTo.indexOf(options.to) !== -1 ? options.to : "markdown";
    const compact = Boolean(options.compact);

    let output;
    switch (to) {
    case "csv":
        output = mdtFormatDelimited(headers, dataRows, ",");
        break;
    case "tsv":
        output = mdtFormatDelimited(headers, dataRows, "\t");
        break;
    case "json":
        output = mdtFormatJson(headers, dataRows);
        break;
    case "html":
        output = mdtFormatHtml(headers, dataRows, alignments);
        break;
    default:
        output = mdtFormatMarkdown(headers, dataRows, alignments, compact);
        break;
    }

    const meta = {
        size: dataRows.length + "×" + colCount,
        from: MDT_FORMAT_NAMES[from] || from
    };
    if (paddedCount > 0)
        meta.warning = paddedCount + " ragged row" + (paddedCount === 1 ? "" : "s") + " padded";

    return { output, meta };
}
// @slot-end markdown_table

// @slot-begin hypr_keybind
const HKB_MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5"];

const HKB_MOD_ALIASES = {
    SUPER: "SUPER", WIN: "SUPER", WINDOWS: "SUPER", MOD4: "SUPER",
    META: "SUPER", LOGO: "SUPER", CMD: "SUPER", COMMAND: "SUPER", "$MAINMOD": "SUPER",
    CTRL: "CTRL", CONTROL: "CTRL", CTL: "CTRL",
    ALT: "ALT", MOD1: "ALT", OPT: "ALT", OPTION: "ALT",
    SHIFT: "SHIFT", SHFT: "SHIFT",
    CAPS: "CAPS", CAPSLOCK: "CAPS",
    MOD2: "MOD2", MOD3: "MOD3", MOD5: "MOD5"
};

const HKB_KEY_ALIASES = {
    "return": "Return", "enter": "Return", "kp_enter": "KP_Enter",
    "escape": "Escape", "esc": "Escape",
    "space": "space", "spacebar": "space",
    "tab": "Tab", "delete": "Delete", "del": "Delete",
    "backspace": "BackSpace", "insert": "Insert", "ins": "Insert",
    "home": "Home", "end": "End",
    "page_up": "Page_Up", "pageup": "Page_Up", "pgup": "Page_Up", "prior": "Page_Up",
    "page_down": "Page_Down", "pagedown": "Page_Down", "pgdn": "Page_Down", "next": "Page_Down",
    "print": "Print", "prtsc": "Print", "printscreen": "Print", "sys_req": "Print",
    "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "caps_lock": "Caps_Lock", "capslock": "Caps_Lock",
    "num_lock": "Num_Lock", "numlock": "Num_Lock",
    "scroll_lock": "Scroll_Lock", "pause": "Pause", "menu": "Menu",
    "slash": "Slash", "/": "Slash",
    "backslash": "Backslash", "\\": "Backslash",
    "period": "Period", ".": "Period",
    "comma": "Comma", ",": "Comma",
    "semicolon": "Semicolon", ";": "Semicolon",
    "apostrophe": "Apostrophe", "'": "Apostrophe",
    "minus": "Minus", "-": "Minus",
    "equal": "Equal", "=": "Equal",
    "grave": "grave", "`": "grave",
    "bracketleft": "BracketLeft", "[": "BracketLeft",
    "bracketright": "BracketRight", "]": "BracketRight",
    "super_l": "SUPER_L", "super_r": "SUPER_R",
    "alt_l": "ALT_L", "alt_r": "ALT_R",
    "ctrl_l": "CTRL_L", "ctrl_r": "CTRL_R",
    "kp_add": "KP_Add", "kp_subtract": "KP_Subtract",
    "kp_multiply": "KP_Multiply", "kp_divide": "KP_Divide",
    "mouse_up": "mouse_up", "mouse_down": "mouse_down",
    "mouse_left": "mouse_left", "mouse_right": "mouse_right",
    "lmb": "mouse:272", "leftclick": "mouse:272",
    "rmb": "mouse:273", "rightclick": "mouse:273",
    "mmb": "mouse:274", "middleclick": "mouse:274",
    "catchall": "catchall"
};

const HKB_XF86_CANONICAL = {
    "xf86audioraisevolume": "XF86AudioRaiseVolume",
    "xf86audiolowervolume": "XF86AudioLowerVolume",
    "xf86audiomute": "XF86AudioMute",
    "xf86audiomicmute": "XF86AudioMicMute",
    "xf86audioplay": "XF86AudioPlay",
    "xf86audiopause": "XF86AudioPause",
    "xf86audionext": "XF86AudioNext",
    "xf86audioprev": "XF86AudioPrev",
    "xf86audiostop": "XF86AudioStop",
    "xf86monbrightnessup": "XF86MonBrightnessUp",
    "xf86monbrightnessdown": "XF86MonBrightnessDown",
    "xf86touchpadtoggle": "XF86TouchpadToggle",
    "xf86touchpadon": "XF86TouchpadOn",
    "xf86touchpadoff": "XF86TouchpadOff",
    "xf86calculator": "XF86Calculator",
    "xf86mail": "XF86Mail",
    "xf86search": "XF86Search",
    "xf86homepage": "XF86HomePage",
    "xf86poweroff": "XF86PowerOff",
    "xf86sleep": "XF86Sleep",
    "xf86suspend": "XF86Suspend",
    "xf86screensaver": "XF86ScreenSaver",
    "xf86wlan": "XF86WLAN",
    "xf86bluetooth": "XF86Bluetooth"
};

// Flag order puts e before l so repeat+locked emits "bindel" (common Hyprland convention).
const HKB_CONF_FLAG_ORDER = ["e", "l", "r", "o", "n", "t", "i", "p", "u", "m", "c", "g", "s"];
const HKB_FLAG_TO_LUA = {
    e: "repeating",
    l: "locked",
    r: "release",
    o: "long_press",
    n: "non_consuming",
    t: "transparent",
    i: "ignore_mods",
    p: "dont_inhibit",
    u: "submap_universal",
    m: "mouse",
    c: "click",
    g: "drag"
};
const HKB_LUA_TO_FLAG = {
    repeating: "e",
    locked: "l",
    release: "r",
    long_press: "o",
    non_consuming: "n",
    transparent: "t",
    ignore_mods: "i",
    dont_inhibit: "p",
    submap_universal: "u",
    mouse: "m",
    click: "c",
    drag: "g"
};
const HKB_FLAG_LABELS = {
    e: "repeat", l: "locked", r: "release", o: "long_press", n: "non_consuming",
    t: "transparent", i: "ignore_mods", p: "dont_inhibit", u: "submap_universal",
    m: "mouse", c: "click", g: "drag", s: "separate"
};

const HKB_VALID_LUA_DSP = {
    "cursor.move": true,
    "cursor.move_to_corner": true,
    dpms: true,
    event: true,
    exec_cmd: true,
    exec_raw: true,
    exit: true,
    focus: true,
    force_idle: true,
    force_renderer_reload: true,
    global: true,
    "group.active": true,
    "group.lock": true,
    "group.lock_active": true,
    "group.move_window": true,
    "group.next": true,
    "group.prev": true,
    "group.toggle": true,
    layout: true,
    no_op: true,
    pass: true,
    release_input_capture: true,
    send_key_state: true,
    send_shortcut: true,
    submap: true,
    "window.alter_zorder": true,
    "window.bring_to_top": true,
    "window.center": true,
    "window.clear_tags": true,
    "window.close": true,
    "window.cycle_next": true,
    "window.deny_from_group": true,
    "window.drag": true,
    "window.float": true,
    "window.fullscreen": true,
    "window.fullscreen_state": true,
    "window.kill": true,
    "window.move": true,
    "window.pin": true,
    "window.pseudo": true,
    "window.resize": true,
    "window.set_prop": true,
    "window.signal": true,
    "window.swap": true,
    "window.tag": true,
    "window.toggle_swallow": true,
    "workspace.change_id": true,
    "workspace.move": true,
    "workspace.rename": true,
    "workspace.swap_monitors": true,
    "workspace.toggle_special": true
};

const HKB_DISPATCHERS = {
    exec: { arg: "required", hint: "command" },
    execr: { arg: "required", hint: "command" },
    pass: { arg: "optional", hint: "window" },
    sendshortcut: { arg: "required", hint: "mods, key[, window]" },
    sendkeystate: { arg: "required", hint: "mods, key, state, window" },
    killactive: { arg: "none" },
    forcekillactive: { arg: "none" },
    closewindow: { arg: "required", hint: "window" },
    killwindow: { arg: "required", hint: "window" },
    signal: { arg: "required", hint: "signal" },
    signalwindow: { arg: "required", hint: "window,signal" },
    workspace: { arg: "required", hint: "id, +1/-1, or name" },
    movetoworkspace: { arg: "required", hint: "workspace[,window]" },
    movetoworkspacesilent: { arg: "required", hint: "workspace[,window]" },
    togglefloating: { arg: "optional", hint: "window" },
    setfloating: { arg: "optional", hint: "window" },
    settiled: { arg: "optional", hint: "window" },
    fullscreen: { arg: "optional", hint: "0 (full) or 1 (maximize)" },
    fullscreenstate: { arg: "required", hint: "internal client" },
    dpms: { arg: "required", hint: "on, off, or toggle" },
    pin: { arg: "optional", hint: "window" },
    movefocus: { arg: "required", hint: "l, r, u, or d" },
    movewindow: { arg: "optional", hint: "l, r, u, d, or mon:..." },
    resizewindow: { arg: "optional" },
    swapwindow: { arg: "required", hint: "l, r, u, or d" },
    centerwindow: { arg: "optional", hint: "1" },
    resizeactive: { arg: "required", hint: "[exact] x y" },
    moveactive: { arg: "required", hint: "[exact] x y" },
    resizewindowpixel: { arg: "required", hint: "[exact] x y,window" },
    movewindowpixel: { arg: "required", hint: "[exact] x y,window" },
    cyclenext: { arg: "optional", hint: "prev, tiled, floating, hist, visible" },
    swapnext: { arg: "optional", hint: "prev" },
    focuswindow: { arg: "required", hint: "window" },
    focusmonitor: { arg: "required", hint: "monitor" },
    splitratio: { arg: "required", hint: "delta or exact value" },
    toggleopaque: { arg: "none" },
    movecursortocorner: { arg: "required", hint: "0-3" },
    movecursor: { arg: "required", hint: "x y" },
    renameworkspace: { arg: "required", hint: "id name" },
    exit: { arg: "none" },
    forcerendererreload: { arg: "none" },
    focuscurrentorlast: { arg: "none" },
    focusurgentorlast: { arg: "none" },
    togglespecialworkspace: { arg: "optional", hint: "name" },
    movecurrentworkspacetomonitor: { arg: "required", hint: "monitor" },
    focusworkspaceoncurrentmonitor: { arg: "required", hint: "workspace" },
    moveworkspacetomonitor: { arg: "required", hint: "workspace monitor" },
    swapactiveworkspaces: { arg: "required", hint: "mon1 mon2" },
    bringactivetotop: { arg: "none" },
    alterzorder: { arg: "required", hint: "top or bottom[,window]" },
    togglesplit: { arg: "none" },
    pseudo: { arg: "optional", hint: "window" },
    swapsplit: { arg: "none" },
    togglegroup: { arg: "none" },
    changegroupactive: { arg: "optional", hint: "f, b, or index" },
    focusgroup: { arg: "optional", hint: "f or b" },
    lockgroups: { arg: "required", hint: "lock, unlock, or toggle" },
    lockactivegroup: { arg: "required", hint: "lock, unlock, or toggle" },
    moveintogroup: { arg: "required", hint: "l, r, u, or d" },
    moveoutofgroup: { arg: "optional", hint: "window" },
    movewindoworgroup: { arg: "required", hint: "l, r, u, or d" },
    movegroupwindow: { arg: "optional", hint: "b or f" },
    denywindowfromgroup: { arg: "required", hint: "on, off, or toggle" },
    setignoregrouplock: { arg: "required", hint: "on, off, or toggle" },
    global: { arg: "required", hint: "namespace:name" },
    submap: { arg: "required", hint: "name or reset" },
    layoutmsg: { arg: "required", hint: "message" },
    workspaceopt: { arg: "required", hint: "option" },
    setprop: { arg: "required", hint: "window prop value" },
    tagwindow: { arg: "required", hint: "tag [window]" },
    event: { arg: "required", hint: "payload" },
    forceidle: { arg: "required", hint: "seconds" },
    toggleswallow: { arg: "optional", hint: "window" },
    cleartags: { arg: "optional", hint: "window" },
    releaseinputcapture: { arg: "none" },
    changeworkspaceid: { arg: "required", hint: "workspace id" }
};

function hkbHasOwn(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
}

function hkbLevenshtein(a, b) {
    const m = a.length;
    const n = b.length;
    const dp = [];
    for (let i = 0; i <= m; i++) {
        const row = [];
        for (let j = 0; j <= n; j++) row.push(0);
        dp.push(row);
    }
    for (let i = 0; i <= m; i++) dp[i][0] = i;
    for (let j = 0; j <= n; j++) dp[0][j] = j;
    for (let i = 1; i <= m; i++) {
        for (let j = 1; j <= n; j++) {
            const cost = a.charAt(i - 1) === b.charAt(j - 1) ? 0 : 1;
            let best = dp[i - 1][j] + 1;
            if (dp[i][j - 1] + 1 < best) best = dp[i][j - 1] + 1;
            if (dp[i - 1][j - 1] + cost < best) best = dp[i - 1][j - 1] + cost;
            dp[i][j] = best;
        }
    }
    return dp[m][n];
}

function hkbSuggestDispatcher(name) {
    const lower = name.toLowerCase();
    let bestName = "";
    let bestDist = 4;
    const keys = Object.keys(HKB_DISPATCHERS);
    for (let i = 0; i < keys.length; i++) {
        const cand = keys[i];
        const dist = hkbLevenshtein(lower, cand);
        if (dist < bestDist) {
            bestDist = dist;
            bestName = cand;
        }
    }
    return bestName;
}

function hkbNormalizeModifiers(rawTokens, warnings, lineNum) {
    const mods = [];
    const seen = {};
    for (let i = 0; i < rawTokens.length; i++) {
        const tok = String(rawTokens[i] || "").trim();
        if (!tok) continue;
        const upper = tok.toUpperCase();
        const norm = hkbHasOwn(HKB_MOD_ALIASES, upper) ? HKB_MOD_ALIASES[upper] : null;
        if (!norm) {
            warnings.push(`Line ${lineNum}: Unknown modifier "${tok}"`);
            if (!hkbHasOwn(seen, upper)) {
                seen[upper] = true;
                mods.push(upper);
            }
            continue;
        }
        if (!hkbHasOwn(seen, norm)) {
            seen[norm] = true;
            mods.push(norm);
        }
    }
    mods.sort((a, b) => {
        const ia = HKB_MOD_ORDER.indexOf(a);
        const ib = HKB_MOD_ORDER.indexOf(b);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
    });
    return mods;
}

function hkbNormalizeKey(rawKey) {
    const k = String(rawKey || "").trim();
    if (!k) return "";
    const lower = k.toLowerCase();
    if (/^[a-z]$/.test(lower)) return lower.toUpperCase();
    if (/^f([1-9]|1[0-9]|2[0-4])$/.test(lower)) return lower.toUpperCase();
    if (/^code:\d+$/.test(lower)) return "code:" + lower.slice(5);
    if (/^mouse:\d+$/.test(lower)) return "mouse:" + lower.slice(6);
    if (/^switch:(on|off):/i.test(k)) return k;
    if (hkbHasOwn(HKB_XF86_CANONICAL, lower)) return HKB_XF86_CANONICAL[lower];
    if (lower.startsWith("xf86")) return "XF86" + k.slice(4);
    if (hkbHasOwn(HKB_KEY_ALIASES, lower)) return HKB_KEY_ALIASES[lower];
    return k;
}

function hkbFormatCombo(mods, key, joiner) {
    const parts = mods.slice();
    if (key) parts.push(key);
    return parts.join(joiner);
}

function hkbEscapeLuaString(str) {
    return String(str)
        .replace(/\\/g, "\\\\")
        .replace(/"/g, "\\\"")
        .replace(/\r/g, "\\r")
        .replace(/\n/g, "\\n")
        .replace(/\t/g, "\\t");
}

function hkbUnescapeLuaString(str) {
    let out = "";
    for (let i = 0; i < str.length; i++) {
        const ch = str.charAt(i);
        if (ch === "\\" && i + 1 < str.length) {
            const nxt = str.charAt(++i);
            if (nxt === "n") out += "\n";
            else if (nxt === "r") out += "\r";
            else if (nxt === "t") out += "\t";
            else out += nxt;
        } else {
            out += ch;
        }
    }
    return out;
}

function hkbParseLuaStringValue(expr) {
    const s = String(expr || "").trim();
    if (s.length >= 2) {
        const q = s.charAt(0);
        if ((q === "\"" || q === "'") && s.charAt(s.length - 1) === q) {
            return { isLiteral: true, value: hkbUnescapeLuaString(s.slice(1, -1)) };
        }
        if (s.startsWith("[[") && s.endsWith("]]")) {
            return { isLiteral: true, value: s.slice(2, -2) };
        }
    }
    return { isLiteral: false, value: s };
}

function hkbSplitTopLevel(str, delim) {
    const parts = [];
    let cur = "";
    let depthParen = 0;
    let depthBrace = 0;
    let depthBracket = 0;
    let quote = "";
    for (let i = 0; i < str.length; i++) {
        const ch = str.charAt(i);
        if (quote) {
            cur += ch;
            if (quote === "]]") {
                if (ch === "]" && str.charAt(i - 1) === "]") quote = "";
            } else if (ch === "\\") {
                if (i + 1 < str.length) cur += str.charAt(++i);
            } else if (ch === quote) {
                quote = "";
            }
            continue;
        }
        if (ch === "\"" || ch === "'") {
            quote = ch;
            cur += ch;
            continue;
        }
        if (ch === "[" && str.charAt(i + 1) === "[") {
            quote = "]]";
            cur += "[[";
            i++;
            continue;
        }
        if (ch === "(") depthParen++;
        else if (ch === ")" && depthParen > 0) depthParen--;
        else if (ch === "{") depthBrace++;
        else if (ch === "}" && depthBrace > 0) depthBrace--;
        else if (ch === "[") depthBracket++;
        else if (ch === "]" && depthBracket > 0) depthBracket--;
        else if (ch === delim && depthParen === 0 && depthBrace === 0 && depthBracket === 0) {
            parts.push(cur.trim());
            cur = "";
            continue;
        }
        cur += ch;
    }
    if (cur.trim().length > 0 || parts.length > 0) parts.push(cur.trim());
    return parts;
}

function hkbParseLuaTable(tableSrc) {
    const s = String(tableSrc || "").trim();
    if (!s.startsWith("{") || !s.endsWith("}")) return null;
    const inner = s.slice(1, -1).trim();
    const out = {};
    const positional = [];
    if (!inner) return { map: out, positional };
    const entries = hkbSplitTopLevel(inner, ",");
    for (let i = 0; i < entries.length; i++) {
        const entry = entries[i].trim();
        if (!entry) continue;
        const eqIdx = entry.indexOf("=");
        let isNamed = false;
        if (eqIdx > 0) {
            const keyPart = entry.slice(0, eqIdx).trim();
            if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(keyPart)) {
                isNamed = true;
                const valRaw = entry.slice(eqIdx + 1).trim();
                if (valRaw === "true") out[keyPart] = true;
                else if (valRaw === "false") out[keyPart] = false;
                else if (/^-?\d+(\.\d+)?$/.test(valRaw)) out[keyPart] = Number(valRaw);
                else out[keyPart] = hkbParseLuaStringValue(valRaw).value;
            }
        }
        if (!isNamed) {
            positional.push(hkbParseLuaStringValue(entry).value);
        }
    }
    return { map: out, positional };
}

function hkbParseLuaDispatcher(actionSrc) {
    const s = String(actionSrc || "").trim();
    if (s.startsWith("function")) {
        return { dispatcher: "<lua>", arg: "", isLuaCallback: true };
    }
    const lit = hkbParseLuaStringValue(s);
    if (lit.isLiteral) {
        return { dispatcher: lit.value.toLowerCase(), arg: "" };
    }
    const m = /^hl\.dsp\.([a-zA-Z0-9_.]+)\s*\(([\s\S]*)\)$/.exec(s);
    if (!m) {
        return { dispatcher: s, arg: "" };
    }
    const fn = m[1];
    const rawArgs = m[2].trim();
    const argsList = rawArgs ? hkbSplitTopLevel(rawArgs, ",") : [];
    const firstRaw = argsList[0] || "";
    const firstStr = hkbParseLuaStringValue(firstRaw);
    const tbl = firstRaw.startsWith("{") ? hkbParseLuaTable(firstRaw) : null;

    switch (fn) {
    case "exec_cmd":
        return { dispatcher: "exec", arg: firstStr.value };
    case "exec_raw":
        return { dispatcher: "execr", arg: firstStr.value };
    case "global":
        return { dispatcher: "global", arg: firstStr.value };
    case "layout":
        if (firstStr.value === "togglesplit" || firstStr.value === "swapsplit") {
            return { dispatcher: firstStr.value, arg: "" };
        }
        if (firstStr.value.startsWith("splitratio ")) {
            return { dispatcher: "splitratio", arg: firstStr.value.slice(11).trim() };
        }
        return { dispatcher: "layoutmsg", arg: firstStr.value };
    case "submap":
        return { dispatcher: "submap", arg: firstStr.value };
    case "exit":
        return { dispatcher: "exit", arg: "" };
    case "force_renderer_reload":
        return { dispatcher: "forcerendererreload", arg: "" };
    case "force_idle":
        return { dispatcher: "forceidle", arg: String(firstStr.value) };
    case "release_input_capture":
        return { dispatcher: "releaseinputcapture", arg: "" };
    case "no_op":
        return { dispatcher: "pass", arg: "" };
    case "pass":
        return { dispatcher: "pass", arg: tbl && tbl.map.window !== undefined ? String(tbl.map.window) : firstStr.value };
    case "send_shortcut":
        if (tbl) {
            const parts = [tbl.map.mods ?? "", tbl.map.key ?? ""];
            if (tbl.map.window !== undefined) parts.push(String(tbl.map.window));
            return { dispatcher: "sendshortcut", arg: parts.join(", ") };
        }
        return { dispatcher: "sendshortcut", arg: firstStr.value };
    case "send_key_state":
        if (tbl) {
            const parts = [tbl.map.mods ?? "", tbl.map.key ?? "", tbl.map.state ?? ""];
            if (tbl.map.window !== undefined) parts.push(String(tbl.map.window));
            return { dispatcher: "sendkeystate", arg: parts.join(", ") };
        }
        return { dispatcher: "sendkeystate", arg: firstStr.value };
    case "event":
        return { dispatcher: "event", arg: firstStr.value };
    case "dpms":
        if (tbl && tbl.map.action) {
            const act = tbl.map.action === "disable" ? "off" : (tbl.map.action === "enable" ? "on" : tbl.map.action);
            const mon = tbl.map.monitor ? ` ${tbl.map.monitor}` : "";
            return { dispatcher: "dpms", arg: `${act}${mon}` };
        }
        return { dispatcher: "dpms", arg: firstStr.value };
    case "window.close":
        if (tbl && tbl.map.window) return { dispatcher: "closewindow", arg: String(tbl.map.window) };
        if (tbl && tbl.map.force) return { dispatcher: "forcekillactive", arg: "" };
        return { dispatcher: "killactive", arg: "" };
    case "window.kill":
        if (tbl && tbl.map.window) return { dispatcher: "killwindow", arg: String(tbl.map.window) };
        return { dispatcher: "forcekillactive", arg: "" };
    case "window.signal":
        if (tbl && tbl.map.window !== undefined) {
            return { dispatcher: "signalwindow", arg: `${tbl.map.window},${tbl.map.signal ?? ""}` };
        }
        return { dispatcher: "signal", arg: tbl && tbl.map.signal !== undefined ? String(tbl.map.signal) : firstStr.value };
    case "window.float": {
        const win = tbl && tbl.map.window ? String(tbl.map.window) : "";
        if (tbl && tbl.map.action === "float") return { dispatcher: "setfloating", arg: win };
        if (tbl && tbl.map.action === "tile") return { dispatcher: "settiled", arg: win };
        return { dispatcher: "togglefloating", arg: win };
    }
    case "window.fullscreen": {
        const mode = tbl && tbl.map.mode === "maximized" ? "1" : "0";
        return { dispatcher: "fullscreen", arg: mode };
    }
    case "window.fullscreen_state": {
        const internal = tbl && tbl.map.internal !== undefined ? String(tbl.map.internal) : "0";
        const client = tbl && tbl.map.client !== undefined ? String(tbl.map.client) : "0";
        return { dispatcher: "fullscreenstate", arg: `${internal} ${client}` };
    }
    case "window.pin":
        return { dispatcher: "pin", arg: tbl && tbl.map.window ? String(tbl.map.window) : "" };
    case "window.pseudo":
        return { dispatcher: "pseudo", arg: tbl && tbl.map.window ? String(tbl.map.window) : "" };
    case "window.center":
        return { dispatcher: "centerwindow", arg: tbl && tbl.map.preserve_size ? "1" : "" };
    case "window.bring_to_top":
        return { dispatcher: "bringactivetotop", arg: "" };
    case "window.alter_zorder":
        if (tbl) {
            const win = tbl.map.window ? `,${tbl.map.window}` : "";
            return { dispatcher: "alterzorder", arg: `${tbl.map.mode || "top"}${win}` };
        }
        return { dispatcher: "alterzorder", arg: firstStr.value };
    case "window.cycle_next":
        if (tbl) {
            const flags = ["prev", "tiled", "floating", "hist", "visible"].filter(k => tbl.map[k]);
            return { dispatcher: "cyclenext", arg: flags.join(" ") };
        }
        return { dispatcher: "cyclenext", arg: firstStr.value };
    case "window.deny_from_group":
        return { dispatcher: "denywindowfromgroup", arg: tbl && tbl.map.action ? String(tbl.map.action) : firstStr.value };
    case "window.set_prop":
        if (tbl) {
            const win = tbl.map.window ? String(tbl.map.window) : "active";
            return { dispatcher: "setprop", arg: `${win} ${tbl.map.prop || ""} ${tbl.map.value ?? ""}`.trim() };
        }
        return { dispatcher: "setprop", arg: firstStr.value };
    case "window.tag":
        if (tbl) {
            const win = tbl.map.window ? ` ${tbl.map.window}` : "";
            return { dispatcher: "tagwindow", arg: `${tbl.map.tag || ""}${win}` };
        }
        return { dispatcher: "tagwindow", arg: firstStr.value };
    case "window.clear_tags":
        return { dispatcher: "cleartags", arg: tbl && tbl.map.window ? String(tbl.map.window) : "" };
    case "window.toggle_swallow":
        return { dispatcher: "toggleswallow", arg: tbl && tbl.map.window ? String(tbl.map.window) : "" };
    case "window.drag":
        return { dispatcher: "movewindow", arg: "", isMouseOp: true };
    case "window.resize":
        if (tbl && (tbl.map.x !== undefined || tbl.map.y !== undefined)) {
            const exact = (tbl.map.exact === true || tbl.positional.indexOf("exact") !== -1) ? "exact " : "";
            const coords = `${exact}${tbl.map.x ?? 0} ${tbl.map.y ?? 0}`;
            if (tbl.map.window !== undefined) {
                return { dispatcher: "resizewindowpixel", arg: `${coords},${tbl.map.window}` };
            }
            return { dispatcher: "resizeactive", arg: coords };
        }
        return { dispatcher: "resizewindow", arg: "", isMouseOp: true };
    case "window.move":
        if (tbl) {
            if (tbl.map.into_group !== undefined) return { dispatcher: "moveintogroup", arg: String(tbl.map.into_group) };
            if (tbl.map.out_of_group !== undefined) {
                return { dispatcher: "moveoutofgroup", arg: tbl.map.out_of_group === true ? "" : String(tbl.map.out_of_group) };
            }
            if (tbl.map.direction !== undefined) {
                return { dispatcher: tbl.map.group ? "movewindoworgroup" : "movewindow", arg: String(tbl.map.direction) };
            }
            if (tbl.map.workspace !== undefined) {
                const ws = String(tbl.map.workspace) + (tbl.map.window ? `,${tbl.map.window}` : "");
                return { dispatcher: tbl.map.silent ? "movetoworkspacesilent" : "movetoworkspace", arg: ws };
            }
            if (tbl.map.monitor !== undefined) return { dispatcher: "movewindow", arg: `mon:${tbl.map.monitor}` };
            if (tbl.map.x !== undefined || tbl.map.y !== undefined) {
                const exact = (tbl.map.exact === true || tbl.positional.indexOf("exact") !== -1) ? "exact " : "";
                const coords = `${exact}${tbl.map.x ?? 0} ${tbl.map.y ?? 0}`;
                if (tbl.map.window !== undefined) {
                    return { dispatcher: "movewindowpixel", arg: `${coords},${tbl.map.window}` };
                }
                return { dispatcher: "moveactive", arg: coords };
            }
        }
        return { dispatcher: "movewindow", arg: firstStr.value };
    case "window.swap":
        if (tbl) {
            if (tbl.map.prev) return { dispatcher: "swapnext", arg: "prev" };
            if (tbl.map.next) return { dispatcher: "swapnext", arg: "" };
            if (tbl.map.direction !== undefined) return { dispatcher: "swapwindow", arg: String(tbl.map.direction) };
            const target = tbl.map.target ?? tbl.map.with ?? tbl.map.other ?? tbl.map.window;
            if (target !== undefined) return { dispatcher: "swapwindow", arg: String(target) };
        }
        return { dispatcher: "swapwindow", arg: firstStr.value };
    case "focus":
        if (tbl) {
            if (tbl.map.last) return { dispatcher: "focuscurrentorlast", arg: "" };
            if (tbl.map.urgent_or_last) return { dispatcher: "focusurgentorlast", arg: "" };
            if (tbl.map.direction !== undefined) return { dispatcher: "movefocus", arg: String(tbl.map.direction) };
            if (tbl.map.workspace !== undefined) return { dispatcher: "workspace", arg: String(tbl.map.workspace) };
            if (tbl.map.monitor !== undefined) return { dispatcher: "focusmonitor", arg: String(tbl.map.monitor) };
            if (tbl.map.window !== undefined) return { dispatcher: "focuswindow", arg: String(tbl.map.window) };
        }
        return { dispatcher: "movefocus", arg: firstStr.value };
    case "workspace.toggle_special":
        return { dispatcher: "togglespecialworkspace", arg: firstStr.value };
    case "workspace.rename":
        if (tbl && tbl.map.workspace !== undefined) {
            const nm = tbl.map.name ? ` ${tbl.map.name}` : "";
            return { dispatcher: "renameworkspace", arg: `${tbl.map.workspace}${nm}` };
        }
        return { dispatcher: "renameworkspace", arg: firstStr.value };
    case "workspace.swap_monitors":
        if (tbl && tbl.map.monitor1 !== undefined && tbl.map.monitor2 !== undefined) {
            return { dispatcher: "swapactiveworkspaces", arg: `${tbl.map.monitor1} ${tbl.map.monitor2}` };
        }
        return { dispatcher: "swapactiveworkspaces", arg: firstStr.value };
    case "workspace.change_id":
        if (tbl && tbl.map.workspace !== undefined && tbl.map.id !== undefined) {
            return { dispatcher: "changeworkspaceid", arg: `${tbl.map.workspace} ${tbl.map.id}` };
        }
        return { dispatcher: "changeworkspaceid", arg: firstStr.value };
    case "workspace.move":
        if (tbl && tbl.map.workspace !== undefined && tbl.map.monitor !== undefined) {
            return { dispatcher: "moveworkspacetomonitor", arg: `${tbl.map.workspace} ${tbl.map.monitor}` };
        }
        if (tbl && tbl.map.monitor !== undefined) {
            return { dispatcher: "movecurrentworkspacetomonitor", arg: String(tbl.map.monitor) };
        }
        return { dispatcher: "movecurrentworkspacetomonitor", arg: firstStr.value };
    case "group.toggle":
        return { dispatcher: "togglegroup", arg: "" };
    case "group.next":
        return { dispatcher: "changegroupactive", arg: "f" };
    case "group.prev":
        return { dispatcher: "changegroupactive", arg: "b" };
    case "group.active":
        return { dispatcher: "changegroupactive", arg: tbl && tbl.map.index !== undefined ? String(tbl.map.index) : firstStr.value };
    case "group.lock":
        return { dispatcher: "lockgroups", arg: tbl && tbl.map.action ? String(tbl.map.action) : firstStr.value };
    case "group.lock_active":
        return { dispatcher: "lockactivegroup", arg: tbl && tbl.map.action ? String(tbl.map.action) : firstStr.value };
    case "group.move_window":
        return { dispatcher: "movegroupwindow", arg: tbl && tbl.map.direction ? String(tbl.map.direction) : firstStr.value };
    case "cursor.move":
        if (tbl) return { dispatcher: "movecursor", arg: `${tbl.map.x ?? 0} ${tbl.map.y ?? 0}` };
        return { dispatcher: "movecursor", arg: firstStr.value };
    case "cursor.move_to_corner":
        return { dispatcher: "movecursortocorner", arg: tbl && tbl.map.corner !== undefined ? String(tbl.map.corner) : firstStr.value };
    default: {
        const tail = fn.indexOf(".") !== -1 ? fn.split(".").pop() : fn;
        return { dispatcher: tail.toLowerCase(), arg: rawArgs ? firstStr.value : "", unknownLuaDsp: fn };
    }
    }
}

function hkbSplitComboString(comboStr, sepPattern, warnings, lineNum) {
    const raw = String(comboStr || "").trim();
    if (!raw) return { mods: [], key: "" };
    const tokens = raw.split(sepPattern).map(t => t.trim()).filter(t => t.length > 0);
    if (tokens.length === 0) return { mods: [], key: "" };
    if (tokens.length === 1) {
        return { mods: [], key: hkbNormalizeKey(tokens[0]) };
    }
    const modTokens = tokens.slice(0, -1);
    const keyToken = tokens[tokens.length - 1];
    return {
        mods: hkbNormalizeModifiers(modTokens, warnings, lineNum),
        key: hkbNormalizeKey(keyToken)
    };
}

function hkbStripConfComment(line) {
    let quote = "";
    for (let i = 0; i < line.length; i++) {
        const ch = line.charAt(i);
        if (quote) {
            if (ch === "\\") i++;
            else if (ch === quote) quote = "";
            continue;
        }
        if (ch === "\"" || ch === "'") {
            quote = ch;
            continue;
        }
        if (ch === "#" && i > 0 && /\s/.test(line.charAt(i - 1))) {
            return {
                code: line.slice(0, i).trim(),
                comment: line.slice(i + 1).trim()
            };
        }
    }
    return { code: line.trim(), comment: "" };
}

function hkbSplitHumanLine(line) {
    // Find separator between key combo and action: →, ->, =>, or : (skipping mouse:NN / code:NN / switch:...).
    for (let i = 0; i < line.length; i++) {
        const ch = line.charAt(i);
        if (ch === "→") {
            return { left: line.slice(0, i).trim(), right: line.slice(i + 1).trim() };
        }
        if ((ch === "-" || ch === "=") && line.charAt(i + 1) === ">") {
            return { left: line.slice(0, i).trim(), right: line.slice(i + 2).trim() };
        }
        if (ch === ":") {
            const before = line.slice(0, i).toLowerCase();
            const after = line.slice(i + 1);
            if ((/(?:^|[\s+\-])mouse$/.test(before) || /(?:^|[\s+\-])code$/.test(before)) && /^\d+/.test(after)) {
                continue;
            }
            if (/(?:^|[\s+\-])switch$/.test(before) || /(?:^|[\s+\-])switch:(?:on|off)$/.test(before)) {
                continue;
            }
            return { left: line.slice(0, i).trim(), right: after.trim() };
        }
    }
    return null;
}

function hkbParseHumanCombo(raw, warnings, lineNum) {
    // Support "+" or "-" separators while keeping trailing "+" or "-" keys intact.
    const s = raw.trim();
    if (!s) return { mods: [], key: "" };
    const sep = s.indexOf("+") !== -1 ? "+" : (s.indexOf("-") !== -1 && !/^(mouse|code|switch)/i.test(s) ? "-" : "");
    if (!sep) return { mods: [], key: hkbNormalizeKey(s) };
    let tokens;
    if (s.endsWith(sep + sep)) {
        tokens = s.slice(0, -1).split(sep).map(t => t.trim()).filter(t => t.length > 0);
        tokens.push(sep);
    } else {
        tokens = s.split(sep).map(t => t.trim()).filter(t => t.length > 0);
    }
    if (tokens.length <= 1) return { mods: [], key: hkbNormalizeKey(tokens[0] || s) };
    return {
        mods: hkbNormalizeModifiers(tokens.slice(0, -1), warnings, lineNum),
        key: hkbNormalizeKey(tokens[tokens.length - 1])
    };
}

function hkbParseLuaStatement(stmt, lineNum, submap, warnings) {
    const clean = stmt.replace(/\s*--.*$/, "").trim();
    let isUnbind = false;
    let inner = "";
    const unbindM = /^(?:pcall\s*\(\s*hl\.unbind\s*,|hl\.unbind\s*\()([\s\S]+)\)$/.exec(clean);
    if (unbindM) {
        isUnbind = true;
        inner = unbindM[1].trim();
    } else {
        const bindM = /^hl\.bind\s*\(([\s\S]+)\)$/.exec(clean);
        if (!bindM) return null;
        inner = bindM[1].trim();
    }

    const args = hkbSplitTopLevel(inner, ",");
    if (args.length === 0 || !args[0]) {
        warnings.push(`Line ${lineNum}: hl.${isUnbind ? "unbind" : "bind"} is missing key combo`);
        return null;
    }

    const comboRaw = hkbParseLuaStringValue(args[0]).value;
    const combo = hkbSplitComboString(comboRaw, /\s*\+\s*/, warnings, lineNum);

    if (isUnbind) {
        return {
            kind: "unbind",
            line: lineNum,
            submap,
            mods: combo.mods,
            key: combo.key,
            flags: [],
            dispatcher: "",
            arg: "",
            description: ""
        };
    }

    if (args.length < 2 || !args[1]) {
        warnings.push(`Line ${lineNum}: hl.bind is missing dispatcher action`);
        return null;
    }

    let action = null;
    let optsIdx = 2;
    const firstActionVal = hkbParseLuaStringValue(args[1]);
    if (firstActionVal.isLiteral && args.length >= 3 && !args[2].trim().startsWith("{")) {
        // Handle hl.bind("SUPER + T", "exec", "kitty", { ... })
        action = {
            dispatcher: firstActionVal.value.toLowerCase(),
            arg: hkbParseLuaStringValue(args[2]).value
        };
        optsIdx = 3;
    } else {
        action = hkbParseLuaDispatcher(args[1]);
    }

    const flags = [];
    let description = "";
    if (args.length > optsIdx && args[optsIdx]) {
        const tbl = hkbParseLuaTable(args[optsIdx]);
        if (tbl) {
            const keys = Object.keys(tbl.map);
            for (let i = 0; i < keys.length; i++) {
                const k = keys[i];
                const v = tbl.map[k];
                if (k === "description") {
                    description = String(v);
                } else if (hkbHasOwn(HKB_LUA_TO_FLAG, k)) {
                    if (v) {
                        const f = HKB_LUA_TO_FLAG[k];
                        if (flags.indexOf(f) === -1) flags.push(f);
                    }
                } else {
                    warnings.push(`Line ${lineNum}: Unknown Lua bind option "${k}"`);
                }
            }
        }
    }
    if (action.isMouseOp && flags.indexOf("m") === -1) {
        flags.push("m");
    }

    return {
        kind: "bind",
        line: lineNum,
        submap,
        mods: combo.mods,
        key: combo.key,
        flags,
        dispatcher: action.dispatcher,
        arg: action.arg,
        description,
        isLuaCallback: Boolean(action.isLuaCallback),
        unknownLuaDsp: action.unknownLuaDsp || ""
    };
}

function hkbParseConfLine(line, lineNum, submap, warnings) {
    const stripped = hkbStripConfComment(line);
    const code = stripped.code;
    const comment = stripped.comment;

    const unbindM = /^unbind\s*=\s*(.+)$/i.exec(code);
    if (unbindM) {
        const parts = hkbSplitTopLevel(unbindM[1], ",");
        const mods = parts[0] ? hkbNormalizeModifiers(parts[0].split(/[\s+&]+/), warnings, lineNum) : [];
        const key = hkbNormalizeKey(parts[1] || "");
        return {
            kind: "unbind",
            line: lineNum,
            submap,
            mods,
            key,
            flags: [],
            dispatcher: "",
            arg: "",
            description: comment
        };
    }

    const bindM = /^bind([a-z]*)\s*=\s*(.*)$/i.exec(code);
    if (!bindM) return null;

    const rawFlags = bindM[1].toLowerCase();
    const rest = bindM[2];
    const flags = [];
    let hasDescField = false;
    for (let i = 0; i < rawFlags.length; i++) {
        const ch = rawFlags.charAt(i);
        if (ch === "d") {
            hasDescField = true;
        } else if (hkbHasOwn(HKB_FLAG_LABELS, ch)) {
            if (flags.indexOf(ch) === -1) flags.push(ch);
        } else {
            warnings.push(`Line ${lineNum}: Unknown bind flag "${ch}" in "bind${rawFlags}"`);
        }
    }

    const expectedBeforeParams = hasDescField ? 4 : 3;
    const fields = [];
    let start = 0;
    for (let i = 0; i < rest.length && fields.length < expectedBeforeParams; i++) {
        if (rest.charAt(i) === ",") {
            fields.push(rest.slice(start, i).trim());
            start = i + 1;
        }
    }
    const tail = rest.slice(start).trim();
    if (fields.length < expectedBeforeParams) {
        fields.push(tail);
    } else if (tail.length > 0) {
        fields.push(tail);
    }

    if (fields.length < expectedBeforeParams) {
        warnings.push(`Line ${lineNum}: Incomplete bind (expected ${expectedBeforeParams} comma-separated fields)`);
        return null;
    }

    const mods = fields[0] ? hkbNormalizeModifiers(fields[0].split(/[\s+&]+/), warnings, lineNum) : [];
    const key = hkbNormalizeKey(fields[1]);
    let description = comment;
    let dispatcherIdx = 2;
    if (hasDescField) {
        description = fields[2] || comment;
        dispatcherIdx = 3;
    }
    const dispatcher = String(fields[dispatcherIdx] || "").trim().toLowerCase();
    const arg = fields.length > dispatcherIdx + 1 ? fields[dispatcherIdx + 1].trim() : "";

    return {
        kind: "bind",
        line: lineNum,
        submap,
        mods,
        key,
        flags,
        dispatcher,
        arg,
        description
    };
}

function hkbParseHumanLine(line, lineNum, submap, warnings) {
    const stripped = hkbStripConfComment(line);
    const split = hkbSplitHumanLine(stripped.code);
    if (!split || !split.left || !split.right) return null;

    const combo = hkbParseHumanCombo(split.left, warnings, lineNum);
    if (!combo.key) return null;

    const rhs = split.right.trim();
    let dispatcher = "";
    let arg = "";
    const commaIdx = rhs.indexOf(",");
    const spaceMatch = /^([^\s,]+)(?:[\s,]+([\s\S]*))?$/.exec(rhs);
    if (!spaceMatch) return null;

    dispatcher = spaceMatch[1].trim().toLowerCase();
    arg = (spaceMatch[2] || "").trim();
    if (commaIdx !== -1 && rhs.slice(0, commaIdx).trim().toLowerCase() === dispatcher) {
        arg = rhs.slice(commaIdx + 1).trim();
    }

    return {
        kind: "bind",
        line: lineNum,
        submap,
        mods: combo.mods,
        key: combo.key,
        flags: [],
        dispatcher,
        arg,
        description: stripped.comment
    };
}

function hkbCountLuaNestingDelta(line) {
    let paren = 0;
    let quote = "";
    for (let i = 0; i < line.length; i++) {
        const ch = line.charAt(i);
        if (quote) {
            if (quote === "]]") {
                if (ch === "]" && line.charAt(i - 1) === "]") quote = "";
            } else if (ch === "\\") {
                i++;
            } else if (ch === quote) {
                quote = "";
            }
            continue;
        }
        if (ch === "-" && line.charAt(i + 1) === "-") break;
        if (ch === "\"" || ch === "'") quote = ch;
        else if (ch === "[" && line.charAt(i + 1) === "[") { quote = "]]"; i++; }
        else if (ch === "(") paren++;
        else if (ch === ")") paren--;
    }
    return paren;
}

function hkbParseInput(text) {
    const lines = String(text || "").split(/\r?\n/);
    const entries = [];
    const warnings = [];
    const submapStack = [];
    let confSubmap = "";
    let i = 0;

    while (i < lines.length) {
        const raw = lines[i];
        const trimmed = raw.trim();
        const lineNum = i + 1;

        if (!trimmed || trimmed.startsWith("#") || trimmed.startsWith("//") || trimmed.startsWith("--")) {
            i++;
            continue;
        }

        const curSubmap = submapStack.length > 0 ? submapStack[submapStack.length - 1] : confSubmap;

        // Lua submap block header: hl.define_submap("name", function()
        const luaSubM = /^hl\.define_submap\s*\(\s*(?:"([^"]+)"|'([^']+)')\s*,\s*function\s*\(\s*\)/.exec(trimmed);
        if (luaSubM) {
            submapStack.push(luaSubM[1] || luaSubM[2] || "");
            i++;
            continue;
        }
        if (submapStack.length > 0 && /^end\s*\)$/.test(trimmed)) {
            submapStack.pop();
            i++;
            continue;
        }

        // Conf submap directive: submap = name | reset
        const confSubM = /^submap\s*=\s*(.+)$/i.exec(trimmed);
        if (confSubM) {
            const name = hkbStripConfComment(confSubM[1]).code;
            confSubmap = name.toLowerCase() === "reset" ? "" : name;
            i++;
            continue;
        }

        // Multi-line or single-line Lua bind/unbind
        if (/^(?:hl\.bind|hl\.unbind|pcall\s*\(\s*hl\.unbind)\s*[(,]/.test(trimmed)) {
            let stmt = trimmed;
            let depth = hkbCountLuaNestingDelta(trimmed);
            while (depth > 0 && i + 1 < lines.length) {
                i++;
                const nextLine = lines[i];
                stmt += "\n" + nextLine;
                depth += hkbCountLuaNestingDelta(nextLine);
            }
            const parsedLua = hkbParseLuaStatement(stmt, lineNum, curSubmap, warnings);
            if (parsedLua) entries.push(parsedLua);
            i++;
            continue;
        }

        // Conf bind/unbind
        if (/^(?:bind[a-z]*|unbind)\s*=/i.test(trimmed)) {
            const parsedConf = hkbParseConfLine(trimmed, lineNum, curSubmap, warnings);
            if (parsedConf) entries.push(parsedConf);
            i++;
            continue;
        }

        // Human notation: Super+Shift+T: exec kitty / Ctrl+Alt+Delete → exit
        const parsedHuman = hkbParseHumanLine(trimmed, lineNum, curSubmap, warnings);
        if (parsedHuman) {
            entries.push(parsedHuman);
            i++;
            continue;
        }

        warnings.push(`Line ${lineNum}: Could not parse "${trimmed.length > 48 ? trimmed.slice(0, 45) + "..." : trimmed}"`);
        i++;
    }

    return { entries, warnings };
}

function hkbValidateEntries(entries, warnings) {
    const activeCombos = {};

    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        if (!e.key) {
            warnings.push(`Line ${e.line}: Missing key in bind`);
        }

        const comboId = `${e.submap || ""}|${e.mods.join("+")}+${e.key.toLowerCase()}|${e.flags.indexOf("r") !== -1 ? "R" : "P"}`;
        if (e.kind === "unbind") {
            delete activeCombos[comboId];
            continue;
        }

        const comboLabel = hkbFormatCombo(e.mods, e.key, " + ");
        if (hkbHasOwn(activeCombos, comboId)) {
            warnings.push(`Line ${e.line}: Duplicate key combo "${comboLabel}" (already bound on line ${activeCombos[comboId]})`);
        } else {
            activeCombos[comboId] = e.line;
        }

        if (e.isLuaCallback) continue;

        if (e.unknownLuaDsp) {
            warnings.push(`Line ${e.line}: Unknown hl.dsp function "hl.dsp.${e.unknownLuaDsp}"`);
            continue;
        }

        if (!e.dispatcher) {
            warnings.push(`Line ${e.line}: Missing dispatcher`);
            continue;
        }

        const spec = hkbHasOwn(HKB_DISPATCHERS, e.dispatcher) ? HKB_DISPATCHERS[e.dispatcher] : null;
        if (!spec) {
            const suggestion = hkbSuggestDispatcher(e.dispatcher);
            const hint = suggestion ? ` (did you mean "${suggestion}"?)` : "";
            warnings.push(`Line ${e.line}: Unknown dispatcher "${e.dispatcher}"${hint}`);
            continue;
        }

        const hasArg = e.arg.length > 0;
        if (spec.arg === "required" && !hasArg) {
            warnings.push(`Line ${e.line}: "${e.dispatcher}" requires an argument (${spec.hint || "value"})`);
        } else if (spec.arg === "none" && hasArg) {
            warnings.push(`Line ${e.line}: "${e.dispatcher}" takes no arguments (got "${e.arg}")`);
        }

        // Targeted value checks for common dispatchers
        if (e.dispatcher === "movefocus" && hasArg && !/^[lrud]$/.test(e.arg)) {
            warnings.push(`Line ${e.line}: "movefocus" expects direction l, r, u, or d (got "${e.arg}")`);
        } else if (e.dispatcher === "movewindow") {
            const isMouse = e.flags.indexOf("m") !== -1 || e.key.startsWith("mouse:");
            if (!hasArg && !isMouse) {
                warnings.push(`Line ${e.line}: "movewindow" requires direction (l, r, u, d) or mouse flag (bindm)`);
            }
        } else if (e.dispatcher === "dpms" && hasArg) {
            const firstWord = e.arg.split(/\s+/)[0].toLowerCase();
            if (["on", "off", "toggle"].indexOf(firstWord) === -1) {
                warnings.push(`Line ${e.line}: "dpms" expects on, off, or toggle (got "${e.arg}")`);
            }
        } else if (e.dispatcher === "lockgroups" && hasArg) {
            if (["lock", "unlock", "toggle"].indexOf(e.arg.toLowerCase()) === -1) {
                warnings.push(`Line ${e.line}: "lockgroups" expects lock, unlock, or toggle (got "${e.arg}")`);
            }
        }
    }
}

function hkbParseMoveResizeArgs(arg, expectWindow) {
    let s = String(arg || "").trim();
    let windowSel = "";
    if (expectWindow) {
        const comma = s.indexOf(",");
        if (comma === -1) return null;
        windowSel = s.slice(comma + 1).trim();
        s = s.slice(0, comma).trim();
        if (!windowSel) return null;
    }
    let exact = false;
    if (/^exact\s+/i.test(s)) {
        exact = true;
        s = s.replace(/^exact\s+/i, "").trim();
    }
    const parts = s.split(/\s+/).filter(p => p.length > 0);
    if (parts.length !== 2) return null;
    if (!/^-?\d+(\.\d+)?$/.test(parts[0]) || !/^-?\d+(\.\d+)?$/.test(parts[1])) return null;
    return {
        x: Number(parts[0]),
        y: Number(parts[1]),
        exact,
        window: windowSel
    };
}

function hkbFormatLuaAction(e) {
    const d = e.dispatcher;
    const a = e.arg;
    const esc = v => `"${hkbEscapeLuaString(v)}"`;

    if (e.unknownLuaDsp) {
        return { expr: null, reason: "" };
    }

    switch (d) {
    case "exec":
        return { expr: `hl.dsp.exec_cmd(${esc(a)})` };
    case "execr":
        return { expr: `hl.dsp.exec_raw(${esc(a)})` };
    case "global":
        return { expr: `hl.dsp.global(${esc(a)})` };
    case "killactive":
        return { expr: "hl.dsp.window.close()" };
    case "forcekillactive":
        return { expr: "hl.dsp.window.kill()" };
    case "closewindow":
        return { expr: `hl.dsp.window.close({ window = ${esc(a)} })` };
    case "killwindow":
        return { expr: `hl.dsp.window.kill({ window = ${esc(a)} })` };
    case "signal":
        if (/^-?\d+$/.test(a.trim())) {
            return { expr: `hl.dsp.window.signal({ signal = ${Number(a.trim())} })` };
        }
        return { expr: null, reason: `"hl.dsp.window.signal" requires a numeric signal (got "${a}")` };
    case "signalwindow": {
        const parts = hkbSplitTopLevel(a, ",");
        const win = (parts[0] || "").trim();
        const sig = (parts[1] || "").trim();
        if (win && /^-?\d+$/.test(sig)) {
            return { expr: `hl.dsp.window.signal({ window = ${esc(win)}, signal = ${Number(sig)} })` };
        }
        return { expr: null, reason: `"signalwindow" requires window and numeric signal (got "${a}")` };
    }
    case "togglefloating":
        return { expr: a ? `hl.dsp.window.float({ action = "toggle", window = ${esc(a)} })` : "hl.dsp.window.float({ action = \"toggle\" })" };
    case "setfloating":
        return { expr: a ? `hl.dsp.window.float({ action = "float", window = ${esc(a)} })` : "hl.dsp.window.float({ action = \"float\" })" };
    case "settiled":
        return { expr: a ? `hl.dsp.window.float({ action = "tile", window = ${esc(a)} })` : "hl.dsp.window.float({ action = \"tile\" })" };
    case "fullscreen":
        return {
            expr: a === "1"
                ? "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })"
                : "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })"
        };
    case "fullscreenstate": {
        const parts = a.split(/[\s,]+/).filter(p => p.length > 0);
        const internal = /^-?\d+$/.test(parts[0] || "") ? Number(parts[0]) : 0;
        const client = /^-?\d+$/.test(parts[1] || "") ? Number(parts[1]) : 0;
        return { expr: `hl.dsp.window.fullscreen_state({ internal = ${internal}, client = ${client}, action = "toggle" })` };
    }
    case "pin":
        return { expr: a ? `hl.dsp.window.pin({ window = ${esc(a)} })` : "hl.dsp.window.pin()" };
    case "pseudo":
        return { expr: a ? `hl.dsp.window.pseudo({ window = ${esc(a)} })` : "hl.dsp.window.pseudo()" };
    case "centerwindow":
        return { expr: a.trim() === "1" ? "hl.dsp.window.center({ preserve_size = true })" : "hl.dsp.window.center()" };
    case "bringactivetotop":
        return { expr: "hl.dsp.window.bring_to_top()" };
    case "alterzorder": {
        const parts = hkbSplitTopLevel(a, ",");
        const mode = (parts[0] || "").trim().toLowerCase();
        const win = (parts[1] || "").trim();
        if (mode !== "top" && mode !== "bottom") {
            return { expr: null, reason: `"alterzorder" expects top or bottom (got "${a}")` };
        }
        return { expr: win ? `hl.dsp.window.alter_zorder({ mode = ${esc(mode)}, window = ${esc(win)} })` : `hl.dsp.window.alter_zorder({ mode = ${esc(mode)} })` };
    }
    case "movefocus":
        return { expr: `hl.dsp.focus({ direction = ${esc(a)} })` };
    case "focuswindow":
        return { expr: `hl.dsp.focus({ window = ${esc(a)} })` };
    case "focusmonitor":
        return { expr: `hl.dsp.focus({ monitor = ${esc(a)} })` };
    case "focuscurrentorlast":
        return { expr: "hl.dsp.focus({ last = true })" };
    case "focusurgentorlast":
        return { expr: "hl.dsp.focus({ urgent_or_last = true })" };
    case "workspace":
        return { expr: `hl.dsp.focus({ workspace = ${esc(a)} })` };
    case "movewindow":
        if (!a) return { expr: "hl.dsp.window.drag()" };
        if (/^[lrud]$/.test(a)) return { expr: `hl.dsp.window.move({ direction = ${esc(a)} })` };
        if (/^mon:.+$/i.test(a)) return { expr: `hl.dsp.window.move({ monitor = ${esc(a.slice(4))} })` };
        return { expr: null, reason: `"movewindow" argument "${a}" has no hl.dsp.window.move equivalent` };
    case "resizewindow": {
        if (!a) return { expr: "hl.dsp.window.resize()" };
        const parsed = hkbParseMoveResizeArgs(a, false);
        if (!parsed) return { expr: null, reason: `"resizewindow" argument "${a}" cannot be represented as hl.dsp.window.resize` };
        return { expr: `hl.dsp.window.resize({ x = ${parsed.x}, y = ${parsed.y}${parsed.exact ? ", exact = true" : ""} })` };
    }
    case "resizeactive": {
        const parsed = hkbParseMoveResizeArgs(a, false);
        if (!parsed) return { expr: null, reason: `"resizeactive" argument "${a}" cannot be represented as numeric hl.dsp.window.resize({ x, y })` };
        return { expr: `hl.dsp.window.resize({ x = ${parsed.x}, y = ${parsed.y}${parsed.exact ? ", exact = true" : ""} })` };
    }
    case "moveactive": {
        const parsed = hkbParseMoveResizeArgs(a, false);
        if (!parsed) return { expr: null, reason: `"moveactive" argument "${a}" cannot be represented as numeric hl.dsp.window.move({ x, y })` };
        return { expr: `hl.dsp.window.move({ x = ${parsed.x}, y = ${parsed.y}${parsed.exact ? ", exact = true" : ""} })` };
    }
    case "resizewindowpixel": {
        const parsed = hkbParseMoveResizeArgs(a, true);
        if (!parsed) return { expr: null, reason: `"resizewindowpixel" argument "${a}" cannot be represented as hl.dsp.window.resize({ x, y, window })` };
        return { expr: `hl.dsp.window.resize({ x = ${parsed.x}, y = ${parsed.y}, window = ${esc(parsed.window)}${parsed.exact ? ", exact = true" : ""} })` };
    }
    case "movewindowpixel": {
        const parsed = hkbParseMoveResizeArgs(a, true);
        if (!parsed) return { expr: null, reason: `"movewindowpixel" argument "${a}" cannot be represented as hl.dsp.window.move({ x, y, window })` };
        return { expr: `hl.dsp.window.move({ x = ${parsed.x}, y = ${parsed.y}, window = ${esc(parsed.window)}${parsed.exact ? ", exact = true" : ""} })` };
    }
    case "swapwindow":
        return { expr: /^[lrud]$/.test(a) ? `hl.dsp.window.swap({ direction = ${esc(a)} })` : `hl.dsp.window.swap({ target = ${esc(a)} })` };
    case "swapnext":
        return { expr: a.trim().toLowerCase() === "prev" ? "hl.dsp.window.swap({ prev = true })" : "hl.dsp.window.swap({ next = true })" };
    case "cyclenext":
        return { expr: a ? `hl.dsp.window.cycle_next(${esc(a)})` : "hl.dsp.window.cycle_next()" };
    case "movetoworkspace": {
        const parts = hkbSplitTopLevel(a, ",");
        const ws = (parts[0] || "").trim();
        const win = (parts[1] || "").trim();
        return { expr: win ? `hl.dsp.window.move({ workspace = ${esc(ws)}, window = ${esc(win)} })` : `hl.dsp.window.move({ workspace = ${esc(ws)} })` };
    }
    case "movetoworkspacesilent": {
        const parts = hkbSplitTopLevel(a, ",");
        const ws = (parts[0] || "").trim();
        const win = (parts[1] || "").trim();
        return { expr: win ? `hl.dsp.window.move({ workspace = ${esc(ws)}, window = ${esc(win)}, silent = true })` : `hl.dsp.window.move({ workspace = ${esc(ws)}, silent = true })` };
    }
    case "togglespecialworkspace":
        return { expr: a ? `hl.dsp.workspace.toggle_special(${esc(a)})` : "hl.dsp.workspace.toggle_special(\"special\")" };
    case "movecurrentworkspacetomonitor":
        return { expr: `hl.dsp.workspace.move({ monitor = ${esc(a)} })` };
    case "moveworkspacetomonitor": {
        const parts = a.trim().split(/\s+/).filter(p => p.length > 0);
        if (parts.length < 2) return { expr: null, reason: `"moveworkspacetomonitor" expects workspace and monitor` };
        return { expr: `hl.dsp.workspace.move({ workspace = ${esc(parts[0])}, monitor = ${esc(parts.slice(1).join(" "))} })` };
    }
    case "renameworkspace": {
        const trimmed = a.trim();
        const sp = trimmed.search(/\s/);
        const wsTok = sp === -1 ? trimmed : trimmed.slice(0, sp);
        const nameTok = sp === -1 ? "" : trimmed.slice(sp + 1).trim();
        if (!wsTok) return { expr: null, reason: `"renameworkspace" expects workspace id` };
        const wsExpr = /^-?\d+$/.test(wsTok) ? Number(wsTok) : esc(wsTok);
        return { expr: nameTok ? `hl.dsp.workspace.rename({ workspace = ${wsExpr}, name = ${esc(nameTok)} })` : `hl.dsp.workspace.rename({ workspace = ${wsExpr} })` };
    }
    case "swapactiveworkspaces": {
        const parts = a.trim().split(/\s+/).filter(p => p.length > 0);
        if (parts.length < 2) return { expr: null, reason: `"swapactiveworkspaces" expects two monitors` };
        return { expr: `hl.dsp.workspace.swap_monitors({ monitor1 = ${esc(parts[0])}, monitor2 = ${esc(parts[1])} })` };
    }
    case "changeworkspaceid": {
        const parts = a.trim().split(/\s+/).filter(p => p.length > 0);
        if (parts.length < 2 || !/^-?\d+$/.test(parts[1])) {
            return { expr: null, reason: `"changeworkspaceid" expects workspace and numeric id` };
        }
        return { expr: `hl.dsp.workspace.change_id({ workspace = ${esc(parts[0])}, id = ${Number(parts[1])} })` };
    }
    case "layoutmsg":
        return { expr: `hl.dsp.layout(${esc(a)})` };
    case "togglesplit":
        return { expr: "hl.dsp.layout(\"togglesplit\")" };
    case "swapsplit":
        return { expr: "hl.dsp.layout(\"swapsplit\")" };
    case "splitratio":
        return { expr: `hl.dsp.layout(${esc("splitratio " + a)})` };
    case "toggleopaque":
        return { expr: "hl.dsp.window.set_prop({ prop = \"opaque\", value = \"toggle\" })" };
    case "setprop": {
        const parts = a.trim().split(/\s+/).filter(p => p.length > 0);
        if (parts.length < 3) return { expr: null, reason: `"setprop" expects window, prop, and value` };
        return { expr: `hl.dsp.window.set_prop({ window = ${esc(parts[0])}, prop = ${esc(parts[1])}, value = ${esc(parts.slice(2).join(" "))} })` };
    }
    case "tagwindow": {
        const parts = a.trim().split(/\s+/).filter(p => p.length > 0);
        if (parts.length === 0) return { expr: null, reason: `"tagwindow" expects a tag` };
        if (parts.length === 1) return { expr: `hl.dsp.window.tag({ tag = ${esc(parts[0])} })` };
        return { expr: `hl.dsp.window.tag({ tag = ${esc(parts[0])}, window = ${esc(parts.slice(1).join(" "))} })` };
    }
    case "cleartags":
        return { expr: a ? `hl.dsp.window.clear_tags({ window = ${esc(a)} })` : "hl.dsp.window.clear_tags()" };
    case "toggleswallow":
        return { expr: a ? `hl.dsp.window.toggle_swallow({ window = ${esc(a)} })` : "hl.dsp.window.toggle_swallow()" };
    case "togglegroup":
        return { expr: "hl.dsp.group.toggle()" };
    case "changegroupactive":
        if (a === "b") return { expr: "hl.dsp.group.prev()" };
        if (!a || a === "f") return { expr: "hl.dsp.group.next()" };
        return { expr: `hl.dsp.group.active({ index = ${/^\d+$/.test(a.trim()) ? Number(a.trim()) : esc(a)} })` };
    case "lockgroups":
        return { expr: `hl.dsp.group.lock(${esc(a)})` };
    case "lockactivegroup":
        return { expr: `hl.dsp.group.lock_active(${esc(a)})` };
    case "moveintogroup":
        return { expr: `hl.dsp.window.move({ into_group = ${esc(a)} })` };
    case "moveoutofgroup":
        return { expr: a ? `hl.dsp.window.move({ out_of_group = ${esc(a)} })` : "hl.dsp.window.move({ out_of_group = true })" };
    case "movewindoworgroup":
        return { expr: `hl.dsp.window.move({ direction = ${esc(a)}, group = true })` };
    case "movegroupwindow":
        return { expr: a ? `hl.dsp.group.move_window(${esc(a)})` : "hl.dsp.group.move_window(\"f\")" };
    case "denywindowfromgroup":
        return { expr: `hl.dsp.window.deny_from_group(${esc(a)})` };
    case "movecursortocorner":
        if (!/^[0-3]$/.test(a.trim())) return { expr: null, reason: `"movecursortocorner" expects corner 0-3` };
        return { expr: `hl.dsp.cursor.move_to_corner({ corner = ${Number(a.trim())} })` };
    case "movecursor": {
        const parts = a.trim().split(/\s+/).filter(p => p.length > 0);
        if (parts.length !== 2 || !/^-?\d+$/.test(parts[0]) || !/^-?\d+$/.test(parts[1])) {
            return { expr: null, reason: `"movecursor" expects numeric x y coordinates` };
        }
        return { expr: `hl.dsp.cursor.move({ x = ${Number(parts[0])}, y = ${Number(parts[1])} })` };
    }
    case "submap":
        return { expr: `hl.dsp.submap(${esc(a)})` };
    case "dpms": {
        const words = a.trim().split(/\s+/).filter(p => p.length > 0);
        const rawAct = (words[0] || "").toLowerCase();
        const act = rawAct === "on" ? "enable" : (rawAct === "off" ? "disable" : rawAct);
        if (["enable", "disable", "toggle"].indexOf(act) === -1) {
            return { expr: null, reason: "" };
        }
        return { expr: words[1] ? `hl.dsp.dpms({ action = ${esc(act)}, monitor = ${esc(words[1])} })` : `hl.dsp.dpms({ action = ${esc(act)} })` };
    }
    case "exit":
        return { expr: "hl.dsp.exit()" };
    case "forcerendererreload":
        return { expr: "hl.dsp.force_renderer_reload()" };
    case "forceidle":
        if (!/^-?\d+(\.\d+)?$/.test(a.trim())) return { expr: null, reason: `"forceidle" expects numeric seconds` };
        return { expr: `hl.dsp.force_idle(${Number(a.trim())})` };
    case "releaseinputcapture":
        return { expr: "hl.dsp.release_input_capture()" };
    case "pass":
        return { expr: a ? `hl.dsp.pass({ window = ${esc(a)} })` : "hl.dsp.no_op()" };
    case "sendshortcut": {
        const parts = hkbSplitTopLevel(a, ",");
        const mods = (parts[0] || "").trim();
        const key = (parts[1] || "").trim();
        const win = (parts[2] || "").trim();
        if (!key) return { expr: null, reason: `"sendshortcut" expects mods, key[, window]` };
        return { expr: `hl.dsp.send_shortcut({ mods = ${esc(mods)}, key = ${esc(key)}${win ? `, window = ${esc(win)}` : ""} })` };
    }
    case "sendkeystate": {
        const parts = hkbSplitTopLevel(a, ",");
        const mods = (parts[0] || "").trim();
        const key = (parts[1] || "").trim();
        const state = (parts[2] || "").trim().toLowerCase();
        const win = (parts[3] || "").trim();
        if (!key || ["down", "up", "repeat"].indexOf(state) === -1) {
            return { expr: null, reason: `"sendkeystate" expects mods, key, state (down/up/repeat)[, window]` };
        }
        return { expr: `hl.dsp.send_key_state({ mods = ${esc(mods)}, key = ${esc(key)}, state = ${esc(state)}${win ? `, window = ${esc(win)}` : ""} })` };
    }
    case "event":
        return { expr: `hl.dsp.event(${esc(a)})` };
    default:
        if (hkbHasOwn(HKB_DISPATCHERS, d)) {
            return { expr: null, reason: `Dispatcher "${d}" has no Lua hl.dsp equivalent` };
        }
        return { expr: null, reason: "" };
    }
}

function hkbFormatLua(entries, warnings) {
    const out = [];
    let openSubmap = "";

    const closeSubmapIfNeeded = nextSubmap => {
        if (openSubmap && openSubmap !== nextSubmap) {
            out.push("end)");
            openSubmap = "";
        }
    };

    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        const targetSubmap = e.submap || "";
        closeSubmapIfNeeded(targetSubmap);
        if (targetSubmap && openSubmap !== targetSubmap) {
            out.push(`hl.define_submap("${hkbEscapeLuaString(targetSubmap)}", function()`);
            openSubmap = targetSubmap;
        }
        const indent = openSubmap ? "    " : "";
        const combo = hkbFormatCombo(e.mods, e.key, " + ");

        if (e.kind === "unbind") {
            out.push(`${indent}hl.unbind("${hkbEscapeLuaString(combo)}")`);
            continue;
        }

        const optParts = [];
        for (let f = 0; f < HKB_CONF_FLAG_ORDER.length; f++) {
            const flag = HKB_CONF_FLAG_ORDER[f];
            if (e.flags.indexOf(flag) !== -1 && hkbHasOwn(HKB_FLAG_TO_LUA, flag)) {
                optParts.push(`${HKB_FLAG_TO_LUA[flag]} = true`);
            }
        }
        if (e.description) {
            optParts.push(`description = "${hkbEscapeLuaString(e.description)}"`);
        }

        const optsStr = optParts.length > 0 ? `, { ${optParts.join(", ")} }` : "";
        if (e.isLuaCallback) {
            out.push(`${indent}hl.bind("${hkbEscapeLuaString(combo)}", function() end${optsStr})`);
            continue;
        }
        const actionRes = hkbFormatLuaAction(e);
        if (actionRes.expr) {
            out.push(`${indent}hl.bind("${hkbEscapeLuaString(combo)}", ${actionRes.expr}${optsStr})`);
        } else {
            const dispArg = e.arg ? `, "${hkbEscapeLuaString(e.arg)}"` : "";
            out.push(`${indent}-- hl.bind("${hkbEscapeLuaString(combo)}", "${hkbEscapeLuaString(e.dispatcher)}"${dispArg}${optsStr})`);
            if (actionRes.reason) {
                warnings.push(`Line ${e.line}: ${actionRes.reason} (commented out)`);
            }
        }
    }
    closeSubmapIfNeeded("");

    if (warnings.length > 0) {
        out.push("");
        for (let i = 0; i < warnings.length; i++) {
            out.push(`-- [!] ${warnings[i]}`);
        }
    }
    return out.join("\n");
}

function hkbFormatConf(entries, warnings) {
    const out = [];
    let openSubmap = "";

    const closeSubmapIfNeeded = nextSubmap => {
        if (openSubmap && openSubmap !== nextSubmap) {
            out.push("submap = reset");
            openSubmap = "";
        }
    };

    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        const targetSubmap = e.submap || "";
        closeSubmapIfNeeded(targetSubmap);
        if (targetSubmap && openSubmap !== targetSubmap) {
            out.push(`submap = ${targetSubmap}`);
            openSubmap = targetSubmap;
        }

        const modsStr = e.mods.join(" ");
        if (e.kind === "unbind") {
            out.push(`unbind = ${modsStr}, ${e.key}`);
            continue;
        }

        let flagStr = "";
        for (let f = 0; f < HKB_CONF_FLAG_ORDER.length; f++) {
            const ch = HKB_CONF_FLAG_ORDER[f];
            if (e.flags.indexOf(ch) !== -1) flagStr += ch;
        }
        const kw = "bind" + flagStr;
        const fields = [modsStr, e.key, e.dispatcher];
        if (e.arg) fields.push(e.arg);
        const desc = e.description ? ` # ${e.description}` : "";
        out.push(`${kw} = ${fields.join(", ")}${desc}`);
    }
    closeSubmapIfNeeded("");

    if (warnings.length > 0) {
        out.push("");
        for (let i = 0; i < warnings.length; i++) {
            out.push(`# [!] ${warnings[i]}`);
        }
    }
    return out.join("\n");
}

function hkbFormatTable(entries, warnings) {
    const hasFlags = entries.some(e => e.kind === "unbind" || e.flags.length > 0);
    const hasDesc = entries.some(e => Boolean(e.description));
    const headers = ["Keys"];
    if (hasFlags) headers.push("Flags");
    headers.push("Dispatcher", "Argument");
    if (hasDesc) headers.push("Description");

    const rows = [];
    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        const keys = (e.submap ? `[${e.submap}] ` : "") + hkbFormatCombo(e.mods, e.key, " + ");
        const flags = e.kind === "unbind"
            ? "unbind"
            : (e.flags.length > 0 ? e.flags.map(f => HKB_FLAG_LABELS[f] || f).join(", ") : "-");
        const disp = e.kind === "unbind" ? "-" : e.dispatcher;
        const arg = e.arg || "-";
        const desc = e.description || "-";
        const row = [keys];
        if (hasFlags) row.push(flags);
        row.push(disp, arg);
        if (hasDesc) row.push(desc);
        rows.push(row);
    }

    const widths = headers.map(h => h.length);
    for (let i = 0; i < rows.length; i++) {
        for (let c = 0; c < headers.length; c++) {
            if (rows[i][c].length > widths[c]) widths[c] = rows[i][c].length;
        }
    }

    const padRow = cols => cols.map((col, idx) => idx === cols.length - 1 ? col : col.padEnd(widths[idx])).join("  ");
    const sepRow = widths.map(w => "-".repeat(w)).join("  ");

    const out = [padRow(headers), sepRow];
    for (let i = 0; i < rows.length; i++) {
        out.push(padRow(rows[i]));
    }

    if (warnings.length > 0) {
        out.push("", `Warnings (${warnings.length}):`);
        for (let i = 0; i < warnings.length; i++) {
            out.push(`  ! ${warnings[i]}`);
        }
    }
    return out.join("\n");
}

function toolHyprKeybind(input = "", options = {}) {
    const text = String(input);
    if (text.trim().length === 0) {
        return { output: "" };
    }

    const to = String(options.to || "lua");
    if (["lua", "conf", "table"].indexOf(to) === -1) {
        return { output: "", error: `Unsupported output format "${to}". Choose lua, conf, or table.` };
    }

    const parsed = hkbParseInput(text);
    if (parsed.entries.length === 0) {
        return {
            output: "",
            error: "No valid keybinds found. Use Lua hl.bind(...), hyprland.conf (bind = ...), or Super+Key: dispatcher [arg]."
        };
    }

    hkbValidateEntries(parsed.entries, parsed.warnings);

    let output = "";
    if (to === "conf") output = hkbFormatConf(parsed.entries, parsed.warnings);
    else if (to === "table") output = hkbFormatTable(parsed.entries, parsed.warnings);
    else output = hkbFormatLua(parsed.entries, parsed.warnings);

    return {
        output,
        meta: {
            binds: parsed.entries.length,
            warnings: parsed.warnings.length
        }
    };
}
// @slot-end hypr_keybind

function runTool(toolId, input = "", options = {}) {
    switch (toolId) {
    case "uuid":
        return generateUuid(options);
    case "password":
        return generatePassword(options);
    case "lorem":
        return generateLorem(options);
    case "base64":
        return toolBase64(input, options);
    case "url_encode":
        return toolUrlEncode(input, options);
    case "html_entities":
        return toolHtmlEntities(input, options);
    case "jwt_decoder":
        return toolJwtDecode(input, options);
    case "case_converter":
        return toolCaseConvert(input, options);
    case "escape_string":
        return toolEscapeString(input, options);
    case "text_inspector":
        return toolTextInspector(input, options);
    case "line_tools":
        return toolLineTools(input, options);
    case "whitespace_tools":
        return toolWhitespace(input, options);
    case "regex_tester":
        return toolRegexTester(input, options);
    case "slugify":
        return toolSlugify(input, options);
    case "text_diff":
        return toolTextDiff(input, options);
    case "number_base":
        return toolNumberBase(input, options);
    case "unix_timestamp":
        return toolUnixTimestamp(input, options);
    case "color_converter":
        return toolColorConverter(input, options);
    case "json_formatter":
        return toolJsonFormatter(input, options);
    case "id_generator":
        return generateIds(options);
    case "hash_generator":
        return toolHashGenerator(input, options);
    case "hex_text":
        return toolHexText(input, options);
    case "json_csv":
        return toolJsonCsv(input, options);
    case "byte_size":
        return toolByteSize(input, options);
    case "url_parser":
        return toolUrlParser(input, options);
    case "http_status":
        return toolHttpStatus(input, options);
    case "cron_explainer":
        return toolCronExplainer(input, options);
    case "chmod_calculator":
        return toolChmod(input, options);
    case "qr_code":
        return toolQrCode(input, options);
    case "subnet_calculator":
        return toolSubnet(input, options);
    case "unit_converter":
        return toolUnitConverter(input, options);
    case "time_zones":
        return toolTimeZones(input, options);
    case "date_calculator":
        return toolDateCalculator(input, options);
    case "contrast_checker":
        return toolContrastChecker(input, options);
    case "palette_generator":
        return toolPaletteGenerator(input, options);
    case "data_converter":
        return toolDataConverter(input, options);
    case "code_formatter":
        return toolCodeFormatter(input, options);
    // @case-begin curl_converter
    case "curl_converter":
        return curlcConvert(input, options);
    // @case-end curl_converter
    // @case-begin json_query
    case "json_query":
        return jsonqTool(input, options);
    // @case-end json_query
    // @case-begin json_types
    case "json_types":
        return toolJsonTypes(input, options);
    // @case-end json_types
    // @case-begin glob_tester
    case "glob_tester":
        return globtTool(input, options);
    // @case-end glob_tester
    // @case-begin semver_tool
    case "semver_tool":
        return semvTool(input, options);
    // @case-end semver_tool
    // @case-begin commit_lint
    case "commit_lint":
        return ccmtCommitLint(input, options);
    // @case-end commit_lint
    // @case-begin regex_explainer
    case "regex_explainer":
        return rxeToolRegexExplainer(input, options);
    // @case-end regex_explainer
    // @case-begin log_formatter
    case "log_formatter":
        return logfFormat(input, options);
    // @case-end log_formatter
    // @case-begin markdown_table
    case "markdown_table":
        return mdtMarkdownTable(input, options);
    // @case-end markdown_table
    // @case-begin hypr_keybind
    case "hypr_keybind":
        return toolHyprKeybind(input, options);
    // @case-end hypr_keybind
    default:
        return { output: "", error: "Unknown tool: " + toolId };
    }
}

// Node.js module export for testing
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        utf8Encode,
        utf8Decode,
        bytesToBase64,
        base64ToBytes,
        generateUuid,
        generatePassword,
        generateLorem,
        toolBase64,
        toolUrlEncode,
        toolHtmlEntities,
        toolJwtDecode,
        toolCaseConvert,
        toolEscapeString,
        toolTextInspector,
        toolLineTools,
        toolWhitespace,
        toolRegexTester,
        toolSlugify,
        toolTextDiff,
        toolNumberBase,
        toolUnixTimestamp,
        toolColorConverter,
        toolJsonFormatter,
        generateUlid,
        generateIds,
        md5Bytes,
        sha1Bytes,
        sha256Bytes,
        crc32,
        bytesToHex,
        toolHashGenerator,
        toolHexText,
        toolJsonCsv,
        toolByteSize,
        toolUrlParser,
        toolHttpStatus,
        toolCronExplainer,
        toolChmod,
        qrEncodeBytes,
        qrSvg,
        qrSvgResolveColors,
        toolQrCode,
        parseIpv6,
        formatIpv6,
        toolSubnet,
        toolUnitConverter,
        dstActive,
        findTimeZone,
        toolTimeZones,
        toolDateCalculator,
        contrastRatio,
        toolContrastChecker,
        rgbToOklch,
        toolPaletteGenerator,
        materialScheme,
        parseMatugenInput,
        mcuSolve,
        mcuCam16,
        yamlParse,
        yamlEmit,
        tomlParse,
        tomlEmit,
        toolDataConverter,
        toolCodeFormatter,
        // @export-begin curl_converter
        curlcTokenize,
        curlcParseUrl,
        curlcParseCommand,
        curlcParseHttpRequest,
        curlcConvert,
        // @export-end curl_converter
        // @export-begin json_query
        jsonqJpParse,
        jsonqJpEval,
        jsonqJqTokenize,
        jsonqJqParse,
        jsonqJqEval,
        jsonqTool,
        // @export-end json_query
        // @export-begin json_types
        toolJsonTypes,
        jtypesSingularizeWord,
        jtypesToPascalCase,
        jtypesToSnakeCase,
        // @export-end json_types
        // @export-begin glob_tester
        globtCompilePattern,
        globtTool,
        // @export-end glob_tester
        // @export-begin semver_tool
        semvParseVersion,
        semvCompare,
        semvDiff,
        semvInc,
        semvParseRange,
        semvSatisfies,
        semvTool,
        // @export-end semver_tool
        // @export-begin commit_lint
        ccmtCommitLint,
        // @export-end commit_lint
        // @export-begin regex_explainer
        rxeExtractLiteral,
        rxeParsePattern,
        rxeToolRegexExplainer,
        // @export-end regex_explainer
        // @export-begin log_formatter
        logfStripAnsi,
        logfParseTimestamp,
        logfFormat,
        // @export-end log_formatter
        // @export-begin markdown_table
        mdtDisplayWidth,
        mdtMarkdownTable,
        // @export-end markdown_table
        // @export-begin hypr_keybind
        HKB_DISPATCHERS,
        HKB_VALID_LUA_DSP,
        hkbNormalizeKey,
        hkbNormalizeModifiers,
        hkbParseInput,
        toolHyprKeybind,
        // @export-end hypr_keybind
        runTool
    };
}
