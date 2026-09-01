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
