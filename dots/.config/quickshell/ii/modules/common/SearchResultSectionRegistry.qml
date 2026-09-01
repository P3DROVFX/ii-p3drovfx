pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Catalogue of the result classes the launcher groups by.
 *
 * The presentation of a section and the priority it is shown at used to live as
 * two parallel switch statements inside SearchWidget, which meant the Settings
 * window had no way to name a section, let alone reorder one. They live here so
 * the surface that renders the groups and the surface that lets the user
 * arrange them read the same list.
 *
 * `Config.options.search.sectionOrder` holds the user's arrangement; this is the
 * catalogue behind it, the source of the shipped order, and the fallback for a
 * list that has been emptied out.
 */
Singleton {
    id: root

    readonly property var sections: [
        {
            // Idle-only: a short, frecency-ranked strip (favorites, most-used
            // apps and panels) shown above everything else when Search opens
            // with an empty query. Never populated for a typed query, so it
            // is exempt from the user's configurable `sectionOrder` — see
            // `SearchWidget.sectionOrder`.
            id: "suggested",
            title: qsTr("Suggestions"),
            icon: "auto_awesome"
        },
        {
            id: "aliases",
            title: qsTr("Aliases"),
            icon: "label"
        },
        {
            id: "media",
            title: qsTr("Now playing"),
            icon: "music_note"
        },
        {
            id: "best",
            title: qsTr("Best match"),
            icon: "stars"
        },
        {
            id: "apps",
            title: qsTr("Applications"),
            icon: "apps"
        },
        {
            id: "sites",
            title: qsTr("Sites"),
            icon: "public"
        },
        {
            id: "controls",
            title: qsTr("Controls"),
            icon: "tune"
        },
        {
            id: "tools",
            title: qsTr("Search tools"),
            icon: "widgets"
        },
        {
            id: "actions",
            title: qsTr("Actions & shortcuts"),
            icon: "bolt"
        },
        {
            id: "quicklinks",
            title: qsTr("Quick links"),
            icon: "link"
        },
        {
            id: "textSnippets",
            title: qsTr("Text snippets"),
            icon: "content_copy"
        },
        {
            id: "other",
            title: qsTr("More results"),
            icon: "search"
        },
        {
            id: "settings",
            title: qsTr("Settings"),
            icon: "settings"
        },
        {
            id: "files",
            title: qsTr("Files & folders"),
            icon: "folder"
        },
        {
            id: "continue",
            title: qsTr("Continue with"),
            icon: "arrow_forward"
        }
    ]

    readonly property var defaultOrder: root.sections.map(section => section.id)

    // `sites` remains one configurable provider in Settings, but the Search
    // expands it into semantic result groups. This keeps priority controls
    // compact while avoiding a mixed, visually ambiguous Sites bucket.
    readonly property var siteSubsections: [
        {
            id: "siteTabs",
            title: qsTr("Open tabs"),
            icon: "tab"
        },
        {
            id: "siteFavorites",
            title: qsTr("Favorite sites"),
            icon: "bookmark"
        },
        {
            id: "siteSuggestions",
            title: qsTr("Suggested sites"),
            icon: "history"
        }
    ]

    function getComponent(id: string): var {
        const wanted = String(id ?? "");
        for (let i = 0; i < root.sections.length; i++) {
            if (root.sections[i].id === wanted)
                return root.sections[i];
        }
        for (let i = 0; i < root.siteSubsections.length; i++) {
            if (root.siteSubsections[i].id === wanted)
                return root.siteSubsections[i];
        }
        return null;
    }

    function getAvailableComponents(usedIds: var): var {
        const used = Array.from(usedIds ?? []);
        return root.sections.filter(section => used.indexOf(section.id) === -1);
    }

    function expandOrder(order: var): var {
        const expanded = [];
        const source = Array.from(order ?? []);
        for (let i = 0; i < source.length; i++) {
            const sectionId = String(source[i]?.id ?? source[i] ?? "");
            if (sectionId === "sites")
                expanded.push("siteTabs", "siteFavorites", "siteSuggestions");
            else if (sectionId.length > 0)
                expanded.push(sectionId);
        }
        return expanded;
    }

    /**
     * The order the launcher actually renders.
     *
     * A section the user removed from the list is a section whose results are
     * not shown, so the list doubles as the on/off switch. An empty list would
     * mean "no results at all", which is never what someone meant to configure —
     * that falls back to the full catalogue.
     */
    readonly property var activeOrder: {
        const configured = Array.from(Config.options.search.sectionOrder ?? []);
        const order = [];
        for (let i = 0; i < configured.length; i++) {
            const id = String(configured[i]?.id ?? configured[i] ?? "");
            // Ignore ids from a config written by a newer or older build, and
            // ignore duplicates: either would make a section render twice.
            if (id.length > 0 && root.getComponent(id) !== null && order.indexOf(id) === -1)
                order.push(id);
        }
        const selectedOrder = order.length > 0 ? order : root.defaultOrder;
        return root.expandOrder(selectedOrder);
    }
}
