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

    // Sizes
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns));
        return availableWidth / root.columns;
    }
    readonly property real baseCellHeight: 56

    // Toggles config
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile", "musicRecognition", "antiFlashbang", "soundcoreAnc"]
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

        const first = cfg.pages[0];
        // Detect format: if first element has a `type` property, it's the old flat
        // toggle list (legacy `toggles` renamed to `pages`). Wrap in a single page.
        // Otherwise it's the new pages-of-arrays format.
        if (first && typeof first === "object" && first.type !== undefined) {
            // Old flat format — wrap in single page
            return [cfg.pages];
        }

        // New format: pages is array of arrays
        return cfg.pages;
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
            if (!page) continue;
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
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0;
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i])
                continue;
            if (totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(togglesList[i]);
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) {
            rows.push(row);
        }
        return rows;
    }

    // Calculate height for a specific page
    function pageHeight(pageIndex) {
        if (pageIndex < 0 || pageIndex >= pages.length)
            return baseCellHeight;
        var pageToggles = pages[pageIndex] || [];
        var toggleRows = toggleRowsForList(pageToggles);
        return Math.max(baseCellHeight, toggleRows.length * (baseCellHeight + spacing) - spacing);
    }

    // Dynamic height based on current page + page indicators
    readonly property real currentContentHeight: pageHeight(currentPage)
    readonly property real pageIndicatorHeight: pages.length > 1 ? 20 : 0

    implicitHeight: {
        if (editMode)
            return contentItem.implicitHeight + root.padding * 2;
        return currentContentHeight + pageIndicatorHeight + root.padding * 2;
    }
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

    // Page management functions
    function addPage() {
        var targetPage;
        mutatePages(function(p) {
            p.push([]);
            targetPage = p.length - 1;
        });
        currentPage = targetPage;
    }

    function removePage(pageIndex) {
        if (pages.length <= 1) return; // Never remove last page
        if (pageIndex < 0 || pageIndex >= pages.length) return;

        mutatePages(function(p) {
            p.splice(pageIndex, 1);
        });

        if (currentPage >= pages.length)
            currentPage = Math.max(0, pages.length - 1);
    }

    function goToPage(pageIndex) {
        if (pageIndex < 0 || pageIndex >= pages.length) return;
        currentPage = pageIndex;
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
                    onWheel: function(wheelEvent) {
                        if (root.editMode) {
                            wheelEvent.accepted = false;
                            return;
                        }
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
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
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
                            property list<var> pageToggleRows: root.toggleRowsForList(pageToggles)

                            Column {
                                id: pageContentColumn
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                spacing: root.spacing
                                objectName: "pageContent_" + pageContainer.index

                                Repeater {
                                    id: rowRepeater
                                    model: ScriptModel {
                                        values: Array(pageContainer.pageToggleRows.length)
                                    }
                                    delegate: ButtonGroup {
                                        id: toggleRow
                                        required property int index
                                        property var modelData: pageContainer.pageToggleRows[index]
                                        property int startingIndex: {
                                            const rows = pageContainer.pageToggleRows;
                                            let sum = 0;
                                            for (let i = 0; i < index; i++) {
                                                sum += rows[i].length;
                                            }
                                            return sum;
                                        }
                                        spacing: root.spacing

                                        Repeater {
                                            model: ScriptModel {
                                                values: toggleRow?.modelData ?? []
                                                objectProp: "type"
                                            }
                                            delegate: AndroidToggleDelegateChooser {
                                                startingIndex: toggleRow.startingIndex
                                                editMode: root.editMode
                                                baseCellWidth: root.baseCellWidth
                                                baseCellHeight: root.baseCellHeight
                                                spacing: root.spacing
                                                pageIndex: pageContainer.index
                                                onOpenAudioOutputDialog: root.openAudioOutputDialog()
                                                onOpenAudioInputDialog: root.openAudioInputDialog()
                                                onOpenBluetoothDialog: root.openBluetoothDialog()
                                                onOpenNightLightDialog: root.openNightLightDialog()
                                                onOpenWifiDialog: root.openWifiDialog()
                                                onOpenDarkModeDialog: root.openDarkModeDialog()
                                            }
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
            sourceComponent: Column {
                id: unusedRows
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: Array(root.unusedToggleRows.length)
                    }
                    delegate: ButtonGroup {
                        id: unusedToggleRow
                        required property int index
                        property var modelData: root.unusedToggleRows[index]
                        spacing: root.spacing

                        Repeater {
                            model: ScriptModel {
                                values: unusedToggleRow?.modelData ?? []
                                objectProp: "type"
                            }
                            delegate: AndroidToggleDelegateChooser {
                                startingIndex: -1
                                editMode: root.editMode
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                                pageIndex: root.currentPage
                            }
                        }
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
