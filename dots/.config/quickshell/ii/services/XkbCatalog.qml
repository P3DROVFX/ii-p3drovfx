pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The X keyboard catalogue, parsed from `/usr/share/X11/xkb/rules/base.lst`.
 *
 * Every layout, variant, model and option the system knows about, with the descriptions
 * setxkbmap itself uses. Loaded on demand: nothing reads this file until something asks for a
 * layout list, and it is then parsed once for the lifetime of the shell.
 *
 * `HyprlandXkb` reports which layout is *active*; this reports which ones *exist*.
 */
Singleton {
    id: root

    readonly property string source: "/usr/share/X11/xkb/rules/base.lst"

    /// [{ code, name }] - "fr", "French"
    property var layouts: []
    /// layout code -> [{ code, name }] - "fr" -> [{ code: "latin9", name: "French (legacy, alt.)" }]
    property var variants: ({})
    /// [{ code, name }] - "pc105", "Generic 105-key PC"
    property var models: []
    /// [{ code, name, group }] - "caps:escape", "Make Caps Lock an additional Esc", "caps"
    property var options: []

    property bool loaded: false
    property bool failed: false

    /// The shortlist the Welcome flow offers, in the languages' own names. Kept here so the
    /// Welcome page and the settings picker cannot drift apart.
    readonly property var commonLayouts: [
        { "code": "us", "label": "English (US)" },
        { "code": "gb", "label": "English (UK)" },
        { "code": "br", "label": "Português (Brasil)" },
        { "code": "de", "label": "Deutsch" },
        { "code": "fr", "label": "Français" },
        { "code": "es", "label": "Español" },
        { "code": "it", "label": "Italiano" },
        { "code": "pt", "label": "Português" },
        { "code": "ru", "label": "Русский" },
        { "code": "uk", "label": "Українська" },
        { "code": "tr", "label": "Türkçe" },
        { "code": "pl", "label": "Polski" },
        { "code": "cz", "label": "Čeština" },
        { "code": "hu", "label": "Magyar" },
        { "code": "se", "label": "Svenska" },
        { "code": "no", "label": "Norsk" },
        { "code": "dk", "label": "Dansk" },
        { "code": "fi", "label": "Suomi" },
        { "code": "gr", "label": "Ελληνικά" },
        { "code": "il", "label": "עברית" },
        { "code": "jp", "label": "日本語" },
        { "code": "kr", "label": "한국어" },
        { "code": "cn", "label": "简体中文" },
        { "code": "in", "label": "English (India)" },
        { "code": "latam", "label": "Español (Latinoamérica)" }
    ]

    /// Read the catalogue if it has not been read yet. Safe to call from every onCompleted.
    function load() {
        if (root.loaded || readProc.running) return;
        readProc.running = true;
    }

    function layoutName(code: string): string {
        const hit = root.layouts.find(layout => layout.code === code);
        return hit ? hit.name : code;
    }

    function variantName(layout: string, variant: string): string {
        const hit = (root.variants[layout] ?? []).find(entry => entry.code === variant);
        return hit ? hit.name : variant;
    }

    /// One flat, searchable row per layout and per variant, which is how the picker shows them:
    /// choosing "French (legacy, alt.)" sets kb_layout and kb_variant in one go.
    function pickerRows(): var {
        const rows = [];
        for (const layout of root.layouts) {
            rows.push({ "layout": layout.code, "variant": "", "name": layout.name });
            for (const variant of (root.variants[layout.code] ?? []))
                rows.push({ "layout": layout.code, "variant": variant.code, "name": variant.name });
        }
        return rows;
    }

    function _parse(text: string) {
        const layouts = [];
        const variants = {};
        const models = [];
        const options = [];
        let section = "";
        for (const raw of text.split("\n")) {
            if (raw.startsWith("!")) {
                section = raw.slice(1).trim().split(/\s+/)[0];
                continue;
            }
            // Qt's JS engine has no String.trimEnd.
            const line = raw.replace(/\s+$/, "");
            if (line.length === 0 || !line.startsWith(" ")) continue;
            if (section === "variant") {
                // "  latin9          fr: French (legacy, alt.)"
                const match = line.match(/^\s+(\S+)\s+(\S+):\s*(.*)$/);
                if (!match) continue;
                if (variants[match[2]] === undefined) variants[match[2]] = [];
                variants[match[2]].push({ "code": match[1], "name": match[3] });
                continue;
            }
            const match = line.match(/^\s+(\S+)\s+(.*)$/);
            if (!match) continue;
            const entry = { "code": match[1], "name": match[2].trim() };
            if (section === "layout") layouts.push(entry);
            else if (section === "model") models.push(entry);
            else if (section === "option") options.push(Object.assign({
                "group": entry.code.split(":")[0]
            }, entry));
        }
        root.layouts = layouts;
        root.variants = variants;
        root.models = models;
        root.options = options;
        root.loaded = layouts.length > 0;
        root.failed = layouts.length === 0;
    }

    Process {
        id: readProc
        command: ["cat", root.source]
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
        onExited: (code, status) => {
            if (code !== 0) root.failed = true;
        }
    }
}
