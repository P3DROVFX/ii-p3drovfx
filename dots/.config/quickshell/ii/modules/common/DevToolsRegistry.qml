pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import "functions/devtools.js" as DevToolsEngine

Singleton {
    id: root

    readonly property var categories: [
        { id: "all", label: Translation.tr("All"), icon: "grid_view" },
        { id: "generators", label: Translation.tr("Generators"), icon: "wand_stars" },
        { id: "encoders", label: Translation.tr("Encoders"), icon: "lock_open" },
        { id: "converters", label: Translation.tr("Converters"), icon: "sync_alt" },
        { id: "formatters", label: Translation.tr("Formatters"), icon: "code" },
        { id: "text", label: Translation.tr("Text"), icon: "match_case" }
    ]

    readonly property var tools: [
        // ── Generators ──
        {
            id: "uuid",
            name: Translation.tr("UUID Generator"),
            category: "generators",
            type: "generator",
            icon: "fingerprint",
            description: Translation.tr("Universally unique identifier (v4)"),
            keywords: ["uuid", "guid", "id", "identifier", "identificador", "gerar", "generate"],
            sampleInput: "",
            defaultOptions: { uppercase: false, hyphens: true, quantity: 1 },
            options: [
                { id: "uppercase", type: "toggle", label: Translation.tr("Uppercase"), default: false },
                { id: "hyphens", type: "toggle", label: Translation.tr("Hyphens"), default: true }
            ]
        },
        {
            id: "password",
            name: Translation.tr("Password Generator"),
            category: "generators",
            type: "generator",
            icon: "password",
            description: Translation.tr("Random password with customizable alphabet"),
            keywords: ["password", "pass", "senha", "secret", "gerar", "generate", "random"],
            sampleInput: "",
            defaultOptions: { length: 20, uppercase: true, lowercase: true, numbers: true, symbols: true, avoidAmbiguous: true },
            options: [
                {
                    id: "length",
                    type: "choice",
                    label: Translation.tr("Length"),
                    default: 20,
                    choices: [
                        { value: 12, label: "12" },
                        { value: 16, label: "16" },
                        { value: 20, label: "20" },
                        { value: 32, label: "32" },
                        { value: 64, label: "64" }
                    ]
                },
                { id: "uppercase", type: "toggle", label: Translation.tr("A-Z"), default: true },
                { id: "lowercase", type: "toggle", label: Translation.tr("a-z"), default: true },
                { id: "numbers", type: "toggle", label: Translation.tr("0-9"), default: true },
                { id: "symbols", type: "toggle", label: Translation.tr("!@#$"), default: true },
                { id: "avoidAmbiguous", type: "toggle", label: Translation.tr("No ambiguous (l, 1, O, 0)"), default: true }
            ]
        },
        {
            id: "lorem",
            name: Translation.tr("Lorem Ipsum"),
            category: "generators",
            type: "generator",
            icon: "notes",
            description: Translation.tr("Placeholder Latin text generator"),
            keywords: ["lorem", "ipsum", "text", "placeholder", "texto", "latin", "gerar"],
            sampleInput: "",
            defaultOptions: { unit: "paragraphs", count: 1, startWithLorem: true },
            options: [
                {
                    id: "unit",
                    type: "choice",
                    label: Translation.tr("Unit"),
                    default: "paragraphs",
                    choices: [
                        { value: "paragraphs", label: Translation.tr("Paragraphs") },
                        { value: "sentences", label: Translation.tr("Sentences") },
                        { value: "words", label: Translation.tr("Words") }
                    ]
                },
                {
                    id: "count",
                    type: "choice",
                    label: Translation.tr("Count"),
                    default: 1,
                    choices: [
                        { value: 1, label: "1" },
                        { value: 2, label: "2" },
                        { value: 3, label: "3" },
                        { value: 5, label: "5" },
                        { value: 10, label: "10" }
                    ]
                },
                { id: "startWithLorem", type: "toggle", label: Translation.tr("Start with Lorem ipsum"), default: true }
            ]
        },

        // ── Encoders / Decoders ──
        {
            id: "base64",
            name: Translation.tr("Base64 Encode / Decode"),
            category: "encoders",
            type: "transformer",
            icon: "enhanced_encryption",
            description: Translation.tr("Encode or decode UTF-8 text with URL-safe option"),
            keywords: ["base64", "b64", "encode", "decode", "codificar", "decodificar"],
            sampleInput: "Hello World! 🚀",
            defaultOptions: { mode: "encode", urlSafe: false },
            options: [
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Mode"),
                    default: "encode",
                    choices: [
                        { value: "encode", label: Translation.tr("Encode") },
                        { value: "decode", label: Translation.tr("Decode") }
                    ]
                },
                { id: "urlSafe", type: "toggle", label: Translation.tr("URL Safe (- and _)"), default: false }
            ]
        },
        {
            id: "url_encode",
            name: Translation.tr("URL Encode / Decode"),
            category: "encoders",
            type: "transformer",
            icon: "link",
            description: Translation.tr("Encode or decode URL query parameters and paths"),
            keywords: ["url", "uri", "percent", "encode", "decode", "link", "param"],
            sampleInput: "https://example.com/search?query=hello world & cat=1",
            defaultOptions: { mode: "encode", component: true },
            options: [
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Mode"),
                    default: "encode",
                    choices: [
                        { value: "encode", label: Translation.tr("Encode") },
                        { value: "decode", label: Translation.tr("Decode") }
                    ]
                },
                { id: "component", type: "toggle", label: Translation.tr("Component (encodeURIComponent)"), default: true }
            ]
        },
        {
            id: "html_entities",
            name: Translation.tr("HTML Entities"),
            category: "encoders",
            type: "transformer",
            icon: "html",
            description: Translation.tr("Escape or unescape HTML characters and entities"),
            keywords: ["html", "entity", "entities", "escape", "unescape", "sanitize"],
            sampleInput: "<div class=\"hero\">Quickshell & Co. 🚀</div>",
            defaultOptions: { mode: "encode" },
            options: [
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Mode"),
                    default: "encode",
                    choices: [
                        { value: "encode", label: Translation.tr("Encode") },
                        { value: "decode", label: Translation.tr("Decode") }
                    ]
                }
            ]
        },
        {
            id: "jwt_decoder",
            name: Translation.tr("JWT Decoder"),
            category: "encoders",
            type: "analyzer",
            icon: "token",
            description: Translation.tr("Decode header & payload from JSON Web Token"),
            keywords: ["jwt", "token", "json web token", "bearer", "auth", "decode"],
            sampleInput: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
            defaultOptions: {},
            options: []
        },

        // ── Converters ──
        {
            id: "number_base",
            name: Translation.tr("Number Base Converter"),
            category: "converters",
            type: "transformer",
            icon: "pin",
            description: Translation.tr("Convert between Decimal, Hex, Binary, and Octal"),
            keywords: ["base", "number", "bin", "binary", "hex", "hexadecimal", "octal", "decimal", "conversor"],
            sampleInput: "255",
            defaultOptions: { fromBase: "auto" },
            options: [
                {
                    id: "fromBase",
                    type: "choice",
                    label: Translation.tr("From Base"),
                    default: "auto",
                    choices: [
                        { value: "auto", label: Translation.tr("Auto Detect") },
                        { value: "10", label: Translation.tr("Decimal (10)") },
                        { value: "16", label: Translation.tr("Hex (16)") },
                        { value: "2", label: Translation.tr("Binary (2)") },
                        { value: "8", label: Translation.tr("Octal (8)") }
                    ]
                }
            ]
        },
        {
            id: "unix_timestamp",
            name: Translation.tr("Unix Timestamp"),
            category: "converters",
            type: "transformer",
            icon: "schedule",
            description: Translation.tr("Convert Unix epoch timestamp to human date and ISO 8601"),
            keywords: ["timestamp", "unix", "epoch", "time", "date", "iso", "data", "tempo"],
            sampleInput: "now",
            defaultOptions: {},
            options: []
        },
        {
            id: "color_converter",
            name: Translation.tr("Color Converter"),
            category: "converters",
            type: "transformer",
            icon: "palette",
            description: Translation.tr("Convert color between Hex, RGB(A), and HSL(A)"),
            keywords: ["color", "cor", "hex", "rgb", "rgba", "hsl", "hsla", "palette"],
            sampleInput: "#4A90E2",
            defaultOptions: {},
            options: []
        },

        // ── Formatters ──
        {
            id: "json_formatter",
            name: Translation.tr("JSON Formatter & Validator"),
            category: "formatters",
            type: "transformer",
            icon: "data_object",
            description: Translation.tr("Format, minify, sort keys, and validate JSON"),
            keywords: ["json", "format", "formatar", "minify", "minificar", "validate", "validar", "pretty"],
            sampleInput: "{\"name\":\"Quickshell\",\"version\":\"2.0\",\"features\":[\"fast\",\"customizable\",\"beautiful\"],\"active\":true}",
            defaultOptions: { indent: "2", sortKeys: false },
            options: [
                {
                    id: "indent",
                    type: "choice",
                    label: Translation.tr("Format"),
                    default: "2",
                    choices: [
                        { value: "2", label: "2 " + Translation.tr("spaces") },
                        { value: "4", label: "4 " + Translation.tr("spaces") },
                        { value: "tab", label: "Tab" },
                        { value: "minified", label: Translation.tr("Minify") }
                    ]
                },
                { id: "sortKeys", type: "toggle", label: Translation.tr("Sort Keys"), default: false }
            ]
        },

        // ── Text Tools ──
        {
            id: "case_converter",
            name: Translation.tr("Case Converter"),
            category: "text",
            type: "transformer",
            icon: "match_case",
            description: Translation.tr("Convert text case: camel, pascal, snake, kebab, title, and more"),
            keywords: ["case", "camelcase", "snakecase", "kebabcase", "pascalcase", "caixa", "maiuscula", "minuscula"],
            sampleInput: "hello world quickshell development",
            defaultOptions: { target: "camel" },
            options: [
                {
                    id: "target",
                    type: "choice",
                    label: Translation.tr("Target Case"),
                    default: "camel",
                    choices: [
                        { value: "camel", label: "camelCase" },
                        { value: "pascal", label: "PascalCase" },
                        { value: "snake", label: "snake_case" },
                        { value: "kebab", label: "kebab-case" },
                        { value: "constant", label: "CONSTANT_CASE" },
                        { value: "title", label: "Title Case" },
                        { value: "upper", label: "UPPERCASE" },
                        { value: "lower", label: "lowercase" },
                        { value: "dot", label: "dot.case" }
                    ]
                }
            ]
        },
        {
            id: "escape_string",
            name: Translation.tr("Escape / Unescape"),
            category: "text",
            type: "transformer",
            icon: "code_blocks",
            description: Translation.tr("Escape or unescape JSON, Regex, and Shell strings"),
            keywords: ["escape", "unescape", "regex", "shell", "string", "quotes", "aspas"],
            sampleInput: "Hello \"World\" & 'Developer'\nLine 2 $PATH",
            defaultOptions: { mode: "json", action: "escape" },
            options: [
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Language"),
                    default: "json",
                    choices: [
                        { value: "json", label: "JSON String" },
                        { value: "regex", label: "Regex" },
                        { value: "shell_single", label: "Shell ('single')" },
                        { value: "shell_double", label: "Shell (\"double\")" },
                        { value: "sql", label: "SQL String" }
                    ]
                },
                {
                    id: "action",
                    type: "choice",
                    label: Translation.tr("Action"),
                    default: "escape",
                    choices: [
                        { value: "escape", label: Translation.tr("Escape") },
                        { value: "unescape", label: Translation.tr("Unescape") }
                    ]
                }
            ]
        },
        {
            id: "text_inspector",
            name: Translation.tr("Text Inspector"),
            category: "text",
            type: "analyzer",
            icon: "analytics",
            description: Translation.tr("Detailed character, word, sentence, and UTF-8 byte statistics"),
            keywords: ["count", "stats", "statistics", "words", "characters", "palavras", "linhas", "bytes"],
            sampleInput: "Quickshell is a flexible framework for building desktop shells and desktop environments.\nIt offers powerful QML and C++ bindings with top performance.",
            defaultOptions: {},
            options: []
        },
        {
            id: "line_tools",
            name: Translation.tr("Line Operations"),
            category: "text",
            type: "transformer",
            icon: "format_list_numbered",
            description: Translation.tr("Sort alphabetically, deduplicate, reverse, or number lines"),
            keywords: ["lines", "sort", "dedupe", "reverse", "number", "linhas", "ordenar", "remover duplicadas"],
            sampleInput: "Zebra\nApple\nOrange\nBanana\nApple\nGrape",
            defaultOptions: { operation: "sort_az", caseSensitive: false },
            options: [
                {
                    id: "operation",
                    type: "choice",
                    label: Translation.tr("Operation"),
                    default: "sort_az",
                    choices: [
                        { value: "sort_az", label: "A → Z" },
                        { value: "sort_za", label: "Z → A" },
                        { value: "sort_length_asc", label: Translation.tr("Shortest first") },
                        { value: "sort_length_desc", label: Translation.tr("Longest first") },
                        { value: "dedupe", label: Translation.tr("Remove duplicates") },
                        { value: "reverse", label: Translation.tr("Reverse lines") },
                        { value: "number", label: Translation.tr("Add line numbers") },
                        { value: "filter_empty", label: Translation.tr("Remove empty lines") }
                    ]
                },
                { id: "caseSensitive", type: "toggle", label: Translation.tr("Case sensitive"), default: false }
            ]
        },
        {
            id: "whitespace_tools",
            name: Translation.tr("Whitespace Cleaner"),
            category: "text",
            type: "transformer",
            icon: "space_bar",
            description: Translation.tr("Trim lines, collapse spaces, or convert tabs/spaces"),
            keywords: ["whitespace", "trim", "collapse", "spaces", "tabs", "espacos", "limpar"],
            sampleInput: "   First line with spaces   \n\n\tSecond line with tab\n      Third line   ",
            defaultOptions: { operation: "trim", tabSize: 4 },
            options: [
                {
                    id: "operation",
                    type: "choice",
                    label: Translation.tr("Operation"),
                    default: "trim",
                    choices: [
                        { value: "trim", label: Translation.tr("Trim each line") },
                        { value: "collapse", label: Translation.tr("Collapse multiple spaces") },
                        { value: "remove_blank", label: Translation.tr("Remove blank lines") },
                        { value: "tabs_to_spaces", label: Translation.tr("Tabs to spaces") },
                        { value: "spaces_to_tabs", label: Translation.tr("Spaces to tabs") },
                        { value: "remove_all", label: Translation.tr("Remove all spaces") }
                    ]
                }
            ]
        },
        {
            id: "regex_tester",
            name: Translation.tr("Regex Tester"),
            category: "text",
            type: "transformer",
            icon: "regular_expression",
            description: Translation.tr("Test regular expressions with groups and match details"),
            keywords: ["regex", "regexp", "regular expression", "test", "match", "padrao"],
            sampleInput: "Contact us at info@example.com or support@quickshell.org for assistance.",
            defaultOptions: { pattern: "([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})", flags: "g" },
            options: [
                { id: "pattern", type: "text", label: Translation.tr("Pattern"), default: "([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})" },
                { id: "flags", type: "text", label: Translation.tr("Flags"), default: "g" }
            ]
        },
        {
            id: "slugify",
            name: Translation.tr("Slugify"),
            category: "text",
            type: "transformer",
            icon: "link_off",
            description: Translation.tr("Convert string to URL-friendly slug (removes accents)"),
            keywords: ["slug", "slugify", "url", "seo", "sanitize", "titular", "link"],
            sampleInput: "How to Build an Incredible System in 2026?",
            defaultOptions: { separator: "-", lowercase: true },
            options: [
                {
                    id: "separator",
                    type: "choice",
                    label: Translation.tr("Separator"),
                    default: "-",
                    choices: [
                        { value: "-", label: "Hyphen (-)" },
                        { value: "_", label: "Underscore (_)" },
                        { value: ".", label: "Dot (.)" }
                    ]
                },
                { id: "lowercase", type: "toggle", label: Translation.tr("Lowercase"), default: true }
            ]
        },
        {
            id: "text_diff",
            name: Translation.tr("Text Diff"),
            category: "text",
            type: "transformer",
            icon: "difference",
            description: Translation.tr("Line-by-line unified diff between original and modified text"),
            keywords: ["diff", "compare", "diferenca", "comparar", "patch", "git"],
            sampleInput: "const greeting = 'Hello';\nconsole.log(greeting);\n\n===DIFF_SPLIT===\nconst greeting = 'Hello, World!';\nconsole.log(greeting);\nconsole.log('Done!');",
            defaultOptions: {},
            options: []
        }
    ]

    function byId(id: string): var {
        return root.tools.find(tool => tool.id === id) ?? null;
    }

    function run(toolId: string, input = "", options = {}): var {
        return DevToolsEngine.runTool(toolId, input, options);
    }

    function search(queryText: string, category = "all"): var {
        const query = String(queryText ?? "").trim().toLocaleLowerCase();
        const terms = query.split(/\s+/).filter(t => t.length > 0);

        return root.tools.filter(tool => {
            if (category !== "all" && tool.category !== category) {
                return false;
            }
            if (terms.length === 0) {
                return true;
            }
            const keywordsStr = Array.isArray(tool.keywords) ? tool.keywords.join(" ") : String(tool.keywords ?? "");
            const fullText = [tool.id, tool.name, tool.description, keywordsStr].join(" ").toLocaleLowerCase();
            return terms.every(term => fullText.includes(term));
        });
    }

    function inlineMatches(queryText: string): var {
        const query = String(queryText ?? "").trim().toLocaleLowerCase();
        if (query.length < 2)
            return [];

        const generic = ["tool", "tools", "devtools", "generator", "generators", "generate", "gerador", "gerar", "caixa de ferramentas"];
        const isGeneric = generic.some(t => t === query);

        // Direct tool commands (e.g. "b64 hello", "uuid", "password", "json {...}")
        const results = [];
        for (const tool of root.tools) {
            if (isGeneric) {
                results.push({ tool, query, arg: "" });
                continue;
            }
            // Check direct keyword match or prefix command
            const matchedKeyword = (tool.keywords ?? []).find(kw => {
                if (query === kw) return true;
                if (query.startsWith(kw + " ") || query.startsWith(kw + ":")) return true;
                return false;
            });
            if (matchedKeyword) {
                const arg = query.startsWith(matchedKeyword) ? query.slice(matchedKeyword.length).replace(/^[:\s]+/, "") : "";
                results.push({ tool, query, arg });
            }
        }
        return results;
    }
}
