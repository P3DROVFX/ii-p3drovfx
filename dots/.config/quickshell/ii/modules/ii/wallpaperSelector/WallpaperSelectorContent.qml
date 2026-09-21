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
     * One row of wallpapers instead of a page of them: the folder path stays at the top
     * as the way between directories, the sidebar goes (the island has no room for a
     * second navigation), and the toolbars move from floating over the grid to a row
     * beneath it. Everything else - the model, the thumbnails, the colour filter, the
     * delegates, the toolbars themselves - is the browser as it already is, which is why
     * this is a layout switch and not a second implementation.
     *
     * The host owns the surface and the open animation in this mode, so the panel's own
     * background, shadow and entrance are all off; see `active` and `closeRequested`.
     */
    property bool compact: false
    /**
     * The colour the compact layout's edge fades fade into: the host's surface, which
     * is the island body and follows the expressive bar theme when one is on. The full
     * selector draws its own background, so it is that.
     */
    property color surfaceColor: Appearance.colors.colLayer0
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
    /** The carousel's centred card, at the screens' own 16:10-ish shape. */
    readonly property real compactCardWidth: 336
    readonly property real compactCardHeight: 210
    /** The one caption under the row: the centred wallpaper's name and its place. */
    readonly property real compactCaptionHeight: 50
    /** Room above the card for the hover grow and the selection ring. */
    readonly property real compactCardInset: 10
    readonly property real compactRowHeight: compactCardInset + compactCardHeight + compactCaptionHeight
    readonly property real compactPadding: 8
    // The centred card and a neighbour and a half on each side.
    readonly property real contentTargetWidth: 3 * compactCardWidth + 2 * compactPadding
    readonly property real contentTargetHeight: compactAddressRowHeight
        + compactRowHeight + compactToolbarRowHeight + 2 * compactPadding
    /** The path row and the toolbar row, both fixed: neither animates. */
    readonly property real compactAddressRowHeight: Appearance.sizes.toolbarHeight + 8
    readonly property real compactToolbarRowHeight: Appearance.sizes.toolbarHeight + 12
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
    property string filterText: extraOptions.text
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
     * The grid in the full selector, the carousel in the island. Both answer to the same
     * few calls - count, currentIndex, moveSelection, activateCurrent, resetSelection -
     * so the keys and the toolbars don't need to know which one is on screen.
     */
    readonly property Item view: compact ? carousel : grid

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

    function updateThumbnails(force = false) {
        scheduleThumbnailDiagnostics();
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(grid.cellWidth - totalImageMargin, grid.cellHeight - totalImageMargin);
        Wallpapers.generateThumbnail(thumbnailSizeName, force);
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

    Component.onCompleted: wallpaperSelectorContent.scheduleThumbnailDiagnostics()
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
        extraOptions.clearSearch();
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
        extraOptions.clearSearch();
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
                extraOptions.setSearchText(filterText.substring(0, filterText.length - 1));
            }
            extraOptions.focusSearch();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            extraOptions.focusSearch();
            event.accepted = true;
        } else {
            if (event.text.length > 0) {
                extraOptions.setSearchText(filterText + event.text);
                extraOptions.focusSearch();
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

                RowLayout {
                    Layout.margins: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 8
                    visible: !wallpaperSelectorContent.favMode && !wallpaperSelectorContent.browserMode

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
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        directory: Wallpapers.effectiveDirectory
                        onNavigateToDirectory: path => {
                            Wallpapers.setDirectory(path.length == 0 ? "/" : path);
                        }
                        radius: wallpaperGridBackground.radius - 4
                    }

                    RippleButton {
                        id: favFolderBtn
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

                Rectangle {
                    visible: wallpaperSelectorContent.favMode || wallpaperSelectorContent.browserMode
                    Layout.margins: 4
                    Layout.fillWidth: true
                    implicitHeight: addressBar.implicitHeight
                    color: Appearance.colors.colLayer2
                    radius: wallpaperGridBackground.radius - Layout.margins

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

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // The row scrolls sideways in compact mode, so the fade that says
                    // "there is more" turns with it: the same gradient, rotated onto the
                    // left and right edges.
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

                    // Left edge fade (compact)
                    Rectangle {
                        z: 10
                        visible: wallpaperSelectorContent.compact
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 96
                        opacity: carousel.count > 1 ? 1.0 : 0.0
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: wallpaperSelectorContent.surfaceColor }
                            GradientStop { position: 0.45; color: ColorUtils.transparentize(wallpaperSelectorContent.surfaceColor, 0.15) }
                            GradientStop { position: 0.75; color: ColorUtils.transparentize(wallpaperSelectorContent.surfaceColor, 0.60) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // Right edge fade (compact)
                    Rectangle {
                        z: 10
                        visible: wallpaperSelectorContent.compact
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 96
                        opacity: carousel.count > 1 ? 1.0 : 0.0
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.25; color: ColorUtils.transparentize(wallpaperSelectorContent.surfaceColor, 0.60) }
                            GradientStop { position: 0.55; color: ColorUtils.transparentize(wallpaperSelectorContent.surfaceColor, 0.15) }
                            GradientStop { position: 1.0; color: wallpaperSelectorContent.surfaceColor }
                        }
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
                                            extraOptions.focusSearch();
                                        }
                                    } else if (wallpaperSelectorContent.favMode) {
                                        wallpaperSelectorContent.openDefaultFolder();
                                    } else if (wallpaperSelectorContent.localSearchActive) {
                                        extraOptions.clearSearch();
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
                        cellWidth: width / wallpaperSelectorContent.columns
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
                            enabled: wallpaperSelectorContent.compact
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

                        // The carousel draws the island's row; the grid holds nothing there.
                        model: wallpaperSelectorContent.compact ? null : wallpaperSelectorContent.viewModel
                        onModelChanged: {
                            currentIndex = -1
                            keyboardNavigationActive = false
                            loadedCount = 0
                            loadTimer.restart()
                            wallpaperSelectorContent.scheduleThumbnailDiagnostics()
                        }
                        onCountChanged: {
                            if (count <= 0) {
                                currentIndex = -1;
                                keyboardNavigationActive = false;
                            }
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
                                : (isKeyboardSelected || containsMouse) ? Appearance.colors.colLayer2Hover
                                : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer))
                            colText: appliedState ? Appearance.colors.colOnPrimaryContainer
                                : (isMoreOptionsSelected || isKeyboardSelected || containsMouse) ? Appearance.colors.colOnLayer2
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

                        // Empty in compact (the carousel draws the row), so no mask to allocate.
                        layer.enabled: !wallpaperSelectorContent.compact
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
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
                     * Only built when compact: the full selector gives it no model, so it
                     * holds no delegates there.
                     */
                    PathView {
                        id: carousel
                        anchors.fill: parent
                        visible: wallpaperSelectorContent.compact && count > 0
                        model: wallpaperSelectorContent.compact ? wallpaperSelectorContent.viewModel : null

                        readonly property real cardWidth: wallpaperSelectorContent.compactCardWidth
                        readonly property real cardHeight: wallpaperSelectorContent.compactCardHeight
                        readonly property real centerX: width / 2
                        readonly property real centerY: wallpaperSelectorContent.compactCardInset + cardHeight / 2
                        // Card centres, measured out from the middle: the first neighbour tucks
                        // under the centred card, the second under the first, and the ends sit
                        // past the row's edge so a card slides in rather than popping up.
                        readonly property real near: 0.7 * cardWidth
                        readonly property real far: 1.2 * cardWidth
                        readonly property real edge: 1.6 * cardWidth
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
                            let found = -1;
                            let applied = -1;
                            for (let i = 0; i < carousel.count; i++) {
                                const item = wallpaperSelectorContent.modelAt(i);
                                if (!item)
                                    continue;
                                if (carousel.selectedKey.length > 0
                                        && wallpaperSelectorContent.wallpaperModelKey(item) === carousel.selectedKey) {
                                    found = i;
                                    break;
                                }
                                if (applied < 0 && wallpaperSelectorContent.modelIsApplied(item))
                                    applied = i;
                            }
                            const target = found >= 0 ? found : Math.max(0, applied);
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
                    }

                    // The caption: the centred wallpaper's name and where it sits in the row.
                    RowLayout {
                        id: carouselCaption
                        visible: wallpaperSelectorContent.compact && carousel.count > 0
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
                 * The toolbars: search, the actions, sorting, the colour filter and the
                 * per-image options.
                 *
                 * They float over the bottom of the grid in the full selector, and sit in
                 * a row of their own beneath the wallpapers in compact mode. One region
                 * serves both: it is a real row when compact and zero-height when not,
                 * which leaves its bottom edge exactly where the grid's bottom edge was -
                 * so the toolbars anchored to it land where they always have.
                 */
                Item {
                    id: toolbarRegion
                    z: 20
                    Layout.fillWidth: true
                    Layout.preferredHeight: wallpaperSelectorContent.compact
                        ? wallpaperSelectorContent.compactToolbarRowHeight : 0

                    WallpaperActionsToolbar {
                        id: actionToolbar
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
                extraOptions.focusSearch();
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
