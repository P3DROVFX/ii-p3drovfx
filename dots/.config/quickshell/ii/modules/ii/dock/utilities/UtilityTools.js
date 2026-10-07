.pragma library

// The quick tools of the Tools widget: the bar's utility buttons, in the bar's
// order. The tile owns their live state and runs them; Settings lists them.
// Titles are translation keys.

var tools = [
    { id: "screenSnip", symbol: "screenshot_region", title: "Screenshot" },
    { id: "screenRecord", symbol: "videocam", title: "Screen record" },
    { id: "liveDraw", symbol: "draw", title: "Draw on screen" },
    { id: "colorPicker", symbol: "colorize", title: "Color picker" },
    { id: "keyboard", symbol: "keyboard", title: "On-screen keyboard" },
    { id: "wallpaper", symbol: "imagesmode", title: "Wallpaper" },
    { id: "mic", symbol: "mic", title: "Microphone" },
    { id: "darkMode", symbol: "dark_mode", title: "Dark mode" },
    { id: "performance", symbol: "airwave", title: "Power profile" },
    { id: "phoneMirror", symbol: "smartphone", title: "Phone mirror" },
];

function find(id) {
    for (var i = 0; i < tools.length; i++) {
        if (tools[i].id === id)
            return tools[i];
    }
    return null;
}

// The saved ids that still exist, in the canonical order.
function shown(saved) {
    var wanted = {};
    for (var i = 0; i < (saved || []).length; i++)
        wanted[String(saved[i])] = true;
    return tools.filter(function (tool) { return wanted[tool.id] === true; }).map(function (tool) { return tool.id; });
}
