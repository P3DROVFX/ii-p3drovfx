// We're going to use ydotool
// See /usr/include/linux/input-event-codes.h for keycodes

const defaultLayout = "English (US)";
const byName = {
    "English (US)": {
        name_short: "US",
        description: "QWERTY - Full",
        comment: "Like physical keyboard",
        // A key looks like this: { k: "a", ks: "A", t: "normal" } (key, key-shift, type)
        // key types are: normal, tab, caps, shift, control, fn (normal w/ half height), space, expand
        // keys: [
        //     [{ k: "Esc", t: "fn" }, { k: "F1", t: "fn" }, { k: "F2", t: "fn" }, { k: "F3", t: "fn" }, { k: "F4", t: "fn" }, { k: "F5", t: "fn" }, { k: "F6", t: "fn" }, { k: "F7", t: "fn" }, { k: "F8", t: "fn" }, { k: "F9", t: "fn" }, { k: "F10", t: "fn" }, { k: "F11", t: "fn" }, { k: "F12", t: "fn" }, { k: "PrtSc", t: "fn" }, { k: "Del", t: "fn" }],
        //     [{ k: "`", ks: "~", t: "normal" }, { k: "1", ks: "!", t: "normal" }, { k: "2", ks: "@", t: "normal" }, { k: "3", ks: "#", t: "normal" }, { k: "4", ks: "$", t: "normal" }, { k: "5", ks: "%", t: "normal" }, { k: "6", ks: "^", t: "normal" }, { k: "7", ks: "&", t: "normal" }, { k: "8", ks: "*", t: "normal" }, { k: "9", ks: "(", t: "normal" }, { k: "0", ks: ")", t: "normal" }, { k: "-", ks: "_", t: "normal" }, { k: "=", ks: "+", t: "normal" }, { k: "Backspace", t: "shift" }],
        //     [{ k: "Tab", t: "tab" }, { k: "q", ks: "Q", t: "normal" }, { k: "w", ks: "W", t: "normal" }, { k: "e", ks: "E", t: "normal" }, { k: "r", ks: "R", t: "normal" }, { k: "t", ks: "T", t: "normal" }, { k: "y", ks: "Y", t: "normal" }, { k: "u", ks: "U", t: "normal" }, { k: "i", ks: "I", t: "normal" }, { k: "o", ks: "O", t: "normal" }, { k: "p", ks: "P", t: "normal" }, { k: "[", ks: "{", t: "normal" }, { k: "]", ks: "}", t: "normal" }, { k: "\\", ks: "|", t: "expand" }],
        //     [{ k: "Caps", t: "caps" }, { k: "a", ks: "A", t: "normal" }, { k: "s", ks: "S", t: "normal" }, { k: "d", ks: "D", t: "normal" }, { k: "f", ks: "F", t: "normal" }, { k: "g", ks: "G", t: "normal" }, { k: "h", ks: "H", t: "normal" }, { k: "j", ks: "J", t: "normal" }, { k: "k", ks: "K", t: "normal" }, { k: "l", ks: "L", t: "normal" }, { k: ";", ks: ":", t: "normal" }, { k: "'", ks: '"', t: "normal" }, { k: "Enter", t: "expand" }],
        //     [{ k: "Shift", t: "shift" }, { k: "z", ks: "Z", t: "normal" }, { k: "x", ks: "X", t: "normal" }, { k: "c", ks: "C", t: "normal" }, { k: "v", ks: "V", t: "normal" }, { k: "b", ks: "B", t: "normal" }, { k: "n", ks: "N", t: "normal" }, { k: "m", ks: "M", t: "normal" }, { k: ",", ks: "<", t: "normal" }, { k: ".", ks: ">", t: "normal" }, { k: "/", ks: "?", t: "normal" }, { k: "Shift", t: "expand" }],
        //     [{ k: "Ctrl", t: "control" }, { k: "Fn", t: "normal" }, { k: "Win", t: "normal" }, { k: "Alt", t: "normal" }, { k: "Space", t: "space" }, { k: "Alt", t: "normal" }, { k: "Menu", t: "normal" }, { k: "Ctrl", t: "control" }]
        // ]
        // A normal key looks like this: {label: "a", labelShift: "A", shape: "normal", keycode: 30, type: "normal"}
        // A modkey looks like this: {label: "Ctrl", shape: "control", keycode: 29, type: "modkey"}
        // key types are: normal, tab, caps, shift, control, fn (normal w/ half height), space, expand
        keys: [
            [
                { keytype: "normal", label: "Esc", shape: "fn", keycode: 1 },
                { keytype: "normal", label: "F1", shape: "fn", keycode: 59 },
                { keytype: "normal", label: "F2", shape: "fn", keycode: 60 },
                { keytype: "normal", label: "F3", shape: "fn", keycode: 61 },
                { keytype: "normal", label: "F4", shape: "fn", keycode: 62 },
                { keytype: "normal", label: "F5", shape: "fn", keycode: 63 },
                { keytype: "normal", label: "F6", shape: "fn", keycode: 64 },
                { keytype: "normal", label: "F7", shape: "fn", keycode: 65 },
                { keytype: "normal", label: "F8", shape: "fn", keycode: 66 },
                { keytype: "normal", label: "F9", shape: "fn", keycode: 67 },
                { keytype: "normal", label: "F10", shape: "fn", keycode: 68 },
                { keytype: "normal", label: "F11", shape: "fn", keycode: 87 },
                { keytype: "normal", label: "F12", shape: "fn", keycode: 88 },
                { keytype: "normal", label: "PrtSc", shape: "fn", keycode: 99 },
                { keytype: "normal", label: "Del", shape: "fn", keycode: 111 }
            ],
            [
                { keytype: "normal", label: "`", labelShift: "~", shape: "normal", keycode: 41 },
                { keytype: "normal", label: "1", labelShift: "!", shape: "normal", keycode: 2 },
                { keytype: "normal", label: "2", labelShift: "@", shape: "normal", keycode: 3 },
                { keytype: "normal", label: "3", labelShift: "#", shape: "normal", keycode: 4 },
                { keytype: "normal", label: "4", labelShift: "$", shape: "normal", keycode: 5 },
                { keytype: "normal", label: "5", labelShift: "%", shape: "normal", keycode: 6 },
                { keytype: "normal", label: "6", labelShift: "^", shape: "normal", keycode: 7 },
                { keytype: "normal", label: "7", labelShift: "&", shape: "normal", keycode: 8 },
                { keytype: "normal", label: "8", labelShift: "*", shape: "normal", keycode: 9 },
                { keytype: "normal", label: "9", labelShift: "(", shape: "normal", keycode: 10 },
                { keytype: "normal", label: "0", labelShift: ")", shape: "normal", keycode: 11 },
                { keytype: "normal", label: "-", labelShift: "_", shape: "normal", keycode: 12 },
                { keytype: "normal", label: "=", labelShift: "+", shape: "normal", keycode: 13 },
                { keytype: "normal", label: "Backspace", shape: "expand", keycode: 14 }
            ],
            [
                { keytype: "normal", label: "Tab", shape: "tab", keycode: 15 },
                { keytype: "normal", label: "q", labelShift: "Q", shape: "normal", keycode: 16 },
                { keytype: "normal", label: "w", labelShift: "W", shape: "normal", keycode: 17 },
                { keytype: "normal", label: "e", labelShift: "E", shape: "normal", keycode: 18 },
                { keytype: "normal", label: "r", labelShift: "R", shape: "normal", keycode: 19 },
                { keytype: "normal", label: "t", labelShift: "T", shape: "normal", keycode: 20 },
                { keytype: "normal", label: "y", labelShift: "Y", shape: "normal", keycode: 21 },
                { keytype: "normal", label: "u", labelShift: "U", shape: "normal", keycode: 22 },
                { keytype: "normal", label: "i", labelShift: "I", shape: "normal", keycode: 23 },
                { keytype: "normal", label: "o", labelShift: "O", shape: "normal", keycode: 24 },
                { keytype: "normal", label: "p", labelShift: "P", shape: "normal", keycode: 25 },
                { keytype: "normal", label: "[", labelShift: "{", shape: "normal", keycode: 26 },
                { keytype: "normal", label: "]", labelShift: "}", shape: "normal", keycode: 27 },
                { keytype: "normal", label: "\\", labelShift: "|", shape: "expand", keycode: 43 }
            ],
            [
                //{ keytype: "normal", label: "Caps", shape: "caps", keycode: 58 }, // not needed as double-pressing shift does that
                { keytype: "spacer", label: "", shape: "empty" },
                { keytype: "spacer", label: "", shape: "empty" },
                { keytype: "normal", label: "a", labelShift: "A", shape: "normal", keycode: 30 },
                { keytype: "normal", label: "s", labelShift: "S", shape: "normal", keycode: 31 },
                { keytype: "normal", label: "d", labelShift: "D", shape: "normal", keycode: 32 },
                { keytype: "normal", label: "f", labelShift: "F", shape: "normal", keycode: 33 },
                { keytype: "normal", label: "g", labelShift: "G", shape: "normal", keycode: 34 },
                { keytype: "normal", label: "h", labelShift: "H", shape: "normal", keycode: 35 },
                { keytype: "normal", label: "j", labelShift: "J", shape: "normal", keycode: 36 },
                { keytype: "normal", label: "k", labelShift: "K", shape: "normal", keycode: 37 },
                { keytype: "normal", label: "l", labelShift: "L", shape: "normal", keycode: 38 },
                { keytype: "normal", label: ";", labelShift: ":", shape: "normal", keycode: 39 },
                { keytype: "normal", label: "'", labelShift: '"', shape: "normal", keycode: 40 },
                { keytype: "normal", label: "Enter", shape: "expand", keycode: 28 }
            ],
            [
                { keytype: "modkey", label: "Shift", labelShift: "Shift", labelCaps: "Caps", shape: "shift", keycode: 42 },
                { keytype: "normal", label: "z", labelShift: "Z", shape: "normal", keycode: 44 },
                { keytype: "normal", label: "x", labelShift: "X", shape: "normal", keycode: 45 },
                { keytype: "normal", label: "c", labelShift: "C", shape: "normal", keycode: 46 },
                { keytype: "normal", label: "v", labelShift: "V", shape: "normal", keycode: 47 },
                { keytype: "normal", label: "b", labelShift: "B", shape: "normal", keycode: 48 },
                { keytype: "normal", label: "n", labelShift: "N", shape: "normal", keycode: 49 },
                { keytype: "normal", label: "m", labelShift: "M", shape: "normal", keycode: 50 },
                { keytype: "normal", label: ",", labelShift: "<", shape: "normal", keycode: 51 },
                { keytype: "normal", label: ".", labelShift: ">", shape: "normal", keycode: 52 },
                { keytype: "normal", label: "/", labelShift: "?", shape: "normal", keycode: 53 },
                { keytype: "modkey", label: "Shift", labelShift: "Shift", labelCaps: "Caps", shape: "expand", keycode: 54 } // optional
            ],
            [
                { keytype: "modkey", label: "Ctrl", shape: "control", keycode: 29 },
                // { label: "Super", shape: "normal", keycode: 125 }, // dangerous
                { keytype: "modkey", label: "Alt", shape: "normal", keycode: 56 },
                { keytype: "normal", label: "Space", shape: "space", keycode: 57 },
                { keytype: "modkey", label: "Alt", shape: "normal", keycode: 100 },
                // { label: "Super", shape: "normal", keycode: 126 }, // dangerous
                { keytype: "normal", label: "Menu", shape: "normal", keycode: 139 },
                { keytype: "modkey", label: "Ctrl", shape: "control", keycode: 97 }
            ]
        ]
    },
    "German": {
        name_short: "DE",
        description: "QWERTZ - Full",
        comment: "Keyboard layout commonly used in German-speaking countries",
        keys: [
            [
                { keytype: "normal", label: "Esc", shape: "fn", keycode: 1 },
                { keytype: "normal", label: "F1", shape: "fn", keycode: 59 },
                { keytype: "normal", label: "F2", shape: "fn", keycode: 60 },
                { keytype: "normal", label: "F3", shape: "fn", keycode: 61 },
                { keytype: "normal", label: "F4", shape: "fn", keycode: 62 },
                { keytype: "normal", label: "F5", shape: "fn", keycode: 63 },
                { keytype: "normal", label: "F6", shape: "fn", keycode: 64 },
                { keytype: "normal", label: "F7", shape: "fn", keycode: 65 },
                { keytype: "normal", label: "F8", shape: "fn", keycode: 66 },
                { keytype: "normal", label: "F9", shape: "fn", keycode: 67 },
                { keytype: "normal", label: "F10", shape: "fn", keycode: 68 },
                { keytype: "normal", label: "F11", shape: "fn", keycode: 87 },
                { keytype: "normal", label: "F12", shape: "fn", keycode: 88 },
                { keytype: "normal", label: "Druck", shape: "fn", keycode: 99 },
                { keytype: "normal", label: "Entf", shape: "fn", keycode: 111 }
            ],
            [
                { keytype: "normal", label: "^", labelShift: "°", labelAlt: "′", shape: "normal", keycode: 41 },
                { keytype: "normal", label: "1", labelShift: "!", labelAlt: "¹", shape: "normal", keycode: 2 },
                { keytype: "normal", label: "2", labelShift: "\"", labelAlt: "²", shape: "normal", keycode: 3 },
                { keytype: "normal", label: "3", labelShift: "§", labelAlt: "³", shape: "normal", keycode: 4 },
                { keytype: "normal", label: "4", labelShift: "$", labelAlt: "¼", shape: "normal", keycode: 5 },
                { keytype: "normal", label: "5", labelShift: "%", labelAlt: "½", shape: "normal", keycode: 6 },
                { keytype: "normal", label: "6", labelShift: "&", labelAlt: "¬", shape: "normal", keycode: 7 },
                { keytype: "normal", label: "7", labelShift: "/", labelAlt: "{", shape: "normal", keycode: 8 },
                { keytype: "normal", label: "8", labelShift: "(", labelAlt: "[", shape: "normal", keycode: 9 },
                { keytype: "normal", label: "9", labelShift: ")", labelAlt: "]", shape: "normal", keycode: 10 },
                { keytype: "normal", label: "0", labelShift: "=", labelAlt: "}", shape: "normal", keycode: 11 },
                { keytype: "normal", label: "ß", labelShift: "?", labelAlt: "\\", shape: "normal", keycode: 12 },
                { keytype: "normal", label: "´", labelShift: "`", labelAlt: "¸", shape: "normal", keycode: 13 },
                { keytype: "normal", label: "⟵", shape: "expand", keycode: 14 }
            ],
            [
                { keytype: "normal", label: "Tab ⇆", shape: "tab", keycode: 15 },
                { keytype: "normal", label: "q", labelShift: "Q", labelAlt: "@", shape: "normal", keycode: 16 },
                { keytype: "normal", label: "w", labelShift: "W", labelAlt: "ſ", shape: "normal", keycode: 17 },
                { keytype: "normal", label: "e", labelShift: "E", labelAlt: "€", shape: "normal", keycode: 18 },
                { keytype: "normal", label: "r", labelShift: "R", labelAlt: "¶", shape: "normal", keycode: 19 },
                { keytype: "normal", label: "t", labelShift: "T", labelAlt: "ŧ", shape: "normal", keycode: 20 },
                { keytype: "normal", label: "z", labelShift: "Z", labelAlt: "←", shape: "normal", keycode: 21 },
                { keytype: "normal", label: "u", labelShift: "U", labelAlt: "↓", shape: "normal", keycode: 22 },
                { keytype: "normal", label: "i", labelShift: "I", labelAlt: "→", shape: "normal", keycode: 23 },
                { keytype: "normal", label: "o", labelShift: "O", labelAlt: "ø", shape: "normal", keycode: 24 },
                { keytype: "normal", label: "p", labelShift: "P", labelAlt: "þ", shape: "normal", keycode: 25 },
                { keytype: "normal", label: "ü", labelShift: "Ü", labelAlt: "¨", shape: "normal", keycode: 26 },
                { keytype: "normal", label: "+", labelShift: "*", labelAlt: "~", shape: "normal", keycode: 27 },
                { keytype: "normal", label: "↵", shape: "expand", keycode: 28 }
            ],
            [
                //{ keytype: "normal", label: "Umschalt ⇩", shape: "caps", keycode: 58 },
                { keytype: "spacer", label: "", shape: "empty" },
                { keytype: "spacer", label: "", shape: "empty" },
                { keytype: "normal", label: "a", labelShift: "A", labelAlt: "æ", shape: "normal", keycode: 30 },
                { keytype: "normal", label: "s", labelShift: "S", labelAlt: "ſ", shape: "normal", keycode: 31 },
                { keytype: "normal", label: "d", labelShift: "D", labelAlt: "ð", shape: "normal", keycode: 32 },
                { keytype: "normal", label: "f", labelShift: "F", labelAlt: "đ", shape: "normal", keycode: 33 },
                { keytype: "normal", label: "g", labelShift: "G", labelAlt: "ŋ", shape: "normal", keycode: 34 },
                { keytype: "normal", label: "h", labelShift: "H", labelAlt: "ħ", shape: "normal", keycode: 35 },
                { keytype: "normal", label: "j", labelShift: "J", labelAlt: "", shape: "normal", keycode: 36 },
                { keytype: "normal", label: "k", labelShift: "K", labelAlt: "ĸ", shape: "normal", keycode: 37 },
                { keytype: "normal", label: "l", labelShift: "L", labelAlt: "ł", shape: "normal", keycode: 38 },
                { keytype: "normal", label: "ö", labelShift: "Ö", labelAlt: "˝", shape: "normal", keycode: 39 },
                { keytype: "normal", label: "ä", labelShift: 'Ä', labelAlt: "^", shape: "normal", keycode: 40 },
                { keytype: "normal", label: "#", labelShift: '\'', labelAlt: "’", shape: "normal", keycode: 43 },
                { keytype: "spacer", label: "", shape: "empty" },
                //{ keytype: "normal", label: "↵", shape: "expand", keycode: 28 }
            ],
            [
                { keytype: "modkey", label: "Shift", labelShift: "Shift ⇧", labelCaps: "Locked ⇩", shape: "shift", keycode: 42 },
                { keytype: "normal", label: "<", labelShift: ">", labelAlt: "|", shape: "normal", keycode: 86 },
                { keytype: "normal", label: "y", labelShift: "Y", labelAlt: "»", shape: "normal", keycode: 44 },
                { keytype: "normal", label: "x", labelShift: "X", labelAlt: "«", shape: "normal", keycode: 45 },
                { keytype: "normal", label: "c", labelShift: "C", labelAlt: "¢", shape: "normal", keycode: 46 },
                { keytype: "normal", label: "v", labelShift: "V", labelAlt: "„", shape: "normal", keycode: 47 },
                { keytype: "normal", label: "b", labelShift: "B", labelAlt: "“", shape: "normal", keycode: 48 },
                { keytype: "normal", label: "n", labelShift: "N", labelAlt: "”", shape: "normal", keycode: 49 },
                { keytype: "normal", label: "m", labelShift: "M", labelAlt: "µ", shape: "normal", keycode: 50 },
                { keytype: "normal", label: ",", labelShift: ";", labelAlt: "·", shape: "normal", keycode: 51 },
                { keytype: "normal", label: ".", labelShift: ":", labelAlt: "…", shape: "normal", keycode: 52 },
                { keytype: "normal", label: "-", labelShift: "_", labelAlt: "–", shape: "normal", keycode: 53 },
                { keytype: "modkey", label: "Shift", labelShift: "Shift ⇧", labelCaps: "Locked ⇩", shape: "expand", keycode: 54 }, // optional
            ],
            [
                { keytype: "modkey", label: "Strg", shape: "control", keycode: 29 },
                //{ keytype: "normal", label: "", shape: "normal", keycode: 125 }, // dangerous
                { keytype: "modkey", label: "Alt", shape: "normal", keycode: 56 },
                { keytype: "normal", label: "Leertaste", shape: "space", keycode: 57 },
                { keytype: "modkey", label: "Alt Gr", shape: "normal", keycode: 100 },
                // { label: "Super", shape: "normal", keycode: 126 }, // dangerous
                //{ keytype: "normal", label: "Menu", shape: "normal", keycode: 139 }, // doesn't work?
                { keytype: "modkey", label: "Strg", shape: "control", keycode: 97 },
                { keytype: "normal", label: "⇦", shape: "normal", keycode: 105 },
                { keytype: "normal", label: "⇨", shape: "normal", keycode: 106 },
            ]
        ]
    },
    "Russian": {
        name_short: "RU",
        description: "ЙЦУКЕН - Full",
        comment: "Standard Russian keyboard layout",
        keys: [
            [
                { keytype: "normal", label: "Esc", shape: "fn", keycode: 1 },
                { keytype: "normal", label: "F1", shape: "fn", keycode: 59 },
                { keytype: "normal", label: "F2", shape: "fn", keycode: 60 },
                { keytype: "normal", label: "F3", shape: "fn", keycode: 61 },
                { keytype: "normal", label: "F4", shape: "fn", keycode: 62 },
                { keytype: "normal", label: "F5", shape: "fn", keycode: 63 },
                { keytype: "normal", label: "F6", shape: "fn", keycode: 64 },
                { keytype: "normal", label: "F7", shape: "fn", keycode: 65 },
                { keytype: "normal", label: "F8", shape: "fn", keycode: 66 },
                { keytype: "normal", label: "F9", shape: "fn", keycode: 67 },
                { keytype: "normal", label: "F10", shape: "fn", keycode: 68 },
                { keytype: "normal", label: "F11", shape: "fn", keycode: 87 },
                { keytype: "normal", label: "F12", shape: "fn", keycode: 88 },
                { keytype: "normal", label: "PrtSc", shape: "fn", keycode: 99 },
                { keytype: "normal", label: "Del", shape: "fn", keycode: 111 }
            ],
            [
                { keytype: "normal", label: "ё", labelShift: "Ё", shape: "normal", keycode: 41 },
                { keytype: "normal", label: "1", labelShift: "!", shape: "normal", keycode: 2 },
                { keytype: "normal", label: "2", labelShift: "\"", shape: "normal", keycode: 3 },
                { keytype: "normal", label: "3", labelShift: "№", shape: "normal", keycode: 4 },
                { keytype: "normal", label: "4", labelShift: ";", shape: "normal", keycode: 5 },
                { keytype: "normal", label: "5", labelShift: "%", shape: "normal", keycode: 6 },
                { keytype: "normal", label: "6", labelShift: ":", shape: "normal", keycode: 7 },
                { keytype: "normal", label: "7", labelShift: "?", shape: "normal", keycode: 8 },
                { keytype: "normal", label: "8", labelShift: "*", shape: "normal", keycode: 9 },
                { keytype: "normal", label: "9", labelShift: "(", shape: "normal", keycode: 10 },
                { keytype: "normal", label: "0", labelShift: ")", shape: "normal", keycode: 11 },
                { keytype: "normal", label: "-", labelShift: "_", shape: "normal", keycode: 12 },
                { keytype: "normal", label: "=", labelShift: "+", shape: "normal", keycode: 13 },
                { keytype: "normal", label: "Backspace", shape: "expand", keycode: 14 }
            ],
            [
                { keytype: "normal", label: "Tab", shape: "tab", keycode: 15 },
                { keytype: "normal", label: "й", labelShift: "Й", shape: "normal", keycode: 16 },
                { keytype: "normal", label: "ц", labelShift: "Ц", shape: "normal", keycode: 17 },
                { keytype: "normal", label: "у", labelShift: "У", shape: "normal", keycode: 18 },
                { keytype: "normal", label: "к", labelShift: "К", shape: "normal", keycode: 19 },
                { keytype: "normal", label: "е", labelShift: "Е", shape: "normal", keycode: 20 },
                { keytype: "normal", label: "н", labelShift: "Н", shape: "normal", keycode: 21 },
                { keytype: "normal", label: "г", labelShift: "Г", shape: "normal", keycode: 22 },
                { keytype: "normal", label: "ш", labelShift: "Ш", shape: "normal", keycode: 23 },
                { keytype: "normal", label: "щ", labelShift: "Щ", shape: "normal", keycode: 24 },
                { keytype: "normal", label: "з", labelShift: "З", shape: "normal", keycode: 25 },
                { keytype: "normal", label: "х", labelShift: "Х", shape: "normal", keycode: 26 },
                { keytype: "normal", label: "ъ", labelShift: "Ъ", shape: "normal", keycode: 27 },
                { keytype: "normal", label: "\\", labelShift: "/", shape: "expand", keycode: 43 }
            ],
            [
                { keytype: "spacer", label: "", shape: "empty" },
                { keytype: "spacer", label: "", shape: "empty" },
                { keytype: "normal", label: "ф", labelShift: "Ф", shape: "normal", keycode: 30 },
                { keytype: "normal", label: "ы", labelShift: "Ы", shape: "normal", keycode: 31 },
                { keytype: "normal", label: "в", labelShift: "В", shape: "normal", keycode: 32 },
                { keytype: "normal", label: "а", labelShift: "А", shape: "normal", keycode: 33 },
                { keytype: "normal", label: "п", labelShift: "П", shape: "normal", keycode: 34 },
                { keytype: "normal", label: "р", labelShift: "Р", shape: "normal", keycode: 35 },
                { keytype: "normal", label: "о", labelShift: "О", shape: "normal", keycode: 36 },
                { keytype: "normal", label: "л", labelShift: "Л", shape: "normal", keycode: 37 },
                { keytype: "normal", label: "д", labelShift: "Д", shape: "normal", keycode: 38 },
                { keytype: "normal", label: "ж", labelShift: "Ж", shape: "normal", keycode: 39 },
                { keytype: "normal", label: "э", labelShift: "Э", shape: "normal", keycode: 40 },
                { keytype: "normal", label: "Enter", shape: "expand", keycode: 28 }
            ],
            [
                { keytype: "modkey", label: "Shift", shape: "shift", keycode: 42 },
                { keytype: "normal", label: "я", labelShift: "Я", shape: "normal", keycode: 44 },
                { keytype: "normal", label: "ч", labelShift: "Ч", shape: "normal", keycode: 45 },
                { keytype: "normal", label: "с", labelShift: "С", shape: "normal", keycode: 46 },
                { keytype: "normal", label: "м", labelShift: "М", shape: "normal", keycode: 47 },
                { keytype: "normal", label: "и", labelShift: "И", shape: "normal", keycode: 48 },
                { keytype: "normal", label: "т", labelShift: "Т", shape: "normal", keycode: 49 },
                { keytype: "normal", label: "ь", labelShift: "Ь", shape: "normal", keycode: 50 },
                { keytype: "normal", label: "б", labelShift: "Б", shape: "normal", keycode: 51 },
                { keytype: "normal", label: "ю", labelShift: "Ю", shape: "normal", keycode: 52 },
                { keytype: "normal", label: ".", labelShift: ",", shape: "normal", keycode: 53 },
                { keytype: "modkey", label: "Shift", shape: "expand", keycode: 54 }
            ],
            [
                { keytype: "modkey", label: "Ctrl", shape: "control", keycode: 29 },
                { keytype: "modkey", label: "Alt", shape: "normal", keycode: 56 },
                { keytype: "normal", label: "Space", shape: "space", keycode: 57 },
                { keytype: "modkey", label: "Alt", shape: "normal", keycode: 100 },
                { keytype: "normal", label: "Menu", shape: "normal", keycode: 139 },
                { keytype: "modkey", label: "Ctrl", shape: "control", keycode: 97 }
            ]
        ]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deck layouts
//
// Everything above is the classic on-screen keyboard's data and stays as it is.
// What follows is the schema the deck keyboard uses, kept side by side with it.
//
// ydotool injects evdev keycodes and the compositor applies the xkb layout on top, so the
// keycode of a physical position never changes: a layout is a pure relabelling of one fixed
// geometry. Hence a single row definition plus one glyph table per layout.
// ─────────────────────────────────────────────────────────────────────────────

// Every row is exactly deckUnits wide, cluster included, so the columns line up down the deck.
// The arrows are full-size keys rather than the half-height pair a real board uses, which costs
// the extra half unit over a 15u board - Esc, Backspace, Enter and Caps absorb it.
const deckUnits = 15.5;
const deckClusterUnits = 3; // The arrow cluster claims the last 3 units of the bottom two rows
const deckFnRowScale = 0.62; // The F-row is shorter than a full row
const deckDefaultCode = "us";

// A key is { role, u, code, ... }:
//   role "key"     - { base, shift, altgr } glyphs, one per level; altgr may be null
//   role "mod"     - a latching modifier, labelled
//   role "special" - a plain tap with a fixed label (Esc, Tab, arrows, ...)
//   role "space"   - the space bar, carrying the layout badge
//   role "action"  - no keycode; drives the UI instead (pin, hide)
function deckLevelKey(u, code, glyphs) {
    const levels = glyphs[code] ?? [String(code), null, null];
    return { role: "key", u: u, code: code, base: levels[0], shift: levels[1], altgr: levels[2] };
}

function deckMod(u, code, label) {
    return { role: "mod", u: u, code: code, label: label };
}

function deckSpecial(u, code, label) {
    return { role: "special", u: u, code: code, label: label };
}

function deckSpace(u, code, badge) {
    return { role: "space", u: u, code: code, label: "Space", badge: badge };
}

function deckAction(u, action, label) {
    return { role: "action", u: u, action: action, label: label };
}

// Stamps each key with the offset of its left edge, in units. The deck places its keys at those
// offsets rather than leaning on a positioner: a grid this fixed has nothing to negotiate, and
// explicit coordinates cannot drift out of step when a layout swap rebuilds the rows.
function deckPlace(row) {
    let at = 0;
    row.forEach(key => {
        key.at = at;
        at += key.u;
    });
    return row;
}

// keycode -> [base, shift, altgr], dumped from `xkbcli compile-keymap --layout <code>`, so every
// glyph is what the compositor actually produces here. Dead keys show their spacing form, and a
// null AltGr means the layout has no third level on that key.
const deckGlyphs = {
    fr: {
        // digits
        41: ["²", "~", "¬"], 2: ["&", "1", "¹"], 3: ["é", "2", "~"], 4: ["\"", "3", "#"],
        5: ["'", "4", "{"], 6: ["(", "5", "["], 7: ["-", "6", "|"], 8: ["è", "7", "`"],
        9: ["_", "8", "\\"], 10: ["ç", "9", "^"], 11: ["à", "0", "@"], 12: [")", "°", "]"],
        13: ["=", "+", "}"],
        // upper
        16: ["a", "A", "æ"], 17: ["z", "Z", "«"], 18: ["e", "E", "€"], 19: ["r", "R", "¶"],
        20: ["t", "T", "ŧ"], 21: ["y", "Y", "←"], 22: ["u", "U", "↓"], 23: ["i", "I", "→"],
        24: ["o", "O", "ø"], 25: ["p", "P", "þ"], 26: ["^", "¨", "¨"], 27: ["$", "£", "¤"],
        // home
        30: ["q", "Q", "@"], 31: ["s", "S", "ß"], 32: ["d", "D", "ð"], 33: ["f", "F", "đ"],
        34: ["g", "G", "ŋ"], 35: ["h", "H", "ħ"], 36: ["j", "J", "◌̉"], 37: ["k", "K", "ĸ"],
        38: ["l", "L", "ł"], 39: ["m", "M", "µ"], 40: ["ù", "%", "^"], 43: ["*", "µ", "`"],
        // lower
        86: ["<", ">", "|"], 44: ["w", "W", "ł"], 45: ["x", "X", "»"], 46: ["c", "C", "¢"],
        47: ["v", "V", "„"], 48: ["b", "B", "“"], 49: ["n", "N", "”"], 50: [",", "?", "´"],
        51: [";", ".", "•"], 52: [":", "/", "·"], 53: ["!", "§", "◌̣"],
    },
    us: {
        // digits
        41: ["`", "~", null], 2: ["1", "!", null], 3: ["2", "@", null], 4: ["3", "#", null],
        5: ["4", "$", null], 6: ["5", "%", null], 7: ["6", "^", null], 8: ["7", "&", null],
        9: ["8", "*", null], 10: ["9", "(", null], 11: ["0", ")", null], 12: ["-", "_", null],
        13: ["=", "+", null],
        // upper
        16: ["q", "Q", null], 17: ["w", "W", null], 18: ["e", "E", null], 19: ["r", "R", null],
        20: ["t", "T", null], 21: ["y", "Y", null], 22: ["u", "U", null], 23: ["i", "I", null],
        24: ["o", "O", null], 25: ["p", "P", null], 26: ["[", "{", null], 27: ["]", "}", null],
        // home
        30: ["a", "A", null], 31: ["s", "S", null], 32: ["d", "D", null], 33: ["f", "F", null],
        34: ["g", "G", null], 35: ["h", "H", null], 36: ["j", "J", null], 37: ["k", "K", null],
        38: ["l", "L", null], 39: [";", ":", null], 40: ["'", "\"", null], 43: ["\\", "|", null],
        // lower
        86: ["<", ">", "|"], 44: ["z", "Z", null], 45: ["x", "X", null], 46: ["c", "C", null],
        47: ["v", "V", null], 48: ["b", "B", null], 49: ["n", "N", null], 50: ["m", "M", null],
        51: [",", "<", null], 52: [".", ">", null], 53: ["/", "?", null],
    },
    de: {
        // digits
        41: ["^", "°", "′"], 2: ["1", "!", "¹"], 3: ["2", "\"", "²"], 4: ["3", "§", "³"],
        5: ["4", "$", "¼"], 6: ["5", "%", "½"], 7: ["6", "&", "¬"], 8: ["7", "/", "{"],
        9: ["8", "(", "["], 10: ["9", ")", "]"], 11: ["0", "=", "}"], 12: ["ß", "?", "\\"],
        13: ["´", "`", "¸"],
        // upper
        16: ["q", "Q", "@"], 17: ["w", "W", "ſ"], 18: ["e", "E", "€"], 19: ["r", "R", "¶"],
        20: ["t", "T", "ŧ"], 21: ["z", "Z", "←"], 22: ["u", "U", "↓"], 23: ["i", "I", "→"],
        24: ["o", "O", "ø"], 25: ["p", "P", "þ"], 26: ["ü", "Ü", "¨"], 27: ["+", "*", "~"],
        // home
        30: ["a", "A", "æ"], 31: ["s", "S", "ſ"], 32: ["d", "D", "ð"], 33: ["f", "F", "đ"],
        34: ["g", "G", "ŋ"], 35: ["h", "H", "ħ"], 36: ["j", "J", "◌̣"], 37: ["k", "K", "ĸ"],
        38: ["l", "L", "ł"], 39: ["ö", "Ö", "˝"], 40: ["ä", "Ä", "^"], 43: ["#", "'", "’"],
        // lower
        86: ["<", ">", "|"], 44: ["y", "Y", "»"], 45: ["x", "X", "«"], 46: ["c", "C", "¢"],
        47: ["v", "V", "„"], 48: ["b", "B", "“"], 49: ["n", "N", "”"], 50: ["m", "M", "µ"],
        51: [",", ";", "·"], 52: [".", ":", "…"], 53: ["-", "_", "–"],
    },
    ru: {
        // digits
        41: ["ё", "Ё", null], 2: ["1", "!", null], 3: ["2", "\"", null], 4: ["3", "№", null],
        5: ["4", ";", null], 6: ["5", "%", null], 7: ["6", ":", null], 8: ["7", "?", null],
        9: ["8", "*", "₽"], 10: ["9", "(", null], 11: ["0", ")", null], 12: ["-", "_", null],
        13: ["=", "+", null],
        // upper
        16: ["й", "Й", null], 17: ["ц", "Ц", null], 18: ["у", "У", null], 19: ["к", "К", null],
        20: ["е", "Е", null], 21: ["н", "Н", null], 22: ["г", "Г", null], 23: ["ш", "Ш", null],
        24: ["щ", "Щ", null], 25: ["з", "З", null], 26: ["х", "Х", null], 27: ["ъ", "Ъ", null],
        // home
        30: ["ф", "Ф", null], 31: ["ы", "Ы", null], 32: ["в", "В", null], 33: ["а", "А", null],
        34: ["п", "П", null], 35: ["р", "Р", null], 36: ["о", "О", null], 37: ["л", "Л", null],
        38: ["д", "Д", null], 39: ["ж", "Ж", null], 40: ["э", "Э", null], 43: ["\\", "/", null],
        // lower
        86: ["/", "|", "|"], 44: ["я", "Я", null], 45: ["ч", "Ч", null], 46: ["с", "С", null],
        47: ["м", "М", null], 48: ["и", "И", null], 49: ["т", "Т", null], 50: ["ь", "Ь", null],
        51: ["б", "Б", null], 52: ["ю", "Ю", null], 53: [".", ",", null],
    }
};

const deckMeta = {
    fr: { name: "French", short: "FR", description: "AZERTY" },
    us: { name: "English (US)", short: "US", description: "QWERTY" },
    de: { name: "German", short: "DE", description: "QWERTZ" },
    ru: { name: "Russian", short: "RU", description: "ЙЦУКЕН" }
};

// [keycode, label, units]
const deckFnKeys = [
    [1, "Esc", 1.5], [59, "F1"], [60, "F2"], [61, "F3"], [62, "F4"], [63, "F5"], [64, "F6"],
    [65, "F7"], [66, "F8"], [67, "F9"], [68, "F10"], [87, "F11"], [88, "F12"], [99, "PrtSc"],
    [111, "Del"]
];

// Rows 5 and 6 end here instead of in a right Shift and a Menu key. Pin and Hide take the two dead
// corners of the inverted T, so the panel needs no control rail of its own.
const deckCluster = {
    top: deckPlace([deckAction(1, "pin", "Pin"), deckSpecial(1, 103, "↑"), deckAction(1, "hide", "Hide")]),
    bottom: deckPlace([deckSpecial(1, 105, "←"), deckSpecial(1, 108, "↓"), deckSpecial(1, 106, "→")])
};

function deckRows(glyphs, badge) {
    const key = (code, u) => deckLevelKey(u ?? 1, code, glyphs);
    return [
        deckFnKeys.map(entry => deckSpecial(entry[2] ?? 1, entry[0], entry[1])),
        [41, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13].map(code => key(code))
            .concat([deckSpecial(2.5, 14, "⌫")]),
        [deckSpecial(1.5, 15, "Tab")]
            .concat([16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27].map(code => key(code)))
            .concat([deckSpecial(2, 28, "⏎")]),
        [deckSpecial(2.5, 58, "Caps")]
            .concat([30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40].map(code => key(code)))
            .concat([key(43, 2)]),
        [deckMod(1.5, 42, "Shift")]
            .concat([86, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53].map(code => key(code))),
        [
            deckMod(1.5, 29, "Ctrl"), deckMod(1.25, 125, "Super"), deckMod(1.25, 56, "Alt"),
            deckSpace(6, 57, badge), deckMod(1.25, 100, "AltGr"), deckMod(1.25, 97, "Ctrl")
        ]
    ].map(deckPlace);
}

function buildDeck(code) {
    const meta = deckMeta[code];
    return {
        xkb: code,
        name: meta.name,
        short: meta.short,
        description: meta.description,
        units: deckUnits,
        clusterUnits: deckClusterUnits,
        fnRowScale: deckFnRowScale,
        rows: deckRows(deckGlyphs[code], meta.short),
        cluster: deckCluster
    };
}

const byXkbCode = {
    fr: buildDeck("fr"),
    us: buildDeck("us"),
    de: buildDeck("de"),
    ru: buildDeck("ru")
};

/**
 * The key of the deck an xkb code ("fr") or a layout name ("French") names, or null when no deck
 * covers it. Hyprland glues a variant onto its layout ("frazerty"), so a leading two-letter match
 * counts as well: the variant only moves a few glyphs, and the base table beats no keyboard at all.
 */
function deckCodeFor(codeOrName) {
    if (!codeOrName) return null;
    const name = String(codeOrName);
    const code = name.toLowerCase();
    if (byXkbCode.hasOwnProperty(code)) return code;
    const named = Object.keys(byXkbCode).find(key => byXkbCode[key].name === name);
    if (named) return named;
    const head = code.slice(0, 2);
    return byXkbCode.hasOwnProperty(head) ? head : null;
}

/**
 * Resolves a deck from an xkb code ("fr") or a layout name ("French"), falling back to US.
 * Deciding what to pass - the live layout or a pinned one - is the caller's job.
 */
function deckFor(codeOrName) {
    return byXkbCode[deckCodeFor(codeOrName) ?? deckDefaultCode];
}
