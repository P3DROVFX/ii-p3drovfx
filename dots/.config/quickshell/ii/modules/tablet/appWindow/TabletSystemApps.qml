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
 * Two kinds of entry, because the surfaces genuinely differ:
 *
 *   `hosted`  — the module separates its content from its window (UsageContent,
 *               ModesContent), so the content is re-chromed inside a TabletAppWindow and
 *               gets a title bar and a back button like any app.
 *   `surface` — the module is one indivisible PanelWindow. Splitting it is a refactor of
 *               ii, which this family is not allowed to require, so the entry simply opens
 *               the surface the desktop shell already has. It is still launched from the
 *               drawer; it just wears its own chrome.
 *
 * The content Components live in the ii family, so they are injected by the composition
 * root rather than imported here — the same rule that governs the drawer's tool panels.
 */
Singleton {
    id: root

    /// id -> Component, filled in by TabletFamily for the `hosted` entries.
    property var hostedContent: ({})

    readonly property var apps: [
        {
            id: "usage",
            name: "App Usage",
            icon: "query_stats",
            kind: "hosted",
            keywords: ["usage", "stats", "screen time", "uso", "estatisticas", "tempo de tela"]
        },
        {
            id: "modes",
            name: "Modes & Routines",
            icon: "tune",
            kind: "hosted",
            keywords: ["modes", "routines", "automation", "modos", "rotinas", "automacao", "focus"]
        },
        {
            id: "keyboard",
            name: "On-screen Keyboard",
            icon: "keyboard_alt",
            kind: "surface",
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
        // They keep entering from the left, so the panel that used to live on that edge
        // still arrives from it.
        {
            id: "policies.intelligence",
            name: "Intelligence",
            icon: "neurology",
            kind: "hosted",
            enterFrom: "left",
            enabled: () => Ai.enabled,
            keywords: ["ai", "chat", "intelligence", "assistant", "inteligencia"]
        },
        {
            id: "policies.translator",
            name: "Translator",
            icon: "translate",
            kind: "hosted",
            enterFrom: "left",
            enabled: () => (Config.options?.policies?.translator ?? 0) !== 0,
            keywords: ["translator", "translate", "tradutor", "traduzir"]
        },
        {
            id: "policies.media",
            name: "Media",
            icon: "music_note",
            kind: "hosted",
            enterFrom: "left",
            enabled: () => (Config.options?.policies?.player ?? 0) !== 0,
            keywords: ["media", "player", "music", "musica", "reprodutor"]
        },
        {
            id: "policies.wallpapers",
            name: "Wallpapers",
            icon: "wallpaper",
            kind: "hosted",
            enterFrom: "left",
            enabled: () => (Config.options?.policies?.wallpapers ?? 0) !== 0,
            keywords: ["wallpaper", "wallpapers", "papel de parede", "fundo"]
        },
        {
            id: "policies.anime",
            name: "Anime",
            icon: "bookmark_heart",
            kind: "hosted",
            enterFrom: "left",
            enabled: () => (Config.options?.policies?.weeb ?? 0) !== 0
                && (Config.options?.policies?.weeb ?? 0) !== 2,
            keywords: ["anime", "weeb", "booru"]
        },
        {
            id: "policies.phone",
            name: "Phone",
            icon: "smartphone",
            kind: "hosted",
            enterFrom: "left",
            enabled: () => (Config.options?.policies?.phone ?? 0) !== 0,
            keywords: ["phone", "telefone", "celular", "kdeconnect", "scrcpy"]
        },
        {
            id: "timetable",
            name: "Timetable",
            icon: "calendar_month",
            kind: "surface",
            enabled: () => Config.options?.cheatsheet?.enableTimetable ?? false,
            keywords: ["timetable", "schedule", "classes", "horario", "aulas", "agenda"]
        },
        {
            id: "keybinds",
            name: "Keybinds",
            icon: "keyboard",
            kind: "surface",
            keywords: ["cheatsheet", "shortcuts", "keybinds", "atalhos", "teclas"]
        },
        {
            id: "elements",
            name: "Periodic Table",
            icon: "experiment",
            kind: "surface",
            enabled: () => Config.options?.cheatsheet?.enablePeriodicTable ?? false,
            keywords: ["periodic", "table", "elements", "quimica", "elementos", "tabela"]
        },
        {
            id: "aminoAcids",
            name: "Amino Acids",
            icon: "biotech",
            kind: "surface",
            enabled: () => Config.options?.cheatsheet?.enableAminoAcids ?? false,
            keywords: ["amino", "acids", "aminoacidos", "biologia"]
        },
        {
            id: "videoEditor",
            name: "Video Editor",
            icon: "movie_edit",
            kind: "surface",
            keywords: ["video", "editor", "cut", "trim", "editar", "cortar"]
        },
        {
            id: "scratchpad",
            name: "Scratchpad",
            icon: "inventory_2",
            kind: "surface",
            keywords: ["scratchpad", "special", "rascunho"]
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
    // Some hosted surfaces need shell state set while they are up. Driven from the id
    // rather than from the window, because there is one window per screen and they would
    // all fire; the id changes exactly once per open.
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

        if (app.kind === "hosted") {
            GlobalStates.openTabletApp(appId);
            return;
        }

        switch (appId) {
        // The cheatsheet is one window with tabs, so each tab is its own entry in the
        // drawer and opens straight onto it. From the user's side those are separate apps,
        // which is what they are here.
        case "timetable":
        case "keybinds":
        case "elements":
        case "aminoAcids":
            GlobalStates.openCheatsheet(appId);
            break;
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
            console.log("[TabletSystemApps] no launcher for surface app:", appId);
            break;
        }
    }
}
