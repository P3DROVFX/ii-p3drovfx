pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common.models

/**
 * The actions a search result offers, in one place.
 *
 * This list used to be built inside SearchItem, which meant it existed only for
 * the row shape that owns the Ctrl+K panel. Everything a result can *do* beyond
 * opening it — pin to the dock, copy an id, reset its ranking, reveal a folder —
 * was therefore invisible to any other presentation of the same result.
 *
 * Everything here is derived from the result object; the two callbacks are the
 * only things a caller has to supply, because they are the only parts that are
 * about the surface rather than about the result.
 */
Singleton {
    id: root

    /**
     * @param entry     a LauncherSearchResult
     * @param callbacks { onDone(): the surface should dismiss whatever it opened,
     *                    onExecuted(feedbackText): the primary action ran }
     *
     * Index 0 is always the primary action, so a caller showing its own primary
     * affordance can simply skip it.
     */
    function build(entry: var, callbacks: var): var {
        if (!entry)
            return [];

        const done = callbacks?.onDone ?? (function () {});
        const executed = callbacks?.onExecuted ?? (function () {});

        const itemType = entry.type ?? Translation.tr("App");
        const itemName = String(entry.name ?? "");
        const iconName = String(entry.iconName ?? "");
        const contentType = String(entry.category ?? "");
        const key = String(entry.key ?? "");
        const identifier = String(entry.id ?? "") || iconName;

        const items = [];

        items.push({
            name: entry.verb || Translation.tr("Open"),
            icon: "open_in_new",
            execute: () => {
                const isSystemControl = key.startsWith("sys:");
                const cmdKey = isSystemControl ? key.slice(4) : "";
                const isConfirming = isSystemControl && LauncherSearch.confirmKey !== cmdKey;
                // Rows that switch a mode, or that explicitly ask to stay, must
                // not take the launcher down with them.
                const isModeSwitch = (entry.keepOverviewOpen ?? false)
                    || (key.startsWith("mock:") && key !== "mock:settings")
                    || (key.startsWith("shortcut:") && key !== "shortcut:openSettings")
                    || itemType === Translation.tr("Folder Alias");

                done();
                if (!isConfirming && !isModeSwitch)
                    GlobalStates.overviewOpen = false;
                if (typeof entry.execute === "function")
                    entry.execute();
                executed(String(entry.feedbackText ?? ""));
            }
        });

        // The result's own actions come before the launcher's housekeeping ones.
        // A caller that shows only the first few is showing what the *result*
        // offers — "New Private Window" earns that slot over "Reset ranking".
        const entryActions = entry.actions ?? [];
        for (const action of entryActions) {
            items.push({
                name: action.name,
                icon: action.iconName || "play_arrow",
                nativeIcon: action.iconType === LauncherSearchResult.IconType.System,
                execute: () => {
                    done();
                    GlobalStates.overviewOpen = false;
                    action.execute();
                }
            });
        }

        if (entry.type === Translation.tr("App") || itemType === Translation.tr("App")) {
            const isPinned = TaskbarApps.isPinned(identifier);
            items.push({
                name: isPinned ? Translation.tr("Unpin from Dock") : Translation.tr("Pin to Dock"),
                icon: isPinned ? "keep_off" : "keep",
                execute: () => {
                    TaskbarApps.togglePin(identifier);
                    done();
                }
            });
            items.push({
                name: Translation.tr("Copy ID"),
                icon: "content_copy",
                execute: () => {
                    Quickshell.clipboardText = identifier;
                    done();
                }
            });
            items.push({
                name: Translation.tr("Reset"),
                icon: "restart_alt",
                execute: () => {
                    AppUsage.resetRanking(identifier);
                    done();
                }
            });
        }

        if (contentType === "filepath" || itemType === Translation.tr("Directory") || itemType === Translation.tr("Folder Alias")) {
            const isDir = itemType === Translation.tr("Directory") || itemType === Translation.tr("Folder Alias");
            if (isDir) {
                // File-search rows deliberately display just the basename. Pinning
                // that label used to create an unusable relative dock entry; the
                // canonical result path is the only stable dock identity.
                const folderPath = String(entry.filePath ?? itemName);
                const isPinned = TaskbarApps.isPinnedFile(folderPath);
                items.push({
                    name: isPinned ? Translation.tr("Unpin folder from Dock") : Translation.tr("Pin folder to Dock"),
                    icon: isPinned ? "folder_off" : "create_new_folder",
                    execute: () => {
                        TaskbarApps.togglePinnedFile(folderPath);
                        done();
                    }
                });
            }
        }

        if (key.startsWith("fsearch:") && LauncherSearch.allFileResults.length > 0) {
            const resultCount = LauncherSearch.allFileResults.length;
            items.push({
                name: Translation.tr("Browse %1 results in File Browser").arg(String(resultCount)),
                icon: "folder_search",
                execute: () => {
                    GlobalStates.openFileBrowserResults(LauncherSearch.allFileResults, LauncherSearch.fileSearchQuery);
                    done();
                }
            });
        }

        return items;
    }
}
