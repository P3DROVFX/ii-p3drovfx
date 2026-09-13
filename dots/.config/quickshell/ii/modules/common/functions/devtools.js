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
        runTool
    };
}
