import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarDashboard.quickToggles.androidStyle
import "androidStyle/QuickToggleCatalog.js" as QuickToggleCatalog
import "androidStyle/QuickToggleLayout.js" as QuickToggleLayout

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    // Current page index
    property int currentPage: 0

    property int entranceTrigger: -1

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen && editController.active) {
                editController.cancel();
            }
        }
    }

    onEditModeChanged: {
        if (!root.editMode && editController.active)
            editController.cancel();
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.editMode && editController.active
        onActivated: editController.cancel()
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
    readonly property list<string> availableToggleTypes: QuickToggleCatalog.allTypes()
    function isToggleVisible(toggleType) {
        return true
    }
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns

    // Pages data — reads from Config and exposes the canonical in-memory shape.
    // The legacy `size` field is read only by the catalog normalizer and is not
    // returned to delegates.
    readonly property list<var> pages: {
        const cfg = Config.options.sidebar.quickToggles.android;
        if (!Config.ready)
            return [[]];
        if (!cfg.pages || cfg.pages.length === 0)
            return [[]];
        return QuickToggleCatalog.normalizePages(cfg.pages, root.columns, {
            warn: function(message) { console.warn(message); }
        });
    }

    QuickToggleEditController {
        id: editController
        config: Config.options.sidebar.quickToggles.android
        persistedPages: root.pages
        columns: root.columns
    }

    property alias editController: editController

    // The persisted page arrays are the delegate model. A gesture may change
    // preview geometry, but it must never reorder/retype this model while a
    // MouseArea owns the grab.
    readonly property list<var> displayPages: root.pages

    // Same-page reorder and resize get a live packed preview. Cross-page drag
    // keeps both pages stable until release, then commits one atomic move.
    readonly property list<var> geometryPages: {
        if (!editController.active)
            return root.pages;
        if (editController.mode === "resize"
                || editController.targetPage === editController.sourcePage)
            return editController.draftPages;
        return root.pages;
    }

    // All used toggle types across all pages
    readonly property list<string> allUsedTypes: {
        var types = [];
        for (var p = 0; p < root.pages.length; p++) {
            var page = root.pages[p];
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
        const types = availableToggleTypes.filter(type => root.isToggleVisible(type) && !allUsedTypes.includes(type));
        return types.map(type => QuickToggleCatalog.item(type, type, undefined, undefined, root.columns));
    }

    readonly property var packedUnusedToggles: QuickToggleLayout.pack(root.unusedToggles, root.columns)
    readonly property list<var> positionedUnusedToggles: QuickToggleLayout.positionedItems(
        root.unusedToggles,
        root.packedUnusedToggles,
        root.baseCellWidth,
        root.baseCellHeight,
        root.spacing
    )

    // One packer owns both visible geometry and height. Delegates are decorated
    // by stable id below; their model order remains the persisted order.
    readonly property list<var> packedPages: {
        var result = [];
        for (var i = 0; i < geometryPages.length; i++)
            result.push(QuickToggleLayout.pack(geometryPages[i] || [], root.columns));
        return result;
    }

    readonly property list<var> positionedPages: {
        var result = [];
        for (var i = 0; i < root.pages.length; i++) {
            result.push(QuickToggleLayout.positionedItems(
                root.pages[i] || [],
                root.packedPages[i] || { rowsUsed: 0, items: [] },
                root.baseCellWidth,
                root.baseCellHeight,
                root.spacing
            ));
        }
        return result;
    }

    // Calculate height for a specific page
    function pageHeight(pageIndex) {
        if (pageIndex < 0 || pageIndex >= root.pages.length)
            return baseCellHeight + 8;
        var packedPage = packedPages[pageIndex];
        var rows = packedPage ? packedPage.rowsUsed : 0;
        return Math.max(baseCellHeight, rows * (baseCellHeight + spacing) - spacing) + 8;
    }

    // Dynamic height based on current page + page indicators
    readonly property real currentContentHeight: pageHeight(currentPage) + (editMode ? 14 : 0)

    // How tall the panel is allowed to get, handed down by whoever hosts it.
    // Negative means unconstrained, which is what a host that does not measure
    // itself gets. Everything above the tray is fixed, so the tray gets what is
    // left of the budget and scrolls the rest.
    property real maxContentHeight: -1
    // Every unused toggle wears an add badge that hangs 6px past its own top and
    // right edge (EditableQuickToggleItem). Outside a clip that just draws over
    // the panel padding; inside one it gets sliced, so the tray has to hand those
    // 6px back on both sides.
    readonly property real trayBadgeOverhang: 6
    readonly property real trayMaxHeight: {
        if (root.maxContentHeight <= 0)
            return -1;
        return Math.max(root.baseCellHeight,
            root.maxContentHeight - unusedTogglesLoader.y - root.padding * 2);
    }

    implicitHeight: contentItem.implicitHeight + root.padding * 2

    // Page management functions
    function addPage() {
        if (editController.addPage())
            currentPage = editController.targetPage;
    }

    function removePage(pageIndex) {
        if (!editController.removePage(pageIndex))
            return;
        var remaining = Config.options.sidebar.quickToggles.android.pages.length;
        currentPage = Math.min(currentPage, Math.max(0, remaining - 1));
    }

    function goToPage(pageIndex) {
        if (pageIndex < 0 || pageIndex >= displayPages.length)
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
            if (root.dragScrollPendingPage >= 0 && root.dragScrollPendingPage < root.displayPages.length) {
                root.currentPage = root.dragScrollPendingPage;
                if (root.editController.active)
                    root.editController.setTargetPage(root.dragScrollPendingPage);
            }
            root.dragScrollPendingPage = -1;
        }
    }

    function cancelDragScroll() {
        dragScrollTimer.stop();
        dragScrollPendingPage = -1;
    }

    function handleDragScrollRequest(absX, dragButton) {
        var newPage = -1;
        if (absX < dragScrollEdgeThreshold && currentPage > 0) {
            newPage = currentPage - 1;
        } else if (absX > root.width - dragScrollEdgeThreshold && currentPage < displayPages.length - 1) {
            newPage = currentPage + 1;
        }

        if (newPage >= 0 && newPage !== dragScrollPendingPage) {
            dragScrollPendingPage = newPage;
            dragScrollTimer.restart();
        } else if (newPage < 0) {
            // Back in safe zone — reset pending
            dragScrollPendingPage = -1;
            dragScrollTimer.stop();
        }
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

            StableQuickToggleModel {
                id: fixedSlidersModel
                sourceValues: {
                    var list = [];
                    const cfg = Config.options.sidebar.quickSliders;
                    if (cfg.enable) {
                        if (cfg.showBrightness)
                            list.push(QuickToggleCatalog.item("brightnessSlider", "brightnessSlider", root.columns, 1, root.columns));
                        if (cfg.showGamma)
                            list.push(QuickToggleCatalog.item("gammaSlider", "gammaSlider", root.columns, 1, root.columns));
                        if (cfg.showVolume)
                            list.push(QuickToggleCatalog.item("volumeSlider", "volumeSlider", root.columns, 1, root.columns));
                        if (cfg.showMic)
                            list.push(QuickToggleCatalog.item("micSlider", "micSlider", root.columns, 1, root.columns));
                    }
                    return list;
                }
            }

            Repeater {
                id: fixedSlidersRepeater
                model: fixedSlidersModel
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
                    onOpenModesDialog: root.openModesDialog()
                }
            }
        }

        // Horizontal paging container
        Item {
            id: flickableContainer
            width: parent.width
            height: root.currentContentHeight

            clip: true

            Flickable {
                id: flickable
                anchors.fill: parent
                contentWidth: width * root.displayPages.length
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: !root.editMode

                // Snap to page on release
                onMovementEnded: {
                    var targetPage = Math.round(contentX / width);
                    targetPage = Math.max(0, Math.min(targetPage, root.displayPages.length - 1));
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
                            if (wheelEvent.angleDelta.x < 0 && root.currentPage < root.displayPages.length - 1) {
                                root.goToPage(root.currentPage + 1);
                            } else if (wheelEvent.angleDelta.x > 0 && root.currentPage > 0) {
                                root.goToPage(root.currentPage - 1);
                            }
                        } else {
                            // Vertical scroll → map to horizontal paging
                            if (wheelEvent.angleDelta.y < 0 && root.currentPage < root.displayPages.length - 1) {
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
                        model: root.displayPages.length

                        Item {
                            id: pageContainer
                            required property int index
                            width: flickable.width
                            height: flickable.height

                            // Show only current page content as visible when current
                            property bool isCurrent: root.currentPage === index
                            property list<var> pageToggles: root.positionedPages[index] || []

                            Item {
                                id: pageContentCanvas
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                implicitHeight: root.pageHeight(pageContainer.index)
                                height: implicitHeight
                                objectName: "pageContent_" + pageContainer.index

                                StableQuickToggleModel {
                                    id: pageToggleModel
                                    sourceValues: pageContainer.pageToggles
                                }

                                Repeater {
                                    id: gridRepeater
                                    model: pageToggleModel
                                    delegate: AndroidToggleDelegateChooser {

                                        editMode: root.editMode
                                        baseCellWidth: root.baseCellWidth
                                        baseCellHeight: root.baseCellHeight
                                        spacing: root.spacing
                                        isUnused: false
                                        pageIndex: pageContainer.index
                                        gridColumns: root.columns
                                        panel: root
                                        gridRef: pageContentCanvas
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
                                        onOpenModesDialog: root.openModesDialog()
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
            visible: root.displayPages.length > 1

            Repeater {
                model: root.displayPages.length
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
            fade: false
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
                            text: Translation.tr("Page %1 / %2").arg(root.currentPage + 1).arg(root.displayPages.length)
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
                    visible: root.currentPage < root.displayPages.length - 1
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
                    visible: root.displayPages.length > 1
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
            fade: false
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
            id: unusedTogglesLoader
            shown: root.editMode
            fade: false
            anchors {
                left: parent.left
                right: parent.right
                // Reach into the panel's own padding so the rightmost badges
                // are inside the clip instead of against it.
                rightMargin: -root.padding
            }
            sourceComponent: Item {
                id: trayViewport
                implicitHeight: trayFlickable.implicitHeight

                StyledFlickable {
                    id: trayFlickable
                    anchors.fill: parent
                    readonly property real fullHeight: unusedCanvas.implicitHeight + root.trayBadgeOverhang
                    implicitHeight: root.trayMaxHeight < 0 ? fullHeight
                        : Math.min(fullHeight, root.trayMaxHeight)
                    contentWidth: width
                    contentHeight: fullHeight
                    clip: true

                    Item {
                        id: unusedCanvas
                        y: root.trayBadgeOverhang
                        width: trayFlickable.width
                        implicitHeight: Math.max(0, root.packedUnusedToggles.rowsUsed
                            * (root.baseCellHeight + root.spacing) - root.spacing)
                        height: implicitHeight

                        StableQuickToggleModel {
                            id: unusedToggleModel
                            sourceValues: root.positionedUnusedToggles
                        }

                        Repeater {
                            model: unusedToggleModel
                            delegate: AndroidToggleDelegateChooser {

                                editMode: root.editMode
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                                isUnused: true
                                pageIndex: root.currentPage
                                gridColumns: root.columns
                                panel: root
                                gridRef: unusedCanvas

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
                                onOpenModesDialog: root.openModesDialog()
                            }
                        }
                    }
                }

                ScrollEdgeFade {
                    target: trayFlickable
                    color: root.color
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
