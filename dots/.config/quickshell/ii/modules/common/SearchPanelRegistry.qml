pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    // This registry is intentionally declarative: the Search surface, aliases and
    // prefix handling consume this data instead of maintaining parallel lists.
    readonly property var panels: [
        { id: "clipboard", source: "ClipboardPanel.qml", prefixKey: "clipboard", keywords: ["clipboard", "clip", "paste", "copiar", "area de transferencia"], label: qsTr("Clipboard"), icon: "content_paste", searchIcon: "content_paste_search", searchShape: "Gem", searchRotationStep: 90, width: () => Config.options.search.clipboard.panelWidth ?? 860, enabled: () => Config.options.search.modules.clipboard, accent: false, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "fileBrowser", source: "FileBrowserPanel.qml", prefixKey: "fileBrowser", keywords: ["file", "files", "folder", "folders", "browse", "browser", "explorer", "arquivo", "arquivos", "pasta", "yazi"], label: qsTr("File Browser"), icon: "folder_data", searchIcon: "folder_data", searchShape: "ClamShell", searchRotationStep: 360, width: () => Config.options.search.fileBrowser.panelWidth ?? 1120, enabled: () => Config.options.search.modules.fileBrowser, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "bluetooth", source: "BluetoothPanel.qml", prefixKey: "bluetooth", keywords: ["bluetooth", "bt", "fone"], label: qsTr("Bluetooth"), icon: "bluetooth", searchIcon: "bluetooth", searchShape: "Bun", searchRotationStep: 360, width: () => Config.options.search.clipboard.panelWidth ?? 860, enabled: () => Config.options.search.modules.bluetooth, accent: false, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "translator", source: "TranslatorPanel.qml", prefixKey: "translator", keywords: ["translator", "translate", "tradutor", "traduzir"], label: qsTr("Translator"), icon: "translate", searchIcon: "translate", searchShape: "Cookie6Sided", searchRotationStep: 60, width: () => Config.options.search.clipboard.panelWidth ?? 860, enabled: () => Config.options.search.modules.translator, accent: false, focusMode: "input", queryProperty: "searchQuery", hosted: true },
        { id: "mediaDownloader", source: "MediaDownloaderPanel.qml", prefixKey: "mediaDownloader", keywords: ["download", "video", "media"], label: qsTr("Media Downloader"), icon: "download", searchIcon: "download", searchShape: "Cookie9Sided", searchRotationStep: 40, width: () => Config.options.search.clipboard.panelWidth ?? 860, enabled: () => Config.options.search.modules.mediaDownloader && Config.options.mediaDownloader.enabled, accent: false, focusMode: "input", queryProperty: "searchQuery", hosted: true },
        { id: "materialSymbols", source: "MaterialSymbolsPanel.qml", prefixKey: "materialSymbols", keywords: ["material", "symbols", "icons"], label: qsTr("Material Symbols"), icon: "font_download", searchIcon: "font_download", searchShape: "SoftBurst", searchRotationStep: 45, width: () => 600, enabled: () => Config.options.search.modules.materialSymbols, accent: false, focusMode: "grid", queryProperty: "searchQuery", hosted: true },
        { id: "typingTest", source: "TypingTestPanel.qml", prefixKey: "typingTest", keywords: ["typing", "typing test", "wpm", "speed typing", "digitação", "teste de digitação", "velocidade de digitação"], label: qsTr("Typing test"), icon: "speed", searchIcon: "speed", searchShape: "Pentagon", searchRotationStep: 72, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.typingTest.enable, accent: true, focusMode: "input", queryProperty: "", inputOwner: "panel", hosted: true },
        { id: "ai", source: "AiChatPanel.qml", prefixKey: "ai", keywords: ["ai", "chat", "assistant"], label: qsTr("AI Chat"), icon: "auto_awesome", searchIcon: "auto_awesome", searchShape: "Clover4Leaf", searchRotationStep: 90, width: () => 720, enabled: () => Ai.enabled, accent: false, focusMode: "input", queryProperty: "" },

        // Future panels are registered now so aliases and configuration have one
        // stable namespace. Their source is activated only when its feature lands.
        { id: "calendar", source: "CalendarPanel.qml", prefixKey: "", keywords: ["calendar", "agenda", "event", "evento", "schedule", "meeting"], label: qsTr("Calendar"), icon: "calendar_month", searchIcon: "calendar_month", searchShape: "Arch", searchRotationStep: 360, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.calendar.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "tasks", source: "TasksPanel.qml", prefixKey: "", keywords: ["tasks", "task", "tarefas", "todo"], label: qsTr("Tasks"), icon: "task_alt", searchIcon: "task_alt", searchShape: "Cookie4Sided", searchRotationStep: 90, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.tasks.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "timers", source: "TimersPanel.qml", prefixKey: "", keywords: ["timer", "timers", "pomodoro", "alarm"], label: qsTr("Timers"), icon: "timer", searchIcon: "timer", searchShape: "PuffyDiamond", searchRotationStep: 90, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.timers.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "emojis", source: "EmojiPanel.qml", prefixKey: "emojis", keywords: ["emoji", "emojis", "emoticon", "smiley", "símbolo"], label: qsTr("Emojis"), icon: "mood", searchIcon: "add_reaction", searchShape: "Sunny", searchRotationStep: 45, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.emojis.enable, accent: true, focusMode: "grid", queryProperty: "searchQuery", hosted: true },
        { id: "screenshots", source: "ScreenshotsPanel.qml", prefixKey: "", keywords: ["screenshot", "screenshots", "print", "captura", "imagem"], label: qsTr("Screenshots"), icon: "screenshot", searchIcon: "screenshot", searchShape: "PixelCircle", searchRotationStep: 90, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.screenshots.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "windows", source: "WindowManagementPanel.qml", prefixKey: "", keywords: ["window", "windows", "tiling", "move", "janela", "mover"], label: qsTr("Window Management"), icon: "splitscreen", searchIcon: "splitscreen", searchShape: "Square", searchRotationStep: 90, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.windowManagement.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "settings", source: "SettingsTogglesPanel.qml", prefixKey: "", keywords: ["settings", "config", "configurar", "dotfiles"], label: qsTr("Settings"), icon: "settings", searchIcon: "tune", searchShape: "Clover8Leaf", searchRotationStep: 45, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.settingsToggles.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "keybinds", source: "KeybindsPanel.qml", prefixKey: "", keywords: ["keybind", "keybinds", "atalho", "shortcut", "bind"], label: qsTr("Keybinds"), icon: "keyboard", searchIcon: "keyboard", searchShape: "PixelTriangle", searchRotationStep: 360, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.keybinds.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "commands", source: "CommandsPanel.qml", prefixKey: "", keywords: ["command", "commands", "comando", "comandos", "cmd", "terminal"], label: qsTr("Commands"), icon: "terminal", searchIcon: "terminal", searchShape: "Ghostish", searchRotationStep: 360, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.cheatsheet.enable && Config.options.search.modules.cheatsheet.commandsPanel, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "gmail", source: "GmailPanel.qml", prefixKey: "", keywords: ["gmail", "email", "mail", "inbox", "unread"], label: qsTr("Email"), icon: "mail", searchIcon: "mail", searchShape: "Heart", searchRotationStep: 360, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.cheatsheet.enable && Config.options.search.modules.cheatsheet.gmailPanel, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "sports", source: "SportsPanel.qml", prefixKey: "", keywords: ["sports", "jogos", "game", "games", "today", "hoje", "football", "futebol"], label: qsTr("Today’s games"), icon: "sports_soccer", searchIcon: "sports_soccer", searchShape: "VerySunny", searchRotationStep: 45, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.sports.enable, accent: true, focusMode: "list", queryProperty: "searchQuery", hosted: true },
        { id: "tools", source: "ToolsPanel.qml", prefixKey: "", keywords: ["tool", "tools", "devtools", "generator", "generators", "generate", "gerador", "gerar", "ferramenta", "ferramentas", "uuid", "guid", "password", "senha", "lorem", "ipsum", "base64", "b64", "jwt", "json", "regex", "hash", "timestamp", "slug", "diff", "case", "converter", "encoder"], label: qsTr("Tools"), icon: "wand_stars", searchIcon: "wand_stars", searchShape: "Burst", searchRotationStep: 45, width: () => Config.options.search.appearance.panelWidth, enabled: () => Config.options.search.modules.tools.enable, accent: true, focusMode: "grid", queryProperty: "searchQuery", hosted: true }
    ]

    readonly property var enabledPanels: root.panels.filter(panel => panel.enabled())
    readonly property var activePrefixes: root.enabledPanels.map(panel => root.prefixOf(panel)).filter(prefix => prefix.length > 0)
    // Alias configuration is a catalogue, not a snapshot of the currently
    // enabled Loaders. Keeping every public panel here lets users prepare an
    // alias before enabling its module, while LauncherSearch still suppresses
    // execution until the target itself is enabled.
    readonly property var aliasTargets: root.panels.filter(panel => panel.aliasable !== false).map(panel => ({
        id: panel.id,
        name: panel.label,
        icon: panel.icon,
        enabled: panel.enabled()
    }))

    function byId(panelId) {
        return root.panels.find(panel => panel.id === panelId) ?? null;
    }

    function prefixOf(panel) {
        if (!panel?.prefixKey)
            return "";
        return String(Config.options.search.prefix[panel.prefixKey] ?? "");
    }

    function resolve(query) {
        const text = String(query ?? "");
        for (const panel of root.enabledPanels) {
            const prefix = root.prefixOf(panel);
            if (prefix.length > 0 && text.startsWith(prefix))
                return panel;
        }
        return null;
    }
}
