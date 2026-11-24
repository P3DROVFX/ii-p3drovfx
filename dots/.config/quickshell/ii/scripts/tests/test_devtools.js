#!/usr/bin/env node

/**
 * Unit tests for modules/common/functions/devtools.js
 */

const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const path = require("path");

const filePath = path.resolve(__dirname, "../../modules/common/functions/devtools.js");
let code = fs.readFileSync(filePath, "utf-8").replace(/^\.pragma library\s*/m, "");

const sandbox = {
    module: { exports: {} },
    exports: {},
    console,
    Date,
    Math,
    String,
    Number,
    BigInt,
    Array,
    Uint8Array,
    Int32Array,
    Set,
    JSON,
    RegExp,
    parseInt,
    parseFloat,
    isNaN,
    isFinite,
    encodeURI,
    decodeURI,
    encodeURIComponent,
    decodeURIComponent,
    TextEncoder: typeof TextEncoder !== "undefined" ? TextEncoder : undefined,
    TextDecoder: typeof TextDecoder !== "undefined" ? TextDecoder : undefined
};
vm.createContext(sandbox);
vm.runInContext(code, sandbox);
const devtools = sandbox.module.exports;

console.log("Running devtools.js unit tests...\n");

// 1. UUID Generator
{
    const single = devtools.generateUuid();
    assert.match(single.output, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
    
    const upper = devtools.generateUuid({ uppercase: true });
    assert.match(upper.output, /^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/);

    const noHyphens = devtools.generateUuid({ hyphens: false });
    assert.equal(noHyphens.output.length, 32);
    assert.equal(noHyphens.output.includes("-"), false);

    const multi = devtools.generateUuid({ quantity: 3 });
    const lines = multi.output.split("\n");
    assert.equal(lines.length, 3);
    assert.equal(new Set(lines).size, 3);
    console.log("✓ UUID generator tests passed");
}

// 2. Password Generator
{
    const pass = devtools.generatePassword({ length: 16 });
    assert.equal(pass.output.length, 16);

    const numericOnly = devtools.generatePassword({ length: 10, uppercase: false, lowercase: false, numbers: true, symbols: false });
    assert.match(numericOnly.output, /^\d{10}$/);

    const multi = devtools.generatePassword({ length: 12, quantity: 5 });
    assert.equal(multi.output.split("\n").length, 5);
    console.log("✓ Password generator tests passed");
}

// 3. Lorem Ipsum Generator
{
    const paras = devtools.generateLorem({ unit: "paragraphs", count: 2, startWithLorem: true });
    const pList = paras.output.split("\n\n");
    assert.equal(pList.length, 2);
    assert.ok(pList[0].startsWith("Lorem ipsum dolor sit amet"));

    const sents = devtools.generateLorem({ unit: "sentences", count: 3, startWithLorem: true });
    assert.equal(sents.meta.sentences, 3);

    const words = devtools.generateLorem({ unit: "words", count: 10 });
    assert.equal(words.output.split(" ").length, 10);
    console.log("✓ Lorem Ipsum generator tests passed");
}

// 4. Base64 (with UTF-8 and URL-safe)
{
    // Basic ASCII
    const encAscii = devtools.toolBase64("Hello World!", { mode: "encode" });
    assert.equal(encAscii.output, "SGVsbG8gV29ybGQh");
    const decAscii = devtools.toolBase64("SGVsbG8gV29ybGQh", { mode: "decode" });
    assert.equal(decAscii.output, "Hello World!");

    // UTF-8 with accents and emojis
    const utf8Str = "Olá mundo! Acentuação e emojis: 🚀✨🇧🇷";
    const encUtf8 = devtools.toolBase64(utf8Str, { mode: "encode" });
    const decUtf8 = devtools.toolBase64(encUtf8.output, { mode: "decode" });
    assert.equal(decUtf8.output, utf8Str);

    // URL-safe mode
    const urlSafeSample = "Subjects?+/>><<";
    const encUrlSafe = devtools.toolBase64(urlSafeSample, { mode: "encode", urlSafe: true });
    assert.equal(encUrlSafe.output.includes("+"), false);
    assert.equal(encUrlSafe.output.includes("/"), false);
    const decUrlSafe = devtools.toolBase64(encUrlSafe.output, { mode: "decode", urlSafe: true });
    assert.equal(decUrlSafe.output, urlSafeSample);

    // Invalid base64 decode
    const invalid = devtools.toolBase64("Invalid!!!Base64###", { mode: "decode" });
    assert.ok(invalid.error);
    console.log("✓ Base64 encoder/decoder (UTF-8 & URL-safe) tests passed");
}

// 5. URL Encode / Decode
{
    const url = "https://example.com/search?q=olá mundo&category=all#top";
    const enc = devtools.toolUrlEncode(url, { mode: "encode", component: true });
    assert.ok(enc.output.includes("%20") || enc.output.includes("%C3%A1"));
    const dec = devtools.toolUrlEncode(enc.output, { mode: "decode", component: true });
    assert.equal(dec.output, url);
    console.log("✓ URL encode/decode tests passed");
}

// 6. HTML Entities
{
    const rawHtml = `<script>alert("Hello & welcome 'friend'");</script>`;
    const enc = devtools.toolHtmlEntities(rawHtml, { mode: "encode" });
    assert.ok(enc.output.includes("&lt;script&gt;"));
    assert.ok(enc.output.includes("&amp;"));
    assert.ok(enc.output.includes("&quot;"));
    assert.ok(enc.output.includes("&#39;"));

    const dec = devtools.toolHtmlEntities(enc.output, { mode: "decode" });
    assert.equal(dec.output, rawHtml);

    const namedEntities = devtools.toolHtmlEntities("&copy; 2026 &euro; 100 &mdash; &ndash; &amp;", { mode: "decode" });
    assert.equal(namedEntities.output, "© 2026 € 100 — – &");
    console.log("✓ HTML entities tests passed");
}

// 7. JWT Decoder
{
    // Standard test JWT (header: {"alg":"HS256","typ":"JWT"}, payload: {"sub":"1234567890","name":"Pedro","admin":true,"iat":1516239022})
    const testJwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IlBlZHJvIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c";
    const decoded = devtools.toolJwtDecode(testJwt);
    assert.ok(!decoded.error);
    assert.equal(decoded.meta.header.alg, "HS256");
    assert.equal(decoded.meta.payload.name, "Pedro");
    assert.equal(decoded.meta.payload.admin, true);
    assert.ok(decoded.output.includes("⚠️ Note: Signature is not verified"));
    assert.ok(decoded.output.includes("Pedro"));

    const invalidJwt = devtools.toolJwtDecode("invalid.jwt");
    assert.ok(invalidJwt.error);
    console.log("✓ JWT decoder tests passed");
}

// 8. Case Converter
{
    const input = "helloWorld_foo-bar test123XML";
    assert.equal(devtools.toolCaseConvert(input, { target: "camel" }).output, "helloWorldFooBarTest123Xml");
    assert.equal(devtools.toolCaseConvert(input, { target: "pascal" }).output, "HelloWorldFooBarTest123Xml");
    assert.equal(devtools.toolCaseConvert(input, { target: "snake" }).output, "hello_world_foo_bar_test123_xml");
    assert.equal(devtools.toolCaseConvert(input, { target: "kebab" }).output, "hello-world-foo-bar-test123-xml");
    assert.equal(devtools.toolCaseConvert(input, { target: "constant" }).output, "HELLO_WORLD_FOO_BAR_TEST123_XML");
    assert.equal(devtools.toolCaseConvert(input, { target: "title" }).output, "Hello World Foo Bar Test123 Xml");
    assert.equal(devtools.toolCaseConvert(input, { target: "dot" }).output, "hello.world.foo.bar.test123.xml");
    console.log("✓ Case converter tests passed");
}

// 9. Escape String
{
    const jsonStr = `Line 1\nLine 2\t"quoted"`;
    const escJson = devtools.toolEscapeString(jsonStr, { mode: "json" });
    assert.equal(escJson.output, `Line 1\\nLine 2\\t\\"quoted\\"`);

    const regexStr = "foo.bar*[123]?(test)";
    const escRegex = devtools.toolEscapeString(regexStr, { mode: "regex" });
    assert.equal(escRegex.output, "foo\\.bar\\*\\[123\\]\\?\\(test\\)");

    const shellStr = `Pedro's Mac "Pro" $PATH`;
    const escShell = devtools.toolEscapeString(shellStr, { mode: "shell_single" });
    assert.equal(escShell.output, `Pedro'\\''s Mac "Pro" $PATH`);
    console.log("✓ Escape string tests passed");
}

// 10. Text Inspector
{
    const sample = "Olá mundo!\nEste é um teste de estatísticas.\n\nMais um parágrafo.";
    const stats = devtools.toolTextInspector(sample);
    assert.ok(stats.meta.words > 5);
    assert.equal(stats.meta.paragraphs, 2);
    assert.ok(stats.meta.bytesUtf8 > sample.length); // Due to multi-byte UTF-8 chars (á, é, í)
    console.log("✓ Text inspector tests passed");
}

// 11. Line Tools
{
    const lines = "banana\nApple\ncherry\nApple\n";
    const sortAz = devtools.toolLineTools(lines, { operation: "sort_az" });
    assert.ok(sortAz.output.toLowerCase().startsWith("apple"));

    const dedupe = devtools.toolLineTools(lines, { operation: "dedupe" });
    assert.equal(dedupe.output.split("\n").filter(l => l.toLowerCase() === "apple").length, 1);

    const numbered = devtools.toolLineTools("a\nb\nc", { operation: "number" });
    assert.ok(numbered.output.includes("1. a"));
    assert.ok(numbered.output.includes("2. b"));
    assert.ok(numbered.output.includes("3. c"));
    console.log("✓ Line tools tests passed");
}

// 12. Whitespace Tools
{
    const spaces = "   hello   world   \n   foo   bar   ";
    assert.equal(devtools.toolWhitespace(spaces, { operation: "trim" }).output, "hello   world\nfoo   bar");
    assert.equal(devtools.toolWhitespace(spaces, { operation: "collapse" }).output, " hello world \n foo bar ");
    console.log("✓ Whitespace tools tests passed");
}

// 13. Regex Tester
{
    const text = "Contact support@example.com or sales@test.org for info";
    const res = devtools.toolRegexTester(text, { pattern: "([a-z]+)@([a-z.]+)", flags: "g" });
    assert.equal(res.meta.count, 2);
    assert.equal(res.meta.matches[0].value, "support@example.com");
    assert.equal(res.meta.matches[0].groups[0], "support");
    assert.equal(res.meta.matches[0].groups[1], "example.com");

    const errRes = devtools.toolRegexTester(text, { pattern: "[invalid(", flags: "g" });
    assert.ok(errRes.error);
    console.log("✓ Regex tester tests passed");
}

// 14. Slugify
{
    const title = "  Olá! Como Você Está Hoje em 2026?  ";
    assert.equal(devtools.toolSlugify(title).output, "ola-como-voce-esta-hoje-em-2026");
    assert.equal(devtools.toolSlugify(title, { separator: "_" }).output, "ola_como_voce_esta_hoje_em_2026");
    console.log("✓ Slugify tests passed");
}

// 15. Text Diff
{
    const orig = "alpha\nbravo\ncharlie\ndelta";
    const mod = "alpha\nbravo\nCHARLIE\ndelta\necho";
    const diff = devtools.toolTextDiff("", { original: orig, modified: mod });
    assert.ok(diff.output.includes("- charlie"));
    assert.ok(diff.output.includes("+ CHARLIE"));
    assert.ok(diff.output.includes("+ echo"));
    assert.equal(diff.meta.additions, 2);
    assert.equal(diff.meta.deletions, 1);
    console.log("✓ Text diff tests passed");
}

// 16. Number Base Converter
{
    const dec = devtools.toolNumberBase("255");
    assert.equal(dec.meta.decimal, "255");
    assert.equal(dec.meta.hex, "0xFF");
    assert.equal(dec.meta.binary, "0b11111111");
    assert.equal(dec.meta.octal, "0o377");

    const hex = devtools.toolNumberBase("0x1A");
    assert.equal(hex.meta.decimal, "26");

    const bin = devtools.toolNumberBase("0b1010");
    assert.equal(bin.meta.decimal, "10");
    console.log("✓ Number base converter tests passed");
}

// Hashes, against published test vectors
{
    const vectors = [
        ["", "d41d8cd98f00b204e9800998ecf8427e", "da39a3ee5e6b4b0d3255bfef95601890afd80709",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "00000000"],
        ["abc", "900150983cd24fb0d6963f7d28e17f72", "a9993e364706816aba3e25717850c26c9cd0d89d",
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "352441c2"],
        ["The quick brown fox jumps over the lazy dog", "9e107d9d372bb6826bd81d3542a419d6",
            "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592", "414fa339"],
        // 56 bytes: the length field no longer fits in the first block.
        ["abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "8215ef0796a20bcaaae116d3876c664a",
            "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", null]
    ];
    for (const [text, md5, sha1, sha256, crc] of vectors) {
        assert.equal(devtools.toolHashGenerator(text, { algorithm: "md5" }).output, md5);
        assert.equal(devtools.toolHashGenerator(text, { algorithm: "sha1" }).output, sha1);
        assert.equal(devtools.toolHashGenerator(text, { algorithm: "sha256" }).output, sha256);
        if (crc)
            assert.equal(devtools.toolHashGenerator(text, { algorithm: "crc32" }).output, crc);
    }
    const all = devtools.toolHashGenerator("abc", { algorithm: "all", uppercase: true });
    assert.equal(all.meta.sha256, "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD");
    assert.equal(devtools.runTool("hash_generator", "abc", { algorithm: "md5" }).output, "900150983cd24fb0d6963f7d28e17f72");
    console.log("✓ Hash generator tests passed");
}

// NanoID, ULID and UUID v7
{
    assert.match(devtools.generateIds({ kind: "nanoid", size: 21 }).output, /^[A-Za-z0-9_-]{21}$/);
    assert.match(devtools.generateIds({ kind: "ulid" }).output, /^[0-9A-HJKMNP-TV-Z]{26}$/);
    // The ULID specification's own example timestamp.
    assert.equal(devtools.generateUlid(1469918176385).slice(0, 10), "01ARYZ6S41");
    const many = devtools.generateIds({ kind: "nanoid", quantity: 5 }).output.split("\n");
    assert.equal(new Set(many).size, 5);
    const v7 = devtools.generateUuid({ version: "7" }).output;
    assert.match(v7, /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    assert.ok(Math.abs(parseInt(v7.replace(/-/g, "").slice(0, 12), 16) - Date.now()) < 5000);
    console.log("✓ NanoID, ULID and UUID v7 tests passed");
}

// Text <-> hex
{
    assert.equal(devtools.toolHexText("Hi!", { mode: "encode" }).output, "48 69 21");
    assert.equal(devtools.toolHexText("Hi!", { mode: "encode", separator: "colon" }).output, "48:69:21");
    assert.equal(devtools.toolHexText("48 69 21", { mode: "decode" }).output, "Hi!");
    assert.equal(devtools.toolHexText("0xc3 0xa9", { mode: "decode" }).output, "é");
    assert.ok(devtools.toolHexText("4", { mode: "decode" }).error);
    console.log("✓ Text/hex tests passed");
}

// JSON <-> CSV
{
    const csv = devtools.toolJsonCsv('[{"name":"Ada","note":"likes, commas"},{"name":"Linus","stars":99}]', { mode: "json_to_csv" });
    assert.equal(csv.output, 'name,note,stars\nAda,"likes, commas",\nLinus,,99');
    const json = devtools.toolJsonCsv('name,stars,active\n"Ada ""Countess""",42,true', { mode: "csv_to_json" });
    assert.deepEqual(JSON.parse(json.output), [{ name: 'Ada "Countess"', stars: 42, active: true }]);
    assert.ok(devtools.toolJsonCsv('{"a":1', { mode: "json_to_csv" }).error);
    assert.ok(devtools.toolJsonCsv('a,b\n"open', { mode: "csv_to_json" }).error);
    console.log("✓ JSON/CSV tests passed");
}

// Data sizes
{
    const size = devtools.toolByteSize("1.5 GiB");
    assert.equal(size.meta.bytes, 1610612736);
    assert.ok(size.output.includes("GB   1.610613"));
    assert.equal(devtools.toolByteSize("500MB").meta.bytes, 5e8);
    assert.equal(devtools.toolByteSize("4G").meta.bytes, 4 * 1024 * 1024 * 1024);
    assert.ok(devtools.toolByteSize("12 parsecs").error);
    console.log("✓ Data size tests passed");
}

// URL parser
{
    const url = devtools.toolUrlParser("https://dev@example.com:8080/api/v1/search?q=quick+shell&page=2#results");
    assert.equal(url.meta.host, "example.com");
    assert.equal(url.meta.params, 2);
    assert.ok(url.output.includes("Port       8080"));
    assert.ok(url.output.includes("q     quick shell"));
    assert.ok(url.output.includes("Fragment   results"));
    assert.ok(devtools.toolUrlParser("https://example.com").output.includes("443 (default)"));
    assert.ok(devtools.toolUrlParser("not a url").error);
    console.log("✓ URL parser tests passed");
}

// HTTP status codes
{
    assert.ok(devtools.toolHttpStatus("404").output.startsWith("404  Not Found"));
    const serverErrors = devtools.toolHttpStatus("5xx").output.split("\n").filter(line => /^\d{3}/.test(line));
    assert.ok(serverErrors.length > 0 && serverErrors.every(line => line.startsWith("5")));
    assert.equal(devtools.toolHttpStatus("teapot").meta.count, 1);
    assert.equal(devtools.toolHttpStatus("299").meta.count, 0);
    console.log("✓ HTTP status tests passed");
}

// Cron explainer
{
    const monday = new Date(2026, 8, 14, 8, 50).getTime();
    const cron = devtools.toolCronExplainer("*/15 9-17 * * 1-5", { count: 3, now: monday });
    assert.ok(cron.output.includes("2026-09-14 09:00  Mon"));
    assert.ok(cron.output.includes("2026-09-14 09:30  Mon"));
    assert.equal(cron.meta.runs, 3);
    assert.ok(cron.output.includes("every 15 minutes"));
    assert.ok(devtools.toolCronExplainer("@weekly", { count: 1, now: monday }).output.includes("2026-09-20 00:00  Sun"));
    // Both day fields restricted: either may match (the 1st, or any Friday).
    const either = devtools.toolCronExplainer("0 12 1 * 5", { count: 2, now: monday });
    assert.ok(either.output.includes("2026-09-18 12:00  Fri"));
    assert.ok(devtools.toolCronExplainer("61 * * * *").error);
    assert.ok(devtools.toolCronExplainer("* * *").error);
    console.log("✓ Cron explainer tests passed");
}

// chmod calculator
{
    assert.equal(devtools.toolChmod("4755").meta.symbolic, "rwsr-xr-x");
    assert.equal(devtools.toolChmod("-rw-r--r--").meta.octal, "644");
    assert.equal(devtools.toolChmod("rwxrwxrwt").meta.octal, "1777");
    assert.ok(devtools.toolChmod("999").error);
    console.log("✓ chmod calculator tests passed");
}

// 17. Unix Timestamp
{
    const fixed = devtools.toolUnixTimestamp("1700000000");
    assert.equal(fixed.meta.unixSeconds, 1700000000);
    assert.equal(fixed.meta.iso, "2023-11-14T22:13:20.000Z");

    const now = devtools.toolUnixTimestamp("now");
    assert.ok(now.meta.unixSeconds > 1700000000);
    console.log("✓ Unix timestamp tests passed");
}

// 18. Color Converter
{
    const hex = devtools.toolColorConverter("#FF5733");
    assert.equal(hex.meta.hex, "#FF5733");
    assert.equal(hex.meta.rgb, "rgb(255, 87, 51)");
    assert.equal(hex.meta.hsl, "hsl(11, 100%, 60%)");

    const rgb = devtools.toolColorConverter("rgb(0, 128, 255)");
    assert.equal(rgb.meta.hex, "#0080FF");

    const hsl = devtools.toolColorConverter("hsl(120, 100%, 50%)");
    assert.equal(hsl.meta.hex, "#00FF00");
    console.log("✓ Color converter tests passed");
}

// 19. JSON Formatter & Validator
{
    const raw = '{"b":2,"a":1,"list":[3,2,1]}';
    const formatted = devtools.toolJsonFormatter(raw, { indent: "2" });
    assert.ok(formatted.output.includes('  "b": 2'));

    const minified = devtools.toolJsonFormatter('{\n  "a": 1,\n  "b": 2\n}', { indent: "minified" });
    assert.equal(minified.output, '{"a":1,"b":2}');

    const sorted = devtools.toolJsonFormatter(raw, { indent: "2", sortKeys: true });
    assert.ok(sorted.output.indexOf('"a": 1') < sorted.output.indexOf('"b": 2'));

    const invalid = devtools.toolJsonFormatter('{"a": 1, invalid}', { indent: "2" });
    assert.ok(invalid.error);
    assert.ok(invalid.error.includes("Line"));
    console.log("✓ JSON formatter/validator tests passed");
}

// 21. QR codes
{
    const crypto = require("crypto");
    const rowsHash = result => crypto.createHash("sha256").update(result.meta.visual.rows.join(",")).digest("hex");
    // Pinned matrices were decoded back to their payloads with OpenCV.
    const link = devtools.toolQrCode("https://example.com", { ecc: "M" });
    assert.equal(link.meta.version, 2);
    assert.equal(rowsHash(link), "41531892141287a890c639bff5f021361980a7889814e3dabe64f0cd79395c9a");
    const wifi = devtools.toolQrCode("ssid: Home\npassword: correct horse battery staple");
    assert.equal(wifi.meta.payload, "WIFI:T:WPA;S:Home;P:correct horse battery staple;;");
    assert.equal(rowsHash(wifi), "ccee57e9c4d79b54cce08c9312d6512953a1de32271177d4c59179b05d5090fa");

    // Byte-mode capacity of version 1 per level, and the version-40 limit.
    for (const [ecc, capacity] of [["L", 17], ["M", 14], ["Q", 11], ["H", 7]]) {
        assert.equal(devtools.qrEncodeBytes(new Array(capacity).fill(65), ecc).version, 1, ecc);
        assert.equal(devtools.qrEncodeBytes(new Array(capacity + 1).fill(65), ecc).version, 2, ecc);
    }
    assert.equal(devtools.qrEncodeBytes(new Array(2953).fill(65), "L").version, 40);
    assert.equal(devtools.qrEncodeBytes(new Array(2954).fill(65), "L"), null);

    assert.equal(devtools.toolQrCode("ssid: a;b\npassword: p:w").meta.payload, "WIFI:T:WPA;S:a\\;b;P:p\\:w;;");
    assert.ok(devtools.toolQrCode("name: Ana Souza\nphone: +55 11 9999").meta.payload.includes("N:Souza;Ana;;;"));
    assert.ok(devtools.toolQrCode("hello", { kind: "wifi" }).error);
    console.log("✓ QR code tests passed");
}

// 22. Subnets
{
    const v4 = devtools.toolSubnet("192.168.1.130/26\n192.168.1.150\n192.168.1.200");
    assert.equal(v4.meta.network, "192.168.1.128");
    assert.equal(v4.meta.usable, 62);
    assert.ok(v4.output.includes("Broadcast   192.168.1.191"));
    assert.ok(v4.output.includes("✓  192.168.1.150"));
    assert.ok(v4.output.includes("✗  192.168.1.200"));
    assert.equal(devtools.toolSubnet("10.0.0.1 255.255.240.0").meta.prefix, 20);
    assert.equal(devtools.toolSubnet("10.0.0.7/31").meta.usable, 2);
    assert.equal(devtools.toolSubnet("8.8.8.8").meta.usable, 1);
    assert.ok(devtools.toolSubnet("10.0.0.1 255.0.255.0").error);

    assert.equal(devtools.formatIpv6(devtools.parseIpv6("2001:0db8:0000:0000:0001:0000:0000:0001")), "2001:db8::1:0:0:1");
    assert.equal(devtools.formatIpv6(devtools.parseIpv6("::ffff:192.0.2.1")), "::ffff:192.0.2.1");
    assert.equal(devtools.parseIpv6("1::2::3"), null);
    const v6 = devtools.toolSubnet("2001:db8:abcd:12::1/48\n2001:db8:abcd:ffff::9\n2001:db8:abce::1");
    assert.equal(v6.meta.network, "2001:db8:abcd::");
    assert.ok(v6.output.includes("2^80 = 1,208,925,819,614,629,174,706,176"));
    assert.ok(v6.output.includes("✓  2001:db8:abcd:ffff::9"));
    assert.ok(v6.output.includes("✗  2001:db8:abce::1"));
    console.log("✓ Subnet calculator tests passed");
}

// 23. Units
{
    assert.ok(devtools.toolUnitConverter("100 km/h to mph").output.startsWith("100 km/h = 62.13711922 mph"));
    assert.ok(devtools.toolUnitConverter("72°F").output.includes("°C  22.22222222"));
    assert.ok(devtools.toolUnitConverter("0 K to °F").output.startsWith("0 K = -459.67 °F"));
    assert.ok(devtools.toolUnitConverter("-300 °C").error);
    assert.ok(devtools.toolUnitConverter("1,5 kg to g").output.startsWith("1.5 kg = 1,500 g"));
    assert.ok(devtools.toolUnitConverter("24px to rem", { dpi: 96, rootSize: 16 }).output.startsWith("24 px = 1.5 rem"));
    assert.ok(devtools.toolUnitConverter("12 pt to mm").output.startsWith("12 pt = 4.233333333 mm"));
    assert.ok(devtools.toolUnitConverter("1 alqueire to ha").output.startsWith("1 alqueire SP = 2.42 ha"));
    assert.ok(devtools.toolUnitConverter("3 kg to m").error);
    assert.ok(devtools.toolUnitConverter("3 parsecs").error);
    console.log("✓ Unit converter tests passed");
}

// 24. Time zones (rules checked against the tz database's 2026 transitions)
{
    const berlin = devtools.findTimeZone("Berlin");
    assert.equal(berlin.offsetAt(Date.UTC(2026, 2, 29, 0, 59)), 60);
    assert.equal(berlin.offsetAt(Date.UTC(2026, 2, 29, 1, 0)), 120);
    assert.equal(berlin.offsetAt(Date.UTC(2026, 9, 25, 1, 0)), 60);
    const ny = devtools.findTimeZone("New York");
    assert.equal(ny.offsetAt(Date.UTC(2026, 2, 8, 6, 59)), -300);
    assert.equal(ny.offsetAt(Date.UTC(2026, 2, 8, 7, 0)), -240);
    assert.equal(ny.offsetAt(Date.UTC(2026, 10, 1, 6, 0)), -300);
    const sydney = devtools.findTimeZone("Australia/Sydney");
    assert.equal(sydney.offsetAt(Date.UTC(2026, 0, 15)), 660);
    assert.equal(sydney.offsetAt(Date.UTC(2026, 6, 15)), 600);
    assert.equal(sydney.offsetAt(Date.UTC(2026, 3, 4, 15, 59)), 660);
    assert.equal(sydney.offsetAt(Date.UTC(2026, 3, 4, 16, 0)), 600);
    assert.equal(devtools.findTimeZone("Auckland").offsetAt(Date.UTC(2026, 8, 26, 14, 0)), 780);
    assert.equal(devtools.findTimeZone("São Paulo").offsetAt(Date.UTC(2026, 0, 1)), -180);
    assert.equal(devtools.findTimeZone("utc+5:30").offsetAt(0), 330);
    assert.equal(devtools.findTimeZone("Atlantis"), null);

    const meeting = devtools.toolTimeZones("2026-07-01 09:30 Sydney", { zones: "London, America/Los_Angeles", grid: true });
    assert.ok(meeting.output.includes("London       Wed 01 Jul  00:30  UTC+1     DST"));
    assert.ok(meeting.output.includes("Los Angeles  Tue 30 Jun  16:30  UTC−7     DST  -1 day"));
    assert.ok(meeting.output.includes("No hour is inside 09:00-18:00 in every zone."));
    assert.ok(devtools.toolTimeZones("14:00 Atlantis").error);
    console.log("✓ Time zone tests passed");
}

// 25. Dates
{
    const span = devtools.toolDateCalculator("2026-01-01 to 2026-12-25");
    assert.equal(span.meta.days, 358);
    assert.ok(span.output.includes("Calendar       0 years, 11 months, 24 days"));
    assert.ok(span.output.includes("Business days  256"));
    assert.equal(devtools.toolDateCalculator("31/01/2026 + 1m").meta.result, "2026-02-28");
    assert.equal(devtools.toolDateCalculator("01/31/2026 + 1m", { dateOrder: "mdy" }).meta.result, "2026-02-28");
    assert.equal(devtools.toolDateCalculator("2026-11-20 + 1bd").meta.result, "2026-11-23");
    assert.equal(devtools.toolDateCalculator("2026-03-01 - 2w 3d").meta.result, "2026-02-12");
    assert.equal(devtools.toolDateCalculator("2024-02-29 + 1y").meta.result, "2025-02-28");
    assert.equal(devtools.toolDateCalculator("2021-01-03").meta.week, "W53");
    assert.equal(devtools.toolDateCalculator("2026-12-31").meta.week, "W53");
    assert.ok(devtools.toolDateCalculator("2026-02-30").error);
    console.log("✓ Date calculator tests passed");
}

// 26. Contrast and palettes
{
    assert.equal(devtools.toolContrastChecker("black on white").meta.ratio, "21.00:1");
    const grey = devtools.toolContrastChecker("#777777 on #FFFFFF");
    assert.equal(grey.meta.ratio, "4.47:1");
    assert.ok(grey.output.includes("AA   normal text (4.5:1)   ✗ fail"));
    assert.ok(grey.output.includes("AA   #767676"));
    // Translucent text is composited on the background first.
    assert.ok(devtools.toolContrastChecker("rgba(255, 255, 255, 0.6)\n#1E1E2E").output.includes("Text        #A5A5AB"));
    assert.ok(devtools.toolContrastChecker("#fff").error);

    const tonal = devtools.toolPaletteGenerator("#6750A4");
    assert.equal(tonal.meta.visual.items.length, 13);
    assert.equal(tonal.meta.visual.items[0].color, "#000000");
    assert.equal(tonal.meta.visual.items[12].color, "#FFFFFF");
    const hue = devtools.rgbToOklch({ r: 0x67, g: 0x50, b: 0xa4 }).h;
    for (const item of tonal.meta.visual.items.slice(2, 10))
        assert.ok(Math.abs(devtools.rgbToOklch({ r: parseInt(item.color.slice(1, 3), 16), g: parseInt(item.color.slice(3, 5), 16), b: parseInt(item.color.slice(5, 7), 16) }).h - hue) < 2, item.color);
    const css = devtools.toolPaletteGenerator("#6750A4", { scheme: "triadic", format: "css" });
    assert.ok(css.output.startsWith(":root {\n  --color-base: #6750a4;"));
    assert.equal(css.meta.visual.items.length, 3);
    console.log("✓ Contrast and palette tests passed");
}

// 26b. Material You schemes match matugen colour for colour
{
    const fixture = JSON.parse(fs.readFileSync(path.resolve(__dirname, "fixtures/matugen_schemes.json"), "utf-8"));
    let compared = 0;
    for (const [key, packed] of Object.entries(fixture.schemes)) {
        const [type, seed] = key.split("|");
        const rgb = [1, 3, 5].map(i => parseInt(seed.substr(i, 2), 16));
        const mine = {};
        for (const role of devtools.materialScheme(rgb, type).roles)
            mine[role.name] = role.dark.slice(1) + role.light.slice(1);
        packed.split(" ").forEach((pair, i) => {
            assert.equal(mine[fixture.roles[i]], pair, `${key} ${fixture.roles[i]} (dark+light)`);
            compared++;
        });
    }
    assert.equal(compared, 24 * 50);

    const hct = devtools.mcuCam16(0x67, 0x50, 0xa4);
    assert.ok(Math.abs(hct.hue - 298.981) < 0.001 && Math.abs(hct.chroma - 47.857) < 0.001);

    const parsed = devtools.parseMatugenInput("matugen color hex \"#ff0000\" -t scheme-vibrant -m light");
    assert.equal(parsed.color, "#ff0000");
    assert.equal(parsed.type, "vibrant");
    assert.equal(parsed.mode, "light");
    const fromCommand = devtools.toolPaletteGenerator("matugen color hex \"#ff0000\" -t scheme-vibrant -m light", { format: "css" });
    assert.ok(fromCommand.output.includes("  --primary: #c00100;"));
    assert.equal(fromCommand.meta.visual.items.length, 50);
    const qml = devtools.toolPaletteGenerator("#6750A4", { scheme: "matugen", format: "qml", mode: "dark" });
    assert.ok(qml.output.includes("property color m3onPrimaryContainer: \"#e9ddff\""));
    const json = JSON.parse(devtools.toolPaletteGenerator("#6750A4", { scheme: "matugen", format: "json", mode: "light" }).output);
    assert.equal(json.colors.primary.default.color, "#65558f");
    assert.equal(json.colors.primary.dark.color, "#cfbdfe");
    assert.ok(devtools.toolPaletteGenerator("matugen color hex \"#123456\" -t scheme-content", {}).error.includes("content"));
    console.log("✓ Material You (matugen) tests passed");
}

// 27. JSON / YAML / TOML
{
    // Objects built inside the vm context have its own prototypes.
    const plain = value => JSON.parse(JSON.stringify(value));
    const yaml = [
        "server:",
        "  host: example.com  # main",
        "  ports: [80, 443]",
        "users:",
        "  - name: ana",
        "    roles:",
        "      - admin",
        "  - name: bo",
        "    note: |",
        "      line one",
        "      line two",
        "quoted: \"a: b\"",
        "base: &b",
        "  x: 1",
        "derived:",
        "  <<: *b",
        "  y: 2"
    ].join("\n");
    assert.deepStrictEqual(JSON.parse(devtools.toolDataConverter(yaml, { to: "json" }).output), {
        server: { host: "example.com", ports: [80, 443] },
        users: [{ name: "ana", roles: ["admin"] }, { name: "bo", note: "line one\nline two\n" }],
        quoted: "a: b",
        base: { x: 1 },
        derived: { x: 1, y: 2 }
    });

    const toml = "title = \"T\"\n[owner]\nname = \"Tom\" # c\ndob = 1979-05-27T07:32:00-08:00\n[[products]]\nsku = 738_594_937\n[[products]]\ncolor = 'gray'\nflags = [ true,\n false, ]\n[a.b]\nd = 0xff\ninline = { x = 1, y.z = 2 }";
    assert.deepStrictEqual(plain(devtools.tomlParse(toml)), {
        title: "T",
        owner: { name: "Tom", dob: "1979-05-27T07:32:00-08:00" },
        products: [{ sku: 738594937 }, { color: "gray", flags: [true, false] }],
        a: { b: { d: 255, inline: { x: 1, y: { z: 2 } } } }
    });
    assert.ok(devtools.toolDataConverter("a = 1\na = 2", { from: "toml" }).error.includes("Duplicate key"));

    // Round trips: JSON → YAML → JSON and JSON → TOML → JSON.
    const value = { name: "x", n: 3, f: 1.5, t: true, s: "yes", num: "123", multi: "a\nb\n", list: [1, { k: [] }, [2, 3]], empty: {}, nested: { deep: { v: "a: b # c" } } };
    assert.deepStrictEqual(plain(devtools.yamlParse(devtools.yamlEmit(value, 2))), value);
    const tomlValue = { name: "x", servers: [{ ip: "10.0.0.1" }, { ip: "10.0.0.2" }], owner: { tags: ["a", "b"], "weird key": 1 } };
    assert.deepStrictEqual(plain(devtools.tomlParse(devtools.tomlEmit(tomlValue, []))), tomlValue);
    const dropped = devtools.toolDataConverter("{\"a\": null, \"b\": 1}", { to: "toml" });
    assert.equal(dropped.meta.dropped, 1);
    assert.ok(devtools.toolDataConverter("[1, 2]", { to: "toml" }).error);
    console.log("✓ JSON/YAML/TOML tests passed");
}

// 28. Code formatters
{
    const xml = devtools.toolCodeFormatter("<?xml version=\"1.0\"?><root><item id=\"1\">One</item><item><empty/></item></root>");
    assert.equal(xml.meta.language, "XML");
    assert.equal(xml.output, "<?xml version=\"1.0\"?>\n<root>\n  <item id=\"1\">One</item>\n  <item>\n    <empty/>\n  </item>\n</root>");
    const html = devtools.toolCodeFormatter("<div><br><img src=\"a>b.png\"><pre> keep  </pre></div>", { language: "html" });
    assert.equal(html.output, "<div>\n  <br>\n  <img src=\"a>b.png\">\n  <pre> keep  </pre>\n</div>");

    const css = devtools.toolCodeFormatter("a:hover,b{color:red;background:url(\"x;y.png\")!important}", { language: "css" });
    assert.equal(css.output, "a:hover, b {\n  color: red;\n  background: url(\"x;y.png\") !important;\n}");
    assert.equal(devtools.toolCodeFormatter(".a , .b > c {\n  color : red ;\n  margin: 0 auto;\n}\n/* x */", { language: "css", mode: "minify" }).output, ".a,.b>c{color:red;margin:0 auto}");

    const sql = devtools.toolCodeFormatter("select a, count(*) as n from t where x = 'it''s' and y in (select id from u where z > 1) group by a;", { language: "sql" });
    assert.equal(sql.output, [
        "SELECT",
        "  a,",
        "  COUNT(*) AS n",
        "FROM t",
        "WHERE x = 'it''s'",
        "  AND y IN (",
        "    SELECT",
        "      id",
        "    FROM u",
        "    WHERE z > 1",
        "  )",
        "GROUP BY",
        "  a;"
    ].join("\n"));
    assert.equal(devtools.toolCodeFormatter("SELECT  a ,  b FROM t -- c\n WHERE x = 'a  b'", { language: "sql", mode: "minify" }).output, "SELECT a,b FROM t WHERE x='a  b'");
    console.log("✓ Code formatter tests passed");
}

// Developer tools: one slot per tool.
// @test-begin curl_converter
{
    const plain = value => JSON.parse(JSON.stringify(value));

    // Empty/whitespace input
    assert.deepStrictEqual(plain(devtools.runTool("curl_converter", "   \n\t  ")), { output: "" });

    // Tokenizer: quotes, $'...', backslash and Windows ^ continuations
    const tok1 = plain(devtools.curlcTokenize("curl -XPOST 'it'\\''s' \"a\\\"b\" $'c\\nd\\x21' \\\n  --url=https://example.com"));
    assert.deepStrictEqual(tok1.tokens, ["curl", "-XPOST", "it's", "a\"b", "c\nd!", "--url=https://example.com"]);

    const tokWin = plain(devtools.curlcTokenize("curl ^\"https://example.com^\" ^\n  -H ^\"Accept: */*^\" ^\n  --data-raw ^\"^{^\\^\"a^\\^\":1^}^\""));
    assert.deepStrictEqual(tokWin.tokens, ["curl", "https://example.com", "-H", "Accept: */*", "--data-raw", "{\"a\":1}"]);

    // Basic GET -> fetch
    const getFetch = devtools.runTool("curl_converter", "curl https://example.com/items", { target: "fetch" });
    assert.equal(getFetch.output, "const response = await fetch(\"https://example.com/items\");\nconst data = await response.text();");
    assert.equal(getFetch.meta.method, "GET");
    assert.equal(getFetch.meta.host, "example.com");

    // Multi-line POST with JSON, auth, cookies, combined flags -> fetch
    const postCmd = [
        "curl -sSLk -X POST 'https://api.example.com/v1/orders?dry_run=true' \\",
        "  -H 'Content-Type: application/json' \\",
        "  -H 'X-Request-Id: req_9481' \\",
        "  -u 'alice:s3cr3t' \\",
        "  -b 'sid=abc; theme=dark' \\",
        "  -m 10 \\",
        "  -d '{\"item\":\"keyboard\",\"qty\":2}'"
    ].join("\n");

    const postFetch = devtools.runTool("curl_converter", postCmd, { target: "fetch" });
    assert.ok(postFetch.output.includes("method: \"POST\""));
    assert.ok(postFetch.output.includes("\"Authorization\": \"Basic \" + btoa(\"alice:s3cr3t\")"));
    assert.ok(postFetch.output.includes("\"Cookie\": \"sid=abc; theme=dark\""));
    assert.ok(postFetch.output.includes("body: JSON.stringify({"));
    assert.ok(postFetch.output.includes("redirect: \"follow\""));
    assert.ok(postFetch.output.includes("AbortSignal.timeout(10000)"));
    assert.ok(postFetch.output.includes("skip TLS verification"));
    assert.equal(postFetch.meta.method, "POST");
    assert.equal(postFetch.meta.headers, 2);

    // Python requests target
    const postPy = devtools.runTool("curl_converter", postCmd, { target: "python" });
    assert.ok(postPy.output.includes("import requests"));
    assert.ok(postPy.output.includes("json_data = {\n    \"item\": \"keyboard\",\n    \"qty\": 2,\n}"));
    assert.ok(postPy.output.includes("cookies = {\n    \"sid\": \"abc\",\n    \"theme\": \"dark\",\n}"));
    assert.ok(postPy.output.includes("auth=(\"alice\", \"s3cr3t\")"));
    assert.ok(postPy.output.includes("verify=False"));
    assert.ok(postPy.output.includes("timeout=10"));

    // HTTPie target
    const postHttpie = devtools.runTool("curl_converter", postCmd, { target: "httpie" });
    assert.ok(postHttpie.output.includes("http --follow \\"));
    assert.ok(postHttpie.output.includes("--verify=no"));
    assert.ok(postHttpie.output.includes("--auth=alice:s3cr3t"));
    assert.ok(postHttpie.output.includes("--timeout=10"));
    assert.ok(postHttpie.output.includes("POST"));
    assert.ok(postHttpie.output.includes("item=keyboard"));
    assert.ok(postHttpie.output.includes("qty:=2"));

    // wget target
    const postWget = devtools.runTool("curl_converter", postCmd, { target: "wget" });
    assert.ok(postWget.output.includes("--method=POST"));
    assert.ok(postWget.output.includes("--no-check-certificate"));
    assert.ok(postWget.output.includes("--user='alice'"));
    assert.ok(postWget.output.includes("--body-data='{\"item\":\"keyboard\",\"qty\":2}'"));

    // Go net/http target
    const postGo = devtools.runTool("curl_converter", postCmd, { target: "go" });
    assert.ok(postGo.output.includes("http.NewRequest(\"POST\", \"https://api.example.com/v1/orders?dry_run=true\""));
    assert.ok(postGo.output.includes("req.SetBasicAuth(\"alice\", \"s3cr3t\")"));
    assert.ok(postGo.output.includes("req.AddCookie(&http.Cookie{Name: \"sid\", Value: \"abc\"})"));
    assert.ok(postGo.output.includes("InsecureSkipVerify: true"));
    assert.ok(postGo.output.includes("Timeout: 10 * time.Second"));

    // Parsed target
    const parsedOut = devtools.runTool("curl_converter", postCmd, { target: "parsed" });
    assert.ok(parsedOut.output.includes("Method      POST"));
    assert.ok(parsedOut.output.includes("Query parameters (1)"));
    assert.ok(parsedOut.output.includes("Headers (2)"));
    assert.ok(parsedOut.output.includes("Cookies (2)"));
    assert.ok(parsedOut.output.includes("Body (JSON)"));

    // -G / --get moves data to query string & --data-urlencode & repeatable -d
    const getQuery = devtools.runTool("curl_converter", "curl -G -d 'a=1' --data-urlencode 'q=hello world' 'https://example.com/search#top'", { target: "parsed" });
    assert.ok(getQuery.output.includes("Method      GET"));
    assert.ok(getQuery.output.includes("https://example.com/search?a=1&q=hello%20world#top"));
    assert.ok(!getQuery.output.includes("Body ("));

    // --json sets Content-Type and Accept
    const jsonFlagRes = devtools.runTool("curl_converter", "curl --json '{\"ok\":true}' https://example.com/api", { target: "parsed" });
    assert.ok(jsonFlagRes.output.includes("Method      POST"));
    assert.ok(jsonFlagRes.output.includes("Content-Type  application/json"));
    assert.ok(jsonFlagRes.output.includes("Accept        application/json"));

    // -I / --head defaults to HEAD, -F multipart with @file
    const headRes = devtools.runTool("curl_converter", "curl -I https://example.com", { target: "fetch" });
    assert.ok(headRes.output.includes("method: \"HEAD\""));

    const formCmd = "curl -F 'title=hello' -F 'avatar=@/tmp/pic.png;type=image/png' https://example.com/upload";
    const formFetch = devtools.runTool("curl_converter", formCmd, { target: "fetch" });
    assert.ok(formFetch.output.includes("new FormData()"));
    assert.ok(formFetch.output.includes("form.append(\"avatar\", new Blob([\"\"], { type: \"image/png\" }), \"pic.png\")"));
    const formPy = devtools.runTool("curl_converter", formCmd, { target: "python" });
    assert.ok(formPy.output.includes("files = {"));
    assert.ok(formPy.output.includes("open(\"/tmp/pic.png\", \"rb\")"));

    // Unknown flags emit warnings at the end
    const unkRes = devtools.runTool("curl_converter", "curl --http2 -Z https://example.com", { target: "fetch" });
    assert.ok(unkRes.output.includes("// Warning: unknown flags ignored: --http2, -Z"));

    // Reverse direction: raw HTTP request -> curl regardless of target
    const rawHttp = [
        "POST /v1/items HTTP/1.1",
        "Host: api.example.com",
        "Content-Type: application/json",
        "X-Trace: 42",
        "",
        "{\"name\":\"widget\"}"
    ].join("\n");
    const rev = devtools.runTool("curl_converter", rawHttp, { target: "python" });
    assert.equal(rev.output, [
        "curl -X POST \\",
        "  -H 'Content-Type: application/json' \\",
        "  -H 'X-Trace: 42' \\",
        "  -d '{\"name\":\"widget\"}' \\",
        "  'http://api.example.com/v1/items'"
    ].join("\n"));
    assert.equal(rev.meta.method, "POST");
    assert.equal(rev.meta.host, "api.example.com");

    // Errors: unclosed quote, missing URL, invalid input
    assert.ok(devtools.runTool("curl_converter", "curl 'https://example.com").error.includes("Unclosed"));
    assert.ok(devtools.runTool("curl_converter", "curl -X POST").error.includes("No URL"));
    assert.ok(devtools.runTool("curl_converter", "hello world").error.includes("cURL"));

    // Visual/layout checks: 2-space Go indent, compact Parsed view, capped padding & host chip
    assert.ok(!postGo.output.includes("\t"));
    assert.ok(postGo.output.includes("  req, err := http.NewRequest("));
    assert.ok(parsedOut.output.includes("Auth (Basic)"));
    assert.ok(!parsedOut.output.includes("Base URL"));

    const longHeaderParsed = devtools.runTool(
        "curl_converter",
        "curl -H 'X-Very-Long-Custom-Request-Header: val' https://very-long-subdomain.api.internal.example.com/v1",
        { target: "parsed" }
    );
    assert.ok(longHeaderParsed.output.includes("  X-Very-Long-Custom-Request-Header  val"));
    assert.ok(longHeaderParsed.meta.host.length <= 28);
    assert.ok(longHeaderParsed.meta.host.endsWith("…"));

    const sample = "curl -X POST 'https://ex.io/v1?dry=1' \\\n  -H 'Content-Type: application/json' \\\n  -H 'X-Request-Id: req_94' \\\n  -u 'alice:secret' \\\n  -d '{\"item\":\"kbd\",\"qty\":2}'";
    for (const target of ["fetch", "python", "httpie", "wget", "go", "parsed"]) {
        const res = devtools.runTool("curl_converter", sample, { target });
        assert.ok(!res.error && res.output.length > 0);
        assert.equal(res.meta.host, "ex.io");
    }

    console.log("✓ cURL Converter tests passed");
}
// @test-end curl_converter

// @test-begin json_query
{
    const plain = v => JSON.parse(JSON.stringify(v));
    const storeJson = JSON.stringify({
        store: {
            book: [
                { category: "reference", author: "Nigel Rees", title: "Sayings of the Century", price: 8.95 },
                { category: "fiction", author: "Evelyn Waugh", title: "Sword of Honour", price: 12.99 },
                { category: "fiction", author: "Herman Melville", title: "Moby Dick", isbn: "0-553-21311-3", price: 8.99 },
                { category: "fiction", author: "J. R. R. Tolkien", title: "The Lord of the Rings", isbn: "0-395-19395-8", price: 22.99 }
            ],
            bicycle: { color: "red", price: 399 }
        }
    });

    // Empty / invalid inputs
    assert.deepStrictEqual(plain(devtools.runTool("json_query", "   ", { query: "$.a" })), { output: "" });
    const badJson = devtools.runTool("json_query", "{bad", { query: "." });
    assert.ok(badJson.error && badJson.error.includes("Invalid JSON"));
    const emptyQ = devtools.runTool("json_query", storeJson, { query: "   " });
    assert.ok(emptyQ.error && emptyQ.error.includes("Query"));

    // JSONPath: child, wildcard, unions, negative index, slices, recursive descent
    const jpCheap = devtools.runTool("json_query", storeJson, { query: "$.store.book[?(@.price < 10)].title" });
    assert.equal(jpCheap.output, "\"Sayings of the Century\"\n\"Moby Dick\"");
    assert.deepStrictEqual(plain(jpCheap.meta), { results: 2, syntax: "JSONPath" });

    const jpCheapArr = devtools.runTool("json_query", storeJson, { query: "$.store.book[?(@.price < 10)].title", asArray: true });
    assert.deepStrictEqual(JSON.parse(jpCheapArr.output), ["Sayings of the Century", "Moby Dick"]);

    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$..author", asArray: true }).output), [
        "Nigel Rees", "Evelyn Waugh", "Herman Melville", "J. R. R. Tolkien"
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$.store['book'][0, -1]['author', 'price']", asArray: true }).output), [
        "Nigel Rees", 8.95, "J. R. R. Tolkien", 22.99
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$.store.book[1:3].title", asArray: true }).output), [
        "Sword of Honour", "Moby Dick"
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$.store.book[::-2].title", asArray: true }).output), [
        "The Lord of the Rings", "Sword of Honour"
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$.store.*", asArray: true }).output).length, 2);

    // JSONPath: filters (existence, regex, boolean ops, length(), root ref)
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$.store.book[?@.isbn && !(@.price > 10)].title", asArray: true }).output), [
        "Moby Dick"
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$.store.book[?(@.author =~ /tolkien/i || length(@.title) < 10)].title", asArray: true }).output), [
        "Moby Dick", "The Lord of the Rings"
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: "$.store.book[?(@.price < $.store.bicycle.price && @.category == 'reference')].author", asArray: true }).output), [
        "Nigel Rees"
    ]);

    // JSONPath syntax errors include column
    const jpErr = devtools.runTool("json_query", storeJson, { query: "$.store.book[0" });
    assert.ok(jpErr.error && jpErr.error.includes("column"));

    // jq: paths, quoted keys, indexing, slicing, optionality, pipe, comma
    assert.equal(devtools.runTool("json_query", "{\"a b\": [10, 20, 30, 40]}", { query: ".\"a b\"[1:3]" }).output, "[\n  20,\n  30\n]");
    assert.equal(devtools.runTool("json_query", "{\"a\": 1}", { query: ".a, .missing, (.missing // 99)" }).output, "1\nnull\n99");
    assert.equal(devtools.runTool("json_query", "{\"a\": 5}", { query: ".a[]?" }).output, "");
    assert.ok(devtools.runTool("json_query", "{\"a\": 5}", { query: ".a[]" }).error.includes("iterate"));

    // jq: array & object construction, shorthand, dynamic keys, string interpolation
    const jqObj = devtools.runTool("json_query", storeJson, {
        query: "[.store.book[] | select(.price < 10) | {title, author, \"tag\": \"deal\", (.category): .price, label: \"\\(.author): $\\(.price)\"}]",
        syntax: "jq"
    });
    assert.deepStrictEqual(JSON.parse(jqObj.output), [
        { title: "Sayings of the Century", author: "Nigel Rees", tag: "deal", reference: 8.95, label: "Nigel Rees: $8.95" },
        { title: "Moby Dick", author: "Herman Melville", tag: "deal", fiction: 8.99, label: "Herman Melville: $8.99" }
    ]);
    assert.deepStrictEqual(plain(jqObj.meta), { results: 1, syntax: "jq" });

    // jq: collections, entries, aggregations, sorting, grouping
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"b\": 2, \"a\": 1}", { query: "keys" }).output), ["a", "b"]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\": 1, \"b\": 2}", { query: "with_entries({key: (.key | ascii_upcase), value: (.value * 10)})" }).output), { A: 10, B: 20 });
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[1, null, 2, null]", { query: "map(values)" }).output), [1, 2]);
    assert.equal(devtools.runTool("json_query", "{\"a\": 1}", { query: "has(\"a\"), (\"a\" | in({\"a\": 1})), (. as $o | \"z\" | in($o))" }).output, "true\ntrue\nfalse");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, {
        query: ".store.book | group_by(.category) | map({cat: .[0].category, n: length, max: (map(.price) | max)})"
    }).output), [
        { cat: "fiction", n: 3, max: 22.99 },
        { cat: "reference", n: 1, max: 8.95 }
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[3, 1, 2, 1]", { query: "unique | reverse" }).output), [3, 2, 1]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[{\"k\":2},{\"k\":1},{\"k\":2}]", { query: "unique_by(.k) | sort_by(-.k)" }).output), [{ k: 2 }, { k: 1 }]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[[1, [2, 3]], 4]", { query: "flatten(1)" }).output), [1, [2, 3], 4]);
    assert.equal(devtools.runTool("json_query", "[1, 2, 3, 4]", { query: "add, min, max, first, last, any(. > 3), all(. > 0)" }).output, "10\n1\n4\n1\n4\ntrue\ntrue");
    assert.equal(devtools.runTool("json_query", "[{\"a\":1},{\"b\":2}]", { query: "add" }).output, "{\n  \"a\": 1,\n  \"b\": 2\n}");
    assert.equal(devtools.runTool("json_query", "{\"x\": 1}", { query: "min_by(.p)" }).error ? "err" : "ok", "err");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, { query: ".store.book | [min_by(.price).title, max_by(.price).title]" }).output), [
        "Sayings of the Century", "The Lord of the Rings"
    ]);
    assert.equal(devtools.runTool("json_query", "[1, 2]", { query: "map_values(. + 1) | [range(3)]" }).output, "[\n  0,\n  1,\n  2\n]");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":1,\"b\":2}", { query: "map_values(. + 10)" }).output), { a: 11, b: 12 });

    // jq: strings, types, logic, conditionals, bindings, reduce, error
    assert.equal(devtools.runTool("json_query", "\"  Hello World!  \"", { query: "ltrimstr(\"  \") | rtrimstr(\"  \") | ascii_downcase | split(\" \") | join(\"-\")" }).output, "\"hello-world!\"");
    assert.equal(devtools.runTool("json_query", "\"QuickShell\"", { query: "[type, length, startswith(\"Quick\"), endswith(\"Shell\"), test(\"^quick\"; \"i\"), (\"42\" | tonumber), (42 | tostring)]" }).output, "[\n  \"string\",\n  10,\n  true,\n  true,\n  true,\n  42,\n  \"42\"\n]");
    assert.equal(devtools.runTool("json_query", "{\"a\": [1, 2, 3], \"b\": \"hi\"}", { query: "contains({a: [2]}) and (false | not)" }).output, "true");
    assert.equal(devtools.runTool("json_query", "[5, 15, 25]", { query: "[.[] | if . < 10 then \"low\" elif . < 20 then \"mid\" else \"high\" end]" }).output, "[\n  \"low\",\n  \"mid\",\n  \"high\"\n]");
    assert.equal(devtools.runTool("json_query", "{\"a\": 10, \"b\": 20}", { query: ".a as $x | $x + .b" }).output, "30");
    assert.equal(devtools.runTool("json_query", "[1, 2, 3, 4]", { query: "reduce .[] as $x (0; . + $x)" }).output, "10");
    assert.equal(devtools.runTool("json_query", "1", { query: "empty" }).output, "");
    assert.ok(devtools.runTool("json_query", "1", { query: "error(\"boom\")" }).error.includes("boom"));
    assert.ok(devtools.runTool("json_query", "1", { query: ". + (" }).error.includes("column"));
    assert.equal(devtools.runTool("json_query", "{\"a\":1}", { query: "$x", syntax: "jq" }).error.includes("$x"), true);

    // jq: per-item error suppression (?) and try / catch
    const usersJson = JSON.stringify({ users: [{ tags: ["a", "b"] }, { tags: [] }, { name: "cy" }] });
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", usersJson, { query: "[.users[].tags[]?]" }).output), ["a", "b"]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[{\"a\":1},\"bad\",{\"a\":2}]", { query: "map(.a?)" }).output), [1, 2]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[{\"a\":1},\"bad\",{\"a\":2}]", { query: "[.[] | select(.a? > 0) | .a]" }).output), [1, 2]);
    assert.equal(devtools.runTool("json_query", "null", { query: "try (1, error(\"boom\"), 2) catch (\"caught:\" + .)" }).output, "1\n\"caught:boom\"");
    assert.equal(devtools.runTool("json_query", "{\"a\":5}", { query: "try .a[] catch \"no-iter\"" }).output, "\"no-iter\"");

    // jq: update-assignment operators (|=, =, +=, -=, *=, /=, //=)
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":{\"b\":10},\"c\":99}", {
        query: ".a.b |= . + 1 | .a.x = .c | .a.b += 4 | .a.b -= 5 | .a.b *= 2 | .a.b /= 4 | .d //= 7 | .a.b //= 99"
    }).output), { a: { b: 5, x: 99 }, c: 99, d: 7 });
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[1,2,3,4]", { query: "(.[] | select(. > 2)) |= empty" }).output), [1, 2]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":1,\"b\":[2,\"x\",{\"c\":3}]}", { query: "(.. | numbers) += 1" }).output), { a: 2, b: [3, "x", { c: 4 }] });

    // jq: user definitions (def, filter params, $var params, recursion)
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[1,2,3]", {
        query: "def mymap(f): [.[] | f]; def addn($n): . + $n; mymap(addn(10))"
    }).output), [11, 12, 13]);
    assert.equal(devtools.runTool("json_query", "5", {
        query: "def fact: if . <= 1 then 1 else . * ((. - 1) | fact) end; fact"
    }).output, "120");

    // jq: paths, leaf_paths, path, getpath, setpath, delpaths, del
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":[1,{\"b\":2}],\"c\":3}", { query: "[paths]" }).output), [
        ["a"], ["a", 0], ["a", 1], ["a", 1, "b"], ["c"]
    ]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":[1,{\"b\":2}],\"c\":3}", { query: "[leaf_paths]" }).output), [
        ["a", 0], ["a", 1, "b"], ["c"]
    ]);
    assert.equal(devtools.runTool("json_query", "{\"a\":[1,{\"b\":2}]}", { query: "getpath([\"a\",1,\"b\"])" }).output, "2");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":[1,{\"b\":2}]}", { query: "setpath([\"a\",1,\"b\"]; 99) | delpaths([[\"a\",0]])" }).output), {
        a: [{ b: 99 }]
    });
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":[10,20,30],\"b\":2}", { query: "del(.a[0], .b)" }).output), {
        a: [20, 30]
    });
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":[1,2]}", { query: "[path(.a[])]" }).output), [["a", 0], ["a", 1]]);

    // jq: stream control (limit, first/last with filter, while, until, recurse, .., $ENV)
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "1", { query: "[limit(3; recurse(. + 1))]" }).output), [1, 2, 3]);
    assert.equal(devtools.runTool("json_query", "null", { query: "first(10, error(\"boom\")), last(10, 20, 30)" }).output, "10\n30");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "1", { query: "[while(. < 8; . * 2)]" }).output), [1, 2, 4]);
    assert.equal(devtools.runTool("json_query", "1", { query: "until(. >= 16; . * 2)" }).output, "16");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":[1,2]}", { query: "[..]" }).output), [{ a: [1, 2] }, [1, 2], 1, 2]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", { query: "$ENV" }).output), {});

    // jq: tojson, fromjson, format strings, regex, codepoints, indices, inside, *
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"x\":1}", { query: "tojson | fromjson" }).output), { x: 1 });
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "\"a<b>&\\\"c' \"", {
        query: "[@json, @text, @html, @uri, @base64]"
    }).output), [
        "\"a<b>&\\\"c' \"",
        "a<b>&\"c' ",
        "a&lt;b&gt;&amp;&quot;c&apos; ",
        "a%3Cb%3E%26%22c%27%20",
        "YTxiPiYiYycg"
    ]);
    assert.equal(devtools.runTool("json_query", "\"aGVsbG8=\"", { query: "@base64d" }).output, "\"hello\"");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "[\"a\",\"b,c\",\"d\\\"e\",1,null,true]", {
        query: "[@csv, @tsv]"
    }).output), ["\"a\",\"b,c\",\"d\"\"e\",1,,true", "a\tb,c\td\"e\t1\t\ttrue"]);
    assert.equal(devtools.runTool("json_query", "{\"q\":\"a b&c\"}", { query: "@uri \"q=\\(.q)\"" }).output, "\"q=a%20b%26c\"");
    assert.equal(devtools.runTool("json_query", "\"bAAadAa\"", { query: "gsub(\"a+\"; \"X\"; \"i\")" }).output, "\"bXdX\"");
    assert.equal(devtools.runTool("json_query", "\"hello world\"", { query: "sub(\"(?<w>\\\\w+)\"; \"[\\(.w)]\")" }).output, "\"[hello] world\"");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "\"a, b,c\"", { query: "[splits(\",\\\\s*\")]" }).output), ["a", "b", "c"]);
    assert.equal(devtools.runTool("json_query", "\"a\\nb\"", { query: "test(\"a.b\"; \"m\") and (\"abc\" | test(\"A B # c\"; \"ix\"))" }).output, "true");
    assert.equal(devtools.runTool("json_query", "\"hi!\"", { query: "explode | implode" }).output, "\"hi!\"");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "\"ababa\"", { query: "[index(\"ab\"), rindex(\"ab\"), indices(\"ab\")]" }).output), [0, 2, [0, 2]]);
    assert.equal(devtools.runTool("json_query", "{\"a\":[2]}", { query: "inside({\"a\":[1,2,3],\"b\":1})" }).output, "true");
    assert.equal(devtools.runTool("json_query", "\"x\"", { query: ". * 0, . * 3" }).output, "\"\"\n\"xxx\"");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "{\"a\":{\"x\":1,\"y\":2}}", { query: ". * {\"a\":{\"y\":9,\"z\":3}}" }).output), {
        a: { x: 1, y: 9, z: 3 }
    });

    // jq: foreach (2-arg & 3-arg), label / break
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", {
        query: "[foreach range(5) as $i (0; . + $i)]"
    }).output), [0, 1, 3, 6, 10]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", {
        query: "[foreach (1, 2, 3) as $x (0; . + $x; [., $x])]"
    }).output), [[1, 1], [3, 2], [6, 3]]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", {
        query: "[foreach (1, 2) as $x ((10, 20); . + $x)]"
    }).output), [11, 13, 21, 23]);
    assert.equal(devtools.runTool("json_query", usersJson, {
        query: "label $out | foreach .users[] as $u (0; . + 1; if . == 2 then ., break $out else empty end)"
    }).output, "2");
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", {
        query: "[label $a | (label $b | (1, break $b, 2), 3), 4]"
    }).output), [1, 4]);
    assert.ok(devtools.runTool("json_query", "null", { query: "if false then break $missing else 1 end" }).error.includes("not defined"));

    // jq: math builtins
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "-2.5", {
        query: "[floor, ceil, round, fabs, trunc]"
    }).output), [-3, -2, -3, 2.5, -2]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", {
        query: "[(9 | sqrt), (-1 | sqrt | isnan), pow(2; 10), (1 | log), (8 | log2), (100 | log10), (0 | exp), (3 | exp10)]"
    }).output), [3, true, 1024, 0, 3, 2, 1, 1000]);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", {
        query: "[infinite, nan, (infinite | isinfinite), (nan | isnan), (1 | isnormal), (0 | isnormal), (infinite | isnormal), (nan | isnormal)]"
    }).output), [1.7976931348623157e+308, null, true, true, true, false, false, false]);
    assert.ok(devtools.runTool("json_query", "\"abc\"", { query: "floor" }).error.includes("number"));

    // jq: SQL-style INDEX and IN
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", storeJson, {
        query: ".store.book | INDEX(.title) | keys | length"
    }).output), 4);
    assert.deepStrictEqual(JSON.parse(devtools.runTool("json_query", "null", {
        query: "INDEX((1, 2); tostring)"
    }).output), { "1": 1, "2": 2 });
    assert.equal(devtools.runTool("json_query", "2", {
        query: "IN(2, error(\"boom\")), IN(5, 6), IN((1, 2); (2, error(\"boom\")))"
    }).output, "true\nfalse\ntrue");

    console.log("✓ JSON Query (JSONPath / jq) tests passed");
}
// @test-end json_query

// @test-begin json_types
{
    const jtypesPlain = x => JSON.parse(JSON.stringify(x));

    // Empty / whitespace input
    assert.deepStrictEqual(jtypesPlain(devtools.runTool("json_types", "")), { output: "" });
    assert.deepStrictEqual(jtypesPlain(devtools.runTool("json_types", "   \n  ")), { output: "" });

    // Error cases
    assert.ok(devtools.runTool("json_types", "{bad json").error.includes("Invalid JSON"));
    assert.ok(devtools.runTool("json_types", "\"hello\"").error.includes("object or array"));
    assert.ok(devtools.runTool("json_types", "42").error.includes("object or array"));
    assert.ok(devtools.runTool("json_types", "null").error.includes("object or array"));
    assert.ok(devtools.runTool("json_types", "{}", { target: "java" }).error.includes("Unsupported target"));

    // Sample API payload across all 6 targets
    const apiJson = JSON.stringify({
        id: 1042,
        username: "ana_silva",
        createdAt: "2026-04-12T14:30:00Z",
        bio: null,
        address: { street: "Av. Paulista", zipCode: "01310-100" },
        orders: [
            { orderId: "ord-1", total: 149.9, paid: true, couponCode: "SPRING10" },
            { orderId: "ord-2", total: 80, paid: false }
        ]
    });

    // TypeScript
    const ts = devtools.runTool("json_types", apiJson, { target: "typescript", rootName: "UserResponse" });
    assert.equal(ts.error, undefined);
    assert.deepStrictEqual(jtypesPlain(ts.meta), { types: 3, target: "TypeScript" });
    assert.equal(ts.output, [
        "export interface Address {",
        "  street: string;",
        "  zipCode: string;",
        "}",
        "",
        "export interface Order {",
        "  orderId: string;",
        "  total: number;",
        "  paid: boolean;",
        "  couponCode?: string;",
        "}",
        "",
        "export interface UserResponse {",
        "  id: number;",
        "  username: string;",
        "  createdAt: string; // ISO date",
        "  bio: unknown | null;",
        "  address: Address;",
        "  orders: Order[];",
        "}"
    ].join("\n"));

    // Zod
    const zod = devtools.runTool("json_types", apiJson, { target: "zod" });
    assert.deepStrictEqual(jtypesPlain(zod.meta), { types: 3, target: "Zod" });
    assert.equal(zod.output, [
        "import { z } from \"zod\";",
        "",
        "export const AddressSchema = z.object({",
        "  street: z.string(),",
        "  zipCode: z.string(),",
        "});",
        "export type Address = z.infer<typeof AddressSchema>;",
        "",
        "export const OrderSchema = z.object({",
        "  orderId: z.string(),",
        "  total: z.number(),",
        "  paid: z.boolean(),",
        "  couponCode: z.string().optional(),",
        "});",
        "export type Order = z.infer<typeof OrderSchema>;",
        "",
        "export const RootSchema = z.object({",
        "  id: z.number().int(),",
        "  username: z.string(),",
        "  createdAt: z.string(), // ISO date",
        "  bio: z.unknown().nullable(),",
        "  address: AddressSchema,",
        "  orders: z.array(OrderSchema),",
        "});",
        "export type Root = z.infer<typeof RootSchema>;"
    ].join("\n"));

    // Python dataclasses
    const py = devtools.runTool("json_types", apiJson, { target: "python" });
    assert.deepStrictEqual(jtypesPlain(py.meta), { types: 3, target: "Python" });
    assert.equal(py.output, [
        "from dataclasses import dataclass",
        "from typing import Any, Optional",
        "",
        "@dataclass",
        "class Address:",
        "    street: str",
        "    zip_code: str  # json: \"zipCode\"",
        "",
        "@dataclass",
        "class Order:",
        "    order_id: str  # json: \"orderId\"",
        "    total: float",
        "    paid: bool",
        "    coupon_code: Optional[str] = None  # json: \"couponCode\"",
        "",
        "@dataclass",
        "class Root:",
        "    id: int",
        "    username: str",
        "    created_at: str  # json: \"createdAt\"",
        "    bio: Optional[Any]",
        "    address: Address",
        "    orders: list[Order]"
    ].join("\n"));

    // Go structs with initialisms, tab indentation, & gofmt column alignment
    const go = devtools.runTool("json_types", apiJson, { target: "go" });
    assert.deepStrictEqual(jtypesPlain(go.meta), { types: 3, target: "Go" });
    assert.equal(go.output, [
        "type Address struct {",
        "\tStreet  string `json:\"street\"`",
        "\tZipCode string `json:\"zipCode\"`",
        "}",
        "",
        "type Order struct {",
        "\tOrderID    string  `json:\"orderId\"`",
        "\tTotal      float64 `json:\"total\"`",
        "\tPaid       bool    `json:\"paid\"`",
        "\tCouponCode *string `json:\"couponCode,omitempty\"`",
        "}",
        "",
        "type Root struct {",
        "\tID        int64   `json:\"id\"`",
        "\tUsername  string  `json:\"username\"`",
        "\tCreatedAt string  `json:\"createdAt\"`",
        "\tBio       any     `json:\"bio\"` // null only",
        "\tAddress   Address `json:\"address\"`",
        "\tOrders    []Order `json:\"orders\"`",
        "}"
    ].join("\n"));
    const goFieldLines = go.output.split("\n").filter(l => l.startsWith("\t") || l.startsWith(" "));
    assert.ok(goFieldLines.length > 0);
    assert.ok(goFieldLines.every(l => /^\t[^\t ]/.test(l)), "Go struct field lines must be tab-indented");

    // Rust serde structs
    const rs = devtools.runTool("json_types", apiJson, { target: "rust" });
    assert.deepStrictEqual(jtypesPlain(rs.meta), { types: 3, target: "Rust" });
    assert.equal(rs.output, [
        "use serde::{Deserialize, Serialize};",
        "",
        "#[derive(Debug, Clone, Serialize, Deserialize)]",
        "pub struct Address {",
        "    pub street: String,",
        "    #[serde(rename = \"zipCode\")]",
        "    pub zip_code: String,",
        "}",
        "",
        "#[derive(Debug, Clone, Serialize, Deserialize)]",
        "pub struct Order {",
        "    #[serde(rename = \"orderId\")]",
        "    pub order_id: String,",
        "    pub total: f64,",
        "    pub paid: bool,",
        "    #[serde(rename = \"couponCode\")]",
        "    pub coupon_code: Option<String>,",
        "}",
        "",
        "#[derive(Debug, Clone, Serialize, Deserialize)]",
        "pub struct Root {",
        "    pub id: i64,",
        "    pub username: String,",
        "    #[serde(rename = \"createdAt\")]",
        "    pub created_at: String,",
        "    pub bio: Option<serde_json::Value>,",
        "    pub address: Address,",
        "    pub orders: Vec<Order>,",
        "}"
    ].join("\n"));

    // JSON Schema draft 2020-12
    const js = devtools.runTool("json_types", apiJson, { target: "jsonschema" });
    assert.deepStrictEqual(jtypesPlain(js.meta), { types: 3, target: "JSON Schema" });
    assert.deepStrictEqual(JSON.parse(js.output), {
        $schema: "https://json-schema.org/draft/2020-12/schema",
        title: "Root",
        type: "object",
        properties: {
            id: { type: "integer" },
            username: { type: "string" },
            createdAt: { type: "string" },
            bio: { type: "null" },
            address: { $ref: "#/$defs/Address" },
            orders: { type: "array", items: { $ref: "#/$defs/Order" } }
        },
        required: ["id", "username", "createdAt", "bio", "address", "orders"],
        additionalProperties: false,
        $defs: {
            Address: {
                type: "object",
                properties: {
                    street: { type: "string" },
                    zipCode: { type: "string" }
                },
                required: ["street", "zipCode"],
                additionalProperties: false
            },
            Order: {
                type: "object",
                properties: {
                    orderId: { type: "string" },
                    total: { type: "number" },
                    paid: { type: "boolean" },
                    couponCode: { type: "string" }
                },
                required: ["orderId", "total", "paid"],
                additionalProperties: false
            }
        }
    });

    // Singularization, shape deduplication, and name clash resolution
    const complex = JSON.stringify({
        users: [{ id: 1 }],
        categories: [{ title: "Books" }],
        addresses: [{ city: "NYC" }],
        billingAddress: { city: "NYC" },
        firstItem: { count: 1 },
        nested: { firstItem: { label: "x" } }
    });
    const tsComplex = devtools.runTool("json_types", complex, { target: "typescript" });
    assert.ok(tsComplex.output.includes("export interface User {"));
    assert.ok(tsComplex.output.includes("export interface Category {"));
    assert.ok(tsComplex.output.includes("export interface Address {"));
    // billingAddress reuses Address (deduplicated) instead of creating BillingAddress
    assert.equal(tsComplex.output.includes("BillingAddress"), false);
    assert.ok(tsComplex.output.includes("billingAddress: Address;"));
    // firstItem clashes with nested.firstItem -> FirstItem & FirstItem2
    assert.ok(tsComplex.output.includes("export interface FirstItem {"));
    assert.ok(tsComplex.output.includes("export interface FirstItem2 {"));

    // Mixed primitives, empty arrays, invalid identifier keys, nullable+optional, root array
    const mixedInput = JSON.stringify({
        "first-name": "Ada",
        "type": "admin",
        emptyList: [],
        mixed: [1, "two", null],
        homepageUrl: "https://example.com"
    });
    const tsMixed = devtools.runTool("json_types", mixedInput, { target: "typescript" });
    assert.ok(tsMixed.output.includes("\"first-name\": string;"));
    assert.ok(tsMixed.output.includes("emptyList: unknown[]; // empty array"));
    assert.ok(tsMixed.output.includes("mixed: (number | string | null)[];"));

    const goMixed = devtools.runTool("json_types", mixedInput, { target: "go" });
    assert.ok(goMixed.output.includes("HomepageURL"));
    assert.ok(goMixed.output.includes("[]any"));
    assert.ok(goMixed.output.includes("// mixed: int64 | string"));
    assert.equal(goMixed.output, [
        "type Root struct {",
        "\tFirstName   string `json:\"first-name\"`",
        "\tType        string `json:\"type\"`",
        "\tEmptyList   []any  `json:\"emptyList\"` // empty array",
        "\tMixed       []any  `json:\"mixed\"`     // mixed: int64 | string",
        "\tHomepageURL string `json:\"homepageUrl\"`",
        "}"
    ].join("\n"));

    // Go tag escaping for control characters & backticks
    const goSpecial = devtools.runTool("json_types", JSON.stringify({ "new\nline": 1, "back`tick": "x" }), { target: "go" });
    assert.equal(goSpecial.output, [
        "type Root struct {",
        "\tNewLine  int64  `json:\"new\\nline\"`",
        "\tBackTick string \"json:\\\"back`tick\\\"\"",
        "}"
    ].join("\n"));

    const rsMixed = devtools.runTool("json_types", mixedInput, { target: "rust" });
    assert.ok(rsMixed.output.includes("#[serde(rename = \"first-name\")]"));
    assert.ok(rsMixed.output.includes("pub first_name: String,"));
    assert.ok(rsMixed.output.includes("#[serde(rename = \"type\")]"));
    assert.ok(rsMixed.output.includes("pub type_: String,"));
    assert.ok(rsMixed.output.includes("Vec<serde_json::Value>"));

    // Root array of objects
    const rootArr = devtools.runTool("json_types", "[{\"id\":1},{\"id\":2,\"tag\":null}]", { target: "typescript", rootName: "Users" });
    assert.equal(rootArr.output, [
        "export interface User {",
        "  id: number;",
        "  tag?: unknown | null;",
        "}",
        "",
        "export type Users = User[];"
    ].join("\n"));
    assert.deepStrictEqual(jtypesPlain(rootArr.meta), { types: 2, target: "TypeScript" });

    // Empty root array
    const emptyRootArr = devtools.runTool("json_types", "[]", { target: "python" });
    assert.equal(emptyRootArr.output, "from typing import Any\n\nRoot = list[Any]  # empty array");

    console.log("✓ JSON → Types tests passed");
}
// @test-end json_types

// @test-begin glob_tester
{
    const plain = value => JSON.parse(JSON.stringify(value));

    // Empty / whitespace input
    assert.deepStrictEqual(plain(devtools.globtTool("")), { output: "" });
    assert.deepStrictEqual(plain(devtools.globtTool("   \n  ")), { output: "" });

    // Error cases
    assert.ok(devtools.globtTool("*.log\napp.log").error.includes("---"));
    assert.ok(devtools.globtTool("---\napp.log").error.includes("before ---"));
    assert.ok(devtools.globtTool("*.log\n---").error.includes("after ---"));
    assert.ok(devtools.globtTool("[abc\n---\na").error.includes("unclosed '['"));
    assert.ok(devtools.globtTool("{a,b\n---\na", { mode: "glob" }).error.includes("unclosed '{'"));
    assert.ok(devtools.globtTool("!\n---\na").error.includes("negated pattern"));
    assert.ok(devtools.globtTool("foo\\\n---\nfoo").error.includes("trailing backslash"));

    // gitignore(5): comments, escapes, trailing spaces, anchoring, dirOnly, **, parent-dir rule
    const giInput = [
        "# comment",
        "node_modules/",
        "*.log",
        "!important.log",
        "/build",
        "!build/keep.txt",
        "docs/**/*.pdf",
        "\\#hash.md",
        "\\!bang.txt",
        "trailing\\   ",
        "---",
        "node_modules/",
        "node_modules/pkg/index.js",
        "src/app.log",
        "important.log",
        "build/",
        "build/keep.txt",
        "src/build/app.js",
        "docs/a.pdf",
        "docs/x/y/b.pdf",
        "#hash.md",
        "!bang.txt",
        "trailing ",
        "trailing"
    ].join("\n");
    const giRes = devtools.runTool("glob_tester", giInput, { mode: "gitignore" });
    assert.ok(!giRes.error);
    assert.deepStrictEqual(plain(giRes.meta), { mode: "gitignore", matched: "10/13", patterns: 9 });
    assert.ok(giRes.output.includes("✓ ignored  node_modules/     #2 node_modules/"));
    assert.ok(giRes.output.includes("✓ ignored  node_modules/pkg/index.js\n             #2 via node_modules/"));
    assert.ok(giRes.output.includes("✓ ignored  src/app.log       #3 *.log"));
    assert.ok(giRes.output.includes("· kept     important.log     #4 !important.log"));
    assert.ok(giRes.output.includes("✓ ignored  build/keep.txt    #5 /build (via build/)"));
    assert.ok(giRes.output.includes("· kept     src/build/app.js  —"));
    assert.ok(giRes.output.includes("✓ ignored  docs/a.pdf        #7 docs/**/*.pdf"));
    assert.ok(giRes.output.includes("✓ ignored  docs/x/y/b.pdf    #7 docs/**/*.pdf"));
    assert.ok(giRes.output.includes("✓ ignored  #hash.md          #8 \\#hash.md"));
    assert.ok(giRes.output.includes("✓ ignored  !bang.txt         #9 \\!bang.txt"));
    assert.ok(giRes.output.includes("✓ ignored  trailing          #10 trailing\\ "));
    // Unescaped "trailing" (without space) is kept because line 10 had "\ "
    const trailingLine = giRes.output.split("\n").find(l => /· kept\s+trailing\s+—/.test(l));
    assert.ok(trailingLine);

    // gitignore(5): whitelist pattern with !*/ keeps parent dirs open for re-inclusion
    const wlRes = devtools.globtTool("*\n!*/\n!*.ts\n---\nsrc/a.ts\nsrc/b.js", { mode: "gitignore" });
    assert.equal(wlRes.meta.matched, "1/2");
    assert.ok(wlRes.output.includes("· kept     src/a.ts"));
    assert.ok(wlRes.output.includes("✓ ignored  src/b.js"));

    // gitignore(5): file vs dirOnly when path is a file
    const dirOnlyRes = devtools.globtTool("dist/\n---\ndist\ndist/", { mode: "gitignore" });
    assert.equal(dirOnlyRes.meta.matched, "1/2");
    assert.ok(dirOnlyRes.output.includes("· kept     dist "));
    assert.ok(dirOnlyRes.output.includes("✓ ignored  dist/"));

    // gitignore(5): middle slash anchors, leading **/ matches at any depth, /** matches inside
    const slashRes = devtools.globtTool("a/b.txt\n**/leaf\nin/**\n---\na/b.txt\nx/a/b.txt\nleaf\nx/y/leaf\nin\nin/file.txt", { mode: "gitignore" });
    assert.equal(slashRes.meta.matched, "4/6");
    assert.ok(slashRes.output.includes("✓ ignored  a/b.txt"));
    assert.ok(slashRes.output.includes("· kept     x/a/b.txt"));
    assert.ok(slashRes.output.includes("✓ ignored  leaf"));
    assert.ok(slashRes.output.includes("✓ ignored  x/y/leaf"));
    assert.ok(slashRes.output.includes("· kept     in "));
    assert.ok(slashRes.output.includes("✓ ignored  in/file.txt"));

    // glob mode: *, **, ?, character classes, nested braces, escapes, negation
    const globInput = [
        "src/**/*.{ts,tsx}",
        "!src/**/*.test.{ts,tsx}",
        "doc[0-9]?.md",
        "file[!a].txt",
        "sub/{x,{y,z}}.js",
        "\\*literal.txt",
        "---",
        "src/app.ts",
        "src/ui/btn.tsx",
        "src/app.test.ts",
        "doc1a.md",
        "doc1/a.md",
        "filea.txt",
        "fileb.txt",
        "file/.txt",
        "sub/y.js",
        "*literal.txt"
    ].join("\n");
    const globRes = devtools.runTool("glob_tester", globInput, { mode: "glob" });
    assert.ok(!globRes.error);
    assert.deepStrictEqual(plain(globRes.meta), { mode: "glob", matched: "6/10", patterns: 6 });
    assert.ok(globRes.output.includes("  #1  src/**/*.{ts,tsx}  ^src/(?:.+/)?[^/]*\\.(?:ts|tsx)$"));
    assert.ok(globRes.output.includes("  #2  !src/**/*.test.{ts,tsx}\n      ^src/(?:.+/)?[^/]*\\.test\\.(?:ts|tsx)$ (negate)"));
    assert.ok(globRes.output.includes("✓ match     src/app.ts      #1 src/**/*.{ts,tsx}"));
    assert.ok(globRes.output.includes("✓ match     src/ui/btn.tsx  #1 src/**/*.{ts,tsx}"));
    assert.ok(globRes.output.includes("· no match  src/app.test.ts\n              #2 !src/**/*.test.{ts,tsx} (also: #1)"));
    assert.ok(globRes.output.includes("✓ match     doc1a.md        #3 doc[0-9]?.md"));
    assert.ok(globRes.output.includes("· no match  doc1/a.md       —"));
    assert.ok(globRes.output.includes("· no match  filea.txt       —"));
    assert.ok(globRes.output.includes("✓ match     fileb.txt       #4 file[!a].txt"));
    assert.ok(globRes.output.includes("· no match  file/.txt       —"));
    assert.ok(globRes.output.includes("✓ match     sub/y.js        #5 sub/{x,{y,z}}.js"));
    assert.ok(globRes.output.includes("✓ match     *literal.txt    #6 \\*literal.txt"));

    // glob mode: negation-only list acts as exclusion filter
    const negOnlyRes = devtools.globtTool("!*.log\n---\napp.ts\napp.log", { mode: "glob" });
    assert.equal(negOnlyRes.meta.matched, "1/2");
    assert.ok(negOnlyRes.output.includes("✓ match     app.ts"));
    assert.ok(negOnlyRes.output.includes("· no match  app.log"));

    // Visual fit: compact sampleInput stays within 57 chars per line and 22 lines
    const sampleInput = [
        "# Dependencies & logs",
        "node_modules/",
        "*.log",
        "!important.log",
        "",
        "# Root-only build output",
        "/build",
        "!build/keep.txt",
        "",
        "# Nested docs & escaped hash",
        "docs/**/*.pdf",
        "\\#draft.md",
        "---",
        "node_modules/",
        "node_modules/pkg.js",
        "src/app.log",
        "important.log",
        "build/",
        "build/keep.txt",
        "src/build/readme.md",
        "docs/guide.pdf",
        "docs/a/b/spec.pdf",
        "#draft.md",
        "src/index.ts"
    ].join("\n");
    const sampleRes = devtools.runTool("glob_tester", sampleInput, { mode: "gitignore" });
    assert.ok(!sampleRes.error);
    assert.deepStrictEqual(plain(sampleRes.meta), { mode: "gitignore", matched: "8/11", patterns: 7 });
    const sampleLines = sampleRes.output.split("\n");
    assert.ok(sampleLines.length <= 22, "expected <= 22 lines, got " + sampleLines.length);
    for (const line of sampleLines)
        assert.ok(line.length <= 57, "line exceeds 57 chars (" + line.length + "): " + line);

    // Column alignment & graceful wrap when an entry exceeds width budget
    const wrapLines = globRes.output.split("\n");
    for (const line of wrapLines)
        assert.ok(line.length <= 57, "glob line exceeds 57 chars (" + line.length + "): " + line);

    console.log("✓ Glob & .gitignore tester tests passed");
}
// @test-end glob_tester

// @test-begin semver_tool
{
    const plain = value => JSON.parse(JSON.stringify(value));
    const run = (input, opts) => devtools.runTool("semver_tool", input, opts);

    // Empty / whitespace input
    assert.deepStrictEqual(plain(run("")), { output: "" });
    assert.deepStrictEqual(plain(run("   \n  \t ")), { output: "" });

    // Form 1: Single version breakdown and bumps
    const single = run("1.2.3-alpha.1+build.42", { pre: "rc" });
    assert.equal(single.error, undefined);
    assert.equal(single.meta.version, "1.2.3-alpha.1+build.42");
    assert.equal(single.meta.channel, "prerelease");
    assert.equal(single.meta.nextPatch, "1.2.3");
    assert.equal(single.output, [
        "Version     1.2.3-alpha.1+build.42",
        "Major       1",
        "Minor       2",
        "Patch       3",
        "Prerelease  alpha, 1",
        "Build       build, 42",
        "Channel     prerelease",
        "",
        "Next versions (pre: rc)",
        "  major       2.0.0",
        "  minor       1.3.0",
        "  patch       1.2.3",
        "  premajor    2.0.0-rc.0",
        "  preminor    1.3.0-rc.0",
        "  prepatch    1.2.4-rc.0",
        "  prerelease  1.2.3-rc.0"
    ].join("\n"));

    // Prerelease bump with matching identifier increments numeric part, and 1.0.0-rc.1 -> major 1.0.0
    const preMatch = run("1.0.0-rc.1", { pre: "rc" });
    assert.ok(preMatch.output.includes("  major       1.0.0\n"));
    assert.ok(preMatch.output.includes("  prerelease  1.0.0-rc.2"));
    assert.equal(devtools.semvInc(devtools.semvParseVersion("1.2.3"), "prerelease", "beta").full, "1.2.4-beta.0");

    // Precedence rules (SemVer 2.0.0 §11)
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-alpha"), devtools.semvParseVersion("1.0.0-alpha.1")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-alpha.1"), devtools.semvParseVersion("1.0.0-alpha.beta")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-alpha.beta"), devtools.semvParseVersion("1.0.0-beta")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-beta"), devtools.semvParseVersion("1.0.0-beta.2")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-beta.2"), devtools.semvParseVersion("1.0.0-beta.11")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-beta.11"), devtools.semvParseVersion("1.0.0-rc.1")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-rc.1"), devtools.semvParseVersion("1.0.0")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0-1"), devtools.semvParseVersion("1.0.0-alpha")), -1);
    assert.equal(devtools.semvCompare(devtools.semvParseVersion("1.0.0+build.1"), devtools.semvParseVersion("1.0.0+build.2")), 0);

    // Form 2: Two versions (vs, operator?, two lines)
    const vsCmp = run("1.2.3 vs 1.10.0");
    assert.equal(vsCmp.meta.order, "<");
    assert.equal(vsCmp.meta.diff, "minor");
    assert.equal(vsCmp.meta.higher, "1.10.0");
    assert.ok(vsCmp.output.includes("Order       1.2.3 < 1.10.0"));

    const qCmp = run("1.2.3 < 1.10.0 ?");
    assert.equal(qCmp.meta.result, true);
    assert.ok(qCmp.output.includes("Assertion   1.2.3 < 1.10.0  ->  true (✓)"));

    const twoLines = run("1.0.0\n2.0.0-rc.1");
    assert.equal(twoLines.meta.diff, "premajor");
    assert.equal(twoLines.meta.higher, "2.0.0-rc.1");

    const buildEq = run("1.0.0+a vs 1.0.0+b");
    assert.equal(buildEq.meta.order, "==");
    assert.equal(buildEq.meta.diff, "none");
    assert.ok(buildEq.output.includes("equal precedence"));

    // Form 3: Range expansions and satisfaction
    assert.equal(devtools.semvParseRange("^1.2.3").expanded, ">=1.2.3 <2.0.0-0");
    assert.equal(devtools.semvParseRange("^0.2.3").expanded, ">=0.2.3 <0.3.0-0");
    assert.equal(devtools.semvParseRange("^0.0.3").expanded, ">=0.0.3 <0.0.4-0");
    assert.equal(devtools.semvParseRange("~1.2").expanded, ">=1.2.0 <1.3.0-0");
    assert.equal(devtools.semvParseRange("1.x").expanded, ">=1.0.0 <2.0.0-0");
    assert.equal(devtools.semvParseRange("1.2.3 - 2.3.4").expanded, ">=1.2.3 <=2.3.4");
    assert.equal(devtools.semvParseRange(">=1.0.0 <2.0.0 || >=3").expanded, ">=1.0.0 <2.0.0 || >=3.0.0");

    const rangeStrict = run("^1.2.3\n1.2.2\n1.2.3\n1.2.4-alpha.1\n1.3.0\n1.5.2-rc.1\n1.9.0\n2.0.0-alpha.1\n2.0.0");
    assert.equal(rangeStrict.meta.satisfying, "3/8");
    assert.equal(rangeStrict.meta.min, "1.2.3");
    assert.equal(rangeStrict.meta.max, "1.9.0");
    assert.deepStrictEqual(Object.keys(rangeStrict.meta), ["satisfying", "min", "max"]);
    assert.ok(rangeStrict.output.includes("Expanded    >=1.2.3 <2.0.0-0"));
    assert.ok(rangeStrict.output.includes("✗  1.2.4-alpha.1  prerelease excluded"));
    assert.ok(rangeStrict.output.includes("✗  2.0.0-alpha.1  outside range"));
    assert.ok(rangeStrict.output.includes("Min         1.2.3\nMax         1.9.0"));

    const rangeWithPre = run("^1.2.3\n1.2.2\n1.2.3\n1.2.4-alpha.1\n1.3.0\n1.5.2-rc.1\n1.9.0\n2.0.0-alpha.1\n2.0.0", { includePrerelease: true });
    assert.equal(rangeWithPre.meta.satisfying, "5/8");
    assert.ok(rangeWithPre.output.includes("✓  1.2.4-alpha.1"));
    assert.ok(rangeWithPre.output.includes("✗  2.0.0-alpha.1  outside range"));

    // Prerelease matching same [major, minor, patch] rule without includePrerelease
    const sameMmp = run("^1.2.3-alpha.1\n1.2.3-alpha.2\n1.2.4-alpha.1\n1.2.3");
    assert.equal(sameMmp.meta.satisfying, "2/3");
    assert.ok(sameMmp.output.includes("✓  1.2.3-alpha.2"));
    assert.ok(sameMmp.output.includes("✗  1.2.4-alpha.1  prerelease excluded"));

    // Form 4: List sorting & invalid line reporting (compact 3-chip meta)
    const listAsc = run("1.10.0\n1.2.3\n1.2.3-alpha.1\nbad-ver\n2.0.0");
    assert.equal(listAsc.meta.count, "4/5");
    assert.equal(listAsc.meta.min, "1.2.3-alpha.1");
    assert.equal(listAsc.meta.max, "2.0.0");
    assert.ok(Object.keys(listAsc.meta).length <= 3);
    assert.ok(listAsc.output.includes("  1. 1.2.3-alpha.1\n  2. 1.2.3\n  3. 1.10.0\n  4. 2.0.0"));
    assert.ok(listAsc.output.includes("line 4: bad-ver"));

    const listDesc = run("1.2.3-x86\n1.2.3\n1.10.0", { order: "desc" });
    assert.equal(listDesc.meta.count, 3);
    assert.ok(Object.keys(listDesc.meta).length <= 3);
    assert.ok(listDesc.output.includes("Sorted (desc, 3 valid)"));
    assert.ok(listDesc.output.includes("  1. 1.10.0\n  2. 1.2.3\n  3. 1.2.3-x86"));

    // Loose / coerce mode vs strict errors
    assert.ok(run("v1.2").error);
    assert.ok(run("=1.2.3").error);
    assert.ok(run("1.2.3.4").error);
    assert.ok(run("01.02.03").error);
    assert.equal(run("v1.2", { loose: true }).meta.version, "1.2.0");
    assert.equal(run("=1.2.3", { loose: true }).meta.version, "1.2.3");
    assert.equal(run("1.2.3.4", { loose: true }).meta.version, "1.2.3");
    assert.equal(run("01.02.03-01", { loose: true }).meta.version, "1.2.3-1");

    // Invalid inputs / options return clear errors
    assert.ok(run("not-a-semver").error);
    assert.ok(run("1.2.3", { pre: "bad id!" }).error);
    assert.ok(run("^1.2.3 ||\n1.2.3").error);
    console.log("✓ Semver tool tests passed");
}
// @test-end semver_tool

// @test-begin commit_lint
{
    const plain = v => JSON.parse(JSON.stringify(v));

    // Empty and whitespace input
    assert.deepStrictEqual(plain(devtools.runTool("commit_lint", "")), { output: "" });
    assert.deepStrictEqual(plain(devtools.runTool("commit_lint", "   \n\t  ")), { output: "" });

    // 1. Valid simple feat commit
    const validFeat = devtools.runTool("commit_lint", "feat(auth): add OAuth2 PKCE flow");
    assert.deepStrictEqual(plain(validFeat.meta), { bump: "minor", errors: 0, warnings: 0 });
    assert.ok(validFeat.output.includes("Valid (0 errors, 0 warnings)"));
    assert.ok(validFeat.output.includes("Type         feat"));
    assert.ok(validFeat.output.includes("Scope        auth"));
    assert.ok(validFeat.output.includes("Breaking     no"));

    // 2. Valid fix with body, multi-line footer, Token #value, and BREAKING CHANGE footer
    const fullMsg = [
        "fix(api): normalize error payload",
        "",
        "Wrap upstream exceptions into JSON problem details.",
        "",
        "Refs #123",
        "Signed-off-by: Alice <alice@example.com>",
        "BREAKING CHANGE: error field renamed from msg to message",
        "  Update client parsers accordingly."
    ].join("\n");
    const fullRes = devtools.runTool("commit_lint", fullMsg, { version: "1.4.2" });
    assert.deepStrictEqual(plain(fullRes.meta), { bump: "major", errors: 0, warnings: 0 });
    assert.ok(fullRes.output.includes("major  (1.4.2 -> 2.0.0)"));
    assert.ok(fullRes.output.includes("yes (BREAKING CHANGE footer)"));
    assert.ok(fullRes.output.includes("Refs #123"));
    assert.ok(fullRes.output.includes("Update client parsers accordingly."));

    // 3. Bang breaking change on chore -> major bump, none without breaking
    const choreBang = devtools.runTool("commit_lint", "chore!: drop Node 18 support");
    assert.equal(choreBang.meta.bump, "major");
    assert.ok(choreBang.output.includes("yes (! in header)"));
    const docsOnly = devtools.runTool("commit_lint", "docs: update install guide");
    assert.deepStrictEqual(plain(docsOnly.meta), { bump: "none", errors: 0, warnings: 0 });
    const fixOnly = devtools.runTool("commit_lint", "fix: handle null token");
    assert.deepStrictEqual(plain(fixOnly.meta), { bump: "patch", errors: 0, warnings: 0 });

    // 4. Warnings: uppercase start, imperative mood, header length, maxHeader option
    const warnMsg = devtools.runTool("commit_lint", "feat(ui): Added a very long description that exceeds fifty characters easily", { maxHeader: 50 });
    assert.equal(warnMsg.meta.errors, 0);
    assert.equal(warnMsg.meta.warnings, 3);
    assert.ok(warnMsg.output.includes("⚠  Header exceeds 50 chars"));
    assert.ok(warnMsg.output.includes("⚠  Description starts with uppercase"));
    assert.ok(warnMsg.output.includes('⚠  Use imperative mood for "Added" → "add"'));

    // Imperative heuristic: "fixes", "updating", "fixed" warn, while valid "embed"/"process" pass
    assert.equal(devtools.runTool("commit_lint", "fix: fixes crash on startup").meta.warnings, 1);
    assert.equal(devtools.runTool("commit_lint", "chore: updating dependencies").meta.warnings, 1);
    assert.equal(devtools.runTool("commit_lint", "feat: embed icon font in binary").meta.warnings, 0);
    assert.equal(devtools.runTool("commit_lint", "refactor: process queued events in batch").meta.warnings, 0);

    // 5. Errors: uppercase type, unknown type, bad scope, missing space, trailing period, missing blank lines
    const badHeader = devtools.runTool("commit_lint", "Feat(my scope):add login.");
    assert.ok(badHeader.meta.errors >= 4);
    assert.ok(badHeader.output.includes('✗  Type "Feat" must be lowercase'));
    assert.ok(badHeader.output.includes("✗  Scope format"));
    assert.ok(badHeader.output.includes('✗  Separator ": " requires a space after ":"'));
    assert.ok(badHeader.output.includes("✗  Description must not end with a period"));

    const emptyScope = devtools.runTool("commit_lint", "fix(): handle empty");
    assert.equal(emptyScope.meta.errors, 1);
    assert.ok(emptyScope.output.includes("Scope cannot be empty"));

    const noColon = devtools.runTool("commit_lint", "just a commit message");
    assert.ok(noColon.meta.errors >= 3);
    assert.ok(noColon.output.includes('✗  Separator ": " missing'));

    const missingBlankBody = devtools.runTool("commit_lint", "feat: add dark mode\nBody without blank line.");
    assert.equal(missingBlankBody.meta.errors, 1);
    assert.ok(missingBlankBody.output.includes("✗  Blank line required after header"));

    const missingBlankFooter = devtools.runTool("commit_lint", "feat: add dark mode\n\nBody paragraph.\nRefs: #42");
    assert.equal(missingBlankFooter.meta.errors, 1);
    assert.ok(missingBlankFooter.output.includes("✗  Blank line required before footers"));
    assert.ok(missingBlankFooter.output.includes("Refs: #42"));

    // Footers in single commit should not falsely trigger multi-commit changelog mode
    const multiFooters = devtools.runTool("commit_lint", "fix: resolve race\n\nFixes: #10\nRefs: #20");
    assert.ok(multiFooters.output.includes("Mode         Single commit"));
    assert.equal(multiFooters.meta.errors, 0);

    // 6. Custom types option
    const customAllowed = devtools.runTool("commit_lint", "ops(k8s): scale replicas", { types: "feat, fix, ops" });
    assert.equal(customAllowed.meta.errors, 0);
    const customRejected = devtools.runTool("commit_lint", "docs: update readme", { types: "feat, fix" });
    assert.equal(customRejected.meta.errors, 1);
    assert.ok(customRejected.output.includes('✗  Unknown type "docs"'));

    // 7. Revert hash check
    const revertWithHash = devtools.runTool("commit_lint", "revert: undo cache layer\n\nThis reverts commit a1b2c3d.");
    assert.equal(revertWithHash.meta.warnings, 0);
    assert.ok(revertWithHash.output.includes("✓  Revert references commit hash (a1b2c3d)"));
    const revertNoHash = devtools.runTool("commit_lint", "revert: undo cache layer");
    assert.equal(revertNoHash.meta.warnings, 1);
    assert.ok(revertNoHash.output.includes("⚠  Revert should reference a commit hash"));

    // 8. Mode 2: git log --oneline -> Markdown changelog
    const gitLog = [
        "a3f91c2 feat(auth)!: require PKCE for public clients",
        "8b14e09 feat(ui): add dark palette",
        "1122334 feat(api): add batch endpoint",
        "4d2c7a1 fix(ui): fix tooltip clipping",
        "e901b54 perf(cache): memoize glyph lookups",
        "9a8b7c6 revert: drop experimental flag",
        "5e6f7a8 refactor(core): simplify state machine",
        "19f3a88 docs: document shortcuts",
        "3c4d5e6 test(auth): add PKCE unit tests",
        "7c02d11 ci: run QV4 parity check",
        "2b3c4d5 build: bump quickshell minimum version",
        "6f7a8b9 chore: clean up unused assets",
        "f558e20 Merge pull request #142 from dev/fix"
    ].join("\n");

    const changelog = devtools.runTool("commit_lint", gitLog, { version: "1.4.2" });
    assert.deepStrictEqual(plain(changelog.meta), { bump: "major", commits: 13, next: "2.0.0" });
    assert.equal(changelog.output, [
        "## Changelog",
        "",
        "Suggested bump: **major** · Next version: **2.0.0** (from 1.4.2, 13 commits)",
        "",
        "### ⚠ Breaking changes",
        "- **auth:** require PKCE for public clients (a3f91c2)",
        "",
        "### Features",
        "- **api:** add batch endpoint (1122334)",
        "- **ui:** add dark palette (8b14e09)",
        "",
        "### Bug fixes",
        "- **ui:** fix tooltip clipping (4d2c7a1)",
        "",
        "### Performance",
        "- **cache:** memoize glyph lookups (e901b54)",
        "",
        "### Reverts",
        "- drop experimental flag (9a8b7c6)",
        "",
        "### Refactoring",
        "- **core:** simplify state machine (5e6f7a8)",
        "",
        "### Documentation",
        "- document shortcuts (19f3a88)",
        "",
        "### Tests",
        "- **auth:** add PKCE unit tests (3c4d5e6)",
        "",
        "### Build & CI",
        "- run QV4 parity check (7c02d11)",
        "- bump quickshell minimum version (2b3c4d5)",
        "",
        "### Chores",
        "- clean up unused assets (6f7a8b9)",
        "",
        "### Other",
        "- Merge pull request #142 from dev/fix (f558e20)"
    ].join("\n"));

    // Multi-commit without hashes -> minor / patch / none bumps + version bump
    const minorLog = devtools.runTool("commit_lint", "feat(z): z feature\nfeat(a): a feature\nfix(b): b fix", { version: "v1.4.2" });
    assert.deepStrictEqual(plain(minorLog.meta), { bump: "minor", commits: 3, next: "v1.5.0" });
    assert.ok(minorLog.output.indexOf("**a:**") < minorLog.output.indexOf("**z:**"));

    const patchLog = devtools.runTool("commit_lint", "fix: a\ndocs: b", { version: "1.4.2" });
    assert.deepStrictEqual(plain(patchLog.meta), { bump: "patch", commits: 2, next: "1.4.3" });

    const noneLog = devtools.runTool("commit_lint", "docs: a\nchore: b", { version: "1.4.2" });
    assert.deepStrictEqual(plain(noneLog.meta), { bump: "none", commits: 2, next: "1.4.2" });

    // 9. Blank types option defaults to standard types, and long lines wrap aligned within pane width
    const blankTypesRes = devtools.runTool("commit_lint", "feat(ui): add compact mode", { types: "" });
    assert.equal(blankTypesRes.meta.errors, 0);

    const wrappedCheckRes = devtools.runTool("commit_lint", "unknown(bad scope): add feature");
    const wrappedLines = wrappedCheckRes.output.split("\n");
    assert.ok(wrappedLines.some(l => l.startsWith("     ")), "Long checklist item wraps with 5-space indent");
    assert.ok(wrappedLines.every(l => l.length <= 55), "Checklist and parsed lines stay within 55 chars");

    assert.ok(fullRes.output.includes("               problem details."), "Long body wraps aligned under value column");
    assert.ok(fullRes.output.split("\n").every(l => l.length <= 55), "Parsed fields wrap within 55 chars");

    const sampleLog = [
        "a3f91c2 feat(auth)!: require PKCE for OAuth2",
        "8b14e09 feat(search): add fuzzy tool matching",
        "4d2c7a1 fix(panel): stop tooltip edge clipping",
        "e901b54 perf(render): cache parsed icon glyphs",
        "19f3a88 docs: document DevTools shortcuts",
        "7c02d11 ci: run QV4 check on pull requests",
        "f558e20 Merge PR #142 from dev/fix-focus"
    ].join("\n");
    const sampleRes = devtools.runTool("commit_lint", sampleLog);
    assert.deepStrictEqual(plain(sampleRes.meta), { bump: "major", commits: 7, breaking: 1 });
    assert.ok(sampleRes.output.split("\n").every(l => l.length <= 54), "Sample changelog lines fit without wrapping");

    console.log("✓ Conventional Commits (commit_lint) tests passed");
}
// @test-end commit_lint

// @test-begin regex_explainer
{
    const rxePlain = x => JSON.parse(JSON.stringify(x));

    // Empty input
    assert.deepStrictEqual(rxePlain(devtools.runTool("regex_explainer", "   ")), { output: "" });

    // Basic bare pattern with exact output assertions
    const phone = devtools.runTool("regex_explainer", "^(\\d{3})-(\\d{4})$");
    assert.equal(phone.error, undefined);
    assert.deepStrictEqual(rxePlain(phone.meta), { groups: 2, flags: "none", warnings: 0 });
    assert.equal(phone.output, [
        "^               start of string",
        "(\\d{3})         capture group #1",
        "  \\d{3}         a digit (0-9), exactly 3 times",
        "-               literal \"-\"",
        "(\\d{4})         capture group #2",
        "  \\d{4}         a digit (0-9), exactly 4 times",
        "$               end of string",
        "",
        "Groups",
        "  #   Name  Fragment",
        "  #1  -     (\\d{3})",
        "  #2  -     (\\d{4})"
    ].join("\n"));

    // Literal with named group, lookahead, non-capturing group, and flags
    const email = devtools.runTool(
        "regex_explainer",
        "/^(?=[a-z0-9._+-]+@)(?<user>[\\w.+-]+)@(?<domain>(?:[a-z0-9-]+\\.)+[a-z]{2,})$/iu"
    );
    assert.equal(email.error, undefined);
    assert.deepStrictEqual(rxePlain(email.meta), { groups: 2, flags: "iu", warnings: 0 });
    assert.ok(email.output.includes("positive lookahead (followed by)"));
    assert.ok(email.output.includes("capture group #1 \"user\""));
    assert.ok(email.output.includes("capture group #2 \"domain\""));
    assert.ok(email.output.includes("i  ignoreCase"));
    assert.ok(email.output.includes("u  unicode"));
    assert.ok(email.output.includes("Named capture groups (?<name>...) require ES2018+"));
    // No false-positive catastrophic backtracking warning on non-overlapping subdomain loop
    assert.equal(email.output.includes("catastrophic"), false);

    // All flags (g, m, s, y, d) and lookbehind + modifier group + backreferences
    const modern = devtools.runTool(
        "regex_explainer",
        "/(?<=foo)(?i:bar)(a)\\1(?<x>z)\\k<x>/gmsyd"
    );
    assert.equal(modern.error, undefined);
    assert.equal(modern.meta.groups, 2);
    assert.equal(modern.meta.flags, "gmsyd");
    assert.ok(modern.output.includes("positive lookbehind (preceded by)"));
    assert.ok(modern.output.includes("modifier group (enable i)"));
    assert.ok(modern.output.includes("backreference to capture group #1"));
    assert.ok(modern.output.includes("backreference to group 'x'"));
    assert.ok(modern.output.includes("Lookbehind assertions"));
    assert.ok(modern.output.includes("Inline modifier groups"));
    assert.ok(modern.output.includes("Flag 'd' (hasIndices)"));

    // All escapes: \d \D \w \W \s \S \b \B \n \t \r \f \v \0 \cA \x41 \u0042 \u{1F600} \p{L} \P{N}
    const escapes = devtools.runTool(
        "regex_explainer",
        "/\\d\\D\\w\\W\\s\\S\\b\\B\\n\\t\\r\\f\\v\\0\\cA\\x41\\u0042\\u{1F600}\\p{L}\\P{N}/u"
    );
    assert.equal(escapes.error, undefined);
    assert.ok(escapes.output.includes("a digit (0-9)"));
    assert.ok(escapes.output.includes("a non-digit"));
    assert.ok(escapes.output.includes("word boundary"));
    assert.ok(escapes.output.includes("non-word boundary"));
    assert.ok(escapes.output.includes("control character Ctrl+A"));
    assert.ok(escapes.output.includes("hex character U+0041"));
    assert.ok(escapes.output.includes("Unicode character U+0042"));
    assert.ok(escapes.output.includes("Unicode code point U+1F600"));
    assert.ok(escapes.output.includes("Unicode property L"));
    assert.ok(escapes.output.includes("not Unicode property N"));

    // ES2024 v-flag set operations (intersection, subtraction, string literal set)
    const vMode = devtools.runTool("regex_explainer", "/[[\\p{Letter}&&\\p{Script=Greek}][\\w--[0-9_]]\\q{ab|cd}]/v");
    assert.equal(vMode.error, undefined);
    assert.equal(vMode.meta.flags, "v");
    assert.ok(vMode.output.includes("intersection (&&)"));
    assert.ok(vMode.output.includes("subtraction (--)"));
    assert.ok(vMode.output.includes("string literal set {\"ab\", \"cd\"}"));
    assert.ok(vMode.output.includes("Flag 'v' (unicodeSets) requires ES2024+"));

    // Quantifiers: lazy, ranges, open-ended
    const quants = devtools.runTool("regex_explainer", "a*?b+?c??d{2,}?e{1,4}");
    assert.equal(quants.error, undefined);
    assert.ok(quants.output.includes("0 or more times, lazy"));
    assert.ok(quants.output.includes("1 or more times, lazy"));
    assert.ok(quants.output.includes("optional (0 or 1 time), lazy"));
    assert.ok(quants.output.includes("2 or more times, lazy"));
    assert.ok(quants.output.includes("1 to 4 times"));

    // Warnings: catastrophic backtracking (nested quantifiers & overlapping alternation), unescaped dot, useless escape, empty alt
    const redos1 = devtools.runTool("regex_explainer", "(a+)+");
    assert.ok(redos1.output.includes("catastrophic backtracking"));

    const redos2 = devtools.runTool("regex_explainer", "(\\w*)*");
    assert.ok(redos2.output.includes("catastrophic backtracking"));

    const redosAlt = devtools.runTool("regex_explainer", "(a|\\w)+");
    assert.ok(redosAlt.output.includes("Overlapping alternation branches"));

    const domainDot = devtools.runTool("regex_explainer", "example.com");
    assert.ok(domainDot.output.includes("Unescaped '.' in 'example.com'"));

    const uselessEsc = devtools.runTool("regex_explainer", "\\a");
    assert.ok(uselessEsc.output.includes("Useless escape '\\a'"));

    const emptyAlt = devtools.runTool("regex_explainer", "(foo|)");
    assert.ok(emptyAlt.output.includes("Empty alternative"));

    // Options: view="tree" and showSpans=true
    const treeOnly = devtools.runTool("regex_explainer", "/(a)/g", { view: "tree", showSpans: true });
    assert.equal(treeOnly.output.includes("Groups"), false);
    assert.equal(treeOnly.output.includes("Flags"), false);
    assert.ok(treeOnly.output.includes("[0:3]"));

    const summaryOnly = devtools.runTool("regex_explainer", "/(a)/g", { view: "summary" });
    assert.ok(summaryOnly.output.includes("Flags"));
    assert.ok(summaryOnly.output.includes("Groups"));
    assert.equal(summaryOnly.output.includes("capture group #1"), false);

    // Single-line errors with column and inline marker (never breaks proportional UI / footer)
    const errMinMax = devtools.runTool("regex_explainer", "a{5,2}");
    assert.ok(errMinMax.error.includes("column 2"));
    assert.ok(!errMinMax.error.includes("\n"));
    assert.ok(errMinMax.error.includes("▸{5,2}"));

    const errUnclosed = devtools.runTool("regex_explainer", "^(\\d{3");
    assert.ok(errUnclosed.error.includes("column 2"));
    assert.ok(!errUnclosed.error.includes("\n"));
    assert.ok(errUnclosed.error.includes("^▸(\\d{3"));

    const errBadFlag = devtools.runTool("regex_explainer", "/abc/z");
    assert.ok(errBadFlag.error.includes("Unknown regex flag 'z'"));
    assert.ok(errBadFlag.error.includes("column 6"));

    const errUV = devtools.runTool("regex_explainer", "/abc/uv");
    assert.ok(errUV.error.includes("cannot be combined"));

    const errRange = devtools.runTool("regex_explainer", "[z-a]");
    assert.ok(errRange.error.includes("out of order"));

    // Page-width formatting: word-wrapped lines <= 58 cols, bounded padWidth, non-breaking (col N)
    const sampleOut = devtools.runTool(
        "regex_explainer",
        "/^(?<user>[\\w.-]+)@(?<host>(?:[a-z0-9-]+\\.)+[a-z]{2,})$/iu"
    );
    assert.equal(sampleOut.error, undefined);
    for (const line of sampleOut.output.split("\n")) {
        assert.ok(line.length <= 58, "Expected line <= 58 chars, got " + line.length + ": " + line);
    }

    const warnOut = devtools.runTool("regex_explainer", "(a+)+|example.com|\\a|(foo|)");
    assert.equal(warnOut.error, undefined);
    for (const line of warnOut.output.split("\n")) {
        assert.ok(line.length <= 58, "Expected warning line <= 58 chars, got " + line.length + ": " + line);
    }
    assert.ok(warnOut.output.includes("(col 19)"));
    assert.ok(!warnOut.output.includes("(col 1\n"));

    console.log("✓ Regex explainer tests passed");
}
// @test-end regex_explainer

// @test-begin log_formatter
{
    // Empty & ANSI-only input
    assert.deepStrictEqual(JSON.parse(JSON.stringify(devtools.runTool("log_formatter", ""))), { output: "" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(devtools.runTool("log_formatter", "   \n\t  "))), { output: "" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(devtools.runTool("log_formatter", "\x1b[33m\x1b[0m  "))), { output: "" });

    // Error on invalid level option
    const badOpt = devtools.runTool("log_formatter", "INFO hello", { level: "verbose" });
    assert.ok(badOpt.error);
    assert.equal(badOpt.output, "");

    // ANSI stripping, timestamps (ISO, HH:MM:SS, syslog, epoch ms), level forms, continuation lines, collapse
    const mixed = [
        "\x1b[36m2026-11-24T15:04:50.100Z\x1b[0m INFO  [server] Listening",
        "15:04:51.250 [debug] cache check",
        "  continuation detail",
        "Nov 24 15:04:52 myhost app[12]: warning: slow query",
        "[1732460693500] warn: myhost app[12]: slow query",
        "2026-11-24T15:04:54.000Z trace: enter loop"
    ].join("\n");
    const resMixed = devtools.runTool("log_formatter", mixed);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resMixed.meta)), { errors: 0, warnings: 2, lines: 6 });
    assert.ok(resMixed.output.includes("ERR 0 · WARN 2 · INFO 1 · DBG 2 · TRC 1"));
    assert.ok(resMixed.output.includes("First err  none"));
    assert.ok(resMixed.output.includes("WARN  myhost app[12]: slow query ×2"));
    assert.ok(resMixed.output.includes("DBG   cache check\nDBG     continuation detail"));
    assert.ok(!resMixed.output.includes("\x1b["));

    // stripTimestamps: false keeps timestamps; collapse: false keeps repeats separate
    const resKeepTs = devtools.runTool("log_formatter", "15:04:50 WARN retry\n15:04:51 WARN retry", {
        stripTimestamps: false,
        collapse: false
    });
    assert.ok(resKeepTs.output.includes("WARN  15:04:50 retry\nWARN  15:04:51 retry"));
    assert.ok(resKeepTs.output.includes("15:04:50 -> 15:04:51 (1s)"));

    // Python traceback grouped with preceding error + framesOnly
    const pyLog = [
        "2026-11-24 15:04:50 ERROR worker: Sync failed",
        "Traceback (most recent call last):",
        "  File \"/usr/lib/python3.12/site-packages/celery/trace.py\", line 477, in trace_task",
        "    run()",
        "  File \"/app/jobs/sync.py\", line 83, in run_sync",
        "    raise ValueError(\"missing tenant_id\")",
        "ValueError: missing tenant_id"
    ].join("\n");
    const resPy = devtools.runTool("log_formatter", pyLog);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resPy.meta)), { errors: 1, warnings: 0, lines: 7 });
    assert.ok(resPy.output.includes("1. ValueError: missing tenant_id  @ /app/jobs/sync.py:83"));
    assert.ok(resPy.output.includes("ERR   worker: Sync failed\n        Traceback (most recent call last):"));

    const resPyFramesOnly = devtools.runTool("log_formatter", pyLog, { framesOnly: true });
    assert.ok(!resPyFramesOnly.output.includes("celery/trace.py"));
    assert.ok(resPyFramesOnly.output.includes("File \"/app/jobs/sync.py\", line 83, in run_sync"));

    // JavaScript stack trace
    const jsTrace = [
        "TypeError: Cannot read properties of null",
        "    at processTicks (node:internal/process/task_queues:95:5)",
        "    at Layer.handle (/srv/node_modules/express/lib/router/layer.js:95:5)",
        "    at getUser (/srv/src/users.js:28:19)"
    ].join("\n");
    const resJs = devtools.runTool("log_formatter", jsTrace, { framesOnly: true });
    assert.equal(resJs.meta.errors, 1);
    assert.ok(resJs.output.includes("1. TypeError: Cannot read properties of null  @ /srv/src/users.js:28"));
    assert.ok(!resJs.output.includes("node_modules"));

    // Java/Kotlin stack trace with Caused by
    const javaTrace = [
        "2026-11-24T15:04:50Z ERROR [http] Request failed",
        "java.lang.IllegalStateException: Order closed",
        "\tat org.springframework.web.Servlet.service(Servlet.java:100)",
        "\tat com.acme.OrderService.cancel(OrderService.kt:84)",
        "Caused by: java.sql.SQLException: Deadlock",
        "\tat com.acme.Repo.save(Repo.java:51)",
        "\t... 12 more"
    ].join("\n");
    const resJava = devtools.runTool("log_formatter", javaTrace);
    assert.equal(resJava.meta.errors, 1);
    assert.ok(resJava.output.includes("1. java.lang.IllegalStateException: Order closed  @ OrderService.kt:84"));

    // Rust panic
    const rustTrace = [
        "thread 'main' panicked at src/x.rs:12:5:",
        "called `Option::unwrap()` on a `None` value",
        "stack backtrace:",
        "   0: std::panicking::begin_panic",
        "             at /rustc/abc/library/std/src/panicking.rs:600:5",
        "   1: my_app::run",
        "             at ./src/x.rs:12:5"
    ].join("\n");
    const resRust = devtools.runTool("log_formatter", rustTrace);
    assert.equal(resRust.meta.errors, 1);
    assert.ok(resRust.output.includes("1. Panic: called `Option::unwrap()` on a `None` value  @ src/x.rs:12"));

    // Go panic + goroutine
    const goTrace = [
        "panic: runtime error: invalid memory address",
        "",
        "goroutine 1 [running]:",
        "runtime/debug.Stack()",
        "\t/usr/local/go/src/runtime/debug/stack.go:24 +0x5e",
        "main.handle()",
        "\t/app/cmd/main.go:57 +0x12a"
    ].join("\n");
    const resGo = devtools.runTool("log_formatter", goTrace);
    assert.equal(resGo.meta.errors, 1);
    assert.ok(resGo.output.includes("1. Panic: runtime error: invalid memory address  @ /app/cmd/main.go:57"));

    // QML / Quickshell warning with ANSI + level filter
    const qmlLog = [
        "15:04:50 INFO Booting",
        "\x1b[33m15:04:51 WARN quickshell: file:///home/user/.config/quickshell/ii/Bar.qml[12:5]: ReferenceError: foo is not defined\x1b[0m",
        "15:04:52 ERROR Fatal crash"
    ].join("\n");
    const resQml = devtools.runTool("log_formatter", qmlLog, { level: "error" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resQml.meta)), { errors: 1, warnings: 1, lines: 3 });
    assert.ok(resQml.output.includes("1. ReferenceError: foo is not defined  @ /home/user/.config/quickshell/ii/Bar.qml:12"));
    assert.ok(!resQml.output.includes("INFO  Booting"));
    assert.ok(!resQml.output.includes("WARN  quickshell"));
    assert.ok(resQml.output.includes("ERR   Fatal crash"));

    // Long QML path truncation in trace summary + syslog/ISO year anchoring
    const longQml = "file:///home/user/.config/quickshell/ii/modules/bar/ClockWidget.qml:77:5: TypeError: null";
    assert.ok(devtools.runTool("log_formatter", longQml).output.includes("1. TypeError: null  @ .../bar/ClockWidget.qml:77"));
    const syslogIso = "Nov 24 15:04:50 host app[1]: INFO start\n2026-11-24T15:04:52Z INFO ready";
    assert.ok(devtools.runTool("log_formatter", syslogIso).output.includes("Nov 24 15:04:50 -> 2026-11-24T15:04:52Z (2s)"));

    // Level filter with zero matching lines
    const emptyFilter = devtools.runTool("log_formatter", "INFO all good", { level: "error" });
    assert.ok(emptyFilter.output.includes("(No entries matching level >= ERR)"));

    // Realistic mixed log: WARN lines immediately followed by Python traceback + unindented non-trace line
    const warnThenPyTrace = [
        "15:04:50 WARN quickshell: GlobalShortcut will not work.",
        "15:04:51 WARN quickshell: GlobalShortcut will not work.",
        "15:04:52 WARN scene: Read of states.json failed: File does not exist.",
        "Traceback (most recent call last):",
        "  File \"/usr/lib/python3/site-packages/urllib3/pool.py\", line 90, in urlopen",
        "    return conn.urlopen()",
        "  File \"/app/fetch.py\", line 12, in fetch",
        "    raise ValueError(\"bad url\")",
        "ValueError: bad url",
        "Server still alive"
    ].join("\n");
    const resWarnPy = devtools.runTool("log_formatter", warnThenPyTrace);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resWarnPy.meta)), { errors: 1, warnings: 3, lines: 10 });
    assert.ok(resWarnPy.output.includes("ERR 1 · WARN 3 · INFO 1"));
    assert.ok(resWarnPy.output.includes("First err  ValueError: bad url"));
    assert.ok(resWarnPy.output.includes("1. ValueError: bad url  @ /app/fetch.py:12"));
    assert.ok(resWarnPy.output.includes("WARN  scene: Read of states.json failed: File does not exist.\nERR   ValueError: bad url\n        Traceback (most recent call last):"));
    assert.ok(resWarnPy.output.includes("        ValueError: bad url") === false);
    assert.ok(resWarnPy.output.includes("INFO  Server still alive"));

    // JS stack (Uncaught and Error:) after INFO/WARN lines + unindented non-trace line ends trace
    const infoThenJsUncaught = [
        "15:04:50 INFO handling /api/sync",
        "Uncaught TypeError: bad arg",
        "    at node:internal/process/task_queues:95:5",
        "    at handler (/app/server.js:42:11)",
        "Request finished"
    ].join("\n");
    const resInfoJs = devtools.runTool("log_formatter", infoThenJsUncaught);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resInfoJs.meta)), { errors: 1, warnings: 0, lines: 5 });
    assert.ok(resInfoJs.output.includes("First err  Uncaught TypeError: bad arg"));
    assert.ok(resInfoJs.output.includes("1. Uncaught TypeError: bad arg  @ /app/server.js:42"));
    assert.ok(resInfoJs.output.includes("INFO  Request finished"));

    const warnThenJsError = [
        "15:04:50 WARN pool low",
        "Error: connect ECONNREFUSED",
        "    at connect (/app/db.js:18:5)",
        "15:04:51 WARN retrying"
    ].join("\n");
    const resWarnJs = devtools.runTool("log_formatter", warnThenJsError);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resWarnJs.meta)), { errors: 1, warnings: 2, lines: 4 });
    assert.ok(resWarnJs.output.includes("First err  Error: connect ECONNREFUSED"));
    assert.ok(resWarnJs.output.includes("1. Error: connect ECONNREFUSED  @ /app/db.js:18"));

    // Go goroutine, Java Exception in thread, and QML ReferenceError after WARN/INFO must start NEW ERROR entries
    const warnThenGoAndJava = [
        "WARN cache miss",
        "goroutine 7 [running]:",
        "main.serve()",
        "\t/app/srv.go:31 +0x44",
        "INFO next worker",
        "Exception in thread \"main\" java.lang.NullPointerException: null ctx",
        "\tat com.acme.App.main(App.java:14)",
        "qml: ReferenceError: badge is not defined"
    ].join("\n");
    const resGoJavaQml = devtools.runTool("log_formatter", warnThenGoAndJava);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resGoJavaQml.meta)), { errors: 3, warnings: 1, lines: 8 });
    assert.ok(resGoJavaQml.output.includes("First err  goroutine 7 [running]:"));
    assert.ok(resGoJavaQml.output.includes("ERR   qml: ReferenceError: badge is not defined"));

    // Truncated Python trace ended by unindented non-trace line
    const truncPy = [
        "Traceback (most recent call last):",
        "  File \"/app/run.py\", line 5, in main",
        "    boot()",
        "Starting worker"
    ].join("\n");
    const resTruncPy = devtools.runTool("log_formatter", truncPy);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resTruncPy.meta)), { errors: 1, warnings: 0, lines: 4 });
    assert.ok(resTruncPy.output.includes("INFO  Starting worker"));

    console.log("✓ Log & Stack Trace Reader tests passed");
}
// @test-end log_formatter

// @test-begin markdown_table
{
    // Empty / whitespace input
    assert.deepStrictEqual(JSON.parse(JSON.stringify(devtools.runTool("markdown_table", ""))), { output: "" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(devtools.runTool("markdown_table", "   \n\t  "))), { output: "" });

    // Display width: ASCII, combining marks, CJK, emoji
    assert.equal(devtools.mdtDisplayWidth("abc"), 3);
    assert.equal(devtools.mdtDisplayWidth("Café"), 4);
    assert.equal(devtools.mdtDisplayWidth("Cafe\u0301"), 4);
    assert.equal(devtools.mdtDisplayWidth("日本語"), 6);
    assert.equal(devtools.mdtDisplayWidth("🚀"), 2);
    assert.equal(devtools.mdtDisplayWidth("🚀 Yūki"), 7);

    // Registry sampleInput: quoted comma, accented Latin (no emoji misalignment in Qt), auto numeric align
    const sampleInput = 'Name,Role,Score\n"Silva, José",Engineer,98.5\nAda Lovelace,Mathematician,100\nYūki Tanaka,Designer,94.2';
    const sampleRes = devtools.runTool("markdown_table", sampleInput);
    assert.equal(sampleRes.error, undefined);
    assert.equal(sampleRes.output, [
        "| Name         | Role          | Score |",
        "| :----------- | :------------ | ----: |",
        "| Silva, José  | Engineer      |  98.5 |",
        "| Ada Lovelace | Mathematician |   100 |",
        "| Yūki Tanaka  | Designer      |  94.2 |"
    ].join("\n"));
    assert.deepStrictEqual(JSON.parse(JSON.stringify(sampleRes.meta)), { size: "3×3", from: "CSV" });

    // CSV with quoted comma, numbers (auto right-align), accented + emoji
    const csvRes = devtools.runTool(
        "markdown_table",
        'Name,Role,Score\n"Silva, José",Engineer,98.5\nAda Lovelace,Mathematician,100\n"🚀 Yūki",Designer,94.2'
    );
    assert.equal(csvRes.error, undefined);
    assert.equal(csvRes.output, [
        "| Name         | Role          | Score |",
        "| :----------- | :------------ | ----: |",
        "| Silva, José  | Engineer      |  98.5 |",
        "| Ada Lovelace | Mathematician |   100 |",
        "| 🚀 Yūki      | Designer      |  94.2 |"
    ].join("\n"));
    assert.deepStrictEqual(JSON.parse(JSON.stringify(csvRes.meta)), { size: "3×3", from: "CSV" });

    // CJK width alignment in Markdown output
    const cjkRes = devtools.runTool("markdown_table", "Name,City\n田中,東京\nAda,London");
    assert.equal(cjkRes.output, [
        "| Name | City   |",
        "| :--- | :----- |",
        "| 田中 | 東京   |",
        "| Ada  | London |"
    ].join("\n"));

    // Markdown input (no outer pipes) with escaped pipes and multiline cells -> CSV & Markdown
    const mdNoOuter = "Col A | Col B\n--- | :---:\nfoo \\| bar | line1<br>line2";
    const mdToMd = devtools.runTool("markdown_table", mdNoOuter, { align: "center" });
    assert.equal(mdToMd.meta.from, "Markdown");
    assert.equal(mdToMd.output, [
        "|   Col A    |     Col B      |",
        "| :--------: | :------------: |",
        "| foo \\| bar | line1<br>line2 |"
    ].join("\n"));
    const mdToCsv = devtools.runTool("markdown_table", mdNoOuter, { to: "csv" });
    assert.equal(mdToCsv.output, 'Col A,Col B\nfoo | bar,"line1\nline2"');

    // TSV input -> Markdown compact mode
    const tsvInput = "Item\tQty\tPrice\nPen\t2\t$1.50\nBook\t10\t$12.00";
    const tsvCompact = devtools.runTool("markdown_table", tsvInput, { compact: true });
    assert.equal(tsvCompact.meta.from, "TSV");
    assert.equal(tsvCompact.output, [
        "|Item|Qty|Price|",
        "|:-|-:|-:|",
        "|Pen|2|$1.50|",
        "|Book|10|$12.00|"
    ].join("\n"));

    // JSON array of objects (union of keys, nested values compact JSON) -> Markdown & HTML
    const jsonInput = JSON.stringify([
        { id: 1, name: "Ada", tags: ["math", "code"] },
        { id: 2, name: "Linus", meta: { os: "Linux" } }
    ]);
    const jsonToMd = devtools.runTool("markdown_table", jsonInput);
    assert.equal(jsonToMd.meta.from, "JSON");
    assert.deepStrictEqual(JSON.parse(JSON.stringify(jsonToMd.meta)), { size: "2×4", from: "JSON" });
    assert.equal(jsonToMd.output, [
        "|   id | name  | tags            | meta           |",
        "| ---: | :---- | :-------------- | :------------- |",
        '|    1 | Ada   | ["math","code"] |                |',
        '|    2 | Linus |                 | {"os":"Linux"} |'
    ].join("\n"));

    const jsonToHtml = devtools.runTool("markdown_table", '[{"Name":"A & B","Count":5}]', { to: "html" });
    assert.equal(jsonToHtml.output, [
        "<table>",
        "  <thead>",
        "    <tr>",
        "      <th>Name</th>",
        '      <th style="text-align: right">Count</th>',
        "    </tr>",
        "  </thead>",
        "  <tbody>",
        "    <tr>",
        "      <td>A &amp; B</td>",
        '      <td style="text-align: right">5</td>',
        "    </tr>",
        "  </tbody>",
        "</table>"
    ].join("\n"));

    // Whitespace-aligned CLI output (docker ps style with empty cell & comma in PORTS) -> TSV & JSON
    const dockerInput = [
        "CONTAINER ID   IMAGE          STATUS        PORTS                NAMES",
        "a1b2c3d4e5f6   nginx:latest   Up 2 hours                         web",
        "f6e5d4c3b2a1   redis:7        Up 5 mins     80/tcp, 443/tcp      cache"
    ].join("\n");
    const spacesToJson = devtools.runTool("markdown_table", dockerInput, { to: "json" });
    assert.equal(spacesToJson.meta.from, "Spaces");
    assert.deepStrictEqual(JSON.parse(spacesToJson.output), [
        { "CONTAINER ID": "a1b2c3d4e5f6", IMAGE: "nginx:latest", STATUS: "Up 2 hours", PORTS: "", NAMES: "web" },
        { "CONTAINER ID": "f6e5d4c3b2a1", IMAGE: "redis:7", STATUS: "Up 5 mins", PORTS: "80/tcp, 443/tcp", NAMES: "cache" }
    ]);

    // Header = false generates Column 1..n
    const noHeaderRes = devtools.runTool("markdown_table", "Ada,10\nGrace,20", { header: false });
    assert.equal(noHeaderRes.output, [
        "| Column 1 | Column 2 |",
        "| :------- | -------: |",
        "| Ada      |       10 |",
        "| Grace    |       20 |"
    ].join("\n"));
    assert.equal(noHeaderRes.meta.size, "2×2");

    // Ragged rows padded with empty cells and reported in meta.warning
    const raggedRes = devtools.runTool("markdown_table", "A,B,C\n1\n2,3", { to: "markdown" });
    assert.equal(raggedRes.meta.warning, "2 ragged rows padded");
    assert.equal(raggedRes.output, [
        "|    A |    B | C    |",
        "| ---: | ---: | :--- |",
        "|    1 |      |      |",
        "|    2 |    3 |      |"
    ].join("\n"));

    // Error cases
    const badJson = devtools.runTool("markdown_table", "{not valid", { from: "json" });
    assert.equal(badJson.error, 'Invalid JSON: expected a JSON array of objects, e.g. [{"name": "Ada"}].');
    const notArrayJson = devtools.runTool("markdown_table", '{"a": 1}', { from: "json" });
    assert.ok(notArrayJson.error && notArrayJson.error.includes("JSON array of objects"));
    const unclosedCsv = devtools.runTool("markdown_table", 'a,b\n"unclosed,2', { from: "csv" });
    assert.equal(unclosedCsv.error, "Unclosed quote in CSV input.");
    const emptyMd = devtools.runTool("markdown_table", "| --- | --- |", { from: "markdown" });
    assert.ok(emptyMd.error && emptyMd.error.includes("Markdown table"));

    console.log("✓ Markdown table tests passed");
}
// @test-end markdown_table

// @test-begin hypr_keybind
{
    const plain = value => JSON.parse(JSON.stringify(value));

    // Empty and whitespace input
    assert.deepStrictEqual(plain(devtools.toolHyprKeybind("")), { output: "" });
    assert.deepStrictEqual(plain(devtools.toolHyprKeybind("   \n\t  ")), { output: "" });

    // Error on invalid / unparseable input or invalid option
    assert.ok(devtools.toolHyprKeybind("not a keybind at all").error);
    assert.ok(devtools.toolHyprKeybind("# comment only\n-- lua comment").error);
    assert.ok(devtools.toolHyprKeybind("Super+Q: killactive", { to: "xml" }).error);

    // Mixed notations -> Lua (repo format)
    const mixed = [
        "bind = SUPER SHIFT, T, exec, kitty",
        "bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+",
        "Super+Q: killactive",
        "Ctrl+Alt+Delete → exit",
        "hl.bind(\"SUPER + F\", hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" }), { description = \"Window: Fullscreen\" })",
        "bind = SUPER, B, movefocsu, l"
    ].join("\n");

    const luaRes = devtools.toolHyprKeybind(mixed, { to: "lua" });
    assert.ok(!luaRes.error);
    assert.equal(luaRes.meta.binds, 6);
    assert.equal(luaRes.meta.warnings, 1);
    assert.equal(luaRes.output, [
        "hl.bind(\"SUPER + SHIFT + T\", hl.dsp.exec_cmd(\"kitty\"))",
        "hl.bind(\"XF86AudioRaiseVolume\", hl.dsp.exec_cmd(\"wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+\"), { repeating = true, locked = true })",
        "hl.bind(\"SUPER + Q\", hl.dsp.window.close())",
        "hl.bind(\"CTRL + ALT + Delete\", hl.dsp.exit())",
        "hl.bind(\"SUPER + F\", hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" }), { description = \"Window: Fullscreen\" })",
        "-- hl.bind(\"SUPER + B\", \"movefocsu\", \"l\")",
        "",
        "-- [!] Line 6: Unknown dispatcher \"movefocsu\" (did you mean \"movefocus\"?)"
    ].join("\n"));

    // Modifier normalization & ordering (SUPER CTRL ALT SHIFT) + keysyms
    const modNorm = devtools.toolHyprKeybind(
        "shift+alt+control+win+return: exec, alacritty\nmod4+mod1+esc -> workspace 1\nsuper+space: layoutmsg splitratio +0.1",
        { to: "conf" }
    );
    assert.equal(modNorm.meta.binds, 3);
    assert.equal(modNorm.meta.warnings, 0);
    assert.equal(modNorm.output, [
        "bind = SUPER CTRL ALT SHIFT, Return, exec, alacritty",
        "bind = SUPER ALT, Escape, workspace, 1",
        "bind = SUPER, space, layoutmsg, splitratio +0.1"
    ].join("\n"));

    // Table output alignment and columns
    const tableRes = devtools.toolHyprKeybind(
        "bind = SUPER, Q, killactive # Close window\nbindm = SUPER, mouse:272, movewindow",
        { to: "table" }
    );
    assert.equal(tableRes.meta.binds, 2);
    assert.equal(tableRes.meta.warnings, 0);
    assert.ok(tableRes.output.includes("Keys               Flags  Dispatcher  Argument  Description"));
    assert.ok(tableRes.output.includes("SUPER + Q          -      killactive  -         Close window"));
    assert.ok(tableRes.output.includes("SUPER + mouse:272  mouse  movewindow  -         -"));

    // Submaps, multi-line Lua, bindd, and unbind clearing duplicate detection
    const submapLua = [
        "hl.bind(\"SUPER + Q\", hl.dsp.window.close())",
        "hl.unbind(\"SUPER + Q\")",
        "hl.bind(\"SUPER + Q\", hl.dsp.exec_cmd(\"kitty\"))",
        "hl.define_submap(\"resize\", function()",
        "    hl.bind(\"Left\", hl.dsp.window.resize({ x = -10, y = 0 }),",
        "        { repeating = true })",
        "end)"
    ].join("\n");
    const submapConf = devtools.toolHyprKeybind(submapLua, { to: "conf" });
    assert.equal(submapConf.meta.binds, 4);
    assert.equal(submapConf.meta.warnings, 0);
    assert.equal(submapConf.output, [
        "bind = SUPER, Q, killactive",
        "unbind = SUPER, Q",
        "bind = SUPER, Q, exec, kitty",
        "submap = resize",
        "binde = , Left, resizeactive, -10 0",
        "submap = reset"
    ].join("\n"));

    // Table omits empty optional Description/Flags columns when unused
    const compactTable = devtools.toolHyprKeybind("bind = SUPER, Q, killactive", { to: "table" });
    assert.ok(compactTable.output.includes("Keys       Dispatcher  Argument"));
    assert.ok(!compactTable.output.includes("Description"));

    // Every emitted hl.dsp.<name> must belong to the real Hyprland hl.dsp allowlist
    const ALLOWED_HL_DSP = new Set([
        "cursor.move", "cursor.move_to_corner", "dpms", "event", "exec_cmd", "exec_raw",
        "exit", "focus", "force_idle", "force_renderer_reload", "global",
        "group.active", "group.lock", "group.lock_active", "group.move_window",
        "group.next", "group.prev", "group.toggle", "layout", "no_op", "pass",
        "release_input_capture", "send_key_state", "send_shortcut", "submap",
        "window.alter_zorder", "window.bring_to_top", "window.center", "window.clear_tags",
        "window.close", "window.cycle_next", "window.deny_from_group", "window.drag",
        "window.float", "window.fullscreen", "window.fullscreen_state", "window.kill",
        "window.move", "window.pin", "window.pseudo", "window.resize", "window.set_prop",
        "window.signal", "window.swap", "window.tag", "window.toggle_swallow",
        "workspace.change_id", "workspace.move", "workspace.rename",
        "workspace.swap_monitors", "workspace.toggle_special"
    ]);
    assert.deepStrictEqual(
        Object.keys(devtools.HKB_VALID_LUA_DSP).sort(),
        Array.from(ALLOWED_HL_DSP).sort()
    );

    const sampleArgsByDispatcher = {
        exec: "foot",
        execr: "foot",
        pass: "class:obs",
        sendshortcut: "SUPER, A, class:obs",
        sendkeystate: "SUPER, A, down, class:obs",
        killactive: "",
        forcekillactive: "",
        closewindow: "class:kitty",
        killwindow: "class:kitty",
        signal: "9",
        signalwindow: "class:kitty,9",
        workspace: "1",
        movetoworkspace: "2,class:kitty",
        movetoworkspacesilent: "3",
        togglefloating: "",
        setfloating: "class:kitty",
        settiled: "",
        fullscreen: "0",
        fullscreenstate: "0 2",
        dpms: "on",
        pin: "",
        movefocus: "l",
        movewindow: "r",
        resizewindow: "",
        swapwindow: "u",
        centerwindow: "1",
        resizeactive: "10 -10",
        moveactive: "exact 10 20",
        resizewindowpixel: "exact 640 480,class:kitty",
        movewindowpixel: "10 10,class:kitty",
        cyclenext: "prev",
        swapnext: "prev",
        focuswindow: "class:kitty",
        focusmonitor: "DP-1",
        splitratio: "+0.1",
        toggleopaque: "",
        movecursortocorner: "0",
        movecursor: "100 200",
        renameworkspace: "1 web",
        exit: "",
        forcerendererreload: "",
        focuscurrentorlast: "",
        focusurgentorlast: "",
        togglespecialworkspace: "scratch",
        movecurrentworkspacetomonitor: "DP-1",
        focusworkspaceoncurrentmonitor: "2",
        moveworkspacetomonitor: "2 DP-1",
        swapactiveworkspaces: "DP-1 HDMI-A-1",
        bringactivetotop: "",
        alterzorder: "top,class:kitty",
        togglesplit: "",
        pseudo: "",
        swapsplit: "",
        togglegroup: "",
        changegroupactive: "2",
        focusgroup: "f",
        lockgroups: "lock",
        lockactivegroup: "toggle",
        moveintogroup: "l",
        moveoutofgroup: "",
        movewindoworgroup: "r",
        movegroupwindow: "b",
        denywindowfromgroup: "on",
        setignoregrouplock: "toggle",
        global: "quickshell:overview",
        submap: "resize",
        layoutmsg: "orientationleft",
        workspaceopt: "allfloat",
        setprop: "class:kitty alpha 0.8",
        tagwindow: "+code class:kitty",
        event: "custom",
        forceidle: "10",
        toggleswallow: "",
        cleartags: "",
        releaseinputcapture: "",
        changeworkspaceid: "1 2"
    };

    const allDispatcherKeys = Object.keys(devtools.HKB_DISPATCHERS);
    for (let i = 0; i < allDispatcherKeys.length; i++) {
        const dsp = allDispatcherKeys[i];
        assert.ok(Object.prototype.hasOwnProperty.call(sampleArgsByDispatcher, dsp), `Missing test sample for dispatcher ${dsp}`);
        const arg = sampleArgsByDispatcher[dsp];
        const line = arg ? `bind = SUPER, A, ${dsp}, ${arg}` : `bind = SUPER, A, ${dsp}`;
        const res = devtools.toolHyprKeybind(line, { to: "lua" });
        assert.ok(!res.error, `Unexpected error for ${dsp}: ${res.error}`);
        const firstLine = res.output.split("\n")[0];
        if (firstLine.startsWith("-- hl.bind(")) {
            assert.ok(res.meta.warnings >= 1, `Commented-out dispatcher ${dsp} must emit a warning`);
            assert.ok(!firstLine.includes("hl.dsp."), `Commented-out dispatcher ${dsp} must not invent hl.dsp.*`);
        } else {
            const m = /hl\.dsp\.([a-z_]+(?:\.[a-z_]+)?)\s*\(/.exec(firstLine);
            assert.ok(m, `Expected hl.dsp.* call for ${dsp}, got: ${firstLine}`);
            assert.ok(ALLOWED_HL_DSP.has(m[1]), `Emitted unknown hl.dsp.${m[1]} for ${dsp}`);
        }
    }

    // Specific mappings and unsupported/non-representable fallback checks
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, R, execr, foot", { to: "lua" }).output, "hl.bind(\"SUPER + R\", hl.dsp.exec_raw(\"foot\"))");
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, P, pseudo", { to: "lua" }).output, "hl.bind(\"SUPER + P\", hl.dsp.window.pseudo())");
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, T, togglesplit", { to: "lua" }).output, "hl.bind(\"SUPER + T\", hl.dsp.layout(\"togglesplit\"))");
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, F, forcerendererreload", { to: "lua" }).output, "hl.bind(\"SUPER + F\", hl.dsp.force_renderer_reload())");
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, O, pass, class:obs", { to: "lua" }).output, "hl.bind(\"SUPER + O\", hl.dsp.pass({ window = \"class:obs\" }))");
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, G, lockgroups, lock", { to: "lua" }).output, "hl.bind(\"SUPER + G\", hl.dsp.group.lock(\"lock\"))");
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, W, renameworkspace, 1 web", { to: "lua" }).output, "hl.bind(\"SUPER + W\", hl.dsp.workspace.rename({ workspace = 1, name = \"web\" }))");
    assert.equal(devtools.toolHyprKeybind("bind = SUPER, M, swapactiveworkspaces, DP-1 HDMI-A-1", { to: "lua" }).output, "hl.bind(\"SUPER + M\", hl.dsp.workspace.swap_monitors({ monitor1 = \"DP-1\", monitor2 = \"HDMI-A-1\" }))");

    const noLuaRes = devtools.toolHyprKeybind("bind = SUPER, O, workspaceopt, allfloat\nbind = SUPER, R, resizeactive, 10% 0", { to: "lua" });
    assert.equal(noLuaRes.meta.warnings, 2);
    assert.ok(noLuaRes.output.includes("-- hl.bind(\"SUPER + O\", \"workspaceopt\", \"allfloat\")"));
    assert.ok(noLuaRes.output.includes("-- hl.bind(\"SUPER + R\", \"resizeactive\", \"10% 0\")"));
    assert.ok(!noLuaRes.output.split("\n").some(line => !line.startsWith("-- [!]") && line.includes("hl.dsp.")));

    // Lua -> Conf round-trip for new hl.dsp.* calls
    const luaRoundTrip = devtools.toolHyprKeybind([
        "hl.bind(\"SUPER + P\", hl.dsp.window.pseudo())",
        "hl.bind(\"SUPER + T\", hl.dsp.layout(\"togglesplit\"))",
        "hl.bind(\"SUPER + O\", hl.dsp.pass({ window = \"class:obs\" }))",
        "hl.bind(\"SUPER + R\", hl.dsp.force_renderer_reload())",
        "hl.bind(\"SUPER + W\", hl.dsp.workspace.rename({ workspace = 1, name = \"web\" }))"
    ].join("\n"), { to: "conf" });
    assert.equal(luaRoundTrip.meta.warnings, 0);
    assert.equal(luaRoundTrip.output, [
        "bind = SUPER, P, pseudo",
        "bind = SUPER, T, togglesplit",
        "bind = SUPER, O, pass, class:obs",
        "bind = SUPER, R, forcerendererreload",
        "bind = SUPER, W, renameworkspace, 1 web"
    ].join("\n"));

    // Validation warnings: missing arg, extra arg, duplicate combo, invalid direction
    const badBinds = [
        "bind = SUPER, W, workspace",
        "bind = SUPER, E, exit, now",
        "bind = SUPER, E, killactive",
        "bind = SUPER, H, movefocus, left"
    ].join("\n");
    const valRes = devtools.toolHyprKeybind(badBinds, { to: "conf" });
    assert.equal(valRes.meta.binds, 4);
    assert.equal(valRes.meta.warnings, 4);
    assert.ok(valRes.output.includes("# [!] Line 1: \"workspace\" requires an argument"));
    assert.ok(valRes.output.includes("# [!] Line 2: \"exit\" takes no arguments"));
    assert.ok(valRes.output.includes("# [!] Line 3: Duplicate key combo \"SUPER + E\" (already bound on line 2)"));
    assert.ok(valRes.output.includes("# [!] Line 4: \"movefocus\" expects direction l, r, u, or d"));

    // runTool dispatch check
    const viaMaster = devtools.runTool("hypr_keybind", "bind = SUPER, code:10, workspace, 1", { to: "lua" });
    assert.equal(viaMaster.output, "hl.bind(\"SUPER + code:10\", hl.dsp.focus({ workspace = \"1\" }))");
    console.log("✓ Hyprland keybind tests passed");
}
// @test-end hypr_keybind

// 20. Master runner
{
    const runRes = devtools.runTool("uuid");
    assert.ok(runRes.output.length > 0);
    console.log("✓ Master runner tests passed");
}

console.log("\nAll devtools.js tests passed successfully! 🎉");
