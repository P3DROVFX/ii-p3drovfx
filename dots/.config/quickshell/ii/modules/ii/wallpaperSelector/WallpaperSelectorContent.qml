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
    property int columns: 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    property bool favMode: false
    property bool browserMode: false

    readonly property var sidebarDirectoriesModel: {
        let base = [
            { icon: "home", name: Translation.tr("Home"), path: Directories.home }, 
            { icon: "docs", name: Translation.tr("Documents"), path: Directories.documents }, 
            { icon: "wallpaper", name: Translation.tr("Wallpapers"), path: Config.options.wallpaperSelector.useCustomDefaultPath && Config.options.wallpaperSelector.customDefaultPath ? ("file://" + Config.options.wallpaperSelector.customDefaultPath) : (Directories.pictures + "/Wallpapers") }, 
            { icon: "image", name: Translation.tr("Pictures"), path: Directories.pictures }, 
            { icon: "movie", name: Translation.tr("Videos"), path: Directories.videos }, 
            { icon: "public", name: Translation.tr("Browser"), path: "BROWSER_MODE" }, 
            { icon: "favorite", name: Translation.tr("Favourites"), path: "FAVOURITES_MODE" }, 
            { icon: "", name: "---", path: "INTENTIONALLY_INVALID_DIR" }
        ];

        const favDirs = Persistent.states.wallpaper.favouriteDirectories;
        if (favDirs && favDirs.length > 0) {
            for (let i = 0; i < favDirs.length; i++) {
                const path = favDirs[i];
                const folderName = path.split('/').pop() || path;
                base.push({ icon: "folder_special", name: folderName, path: path });
            }
            base.push({ icon: "", name: "---", path: "INTENTIONALLY_INVALID_DIR" });
        }

        const configDirs = Config.options.wallpaperSelector.directories || [];
        for (let i = 0; i < configDirs.length; i++) {
            const entry = configDirs[i];
            base.push({
                icon: entry.icon || "folder",
                name: entry.name || entry.path.split('/').pop() || "Dir",
                path: entry.path
            });
        }

        if (Config.options.policies.weeb === 1) {
            base.push({ icon: "favorite", name: Translation.tr("Homework"), path: `${Directories.pictures}/homework` });
        }

        return base;
    }

    property var moreOptionsModelData: null
    property string filterText: extraOptions.text

    property string activeColorFilter: ""
    property real colorCacheProgress: 0
    property bool isColorFiltering: false

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

    function updateThumbnails() {
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(grid.cellWidth - totalImageMargin, grid.cellHeight - totalImageMargin);
        Wallpapers.generateThumbnail(thumbnailSizeName);
    }

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            wallpaperSelectorContent.favMode = false;
            wallpaperSelectorContent.browserMode = false;
            wallpaperSelectorContent.updateThumbnails();
            grid.currentIndex = 0;
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
        if (filePath && filePath.length > 0) {
            Wallpapers.select(filePath, wallpaperSelectorContent.useDarkMode);
            filterText = "";
            wallpaperSelectorContent.browserMode = false;
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
        filterText = "";
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
            GlobalStates.wallpaperSelectorOpen = false;
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
            grid.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            grid.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            grid.moveSelection(-grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            grid.moveSelection(grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            grid.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (filterText.length > 0) {
                filterText = filterText.substring(0, filterText.length - 1);
            }
            filterField.forceActiveFocus();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0) {
                filterText += event.text;
                filterField.cursorPosition = filterText.length;
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: wallpaperGridBackground
    }
    Rectangle {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        property bool animateIn: false

        Connections {
            target: GlobalStates
            function onWallpaperSelectorOpenChanged() {
                if (GlobalStates.wallpaperSelectorOpen) {
                    wallpaperGridBackground.animateIn = false;
                    wpContentDelayTimer.restart();
                } else {
                    wallpaperGridBackground.animateIn = false;
                }
            }
        }

        Timer {
            id: wpContentDelayTimer
            interval: 70
            repeat: false
            running: true
            onTriggered: wallpaperGridBackground.animateIn = true
        }

        scale: wallpaperGridBackground.animateIn && GlobalStates.wallpaperSelectorOpen ? 1.0 : 0.95
        opacity: wallpaperGridBackground.animateIn && GlobalStates.wallpaperSelectorOpen ? 1.0 : 0.0

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
            spacing: -4

            Rectangle {
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

                    StyledText {
                        Layout.margins: 12
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.Medium
                        }
                        text: Translation.tr("Pick a wallpaper")
                    }
                    Item {
                        id: quickDirsContainer
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        implicitWidth: 160

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
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                Layout.topMargin: 0
                                expanded: true
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
                                        
                                        baseSize: 40
                                        baseHighlightHeight: 32
                                        iconSize: 18
                                        
                                        buttonIcon: modelData.icon
                                        buttonText: modelData.name
                                        expanded: true
                                        toggled: sideBarRail.currentIndex === index
                                        showToggledHighlight: false
                                        
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

                    // Top Scroll Fade Gradient Overlay
                    Rectangle {
                        z: 10
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

                    StyledIndeterminateProgressBar {
                        id: indeterminateProgressBar
                        visible: (Wallpapers.thumbnailGenerationRunning && value == 0) || (wallpaperSelectorContent.browserMode && WallpaperBrowser.runningRequests > 0) || (wallpaperSelectorContent.colorCacheProgress === 0 && colorCacheProc.running) || wallpaperSelectorContent.isColorFiltering
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

                    StyledText {
                        visible: (wallpaperSelectorContent.favMode && grid.model.count === 0) || (wallpaperSelectorContent.browserMode && grid.model.length === 0)
                        text: {
                            if (wallpaperSelectorContent.browserMode) {
                                return (WallpaperBrowser.runningRequests > 0) ? Translation.tr("Searching...") : Translation.tr("Search wallpapers with the search bar at the bottom.");
                            }
                            return Translation.tr("No favourites yet. Click the heart icon on any wallpaper to add it to favourites.");
                        }
                        anchors.centerIn: parent

                        font.family: Appearance.font.family.reading
                    }

                    GridView {
                        id: grid
                        visible: count > 0

                        readonly property int columns: wallpaperSelectorContent.columns
                        readonly property int rows: Math.max(1, Math.ceil(count / columns))
                        property int currentIndex: 0

                        anchors.fill: parent
                        cellWidth: width / wallpaperSelectorContent.columns
                        cellHeight: cellWidth / wallpaperSelectorContent.previewCellAspectRatio
                        interactive: true
                        clip: true
                        keyNavigationWraps: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}

                        // Touchpad and mouse scroll physics adjustments
                        property real scrollTargetY: 0
                        property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
                        property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
                        property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

                        maximumFlickVelocity: 3500

                        MouseArea {
                            z: 99
                            visible: Config?.options.interactions.scrolling.fasterTouchpadScroll
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

                        Behavior on contentY {
                            NumberAnimation {
                                id: scrollAnim
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

                        Component.onCompleted: {
                            Qt.callLater(() => loadTimer.start())
                            wallpaperSelectorContent.updateThumbnails()
                        }

                        function moveSelection(delta) {
                            currentIndex = Math.max(0, Math.min(grid.model.count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }

                        function activateCurrent() {
                            let filePath;
                            if (wallpaperSelectorContent.browserMode) {
                                filePath = grid.model[currentIndex].filePath;
                            } else if (wallpaperSelectorContent.favMode || wallpaperSelectorContent.activeColorFilter) {
                                filePath = grid.model.get(currentIndex).filePath;
                            } else {
                                filePath = grid.model.get(currentIndex, "filePath");
                            }
                            wallpaperSelectorContent.selectWallpaperPath(filePath);
                        }

                        property int loadedCount: 0

                        Timer {
                            id: loadTimer
                            interval: 16
                            repeat: true
                            running: false
                            onTriggered: {
                                grid.loadedCount += 1
                                if (grid.loadedCount >= grid.count) loadTimer.stop()
                            }
                        }

                        model: wallpaperSelectorContent.browserMode ? wallpaperSelectorContent.apiImages : (wallpaperSelectorContent.favMode ? favouritesModel : (wallpaperSelectorContent.activeColorFilter ? colorFilteredModel : Wallpapers.folderModel))
                        onModelChanged: {
                            currentIndex = 0
                            loadedCount = 0
                            loadTimer.restart()
                        }
                        onCountChanged: {
                            if (count > 0 && loadedCount < count) {
                                loadTimer.restart()
                            }
                        }
                        delegate: WallpaperDirectoryItem {
                            id: wpItemDelegate
                            required property var modelData
                            required property int index
                            fileModelData: modelData
                            width: grid.cellWidth
                            height: grid.cellHeight

                            readonly property int cols: grid.columns
                            readonly property int itemRow: Math.floor(index / Math.max(1, cols))
                            readonly property int itemCol: index % Math.max(1, cols)
                            readonly property int cascadeDelay: (itemRow * 50) + (itemCol * 35)

                            colBackground: (index === grid?.currentIndex || containsMouse) ? Appearance.colors.colPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colSecondaryContainer : (fileModelData.filePath === wallpaperSelectorContent.moreOptionsModelData?.filePath) ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                            colText: (index === grid.currentIndex || containsMouse) ? Appearance.colors.colOnPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colOnSecondaryContainer : (fileModelData.filePath === wallpaperSelectorContent.moreOptionsModelData?.filePath) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                            shouldLoad: index < grid.loadedCount

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

                            onEntered: {
                                grid.currentIndex = index;
                            }

                            onActivated: {
                                wallpaperSelectorContent.selectWallpaperPath(fileModelData.actualPath || fileModelData.filePath);
                            }

                            onSearchSimilarRequested: (path, id) => {
                                wallpaperSelectorContent.searchForSimilarImages(id)
                            }
                            onMoreOptionsRequested: (modelData) => {
                                wallpaperSelectorContent.moreOptionsModelData = modelData
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    ColorFilterToolbar {
                        id: colorFilterToolbar
                        z: 20
                        colBackground: Appearance.m3colors.m3surfaceContainerLow
                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            leftMargin: 16
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
                        colBackground: Appearance.m3colors.m3surfaceContainerLow
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

                    ImageOptionsToolbar {
                        z: 20
                        colBackground: Appearance.colors.colPrimary
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
                if (monitorIsFocused) {
                    filterField.forceActiveFocus();
                }
            } else {
                colorCacheProc.signal(9)
            }
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
        }
    }
}