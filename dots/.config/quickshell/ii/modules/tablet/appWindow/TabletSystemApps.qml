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
            id: "cheatsheet",
            name: "Shortcuts",
            icon: "keyboard",
            kind: "surface",
            keywords: ["cheatsheet", "shortcuts", "keybinds", "atalhos", "teclas"]
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

    function byId(appId) {
        return root.apps.find(app => app.id === appId) ?? null;
    }

    /// Matches the drawer's search. Same shape as an app entry there: `name` and keywords.
    function search(query) {
        const q = String(query).trim().toLowerCase();
        if (q.length === 0)
            return [];
        return root.apps.filter(app => {
            if (app.name.toLowerCase().includes(q))
                return true;
            return (app.keywords ?? []).some(keyword => keyword.startsWith(q));
        });
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
        case "cheatsheet":
            GlobalStates.cheatsheetOpen = true;
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
