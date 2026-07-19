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
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "screenRecord", "colorPicker", "videoEditor", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile", "musicRecognition", "antiFlashbang", "soundcoreAnc", "systemSounds", "localSend", "mediaWidget", "volumeSlider", "micSlider", "brightnessSlider", "gammaSlider", "keyboardBacklight"]
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns

    // Pages data — reads from Config.
    // The stored format is: pages = [[toggle, toggle, ...], [toggle, ...], ...]
    // Each inner array is one page. Each toggle is {type: string, size: int}.
    readonly property list<var> pages: {
        const cfg = Config.options.sidebar.quickToggles.android;
        if (!Config.ready)
            return [[]];
        if (!cfg.pages || cfg.pages.length === 0)
            return [[]];

        var rawPages = cfg.pages;
        const first = rawPages[0];
        // Detect format: if first element has a `type` property, it's the old flat
        // toggle list (legacy `toggles` renamed to `pages`). Wrap in a single page.
        // Otherwise it's the new pages-of-arrays format.
        if (first && typeof first === "object" && first.type !== undefined) {
            // Old flat format — wrap in single page
            rawPages = [cfg.pages];
        }

        const useThreeWay = Config.options.sidebar.quickToggles.useThreeWaySliders ?? false;
        if (!useThreeWay)
            return rawPages;

        var mappedPages = [];
        for (var p = 0; p < rawPages.length; p++) {
            var page = rawPages[p];
            if (!page) {
                mappedPages.push([]);
                continue;
            }
            var newPage = [];
            for (var i = 0; i < page.length; i++) {
                var item = page[i];
                if (item && (item.type === "soundcoreAnc" || item.type === "powerProfile" || item.type === "keyboardBacklight")) {
                    var newItem = {};
                    for (var key in item) {
                        newItem[key] = item[key];
                    }
                    newItem.size = 2;
                    newItem.sizeW = 2;
                    newPage.push(newItem);
                } else {
                    newPage.push(item);
                }
            }
            mappedPages.push(newPage);
        }
        return mappedPages;
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

    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !allUsedTypes.includes(type));
        return types.map(type => {
            return {
                type: type,
                size: 1
            };
        });
    }
    function getGridRowsNeeded(togglesList) {
        var grid = [];
        var rowsNeeded = 0;
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i])
                continue;
            var t = togglesList[i];
            var w = t.sizeW ?? t.size ?? 1;
            var h = t.sizeH ?? 1;
            w = Math.min(w, columns); // sanitize

            var startX = -1, startY = -1;
            for (var y = 0; startX === -1; y++) {
                for (var x = 0; x <= columns - w; x++) {
                    var conflict = false;
                    for (var dy = 0; dy < h; dy++) {
                        for (var dx = 0; dx < w; dx++) {
                            if (grid[y + dy] && grid[y + dy][x + dx]) {
                                conflict = true;
                                break;
                            }
                        }
                        if (conflict)
                            break;
                    }
                    if (!conflict) {
                        startX = x;
                        startY = y;
                        break;
                    }
                }
            }
            for (var dY = 0; dY < h; dY++) {
                if (!grid[startY + dY])
                    grid[startY + dY] = [];
                for (var dX = 0; dX < w; dX++) {
                    grid[startY + dY][startX + dX] = true;
                }
            }
            rowsNeeded = Math.max(rowsNeeded, startY + h);
        }
        return rowsNeeded;
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

    // Helper: deep-clone pages, run mutator, reassign to Config
    // This is REQUIRED because list<var> returns a copy, not a reference.
    function mutatePages(mutatorFn) {
        var cloned = JSON.parse(JSON.stringify(Config.options.sidebar.quickToggles.android.pages));
        mutatorFn(cloned);
        Config.options.sidebar.quickToggles.android.pages = cloned;
    }

    function resolveLayoutConflicts(pageIndex, gridColumns) {
        mutatePages(function (pages) {
            if (pageIndex < 0 || pageIndex >= pages.length)
                return;
            var page = pages[pageIndex];
            if (!page || page.length === 0)
                return;

            // Sort by current position to maintain order
            var sorted = [];
            for (var i = 0; i < page.length; i++) {
                sorted.push({
                    idx: i,
                    type: page[i].type,
                    sizeW: page[i].sizeW ?? page[i].size ?? 1,
                    sizeH: page[i].sizeH ?? 1
                });
            }

            // Simple grid placement simulation
            var grid = [];
            var newOrder = [];

            for (var j = 0; j < sorted.length; j++) {
                var item = sorted[j];
                var placed = false;

                for (var row = 0; row < 20 && !placed; row++) {
                    for (var col = 0; col <= gridColumns - item.sizeW && !placed; col++) {
                        var fits = true;

                        for (var h = 0; h < item.sizeH && fits; h++) {
                            for (var w = 0; w < item.sizeW && fits; w++) {
                                var cell = (row + h) * gridColumns + (col + w);
                                if (grid.indexOf(cell) !== -1) {
                                    fits = false;
                                }
                            }
                        }

                        if (fits) {
                            for (var h2 = 0; h2 < item.sizeH; h2++) {
                                for (var w2 = 0; w2 < item.sizeW; w2++) {
                                    var cell2 = (row + h2) * gridColumns + (col + w2);
                                    grid.push(cell2);
                                }
                            }
                            newOrder.push(item);
                            placed = true;
                        }
                    }
                }

                if (!placed) {
                    // Fallback: place at next available single cell
                    newOrder.push({
                        type: item.type,
                        sizeW: 1,
                        sizeH: 1
                    });
                }
            }

            // Rebuild page array
            page.length = 0;
            for (var k = 0; k < newOrder.length; k++) {
                page.push({
                    type: newOrder[k].type,
                    sizeW: newOrder[k].sizeW,
                    sizeH: newOrder[k].sizeH,
                    size: newOrder[k].sizeW
                });
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
            if (!targetPage)
                pages[toPage] = [];
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

                                GridLayout {
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
                            iconSize: Appearance.font.pixelSize.medium
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
