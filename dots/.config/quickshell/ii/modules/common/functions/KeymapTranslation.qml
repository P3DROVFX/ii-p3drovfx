pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell

/**
 * Layout-aware search helpers.
 *
 * Someone searching with the wrong keyboard layout active types the right keys
 * and gets the wrong characters. Mapping the query back through the physical
 * layout recovers the intent without asking them to notice and switch first.
 *
 * Ported from end-4/dots-hyprland#3447.
 */
Singleton {
    id: root

    // Physical layout maps. Bidirectional pairs are generated in the IIFE below.
    readonly property var layouts: (function () {
            const list = [
                {
                    name: "uk",
                    map: {
                        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u",
                        "ш": "i", "щ": "o", "з": "p", "х": "[", "ї": "]",
                        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U",
                        "Ш": "I", "Щ": "O", "З": "P", "Х": "{", "Ї": "}",
                        "ф": "a", "і": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j",
                        "л": "k", "д": "l", "ж": ";", "є": "'",
                        "Ф": "A", "І": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J",
                        "Л": "K", "Д": "L", "Ж": ":", "Є": '"',
                        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
                        "б": ",", "ю": ".",
                        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M",
                        "Б": "<", "Ю": ">"
                    }
                },
                {
                    name: "ru",
                    map: {
                        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u",
                        "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
                        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j",
                        "л": "k", "д": "l", "ж": ";", "э": "'",
                        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
                        "б": ",", "ю": "."
                    }
                },
                {
                    name: "de",
                    map: {
                        "y": "z", "Y": "Z", "z": "y", "Z": "Y",
                        "ü": "[", "Ü": "{", "ö": ";", "Ö": ":", "ä": "'", "Ä": '"', "ß": "-"
                    }
                },
                {
                    name: "fr",
                    map: {
                        "a": "q", "A": "Q", "z": "w", "Z": "W", "q": "a", "Q": "A", "w": "z", "W": "Z",
                        "é": "2", "è": "7", "ê": "[", "à": "0", "ù": "`", "ç": "9", "œ": "p",
                        "m": ";", "M": ":", ";": "m", ":": "M"
                    }
                },
                {
                    // ABNT2 — the layout this fork's author actually types on.
                    name: "br",
                    map: {
                        "ç": ";", "Ç": ":", "´": "[", "`": "{", "[": "'", "{": '"',
                        "]": "\\\\", "}": "|", "/": "?", ";": "/", ":": "?"
                    }
                }
            ];

            // Make all layout maps bidirectional (for example, add "q":"й" for "uk").
            for (const layout of list) {
                const reversePairs = {};
                for (const key in layout.map) {
                    const value = layout.map[key];
                    if (layout.map[value] === undefined)
                        reversePairs[value] = key;
                }
                Object.assign(layout.map, reversePairs);
            }

            return list;
        })()

    // Compact Cyrillic-to-Latin transliteration for search.
    readonly property var cyrillicToLatin: ({
            "а": "a", "б": "b", "в": "v", "г": "g", "ґ": "g",
            "д": "d", "е": "e", "є": "e", "ж": "z", "з": "z",
            "и": "i", "і": "i", "ї": "i", "й": "y", "к": "k",
            "л": "l", "м": "m", "н": "n", "о": "o", "п": "p",
            "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
            "х": "h", "ц": "c", "ч": "c", "ш": "s", "щ": "s",
            "ь": "", "ъ": "", "ю": "u", "я": "a",
            "ы": "y", "э": "e", "ё": "o",
            "А": "A", "Б": "B", "В": "V", "Г": "G", "Ґ": "G",
            "Д": "D", "Е": "E", "Є": "E", "Ж": "Z", "З": "Z",
            "И": "I", "І": "I", "Ї": "I", "Й": "Y", "К": "K",
            "Л": "L", "М": "M", "Н": "N", "О": "O", "П": "P",
            "Р": "R", "С": "S", "Т": "T", "У": "U", "Ф": "F",
            "Х": "H", "Ц": "C", "Ч": "C", "Ш": "S", "Щ": "S",
            "Ь": "", "Ъ": "", "Ю": "U", "Я": "A",
            "Ы": "Y", "Э": "E", "Ё": "O"
        })

    function mapWithLayout(text: string, layoutName: string): string {
        const layout = root.layouts.find(candidate => candidate.name === layoutName);
        if (!layout)
            return text;
        return text.split("").map(character => {
            const mapped = layout.map[character];
            return mapped !== undefined ? mapped : character;
        }).join("");
    }

    /**
     * Unique layout-corrected variants, in both directions for every layout.
     * The input itself is never returned — the caller already searched it.
     */
    function translateAll(text: string): var {
        if (!text)
            return [];

        const results = [];
        const seen = new Set([text]);

        for (const layout of root.layouts) {
            const translated = root.mapWithLayout(text, layout.name);
            if (!seen.has(translated)) {
                seen.add(translated);
                results.push(translated);
            }
        }
        return results;
    }

    /**
     * Transliterated Latin text, or "" when the input holds no Cyrillic.
     * The guard matters: without it every ASCII query pays for a pointless pass.
     */
    function transliterate(text: string): string {
        if (!text || !/[Ѐ-ӿԀ-ԯ]/.test(text))
            return "";
        const table = root.cyrillicToLatin;
        return text.split("").map(character => {
            const mapped = table[character];
            return mapped !== undefined ? mapped : character;
        }).join("").replace(/\s+/g, " ").trim();
    }
}
