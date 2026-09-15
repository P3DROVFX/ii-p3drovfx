pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/**
 * Shell surfaces the tablet family presents as apps.
 *
 * The desktop shell reaches these through keybinds, edge gestures and the launcher. None of
 * those exist here: this family has no cheatsheet gesture, no keyboard to press, and the
 * launcher is the app drawer. So the surfaces are listed in the drawer next to real apps
 * and opened the same way, which is what D6 asked for — they come back "as if they were
 * Android apps".
 *
 * Every ii tool that exposes standalone content is hosted in the same native app window.
 * The composition root injects those components, so this registry remains tablet-owned and
 * does not import ii directly. Keyboard, video editor and scratchpad keep their specialised
 * launch paths because they are already independent system surfaces.
 *
 * The content Components live in the ii family, so they are injected by the composition
 * root rather than imported here — the same rule that governs the drawer's tool panels.
 */
Singleton {
    id: root

    /// id -> Component, filled in by TabletFamily for native app entries.
    property var hostedContent: ({})

    readonly property var apps: [
        {
            id: "usage",
            name: "App Usage",
            icon: "query_stats",
            keywords: ["usage", "stats", "screen time", "uso", "estatisticas", "tempo de tela"]
        },
        {
            id: "modes",
            name: "Modes & Routines",
            icon: "tune",
            keywords: ["modes", "routines", "automation", "modos", "rotinas", "automacao", "focus"]
        },
        {
            id: "keyboard",
            name: "On-screen Keyboard",
            icon: "keyboard_alt",
            // First-class here rather than an accessory: this family assumes no physical
            // keyboard, so the on-screen one needs a way in that is not itself a keybind.
            keywords: ["keyboard", "osk", "onscreen", "teclado", "virtual"]
        },
        // ── The policies panel, split into its tabs ─────────────────────────
        // The desktop shell stacks these behind a tab bar because they share one narrow
        // sidebar. Nothing about them is actually related — an AI chat, a translator, a
        // media remote, a wallpaper browser — and with a whole screen to work in, a tab bar
        // is just a lid over four separate things. Each is its own app here.
        //
        {
            id: "policies.intelligence",
            name: "Intelligence",
            icon: "neurology",
            enabled: () => Ai.enabled,
            keywords: ["ai", "chat", "intelligence", "assistant", "inteligencia"]
        },
        {
            id: "policies.translator",
            name: "Translator",
            icon: "translate",
            enabled: () => (Config.options?.policies?.translator ?? 0) !== 0,
            keywords: ["translator", "translate", "tradutor", "traduzir"]
        },
        {
            id: "policies.media",
            name: "Media",
            icon: "music_note",
            enabled: () => (Config.options?.policies?.player ?? 0) !== 0,
            keywords: ["media", "player", "music", "musica", "reprodutor"]
        },
        {
            id: "policies.wallpapers",
            name: "Wallpapers",
            icon: "wallpaper",
            enabled: () => (Config.options?.policies?.wallpapers ?? 0) !== 0,
            keywords: ["wallpaper", "wallpapers", "papel de parede", "fundo"]
        },
        {
            id: "policies.anime",
            name: "Anime",
            icon: "bookmark_heart",
            enabled: () => (Config.options?.policies?.weeb ?? 0) !== 0
                && (Config.options?.policies?.weeb ?? 0) !== 2,
            keywords: ["anime", "weeb", "booru"]
        },
        {
            id: "policies.phone",
            name: "Phone",
            icon: "smartphone",
            enabled: () => (Config.options?.policies?.phone ?? 0) !== 0,
            keywords: ["phone", "telefone", "celular", "kdeconnect", "scrcpy"]
        },
        {
            id: "timetable",
            name: "Timetable",
            icon: "calendar_month",
            enabled: () => Config.options?.cheatsheet?.enableTimetable ?? false,
            keywords: ["timetable", "schedule", "classes", "horario", "aulas", "agenda"]
        },
        {
            id: "keybinds",
            name: "Keybinds",
            icon: "keyboard",
            keywords: ["cheatsheet", "shortcuts", "keybinds", "atalhos", "teclas"]
        },
        {
            id: "elements",
            name: "Periodic Table",
            icon: "experiment",
            enabled: () => Config.options?.cheatsheet?.enablePeriodicTable ?? false,
            keywords: ["periodic", "table", "elements", "quimica", "elementos", "tabela"]
        },
        {
            id: "aminoAcids",
            name: "Amino Acids",
            icon: "biotech",
            enabled: () => Config.options?.cheatsheet?.enableAminoAcids ?? false,
            keywords: ["amino", "acids", "aminoacidos", "biologia"]
        },
        {
            id: "commands",
            name: "Commands",
            icon: "terminal",
            enabled: () => Config.options?.cheatsheet?.enableCommands ?? false,
            keywords: ["commands", "terminal", "comandos"]
        },
        {
            id: "workspaces",
            name: "Workspaces",
            icon: "dashboard",
            enabled: () => Config.options?.cheatsheet?.enableWorkspaceProfiles ?? false,
            keywords: ["workspaces", "profiles", "areas de trabalho", "perfis"]
        },
        {
            id: "email",
            name: "Email",
            icon: "mail",
            enabled: () => Config.options?.cheatsheet?.enableGmail ?? false,
            keywords: ["email", "mail", "gmail"]
        },
        {
            id: "typingTest",
            name: "Typing Test",
            icon: "speed",
            enabled: () => Config.options?.cheatsheet?.enableTypingTest ?? false,
            keywords: ["typing", "test", "digitacao"]
        },
        {
            id: "videoEditor",
            name: "Video Editor",
            icon: "movie_edit",
            keywords: ["video", "editor", "cut", "trim", "editar", "cortar"]
        },
        {
            id: "scratchpad",
            name: "Scratchpad",
            icon: "inventory_2",
            keywords: ["scratchpad", "special", "rascunho"]
        },
        {
            id: "notes",
            name: "Notes",
            icon: "note_stack",
            enabled: () => Config.options?.notes?.enable ?? true,
            keywords: ["notes", "notebook", "notas", "anotacoes", "bloco", "caderno", "keep"]
        }
    ]

    /// Entries whose feature is switched on. An app the user has disabled in Settings must
    /// not sit in the drawer doing nothing when tapped.
    readonly property var available: root.apps.filter(app => !app.enabled || app.enabled())

    function byId(appId) {
        return root.apps.find(app => app.id === appId) ?? null;
    }

    /// Matches the drawer's search. Same shape as an app entry there: `name` and keywords.
    function search(query) {
        const q = String(query).trim().toLowerCase();
        if (q.length === 0)
            return [];
        return root.available.filter(app => {
            if (app.name.toLowerCase().includes(q))
                return true;
            return (app.keywords ?? []).some(keyword => keyword.startsWith(q));
        });
    }

    // ── Open/close hooks ────────────────────────────────────────────────────
    // Some native app surfaces need shell state set while they are up. Driven from the id
    // rather than from the window, because one window hosts one app at a time.
    property string _activeHostedId: ""

    function _syncActive() {
        const next = GlobalStates.tabletAppId;
        if (next === root._activeHostedId)
            return;
        root.byId(root._activeHostedId)?.onClose?.();
        root._activeHostedId = next;
        root.byId(next)?.onOpen?.();
    }

    readonly property Connections _appIdWatcher: Connections {
        target: GlobalStates
        function onTabletAppIdChanged() {
            root._syncActive();
        }
    }

    function launch(appId) {
        const app = root.byId(appId);
        if (!app)
            return;

        switch (appId) {
        case "keyboard":
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
            break;
        case "videoEditor":
            GlobalStates.videoEditorOpen = true;
            break;
        case "scratchpad":
            // GlobalStates.scratchpadOpen is derived, not a switch — the special workspace
            // is the state, so ask Hyprland the way the gesture registry does.
            Hyprland.dispatch("hl.dsp.workspace.toggle_special('special')");
            break;
        default:
            GlobalStates.openTabletApp(appId);
            break;
        }
    }
}
