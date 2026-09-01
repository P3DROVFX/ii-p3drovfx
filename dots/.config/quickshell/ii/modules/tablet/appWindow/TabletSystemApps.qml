pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
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
            id: "policies",
            name: "Policies",
            icon: "policy",
            kind: "hosted",
            // It lives on the left edge in the desktop shell, so it still arrives from
            // there — but at app width with a title bar, not as a 460px sidebar.
            enterFrom: "left",
            // Its content only builds its tabs while the shell considers policies open
            // (SidebarPoliciesContent.tabsWanted). Opening it as an app has to say so, and
            // saying so is true: policies IS open, just presented differently.
            onOpen: () => GlobalStates.sidebarLeftOpen = true,
            onClose: () => GlobalStates.sidebarLeftOpen = false,
            keywords: ["policies", "ai", "phone", "anime", "politicas", "telefone"]
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
