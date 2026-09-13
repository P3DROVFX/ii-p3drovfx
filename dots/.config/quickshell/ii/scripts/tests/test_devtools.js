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

// 20. Master runner
{
    const runRes = devtools.runTool("uuid");
    assert.ok(runRes.output.length > 0);
    console.log("✓ Master runner tests passed");
}

console.log("\nAll devtools.js tests passed successfully! 🎉");
