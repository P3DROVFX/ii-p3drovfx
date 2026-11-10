import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

/*
 * What a button on the search bar widgets (Pixel Search Bar, Search with
 * Shortcuts) can do: its symbol, its name, and running it. `catalog` is the
 * list their Settings page offers.
 */
QtObject {
    id: root

    readonly property var catalog: [
        { value: "search", icon: "search", displayName: Translation.tr("Search") },
        { value: "lens", icon: "center_focus_strong", displayName: Translation.tr("Google Lens") },
        { value: "ai_chat", icon: "auto_awesome", displayName: Translation.tr("AI Chat") },
        { value: "music_rec", icon: "music_note", displayName: Translation.tr("Music Recognition") },
        { value: "clipboard", icon: "content_paste", displayName: Translation.tr("Clipboard") },
        { value: "emojis", icon: "mood", displayName: Translation.tr("Emojis") },
        { value: "files", icon: "folder", displayName: Translation.tr("Files") },
        { value: "translator", icon: "translate", displayName: Translation.tr("Translator") },
        { value: "screenshot", icon: "screenshot_region", displayName: Translation.tr("Screenshot") },
        { value: "color_picker", icon: "colorize", displayName: Translation.tr("Color Picker") },
        { value: "wallpapers", icon: "wallpaper", displayName: Translation.tr("Wallpapers") }
    ]

    function details(key) {
        return root.catalog.find(entry => entry.value === key) ?? root.catalog[0];
    }

    function run(key) {
        switch (key) {
        case "lens":
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"]);
            break;
        case "ai_chat":
            Ai.surfaceRouter.open({ surface: "sidebar", focusIntent: "composer" });
            break;
        case "music_rec":
            SongRec.toggleRunning();
            break;
        case "clipboard":
            GlobalStates.openSearchPanel("clipboard", "", "");
            break;
        case "emojis":
            GlobalStates.openSearchPanel("emojis", "", "");
            break;
        case "files":
            GlobalStates.openSearchPanel("fileBrowser", "", "");
            break;
        case "translator":
            Persistent.states.sidebar.policies.tab = 1;
            GlobalStates.sidebarLeftOpen = true;
            break;
        case "screenshot":
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
            break;
        case "color_picker":
            Quickshell.execDetached(["hyprpicker", "-a"]);
            break;
        case "wallpapers":
            Persistent.states.sidebar.policies.tab = 3;
            GlobalStates.sidebarLeftOpen = true;
            break;
        default:
            GlobalStates.toggleSearchOnly();
        }
    }
}
