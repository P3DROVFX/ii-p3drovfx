pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> All options.
 *
 * The other five tabs are opinionated: they pick the settings worth having, name them in words
 * and give each one a control that understands its values. This tab is the opposite, and exists
 * because that curation is also a ceiling - Hyprland has 353 options and the list grows every
 * release, so anything not chosen for a tab would otherwise need a text editor.
 *
 * The list is not written here. It is read out of the type declarations Hyprland itself ships in
 * /usr/share/hypr/stubs, so a version with new options shows them without this file changing.
 *
 * The tab is an index rather than the list: 353 rows behind a section heading is a scroll, not a
 * page. Picking a section, or searching, opens the browser with the list in it.
 */
ContentPage {
    id: tab

    forceWidth: false

    readonly property url browserPage: Qt.resolvedUrl("HyprOptionBrowserPage.qml")

    /// The host that owns the slide-in overlay is the hub, several files up; this page cannot
    /// see it by name.
    function openSubPage(page: url) {
        let node = tab.parent;
        while (node) {
            if (typeof node.activeSubPage !== "undefined") {
                node.activeSubPage = page;
                return;
            }
            node = node.parent;
        }
    }

    function browse(section: string, key: string) {
        HyprlandCatalog.browse(section, key);
        tab.openSubPage(tab.browserPage);
    }

    /// section id -> how many of its keys this page has set.
    readonly property var managedBySection: {
        const out = {};
        for (const key of Object.keys(HyprlandGui.managedConfig)) {
            const section = key.split(":")[0];
            out[section] = (out[section] ?? 0) + 1;
        }
        return out;
    }

    property var _memo: ({})

    /// Kept by identity while the key set is unchanged, so editing a value does not rebuild
    /// the whole "set from this page" list underneath it.
    readonly property var managedKeys: ObjectUtils.keep(tab._memo, "managedKeys",
        Object.keys(HyprlandGui.managedConfig).sort())

    readonly property var listedSections: Array.from(HyprlandCatalog.sections)
        .filter(entry => entry.id !== "debug" || HyprlandCatalog.showDebug)

    // ── What this is ──────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Every option")
        icon: "tune"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Everything Hyprland can be told, including the settings that never earned a place on the other tabs. Each one is shown with the value the compositor reports for it, and edited as whatever type it takes.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        HyprNavRow {
            buttonIcon: "search"
            text: Translation.tr("Browse and search")
            value: HyprlandCatalog.ready
                ? Translation.tr("%1 options").arg(HyprlandCatalog.entries.length)
                : Translation.tr("Reading…")
            enabled: HyprlandCatalog.ready
            configPage: tab.browserPage
            onOpenSubPage: HyprlandCatalog.browse("", "")
        }

        HyprOptionNote {
            notes: {
                const out = [];
                if (HyprlandCatalog.origin === "stub")
                    out.push({ "icon": "inventory", "text": Translation.tr("The list is read from the type declarations installed with Hyprland, so it matches the version actually running.") });
                if (HyprlandCatalog.origin === "bundled")
                    out.push({ "icon": "warning", "text": Translation.tr("Hyprland's own option list is not installed on this machine, so a copy shipped with the shell is being used instead. Options added since then are missing from it.") });
                out.push({ "icon": "edit", "text": Translation.tr("Anything set here is written into the block at the end of custom/general.lua, the same file the other tabs use, and takes effect on the reload that follows.") });
                return out;
            }
        }
    }

    // ── What has been changed ─────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Set from this page")
        icon: "edit"
        visible: tab.managedKeys.length > 0

        Repeater {
            model: tab.managedKeys

            delegate: HyprNavRow {
                required property var modelData

                readonly property var entry: HyprlandCatalog.entryFor(modelData)

                buttonIcon: "chevron_right"
                text: modelData
                value: HyprlandCatalog.format(entry?.kind ?? "text",
                    HyprlandGui.managedConfig[modelData])
                configPage: tab.browserPage
                onOpenSubPage: HyprlandCatalog.browse("", modelData)
            }
        }

        HyprOptionNote {
            notes: [{ "icon": "info", "text": Translation.tr("These are the keys the hub has written, wherever they were set from. Opening one goes to it in the list, where it can be changed or put back.") }]
        }
    }

    // ── The sections ──────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("By section")
        icon: "list"

        // Sections are filled in once HyprlandCatalog finishes reading Hyprland's type
        // declarations - the same async read "Browse and search" above already waits on. Without
        // this the Repeater below is just empty, and the section reads as broken rather than
        // as still loading.
        StyledText {
            Layout.fillWidth: true
            visible: !HyprlandCatalog.ready
            text: Translation.tr("Reading…")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: tab.listedSections

            delegate: HyprNavRow {
                required property var modelData

                readonly property int mine: tab.managedBySection[modelData.id] ?? 0

                buttonIcon: modelData.icon
                text: Translation.tr(modelData.title)
                value: mine > 0
                    ? Translation.tr("%1 options, %2 set").arg(modelData.count).arg(mine)
                    : Translation.tr("%1 options").arg(modelData.count)
                configPage: tab.browserPage
                onOpenSubPage: HyprlandCatalog.browse(modelData.id, "")
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: HyprlandCatalog.ready && tab.listedSections.length === 0
            text: Translation.tr("No sections were reported.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // ── Debugging ─────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Advanced")
        icon: "bug_report"

        HyprToggle {
            buttonIcon: "bug_report"
            text: Translation.tr("Show Hyprland's debugging options")
            switchOn: HyprlandCatalog.showDebug
            onRequested: wanted => HyprlandCatalog.showDebug = wanted
        }

        HyprOptionNote {
            notes: [
                { "icon": "warning", "text": Translation.tr("These exist for diagnosing the compositor, not for using it: they blink the damage regions, fill the log, disable safety checks, and one of them crashes Hyprland on purpose. Nothing here is remembered - they are hidden again after a restart.") },
                { "icon": "visibility_off", "text": Translation.tr("While this is off, the debugging options are left out of the list and out of every search.") }
            ]
        }
    }

    // ── Related ───────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Related settings")
        icon: "link"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Borders, gaps, rounding, blur and the animation curves are the shell's to set: it pushes its own values back after every reload, so those keys are shown here but cannot be changed from here.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            RelatedChip {
                pageId: "windows"
                label: Translation.tr("Windows")
            }

            RelatedChip {
                pageId: "tiling"
                label: Translation.tr("Window tiling")
            }

            RelatedChip {
                pageId: "overlays"
                label: Translation.tr("Overlays")
            }
        }
    }
}
