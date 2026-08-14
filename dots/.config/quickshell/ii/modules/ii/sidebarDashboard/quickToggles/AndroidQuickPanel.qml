import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarDashboard.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    // Current page index
    property int currentPage: 0

    // Entrance animation trigger
    property int entranceTrigger: -1

    function triggerContentEntrance() {
        entranceTrigger++;
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                root.triggerContentEntrance();
            }
        }
    }

    // Sizes
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns));
        return availableWidth / root.columns;
    }
    readonly property real baseCellHeight: 56

    // Toggles config
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "vpn", "tailscale", "dnsOverTls", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "screenRecord", "colorPicker", "videoEditor", "onScreenKeyboard", "mic", "audio", "notifications", "autoDnd", "powerProfile", "musicRecognition", "antiFlashbang", "screenShader", "soundcoreAnc", "systemSounds", "localSend", "mediaWidget", "volumeSlider", "micSlider", "brightnessSlider", "gammaSlider", "keyboardBacklight"]
    function isToggleVisible(toggleType) {
        return true
    }
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns

    function normalizedSpan(value, fallback, maximum) {
        var numericValue = Number(value);
        if (!isFinite(numericValue))
            numericValue = fallback;
        numericValue = Math.round(numericValue);
        return Math.max(1, Math.min(numericValue, maximum));
    }

    // Keep one canonical representation of the layout. Old/stale config entries can
    // otherwise be counted by the height calculator even when no delegate exists for
    // them, and duplicate toggle types break ScriptModel's type-based identity.
    function normalizePages(rawPages) {
        if (!rawPages || rawPages.length === 0)
            return [[]];

        var inputPages = rawPages;
        var first = inputPages[0];
        if (first && typeof first === "object" && first.type !== undefined)
            inputPages = [rawPages];

        var seenTypes = {};
        var normalized = [];
        for (var p = 0; p < inputPages.length; p++) {
            var sourcePage = inputPages[p] || [];
            var page = [];
            for (var i = 0; i < sourcePage.length; i++) {
                var toggle = sourcePage[i];
                if (!toggle || !toggle.type)
                    continue;
                if (!root.availableToggleTypes.includes(toggle.type) || !root.isToggleVisible(toggle.type))
                    continue;
                if (seenTypes[toggle.type])
                    continue;

                var t = Object.assign({}, toggle);
                var defaultH = (t.type === "mediaWidget") ? 2 : 1;
                var defaultW = (t.type === "mediaWidget") ? 2 : 1;
                t.sizeW = root.normalizedSpan(t.sizeW ?? t.size, defaultW, Math.max(1, root.columns));
                t.sizeH = root.normalizedSpan(t.sizeH, defaultH, 8);
                t.size = t.sizeW;
                seenTypes[t.type] = true;
                page.push(t);
            }
            normalized.push(page);
        }

        return normalized.length > 0 ? normalized : [[]];
    }

    // Pages data — reads from Config.
    // The stored format is: pages = [[toggle, toggle, ...], [toggle, ...], ...]
    // Each inner array is one page. Each toggle is {type: string, size: int}.
    readonly property list<var> pages: {
        const cfg = Config.options.sidebar.quickToggles.android;
        if (!Config.ready)
            return [[]];
        return root.normalizePages(cfg.pages);
    }

    // Current page toggles
    readonly property list<var> currentPageToggles: {
        if (currentPage >= 0 && currentPage < pages.length)
            return pages[currentPage] || [];
        return [];
    }

    // All used toggle types across all pages
    readonly property list<string> allUsedTypes: {
        var types = [];
        for (var p = 0; p < pages.length; p++) {
            var page = pages[p];
            if (!page)
                continue;
            for (var i = 0; i < page.length; i++) {
                if (page[i] && page[i].type)
                    types.push(page[i].type);
            }
        }
        return types;
    }

    // The catalog owns stable JS objects. Recreating every object whenever a toggle is
    // added/removed makes ScriptModel emit dataChanged for every surviving row even
    // though objectProp is "type". DelegateChooser can then keep a stale concrete
    // delegate while rows are shifted, which is why the visually removed tray item can
    // differ from the type that was actually added to the page.
    readonly property var toggleCatalog: availableToggleTypes.map(type => {
        return {
            type: type,
            size: (type === "mediaWidget") ? 2 : 1,
            sizeW: (type === "mediaWidget") ? 2 : 1,
            sizeH: (type === "mediaWidget") ? 2 : 1
        };
    })

    readonly property var unusedToggles: toggleCatalog.filter(toggle =>
        root.isToggleVisible(toggle.type) && !allUsedTypes.includes(toggle.type)
    )

    function getGridRowsNeeded(togglesList) {
        if (!togglesList || togglesList.length === 0)
            return 0;
        var cols = Math.max(1, columns);
        var grid = [];

        function isFree(r, c, w, h) {
            if (c + w > cols) return false;
            for (var dr = 0; dr < h; dr++) {
                var rowArr = grid[r + dr];
                if (rowArr) {
                    for (var dc = 0; dc < w; dc++) {
                        if (rowArr[c + dc]) return false;
                    }
                }
            }
            return true;
        }

        function markOccupied(r, c, w, h) {
            for (var dr = 0; dr < h; dr++) {
                var rowIdx = r + dr;
                while (grid.length <= rowIdx) {
                    grid.push(new Array(cols).fill(false));
                }
                for (var dc = 0; dc < w; dc++) {
                    grid[rowIdx][c + dc] = true;
                }
            }
        }

        // GridLayout auto-placement advances through the grid in model order. Starting
        // every item again at row 0 backfills old holes differently from GridLayout and
        // can make the simulated row count diverge by one after a resize. Keep a cursor
        // and only search forward, while still honoring vertical spans with the matrix.
        var cursorRow = 0;
        var cursorColumn = 0;
        var maxRow = 0;
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i])
                continue;
            var t = togglesList[i];
            var defaultH = (t.type === "mediaWidget") ? 2 : 1;
            var defaultW = (t.type === "mediaWidget") ? 2 : 1;
            var w = root.normalizedSpan(t.sizeW ?? t.size, defaultW, cols);
            var h = root.normalizedSpan(t.sizeH, defaultH, 8);

            var r = cursorRow;
            var c = cursorColumn;
            var placed = false;
            while (!placed) {
                if (c + w > cols) {
                    r++;
                    c = 0;
                    continue;
                }

                if (isFree(r, c, w, h)) {
                    markOccupied(r, c, w, h);
                    maxRow = Math.max(maxRow, r + h);
                    cursorRow = r;
                    cursorColumn = c + w;
                    if (cursorColumn >= cols) {
                        cursorRow++;
                        cursorColumn = 0;
                    }
                    placed = true;
                } else {
                    c++;
                    if (c >= cols) {
                        r++;
                        c = 0;
                    }
                }
            }
        }
        return maxRow;
    }



    // Calculate height for a specific page
    function pageHeight(pageIndex) {
        if (pageIndex < 0 || pageIndex >= pages.length)
            return baseCellHeight + 8;
        var pageToggles = pages[pageIndex] || [];
        var rows = getGridRowsNeeded(pageToggles);
        return Math.max(baseCellHeight, rows * (baseCellHeight + spacing) - spacing) + 8;
    }

    // Dynamic height based on current page + page indicators
    readonly property real currentContentHeight: pageHeight(currentPage) + (editMode ? 14 : 0)
    readonly property real pageIndicatorHeight: pages.length > 1 ? 20 : 0

    implicitHeight: contentItem.implicitHeight + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // Helper: deep-clone the canonical pages, run mutator, sanitize and reassign.
    // Cloning Config's raw list preserved stale/duplicate entries forever and let the
    // rendered model drift away from the persisted one.
    function mutatePages(mutatorFn) {
        if (!Config.ready)
            return;
        var cloned = JSON.parse(JSON.stringify(root.pages));
        mutatorFn(cloned);
        Config.options.sidebar.quickToggles.android.pages = root.normalizePages(cloned);
    }

    function resolveLayoutConflicts(pageIndex, gridColumns) {
        var cols = Math.max(1, gridColumns);
        mutatePages(function (pages) {
            if (pageIndex < 0 || pageIndex >= pages.length)
                return;
            var page = pages[pageIndex];
            if (!page || page.length === 0)
                return;

            for (var i = 0; i < page.length; i++) {
                if (!page[i]) continue;
                var w = page[i].sizeW ?? page[i].size ?? 1;
                var h = page[i].sizeH ?? 1;
                w = Math.max(1, Math.min(w, cols));
                h = Math.max(1, h);
                page[i].sizeW = w;
                page[i].sizeH = h;
                page[i].size = w;
            }
        });
    }

    // Page management functions
    function addPage() {
        var targetPage;
        mutatePages(function (p) {
            p.push([]);
            targetPage = p.length - 1;
        });
        currentPage = targetPage;
    }

    function removePage(pageIndex) {
        if (pages.length <= 1)
            return; // Never remove last page
        if (pageIndex < 0 || pageIndex >= pages.length)
            return;

        mutatePages(function (p) {
            p.splice(pageIndex, 1);
        });

        if (currentPage >= pages.length)
            currentPage = Math.max(0, pages.length - 1);
    }

    function goToPage(pageIndex) {
        if (pageIndex < 0 || pageIndex >= pages.length)
            return;
        currentPage = pageIndex;
    }

    // Drag-scroll: called by toggle buttons during drag to auto-scroll pages
    // absX: x coordinate mapped to panel root
    // dragButton: the toggle button being dragged
    property real dragScrollEdgeThreshold: 40
    property int dragScrollPendingPage: -1

    Timer {
        id: dragScrollTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root.dragScrollPendingPage >= 0 && root.dragScrollPendingPage < root.pages.length) {
                root.currentPage = root.dragScrollPendingPage;
                // Notify all dragging buttons about the new target page
                root.dragScrollPageChanged(root.dragScrollPendingPage);
            }
            root.dragScrollPendingPage = -1;
        }
    }

    signal dragScrollPageChanged(int newPage)

    function cancelDragScroll() {
        dragScrollTimer.stop();
        dragScrollPendingPage = -1;
    }

    function handleDragScrollRequest(absX, dragButton) {
        var newPage = -1;
        if (absX < dragScrollEdgeThreshold && currentPage > 0) {
            newPage = currentPage - 1;
        } else if (absX > root.width - dragScrollEdgeThreshold && currentPage < pages.length - 1) {
            newPage = currentPage + 1;
        }

        if (newPage >= 0 && newPage !== dragScrollPendingPage) {
            dragScrollPendingPage = newPage;
            dragScrollTimer.restart();
            // Update dragTargetPage on the button immediately for visual feedback
            if (dragButton && dragButton.hasOwnProperty("dragTargetPage")) {
                dragButton.dragTargetPage = newPage;
            }
        } else if (newPage < 0) {
            // Back in safe zone — reset pending
            dragScrollPendingPage = -1;
            dragScrollTimer.stop();
            if (dragButton && dragButton.hasOwnProperty("dragTargetPage")) {
                dragButton.dragTargetPage = dragButton.pageIndex;
            }
        }
    }

    // Move a toggle from one page to another at the drop position
    function moveToggleToPage(buttonType, fromPage, toPage, dropAbsX, dropAbsY) {
        if (fromPage === toPage)
            return;
        if (toPage < 0 || toPage >= pages.length)
            return;

        mutatePages(function (pages) {
            if (fromPage < 0 || fromPage >= pages.length)
                return;
            var sourcePage = pages[fromPage];
            if (!sourcePage)
                return;

            // Find and remove the toggle from the source page
            var toggleData = null;
            for (var i = 0; i < sourcePage.length; i++) {
                if (sourcePage[i].type === buttonType) {
                    toggleData = JSON.parse(JSON.stringify(sourcePage[i]));
                    sourcePage.splice(i, 1);
                    break;
                }
            }
            if (!toggleData)
                return;

            // Append to the target page (position at end, layout engine will sort)
            var targetPage = pages[toPage];
            if (!targetPage) pages[toPage] = [];
            pages[toPage].push(toggleData);
        });
    }

    Column {
        id: contentItem
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 8

        Column {
            id: fixedSlidersColumn
            width: parent.width
            spacing: root.spacing

            Repeater {
                id: fixedSlidersRepeater
                model: ScriptModel {
                    values: {
                        var list = [];
                        const cfg = Config.options.sidebar.quickSliders;
                        if (cfg.enable) {
                            if (cfg.showBrightness)
                                list.push({
                                    type: "brightnessSlider",
                                    sizeW: root.columns,
                                    sizeH: 1,
                                    size: root.columns
                                });
                            if (cfg.showGamma)
                                list.push({
                                    type: "gammaSlider",
                                    sizeW: root.columns,
                                    sizeH: 1,
                                    size: root.columns
                                });
                            if (cfg.showVolume)
                                list.push({
                                    type: "volumeSlider",
                                    sizeW: root.columns,
                                    sizeH: 1,
                                    size: root.columns
                                });
                            if (cfg.showMic)
                                list.push({
                                    type: "micSlider",
                                    sizeW: root.columns,
                                    sizeH: 1,
                                    size: root.columns
                                });
                        }
                        return list;
                    }
                    objectProp: "type"
                }
                delegate: AndroidToggleDelegateChooser {
                    editMode: false // Force false so they can't be dragged
                    baseCellWidth: root.baseCellWidth
                    baseCellHeight: root.baseCellHeight
                    spacing: root.spacing
                    isUnused: false
                    pageIndex: -1
                    gridColumns: root.columns
                    panel: root
                    gridRef: fixedSlidersColumn
                    entranceTrigger: root.entranceTrigger

                    onOpenAudioOutputDialog: root.openAudioOutputDialog()
                    onOpenAudioInputDialog: root.openAudioInputDialog()
                    onOpenBluetoothDialog: root.openBluetoothDialog()
                    onOpenNightLightDialog: root.openNightLightDialog()
                    onOpenWifiDialog: root.openWifiDialog()
                    onOpenDarkModeDialog: root.openDarkModeDialog()
                    onOpenLocalSendDialog: root.openLocalSendDialog()
                    onOpenVpnDialog: root.openVpnDialog()
                    onOpenTailscaleDialog: root.openTailscaleDialog()
                    onOpenDnsOverTlsDialog: root.openDnsOverTlsDialog()
                    onOpenIdleInhibitorDialog: root.openIdleInhibitorDialog()
                    onOpenScreenShaderDialog: root.openScreenShaderDialog()
                }
            }
        }

        // Horizontal paging container
        Item {
            id: flickableContainer
            width: parent.width
            height: root.currentContentHeight

            Behavior on height {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            clip: true

            Flickable {
                id: flickable
                anchors.fill: parent
                contentWidth: width * root.pages.length
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: !root.editMode

                // Snap to page on release
                onMovementEnded: {
                    var targetPage = Math.round(contentX / width);
                    targetPage = Math.max(0, Math.min(targetPage, root.pages.length - 1));
                    root.currentPage = targetPage;
                    snapAnimation.to = targetPage * width;
                    snapAnimation.start();
                }

                // Mouse wheel / scroll paging
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: function (wheelEvent) {
                        if (Math.abs(wheelEvent.angleDelta.x) > Math.abs(wheelEvent.angleDelta.y)) {
                            // Horizontal scroll
                            if (wheelEvent.angleDelta.x < 0 && root.currentPage < root.pages.length - 1) {
                                root.goToPage(root.currentPage + 1);
                            } else if (wheelEvent.angleDelta.x > 0 && root.currentPage > 0) {
                                root.goToPage(root.currentPage - 1);
                            }
                        } else {
                            // Vertical scroll → map to horizontal paging
                            if (wheelEvent.angleDelta.y < 0 && root.currentPage < root.pages.length - 1) {
                                root.goToPage(root.currentPage + 1);
                            } else if (wheelEvent.angleDelta.y > 0 && root.currentPage > 0) {
                                root.goToPage(root.currentPage - 1);
                            }
                        }
                        wheelEvent.accepted = true;
                    }
                }

                NumberAnimation {
                    id: snapAnimation
                    target: flickable
                    property: "contentX"
                    duration: 350
                    easing.type: Easing.OutQuint
                }

                Row {
                    id: pagesRow
                    height: parent.height

                    Repeater {
                        id: pagesRepeater
                        model: root.pages.length

                        Item {
                            id: pageContainer
                            required property int index
                            width: flickable.width
                            height: flickable.height

                            // Show only current page content as visible when current
                            property bool isCurrent: root.currentPage === index
                            property list<var> pageToggles: root.pages[index] || []

                            Loader {
                                id: pageContentLoader
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                active: pageContainer.isCurrent || root.editMode
                                asynchronous: true
                                sourceComponent: GridLayout {
                                    id: pageContentGrid
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                    }
                                    columns: root.columns
                                    columnSpacing: root.spacing
                                    rowSpacing: root.spacing
                                    objectName: "pageContent_" + pageContainer.index

                                    Repeater {
                                        model: root.columns
                                        Item {
                                            required property int index
                                            Layout.row: 1000
                                            Layout.column: index
                                            Layout.columnSpan: 1
                                            Layout.rowSpan: 1
                                            Layout.preferredWidth: root.baseCellWidth
                                            Layout.preferredHeight: 0
                                            implicitWidth: root.baseCellWidth
                                            implicitHeight: 0
                                        }
                                    }

                                    Repeater {
                                        id: gridRepeater
                                        model: ScriptModel {
                                            values: pageContainer.pageToggles
                                            objectProp: "type"
                                        }
                                        delegate: AndroidToggleDelegateChooser {

                                            editMode: root.editMode
                                            baseCellWidth: root.baseCellWidth
                                            baseCellHeight: root.baseCellHeight
                                            spacing: root.spacing
                                            isUnused: false
                                            pageIndex: pageContainer.index
                                            gridColumns: root.columns
                                            panel: root
                                            gridRef: pageContentGrid
                                            entranceTrigger: root.entranceTrigger

                                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                                            onOpenAudioInputDialog: root.openAudioInputDialog()
                                            onOpenBluetoothDialog: root.openBluetoothDialog()
                                            onOpenNightLightDialog: root.openNightLightDialog()
                                            onOpenWifiDialog: root.openWifiDialog()
                                            onOpenDarkModeDialog: root.openDarkModeDialog()
                                            onOpenLocalSendDialog: root.openLocalSendDialog()
                                            onOpenVpnDialog: root.openVpnDialog()
                                            onOpenTailscaleDialog: root.openTailscaleDialog()
                                            onOpenDnsOverTlsDialog: root.openDnsOverTlsDialog()
                                            onOpenIdleInhibitorDialog: root.openIdleInhibitorDialog()
                                            onOpenScreenShaderDialog: root.openScreenShaderDialog()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Page indicators (dots)
        Row {
            id: pageIndicators
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            visible: root.pages.length > 1

            Repeater {
                model: root.pages.length
                delegate: Rectangle {
                    required property int index
                    width: root.currentPage === index ? 16 : 8
                    height: 8
                    radius: height / 2
                    color: root.currentPage === index ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    opacity: root.currentPage === index ? 1.0 : 0.5

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToPage(index)
                    }
                }
            }
        }

        // Edit mode: page navigation + add page buttons
        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
            }
            sourceComponent: RowLayout {
                spacing: 6

                // Previous page button
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    visible: root.currentPage > 0
                    buttonRadius: Appearance.rounding.full
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    onClicked: root.goToPage(root.currentPage - 1)
                    contentItem: MaterialSymbol {
                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Page label
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    radius: Appearance.rounding.full
                    color: "transparent"
                    border.color: Appearance.colors.colOutline
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: "auto_awesome_motion"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Page %1 / %2").arg(root.currentPage + 1).arg(root.pages.length)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                // Next page button
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    visible: root.currentPage < root.pages.length - 1
                    bottomLeftRadius: Appearance.rounding.full
                    topLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.verysmall
                    topRightRadius: Appearance.rounding.verysmall
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    onClicked: root.goToPage(root.currentPage + 1)
                    contentItem: MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Add page button
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    bottomLeftRadius: Appearance.rounding.verysmall
                    topLeftRadius: Appearance.rounding.verysmall
                    bottomRightRadius: Appearance.rounding.verysmall
                    topRightRadius: Appearance.rounding.verysmall
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: root.addPage()
                    contentItem: MaterialSymbol {
                        text: "add"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimary
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledToolTip {
                        text: Translation.tr("Add new page")
                    }
                }

                // Delete current page (only if >1 pages and current is empty)
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    visible: root.pages.length > 1
                    bottomLeftRadius: Appearance.rounding.verysmall
                    topLeftRadius: Appearance.rounding.verysmall
                    bottomRightRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    onClicked: root.removePage(root.currentPage)
                    contentItem: MaterialSymbol {
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnErrorContainer
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledToolTip {
                        text: Translation.tr("Remove current page")
                    }
                }
            }
        }

        // Separator between used and unused toggles in edit mode
        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        // Unused toggles (edit mode)
        FadeLoader {
            shown: root.editMode
            sourceComponent: GridLayout {
                id: unusedRows
                columns: root.columns
                columnSpacing: root.spacing
                rowSpacing: root.spacing

                Repeater {
                    model: root.columns
                    Item {
                        required property int index
                        Layout.row: 1000
                        Layout.column: index
                        Layout.columnSpan: 1
                        Layout.rowSpan: 1
                        Layout.preferredWidth: root.baseCellWidth
                        Layout.preferredHeight: 0
                        implicitWidth: root.baseCellWidth
                        implicitHeight: 0
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: root.unusedToggles
                        objectProp: "type"
                    }
                    delegate: AndroidToggleDelegateChooser {

                        editMode: root.editMode
                        baseCellWidth: root.baseCellWidth
                        baseCellHeight: root.baseCellHeight
                        spacing: root.spacing
                        isUnused: true
                        pageIndex: root.currentPage
                        gridColumns: root.columns
                        panel: root
                        gridRef: unusedRows

                        onOpenAudioOutputDialog: root.openAudioOutputDialog()
                        onOpenAudioInputDialog: root.openAudioInputDialog()
                        onOpenBluetoothDialog: root.openBluetoothDialog()
                        onOpenNightLightDialog: root.openNightLightDialog()
                        onOpenWifiDialog: root.openWifiDialog()
                        onOpenDarkModeDialog: root.openDarkModeDialog()
                        onOpenLocalSendDialog: root.openLocalSendDialog()
                        onOpenVpnDialog: root.openVpnDialog()
                        onOpenTailscaleDialog: root.openTailscaleDialog()
                        onOpenDnsOverTlsDialog: root.openDnsOverTlsDialog()
                        onOpenIdleInhibitorDialog: root.openIdleInhibitorDialog()
                        onOpenScreenShaderDialog: root.openScreenShaderDialog()
                    }
                }
            }
        }
    }

    // Keep flickable in sync with currentPage
    onCurrentPageChanged: {
        if (!flickable.moving) {
            snapAnimation.stop();
            snapAnimation.to = currentPage * flickable.width;
            snapAnimation.start();
        }
    }

    // Clamp currentPage when pages are removed
    onPagesChanged: {
        if (currentPage >= pages.length) {
            currentPage = Math.max(0, pages.length - 1);
        }
    }
}
