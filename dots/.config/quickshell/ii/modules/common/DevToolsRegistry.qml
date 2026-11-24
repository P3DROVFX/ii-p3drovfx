pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import "functions/devtools.js" as DevToolsEngine

Singleton {
    id: root

    function qrColors(style: string, colors = ({})): var {
        if (colors && Object.keys(colors).length > 0)
            return DevToolsEngine.qrSvgResolveColors(style || QrCode.style, colors);
        return QrCode.colors(style);
    }

    function qrSvg(visual: var, colors = ({}), options = ({})): string {
        if (colors && Object.keys(colors).length > 0) {
            const opts = Object.assign({}, options, { shapes: QrCode._shapesCache });
            return DevToolsEngine.qrSvg(visual, colors, opts);
        }
        return QrCode.svg(visual, options?.style ?? "", options);
    }

    readonly property var categories: [
        { id: "all", label: Translation.tr("All"), icon: "grid_view" },
        { id: "generators", label: Translation.tr("Generators"), icon: "wand_stars" },
        { id: "encoders", label: Translation.tr("Encoders"), icon: "lock_open" },
        { id: "converters", label: Translation.tr("Converters"), icon: "sync_alt" },
        { id: "formatters", label: Translation.tr("Formatters"), icon: "code" },
        { id: "text", label: Translation.tr("Text"), icon: "match_case" },
        { id: "time", label: Translation.tr("Time & units"), icon: "straighten" },
        { id: "color", label: Translation.tr("Color"), icon: "palette" },
        { id: "web", label: Translation.tr("Web & system"), icon: "public" },
        { id: "dev", label: Translation.tr("Developer"), icon: "terminal" },
        // Page-only: its tools need files and a preview, so only the
        // cheatsheet page shows them (search(..., true)).
        { id: "media", label: Translation.tr("Images"), icon: "image", pageOnly: true }
    ]

    /// Categories the Search Tools panel offers (no page-only ones).
    readonly property var searchCategories: root.categories.filter(category => !category.pageOnly)
    /// Tools the Search panel and inline launcher results may run: page-only
    /// tools have no devtools.js case and are never passed to run().
    readonly property var searchTools: root.tools.filter(tool => !tool.pageOnly)

    readonly property var tools: [
        // ── Generators ──
        {
            id: "uuid",
            name: Translation.tr("UUID Generator"),
            category: "generators",
            type: "generator",
            icon: "fingerprint",
            description: Translation.tr("Universally unique identifier: random (v4) or time-ordered (v7)"),
            keywords: ["uuid", "guid", "id", "identifier", "identificador", "gerar", "generate", "uuidv7", "v7"],
            searchTerms: ["uuid generator", "guid generator", "unique identifier", "generate uuid", "generate id"],
            sampleInput: "",
            defaultOptions: { version: "4", uppercase: false, hyphens: true, quantity: 1 },
            options: [
                {
                    id: "version",
                    type: "choice",
                    label: Translation.tr("Version"),
                    default: "4",
                    choices: [
                        { value: "4", label: Translation.tr("v4 · random") },
                        { value: "7", label: Translation.tr("v7 · time-ordered") }
                    ]
                },
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
            searchTerms: ["password generator", "generate password", "strong password", "random password", "passphrase generator"],
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
            searchTerms: ["lorem ipsum generator", "placeholder text", "dummy text", "filler text", "latin text"],
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
            searchTerms: ["base64 encoder", "base64 decoder", "encode base64", "decode base64"],
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
            searchTerms: ["url encoder", "url decoder", "percent encoding", "encode url", "decode url"],
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
            searchTerms: ["html escaper", "html entities", "escape html", "unescape html"],
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
            searchTerms: ["jwt decoder", "decode jwt", "decode token", "read jwt"],
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
            searchTerms: ["base converter", "number base converter", "binary to decimal", "decimal to binary", "hex converter", "octal converter"],
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
            searchTerms: ["timestamp converter", "epoch converter", "unix time", "timestamp to date", "date converter"],
            sampleInput: "now",
            defaultOptions: {},
            options: []
        },
        {
            id: "color_converter",
            name: Translation.tr("Color Converter"),
            category: "color",
            type: "transformer",
            icon: "palette",
            description: Translation.tr("Convert color between Hex, RGB(A), and HSL(A)"),
            keywords: ["color", "cor", "hex", "rgb", "rgba", "hsl", "hsla"],
            searchTerms: ["color converter", "convert color", "hex to rgb", "rgb to hex", "color format converter"],
            sampleInput: "#4A90E2",
            defaultOptions: {},
            options: []
        },

        {
            id: "data_converter",
            name: Translation.tr("YAML / JSON / TOML"),
            category: "converters",
            type: "transformer",
            icon: "data_object",
            description: Translation.tr("Convert config files between JSON, YAML and TOML"),
            keywords: ["yaml", "yml", "toml", "config"],
            searchTerms: ["yaml to json", "json to yaml", "toml to json", "json to toml", "yaml converter", "toml converter"],
            sampleInput: "server:\n  host: example.com\n  ports: [80, 443]\nusers:\n  - name: ana\n    admin: true\n  - name: bo\n",
            defaultOptions: { from: "auto", to: "json", indent: "2" },
            options: [
                {
                    id: "from",
                    type: "choice",
                    label: Translation.tr("From"),
                    default: "auto",
                    choices: [
                        { value: "auto", label: Translation.tr("Auto") },
                        { value: "json", label: "JSON" },
                        { value: "yaml", label: "YAML" },
                        { value: "toml", label: "TOML" }
                    ]
                },
                {
                    id: "to",
                    type: "choice",
                    label: Translation.tr("To"),
                    default: "json",
                    choices: [
                        { value: "json", label: "JSON" },
                        { value: "yaml", label: "YAML" },
                        { value: "toml", label: "TOML" }
                    ]
                },
                {
                    id: "indent",
                    type: "choice",
                    label: Translation.tr("Indent"),
                    default: "2",
                    choices: [
                        { value: "2", label: "2" },
                        { value: "4", label: "4" }
                    ]
                }
            ]
        },

        // ── Formatters ──
        {
            id: "code_formatter",
            name: Translation.tr("XML / HTML / CSS / SQL Formatter"),
            category: "formatters",
            type: "transformer",
            icon: "format_align_left",
            description: Translation.tr("Beautify or minify XML, HTML, CSS and SQL"),
            keywords: ["xml", "css", "sql", "beautify", "prettify", "pretty print", "indent"],
            searchTerms: ["xml formatter", "html formatter", "css formatter", "sql formatter", "css minifier", "html beautifier", "format sql"],
            sampleInput: "select u.id, u.name, count(o.id) as orders from users u left join orders o on o.user_id = u.id and o.paid = true where u.active = 1 group by u.id, u.name order by orders desc limit 10;",
            defaultOptions: { language: "auto", mode: "beautify", indent: "2", uppercase: true },
            options: [
                {
                    id: "language",
                    type: "choice",
                    label: Translation.tr("Language"),
                    default: "auto",
                    choices: [
                        { value: "auto", label: Translation.tr("Auto") },
                        { value: "xml", label: "XML" },
                        { value: "html", label: "HTML" },
                        { value: "css", label: "CSS" },
                        { value: "sql", label: "SQL" }
                    ]
                },
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Mode"),
                    default: "beautify",
                    choices: [
                        { value: "beautify", label: Translation.tr("Beautify") },
                        { value: "minify", label: Translation.tr("Minify") }
                    ]
                },
                {
                    id: "indent",
                    type: "choice",
                    label: Translation.tr("Indent"),
                    default: "2",
                    choices: [
                        { value: "2", label: "2" },
                        { value: "4", label: "4" },
                        { value: "tab", label: "Tab" }
                    ]
                },
                { id: "uppercase", type: "toggle", label: Translation.tr("SQL keywords in caps"), default: true }
            ]
        },
        {
            id: "json_formatter",
            name: Translation.tr("JSON Formatter & Validator"),
            category: "formatters",
            type: "transformer",
            icon: "data_object",
            description: Translation.tr("Format, minify, sort keys, and validate JSON"),
            keywords: ["json", "format", "formatar", "minify", "minificar", "validate", "validar", "pretty"],
            searchTerms: ["json formatter", "json validator", "prettify json", "minify json", "format json"],
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
            searchTerms: ["case converter", "convert case", "uppercase lowercase", "camel case converter", "capitalize text"],
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
            searchTerms: ["string escaper", "escape string", "escape quotes", "escape shell", "unescape string"],
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
            searchTerms: ["word counter", "character counter", "count words", "count characters", "text statistics"],
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
            searchTerms: ["sort lines", "remove duplicate lines", "reverse lines", "number lines", "line operations"],
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
            searchTerms: ["whitespace cleaner", "remove extra spaces", "tabs to spaces", "remove blank lines", "trim lines"],
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
            searchTerms: ["regex tester", "regular expression tester", "test regex", "regex matcher"],
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
            searchTerms: ["slug generator", "url slug", "seo slug", "generate slug"],
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
            searchTerms: ["text diff", "compare texts", "text comparison", "difference between texts"],
            sampleInput: "const greeting = 'Hello';\nconsole.log(greeting);\n\n===DIFF_SPLIT===\nconst greeting = 'Hello, World!';\nconsole.log(greeting);\nconsole.log('Done!');",
            defaultOptions: {},
            options: []
        },

        // ── Generators (IDs) ──
        {
            id: "id_generator",
            name: Translation.tr("NanoID & ULID"),
            category: "generators",
            type: "generator",
            icon: "fingerprint",
            description: Translation.tr("Short URL-safe NanoIDs or lexicographically sortable ULIDs"),
            keywords: ["nanoid", "ulid", "id", "identifier", "short id", "cuid", "identificador"],
            searchTerms: ["nanoid generator", "ulid generator", "short id generator", "generate nanoid", "generate ulid"],
            defaultOptions: { kind: "nanoid", size: 21, quantity: 1 },
            options: [
                {
                    id: "kind",
                    type: "choice",
                    label: Translation.tr("Kind"),
                    default: "nanoid",
                    choices: [
                        { value: "nanoid", label: "NanoID" },
                        { value: "ulid", label: "ULID" }
                    ]
                },
                {
                    id: "size",
                    type: "choice",
                    label: Translation.tr("NanoID length"),
                    default: 21,
                    choices: [
                        { value: 10, label: "10" },
                        { value: 16, label: "16" },
                        { value: 21, label: "21" },
                        { value: 32, label: "32" }
                    ]
                },
                {
                    id: "quantity",
                    type: "choice",
                    label: Translation.tr("Quantity"),
                    default: 1,
                    choices: [
                        { value: 1, label: "1" },
                        { value: 5, label: "5" },
                        { value: 10, label: "10" }
                    ]
                }
            ]
        },

        // ── Encoders (hashes, bytes) ──
        {
            id: "hash_generator",
            name: Translation.tr("Hash Generator"),
            category: "encoders",
            type: "transformer",
            icon: "tag",
            description: Translation.tr("MD5, SHA-1, SHA-256 and CRC32 digests of UTF-8 text"),
            keywords: ["hash", "md5", "sha1", "sha256", "sha-256", "crc32", "checksum", "digest"],
            searchTerms: ["hash generator", "checksum calculator", "md5 hash", "sha256 hash", "crc32"],
            sampleInput: "The quick brown fox jumps over the lazy dog",
            defaultOptions: { algorithm: "all", uppercase: false },
            options: [
                {
                    id: "algorithm",
                    type: "choice",
                    label: Translation.tr("Algorithm"),
                    default: "all",
                    choices: [
                        { value: "all", label: Translation.tr("All") },
                        { value: "md5", label: "MD5" },
                        { value: "sha1", label: "SHA-1" },
                        { value: "sha256", label: "SHA-256" },
                        { value: "crc32", label: "CRC32" }
                    ]
                },
                { id: "uppercase", type: "toggle", label: Translation.tr("Uppercase"), default: false }
            ]
        },
        {
            id: "qr_code",
            name: Translation.tr("QR Code"),
            category: "encoders",
            type: "transformer",
            icon: "qr_code_2",
            description: Translation.tr("Text, links, Wi-Fi logins or contacts as a Pixel, Blob or Classic QR code"),
            keywords: ["qr", "qrcode", "qr code", "vcard", "wifi qr", "codigo qr"],
            searchTerms: ["qr code generator", "make qr code", "wifi qr code", "qr code for link", "gerar qr code", "contact qr code"],
            sampleInput: "ssid: Home\npassword: correct horse battery staple",
            defaultOptions: { style: "pixel", decoration: true, kind: "auto", ecc: "M" },
            options: [
                {
                    id: "style",
                    type: "choice",
                    label: Translation.tr("Style"),
                    default: "pixel",
                    choices: [
                        { value: "pixel", label: Translation.tr("Pixel") },
                        { value: "blob", label: Translation.tr("Blob") },
                        { value: "classic", label: Translation.tr("Classic") }
                    ]
                },
                { id: "decoration", type: "toggle", label: Translation.tr("Decoration"), default: true },
                {
                    id: "kind",
                    type: "choice",
                    label: Translation.tr("Content"),
                    default: "auto",
                    choices: [
                        { value: "auto", label: Translation.tr("Auto") },
                        { value: "text", label: Translation.tr("Text / link") },
                        { value: "wifi", label: "Wi-Fi" },
                        { value: "vcard", label: Translation.tr("Contact") }
                    ]
                },
                {
                    id: "ecc",
                    type: "choice",
                    label: Translation.tr("Error correction"),
                    default: "M",
                    choices: [
                        { value: "L", label: "L 7%" },
                        { value: "M", label: "M 15%" },
                        { value: "Q", label: "Q 25%" },
                        { value: "H", label: "H 30%" }
                    ]
                }
            ]
        },
        {
            id: "hex_text",
            name: Translation.tr("Text ↔ Hex"),
            category: "encoders",
            type: "transformer",
            icon: "hexagon",
            description: Translation.tr("Turn text into hexadecimal UTF-8 bytes and back"),
            keywords: ["hex", "hexadecimal", "bytes", "ascii", "dump", "hexa"],
            searchTerms: ["text to hex", "hex to text", "hex converter", "hex dump", "ascii to hex"],
            sampleInput: "Hello, Quickshell!",
            defaultOptions: { mode: "encode", separator: "space" },
            options: [
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Mode"),
                    default: "encode",
                    choices: [
                        { value: "encode", label: Translation.tr("Text → Hex") },
                        { value: "decode", label: Translation.tr("Hex → Text") }
                    ]
                },
                {
                    id: "separator",
                    type: "choice",
                    label: Translation.tr("Separator"),
                    default: "space",
                    choices: [
                        { value: "space", label: Translation.tr("Space") },
                        { value: "none", label: Translation.tr("None") },
                        { value: "colon", label: Translation.tr("Colon") }
                    ]
                }
            ]
        },

        // ── Converters (data) ──
        {
            id: "json_csv",
            name: Translation.tr("JSON ↔ CSV"),
            category: "converters",
            type: "transformer",
            icon: "table",
            description: Translation.tr("Convert an array of JSON objects to CSV and back"),
            keywords: ["csv", "json", "table", "spreadsheet", "planilha", "tabela"],
            searchTerms: ["json to csv", "csv to json", "csv converter", "json csv converter"],
            sampleInput: "[\n  { \"name\": \"Ada\", \"language\": \"Python\", \"stars\": 42 },\n  { \"name\": \"Linus\", \"language\": \"C\", \"stars\": 99 }\n]",
            defaultOptions: { mode: "json_to_csv", delimiter: ",", inferTypes: true },
            options: [
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Mode"),
                    default: "json_to_csv",
                    choices: [
                        { value: "json_to_csv", label: "JSON → CSV" },
                        { value: "csv_to_json", label: "CSV → JSON" }
                    ]
                },
                {
                    id: "delimiter",
                    type: "choice",
                    label: Translation.tr("Delimiter"),
                    default: ",",
                    choices: [
                        { value: ",", label: Translation.tr("Comma") },
                        { value: ";", label: Translation.tr("Semicolon") },
                        { value: "tab", label: Translation.tr("Tab") }
                    ]
                },
                { id: "inferTypes", type: "toggle", label: Translation.tr("Numbers & booleans from CSV"), default: true }
            ]
        },
        {
            id: "byte_size",
            name: Translation.tr("Data Size Converter"),
            category: "converters",
            type: "analyzer",
            icon: "database",
            description: Translation.tr("Convert sizes between SI (kB, MB) and binary (KiB, MiB) units"),
            keywords: ["bytes", "size", "kb", "mb", "gb", "kib", "mib", "gib", "tamanho", "storage"],
            searchTerms: ["byte size converter", "file size converter", "convert bytes", "kb to mb", "data size converter"],
            sampleInput: "1.5 GiB",
            defaultOptions: {},
            options: []
        },

        // ── Time & units ──
        {
            id: "unit_converter",
            name: Translation.tr("Unit Converter"),
            category: "time",
            type: "analyzer",
            icon: "straighten",
            description: Translation.tr("Length, mass, temperature, area, volume, speed, energy, power, pressure, time and screen units (px, rem, pt)"),
            keywords: ["unit", "units", "unidade", "unidades", "measure", "medida", "km", "miles", "kg", "lb", "celsius", "fahrenheit", "px", "rem"],
            searchTerms: ["unit converter", "convert units", "km to miles", "celsius to fahrenheit", "px to rem", "kg to lb", "conversor de unidades"],
            sampleInput: "72 °F",
            defaultOptions: { dpi: 96, rootSize: 16 },
            options: [
                {
                    id: "dpi",
                    type: "choice",
                    label: Translation.tr("Screen DPI"),
                    default: 96,
                    choices: [
                        { value: 72, label: "72" },
                        { value: 96, label: "96 (CSS)" },
                        { value: 160, label: "160 (Android)" },
                        { value: 220, label: "220" }
                    ]
                },
                {
                    id: "rootSize",
                    type: "choice",
                    label: Translation.tr("1rem"),
                    default: 16,
                    choices: [
                        { value: 14, label: "14px" },
                        { value: 16, label: "16px" },
                        { value: 18, label: "18px" },
                        { value: 20, label: "20px" }
                    ]
                }
            ]
        },
        {
            id: "time_zones",
            name: Translation.tr("Time Zones"),
            category: "time",
            type: "analyzer",
            icon: "travel_explore",
            description: Translation.tr("A time in one place shown across cities, with daylight saving and a meeting planner grid"),
            keywords: ["tz", "timezone", "timezones", "time zone", "fuso", "fuso horario", "world clock", "meeting", "reuniao"],
            searchTerms: ["time zone converter", "world clock", "meeting planner", "convert time zone", "fuso horario", "what time is it in"],
            sampleInput: "14:00 São Paulo",
            defaultOptions: { zones: "Local, UTC, New York, London, Berlin, Tokyo", grid: false, dateOrder: "dmy" },
            options: [
                { id: "zones", type: "text", label: Translation.tr("Show in"), default: "Local, UTC, New York, London, Berlin, Tokyo" },
                { id: "grid", type: "toggle", label: Translation.tr("Meeting grid"), default: false },
                {
                    id: "dateOrder",
                    type: "choice",
                    label: Translation.tr("Dates"),
                    default: "dmy",
                    choices: [
                        { value: "dmy", label: "DD/MM" },
                        { value: "mdy", label: "MM/DD" }
                    ]
                }
            ]
        },
        {
            id: "date_calculator",
            name: Translation.tr("Date Calculator"),
            category: "time",
            type: "analyzer",
            icon: "date_range",
            description: Translation.tr("Days between dates, business days, adding days, weeks or months, ISO week and age"),
            keywords: ["dates", "days", "calendar", "business days", "dias", "dias uteis", "datas", "calendario", "week", "semana", "age", "idade"],
            searchTerms: ["date calculator", "days between dates", "business days", "add days to date", "days until", "calculadora de datas", "iso week"],
            sampleInput: "2026-01-01 to 2026-12-25",
            defaultOptions: { dateOrder: "dmy" },
            options: [
                {
                    id: "dateOrder",
                    type: "choice",
                    label: Translation.tr("Dates"),
                    default: "dmy",
                    choices: [
                        { value: "dmy", label: "DD/MM/YYYY" },
                        { value: "mdy", label: "MM/DD/YYYY" }
                    ]
                }
            ]
        },

        // ── Color ──
        {
            id: "contrast_checker",
            name: Translation.tr("Contrast Checker"),
            category: "color",
            type: "analyzer",
            icon: "contrast",
            description: Translation.tr("WCAG contrast ratio of a text colour on a background, with the closest colour that passes"),
            keywords: ["contrast", "contraste", "wcag", "a11y", "accessibility", "acessibilidade"],
            searchTerms: ["contrast checker", "wcag contrast", "color contrast", "accessible colors", "contrast ratio"],
            sampleInput: "#777777 on #FFFFFF",
            defaultOptions: {},
            options: []
        },
        {
            id: "palette_generator",
            name: Translation.tr("Palette Generator"),
            category: "color",
            type: "transformer",
            icon: "colors",
            description: Translation.tr("Tonal ramps and harmonies from one colour, or every Material You role exactly as matugen makes them (also takes a matugen command)"),
            keywords: ["palette", "paleta", "tones", "tonal", "shades", "harmony", "complementary", "triadic", "scheme", "matugen", "material you", "m3"],
            searchTerms: ["palette generator", "color palette", "tonal palette", "color harmony", "complementary color", "gerar paleta", "matugen colors", "material you scheme", "material 3 color roles"],
            sampleInput: "#6750A4",
            defaultOptions: { scheme: "tonal", format: "list", matugenType: "tonal-spot", mode: "dark" },
            options: [
                {
                    id: "scheme",
                    type: "choice",
                    label: Translation.tr("Scheme"),
                    default: "tonal",
                    choices: [
                        { value: "tonal", label: Translation.tr("Tonal") },
                        { value: "matugen", label: Translation.tr("Material You (matugen)") },
                        { value: "shades", label: Translation.tr("Shades") },
                        { value: "complementary", label: Translation.tr("Complementary") },
                        { value: "analogous", label: Translation.tr("Analogous") },
                        { value: "triadic", label: Translation.tr("Triadic") },
                        { value: "split", label: Translation.tr("Split") },
                        { value: "tetradic", label: Translation.tr("Tetradic") }
                    ]
                },
                {
                    id: "format",
                    type: "choice",
                    label: Translation.tr("Format"),
                    default: "list",
                    choices: [
                        { value: "list", label: Translation.tr("List") },
                        { value: "css", label: "CSS" },
                        { value: "json", label: "JSON" },
                        { value: "qml", label: "QML" }
                    ]
                },
                {
                    id: "matugenType",
                    type: "choice",
                    label: Translation.tr("Matugen type"),
                    default: "tonal-spot",
                    choices: [
                        { value: "tonal-spot", label: Translation.tr("Tonal spot") },
                        { value: "vibrant", label: Translation.tr("Vibrant") },
                        { value: "expressive", label: Translation.tr("Expressive") },
                        { value: "neutral", label: Translation.tr("Neutral") },
                        { value: "rainbow", label: Translation.tr("Rainbow") },
                        { value: "fruit-salad", label: Translation.tr("Fruit salad") }
                    ]
                },
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Matugen mode"),
                    default: "dark",
                    choices: [
                        { value: "dark", label: Translation.tr("Dark") },
                        { value: "light", label: Translation.tr("Light") }
                    ]
                }
            ]
        },

        // ── Web & system ──
        {
            id: "subnet_calculator",
            name: Translation.tr("Subnet Calculator"),
            category: "web",
            type: "analyzer",
            icon: "lan",
            description: Translation.tr("IPv4 and IPv6 CIDR: netmask, network, host range and count; extra lines are checked for membership"),
            keywords: ["subnet", "cidr", "ipv4", "ipv6", "netmask", "mask", "sub-rede", "subrede", "ip"],
            searchTerms: ["subnet calculator", "cidr calculator", "ip range", "netmask calculator", "ipv6 subnet", "calculadora de sub-rede"],
            sampleInput: "192.168.1.130/26\n192.168.1.150\n192.168.1.200",
            defaultOptions: {},
            options: []
        },
        {
            id: "url_parser",
            name: Translation.tr("URL Parser"),
            category: "web",
            type: "analyzer",
            icon: "link",
            description: Translation.tr("Break a URL into scheme, host, port, path, query parameters and fragment"),
            keywords: ["url", "uri", "query", "params", "querystring", "parse", "link"],
            searchTerms: ["url parser", "parse url", "url parts", "extract query params", "query string parser"],
            sampleInput: "https://dev@example.com:8080/api/v1/search?q=quick+shell&page=2&tags=qml&tags=hyprland#results",
            defaultOptions: {},
            options: []
        },
        {
            id: "http_status",
            name: Translation.tr("HTTP Status Codes"),
            category: "web",
            type: "analyzer",
            icon: "http",
            description: Translation.tr("Look up HTTP status codes by number, class (4xx) or word"),
            keywords: ["http", "status", "code", "404", "500", "rest", "api", "response"],
            searchTerms: ["http status codes", "status code lookup", "404 meaning", "http error codes"],
            sampleInput: "4xx",
            defaultOptions: {},
            options: []
        },
        {
            id: "cron_explainer",
            name: Translation.tr("Cron Explainer"),
            category: "web",
            type: "analyzer",
            icon: "schedule",
            description: Translation.tr("Explain a cron expression field by field and list its next runs"),
            keywords: ["cron", "crontab", "schedule", "agendamento", "timer", "job"],
            searchTerms: ["cron explainer", "cron expression", "crontab schedule", "next cron runs"],
            sampleInput: "*/15 9-17 * * 1-5",
            defaultOptions: { count: 5 },
            options: [
                {
                    id: "count",
                    type: "choice",
                    label: Translation.tr("Next runs"),
                    default: 5,
                    choices: [
                        { value: 5, label: "5" },
                        { value: 10, label: "10" },
                        { value: 20, label: "20" }
                    ]
                }
            ]
        },
        {
            id: "chmod_calculator",
            name: Translation.tr("chmod Calculator"),
            category: "web",
            type: "analyzer",
            icon: "admin_panel_settings",
            description: Translation.tr("Translate Unix permissions between octal (755) and symbolic (rwxr-xr-x)"),
            keywords: ["chmod", "permissions", "permissoes", "octal", "rwx", "unix", "linux"],
            searchTerms: ["chmod calculator", "linux permissions", "file permissions", "unix permissions", "octal permissions"],
            sampleInput: "4755",
            defaultOptions: {},
            options: []
        },

        // ── Developer (one slot per tool) ──
        // @slot-begin curl_converter
        {
            id: "curl_converter",
            name: Translation.tr("cURL Converter"),
            category: "dev",
            type: "transformer",
            icon: "api",
            description: Translation.tr("Convert cURL to fetch, Python, HTTPie, wget, Go, or HTTP to cURL"),
            keywords: ["curl", "curlc", "fetch", "httpie", "wget", "requests", "golang", "request"],
            searchTerms: ["curl converter", "curl to fetch", "curl to python", "curl to go", "curl to wget", "curl to httpie", "http request to curl", "copy as curl"],
            sampleInput: "curl -X POST 'https://ex.io/v1?dry=1' \\\n  -H 'Content-Type: application/json' \\\n  -H 'X-Request-Id: req_94' \\\n  -u 'alice:secret' \\\n  -d '{\"item\":\"kbd\",\"qty\":2}'",
            defaultOptions: { target: "fetch" },
            options: [
                {
                    id: "target",
                    type: "choice",
                    label: Translation.tr("Target"),
                    default: "fetch",
                    choices: [
                        { value: "fetch", label: Translation.tr("fetch") },
                        { value: "python", label: Translation.tr("Python") },
                        { value: "httpie", label: Translation.tr("HTTPie") },
                        { value: "wget", label: Translation.tr("wget") },
                        { value: "go", label: Translation.tr("Go") },
                        { value: "parsed", label: Translation.tr("Parsed") }
                    ]
                }
            ]
        },
        // @slot-end curl_converter
        // @slot-begin json_query
        {
            id: "json_query",
            name: Translation.tr("JSON Query (JSONPath / jq)"),
            category: "dev",
            type: "transformer",
            icon: "manage_search",
            description: Translation.tr("Query, filter and transform JSON with JSONPath or jq expressions"),
            keywords: ["jsonpath", "jq", "jpath", "filter", "extract", "select", "filtrar", "consultar"],
            searchTerms: ["json query", "jsonpath", "jq filter", "query json", "filter json", "extract json"],
            sampleInput: "{\n  \"store\": {\n    \"book\": [\n      {\n        \"category\": \"reference\",\n        \"author\": \"Nigel Rees\",\n        \"title\": \"Sayings of the Century\",\n        \"price\": 8.95\n      },\n      {\n        \"category\": \"fiction\",\n        \"author\": \"Evelyn Waugh\",\n        \"title\": \"Sword of Honour\",\n        \"price\": 12.99\n      },\n      {\n        \"category\": \"fiction\",\n        \"author\": \"Herman Melville\",\n        \"title\": \"Moby Dick\",\n        \"isbn\": \"0-553-21311-3\",\n        \"price\": 8.99\n      },\n      {\n        \"category\": \"fiction\",\n        \"author\": \"J. R. R. Tolkien\",\n        \"title\": \"The Lord of the Rings\",\n        \"isbn\": \"0-395-19395-8\",\n        \"price\": 22.99\n      }\n    ],\n    \"bicycle\": {\n      \"color\": \"red\",\n      \"price\": 399\n    }\n  }\n}",
            defaultOptions: { query: "$.store.book[?(@.price < 10)].title", syntax: "auto", asArray: false },
            options: [
                { id: "query", type: "text", label: Translation.tr("Query"), default: "$.store.book[?(@.price < 10)].title" },
                {
                    id: "syntax",
                    type: "choice",
                    label: Translation.tr("Syntax"),
                    default: "auto",
                    choices: [
                        { value: "auto", label: Translation.tr("Auto") },
                        { value: "jsonpath", label: "JSONPath" },
                        { value: "jq", label: "jq" }
                    ]
                },
                { id: "asArray", type: "toggle", label: Translation.tr("Results as array"), default: false }
            ]
        },
        // @slot-end json_query
        // @slot-begin json_types
        {
            id: "json_types",
            name: Translation.tr("JSON → Types"),
            category: "dev",
            type: "transformer",
            icon: "schema",
            description: Translation.tr("Infer TypeScript, Zod, Python, Go, Rust, or JSON Schema types from JSON"),
            keywords: ["types", "typescript", "zod", "python", "golang", "rust", "jsonschema", "interface", "struct", "dataclass", "infer", "codegen"],
            searchTerms: ["json to typescript", "json to types", "json to zod", "json to go struct", "json to rust serde", "json to python dataclass", "json schema generator", "infer types from json"],
            sampleInput: "{\n  \"id\": 1042,\n  \"username\": \"ana_silva\",\n  \"email\": \"ana@example.com\",\n  \"createdAt\": \"2026-04-12T14:30:00Z\",\n  \"bio\": null,\n  \"address\": {\n    \"street\": \"Av. Paulista, 1000\",\n    \"city\": \"Sao Paulo\",\n    \"zipCode\": \"01310-100\"\n  },\n  \"orders\": [\n    {\n      \"orderId\": \"ord-901\",\n      \"total\": 149.9,\n      \"paid\": true,\n      \"couponCode\": \"SPRING10\"\n    },\n    {\n      \"orderId\": \"ord-902\",\n      \"total\": 80,\n      \"paid\": false\n    }\n  ]\n}",
            defaultOptions: { target: "typescript", rootName: "Root" },
            options: [
                {
                    id: "target",
                    type: "choice",
                    label: Translation.tr("Target"),
                    default: "typescript",
                    choices: [
                        { value: "typescript", label: "TypeScript" },
                        { value: "zod", label: "Zod" },
                        { value: "python", label: "Python" },
                        { value: "go", label: "Go" },
                        { value: "rust", label: "Rust" },
                        { value: "jsonschema", label: "JSON Schema" }
                    ]
                },
                {
                    id: "rootName",
                    type: "text",
                    label: Translation.tr("Root name"),
                    default: "Root"
                }
            ]
        },
        // @slot-end json_types
        // @slot-begin glob_tester
        {
            id: "glob_tester",
            name: Translation.tr("Glob & .gitignore Tester"),
            category: "dev",
            type: "analyzer",
            icon: "filter_alt",
            description: Translation.tr("Test .gitignore rules or shell glob patterns against file and directory paths"),
            keywords: ["glob", "gitignore", ".gitignore", "ignore", "wildcard", "fnmatch", "minimatch"],
            searchTerms: ["glob tester", "gitignore tester", "test gitignore", "glob pattern matcher", "ignore rules", "wildcard matcher"],
            sampleInput: "# Dependencies & logs\nnode_modules/\n*.log\n!important.log\n\n# Root-only build output\n/build\n!build/keep.txt\n\n# Nested docs & escaped hash\ndocs/**/*.pdf\n\\#draft.md\n---\nnode_modules/\nnode_modules/pkg.js\nsrc/app.log\nimportant.log\nbuild/\nbuild/keep.txt\nsrc/build/readme.md\ndocs/guide.pdf\ndocs/a/b/spec.pdf\n#draft.md\nsrc/index.ts",
            defaultOptions: { mode: "gitignore" },
            options: [
                {
                    id: "mode",
                    type: "choice",
                    label: Translation.tr("Mode"),
                    default: "gitignore",
                    choices: [
                        { value: "gitignore", label: Translation.tr(".gitignore") },
                        { value: "glob", label: Translation.tr("Glob") }
                    ]
                }
            ]
        },
        // @slot-end glob_tester
        // @slot-begin semver_tool
        {
            id: "semver_tool",
            name: Translation.tr("Semver"),
            category: "dev",
            type: "analyzer",
            icon: "sell",
            description: Translation.tr("Parse, bump, compare, sort, and test SemVer 2.0.0 versions and node-semver ranges"),
            keywords: ["semver", "version", "versao", "range", "prerelease", "npm", "bump", "satisfies", "caret", "tilde"],
            searchTerms: ["semantic version", "semver range", "version comparison", "semver parser", "npm version range", "bump version", "sort versions"],
            sampleInput: "^1.2.3\n1.2.2\n1.2.3\n1.2.4-alpha.1\n1.3.0\n1.5.2-rc.1\n1.9.0\n2.0.0-alpha.1\n2.0.0",
            defaultOptions: { includePrerelease: false, loose: false, order: "asc", pre: "rc" },
            options: [
                { id: "includePrerelease", type: "toggle", label: Translation.tr("Include prereleases"), default: false },
                { id: "loose", type: "toggle", label: Translation.tr("Loose / coerce"), default: false },
                {
                    id: "order",
                    type: "choice",
                    label: Translation.tr("Sort"),
                    default: "asc",
                    choices: [
                        { value: "asc", label: Translation.tr("Asc") },
                        { value: "desc", label: Translation.tr("Desc") }
                    ]
                },
                { id: "pre", type: "text", label: Translation.tr("Pre ID"), default: "rc" }
            ]
        },
        // @slot-end semver_tool
        // @slot-begin commit_lint
        {
            id: "commit_lint",
            name: Translation.tr("Conventional Commits"),
            category: "dev",
            type: "analyzer",
            icon: "commit",
            description: Translation.tr("Lint a Conventional Commit message or turn a git log into a Markdown changelog"),
            keywords: ["commit", "conventional", "commitlint", "changelog", "lint", "git log"],
            searchTerms: ["conventional commits", "commit lint", "commit message validator", "changelog generator", "git log changelog", "commitlint"],
            sampleInput: "a3f91c2 feat(auth)!: require PKCE for OAuth2\n8b14e09 feat(search): add fuzzy tool matching\n4d2c7a1 fix(panel): stop tooltip edge clipping\ne901b54 perf(render): cache parsed icon glyphs\n19f3a88 docs: document DevTools shortcuts\n7c02d11 ci: run QV4 check on pull requests\nf558e20 Merge PR #142 from dev/fix-focus",
            defaultOptions: { maxHeader: 72, version: "", types: "" },
            options: [
                {
                    id: "maxHeader",
                    type: "choice",
                    label: Translation.tr("Max header"),
                    default: 72,
                    choices: [
                        { value: 50, label: "50" },
                        { value: 72, label: "72" },
                        { value: 100, label: "100" }
                    ]
                },
                { id: "version", type: "text", label: Translation.tr("Version"), default: "" },
                { id: "types", type: "text", label: Translation.tr("Types (blank = default)"), default: "" }
            ]
        },
        // @slot-end commit_lint
        // @slot-begin regex_explainer
        {
            id: "regex_explainer",
            name: Translation.tr("Regex Explainer"),
            category: "text",
            type: "analyzer",
            icon: "account_tree",
            description: Translation.tr("Parse and explain JavaScript regular expressions as a tree with groups, flags and safety warnings"),
            keywords: ["explain", "explainer", "explicar", "pattern", "pcre", "ast", "backtracking", "redos", "syntax"],
            searchTerms: ["regex explainer", "explain regex", "regular expression explainer", "regex parser", "regex tree", "explicar regex"],
            sampleInput: "/^(?<user>[\\w.-]+)@(?<host>(?:[a-z0-9-]+\\.)+[a-z]{2,})$/iu",
            defaultOptions: { view: "full", showSpans: false },
            options: [
                {
                    id: "view",
                    type: "choice",
                    label: Translation.tr("View"),
                    default: "full",
                    choices: [
                        { value: "full", label: Translation.tr("Full") },
                        { value: "tree", label: Translation.tr("Tree only") },
                        { value: "summary", label: Translation.tr("Summary") }
                    ]
                },
                { id: "showSpans", type: "toggle", label: Translation.tr("Offsets"), default: false }
            ]
        },
        // @slot-end regex_explainer
        // @slot-begin log_formatter
        {
            id: "log_formatter",
            name: Translation.tr("Log & Stack Trace Reader"),
            category: "dev",
            type: "analyzer",
            icon: "troubleshoot",
            description: Translation.tr("Strip ANSI codes and timestamps, collapse repeats, filter levels and summarize stack traces"),
            keywords: ["log", "logs", "stack", "trace", "stacktrace", "traceback", "panic", "ansi", "journalctl", "quickshell"],
            searchTerms: ["log reader", "log formatter", "stack trace reader", "python traceback", "qml warning", "strip ansi", "parse logs"],
            sampleInput: "\x1b[36m15:04:50.120\x1b[0m INFO  [server] Listening on :8080\n\x1b[33m15:04:51.005 WARN  [cache] Pool full, retrying\x1b[0m\n\x1b[33m15:04:51.410 WARN  [cache] Pool full, retrying\x1b[0m\n\x1b[33m15:04:51.820 WARN  [cache] Pool full, retrying\x1b[0m\n\x1b[31m15:04:52.300 ERROR [worker] Job #42 failed\x1b[0m\nTraceback (most recent call last):\n  File \"/usr/lib/python3/site-packages/celery.py\", line 47, in run\n    return fn(*args)\n  File \"/app/sync.py\", line 83, in run_sync\n    raise ValueError(\"bad url\")\nValueError: bad url\n15:04:53.150 WARN  file:///ui/Bar.qml:42:9: TypeError: null",
            defaultOptions: { level: "all", stripTimestamps: true, collapse: true, framesOnly: false },
            options: [
                {
                    id: "level",
                    type: "choice",
                    label: Translation.tr("Min level"),
                    default: "all",
                    choices: [
                        { value: "all", label: Translation.tr("All") },
                        { value: "debug", label: Translation.tr("Debug") },
                        { value: "info", label: Translation.tr("Info") },
                        { value: "warn", label: Translation.tr("Warn") },
                        { value: "error", label: Translation.tr("Error") }
                    ]
                },
                { id: "stripTimestamps", type: "toggle", label: Translation.tr("Strip timestamps"), default: true },
                { id: "collapse", type: "toggle", label: Translation.tr("Collapse repeats"), default: true },
                { id: "framesOnly", type: "toggle", label: Translation.tr("App frame only"), default: false }
            ]
        },
        // @slot-end log_formatter
        // @slot-begin markdown_table
        {
            id: "markdown_table",
            name: Translation.tr("Markdown Table"),
            category: "converters",
            type: "transformer",
            icon: "table_chart",
            description: Translation.tr("Format and convert tables across Markdown, CSV, TSV, JSON and HTML"),
            keywords: ["markdown", "md", "mdtable", "tsv", "gfm"],
            searchTerms: ["markdown table", "csv to markdown", "json to markdown", "tsv to markdown", "format markdown table", "table formatter", "html table"],
            sampleInput: "Name,Role,Score\n\"Silva, José\",Engineer,98.5\nAda Lovelace,Mathematician,100\nYūki Tanaka,Designer,94.2",
            defaultOptions: { from: "auto", to: "markdown", align: "auto", compact: false, header: true },
            options: [
                {
                    id: "from",
                    type: "choice",
                    label: Translation.tr("From"),
                    default: "auto",
                    choices: [
                        { value: "auto", label: Translation.tr("Auto") },
                        { value: "markdown", label: "Markdown" },
                        { value: "csv", label: "CSV" },
                        { value: "tsv", label: "TSV" },
                        { value: "json", label: "JSON" },
                        { value: "spaces", label: Translation.tr("Spaces") }
                    ]
                },
                {
                    id: "to",
                    type: "choice",
                    label: Translation.tr("To"),
                    default: "markdown",
                    choices: [
                        { value: "markdown", label: "Markdown" },
                        { value: "csv", label: "CSV" },
                        { value: "tsv", label: "TSV" },
                        { value: "json", label: "JSON" },
                        { value: "html", label: "HTML" }
                    ]
                },
                {
                    id: "align",
                    type: "choice",
                    label: Translation.tr("Align"),
                    default: "auto",
                    choices: [
                        { value: "auto", label: Translation.tr("Auto") },
                        { value: "left", label: Translation.tr("Left") },
                        { value: "center", label: Translation.tr("Center") },
                        { value: "right", label: Translation.tr("Right") }
                    ]
                },
                { id: "compact", type: "toggle", label: Translation.tr("Compact"), default: false },
                { id: "header", type: "toggle", label: Translation.tr("Header row"), default: true }
            ]
        },
        // @slot-end markdown_table
        // @slot-begin hypr_keybind
        {
            id: "hypr_keybind",
            name: Translation.tr("Hyprland Keybind"),
            category: "dev",
            type: "transformer",
            icon: "keyboard",
            description: Translation.tr("Convert between Hyprland Lua (hl.bind), hyprland.conf, and human keybinds with dispatcher validation"),
            keywords: ["hyprland", "keybind", "keybinds", "bind", "shortcut", "hotkey", "hl.bind", "keymap", "atalho"],
            searchTerms: ["hyprland keybind", "hyprland bind converter", "hl.bind", "hyprland.conf bind", "validate keybind", "shortcut converter", "keybind table"],
            sampleInput: "bind = SUPER SHIFT, T, exec, kitty\nbindl = , Print, exec, grim\nSuper+Q: killactive\nCtrl+Alt+Delete → exit\nhl.bind(\"SUPER + D\", hl.dsp.window.float({ action = \"toggle\" }))\nbind = SUPER, B, movefocsu, l",
            defaultOptions: { to: "lua" },
            options: [
                {
                    id: "to",
                    type: "choice",
                    label: Translation.tr("Output"),
                    default: "lua",
                    choices: [
                        { value: "lua", label: "Lua (hl.bind)" },
                        { value: "conf", label: "hyprland.conf" },
                        { value: "table", label: Translation.tr("Table") }
                    ]
                }
            ]
        },
        // @slot-end hypr_keybind

        // ── Images (cheatsheet page only) ──
        {
            id: "image_compress",
            name: Translation.tr("Photo Compressor"),
            category: "media",
            type: "image",
            pageOnly: true,
            icon: "photo_size_select_large",
            description: Translation.tr("Shrink a photo or convert it to JPEG, WebP, AVIF, JPEG XL, PNG and more, with the real size before saving"),
            keywords: ["compress", "comprimir", "image", "imagem", "photo", "foto", "jpeg", "jpg", "webp", "avif", "jxl", "png", "resize", "optimize"],
            searchTerms: ["photo compressor", "image compressor", "compress image", "convert image", "image converter", "reduce image size"],
            sampleInput: "",
            defaultOptions: {},
            options: []
        }
    ]

    function byId(id: string): var {
        return root.tools.find(tool => tool.id === id) ?? null;
    }

    function defaultOptionsFor(tool): var {
        const base = Object.assign({}, tool?.defaultOptions ?? {});
        if (tool?.id === "qr_code") {
            base.style = QrCode.style;
            base.decoration = QrCode.decoration;
        }
        return base;
    }

    function run(toolId: string, input = "", options = {}): var {
        return DevToolsEngine.runTool(toolId, input, options);
    }

    function _normalizeText(text: string): string {
        return String(text ?? "")
            .toLocaleLowerCase()
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "");
    }

    // Full searchable text of a tool: id, name, description, command keywords
    // and the natural-language search terms (accent-insensitive).
    function _toolSearchText(tool: var): string {
        const keywordsStr = Array.isArray(tool.keywords) ? tool.keywords.join(" ") : String(tool.keywords ?? "");
        const searchTermsStr = Array.isArray(tool.searchTerms) ? tool.searchTerms.join(" ") : String(tool.searchTerms ?? "");
        return root._normalizeText([tool.id, tool.name, tool.description, keywordsStr, searchTermsStr].join(" "));
    }

    function _browseTerms(queryText: string): var {
        const stopwords = [
            "the", "and", "for", "with", "from", "of", "to", "in", "on", "a", "an"
        ];
        return root._normalizeText(queryText)
            .split(/[^a-z0-9]+/)
            .filter(term => term.length >= 3 && !stopwords.includes(term));
    }

    function _termMatchesText(term: string, text: string, words: var): bool {
        if (text.includes(term))
            return true;
        for (const word of words) {
            if (word.length >= 3 && (word.startsWith(term) || term.startsWith(word)))
                return true;
        }
        return false;
    }

    // Tools whose searchable text is hit by every browse term.
    function _toolsMatchingBrowse(terms: var): var {
        if (terms.length === 0)
            return [];
        return root.searchTools.filter(tool => {
            const text = root._toolSearchText(tool);
            const words = text.split(/[^a-z0-9]+/).filter(w => w.length > 0);
            return terms.every(term => root._termMatchesText(term, text, words));
        });
    }

    function search(queryText: string, category = "all", includePageOnly = false): var {
        const query = root._normalizeText(queryText).trim();
        const terms = query.split(/\s+/).filter(t => t.length > 0);

        return (includePageOnly ? root.tools : root.searchTools).filter(tool => {
            if (category !== "all" && tool.category !== category) {
                return false;
            }
            if (terms.length === 0) {
                return true;
            }
            const fullText = root._toolSearchText(tool);
            return terms.every(term => root._normalizeText(term).length > 0 && fullText.includes(root._normalizeText(term)));
        });
    }

    function inlineMatches(queryText: string): var {
        const query = String(queryText ?? "").trim().toLocaleLowerCase();
        if (query.length < 2)
            return [];

        const generic = ["tool", "tools", "devtools", "generator", "generators", "generate"];
        const isGeneric = generic.some(t => t === query);

        // Browse matching: natural-language queries ("color converter",
        // "word counter", "binary") discover tools without knowing
        // their command keywords. Every term must hit the tool's searchable
        // text (id, name, description, keywords and searchTerms).
        const browseTerms = root._browseTerms(query);
        const browseResults = root._toolsMatchingBrowse(browseTerms);
        const seen = [];

        // Direct tool commands (e.g. "b64 hello", "uuid", "password", "json {...}")
        const results = [];
        for (const tool of root.searchTools) {
            if (isGeneric) {
                if (!seen.includes(tool.id)) {
                    seen.push(tool.id);
                    results.push({ tool, query, arg: "" });
                }
                continue;
            }
            // Check direct keyword match or prefix command
            const matchedKeyword = (tool.keywords ?? []).find(kw => {
                if (query === kw) return true;
                if (query.startsWith(kw + " ") || query.startsWith(kw + ":")) return true;
                return false;
            });
            if (!matchedKeyword)
                continue;
            const arg = query.startsWith(matchedKeyword) ? query.slice(matchedKeyword.length).replace(/^[:\s]+/, "") : "";
            // If the remainder names another tool ("decode jwt",
            // "color converter"), the query is discovery, not data: let
            // browse matching answer it instead of feeding a tool name to
            // the engine.
            if (arg.length > 0 && root._toolsMatchingBrowse(root._browseTerms(arg)).length > 0)
                continue;
            if (!seen.includes(tool.id)) {
                seen.push(tool.id);
                results.push({ tool, query, arg });
            }
        }
        for (const tool of browseResults) {
            if (!seen.includes(tool.id)) {
                seen.push(tool.id);
                results.push({ tool, query, arg: "" });
            }
        }
        return results;
    }
}
