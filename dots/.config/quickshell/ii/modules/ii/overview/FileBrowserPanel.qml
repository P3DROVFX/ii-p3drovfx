pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import "filebrowser"

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: -1
    property int actionIndex: 0
    property var backHistory: []
    property var forwardHistory: []
    property var markedPaths: ({})
    property var stagedPaths: []
    property bool stagedCut: false
    property bool showHidden: false
    property string sortMode: "name"
    property bool sortDescending: false
    property bool actionMenuOpen: false
    property bool confirmTrash: false
    property string editorMode: ""
    property string editorPresentedMode: ""
    property string editorValue: ""
    property string noticeText: ""
    property bool detailsFirst: false
    property bool consumingPathQuery: false
    property real directoryRevealProgress: 1
    property real actionMenuVisualOpacity: 0
    property real actionMenuVisualScale: 0.82
    property real actionMenuVisualOffset: Appearance.sizes.elevationMargin * 5
    property int pendingSelectionIndex: -1
    property string editorTargetPath: ""
    property var pendingTrashPaths: []
    property int trashPresentedCount: 0
    property bool globalSearchMode: false
    property string globalSearchQuery: ""
    property var globalSearchEntries: []
    property int consumedGlobalSearchRequest: -1
    readonly property bool supportsSectionToggle: true
    readonly property bool keepAlive: backend.loading || backend.inspecting || backend.operating
    readonly property bool listLoading: backend.loading && !root.globalSearchMode
    readonly property bool contentReady: root.globalSearchMode || (!backend.loading && backend.currentPath.length > 0)

    signal requestSetSearchQuery(string query)
    signal requestFocusSearchInput()

    onActionMenuOpenChanged: {
        actionMenuEnterAnimation.stop();
        actionMenuExitAnimation.stop();
        if (root.actionMenuOpen) {
            root.actionMenuVisualOpacity = 0;
            root.actionMenuVisualScale = 0.82;
            root.actionMenuVisualOffset = Appearance.sizes.elevationMargin * 5;
            actionMenuEnterAnimation.start();
        } else {
            actionMenuExitAnimation.start();
        }
    }

    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home).replace(/\/$/, "")
    readonly property var displayedEntries: root.globalSearchMode ? root.globalSearchEntries : backend.entries
    readonly property var filteredEntries: root.filterEntries()
    readonly property var selectedEntry: root.selectedIndex >= 0 && root.selectedIndex < root.filteredEntries.length
        ? root.filteredEntries[root.selectedIndex]
        : null
    readonly property var selectedMetadata: backend.metadata
    readonly property int markedCount: Object.keys(root.markedPaths).length
    readonly property var actionRows: root.buildActions()
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : backend.operating
            ? Translation.tr("Working on files…")
            : root.globalSearchMode
            ? Translation.tr("%1 results for %2").arg(String(root.filteredEntries.length)).arg(root.globalSearchQuery)
            : root.listLoading
            ? Translation.tr("Reading %1…").arg(root.displayPath(backend.pendingListPath))
            : backend.errorText.length > 0
                ? backend.errorText
                : Translation.tr("%1 items · %2").arg(String(root.filteredEntries.length)).arg(root.displayPath(backend.currentPath))

    readonly property var metadataRows: {
        const entry = root.selectedMetadata;
        if (!entry)
            return [];
        const children = Number(entry.childCount ?? -1);
        return [
            { label: Translation.tr("Type"), value: root.typeLabel(entry), icon: "draft" },
            { label: Translation.tr("Size"), value: entry.isDir && children >= 0 ? Translation.tr("%1 items").arg(String(children)) : root.formatBytes(entry.size), icon: "data_usage" },
            { label: Translation.tr("Modified"), value: root.formatDate(entry.modifiedMs), icon: "edit_calendar" },
            { label: entry.createdIsChangeTime ? Translation.tr("Changed") : Translation.tr("Created"), value: root.formatDate(entry.createdMs), icon: "calendar_add_on" },
            { label: Translation.tr("Permissions"), value: String(entry.permissions ?? "—") + "  " + String(entry.mode ?? ""), icon: "encrypted" },
            { label: Translation.tr("Owner"), value: String(entry.owner ?? "—") + " · " + String(entry.group ?? "—"), icon: "person" }
        ];
    }

    readonly property real panelGutter: Appearance.sizes.elevationMargin
    readonly property real rowHoverGutter: Appearance.sizes.elevationMargin * 0.75

    implicitWidth: Config.options.search.fileBrowser.panelWidth
    implicitHeight: scaffold.implicitHeight

    function displayPath(path): string {
        const value = String(path ?? "");
        if (value === root.homePath)
            return "~";
        if (value.startsWith(root.homePath + "/"))
            return "~" + value.slice(root.homePath.length);
        return value || "~";
    }

    function fileIcon(entry): string {
        if (!entry)
            return "draft";
        if (entry.isDir)
            return "folder";
        if (entry.isImage)
            return "image";
        if (entry.isVideo)
            return "movie";
        if (entry.isAudio)
            return "audio_file";
        if (entry.isPdf)
            return "picture_as_pdf";
        if (entry.isText)
            return "description";
        if (entry.executable)
            return "terminal";
        return "draft";
    }

    function fileShape(entry): string {
        if (entry?.isDir)
            return "Arch";
        if (entry?.isImage || entry?.isVideo)
            return "Gem";
        if (entry?.isAudio)
            return "Sunny";
        if (entry?.executable)
            return "PixelCircle";
        return "Cookie4Sided";
    }

    function typeLabel(entry): string {
        if (!entry)
            return Translation.tr("Unknown");
        if (entry.isDir && entry.isSymlink)
            return Translation.tr("Directory link");
        if (entry.isDir)
            return Translation.tr("Directory");
        if (entry.isSymlink)
            return Translation.tr("Symbolic link");
        return String(entry.mime ?? Translation.tr("File"));
    }

    function formatBytes(value): string {
        let bytes = Math.max(0, Number(value ?? 0));
        const units = [Translation.tr("B"), Translation.tr("KB"), Translation.tr("MB"), Translation.tr("GB"), Translation.tr("TB")];
        let unit = 0;
        while (bytes >= 1024 && unit < units.length - 1) {
            bytes /= 1024;
            unit++;
        }
        const digits = unit === 0 || bytes >= 10 ? 0 : 1;
        return bytes.toFixed(digits) + " " + units[unit];
    }

    function formatDate(value): string {
        const timestamp = Number(value ?? 0);
        return timestamp > 0 ? Qt.formatDateTime(new Date(timestamp), "dd MMM yyyy · HH:mm") : "—";
    }

    function filterEntries(): var {
        const rows = Array.from(root.displayedEntries ?? []);
        const terms = root.searchQuery.trim().toLocaleLowerCase().split(/\s+/).filter(term => term.length > 0);
        if (terms.length === 0)
            return rows;
        const ranked = [];
        for (const entry of rows) {
            const name = String(entry.name ?? "").toLocaleLowerCase();
            const haystack = [name, entry.extension, entry.mime].join(" ").toLocaleLowerCase();
            if (!terms.every(term => haystack.includes(term)))
                continue;
            let score = 0;
            for (const term of terms) {
                if (name === term)
                    score += 1000;
                else if (name.startsWith(term))
                    score += 300;
                else
                    score += Math.max(1, 100 - name.indexOf(term));
            }
            ranked.push({ entry: entry, score: score });
        }
        ranked.sort((a, b) => b.score - a.score || String(a.entry.name).localeCompare(String(b.entry.name)));
        return ranked.map(row => row.entry);
    }

    function buildActions(): var {
        const hasEntry = root.selectedEntry !== null;
        const canUseEntry = hasEntry && root.contentReady;
        const canMutateEntry = canUseEntry && !backend.operating;
        return [
            { id: "open", label: root.selectedEntry?.isDir ? Translation.tr("Open directory") : Translation.tr("Open file"), icon: "open_in_new", keys: ["↵"], enabled: canUseEntry },
            { id: "external", label: Translation.tr("Open externally"), icon: "launch", actionId: "secondary", keys: ["Ctrl", "↵"], enabled: canUseEntry },
            { id: "mark", label: root.isMarked(root.selectedEntry?.path) ? Translation.tr("Unmark item") : Translation.tr("Mark item"), icon: "select_check_box", actionId: "select", keys: ["Ctrl", "Space"], enabled: canUseEntry },
            { id: "copy-path", label: Translation.tr("Copy path"), icon: "content_copy", actionId: "copy", keys: ["Ctrl", "C"], enabled: canUseEntry },
            { id: "pin-folder", label: root.isPinnedFolder(root.selectedEntry?.path) ? Translation.tr("Unpin folder from Dock") : Translation.tr("Pin folder to Dock"), icon: root.isPinnedFolder(root.selectedEntry?.path) ? "folder_off" : "create_new_folder", enabled: canUseEntry && root.selectedEntry?.isDir },
            { id: "stage-copy", label: Translation.tr("Copy for paste"), icon: "file_copy", actionId: "stageCopy", keys: ["Ctrl", "Shift", "C"], enabled: canUseEntry },
            { id: "cut", label: Translation.tr("Cut for paste"), icon: "content_cut", actionId: "cut", keys: ["Ctrl", "X"], enabled: canUseEntry },
            { id: "paste", label: Translation.tr("Paste here"), icon: "content_paste", actionId: "paste", keys: ["Ctrl", "V"], enabled: root.contentReady && !root.globalSearchMode && !backend.operating && root.stagedPaths.length > 0 },
            { id: "rename", label: Translation.tr("Rename"), icon: "drive_file_rename_outline", actionId: "edit", keys: ["Ctrl", "E"], enabled: canMutateEntry },
            { id: "duplicate", label: Translation.tr("Duplicate"), icon: "control_point_duplicate", actionId: "duplicate", keys: ["Ctrl", "D"], enabled: canMutateEntry },
            { id: "new-file", label: Translation.tr("New file"), icon: "note_add", actionId: "create", keys: ["Ctrl", "N"], enabled: root.contentReady && !root.globalSearchMode && !backend.operating },
            { id: "new-folder", label: Translation.tr("New folder"), icon: "create_new_folder", actionId: "createFolder", keys: ["Ctrl", "Shift", "N"], enabled: root.contentReady && !root.globalSearchMode && !backend.operating },
            { id: "hidden", label: root.showHidden ? Translation.tr("Hide dotfiles") : Translation.tr("Show dotfiles"), icon: root.showHidden ? "visibility_off" : "visibility", actionId: "toggleHidden", keys: ["Ctrl", "H"], enabled: true },
            { id: "sort", label: Translation.tr("Change sort order"), icon: "sort", actionId: "sortFiles", keys: ["Ctrl", "Shift", "S"], enabled: true },
            { id: "home", label: Translation.tr("Go home"), icon: "home", actionId: "goHome", keys: ["Ctrl", "Home"], enabled: root.globalSearchMode || backend.currentPath !== root.homePath },
            { id: "forward", label: Translation.tr("Go forward"), icon: "arrow_forward", actionId: "forward", keys: ["Alt", "→"], enabled: root.forwardHistory.length > 0 },
            { id: "refresh", label: Translation.tr("Refresh directory"), icon: "refresh", actionId: "refresh", keys: ["Ctrl", "R"], enabled: true },
            { id: "trash", label: Translation.tr("Move to Trash"), icon: "delete", actionId: "delete", keys: ["Shift", "Del"], enabled: canMutateEntry }
        ];
    }

    function clampSelection(): void {
        if (root.filteredEntries.length === 0) {
            root.selectedIndex = -1;
            backend.inspect("");
            return;
        }
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.filteredEntries.length - 1));
        fileList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        previewDebounce.restart();
    }

    function tryConsumePathQuery(): bool {
        if (root.consumingPathQuery)
            return false;
        const query = root.searchQuery.trim();
        if (query.length === 0 || !query.startsWith("/") || !query.endsWith("/"))
            return false;
        root.consumingPathQuery = true;
        const target = query.startsWith("//") ? query.slice(1) : root.homePath + query;
        root.enterDirectory(target, true);
        root.requestSetSearchQuery("");
        root.consumingPathQuery = false;
        return true;
    }

    function searchEntryFromPath(rawPath): var {
        const sourcePath = String(rawPath ?? "");
        const isDir = sourcePath.endsWith("/");
        const path = isDir ? sourcePath.slice(0, -1) : sourcePath;
        if (path.length === 0)
            return null;
        const separator = path.lastIndexOf("/");
        const name = separator >= 0 ? path.slice(separator + 1) : path;
        const parent = separator > 0 ? path.slice(0, separator) : "/";
        const dot = name.lastIndexOf(".");
        return {
            path: path,
            name: name,
            parent: parent,
            isDir: isDir,
            isSymlink: false,
            isImage: false,
            isVideo: false,
            isAudio: false,
            isPdf: false,
            isText: false,
            executable: false,
            extension: !isDir && dot > 0 ? name.slice(dot + 1) : "",
            mime: isDir ? "inode/directory" : "",
            size: 0,
            modifiedMs: 0,
            createdMs: 0,
            createdIsChangeTime: false,
            permissions: "—",
            mode: "",
            owner: "—",
            group: "—"
        };
    }

    function consumeGlobalSearchResults(): void {
        const request = Number(GlobalStates.fileBrowserSearchRequest ?? 0);
        if (request === root.consumedGlobalSearchRequest)
            return;
        root.consumedGlobalSearchRequest = request;
        const entries = Array.from(GlobalStates.fileBrowserSearchResults ?? [])
            .map(path => root.searchEntryFromPath(path))
            .filter(entry => entry !== null);
        root.globalSearchEntries = entries;
        root.globalSearchQuery = String(GlobalStates.fileBrowserSearchQuery ?? "");
        root.globalSearchMode = entries.length > 0;
        root.markedPaths = ({});
        root.confirmTrash = false;
        root.actionMenuOpen = false;
        root.selectedIndex = entries.length > 0 ? 0 : -1;
        if (root.globalSearchMode)
            root.clampSelection();
    }

    function leaveGlobalSearchResults(): bool {
        if (!root.globalSearchMode)
            return false;
        root.globalSearchMode = false;
        root.globalSearchEntries = [];
        root.globalSearchQuery = "";
        root.markedPaths = ({});
        root.selectedIndex = -1;
        return true;
    }

    function enterDirectory(path, remember = true): bool {
        const target = String(path ?? "").replace(/\/$/, "") || "/";
        if (target.length === 0)
            return false;
        root.leaveGlobalSearchResults();
        if (remember && backend.currentPath.length > 0 && target !== backend.currentPath) {
            root.backHistory = root.backHistory.concat([{ path: backend.currentPath, index: root.selectedIndex }]);
            root.forwardHistory = [];
        }
        root.confirmTrash = false;
        root.actionMenuOpen = false;
        root.requestSetSearchQuery("");
        backend.listDirectory(target, root.showHidden, root.sortMode, root.sortDescending);
        return true;
    }

    function navigateBack(): bool {
        if (root.handleEscape())
            return true;
        if (root.globalSearchMode) {
            root.leaveGlobalSearchResults();
            root.backHistory = [];
            root.forwardHistory = [];
            backend.listDirectory(root.homePath, root.showHidden, root.sortMode, root.sortDescending);
            return true;
        }
        if (root.backHistory.length > 0) {
            const item = root.backHistory[root.backHistory.length - 1];
            root.backHistory = root.backHistory.slice(0, -1);
            if (backend.currentPath.length > 0)
                root.forwardHistory = root.forwardHistory.concat([{ path: backend.currentPath, index: root.selectedIndex }]);
            root.pendingSelectionIndex = Number(item.index ?? 0);
            backend.listDirectory(item.path, root.showHidden, root.sortMode, root.sortDescending);
            return true;
        }
        if (backend.currentPath.length > 0 && backend.currentPath !== root.homePath && backend.currentPath !== "/")
            return root.enterDirectory(FileUtils.parentDirectory(backend.currentPath) || "/", true);
        return false;
    }

    function navigateForward(): bool {
        if (root.forwardHistory.length === 0)
            return false;
        const item = root.forwardHistory[root.forwardHistory.length - 1];
        root.forwardHistory = root.forwardHistory.slice(0, -1);
        if (backend.currentPath.length > 0)
            root.backHistory = root.backHistory.concat([{ path: backend.currentPath, index: root.selectedIndex }]);
        root.pendingSelectionIndex = Number(item.index ?? 0);
        backend.listDirectory(item.path, root.showHidden, root.sortMode, root.sortDescending);
        return true;
    }

    function navigateUp(): bool {
        if (root.actionMenuOpen) {
            return root.moveActionSelection(-1);
        }
        if (!root.contentReady)
            return false;
        if (root.selectedIndex <= 0)
            return false;
        root.selectedIndex--;
        fileList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateDown(): bool {
        if (root.actionMenuOpen) {
            return root.moveActionSelection(1);
        }
        if (!root.contentReady)
            return false;
        if (root.selectedIndex < 0 || root.selectedIndex >= root.filteredEntries.length - 1)
            return false;
        root.selectedIndex++;
        fileList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateLeft(): bool {
        return root.navigateBack();
    }

    function navigateRight(): bool {
        if (root.actionMenuOpen)
            return false;
        if (!root.contentReady)
            return false;
        if (root.selectedEntry?.isDir)
            return root.enterDirectory(root.selectedEntry.path, true);
        return root.navigateForward();
    }

    function activateSelected(): bool {
        if (root.actionMenuOpen)
            return root.runAction(root.actionRows[root.actionIndex]?.id);
        if (root.confirmTrash)
            return root.confirmTrashNow();
        if (!root.contentReady)
            return false;
        const entry = root.selectedEntry;
        if (!entry)
            return false;
        if (entry.isDir)
            return root.enterDirectory(entry.path, true);
        Quickshell.execDetached(["xdg-open", entry.path]);
        GlobalStates.overviewOpen = false;
        return true;
    }

    function secondaryActivateSelected(): bool {
        if (!root.contentReady)
            return false;
        const entry = root.selectedEntry;
        if (!entry)
            return false;
        Quickshell.execDetached(["xdg-open", entry.isDir ? entry.path : entry.parent]);
        GlobalStates.overviewOpen = false;
        return true;
    }

    function focusInput(): bool {
        return false;
    }

    function handleEscape(): bool {
        if (root.actionMenuOpen) {
            root.actionMenuOpen = false;
            return true;
        }
        if (root.editorMode.length > 0) {
            root.closeEditor();
            return true;
        }
        if (root.confirmTrash) {
            root.cancelTrashConfirmation();
            return true;
        }
        return false;
    }

    function closeTransientOverlays(except = ""): void {
        if (except !== "actions")
            root.actionMenuOpen = false;
        if (except !== "editor") {
            root.editorMode = "";
            root.editorValue = "";
            root.editorTargetPath = "";
        }
        if (except !== "trash") {
            root.confirmTrash = false;
            root.pendingTrashPaths = [];
        }
    }

    function toggleActions(): bool {
        const opening = !root.actionMenuOpen;
        root.closeTransientOverlays(opening ? "actions" : "");
        root.actionMenuOpen = opening;
        root.actionIndex = root.firstEnabledActionIndex();
        return true;
    }

    function firstEnabledActionIndex(): int {
        for (let index = 0; index < root.actionRows.length; index++) {
            if (root.actionRows[index]?.enabled)
                return index;
        }
        return -1;
    }

    function moveActionSelection(step): bool {
        if (root.actionRows.length === 0)
            return false;
        let index = root.actionIndex;
        for (let visited = 0; visited < root.actionRows.length; visited++) {
            index = Math.max(0, Math.min(root.actionRows.length - 1, index + step));
            if (root.actionRows[index]?.enabled) {
                root.actionIndex = index;
                actionList.positionViewAtIndex(index, ListView.Contain);
                return true;
            }
            if (index === 0 || index === root.actionRows.length - 1)
                break;
        }
        return false;
    }

    function isMarked(path): bool {
        return String(path ?? "").length > 0 && root.markedPaths[String(path)] === true;
    }

    function toggleSelection(): bool {
        const path = String(root.selectedEntry?.path ?? "");
        if (path.length === 0)
            return false;
        const next = Object.assign({}, root.markedPaths);
        if (next[path])
            delete next[path];
        else
            next[path] = true;
        root.markedPaths = next;
        root.showNotice(next[path] ? Translation.tr("Item marked") : Translation.tr("Item unmarked"));
        return true;
    }

    function isPinnedFolder(path): bool {
        return TaskbarApps.isPinnedFile(String(path ?? ""));
    }

    function togglePinnedFolder(): bool {
        const entry = root.selectedEntry;
        if (!entry?.isDir)
            return false;
        TaskbarApps.togglePinnedFile(entry.path);
        root.showNotice(TaskbarApps.isPinnedFile(entry.path)
            ? Translation.tr("Folder pinned to Dock")
            : Translation.tr("Folder unpinned from Dock"));
        return true;
    }

    function operationTargets(): var {
        if (!root.contentReady)
            return [];
        const marked = Object.keys(root.markedPaths);
        if (marked.length > 0)
            return marked;
        const path = String(root.selectedEntry?.path ?? "");
        return path.length > 0 ? [path] : [];
    }

    function copySelected(): bool {
        const paths = root.operationTargets();
        if (paths.length === 0)
            return false;
        Quickshell.clipboardText = paths.join("\n");
        root.showNotice(paths.length === 1 ? Translation.tr("Path copied") : Translation.tr("%1 paths copied").arg(String(paths.length)));
        return true;
    }

    function stageCopy(): bool {
        const paths = root.operationTargets();
        if (paths.length === 0)
            return false;
        root.stagedPaths = paths;
        root.stagedCut = false;
        root.showNotice(Translation.tr("Ready to copy %1 item(s)").arg(String(paths.length)));
        return true;
    }

    function cutSelected(): bool {
        const paths = root.operationTargets();
        if (paths.length === 0)
            return false;
        root.stagedPaths = paths;
        root.stagedCut = true;
        root.showNotice(Translation.tr("Ready to move %1 item(s)").arg(String(paths.length)));
        return true;
    }

    function pasteClipboard(): bool {
        if (root.stagedPaths.length === 0 || backend.currentPath.length === 0)
            return false;
        return backend.operate(root.stagedCut ? "move" : "copy", {
            destination: backend.currentPath,
            paths: root.stagedPaths
        });
    }

    function editSelected(): bool {
        const entry = root.selectedEntry;
        if (!entry)
            return false;
        return root.openEditor("rename", entry.name, entry.path);
    }

    function createFromQuery(): bool {
        const suggested = root.searchQuery.trim();
        return root.openEditor("create-file", suggested.length > 0 ? suggested : Translation.tr("New file"));
    }

    function createFolder(): bool {
        return root.openEditor("create-directory", Translation.tr("New folder"));
    }

    function duplicateSelected(): bool {
        const entry = root.selectedEntry;
        return entry ? backend.operate("duplicate", { path: entry.path }) : false;
    }

    function deleteSelected(): bool {
        const targets = root.operationTargets();
        if (root.editorMode.length > 0 || targets.length === 0 || backend.operating)
            return false;
        root.closeTransientOverlays("trash");
        root.pendingTrashPaths = targets;
        root.trashPresentedCount = targets.length;
        root.confirmTrash = true;
        root.showNotice(Translation.tr("Press Enter to move the selection to Trash"));
        return true;
    }

    function cancelTrashConfirmation(): void {
        root.confirmTrash = false;
        root.pendingTrashPaths = [];
    }

    function confirmTrashNow(): bool {
        const targets = Array.from(root.pendingTrashPaths ?? []);
        root.confirmTrash = false;
        root.pendingTrashPaths = [];
        return targets.length > 0 && backend.operate("trash", { paths: targets });
    }

    function toggleHidden(): bool {
        root.showHidden = !root.showHidden;
        return root.refreshDirectory();
    }

    function refreshDirectory(): bool {
        if (root.globalSearchMode) {
            backend.inspect(String(root.selectedEntry?.path ?? ""));
            return true;
        }
        if (backend.currentPath.length === 0)
            return false;
        backend.listDirectory(backend.currentPath, root.showHidden, root.sortMode, root.sortDescending);
        return true;
    }

    function goHome(): bool {
        if (root.globalSearchMode) {
            root.leaveGlobalSearchResults();
            root.backHistory = [];
            root.forwardHistory = [];
            backend.listDirectory(root.homePath, root.showHidden, root.sortMode, root.sortDescending);
            return true;
        }
        return backend.currentPath === root.homePath ? false : root.enterDirectory(root.homePath, true);
    }

    function cycleSort(): bool {
        const modes = ["name", "modified", "size", "type"];
        const index = modes.indexOf(root.sortMode);
        root.sortMode = modes[(index + 1) % modes.length];
        root.refreshDirectory();
        return true;
    }

    function toggleSection(): bool {
        root.detailsFirst = !root.detailsFirst;
        return true;
    }

    function openEditor(mode, value, targetPath = ""): bool {
        root.closeTransientOverlays("editor");
        root.editorPresentedMode = String(mode ?? "");
        root.editorMode = root.editorPresentedMode;
        root.editorValue = String(value ?? "");
        root.editorTargetPath = String(targetPath ?? "");
        editorFocusTimer.restart();
        return true;
    }

    function closeEditor(): void {
        root.editorMode = "";
        root.editorValue = "";
        root.editorTargetPath = "";
        root.requestFocusSearchInput();
    }

    function submitEditor(): bool {
        const value = editorField.text.trim();
        if (value.length === 0)
            return false;
        let started = false;
        if (root.editorMode === "rename" && root.editorTargetPath.length > 0)
            started = backend.operate("rename", { path: root.editorTargetPath, name: value });
        else if (root.editorMode === "create-file" || root.editorMode === "create-directory")
            started = backend.operate(root.editorMode, { destination: backend.currentPath, name: value });
        if (started)
            root.closeEditor();
        return started;
    }

    function runAction(actionId): bool {
        root.actionMenuOpen = false;
        switch (String(actionId ?? "")) {
        case "open": return root.activateSelected();
        case "external": return root.secondaryActivateSelected();
        case "mark": return root.toggleSelection();
        case "copy-path": return root.copySelected();
        case "pin-folder": return root.togglePinnedFolder();
        case "stage-copy": return root.stageCopy();
        case "cut": return root.cutSelected();
        case "paste": return root.pasteClipboard();
        case "rename": return root.editSelected();
        case "duplicate": return root.duplicateSelected();
        case "new-file": return root.createFromQuery();
        case "new-folder": return root.createFolder();
        case "hidden": return root.toggleHidden();
        case "sort": return root.cycleSort();
        case "home": return root.goHome();
        case "forward": return root.navigateForward();
        case "refresh": return root.refreshDirectory();
        case "trash": return root.deleteSelected();
        default: return false;
        }
    }

    function showNotice(message): void {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    onFilteredEntriesChanged: root.clampSelection()
    onSelectedIndexChanged: previewDebounce.restart()
    onSelectedEntryChanged: previewSelectionAnimation.restart()
    onSearchQueryChanged: {
        if (!root.tryConsumePathQuery()) {
            root.selectedIndex = root.filteredEntries.length > 0 ? 0 : -1;
            root.clampSelection();
        }
    }

    Component.onCompleted: {
        root.consumeGlobalSearchResults();
        if (!root.globalSearchMode)
            backend.listDirectory(root.homePath, root.showHidden, root.sortMode, root.sortDescending);
    }

    Timer {
        id: previewDebounce
        interval: 90
        onTriggered: backend.inspect(String(root.selectedEntry?.path ?? ""))
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    Timer {
        id: editorFocusTimer
        interval: 0
        onTriggered: {
            if (root.editorMode.length === 0)
                return;
            editorField.text = root.editorValue;
            editorField.selectAll();
            editorField.forceActiveFocus();
        }
    }

    NumberAnimation {
        id: previewSelectionAnimation
        target: previewContent
        property: "opacity"
        from: 0.35
        to: 1.0
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    NumberAnimation {
        id: directoryRevealAnimation
        target: root
        property: "directoryRevealProgress"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveSmall.duration
        easing.type: Appearance.animation.elementMoveSmall.type
        easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
    }

    ParallelAnimation {
        id: actionMenuEnterAnimation

        NumberAnimation {
            target: root
            property: "actionMenuVisualOpacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "actionMenuVisualScale"
            from: 0.82
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }
        NumberAnimation {
            target: root
            property: "actionMenuVisualOffset"
            from: Appearance.sizes.elevationMargin * 5
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutBack
            easing.overshoot: 2.5
        }
    }

    ParallelAnimation {
        id: actionMenuExitAnimation

        NumberAnimation {
            target: root
            property: "actionMenuVisualOpacity"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "actionMenuVisualScale"
            to: 0.94
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "actionMenuVisualOffset"
            to: Appearance.sizes.elevationMargin * 2
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }

    FileBrowserBackend {
        id: backend
    }

    Connections {
        target: backend

        function onDirectoryLoaded(path) {
            if (root.globalSearchMode)
                return;
            root.selectedIndex = root.filteredEntries.length > 0
                ? Math.max(0, Math.min(root.pendingSelectionIndex < 0 ? 0 : root.pendingSelectionIndex, root.filteredEntries.length - 1))
                : -1;
            root.pendingSelectionIndex = -1;
            root.clampSelection();
            directoryRevealAnimation.restart();
        }

        function onOperationFinished(success, operation, message, affected) {
            const changedAnything = Array.from(affected ?? []).length > 0;
            if (success) {
                root.markedPaths = ({});
                if (operation === "move") {
                    root.stagedPaths = [];
                    root.stagedCut = false;
                }
                root.showNotice(root.operationSuccessMessage(operation, affected));
                root.refreshDirectory();
            } else {
                root.showNotice(message);
                if (changedAnything)
                    root.refreshDirectory();
            }
        }
    }

    Connections {
        target: GlobalStates

        function onFileBrowserSearchRequestChanged() {
            root.consumeGlobalSearchResults();
        }
    }

    function operationSuccessMessage(operation, affected): string {
        const count = Array.from(affected ?? []).length;
        switch (operation) {
        case "trash": return Translation.tr("Moved %1 item(s) to Trash").arg(String(count));
        case "copy": return Translation.tr("Copied %1 item(s)").arg(String(count));
        case "move": return Translation.tr("Moved %1 item(s)").arg(String(count));
        case "rename": return Translation.tr("Item renamed");
        case "duplicate": return Translation.tr("Item duplicated");
        case "create-file": return Translation.tr("File created");
        case "create-directory": return Translation.tr("Folder created");
        default: return Translation.tr("File operation completed");
        }
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("File Browser")
        icon: "folder_data"
        accent: true
        minimumContentHeight: Config.options.search.fileBrowser.panelBodyHeight
        showStatus: true
        statusText: root.statusText
        primaryHint: ({ label: root.selectedEntry?.isDir ? Translation.tr("Browse") : Translation.tr("Open"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Actions"), actionId: "actions", keys: ["Ctrl", "K"] },
            { label: Translation.tr("Mark"), actionId: "select", keys: ["Ctrl", "Space"] },
            { label: Translation.tr("Back"), keys: ["Backspace"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                RippleButton {
                    enabled: root.backHistory.length > 0 || (backend.currentPath !== root.homePath && backend.currentPath !== "/")
                    Accessible.name: Translation.tr("Back to the previous folder")
                    implicitWidth: Appearance.sizes.elevationMargin * 4
                    implicitHeight: implicitWidth
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: root.navigateBack()
                    MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSecondaryContainer }
                    StyledToolTip { text: Translation.tr("Back to the previous folder · Backspace") }
                }

                RippleButton {
                    Accessible.name: Translation.tr("Go to Home")
                    implicitWidth: Appearance.sizes.elevationMargin * 4
                    implicitHeight: implicitWidth
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.goHome()
                    MaterialSymbol { anchors.centerIn: parent; text: "home"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSurface }
                    StyledToolTip { text: Translation.tr("Go to Home · Ctrl+Home") }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Appearance.sizes.elevationMargin * 4
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSurfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.sizes.elevationMargin
                        anchors.rightMargin: Appearance.sizes.elevationMargin
                        spacing: Appearance.sizes.elevationMargin / 2
                        MaterialSymbol { text: "folder_open"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colPrimary }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.displayPath(backend.currentPath || backend.pendingListPath)
                            elide: Text.ElideMiddle
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            visible: root.markedCount > 0
                            text: Translation.tr("%1 marked").arg(String(root.markedCount))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            visible: root.stagedPaths.length > 0
                            text: root.stagedCut
                                ? Translation.tr("Move %1").arg(String(root.stagedPaths.length))
                                : Translation.tr("Copy %1").arg(String(root.stagedPaths.length))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colTertiary
                        }
                    }
                }

                RippleButton {
                    Accessible.name: Translation.tr("Change file sorting")
                    implicitWidth: sortContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: Appearance.sizes.elevationMargin * 4
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.cycleSort()
                    RowLayout {
                        id: sortContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin / 2
                        MaterialSymbol { text: "sort"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnSurface }
                        StyledText { text: Translation.tr(root.sortMode); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnSurface }
                    }
                    StyledToolTip {
                        text: root.sortDescending
                            ? Translation.tr("Sorted by %1, descending · Ctrl+Shift+S").arg(Translation.tr(root.sortMode))
                            : Translation.tr("Sorted by %1, ascending · Ctrl+Shift+S").arg(Translation.tr(root.sortMode))
                    }
                }

                RippleButton {
                    Accessible.name: root.showHidden ? Translation.tr("Hide hidden files") : Translation.tr("Show hidden files")
                    implicitWidth: Appearance.sizes.elevationMargin * 4
                    implicitHeight: implicitWidth
                    buttonRadius: Appearance.rounding.full
                    toggled: root.showHidden
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colBackgroundToggled: Appearance.colors.colPrimaryContainer
                    colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    colRippleToggled: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.toggleHidden()
                    MaterialSymbol { anchors.centerIn: parent; text: root.showHidden ? "visibility" : "visibility_off"; iconSize: Appearance.font.pixelSize.normal; color: root.showHidden ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface }
                    StyledToolTip {
                        text: root.showHidden
                            ? Translation.tr("Hide dotfiles · Ctrl+H")
                            : Translation.tr("Show dotfiles · Ctrl+H")
                    }
                }
            }

            Item {
                id: browserBody
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    spacing: Appearance.sizes.elevationMargin
                    layoutDirection: root.detailsFirst ? Qt.RightToLeft : Qt.LeftToRight

                    Rectangle {
                        Layout.preferredWidth: browserBody.width * 0.42
                        Layout.fillHeight: true
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colSurfaceContainerHigh

                        ColumnLayout {
                            id: fileColumn
                            anchors.fill: parent
                            anchors.margins: root.panelGutter
                            spacing: 0
                            opacity: 0.3 + root.directoryRevealProgress * 0.7
                            transform: Translate {
                                // Stay inside the card's safety inset even at
                                // frame zero; the external card deliberately
                                // does not clip hover-scaled delegates.
                                y: (1 - root.directoryRevealProgress) * root.rowHoverGutter
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: root.rowHoverGutter
                                Layout.rightMargin: root.rowHoverGutter
                                Layout.bottomMargin: Appearance.sizes.elevationMargin / 4
                                StyledText { Layout.fillWidth: true; text: Translation.tr("Files"); font.weight: Font.DemiBold; color: Appearance.colors.colOnSurface }
                                StyledText { text: String(root.filteredEntries.length); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }

                            ListView {
                                id: fileList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: root.filteredEntries
                                visible: !root.listLoading && root.filteredEntries.length > 0
                                clip: true
                                spacing: Appearance.sizes.elevationMargin / 3
                                boundsBehavior: Flickable.StopAtBounds
                                reuseItems: true
                                cacheBuffer: height
                                currentIndex: root.selectedIndex
                                topMargin: root.rowHoverGutter
                                bottomMargin: root.rowHoverGutter

                                delegate: RippleButton {
                                    id: fileRow
                                    required property int index
                                    required property var modelData
                                    readonly property bool selected: root.selectedIndex === index
                                    readonly property bool marked: root.isMarked(modelData.path)
                                    x: root.rowHoverGutter
                                    width: Math.max(0, ListView.view.width - root.rowHoverGutter * 2)
                                    implicitHeight: Appearance.sizes.elevationMargin * 5
                                    buttonRadius: selected ? Appearance.rounding.full : Appearance.rounding.normal
                                    colBackground: selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                                    colBackgroundHover: selected ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                                    colRipple: selected ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                                    onClicked: { root.selectedIndex = index; root.activateSelected(); }
                                    onHoveredChanged: if (hovered) root.selectedIndex = index

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Appearance.sizes.elevationMargin
                                        anchors.rightMargin: Appearance.sizes.elevationMargin
                                        spacing: Appearance.sizes.elevationMargin

                                        MaterialShape {
                                            implicitSize: Appearance.sizes.elevationMargin * 3.5
                                            shapeString: fileRow.selected ? "Circle" : "Clover8Leaf"
                                            color: fileRow.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: root.fileIcon(fileRow.modelData)
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: fileRow.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: fileRow.modelData.name
                                                elide: Text.ElideMiddle
                                                font.weight: fileRow.selected ? Font.DemiBold : Font.Normal
                                                color: fileRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: fileRow.modelData.isDir
                                                    ? Translation.tr("Directory")
                                                    : root.formatBytes(fileRow.modelData.size) + " · " + String(fileRow.modelData.extension || fileRow.modelData.mime)
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: fileRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                                opacity: 0.78
                                            }
                                        }

                                        MaterialSymbol {
                                            visible: fileRow.marked || fileRow.modelData.isDir
                                            text: fileRow.marked ? "check_circle" : "chevron_right"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: fileRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                                        }

                                        ConfiguredKeyHint {
                                            visible: fileRow.selected && Config.options.search.appearance.showKeyHints
                                            fallbackKeys: ["↵"]
                                            surface: Appearance.colors.colPrimaryContainer
                                            onSurface: Appearance.colors.colOnPrimaryContainer
                                        }
                                    }
                                }

                                add: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.animation.elementMoveFast.duration }
                                        NumberAnimation { property: "y"; from: Appearance.sizes.elevationMargin; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                    }
                                }

                                ScrollEdgeFade {
                                    target: fileList
                                    color: Appearance.colors.colSurfaceContainerHigh
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: !root.listLoading && root.filteredEntries.length === 0
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: Appearance.sizes.elevationMargin
                                    MaterialShape {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitSize: Appearance.sizes.elevationMargin * 10
                                        shapeString: "Puffy"
                                        color: Appearance.colors.colSecondaryContainer
                                        MaterialSymbol { anchors.centerIn: parent; text: root.searchQuery.trim().length > 0 ? "search" : "folder"; iconSize: Appearance.font.pixelSize.huge * 1.6; color: Appearance.colors.colOnSecondaryContainer }
                                    }
                                    StyledText { Layout.alignment: Qt.AlignHCenter; text: root.searchQuery.trim().length > 0 ? Translation.tr("No file matches this search") : Translation.tr("This folder is empty"); font.weight: Font.DemiBold; color: Appearance.colors.colOnSurface }
                                    StyledText { Layout.alignment: Qt.AlignHCenter; text: root.searchQuery.trim().length > 0 ? Translation.tr("Try fewer words or clear the search field") : Translation.tr("Create a file or folder with the shortcuts below"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.listLoading
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: Appearance.sizes.elevationMargin
                                    MaterialShape {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitSize: Appearance.sizes.elevationMargin * 10
                                        shapeString: "ClamShell"
                                        color: Appearance.colors.colPrimaryContainer
                                        MaterialSymbol { anchors.centerIn: parent; text: "folder_open"; iconSize: Appearance.font.pixelSize.huge * 1.6; color: Appearance.colors.colOnPrimaryContainer }
                                    }
                                    StyledText { Layout.alignment: Qt.AlignHCenter; text: Translation.tr("Reading directory…"); color: Appearance.colors.colSubtext }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colSurfaceContainerHigh
                        clip: true

                        ColumnLayout {
                            id: previewContent
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin
                            opacity: 1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.sizes.elevationMargin
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText { Layout.fillWidth: true; text: root.selectedMetadata?.name ?? Translation.tr("Select a file"); elide: Text.ElideMiddle; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurface }
                                    StyledText { Layout.fillWidth: true; text: root.selectedMetadata ? root.displayPath(root.selectedMetadata.path) : Translation.tr("Preview and metadata appear here"); elide: Text.ElideMiddle; font.pixelSize: Appearance.font.pixelSize.smallest; font.family: Appearance.font.family.monospace; color: Appearance.colors.colSubtext }
                                }
                                ConfiguredKeyHint { visible: root.selectedEntry !== null && Config.options.search.appearance.showKeyHints; actionId: "actions"; fallbackKeys: ["Ctrl", "K"]; surface: Appearance.colors.colSecondaryContainer; onSurface: Appearance.colors.colOnSecondaryContainer }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: browserBody.height * 0.42
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colSurfaceContainerHighest
                                clip: true

                                StyledImage {
                                    anchors.fill: parent
                                    anchors.margins: Appearance.sizes.elevationMargin
                                    visible: root.selectedMetadata?.previewKind === "image"
                                    source: visible ? Qt.resolvedUrl(String(root.selectedMetadata?.path ?? "")) : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                ThumbnailImage {
                                    anchors.fill: parent
                                    anchors.margins: Appearance.sizes.elevationMargin
                                    visible: ["video", "pdf"].includes(String(root.selectedMetadata?.previewKind ?? ""))
                                    sourcePath: String(root.selectedMetadata?.path ?? "")
                                    fillMode: Image.PreserveAspectFit
                                    generateThumbnail: visible
                                }

                                StyledFlickable {
                                    anchors.fill: parent
                                    anchors.margins: Appearance.sizes.elevationMargin
                                    visible: root.selectedMetadata?.previewKind === "text"
                                    contentHeight: previewText.implicitHeight
                                    clip: true
                                    StyledText {
                                        id: previewText
                                        width: parent.width
                                        text: String(root.selectedMetadata?.previewText ?? "")
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WrapAnywhere
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSurface
                                    }
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    visible: root.selectedMetadata !== null
                                        && !["image", "video", "pdf", "text"].includes(String(root.selectedMetadata?.previewKind ?? ""))
                                    spacing: Appearance.sizes.elevationMargin
                                    MaterialShape {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitSize: Appearance.sizes.elevationMargin * 9
                                        shapeString: root.fileShape(root.selectedMetadata)
                                        color: Appearance.colors.colPrimaryContainer
                                        MaterialSymbol { anchors.centerIn: parent; text: root.fileIcon(root.selectedMetadata); iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colOnPrimaryContainer }
                                    }
                                    StyledText { Layout.alignment: Qt.AlignHCenter; text: root.typeLabel(root.selectedMetadata); color: Appearance.colors.colSubtext }
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    visible: root.selectedMetadata === null
                                    spacing: Appearance.sizes.elevationMargin
                                    MaterialShape {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitSize: Appearance.sizes.elevationMargin * 8
                                        shapeString: "ClamShell"
                                        color: Appearance.colors.colSecondaryContainer
                                        MaterialSymbol { anchors.centerIn: parent; text: backend.inspecting ? "hourglass_top" : "preview"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colOnSecondaryContainer }
                                    }
                                    StyledText { Layout.alignment: Qt.AlignHCenter; text: backend.inspecting ? Translation.tr("Preparing preview…") : Translation.tr("Choose an item to inspect"); color: Appearance.colors.colSubtext }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: Appearance.sizes.elevationMargin
                                rowSpacing: Appearance.sizes.elevationMargin / 2
                                Repeater {
                                    model: root.metadataRows
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: metaRow.implicitHeight + Appearance.sizes.elevationMargin
                                        radius: Appearance.rounding.normal
                                        color: Appearance.colors.colSurfaceContainerHighest
                                        RowLayout {
                                            id: metaRow
                                            anchors.fill: parent
                                            anchors.leftMargin: Appearance.sizes.elevationMargin
                                            anchors.rightMargin: Appearance.sizes.elevationMargin
                                            spacing: Appearance.sizes.elevationMargin / 2
                                            MaterialSymbol { text: parent.parent.modelData.icon; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colPrimary }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                StyledText { Layout.fillWidth: true; text: parent.parent.parent.modelData.label; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                                                StyledText { Layout.fillWidth: true; text: parent.parent.parent.modelData.value; elide: Text.ElideMiddle; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnSurface }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: modalScrim
                    z: 4
                    readonly property bool overlayOpen: root.actionMenuOpen
                        || root.editorMode.length > 0
                        || root.confirmTrash
                    anchors.fill: parent
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colScrim
                    visible: overlayOpen || opacity > 0.01
                    enabled: overlayOpen
                    opacity: overlayOpen ? 1 : 0

                    TapHandler {
                        onTapped: {
                            if (root.actionMenuOpen)
                                root.actionMenuOpen = false;
                            else if (root.editorMode.length > 0)
                                root.closeEditor();
                            else if (root.confirmTrash)
                                root.cancelTrashConfirmation();
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }

                Rectangle {
                    id: actionMenu
                    z: 5
                    visible: root.actionMenuOpen
                        || actionMenuEnterAnimation.running
                        || actionMenuExitAnimation.running
                        || opacity > 0.01
                    enabled: root.actionMenuOpen
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: Appearance.sizes.elevationMargin
                    width: parent.width * 0.46
                    height: Math.min(parent.height - Appearance.sizes.elevationMargin * 2, actionColumn.implicitHeight + Appearance.sizes.elevationMargin)
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerHighest
                    opacity: root.actionMenuVisualOpacity
                    scale: root.actionMenuVisualScale
                    transformOrigin: Item.BottomRight
                    transform: Translate {
                        y: root.actionMenuVisualOffset
                    }

                    ColumnLayout {
                        id: actionColumn
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.sizes.elevationMargin
                        anchors.rightMargin: Appearance.sizes.elevationMargin
                        anchors.topMargin: Appearance.sizes.elevationMargin
                        anchors.bottomMargin: 0
                        spacing: Appearance.sizes.elevationMargin / 2
                        RowLayout {
                            Layout.fillWidth: true
                            MaterialShape { implicitSize: Appearance.sizes.elevationMargin * 4; shapeString: "Burst"; color: Appearance.colors.colTertiaryContainer; MaterialSymbol { anchors.centerIn: parent; text: "bolt"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnTertiaryContainer } }
                            ColumnLayout { Layout.fillWidth: true; spacing: 0; StyledText { text: Translation.tr("File actions"); font.weight: Font.DemiBold; color: Appearance.colors.colOnSurface } StyledText { text: Translation.tr("Every action is keyboard-accessible"); font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext } }
                        }
                        ListView {
                            id: actionList
                            Layout.fillWidth: true
                            Layout.leftMargin: root.rowHoverGutter
                            Layout.rightMargin: root.rowHoverGutter
                            Layout.preferredHeight: Math.min(contentHeight, browserBody.height - Appearance.sizes.elevationMargin * 9)
                            model: root.actionRows
                            spacing: Appearance.sizes.elevationMargin / 3
                            clip: true
                            currentIndex: root.actionIndex
                            topMargin: root.rowHoverGutter
                            delegate: RippleButton {
                                id: actionRow
                                required property int index
                                required property var modelData
                                width: ListView.view.width
                                implicitHeight: Appearance.sizes.elevationMargin * 4.5
                                // The popup intentionally has no trailing list
                                // gutter. Keep pointer hover at 1:1 so its last
                                // action never needs clipping compensation.
                                scale: down ? 0.98 : 1
                                enabled: modelData.enabled
                                buttonRadius: root.actionIndex === index ? Appearance.rounding.large : Appearance.rounding.normal
                                colBackground: root.actionIndex === index ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSurfaceContainerHigh
                                colBackgroundHover: root.actionIndex === index ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                                colRipple: root.actionIndex === index ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                                onHoveredChanged: if (hovered) root.actionIndex = index
                                onClicked: { root.actionIndex = index; root.runAction(modelData.id); }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Appearance.sizes.elevationMargin
                                    anchors.rightMargin: Appearance.sizes.elevationMargin
                                    spacing: Appearance.sizes.elevationMargin
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: actionRow.modelData.icon
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: root.actionIndex === actionRow.index ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: actionRow.modelData.label
                                        color: root.actionIndex === actionRow.index ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurface
                                    }
                                    ConfiguredKeyHint {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: (actionRow.modelData.keys ?? []).length > 0 && Config.options.search.appearance.showKeyHints
                                        actionId: actionRow.modelData.actionId ?? ""
                                        fallbackKeys: actionRow.modelData.keys ?? []
                                        surface: root.actionIndex === actionRow.index ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSurfaceContainerHigh
                                        onSurface: root.actionIndex === actionRow.index ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurface
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: editorPopup
                    z: 6
                    visible: root.editorMode.length > 0 || opacity > 0.01
                    enabled: root.editorMode.length > 0
                    anchors.centerIn: parent
                    width: parent.width * 0.58
                    height: editorColumn.implicitHeight + Appearance.sizes.elevationMargin * 3
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colSurfaceContainerHighest
                    opacity: root.editorMode.length > 0 ? 1 : 0
                    scale: root.editorMode.length > 0 ? 1 : 0.94
                    transformOrigin: Item.Center

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.editorMode.length > 0
                                ? Appearance.animation.elementMoveEnter.duration
                                : Appearance.animation.elementMoveExit.duration
                            easing.type: root.editorMode.length > 0
                                ? Appearance.animation.elementMoveEnter.type
                                : Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: root.editorMode.length > 0
                                ? Appearance.animation.elementMoveEnter.bezierCurve
                                : Appearance.animation.elementMoveExit.bezierCurve
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: root.editorMode.length > 0
                                ? Appearance.animation.elementResize.duration
                                : Appearance.animation.elementMoveExit.duration
                            easing.type: root.editorMode.length > 0
                                ? Appearance.animation.elementResize.type
                                : Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: root.editorMode.length > 0
                                ? Appearance.animation.elementResize.bezierCurve
                                : Appearance.animation.elementMoveExit.bezierCurve
                        }
                    }

                    ColumnLayout {
                        id: editorColumn
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin * 1.5
                        spacing: Appearance.sizes.elevationMargin
                        RowLayout {
                            Layout.fillWidth: true
                            MaterialShape { implicitSize: Appearance.sizes.elevationMargin * 5; shapeString: root.editorPresentedMode === "create-directory" ? "Arch" : "Cookie4Sided"; color: Appearance.colors.colPrimaryContainer; MaterialSymbol { anchors.centerIn: parent; text: root.editorPresentedMode === "rename" ? "drive_file_rename_outline" : (root.editorPresentedMode === "create-directory" ? "create_new_folder" : "note_add"); iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnPrimaryContainer } }
                            ColumnLayout { Layout.fillWidth: true; spacing: 0; StyledText { text: root.editorPresentedMode === "rename" ? Translation.tr("Rename item") : (root.editorPresentedMode === "create-directory" ? Translation.tr("Create folder") : Translation.tr("Create file")); font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurface } StyledText { Layout.fillWidth: true; text: root.displayPath(backend.currentPath); elide: Text.ElideMiddle; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext } }
                        }
                        ToolbarTextField {
                            id: editorField
                            Layout.fillWidth: true
                            implicitHeight: Appearance.sizes.elevationMargin * 5
                            placeholderText: Translation.tr("Name")
                            colBackground: Appearance.colors.colSurfaceContainerHigh
                            onAccepted: root.submitEditor()
                            Keys.onEscapePressed: event => { root.closeEditor(); event.accepted = true; }
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            RippleButton { implicitWidth: cancelLabel.implicitWidth + Appearance.sizes.elevationMargin * 2; implicitHeight: Appearance.sizes.elevationMargin * 4; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colSurfaceContainerHigh; colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover; colRipple: Appearance.colors.colSurfaceContainerHighestActive; onClicked: root.closeEditor(); StyledText { id: cancelLabel; anchors.centerIn: parent; text: Translation.tr("Cancel"); color: Appearance.colors.colOnSurface } }
                            RippleButton { implicitWidth: confirmLabel.implicitWidth + Appearance.sizes.elevationMargin * 2; implicitHeight: Appearance.sizes.elevationMargin * 4; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colPrimaryContainer; colBackgroundHover: Appearance.colors.colPrimaryContainerHover; colRipple: Appearance.colors.colPrimaryContainerActive; onClicked: root.submitEditor(); RowLayout { id: confirmLabel; anchors.centerIn: parent; MaterialSymbol { text: "check"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnPrimaryContainer } StyledText { text: Translation.tr("Apply"); font.weight: Font.DemiBold; color: Appearance.colors.colOnPrimaryContainer } ConfiguredKeyHint { fallbackKeys: ["↵"]; surface: Appearance.colors.colPrimaryContainer; onSurface: Appearance.colors.colOnPrimaryContainer } } }
                        }
                    }
                }

                Rectangle {
                    id: trashPopup
                    z: 6
                    visible: root.confirmTrash || opacity > 0.01
                    enabled: root.confirmTrash
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Appearance.sizes.elevationMargin
                    width: parent.width * 0.68
                    height: trashContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colErrorContainer
                    opacity: root.confirmTrash ? 1 : 0
                    transform: Translate {
                        y: root.confirmTrash ? 0 : Appearance.sizes.elevationMargin * 2
                        Behavior on y {
                            NumberAnimation {
                                duration: root.confirmTrash
                                    ? Appearance.animation.elementMoveEnter.duration
                                    : Appearance.animation.elementMoveExit.duration
                                easing.type: root.confirmTrash
                                    ? Appearance.animation.elementMoveEnter.type
                                    : Appearance.animation.elementMoveExit.type
                                easing.bezierCurve: root.confirmTrash
                                    ? Appearance.animation.elementMoveEnter.bezierCurve
                                    : Appearance.animation.elementMoveExit.bezierCurve
                            }
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.confirmTrash
                                ? Appearance.animation.elementMoveEnter.duration
                                : Appearance.animation.elementMoveExit.duration
                            easing.type: root.confirmTrash
                                ? Appearance.animation.elementMoveEnter.type
                                : Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: root.confirmTrash
                                ? Appearance.animation.elementMoveEnter.bezierCurve
                                : Appearance.animation.elementMoveExit.bezierCurve
                        }
                    }

                    RowLayout {
                        id: trashContent
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin
                        spacing: Appearance.sizes.elevationMargin
                        MaterialShape { implicitSize: Appearance.sizes.elevationMargin * 5; shapeString: "Boom"; color: Appearance.colors.colError; MaterialSymbol { anchors.centerIn: parent; text: "delete"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnError } }
                        ColumnLayout { Layout.fillWidth: true; spacing: 0; StyledText { text: Translation.tr("Move %1 item(s) to Trash?").arg(String(root.trashPresentedCount)); font.weight: Font.DemiBold; color: Appearance.colors.colOnErrorContainer } StyledText { text: Translation.tr("This is recoverable from your desktop Trash"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnErrorContainer } }
                        RippleButton { implicitWidth: trashCancel.implicitWidth + Appearance.sizes.elevationMargin * 2; implicitHeight: Appearance.sizes.elevationMargin * 4; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colSurfaceContainerHigh; colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover; colRipple: Appearance.colors.colSurfaceContainerHighestActive; onClicked: root.cancelTrashConfirmation(); StyledText { id: trashCancel; anchors.centerIn: parent; text: Translation.tr("Cancel"); color: Appearance.colors.colOnSurface } }
                        RippleButton { implicitWidth: trashConfirm.implicitWidth + Appearance.sizes.elevationMargin * 2; implicitHeight: Appearance.sizes.elevationMargin * 4; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colError; colBackgroundHover: Appearance.colors.colErrorHover; colRipple: Appearance.colors.colErrorActive; onClicked: root.confirmTrashNow(); RowLayout { id: trashConfirm; anchors.centerIn: parent; StyledText { text: Translation.tr("Move to Trash"); font.weight: Font.DemiBold; color: Appearance.colors.colOnError } ConfiguredKeyHint { fallbackKeys: ["↵"]; surface: Appearance.colors.colError; onSurface: Appearance.colors.colOnError } } }
                    }
                }
            }
        }
    }
}
