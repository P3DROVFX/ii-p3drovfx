import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

MouseArea {
    id: wallpaperSelectorContent

    /**
     * The same browser, laid out to live inside the Dynamic Island.
     *
     * One row of wallpapers instead of a page of them: the address row carries all of
     * the controls the row needs — the folder path, the search (a circle that expands
     * into a pill, pushing the path left), the favourite-folder star and the thumbnail
     * reload — so the grid reaches from the address row to the bottom edge with no
     * toolbar row beneath it. The sidebar goes (the island has no room for a second
     * navigation), and the full selector keeps its floating toolbars untouched. The
     * keyboard drives the row: arrows move the selection, Enter applies, typing opens
     * the search, Escape collapses the search or closes the browser.
     *
     * The host owns the surface, the keyboard handoff and the open animation in this
     * mode, so the panel's own background, shadow and entrance are all off; see
     * `active`, `closeRequested` and `takeKeyboard`.
     */
    property bool compact: false
    /** Compact only: the host says when the browser is on screen, so it can animate in. */
    property bool active: true
    /** Compact only: closing is the host's business - it owns the surface. */
    signal closeRequested

    property int columns: 4
    property real previewCellAspectRatio: 4 / 3

    // ── What the compact layout asks the island for ──────────────────────────
    // Declared sizes, never measured from anything that is itself animating: the island
    // animates toward these and drives our width and height in return, so the two can
    // never chase each other. (A host that animated toward a live measurement restarted
    // its own animation every frame - see the quick-toggle tray.)
    /**
     * How the island draws its row: "carousel" (cover-flow) or "row" (the plain row of
     * four). The full selector ignores it.
     */
    property string compactStyle: "row"
    readonly property bool useCarousel: compact && compactStyle === "carousel"
    /**
     * The shape of the screen the island is on, passed by the host. A wallpaper covers
     * every screen, so the card previews it the way the screen you are looking at crops
     * it; each monitor's island passes its own.
     */
    property real screenAspect: 16 / 10
    // Clamped so a super-ultrawide or a portrait screen still gets a readable card.
    readonly property real compactCardAspect: Math.max(9 / 16, Math.min(32 / 9, screenAspect))
    /**
     * The carousel's centred card: the screen's shape at a fixed area (336 x 210 at
     * 16:10), so a wider or taller screen reshapes the card instead of blowing it up.
     */
    readonly property real compactCardArea: 336 * 210
    readonly property real compactCardWidth: Math.round(Math.sqrt(compactCardArea * compactCardAspect))
    readonly property real compactCardHeight: Math.round(compactCardWidth / compactCardAspect)
    /** The 4:3 cell the full selector shows at rest; the plain row grows from this. */
    readonly property real compactBaseCellWidth: 208
    /**
     * One toolbar row taller than the natural 4:3. The compact layout moved the search
     * and the thumbnail reload up into the address row, and the wallpapers took back
     * the height the bottom row freed.
     */
    readonly property real compactCellHeight: Math.round(compactBaseCellWidth / previewCellAspectRatio)
        + Appearance.sizes.toolbarHeight + 12
    /** One cell of the single row; four of them make the row. The 4:3 ratio is kept. */
    readonly property real compactCellWidth: Math.round(compactCellHeight * previewCellAspectRatio)
    /** The one caption under the carousel: the centred wallpaper's name and its place. */
    readonly property real compactCaptionHeight: 50
    /** Room above the card for the hover grow and the selection ring. */
    readonly property real compactCardInset: 10
    readonly property real compactRowHeight: compactCardInset + compactCardHeight + compactCaptionHeight
    readonly property real compactPadding: 8
    // Carousel: the centred card and a neighbour and a half on each side, never
    // narrower than the plain row.
    readonly property real contentTargetWidth: 2 * compactPadding + (useCarousel
        ? Math.max(3 * compactCardWidth, wallpaperSelectorContent.columns * compactCellWidth)
        : wallpaperSelectorContent.columns * compactCellWidth)
    readonly property real contentTargetHeight: compactAddressRowHeight
        + (useCarousel ? compactRowHeight : compactCellHeight) + 2 * compactPadding
    /** The address row is fixed: it never animates. */
    readonly property real compactAddressRowHeight: Appearance.sizes.toolbarHeight + 8

    /**
     * Compact only: the search lives in a circle at the right of the address row and
     * expands into a pill that grows leftwards, pushing the path and the reload toggle
     * along with it. The circle position (the pill's right edge) never moves.
     */
    property bool compactSearchExpanded: false
    function openCompactSearch() {
        wallpaperSelectorContent.compactSearchExpanded = true;
        Qt.callLater(() => compactSearchFilter.forceActiveFocus());
    }

    function closeCompactSearch() {
        wallpaperSelectorContent.compactSearchExpanded = false;
        Qt.callLater(() => wallpaperSelectorContent.forceActiveFocus());
    }

    /** The field the search keys belong to, in whichever layout is on screen. */
    function activeSearchField() {
        return wallpaperSelectorContent.compact ? compactSearchFilter : extraOptions.searchField
    }

    function focusSearchInput() {
        if (wallpaperSelectorContent.compact)
            wallpaperSelectorContent.openCompactSearch();
        else
            extraOptions.focusSearch();
    }

    function setSearchText(text) {
        const field = wallpaperSelectorContent.activeSearchField();
        field.text = text;
        field.cursorPosition = text.length;
    }

    function clearSearchInput() {
        wallpaperSelectorContent.setSearchText("");
    }

    /**
     * Compact only: the island calls this when the face appears. The keyboard starts
     * on the browser itself, not on the search field — arrows must navigate the row
     * and a typed character must open the search, both of which need the root's Keys
     * handler to be the focused chain.
     */
    function takeKeyboard() {
        wallpaperSelectorContent.compactSearchExpanded = false;
        wallpaperSelectorContent.forceActiveFocus();
        Qt.callLater(() => wallpaperSelectorContent.forceActiveFocus());
    }
    property bool useDarkMode: Appearance.m3colors.darkmode
    property bool favMode: false
    property bool browserMode: false
    readonly property bool localMode: !favMode && !browserMode
    readonly property bool localSearchActive: localMode && Wallpapers.searchQuery.trim().length > 0
    readonly property bool browserSearchActive: browserMode && WallpaperBrowser.currentSearchTags.length > 0
    readonly property string targetLabel: {
        if (GlobalStates.wallpaperSelectorTarget === "lockscreen") return Translation.tr("Lockscreen");
        if (GlobalStates.wallpaperSelectorTarget === "lightmode") return Translation.tr("Light mode");
        return Translation.tr("Desktop");
    }

    readonly property var sidebarDirectoriesModel: {
        let base = [
            { icon: "home", name: Translation.tr("Home"), path: Directories.home, groupStart: true },
            { icon: "docs", name: Translation.tr("Documents"), path: Directories.documents }, 
            { icon: "wallpaper", name: Translation.tr("Wallpapers"), path: Config.options.wallpaperSelector.useCustomDefaultPath && Config.options.wallpaperSelector.customDefaultPath ? ("file://" + Config.options.wallpaperSelector.customDefaultPath) : (Directories.pictures + "/Wallpapers") }, 
            { icon: "image", name: Translation.tr("Pictures"), path: Directories.pictures }, 
            { icon: "movie", name: Translation.tr("Videos"), path: Directories.videos }, 
            { icon: "public", name: Translation.tr("Browser"), path: "BROWSER_MODE" }, 
            { icon: "favorite", name: Translation.tr("Favourites"), path: "FAVOURITES_MODE", groupEnd: true }
        ];

        const favDirs = Persistent.states.wallpaper.favouriteDirectories;
        if (favDirs && favDirs.length > 0) {
            for (let i = 0; i < favDirs.length; i++) {
                const path = favDirs[i];
                const folderName = path.split('/').pop() || path;
                base.push({
                    icon: "folder_special",
                    name: folderName,
                    path: path,
                    groupStart: i === 0,
                    groupEnd: i === favDirs.length - 1
                });
            }
        }

        const configDirs = Config.options.wallpaperSelector.directories || [];
        for (let i = 0; i < configDirs.length; i++) {
            const entry = configDirs[i];
            base.push({
                icon: entry.icon || "folder",
                name: entry.name || entry.path.split('/').pop() || "Dir",
                path: entry.path,
                groupStart: i === 0,
                groupEnd: i === configDirs.length - 1 && Config.options.policies.weeb !== 1
            });
        }

        if (Config.options.policies.weeb === 1) {
            base.push({
                icon: "favorite",
                name: Translation.tr("Homework"),
                path: `${Directories.pictures}/homework`,
                groupStart: configDirs.length === 0,
                groupEnd: true
            });
        }

        return base;
    }

    property var moreOptionsModelData: null
    property string filterText: wallpaperSelectorContent.compact
        ? compactSearchFilter.text : extraOptions.text
    readonly property bool colorFilterVisible: colorFilterToolbar.visible
    readonly property bool colorCacheUpdating: colorCacheProc.running

    property string activeColorFilter: ""
    property real colorCacheProgress: 0
    property bool isColorFiltering: false
    property bool thumbnailDiagnosticsReady: false
    property bool thumbnailFailureDetected: false
    readonly property bool thumbnailReloadSuggested: localMode
        && thumbnailDiagnosticsReady
        && thumbnailFailureDetected
        && !Wallpapers.thumbnailGenerationRunning
    /**
     * The island makes a missing thumbnail size itself, once per folder and size, when
     * a card first fails to find it: the carousel's card follows the screen's shape,
     * so it can ask for a size the full selector never made. Nothing runs on an open
     * that finds its thumbnails.
     */
    property string autoThumbnailKey: ""
    onThumbnailReloadSuggestedChanged: {
        if (!thumbnailReloadSuggested || !compact)
            return;
        const key = `${Wallpapers.directory}|${thumbnailSizeNameForView()}`;
        if (key === autoThumbnailKey)
            return;
        autoThumbnailKey = key;
        // Later: generating resets the diagnostics this handler is reacting to.
        Qt.callLater(() => wallpaperSelectorContent?.updateThumbnails(false));
    }

    function wallpaperModelKey(modelData) {
        if (!modelData) return "";
        return String(modelData.actualPath || modelData.filePath || modelData.fileUrl || "");
    }

    function normalizedModelPath(modelData) {
        if (!modelData) return "";
        return FileUtils.trimFileProtocol(String(modelData.actualPath || modelData.filePath || ""));
    }

    function currentTargetPath() {
        const background = Config.options?.background;
        if (!background) return "";
        if (GlobalStates.wallpaperSelectorTarget === "lockscreen") {
            return FileUtils.trimFileProtocol(String(background.lockscreenWallpaperPath || ""));
        }
        if (GlobalStates.wallpaperSelectorTarget === "lightmode") {
            return FileUtils.trimFileProtocol(String(background.lightModeWallpaperPath || ""));
        }
        return FileUtils.trimFileProtocol(String(background.wallpaperPath || ""));
    }

    function modelIsApplied(modelData) {
        const candidate = normalizedModelPath(modelData);
        const applied = currentTargetPath();
        return candidate.length > 0 && applied.length > 0 && candidate === applied;
    }

    function toggleMoreOptions(modelData) {
        const selectedKey = wallpaperModelKey(moreOptionsModelData);
        const requestedKey = wallpaperModelKey(modelData);
        moreOptionsModelData = selectedKey !== "" && selectedKey === requestedKey ? null : modelData;
    }

    function toggleColorFilter() {
        if (!colorFilterToolbar.visible) updateColorCache();
        colorFilterToolbar.visible = !colorFilterToolbar.visible;
        if (!colorFilterToolbar.visible) activeColorFilter = "";
    }

    function closeSelector() {
        moreOptionsModelData = null;
        colorFilterToolbar.visible = false;
        activeColorFilter = "";
        wallpaperSelectorContent.requestClose();
    }

    /**
     * Who closes this depends on who owns the surface. The standalone selector is its
     * own window and drops the global flag; inside the island the flag is what put the
     * activity on screen, so dropping it here and letting the host hear about it are the
     * same act - the host clears the flag when its exit animation is done.
     */
    function requestClose() {
        if (wallpaperSelectorContent.compact)
            wallpaperSelectorContent.closeRequested();
        else
            GlobalStates.wallpaperSelectorOpen = false;
    }

    function openDefaultFolder() {
        wallpaperSelectorContent.favMode = false;
        wallpaperSelectorContent.browserMode = false;
        Wallpapers.setDirectory(Wallpapers.defaultFolder);
    }

    function retryBrowserSearch() {
        const tags = Array.from(WallpaperBrowser.currentSearchTags || []);
        if (tags.length === 0) return;
        WallpaperBrowser.clearResponses();
        WallpaperBrowser.makeRequest(tags, 20, 1);
    }

    focus: true

    /** What the browser lists right now: online results, favourites, a colour filter or the folder. */
    readonly property var viewModel: browserMode ? apiImages
        : (favMode ? favouritesModel : (activeColorFilter ? colorFilteredModel : Wallpapers.sortedFolderModel))
    /**
     * The grid in the full selector and the island's plain row, the carousel in the
     * island otherwise. Both answer to the same
     * few calls - count, currentIndex, moveSelection, activateCurrent, resetSelection -
     * so the keys and the toolbars don't need to know which one is on screen.
     */
    readonly property Item view: useCarousel ? carousel : grid

    /**
     * Where a rebuilt model puts the selection: on the wallpaper that was selected,
     * found by path; failing that the applied one; failing that the first.
     */
    function restoreIndex(count, selectedKey) {
        let applied = -1;
        for (let i = 0; i < count; i++) {
            const item = wallpaperSelectorContent.modelAt(i);
            if (!item)
                continue;
            if (selectedKey.length > 0 && wallpaperSelectorContent.wallpaperModelKey(item) === selectedKey)
                return i;
            if (applied < 0 && wallpaperSelectorContent.modelIsApplied(item))
                applied = i;
        }
        return Math.max(0, applied);
    }

    function modelAt(index) {
        const model = wallpaperSelectorContent.viewModel;
        if (!model || index < 0)
            return null;
        return browserMode ? model[index] : model.get(index);
    }

    function activateModelData(modelData) {
        if (!modelData)
            return;
        const filePath = modelData.actualPath
            || (wallpaperSelectorContent.browserMode ? modelData.fileUrl : modelData.filePath)
            || modelData.filePath
            || "";
        if (modelData.fileIsDir)
            Wallpapers.setDirectory(filePath);
        else
            wallpaperSelectorContent.selectWallpaperPath(filePath);
    }

    property var apiImages: {
        let allImages = [];
        for (let i = 0; i < WallpaperBrowser.responses.length; i++) {
            let resp = WallpaperBrowser.responses[i];
            if (resp.images) {
                for (let j = 0; j < resp.images.length; j++) {
                    let img = resp.images[j];
                    allImages.push({
                        filePath: img.preview_url,
                        fileUrl: img.file_url,
                        fileName: "wallhaven-" + img.id || "image",
                        fileIsDir: false,
                        isApi: true,
                        imageData: img
                    });
                }
            }
        }
        return allImages;
    }

    function thumbnailSizeNameForView() {
        // The size the cards will ask for: their pixels, not their points, and the
        // carousel's card rather than the grid's cell when that is what is shown.
        const dpr = (wallpaperSelectorContent.QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const width = useCarousel ? compactCardWidth : grid.cellWidth - totalImageMargin;
        const height = useCarousel ? compactCardHeight : grid.cellHeight - totalImageMargin;
        return Images.thumbnailSizeNameForDimensions(Math.ceil(width * dpr), Math.ceil(height * dpr));
    }

    function updateThumbnails(force = false) {
        scheduleThumbnailDiagnostics();
        Wallpapers.generateThumbnail(thumbnailSizeNameForView(), force);
    }

    function refreshThumbnailDiagnostics() {
        if (!localMode) {
            thumbnailFailureDetected = false;
            return;
        }

        let failed = false;
        const shownView = wallpaperSelectorContent.view;
        for (let i = 0; i < shownView.count; i++) {
            const delegate = shownView.itemAtIndex(i);
            if (delegate && delegate.thumbnailLoadFailed) {
                failed = true;
                break;
            }
        }
        thumbnailFailureDetected = failed;
    }

    function scheduleThumbnailDiagnostics() {
        thumbnailDiagnosticsReady = false;
        thumbnailDiagnosticTimer.restart();
    }

    Component.onCompleted: {
        wallpaperSelectorContent.scheduleThumbnailDiagnostics()
        // The host's handoff rides on the loader's visibility edge; when this
        // component is created already on screen there is no edge to catch, so
        // take the keyboard here too.
        if (wallpaperSelectorContent.compact && wallpaperSelectorContent.active)
            Qt.callLater(() => wallpaperSelectorContent.takeKeyboard())
    }
    onActiveChanged: if (active) Qt.callLater(() => wallpaperSelectorContent.takeKeyboard())
    onFavModeChanged: wallpaperSelectorContent.scheduleThumbnailDiagnostics()
    onBrowserModeChanged: wallpaperSelectorContent.scheduleThumbnailDiagnostics()

    Timer {
        id: thumbnailDiagnosticTimer
        // Give the delegates' asynchronous thumbnail generation time to settle.
        interval: 1200
        repeat: false
        onTriggered: {
            wallpaperSelectorContent.refreshThumbnailDiagnostics();
            wallpaperSelectorContent.thumbnailDiagnosticsReady = true;
        }
    }

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            wallpaperSelectorContent.favMode = false;
            wallpaperSelectorContent.browserMode = false;
            wallpaperSelectorContent.view.resetSelection();
            wallpaperSelectorContent.scheduleThumbnailDiagnostics();
        }
    }

    Connections {
        target: Persistent.states.wallpaper
        function onFavouritesChanged() {
            if (wallpaperSelectorContent.favMode) {
                wallpaperSelectorContent.refreshFavourites();
            }
        }
    }

    ListModel {
        id: favouritesModel
    }

    ListModel {
        id: colorFilteredModel
    }

    Process {
        id: colorCacheProc
        command: [ "bash", Directories.extractColorsScriptPath, Wallpapers.effectiveDirectory ]
        stdout: SplitParser {
            onRead: data => {
                let progress = data.split("/")[0]
                let wallpaperCount = data.split("/")[1]
                wallpaperSelectorContent.colorCacheProgress = progress / wallpaperCount
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Wallpapers.loadColorCache();
            }
        }
    }

    Process {
    id: trashProc
    onExited: (exitCode, exitStatus) => {
        wallpaperSelectorContent.moreOptionsModelData = null;
        if (!wallpaperSelectorContent.favMode && !wallpaperSelectorContent.browserMode) {
            Wallpapers.reloadCurrentDirectory();
        }
    }
}

function moveToTrashFile(modelData) {
    if (!modelData || modelData.fileIsDir) return;
    const path = FileUtils.trimFileProtocol(modelData.filePath);
    const favs = Array.from(Persistent.states.wallpaper.favourites);
    const idx = favs.indexOf(path);
    if (idx !== -1) {
        favs.splice(idx, 1);
        Persistent.states.wallpaper.favourites = favs;
    }
    trashProc.exec(["bash", "-c", `gio trash -- '${StringUtils.shellSingleQuoteEscape(path)}'`]);
    wallpaperSelectorContent.moreOptionsModelData = null;
}
   
    function updateColorCache() {
        console.log("[Wallpapers] Updating color cache for directory", Wallpapers.effectiveDirectory)
        colorCacheProc.running = true
    }

    Timer {
        id: deferredColorFilterTimer
        interval: 10
        running: false
        repeat: false
        onTriggered: wallpaperSelectorContent.executeColorFilter()
    }

    function applyColorFilter() {
        if (!activeColorFilter || activeColorFilter === "") {
            isColorFiltering = false;
            colorFilteredModel.clear();
            grid.loadedCount = 0;
            loadTimer.restart();
            return;
        }

        isColorFiltering = true;
        colorFilteredModel.clear();
        deferredColorFilterTimer.restart();
    }

    function executeColorFilter() {
        const wps = Wallpapers.wallpapers;
        let results = [];
        
        for (let i = 0; i < wps.length; i++) {
            const path = wps[i];
            const colors = Wallpapers.colorCache[path];
            if (colors && colors.length > 0) {
                let bestDist = Infinity;
                for (let j = 0; j < colors.length; j++) {
                    const dist = ColorUtils.calculateDistance(activeColorFilter, colors[j]);
                    if (dist < bestDist) bestDist = dist;
                }
                if (bestDist < 0.2) {
                    results.push({ path, bestDist });
                }
            }
        }
        
        results.sort((a, b) => a.bestDist - b.bestDist);
        
        for (let i = 0; i < results.length; i++) {
            const path = results[i].path;
            const fileName = path.split('/').pop();
            colorFilteredModel.append({
                filePath: "file://" + path,
                actualPath: path,
                fileName: fileName,
                fileIsDir: false
            });
        }
        grid.loadedCount = 0;
        loadTimer.restart();
        isColorFiltering = false;
    }

    onActiveColorFilterChanged: {
        applyColorFilter();
    }

    function refreshFavourites() {
        favouritesModel.clear();
        const favs = Persistent.states.wallpaper.favourites;
        const query = filterText.toLowerCase();
        for (let i = 0; i < favs.length; i++) {
            const path = favs[i];
            const fileName = path.split('/').pop();
            if (query === "" || fileName.toLowerCase().includes(query)) {
                favouritesModel.append({
                    filePath: path,
                    fileName: fileName,
                    fileIsDir: false
                });
            }
        }
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0];
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    function selectWallpaperPath(filePath) {
        if (!filePath || filePath.length === 0) return;

        // Reset the filter before Wallpapers.changed closes this selector.
        // Otherwise the destroyed search field can leave searchQuery active,
        // and the next open may rebuild an apparently empty model.
        wallpaperSelectorContent.clearSearchInput();
        wallpaperSelectorContent.browserMode = false;

        if (GlobalStates.wallpaperSelectorTarget === "lockscreen") {
            Wallpapers.selectLockscreen(filePath, wallpaperSelectorContent.useDarkMode);
        } else if (GlobalStates.wallpaperSelectorTarget === "lightmode") {
            Wallpapers.selectLightmode(filePath, wallpaperSelectorContent.useDarkMode);
        } else {
            Wallpapers.select(filePath, wallpaperSelectorContent.useDarkMode);
        }
    }

    function getWallhavenId(url) {
        if (!url) return null
        const urlStr = url.toString();
        const fileName = urlStr.split('/').pop();
        const fileNameWithoutExt = fileName.split('.')[0];
        const match = fileNameWithoutExt.match(/^wallhaven-([a-zA-Z0-9]{6})$/i);
        return match ? match[1] : null;
    }
    
    function searchForSimilarImages(id) {
        WallpaperBrowser.clearResponses();
        WallpaperBrowser.moreLikeThisPicture(id, 1);
        wallpaperSelectorContent.browserMode = true;
        wallpaperSelectorContent.favMode = false;
        wallpaperSelectorContent.clearSearchInput();
    }

    function toggleFavourite(path) {
        const favs = Array.from(Persistent.states.wallpaper.favourites);
        const index = favs.indexOf(path);
        if (index === -1) {
            favs.push(path);
        } else {
            favs.splice(index, 1);
        }
        Persistent.states.wallpaper.favourites = favs;
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            // The search pill swallows the row first; Escape gives it back.
            if (wallpaperSelectorContent.compact && wallpaperSelectorContent.compactSearchExpanded)
                wallpaperSelectorContent.closeCompactSearch();
            else
                wallpaperSelectorContent.requestClose();
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
            wallpaperSelectorContent.handleFilePasting(event);
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            wallpaperSelectorContent.view.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            wallpaperSelectorContent.view.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            // One row in compact mode, so up and down are the neighbours too.
            wallpaperSelectorContent.view.moveSelection(wallpaperSelectorContent.compact ? -1 : -grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            wallpaperSelectorContent.view.moveSelection(wallpaperSelectorContent.compact ? 1 : grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            wallpaperSelectorContent.view.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (filterText.length > 0) {
                wallpaperSelectorContent.setSearchText(filterText.substring(0, filterText.length - 1));
            }
            wallpaperSelectorContent.focusSearchInput();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash
                || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F)) {
            wallpaperSelectorContent.focusSearchInput();
            event.accepted = true;
        } else {
            if (event.text.length > 0) {
                wallpaperSelectorContent.setSearchText(filterText + event.text);
                wallpaperSelectorContent.focusSearchInput();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    // The island draws its own surface and its own shadow, and the content crossfades
    // with whatever face it replaced; a second shadow under a second rounded rectangle
    // inside it read as two stacked panels.
    StyledRectangularShadow {
        target: wallpaperGridBackground
        visible: !wallpaperSelectorContent.compact
    }
    Rectangle {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: wallpaperSelectorContent.compact ? 0 : Appearance.sizes.elevationMargin
        }
        focus: true
        color: wallpaperSelectorContent.compact ? "transparent" : Appearance.colors.colLayer0
        radius: wallpaperSelectorContent.compact
            ? Appearance.rounding.large
            : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        /** Whether the contents have made their staggered entrance yet. */
        property bool animateIn: false
        /** Open, by whichever route: the global flag, or the island hosting us. */
        readonly property bool opened: wallpaperSelectorContent.compact
            ? wallpaperSelectorContent.active
            : GlobalStates.wallpaperSelectorOpen

        Component.onCompleted: {
            if (wallpaperGridBackground.opened) {
                wallpaperGridBackground.animateIn = false;
                wpContentDelayTimer.restart();
            }
        }

        onOpenedChanged: {
            wallpaperGridBackground.animateIn = false;
            if (wallpaperGridBackground.opened)
                wpContentDelayTimer.restart();
        }

        Timer {
            id: wpContentDelayTimer
            interval: 70
            repeat: false
            running: true
            onTriggered: wallpaperGridBackground.animateIn = true
        }

        // The island's own crossfade carries the whole surface in, so the panel does not
        // scale or fade a second time inside it - only the contents still stagger.
        scale: wallpaperSelectorContent.compact || (wallpaperGridBackground.animateIn && wallpaperGridBackground.opened) ? 1.0 : 0.95
        opacity: wallpaperSelectorContent.compact || (wallpaperGridBackground.animateIn && wallpaperGridBackground.opened) ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        property int calculatedRows: Math.ceil(grid.count / grid.columns)

        implicitWidth: gridColumnLayout.implicitWidth
        implicitHeight: gridColumnLayout.implicitHeight

        RowLayout {
            id: mainLayout
            anchors.fill: parent
            // The island's surface is the padding in compact mode; the full selector
            // insets its own contents from its background instead.
            anchors.margins: wallpaperSelectorContent.compact ? wallpaperSelectorContent.compactPadding : 0
            spacing: wallpaperSelectorContent.compact ? 0 : -4

            // The sidebar: dropped in compact mode. One row of wallpapers has no room
            // for a second navigation beside it, and the path at the top already goes
            // anywhere the sidebar went. Its Favourites and Browser modes move to the
            // actions toolbar, which is on screen in both layouts.
            Rectangle {
                visible: !wallpaperSelectorContent.compact
                Layout.fillHeight: true
                Layout.margins: 4
                implicitWidth: quickDirColumnLayout.implicitWidth
                implicitHeight: quickDirColumnLayout.implicitHeight
                color: Appearance.colors.colLayer1
                radius: wallpaperGridBackground.radius - Layout.margins

                ColumnLayout {
                    id: quickDirColumnLayout
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.margins: 12
                        spacing: 6
                        MaterialSymbol {
                            visible: GlobalStates.wallpaperSelectorTarget === "lockscreen" || GlobalStates.wallpaperSelectorTarget === "lightmode"
                            text: GlobalStates.wallpaperSelectorTarget === "lockscreen" ? "lock" : "light_mode"
                            color: Appearance.colors.colPrimary
                            iconSize: 18
                        }
                        StyledText {
                            font {
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.Medium
                            }
                            text: {
                                if (GlobalStates.wallpaperSelectorTarget === "lockscreen") return Translation.tr("Lockscreen Wallpaper");
                                if (GlobalStates.wallpaperSelectorTarget === "lightmode") return Translation.tr("Light Mode Wallpaper");
                                return Translation.tr("Pick a wallpaper");
                            }
                            color: (GlobalStates.wallpaperSelectorTarget === "lockscreen" || GlobalStates.wallpaperSelectorTarget === "lightmode") ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        }
                    }
                    Item {
                        id: quickDirsContainer
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        implicitWidth: Appearance.sizes.wallpaperSelectorSidebarWidth

                        Flickable {
                            id: sideBarFlickable
                            anchors.fill: parent
                            contentHeight: sideBarRail.implicitHeight
                            clip: true
                            interactive: contentHeight > height
                            
                            ScrollBar.vertical: StyledScrollBar { 
                                visible: sideBarFlickable.interactive
                            }

                            NavigationRailTabArray {
                                id: sideBarRail
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Appearance.sizes.wallpaperSelectorSidebarHorizontalPadding
                                anchors.rightMargin: Appearance.sizes.wallpaperSelectorSidebarHorizontalPadding
                                Layout.topMargin: 0
                                expanded: true
                                spacing: Appearance.sizes.wallpaperSelectorSidebarButtonSpacing
                                currentIndex: {
                                    const model = sideBarRepeater.model;
                                    for (let i = 0; i < model.length; i++) {
                                        let item = model[i];
                                        let isToggled = false;
                                        if (item.path === "FAVOURITES_MODE") isToggled = wallpaperSelectorContent.favMode;
                                        else if (item.path === "BROWSER_MODE") isToggled = wallpaperSelectorContent.browserMode;
                                        else isToggled = !wallpaperSelectorContent.favMode && !wallpaperSelectorContent.browserMode && Wallpapers.directory === Qt.resolvedUrl(item.path);
                                        
                                        if (isToggled) return i;
                                    }
                                    return -1;
                                }

                                Repeater {
                                    id: sideBarRepeater
                                    model: wallpaperSelectorContent.sidebarDirectoriesModel

                                    delegate: NavigationRailButton {
                                        id: quickDirButton
                                        required property var modelData
                                        required property int index
                                        
                                        baseSize: Appearance.sizes.wallpaperSelectorSidebarButtonHeight
                                        baseHighlightHeight: Appearance.sizes.wallpaperSelectorSidebarButtonHeight
                                        iconSize: Appearance.font.pixelSize.larger
                                        textPixelSize: Appearance.font.pixelSize.normal
                                        useDynamicRadius: true
                                        fillExpandedWidth: true
                                        groupFirst: modelData.groupStart === true
                                        groupLast: modelData.groupEnd === true
                                        groupSpacing: modelData.groupStart ? Appearance.sizes.wallpaperSelectorSidebarGroupSpacing : 0
                                        colBackground: Appearance.colors.colLayer2
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        colBackgroundActive: Appearance.colors.colLayer2Active
                                        colBackgroundToggled: Appearance.colors.colPrimary
                                        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
                                        colRipple: Appearance.colors.colLayer2Active
                                        colRippleToggled: Appearance.colors.colPrimaryActive
                                        colText: Appearance.colors.colOnLayer2
                                        colTextToggled: Appearance.colors.colOnPrimary
                                        
                                        buttonIcon: modelData.icon
                                        buttonText: modelData.name
                                        expanded: true
                                        toggled: sideBarRail.currentIndex === index
                                        showToggledHighlight: true
                                        
                                        opacity: 0
                                        transform: Translate { id: navRailTrans; x: -16 }

                                        Connections {
                                            target: wallpaperGridBackground
                                            function onAnimateInChanged() {
                                                if (wallpaperGridBackground.animateIn) {
                                                    quickDirButton.opacity = 0;
                                                    navRailTrans.x = -16;
                                                    navRailTimer.restart();
                                                }
                                            }
                                        }

                                        Component.onCompleted: {
                                            if (wallpaperGridBackground.animateIn) {
                                                navRailTimer.start();
                                            }
                                        }

                                        Timer {
                                            id: navRailTimer
                                            interval: 80 + index * 35
                                            repeat: false
                                            onTriggered: navRailAnim.start()
                                        }

                                        ParallelAnimation {
                                            id: navRailAnim
                                            NumberAnimation {
                                                target: navRailTrans
                                                property: "x"
                                                to: 0
                                                duration: 250
                                                easing.type: Easing.OutCubic
                                            }
                                            NumberAnimation {
                                                target: quickDirButton
                                                property: "opacity"
                                                to: 1
                                                duration: 250
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        
                                        onClicked: {
                                            if (quickDirButton.modelData.path === "FAVOURITES_MODE") {
                                                wallpaperSelectorContent.favMode = true;
                                                wallpaperSelectorContent.browserMode = false;
                                                wallpaperSelectorContent.refreshFavourites();
                                            } else if (quickDirButton.modelData.path === "BROWSER_MODE") {
                                                wallpaperSelectorContent.favMode = false;
                                                wallpaperSelectorContent.browserMode = true;
                                                WallpaperBrowser.clearResponses();
                                            } else {
                                                wallpaperSelectorContent.favMode = false;
                                                wallpaperSelectorContent.browserMode = false;
                                                Wallpapers.setDirectory(quickDirButton.modelData.path)
                                            }
                                            wallpaperSelectorContent.moreOptionsModelData = null
                                        }
                                        enabled: modelData.icon.length > 0
                                    }
                                }
                            }

                            TouchpadScrollHandler {
                                flickable: sideBarFlickable
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: gridColumnLayout
                Layout.fillWidth: true
                Layout.fillHeight: true

                // The address row: where the wallpapers are (path, or the favourites /
                // browser breadcrumb) and - in the island - everything that acts on the
                // row from the keyboard: reload, search (a circle that opens into a
                // pill pushing the path left) and the folder's favourite star. The full
                // selector keeps only its half of this row; its extra toggles stay in
                // the floating toolbars at the bottom.
                RowLayout {
                    Layout.margins: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 8

                    opacity: wallpaperGridBackground.animateIn ? 1.0 : 0.0
                    transform: Translate {
                        y: wallpaperGridBackground.animateIn ? 0 : -15
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on transform {
                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                    }

                    AddressBar {
                        id: addressBar
                        visible: wallpaperSelectorContent.localMode
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        directory: Wallpapers.effectiveDirectory
                        onNavigateToDirectory: path => {
                            Wallpapers.setDirectory(path.length == 0 ? "/" : path);
                        }
                        radius: wallpaperGridBackground.radius - 4
                    }

                    Rectangle {
                        visible: wallpaperSelectorContent.favMode || wallpaperSelectorContent.browserMode
                        Layout.fillWidth: true
                        implicitHeight: addressBar.implicitHeight
                        clip: true
                        color: Appearance.colors.colLayer2
                        radius: wallpaperGridBackground.radius - 4

                        RowLayout {
                            spacing: 12
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14

                            MaterialSymbol {
                                text: wallpaperSelectorContent.browserMode ? "public" : "favorite"
                                color: Appearance.colors.colPrimary
                                iconSize: Appearance.font.pixelSize.larger
                            }
                            ConfigSelectionArray {
                                options: {
                                    let items = [{ displayName: wallpaperSelectorContent.browserMode ? Translation.tr("Wallpaper Browser") : Translation.tr("Favourites"), isRoot: true }];
                                    if (wallpaperSelectorContent.browserMode) {
                                        const tags = WallpaperBrowser.currentSearchTags;
                                        for (let i = 0; i < tags.length; i++) {
                                            items.push({ displayName: tags[i], value: tags[i] });
                                        }
                                    }
                                    return items;
                                }
                                onSelected: newValue => {
                                    if (!newValue) return;
                                    wallpaperSelectorContent.moreOptionsModelData = null
                                    WallpaperBrowser.clearResponses();
                                    WallpaperBrowser.makeRequest([newValue], 20, 1);
                                }
                            }
                        }
                    }

                    RippleButton {
                        id: compactViewToggle
                        visible: wallpaperSelectorContent.compact
                        implicitWidth: addressBar.implicitHeight
                        implicitHeight: addressBar.implicitHeight
                        buttonRadius: implicitWidth / 2
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover

                        // The same key the settings page writes, so the two surfaces can
                        // never disagree about which view the island is showing.
                        onClicked: Config.options.bar.floatingNotch.wallpaperBrowserStyle =
                            wallpaperSelectorContent.useCarousel ? "row" : "carousel"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: wallpaperSelectorContent.useCarousel ? "view_column" : "view_carousel"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: wallpaperSelectorContent.useCarousel
                                ? Translation.tr("Switch to row view")
                                : Translation.tr("Switch to carousel view")
                        }
                    }

                    RippleButton {
                        id: compactReloadBtn
                        visible: wallpaperSelectorContent.compact
                        implicitWidth: addressBar.implicitHeight
                        implicitHeight: addressBar.implicitHeight
                        buttonRadius: implicitWidth / 2
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover

                        onClicked: wallpaperSelectorContent.updateThumbnails(true)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: wallpaperSelectorContent.thumbnailReloadSuggested
                                ? Translation.tr("Some thumbnails failed to load. Click Reload thumbnails to regenerate them.")
                                : Translation.tr("Reload thumbnails (for high resolution displays)")
                            extraVisibleCondition: !wallpaperSelectorContent.thumbnailReloadSuggested
                            alternativeVisibleCondition: wallpaperSelectorContent.thumbnailReloadSuggested
                            requireOverlay: false
                        }
                    }

                    Item {
                        id: compactSearchSlot
                        visible: wallpaperSelectorContent.compact
                        // The right edge never moves: expanding grows leftwards and
                        // the path row shrinks to pay for it.
                        implicitWidth: wallpaperSelectorContent.compactSearchExpanded
                            ? Appearance.sizes.wallpaperSelectorSearchWidth
                            : addressBar.implicitHeight
                        implicitHeight: addressBar.implicitHeight
                        clip: true

                        Behavior on implicitWidth {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }

                        RippleButton {
                            id: compactSearchCircle
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.implicitHeight
                            height: width
                            buttonRadius: width / 2
                            visible: !wallpaperSelectorContent.compactSearchExpanded
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover

                            onClicked: wallpaperSelectorContent.openCompactSearch()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "search"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledToolTip {
                                text: Translation.tr("Search wallpapers")
                            }
                        }

                        // The pill's way out: it sits where the circle was, so the
                        // right edge of the search never moves across the transition.
                        RippleButton {
                            id: compactSearchClose
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.implicitHeight
                            height: width
                            buttonRadius: width / 2
                            visible: wallpaperSelectorContent.compactSearchExpanded
                            colBackground: Appearance.colors.colLayer2Hover
                            colBackgroundHover: Appearance.colors.colLayer2Active

                            onClicked: {
                                // Closing with the query still standing would leave
                                // the row filtered with nothing on screen to say so.
                                compactSearchFilter.text = "";
                                wallpaperSelectorContent.closeCompactSearch();
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledToolTip {
                                text: Translation.tr("Close search")
                            }
                        }

                        ToolbarTextField {
                            id: compactSearchFilter
                            anchors.right: compactSearchClose.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - compactSearchClose.width - 4
                            height: parent.implicitHeight
                            visible: opacity > 0
                            enabled: wallpaperSelectorContent.compactSearchExpanded
                            opacity: wallpaperSelectorContent.compactSearchExpanded ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }

                            colBackground: Appearance.colors.colLayer2
                            placeholderText: {
                                if (wallpaperSelectorContent.browserMode) return Translation.tr("Search API (e.g. nature, city)");
                                return focus ? Translation.tr("Search wallpapers") : Translation.tr("Hit \"/\" to search");
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            clip: true

                            onTextChanged: {
                                if (!wallpaperSelectorContent.browserMode) {
                                    Wallpapers.searchQuery = text;
                                    if (wallpaperSelectorContent.favMode) {
                                        wallpaperSelectorContent.refreshFavourites();
                                    }
                                }
                            }

                            onAccepted: {
                                if (wallpaperSelectorContent.browserMode && text.trim().length > 0) {
                                    const newTags = text.trim().split(/\s+/);
                                    wallpaperSelectorContent.moreOptionsModelData = null;
                                    WallpaperBrowser.clearResponses();
                                    WallpaperBrowser.makeRequest(newTags, 20, 1);
                                    wallpaperSelectorContent.view.currentIndex = 0;
                                } else if (!wallpaperSelectorContent.browserMode && wallpaperSelectorContent.view.count > 0) {
                                    // Enter applies the selection in whichever view is on
                                    // screen - the plain row or the carousel.
                                    wallpaperSelectorContent.view.activateCurrent();
                                }
                            }

                            Keys.onPressed: event => {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                    wallpaperSelectorContent.handleFilePasting(event);
                                    return;
                                }
                                if (event.key === Qt.Key_Escape) {
                                    wallpaperSelectorContent.closeCompactSearch();
                                    event.accepted = true;
                                    return;
                                }
                                if (event.key === Qt.Key_Down) {
                                    wallpaperSelectorContent.view.moveSelection(1);
                                    event.accepted = true;
                                    return;
                                }
                                if (event.key === Qt.Key_Up) {
                                    wallpaperSelectorContent.view.moveSelection(-1);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false;
                            }
                        }
                    }

                    RippleButton {
                        id: favFolderBtn
                        visible: wallpaperSelectorContent.localMode
                        implicitWidth: addressBar.implicitHeight
                        implicitHeight: addressBar.implicitHeight
                        buttonRadius: implicitWidth / 2
                        colBackground: isCurrentFolderFavorited ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        colBackgroundHover: isCurrentFolderFavorited ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover

                        readonly property bool isCurrentFolderFavorited: {
                            const currentDir = FileUtils.trimFileProtocol(Wallpapers.effectiveDirectory);
                            const favDirs = Persistent.states.wallpaper.favouriteDirectories;
                            return favDirs.indexOf(currentDir) !== -1;
                        }

                        onClicked: {
                            const currentDir = FileUtils.trimFileProtocol(Wallpapers.effectiveDirectory);
                            let favDirs = [];
                            const currentFavs = Persistent.states.wallpaper.favouriteDirectories;
                            for (let i = 0; i < currentFavs.length; i++) {
                                favDirs.push(currentFavs[i]);
                            }
                            const idx = favDirs.indexOf(currentDir);
                            if (idx === -1) {
                                favDirs.push(currentDir);
                            } else {
                                favDirs.splice(idx, 1);
                            }
                            Persistent.states.wallpaper.favouriteDirectories = favDirs;
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "star"
                            fill: favFolderBtn.isCurrentFolderFavorited ? 1.0 : 0.0
                            iconSize: Appearance.font.pixelSize.larger
                            color: favFolderBtn.isCurrentFolderFavorited ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: favFolderBtn.isCurrentFolderFavorited ? Translation.tr("Remove folder from Favourites") : Translation.tr("Add folder to Favourites")
                        }
                    }
                }

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // The full selector draws its own opaque background, so its fades
                    // can repaint the surface colour at the edges. The row inside the
                    // island must not: over the island's translucent body, a band
                    // painted in the surface's own colour picks up a second alpha and
                    // reads as the wrong background. There the ends of the row are
                    // faded by the grid's own OpacityMask instead (see below), and the
                    // ScrollEdgeFade beneath is kept only for its measurements.
                    // Top Scroll Fade Gradient Overlay
                    Rectangle {
                        z: 10
                        visible: !wallpaperSelectorContent.compact
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 42
                        opacity: (grid.atYBeginning || !grid.visible) ? 0.0 : 1.0
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Appearance.colors.colLayer0 }
                            GradientStop { position: 0.45; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15) }
                            GradientStop { position: 0.75; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.60) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // Bottom Scroll Fade Gradient Overlay
                    Rectangle {
                        z: 10
                        visible: !wallpaperSelectorContent.compact
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 48
                        bottomRightRadius: wallpaperGridBackground.radius - 4
                        opacity: (grid.atYEnd || !grid.visible) ? 0.0 : 1.0
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.25; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.60) }
                            GradientStop { position: 0.55; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15) }
                            GradientStop { position: 1.0; color: Appearance.colors.colLayer0 }
                        }
                    }

                    // The plain row fades its own pixels through the grid's OpacityMask
                    // (see below); this stays only for the measurements. The carousel's
                    // edges get the same pixel fade on the PathView's own mask.
                    ScrollEdgeFade {
                        id: rowEdgeFade
                        target: grid
                        vertical: false
                        color: "transparent"
                        fadeSize: 48
                    }

                    StyledIndeterminateProgressBar {
                        id: indeterminateProgressBar
                        visible: (Wallpapers.thumbnailGenerationRunning && value == 0) || (wallpaperSelectorContent.browserMode && WallpaperBrowser.runningRequests > 0) || (wallpaperSelectorContent.localMode && Wallpapers.directoryLoading) || (wallpaperSelectorContent.colorCacheProgress === 0 && colorCacheProc.running) || wallpaperSelectorContent.isColorFiltering
                        anchors {
                            bottom: parent.top
                            left: parent.left
                            right: parent.right
                            leftMargin: 4
                            rightMargin: 4
                        }
                    }

                    StyledProgressBar {
                        visible: wallpaperSelectorContent.colorCacheProgress > 0 && wallpaperSelectorContent.colorCacheProgress < 1
                        value: wallpaperSelectorContent.colorCacheProgress
                        anchors.fill: indeterminateProgressBar
                    }

                    StyledProgressBar {
                        visible: Wallpapers.thumbnailGenerationRunning && value > 0
                        value: Wallpapers.thumbnailGenerationProgress
                        anchors.fill: indeterminateProgressBar
                    }

                    Item {
                        id: emptyStateRegion
                        anchors.fill: parent
                        visible: wallpaperSelectorContent.view.count === 0 && !(
                            (wallpaperSelectorContent.browserMode && WallpaperBrowser.runningRequests > 0)
                            || (wallpaperSelectorContent.localMode && (Wallpapers.directoryLoading || colorCacheProc.running || wallpaperSelectorContent.isColorFiltering))
                        )

                        readonly property bool hasError: wallpaperSelectorContent.localMode && Wallpapers.directoryError.length > 0
                        readonly property bool isSearchEmpty: wallpaperSelectorContent.localSearchActive || wallpaperSelectorContent.activeColorFilter.length > 0
                        readonly property bool isBrowserError: wallpaperSelectorContent.browserMode && WallpaperBrowser.errorMessage.length > 0
                        /** The action button's height, which the placeholder budgets around. */
                        readonly property real emptyActionHeight: wallpaperSelectorContent.compact
                            ? 30 : Appearance.sizes.barHeight
                        readonly property bool showAction: wallpaperSelectorContent.browserMode
                            || wallpaperSelectorContent.favMode
                            || wallpaperSelectorContent.localMode

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - Appearance.font.pixelSize.huge, Appearance.animationCurves.mediaControlsWidth)
                            spacing: wallpaperSelectorContent.compact ? 6 : Appearance.sizes.hyprlandGapsOut

                            Item {
                                Layout.fillWidth: true
                                // A single row leaves far less room than a page of
                                // wallpapers: the placeholder takes what is left once
                                // the action button has its share, and scales itself to
                                // fit rather than overflowing the row.
                                Layout.preferredHeight: wallpaperSelectorContent.compact
                                    ? Math.max(40, emptyStateRegion.height - (emptyStateRegion.showAction ? emptyStateRegion.emptyActionHeight + 6 : 0) - 8)
                                    : Appearance.sizes.barHeight * 3

                                PagePlaceholder {
                                    anchors.fill: parent
                                    fitToParent: wallpaperSelectorContent.compact
                                    titlePixelSize: wallpaperSelectorContent.compact
                                        ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                                    descriptionPixelSize: wallpaperSelectorContent.compact
                                        ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                                    shown: emptyStateRegion.visible
                                    icon: emptyStateRegion.hasError || emptyStateRegion.isBrowserError ? "error"
                                        : wallpaperSelectorContent.browserMode ? "public"
                                        : wallpaperSelectorContent.favMode ? "favorite_border"
                                        : emptyStateRegion.isSearchEmpty ? "search_off"
                                        : "wallpaper"
                                    title: emptyStateRegion.hasError ? Translation.tr("Folder unavailable")
                                        : emptyStateRegion.isBrowserError ? Translation.tr("Wallpaper search failed")
                                        : wallpaperSelectorContent.browserMode ? Translation.tr("No wallpapers found")
                                        : wallpaperSelectorContent.favMode ? Translation.tr("No favourites yet")
                                        : wallpaperSelectorContent.activeColorFilter.length > 0 ? Translation.tr("No wallpapers match this color")
                                        : wallpaperSelectorContent.localSearchActive ? Translation.tr("No wallpapers match this search")
                                        : Translation.tr("This folder has no wallpapers")
                                    description: emptyStateRegion.hasError ? Wallpapers.directoryError
                                        : emptyStateRegion.isBrowserError ? WallpaperBrowser.errorMessage
                                        : wallpaperSelectorContent.browserMode ? Translation.tr("Try different tags or search again.")
                                        : wallpaperSelectorContent.favMode ? Translation.tr("Click the heart icon on a wallpaper to add it here.")
                                        : wallpaperSelectorContent.activeColorFilter.length > 0 ? Translation.tr("Choose another color or clear the color filter.")
                                        : wallpaperSelectorContent.localSearchActive ? Translation.tr("Clear the search to see every wallpaper in this folder.")
                                        : Translation.tr("Choose another folder or add wallpapers to this directory.")
                                    shape: MaterialShape.Shape.Cookie7Sided
                                }
                            }

                            RippleButton {
                                visible: emptyStateRegion.showAction
                                Layout.alignment: Qt.AlignHCenter
                                implicitHeight: emptyStateRegion.emptyActionHeight
                                implicitWidth: emptyActionContent.implicitWidth
                                    + (wallpaperSelectorContent.compact ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.huge)
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                colBackgroundActive: Appearance.colors.colPrimaryActive
                                colRipple: Appearance.colors.colPrimaryActive

                                contentItem: RowLayout {
                                    id: emptyActionContent
                                    anchors.centerIn: parent
                                    spacing: Appearance.font.pixelSize.smaller

                                    MaterialSymbol {
                                        iconSize: wallpaperSelectorContent.compact
                                            ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large
                                        text: wallpaperSelectorContent.browserMode ? (wallpaperSelectorContent.browserSearchActive ? "refresh" : "search")
                                            : wallpaperSelectorContent.favMode ? "wallpaper"
                                            : wallpaperSelectorContent.localSearchActive || wallpaperSelectorContent.activeColorFilter.length > 0 ? "close"
                                            : "folder_open"
                                        color: Appearance.colors.colOnPrimary
                                    }

                                    StyledText {
                                        text: wallpaperSelectorContent.browserMode
                                            ? (wallpaperSelectorContent.browserSearchActive ? Translation.tr("Search again") : Translation.tr("Search wallpapers"))
                                            : wallpaperSelectorContent.favMode ? Translation.tr("Open wallpapers")
                                            : wallpaperSelectorContent.localSearchActive ? Translation.tr("Clear search")
                                            : wallpaperSelectorContent.activeColorFilter.length > 0 ? Translation.tr("Clear color filter")
                                            : Translation.tr("Open file picker")
                                        color: Appearance.colors.colOnPrimary
                                        font.weight: Font.Medium
                                    }
                                }

                                onClicked: {
                                    if (wallpaperSelectorContent.browserMode) {
                                        if (wallpaperSelectorContent.browserSearchActive) {
                                            wallpaperSelectorContent.retryBrowserSearch();
                                        } else {
                                            wallpaperSelectorContent.focusSearchInput();
                                        }
                                    } else if (wallpaperSelectorContent.favMode) {
                                        wallpaperSelectorContent.openDefaultFolder();
                                    } else if (wallpaperSelectorContent.localSearchActive) {
                                        wallpaperSelectorContent.clearSearchInput();
                                    } else if (wallpaperSelectorContent.activeColorFilter.length > 0) {
                                        wallpaperSelectorContent.activeColorFilter = "";
                                    } else {
                                        Wallpapers.openFallbackPicker(wallpaperSelectorContent.useDarkMode, GlobalStates.wallpaperSelectorTarget === "lockscreen");
                                        wallpaperSelectorContent.closeSelector();
                                    }
                                }
                            }
                        }
                    }

                    GridView {
                        id: grid
                        visible: count > 0

                        readonly property int columns: wallpaperSelectorContent.columns
                        readonly property int rows: Math.max(1, Math.ceil(count / columns))
                        property int currentIndex: -1
                        property bool keyboardNavigationActive: false

                        anchors.fill: parent

                        /**
                         * One row, scrolling sideways.
                         *
                         * A GridView laid out top-to-bottom fills a column before moving
                         * to the next one, so a view exactly one cell tall *is* a single
                         * horizontal row - the same delegates, the same model, the same
                         * count of four across. Nothing else about the grid changes.
                         */
                        flow: wallpaperSelectorContent.compact ? GridView.FlowTopToBottom : GridView.FlowLeftToRight
                        // Fixed in the row: the island animates this view's width, and a
                        // cell that grew with it would slide the selection off its place.
                        cellWidth: wallpaperSelectorContent.compact
                            ? wallpaperSelectorContent.compactCellWidth
                            : width / wallpaperSelectorContent.columns
                        cellHeight: wallpaperSelectorContent.compact
                            ? height
                            : cellWidth / wallpaperSelectorContent.previewCellAspectRatio
                        interactive: true
                        clip: true
                        keyNavigationWraps: true
                        boundsBehavior: Flickable.StopAtBounds
                        // The toolbars float over the grid in the full selector, so it
                        // scrolls past them; in compact they have a row of their own.
                        bottomMargin: wallpaperSelectorContent.compact ? 0 : extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {
                            visible: !wallpaperSelectorContent.compact
                        }

                        // Touchpad and mouse scroll physics adjustments
                        property real scrollTargetY: 0
                        property real scrollTargetX: 0
                        property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
                        property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
                        property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

                        maximumFlickVelocity: 3500

                        MouseArea {
                            z: 99
                            visible: !wallpaperSelectorContent.compact
                                && Config?.options.interactions.scrolling.fasterTouchpadScroll
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: function(wheelEvent) {
                                const delta = wheelEvent.angleDelta.y / grid.mouseScrollDeltaThreshold;
                                var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= grid.mouseScrollDeltaThreshold ? grid.mouseScrollFactor : grid.touchpadScrollFactor;

                                const maxY = Math.max(0, grid.contentHeight - grid.height);
                                const base = scrollAnim.running ? grid.scrollTargetY : grid.contentY;
                                var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));

                                grid.scrollTargetY = targetY;
                                grid.contentY = targetY;
                                wheelEvent.accepted = true;
                            }
                        }

                        /**
                         * The wheel, for the single row.
                         *
                         * A Flickable that only flicks sideways ignores a vertical wheel,
                         * so a mouse did nothing at all over the row; and the faster-scroll
                         * MouseArea above is off unless the user turned that setting on.
                         * This is always on in compact, and takes whichever axis the
                         * device reports - a mouse sends y, a touchpad's sideways swipe
                         * sends x - so both reach the row.
                         */
                        WheelHandler {
                            enabled: wallpaperSelectorContent.compact
                            target: null
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const raw = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                                if (raw === 0)
                                    return;
                                const delta = raw / grid.mouseScrollDeltaThreshold;
                                const scrollFactor = Math.abs(raw) >= grid.mouseScrollDeltaThreshold
                                    ? grid.mouseScrollFactor : grid.touchpadScrollFactor;

                                const maxX = Math.max(0, grid.contentWidth - grid.width);
                                const base = hScrollAnim.running ? grid.scrollTargetX : grid.contentX;
                                const targetX = Math.max(0, Math.min(base - delta * scrollFactor, maxX));

                                grid.scrollTargetX = targetX;
                                grid.contentX = targetX;
                                // Claimed, so a device that does send an x delta is not
                                // also flicked by the Flickable underneath.
                                event.accepted = true;
                            }
                        }

                        Behavior on contentY {
                            NumberAnimation {
                                id: scrollAnim
                                alwaysRunToEnd: true
                                duration: Appearance.animation.scroll.duration
                                easing.type: Appearance.animation.scroll.type
                                easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                            }
                        }

                        Behavior on contentX {
                            enabled: wallpaperSelectorContent.compact && !grid.jumping
                            NumberAnimation {
                                id: hScrollAnim
                                alwaysRunToEnd: true
                                duration: Appearance.animation.scroll.duration
                                easing.type: Appearance.animation.scroll.type
                                easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                            }
                        }

                        onContentYChanged: {
                            if (!scrollAnim.running) {
                                grid.scrollTargetY = grid.contentY;
                            }
                        }

                        onContentXChanged: {
                            if (!hScrollAnim.running) {
                                grid.scrollTargetX = grid.contentX;
                            }
                        }

                        Component.onCompleted: {
                            Qt.callLater(() => loadTimer.start())
                        }

                        function moveSelection(delta) {
                            if (grid.count <= 0) {
                                currentIndex = -1;
                                return;
                            }
                            keyboardNavigationActive = true;
                            currentIndex = Math.max(0, Math.min(grid.count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }

                        function resetSelection() {
                            currentIndex = -1;
                            keyboardNavigationActive = false;
                            grid.selectedKey = "";
                            grid.scheduleRestore();
                        }

                        /**
                         * The island's row opens on the applied wallpaper and keeps its
                         * selection through the folder model's re-sorts (see the carousel's
                         * restoreSelection). The full selector opens at the top, as before.
                         */
                        property string selectedKey: ""
                        property bool restorePending: false
                        property bool jumping: false

                        function scheduleRestore() {
                            if (!wallpaperSelectorContent.compact)
                                return;
                            grid.restorePending = true;
                            Qt.callLater(grid.restoreSelection);
                        }

                        function restoreSelection() {
                            if (!grid.restorePending)
                                return;
                            grid.restorePending = false;
                            if (grid.count <= 0)
                                return;
                            const target = wallpaperSelectorContent.restoreIndex(grid.count, grid.selectedKey);
                            grid.currentIndex = target;
                            grid.selectedKey = wallpaperSelectorContent.wallpaperModelKey(wallpaperSelectorContent.modelAt(target));
                            // Centred on the row's full width by hand: this runs while the
                            // island is still growing, and positionViewAtIndex would centre
                            // it in the half-open view and leave it at the left edge.
                            const shown = wallpaperSelectorContent.columns * grid.cellWidth;
                            const maxX = Math.max(0, grid.count * grid.cellWidth - shown);
                            grid.jumping = true;
                            grid.contentX = Math.max(0, Math.min(maxX, (target + 0.5) * grid.cellWidth - shown / 2));
                            grid.jumping = false;
                        }

                        onCurrentIndexChanged: {
                            if (!wallpaperSelectorContent.compact || grid.restorePending || grid.currentIndex < 0)
                                return;
                            const key = wallpaperSelectorContent.wallpaperModelKey(wallpaperSelectorContent.modelAt(grid.currentIndex));
                            if (key.length > 0)
                                grid.selectedKey = key;
                        }

                        function activateCurrent() {
                            if (grid.count <= 0 || currentIndex < 0) return;

                            const modelData = wallpaperSelectorContent.browserMode
                                ? grid.model[currentIndex]
                                : grid.model.get(currentIndex);
                            if (!modelData) return;

                            const filePath = modelData.actualPath
                                || (wallpaperSelectorContent.browserMode ? modelData.fileUrl : modelData.filePath)
                                || modelData.filePath
                                || "";
                            const isDir = Boolean(modelData.fileIsDir);
                            if (isDir) {
                                Wallpapers.setDirectory(filePath);
                            } else {
                                wallpaperSelectorContent.selectWallpaperPath(filePath);
                            }
                        }

                        property int loadedCount: 0

                        Timer {
                            id: loadTimer
                            interval: 8
                            repeat: true
                            running: false
                            onTriggered: {
                                grid.loadedCount = Math.min(grid.count, grid.loadedCount + 4);
                                if (grid.loadedCount >= grid.count) loadTimer.stop()
                            }
                        }

                        // The carousel draws the island's row when it is on; the grid holds nothing then.
                        model: wallpaperSelectorContent.useCarousel ? null : wallpaperSelectorContent.viewModel
                        onModelChanged: {
                            currentIndex = -1
                            keyboardNavigationActive = false
                            loadedCount = 0
                            loadTimer.restart()
                            grid.scheduleRestore()
                            wallpaperSelectorContent.scheduleThumbnailDiagnostics()
                        }
                        onCountChanged: {
                            if (count <= 0) {
                                currentIndex = -1;
                                keyboardNavigationActive = false;
                            }
                            grid.scheduleRestore();
                            if (count > 0 && loadedCount < count) {
                                loadTimer.restart()
                            }
                            wallpaperSelectorContent.scheduleThumbnailDiagnostics()
                        }
                        delegate: WallpaperDirectoryItem {
                            id: wpItemDelegate
                            required property var modelData
                            required property int index
                            fileModelData: modelData
                            width: grid.cellWidth
                            height: grid.cellHeight

                            readonly property int cols: grid.columns
                            // One row in compact mode, so the stagger runs along it
                            // rather than down a grid.
                            readonly property int itemRow: wallpaperSelectorContent.compact
                                ? 0 : Math.floor(index / Math.max(1, cols))
                            readonly property int itemCol: wallpaperSelectorContent.compact
                                ? index : index % Math.max(1, cols)
                            readonly property int cascadeDelay: Math.min(250, (itemRow * 30) + (itemCol * 20))
                            readonly property bool appliedState: wallpaperSelectorContent.modelIsApplied(fileModelData)
                            readonly property bool isKeyboardSelected: grid.keyboardNavigationActive && index === grid.currentIndex
                            readonly property bool isMoreOptionsSelected: wallpaperSelectorContent.moreOptionsModelData !== null
                                && wallpaperSelectorContent.wallpaperModelKey(fileModelData) === wallpaperSelectorContent.wallpaperModelKey(wallpaperSelectorContent.moreOptionsModelData)

                            colBackground: appliedState ? Appearance.colors.colPrimaryContainer
                                : (isMoreOptionsSelected ? Appearance.colors.colSecondaryContainer
                                : // The keyboard marker has to read over the island's
                                // translucent body, where colLayer2Hover is barely a
                                // change at all: the tertiary container is saturated
                                // like the applied wallpaper's primary one, but never
                                // the same colour as it.
                                (isKeyboardSelected ? Appearance.colors.colTertiaryContainer
                                : containsMouse ? Appearance.colors.colLayer2Hover
                                : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)))
                            colText: appliedState ? Appearance.colors.colOnPrimaryContainer
                                : isKeyboardSelected ? Appearance.colors.colOnTertiaryContainer
                                : (isMoreOptionsSelected || containsMouse) ? Appearance.colors.colOnLayer2
                                : Appearance.colors.colOnLayer0
                            isApplied: appliedState
                            appliedLabel: wallpaperSelectorContent.targetLabel
                            shouldLoad: index < grid.loadedCount

                            onThumbnailLoadStateChanged: Qt.callLater(() => wallpaperSelectorContent?.refreshThumbnailDiagnostics())

                            scale: 0.72
                            opacity: 0
                            transform: Translate {
                                id: wpTrans
                                x: (wpItemDelegate.itemCol % 2 === 0 ? -24 : -12)
                            }

                            Timer {
                                id: wpEntryTimer
                                interval: wpItemDelegate.cascadeDelay
                                repeat: false
                                onTriggered: wpEntryAnim.start()
                            }

                            Connections {
                                target: wallpaperGridBackground
                                function onAnimateInChanged() {
                                    if (wallpaperGridBackground.animateIn) {
                                        wpItemDelegate.opacity = 0;
                                        wpItemDelegate.scale = 0.72;
                                        wpTrans.x = (wpItemDelegate.itemCol % 2 === 0 ? -24 : -12);
                                        wpEntryTimer.restart();
                                    }
                                }
                            }

                            Component.onCompleted: {
                                if (wallpaperGridBackground.animateIn) {
                                    wpEntryTimer.start();
                                }
                            }

                            ParallelAnimation {
                                id: wpEntryAnim
                                NumberAnimation {
                                    target: wpTrans
                                    property: "x"
                                    to: 0
                                    duration: 320
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: wpItemDelegate
                                    property: "scale"
                                    to: 1.0
                                    duration: 350
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.15
                                }
                                NumberAnimation {
                                    target: wpItemDelegate
                                    property: "opacity"
                                    to: 1.0
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                            }

                            onEntered: grid.keyboardNavigationActive = false

                            onActivated: {
                                if (fileModelData.fileIsDir) {
                                    Wallpapers.setDirectory(fileModelData.filePath);
                                } else {
                                    wallpaperSelectorContent.selectWallpaperPath(fileModelData.actualPath || fileModelData.filePath);
                                }
                            }

                            onSearchSimilarRequested: (path, id) => {
                                wallpaperSelectorContent.searchForSimilarImages(id)
                            }
                            onMoreOptionsRequested: (modelData) => {
                                wallpaperSelectorContent.toggleMoreOptions(modelData)
                            }
                        }

                        // Empty under the carousel, so no mask to allocate there.
                        layer.enabled: !wallpaperSelectorContent.useCarousel
                        // Fade the row's own pixels, never repaint a translucent
                        // surface colour over them: over the island's see-through body
                        // a painted band doubles the transparency and reads as the wrong
                        // background. One mask handles the rounded corners and the
                        // scroll edges, like TaskList in the ToDoWidget.
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                id: gridViewportMask
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                                readonly property real fadeFraction: Math.min(0.5,
                                    rowEdgeFade.fadeSize / Math.max(1, width))
                                property real leftAlpha: wallpaperSelectorContent.compact
                                    && rowEdgeFade.overflowing
                                    && rowEdgeFade.startGap > rowEdgeFade.edgeTolerance ? 0 : 1
                                property real rightAlpha: wallpaperSelectorContent.compact
                                    && rowEdgeFade.overflowing
                                    && rowEdgeFade.endGap > rowEdgeFade.edgeTolerance ? 0 : 1
                                Behavior on leftAlpha {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(gridViewportMask)
                                }
                                Behavior on rightAlpha {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(gridViewportMask)
                                }
                                // Off compact the stops are all opaque white: the mask
                                // is the plain rounded rectangle it always was.
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, gridViewportMask.leftAlpha) }
                                    GradientStop { position: gridViewportMask.fadeFraction; color: "white" }
                                    GradientStop { position: 1.0 - gridViewportMask.fadeFraction; color: "white" }
                                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, gridViewportMask.rightAlpha) }
                                }
                            }
                        }
                    }

                    /**
                     * The island's row: a cover-flow carousel that loops.
                     *
                     * The selection is whatever sits in the centre - PathView keeps its
                     * currentIndex on the highlight, so the keys, the wheel, a drag and a
                     * click on a neighbour all move the same thing, and Enter always applies
                     * the wallpaper you are looking at. Cards shrink, fade and sink behind
                     * their neighbours toward the ends, and the row wraps round.
                     *
                     * Only built for the island's carousel: elsewhere it gets no model, so it
                     * holds no delegates there.
                     */
                    PathView {
                        id: carousel
                        anchors.fill: parent
                        visible: wallpaperSelectorContent.useCarousel && count > 0
                        model: wallpaperSelectorContent.useCarousel ? wallpaperSelectorContent.viewModel : null

                        readonly property real cardWidth: wallpaperSelectorContent.compactCardWidth
                        readonly property real cardHeight: wallpaperSelectorContent.compactCardHeight
                        readonly property real centerX: width / 2
                        readonly property real centerY: wallpaperSelectorContent.compactCardInset + cardHeight / 2
                        // The step between cards: a card's width, or a third of the row when a
                        // tall screen's narrow card would leave the row's ends empty.
                        readonly property real pitch: Math.max(cardWidth, width / 3)
                        // Card centres, measured out from the middle: the first neighbour tucks
                        // under the centred card, the second under the first, and the ends sit
                        // past the row's edge so a card slides in rather than popping up.
                        readonly property real near: 0.7 * pitch
                        readonly property real far: 1.2 * pitch
                        readonly property real edge: 1.6 * pitch
                        /** The wallpaper the selection follows through a model rebuild. */
                        property string selectedKey: ""
                        property bool restorePending: false
                        property real wheelAccumulator: 0

                        pathItemCount: 7
                        // Two more on each side stay built, so a fast scroll finds them drawn.
                        cacheItemCount: 4
                        preferredHighlightBegin: 0.5
                        preferredHighlightEnd: 0.5
                        highlightRangeMode: PathView.StrictlyEnforceRange
                        snapMode: PathView.SnapToItem
                        highlightMoveDuration: 260
                        interactive: count > 1

                        /*
                         * Seven slots, one every 1/7 of the path; the percents pin each slot to
                         * its point, since the points themselves are not evenly spaced. Side
                         * cards shrink, darken and turn to face the middle.
                         */
                        path: Path {
                            startX: carousel.centerX - carousel.edge
                            startY: carousel.centerY
                            PathAttribute { name: "itemScale"; value: 0.52 }
                            PathAttribute { name: "itemZ"; value: 0 }
                            PathAttribute { name: "itemOpacity"; value: 0 }
                            PathAttribute { name: "itemDim"; value: 0.8 }
                            PathAttribute { name: "itemAngle"; value: 42 }
                            PathLine { x: carousel.centerX - carousel.far; y: carousel.centerY }
                            PathPercent { value: 1.5 / 7 }
                            PathAttribute { name: "itemScale"; value: 0.66 }
                            PathAttribute { name: "itemZ"; value: 1 }
                            PathAttribute { name: "itemOpacity"; value: 1 }
                            PathAttribute { name: "itemDim"; value: 0.62 }
                            PathAttribute { name: "itemAngle"; value: 36 }
                            PathLine { x: carousel.centerX - carousel.near; y: carousel.centerY }
                            PathPercent { value: 2.5 / 7 }
                            PathAttribute { name: "itemScale"; value: 0.82 }
                            PathAttribute { name: "itemZ"; value: 2 }
                            PathAttribute { name: "itemOpacity"; value: 1 }
                            PathAttribute { name: "itemDim"; value: 0.42 }
                            PathAttribute { name: "itemAngle"; value: 28 }
                            PathLine { x: carousel.centerX; y: carousel.centerY }
                            PathPercent { value: 0.5 }
                            PathAttribute { name: "itemScale"; value: 1 }
                            PathAttribute { name: "itemZ"; value: 3 }
                            PathAttribute { name: "itemOpacity"; value: 1 }
                            PathAttribute { name: "itemDim"; value: 0 }
                            PathAttribute { name: "itemAngle"; value: 0 }
                            PathLine { x: carousel.centerX + carousel.near; y: carousel.centerY }
                            PathPercent { value: 4.5 / 7 }
                            PathAttribute { name: "itemScale"; value: 0.82 }
                            PathAttribute { name: "itemZ"; value: 2 }
                            PathAttribute { name: "itemOpacity"; value: 1 }
                            PathAttribute { name: "itemDim"; value: 0.42 }
                            PathAttribute { name: "itemAngle"; value: -28 }
                            PathLine { x: carousel.centerX + carousel.far; y: carousel.centerY }
                            PathPercent { value: 5.5 / 7 }
                            PathAttribute { name: "itemScale"; value: 0.66 }
                            PathAttribute { name: "itemZ"; value: 1 }
                            PathAttribute { name: "itemOpacity"; value: 1 }
                            PathAttribute { name: "itemDim"; value: 0.62 }
                            PathAttribute { name: "itemAngle"; value: -36 }
                            PathLine { x: carousel.centerX + carousel.edge; y: carousel.centerY }
                            PathPercent { value: 1 }
                            PathAttribute { name: "itemScale"; value: 0.52 }
                            PathAttribute { name: "itemZ"; value: 0 }
                            PathAttribute { name: "itemOpacity"; value: 0 }
                            PathAttribute { name: "itemDim"; value: 0.8 }
                            PathAttribute { name: "itemAngle"; value: -42 }
                        }

                        /*
                         * Keys and the wheel drive the offset themselves. PathView's own step
                         * restarts a fixed-length ease-in-out on every press, so a held key
                         * (a press every ~30 ms) kept dropping back to a standstill, worst at
                         * the switch from single steps to auto-repeat. A smoothed animation
                         * keeps its speed when the target moves on, so a held key ramps into
                         * a steady glide and eases out on the last card.
                         *
                         * The target never runs more than `driveLead` cards ahead: that caps a
                         * held key at ~15 cards a second (auto-repeat alone asks for 35, too
                         * fast to read), and a release stops close to where you let go.
                         *
                         * The offset is unwrapped here (it runs past the ends) and wrapped as
                         * it is written; StrictlyEnforceRange keeps currentIndex on it.
                         */
                        property real driveOffset: 0
                        property real driveTarget: 0
                        property bool driving: false
                        readonly property int driveLead: 5
                        Behavior on driveOffset {
                            enabled: carousel.driving
                            SmoothedAnimation {
                                id: carouselDrive
                                velocity: -1
                                // One step outlasts the key-repeat delay (250 ms here), so the
                                // repeats pick the glide up still moving instead of from a stop.
                                duration: 340
                                maximumEasingTime: 90
                            }
                        }
                        onDriveOffsetChanged: {
                            if (carousel.driving && carousel.count > 0)
                                carousel.offset = ((carousel.driveOffset % carousel.count) + carousel.count) % carousel.count;
                        }
                        // A drag takes the offset over; writing with the drive off also stops it.
                        onDraggingChanged: if (carousel.dragging) carousel.stopDrive()

                        function stopDrive() {
                            carousel.driving = false;
                            carousel.driveOffset = carousel.offset;
                        }

                        function moveSelection(delta) {
                            if (carousel.count <= 1 || delta === 0)
                                return;
                            if (!carousel.driving || !carouselDrive.running) {
                                carousel.stopDrive();
                                carousel.driveTarget = Math.round(carousel.offset);
                                carousel.driving = true;
                            }
                            // Moving to the next card lowers the offset.
                            const target = carousel.driveTarget - delta;
                            const lead = Math.max(carousel.driveLead, Math.abs(delta));
                            if (Math.abs(target - carousel.driveOffset) > lead)
                                return;
                            carousel.driveTarget = target;
                            carousel.driveOffset = carousel.driveTarget;
                        }

                        function activateCurrent() {
                            if (carousel.count <= 0)
                                return;
                            wallpaperSelectorContent.activateModelData(wallpaperSelectorContent.modelAt(carousel.currentIndex));
                        }

                        function resetSelection() {
                            carousel.selectedKey = "";
                            carousel.scheduleRestore();
                        }

                        function jumpTo(index) {
                            carousel.stopDrive();
                            const duration = carousel.highlightMoveDuration;
                            carousel.highlightMoveDuration = 0;
                            carousel.currentIndex = index;
                            carousel.highlightMoveDuration = duration;
                        }

                        function scheduleRestore() {
                            carousel.restorePending = true;
                            Qt.callLater(carousel.restoreSelection);
                        }

                        /**
                         * The folder model is cleared and refilled whenever it re-sorts (which
                         * it does once more, a moment after opening, when creation times come
                         * in), so an index is not a wallpaper. Find the one that was selected by
                         * its path; failing that the applied one; failing that the first.
                         */
                        function restoreSelection() {
                            if (!carousel.restorePending)
                                return;
                            carousel.restorePending = false;
                            if (carousel.count <= 0)
                                return;
                            const target = wallpaperSelectorContent.restoreIndex(carousel.count, carousel.selectedKey);
                            carousel.jumpTo(target);
                            carousel.selectedKey = wallpaperSelectorContent.wallpaperModelKey(wallpaperSelectorContent.modelAt(target));
                        }

                        onCountChanged: carousel.scheduleRestore()
                        onModelChanged: carousel.scheduleRestore()
                        onCurrentIndexChanged: {
                            if (carousel.restorePending || carousel.count <= 0)
                                return;
                            const key = wallpaperSelectorContent.wallpaperModelKey(wallpaperSelectorContent.modelAt(carousel.currentIndex));
                            if (key.length > 0)
                                carousel.selectedKey = key;
                        }

                        /**
                         * The wheel steps the carousel: one mouse notch is one wallpaper, and
                         * a touchpad swipe moves one per ~40% of a card of travel. Either axis
                         * counts, since a mouse sends y and a sideways swipe sends x.
                         */
                        WheelHandler {
                            target: null
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const pixels = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.pixelDelta.y;
                                const angle = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                                const amount = pixels !== 0 ? pixels : angle;
                                event.accepted = true;
                                if (amount === 0)
                                    return;

                                const stepSize = pixels !== 0 ? carousel.cardWidth * 0.4 : 120;
                                if (Math.sign(amount) !== Math.sign(carousel.wheelAccumulator))
                                    carousel.wheelAccumulator = 0;
                                carousel.wheelAccumulator += amount;
                                const steps = Math.trunc(carousel.wheelAccumulator / stepSize);
                                if (steps === 0)
                                    return;
                                carousel.wheelAccumulator -= steps * stepSize;
                                carousel.moveSelection(-steps);
                            }
                        }

                        delegate: WallpaperDirectoryItem {
                            id: carouselItem
                            required property var modelData
                            required property int index
                            fileModelData: modelData
                            width: carousel.cardWidth
                            height: carousel.cardHeight

                            readonly property bool isCurrent: PathView.isCurrentItem
                            readonly property real itemScale: PathView.itemScale ?? 1
                            readonly property real itemDim: PathView.itemDim ?? 0
                            readonly property real itemAngle: PathView.itemAngle ?? 0
                            readonly property bool appliedState: wallpaperSelectorContent.modelIsApplied(fileModelData)
                            readonly property bool isMoreOptionsSelected: wallpaperSelectorContent.moreOptionsModelData !== null
                                && wallpaperSelectorContent.wallpaperModelKey(fileModelData) === wallpaperSelectorContent.wallpaperModelKey(wallpaperSelectorContent.moreOptionsModelData)

                            z: PathView.itemZ ?? 0
                            opacity: PathView.itemOpacity ?? 1
                            // The hover grow is the item's own `scale`; the carousel's are
                            // transforms so the two never fight over one property.
                            transform: [
                                Scale {
                                    origin.x: carouselItem.width / 2
                                    origin.y: carouselItem.height / 2
                                    xScale: carouselItem.itemScale
                                    yScale: carouselItem.itemScale
                                },
                                Rotation {
                                    origin.x: carouselItem.width / 2
                                    origin.y: carouselItem.height / 2
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: carouselItem.itemAngle
                                }
                            ]

                            // The thumbnail is the whole card; the one caption under the row
                            // names the centred wallpaper.
                            margins: 0
                            padding: 0
                            showName: false
                            thumbnailRadius: Appearance.rounding.normal
                            radius: Appearance.rounding.normal
                            colBackground: Appearance.colors.colLayer2
                            isApplied: appliedState
                            appliedLabel: wallpaperSelectorContent.targetLabel
                            cacheThumbnail: true

                            onThumbnailLoadStateChanged: Qt.callLater(() => wallpaperSelectorContent?.refreshThumbnailDiagnostics())

                            onActivated: {
                                // A neighbour comes to the centre first; the centred one applies.
                                if (!carouselItem.isCurrent) {
                                    // The short way round, on the same glide as the keys.
                                    const n = carousel.count;
                                    let delta = ((carouselItem.index - carousel.currentIndex) % n + n) % n;
                                    if (delta > n / 2)
                                        delta -= n;
                                    carousel.moveSelection(delta);
                                    return;
                                }
                                wallpaperSelectorContent.activateModelData(carouselItem.fileModelData);
                            }
                            onSearchSimilarRequested: (path, id) => {
                                wallpaperSelectorContent.searchForSimilarImages(id)
                            }
                            onMoreOptionsRequested: (modelData) => {
                                wallpaperSelectorContent.toggleMoreOptions(modelData)
                            }

                            // Side cards sink into the dark; hovering one lifts it part way.
                            Rectangle {
                                z: 4
                                anchors.fill: parent
                                radius: carouselItem.radius
                                color: "black"
                                opacity: carouselItem.containsMouse ? carouselItem.itemDim * 0.4 : carouselItem.itemDim
                                visible: opacity > 0
                            }

                            // The selection ring, just outside the centred card.
                            Rectangle {
                                z: 5
                                anchors.fill: parent
                                anchors.margins: -5
                                radius: carouselItem.radius + 5
                                color: "transparent"
                                border.width: 3
                                border.color: carouselItem.isMoreOptionsSelected
                                    ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                                opacity: carouselItem.isCurrent ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        // The side cards sink into the edge of the island the same way
                        // the plain row does: the pixels themselves fade, never a band
                        // of surface colour painted over the translucent body - a
                        // painted band doubles the alpha and reads as another background.
                        layer.enabled: count > 0
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                id: carouselViewportMask
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                                readonly property real fadeFraction: Math.min(0.5, 96 / Math.max(1, width))
                                property real edgeAlpha: carousel.count > 1 ? 0 : 1
                                Behavior on edgeAlpha {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(carouselViewportMask)
                                }
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, carouselViewportMask.edgeAlpha) }
                                    GradientStop { position: carouselViewportMask.fadeFraction; color: "white" }
                                    GradientStop { position: 1.0 - carouselViewportMask.fadeFraction; color: "white" }
                                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, carouselViewportMask.edgeAlpha) }
                                }
                            }
                        }
                    }

                    // The caption: the centred wallpaper's name and where it sits in the row.
                    RowLayout {
                        id: carouselCaption
                        visible: wallpaperSelectorContent.useCarousel && carousel.count > 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Hung from the card rather than the row's bottom, clear of the ring
                        // and the hover grow, so it never runs into the picture.
                        y: carousel.centerY + carousel.cardHeight / 2 + 18
                        spacing: 8

                        readonly property var current: carousel.currentItem ? carousel.currentItem.fileModelData : null

                        StyledText {
                            Layout.maximumWidth: gridDisplayRegion.width * 0.6
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                            text: carouselCaption.current ? String(carouselCaption.current.fileName ?? "") : ""
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            text: `${carousel.currentIndex + 1} / ${carousel.count}`
                        }
                    }
                }

                /**
                 * The toolbar anchor region: search, the actions, sorting, the colour
                 * filter and the per-image options.
                 *
                 * They float over the bottom of the grid. Nothing lives in a row of
                 * its own beneath the wallpapers any more: the island's address row
                 * carries the search and the reload, and the random / colour-filter /
                 * sort toggles stayed in the full selector - so the region is always
                 * zero-height, and the one toolbar compact still shows, the per-image
                 * one, lands on the grid's bottom edge like the others.
                 */
                Item {
                    id: toolbarRegion
                    z: 20
                    Layout.fillWidth: true
                    Layout.preferredHeight: 0

                    WallpaperActionsToolbar {
                        id: actionToolbar
                        // Random, colour filter and the close-search button stayed in
                        // the full selector; reload moved up into the address row.
                        visible: !wallpaperSelectorContent.compact
                        z: 20
                        anchors {
                            bottom: parent.bottom
                            right: extraOptions.left
                            rightMargin: Appearance.sizes.hyprlandGapsOut
                            bottomMargin: 8
                        }

                        opacity: wallpaperGridBackground.animateIn ? 1.0 : 0.0
                        transform: Translate {
                            y: wallpaperGridBackground.animateIn ? 0 : 25
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        Behavior on transform {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    ColorFilterToolbar {
                        id: colorFilterToolbar
                        z: 20
                        colBackground: Appearance.m3colors.m3surfaceContainerLow
                        anchors {
                            bottom: actionToolbar.top
                            left: actionToolbar.left
                            bottomMargin: 8
                        }

                        opacity: wallpaperGridBackground.animateIn ? 1.0 : 0.0
                        transform: Translate {
                            y: wallpaperGridBackground.animateIn ? 0 : 25
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        Behavior on transform {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    ExtraOptionsToolbar {
                        id: extraOptions
                        z: 20
                        onCloseRequested: wallpaperSelectorContent.closeSelector()
                        // Compact draws its own search in the address row.
                        visible: !wallpaperSelectorContent.compact
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: 8
                        }

                        opacity: wallpaperGridBackground.animateIn ? 1.0 : 0.0
                        transform: Translate {
                            y: wallpaperGridBackground.animateIn ? 0 : 25
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        Behavior on transform {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    WallpaperSortToolbar {
                        id: sortToolbar
                        // Sorting is a full-selector toolbar in compact mode.
                        visible: !wallpaperSelectorContent.compact
                        z: 20
                        anchors {
                            left: extraOptions.right
                            leftMargin: Appearance.sizes.hyprlandGapsOut
                            bottom: parent.bottom
                            bottomMargin: 8
                        }

                        opacity: wallpaperGridBackground.animateIn ? 1.0 : 0.0
                        transform: Translate {
                            y: wallpaperGridBackground.animateIn ? 0 : 25
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        Behavior on transform {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    ImageOptionsToolbar {
                        z: 20
                        anchors {
                            bottom: parent.bottom
                            bottomMargin: 8
                            right: parent.right
                            rightMargin: 16
                        }

                        opacity: wallpaperGridBackground.animateIn ? 1.0 : 0.0
                        transform: Translate {
                            y: wallpaperGridBackground.animateIn ? 0 : 25
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        Behavior on transform {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                // The island hands the keyboard over through takeKeyboard; the field
                // only grabs it on its own in the full selector.
                if (!wallpaperSelectorContent.compact)
                    wallpaperSelectorContent.focusSearchInput();
            } else {
                colorCacheProc.signal(9)
            }
        }
    }

    Connections {
        target: Wallpapers
        function onSortChanged() {
            wallpaperSelectorContent.view.resetSelection();
            if (!wallpaperSelectorContent.compact)
                grid.positionViewAtBeginning();
            wallpaperSelectorContent.scheduleThumbnailDiagnostics();
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            GlobalStates.wallpaperSelectorOpen = false;
        }
        function onColorCacheChanged() {
            if (wallpaperSelectorContent.activeColorFilter) {
                wallpaperSelectorContent.applyColorFilter();
            }
        }
        function onWallpapersChanged() {
            if (wallpaperSelectorContent.activeColorFilter) {
                wallpaperSelectorContent.applyColorFilter();
            }
            wallpaperSelectorContent.scheduleThumbnailDiagnostics();
        }
    }
}
