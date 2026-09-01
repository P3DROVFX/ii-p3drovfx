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

    const hex = () => Math.floor(Math.random() * 16).toString(16);
    const createOne = () => {
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
        runTool
    };
}
