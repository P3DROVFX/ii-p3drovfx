pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Home Timeline page:
 *  - Editorial M3 Expressive header with a large cropped MaterialShape photo
 *    showcase in the top-right (rotates every 4s through favorites or random
 *    home photos; click to open in viewer).
 *  - Virtualized vertical day-grouped timeline ListView whose vertical track
 *    and active day marker follow scroll progress.
 *  - Symmetric circular Back-to-Top FAB in the bottom-left when scrolled down.
 */
Item {
    id: root

    required property var store
    property real layoutWidth: width

    // Flatten homeItems into day-grouped rows for the virtualized ListView.
    readonly property var timelineRows: {
        const items = store.homeItems ?? [];
        const cols = store.gridColumns;
        const rows = [];
        let i = 0;
        let groupIndex = 0;
        while (i < items.length) {
            const key = store.dayKey(items[i].mtime);
            let j = i;
            while (j < items.length && store.dayKey(items[j].mtime) === key)
                j++;
            const count = j - i;
            const d = new Date(items[i].mtime);
            const dayStr = store.pad2(d.getDate());
            const monthStr = store.monthShortName(d.getMonth());
            const relStr = store.relDayLabel(items[i].mtime);
            const rowCount = Math.ceil(count / cols);
            for (let r = 0; r < rowCount; r++) {
                const slice = items.slice(i + r * cols, Math.min(j, i + (r + 1) * cols));
                rows.push({
                    groupKey: key,
                    groupIndex: groupIndex,
                    isFirstRowOfGroup: r === 0,
                    isLastRowOfGroup: r === rowCount - 1,
                    dayStr: dayStr,
                    monthStr: monthStr,
                    relStr: relStr,
                    groupCount: count,
                    cells: slice
                });
            }
            groupIndex++;
            i = j;
        }
        return rows;
    }

    readonly property var enabledRoots: store.folders.filter(f => f.on).map(f => f.name)

    readonly property string sourcesSubtitle: {
        const r = root.enabledRoots;
        if (r.length === 0)
            return Translation.tr("No folders selected for the timeline.");
        const joined = r.length > 1
            ? `${r.slice(0, -1).join(", ")} ${Translation.tr("and")} ${r[r.length - 1]}`
            : r[0];
        return store.includeSub
            ? Translation.tr("From %1, including subfolders.").arg(joined)
            : Translation.tr("From %1, top-level only.").arg(joined);
    }

    readonly property var markerShapes: [
        MaterialShape.Shape.Cookie6Sided,
        MaterialShape.Shape.Clover4Leaf,
        MaterialShape.Shape.Flower,
        MaterialShape.Shape.SoftBurst
    ]

    // ── Hero MaterialShape rotating photo showcase (favorites or random photos) ─
    readonly property var showcasePool: {
        const allPhotos = (store.timelineAllItems ?? []).filter(it => it.type === "photo");
        if (allPhotos.length === 0)
            return [];
        const favPhotos = allPhotos.filter(it => store.isFav(it.path));
        return favPhotos.length > 0 ? favPhotos : allPhotos;
    }

    property int showcaseIdx: 0
    property int showcaseShapeIdx: 0
    readonly property var showcaseShapes: [
        MaterialShape.Shape.Cookie12Sided,
        MaterialShape.Shape.Flower,
        MaterialShape.Shape.SoftBurst,
        MaterialShape.Shape.Cookie9Sided
    ]
    readonly property var showcaseItem: {
        const pool = root.showcasePool;
        if (pool.length === 0)
            return null;
        return pool[root.showcaseIdx % pool.length];
    }

    Timer {
        id: showcaseTimer
        interval: 9000
        repeat: true
        running: root.visible && root.showcasePool.length > 1 && !store.viewerOpen
        onTriggered: {
            const len = root.showcasePool.length;
            if (len <= 1)
                return;
            let next = Math.floor(Math.random() * len);
            if (next === root.showcaseIdx % len)
                next = (next + 1) % len;
            root.showcaseIdx = next;
            root.showcaseShapeIdx = (root.showcaseShapeIdx + 1) % root.showcaseShapes.length;
        }
    }

    // Active day index that follows the scroll position
    readonly property int activeGroupIndex: {
        if (root.timelineRows.length === 0)
            return 0;
        const probeY = timelineList.contentY + 220;
        const rowIdx = timelineList.indexAt(timelineList.leftMargin + 40, probeY);
        if (rowIdx >= 0 && rowIdx < root.timelineRows.length)
            return root.timelineRows[rowIdx].groupIndex;
        return 0;
    }

    NumberAnimation {
        id: scrollTopAnim
        target: timelineList
        property: "contentY"
        to: 0
        duration: 420
        easing.type: Easing.OutCubic
    }

    ListView {
        id: timelineList
        anchors.fill: parent
        clip: true
        cacheBuffer: 160
        flickDeceleration: 2200
        maximumFlickVelocity: 7200
        topMargin: 0
        bottomMargin: 120
        leftMargin: 32
        rightMargin: 32
        model: root.timelineRows

        // Responsive mouse wheel boost (~2.3x faster scroll per notch)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse
            onWheel: event => {
                if (event.angleDelta.y === 0)
                    return;
                const step = -event.angleDelta.y * 0.85;
                const maxY = Math.max(0, timelineList.contentHeight - timelineList.height + timelineList.bottomMargin);
                timelineList.contentY = Math.max(0, Math.min(maxY, timelineList.contentY + step));
                event.accepted = true;
            }
        }

        // Helper: find media path at (vx, vy) in timelineList viewport coordinates
        function mediaPathAt(vx, vy): string {
            const cy = vy + timelineList.contentY;
            const rowIdx = timelineList.indexAt(timelineList.leftMargin + 40, cy);
            if (rowIdx < 0 || rowIdx >= root.timelineRows.length)
                return "";
            const rowData = root.timelineRows[rowIdx];
            if (!rowData || !rowData.cells || rowData.cells.length === 0)
                return "";
            const railW = root.width < 880 ? 118 : 156;
            const gap = 8;
            const cols = store.gridColumns;
            const contentW = timelineList.width - timelineList.leftMargin - timelineList.rightMargin;
            const gridStartX = timelineList.leftMargin + railW + 18;
            const gridAreaW = Math.max(200, contentW - railW - 18);
            const tileSize = Math.max(72, Math.floor((gridAreaW - gap * (cols - 1)) / cols));
            const relX = vx - gridStartX;
            if (relX < 0)
                return "";
            const col = Math.floor(relX / (tileSize + gap));
            if (col < 0 || col >= rowData.cells.length)
                return "";
            return String(rowData.cells[col].path ?? "");
        }

        // Click-and-drag swipe multi-selection overlay (active while in selectionMode)
        MouseArea {
            id: homeDragSelectArea
            anchors.fill: parent
            z: 8
            visible: store.selectionMode
            preventStealing: true
            property real dragY: -1

            Timer {
                interval: 24
                repeat: true
                running: homeDragSelectArea.pressed && (homeDragSelectArea.dragY < 56 || homeDragSelectArea.dragY > timelineList.height - 56)
                onTriggered: {
                    const delta = homeDragSelectArea.dragY < 56 ? -18 : 18;
                    const maxY = Math.max(0, timelineList.contentHeight - timelineList.height + timelineList.bottomMargin);
                    timelineList.contentY = Math.max(0, Math.min(maxY, timelineList.contentY + delta));
                }
            }

            onPressed: mouse => {
                dragY = mouse.y;
                const p = timelineList.mediaPathAt(mouse.x, mouse.y);
                if (p)
                    store.startDragSelect(p);
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                dragY = mouse.y;
                const p = timelineList.mediaPathAt(mouse.x, mouse.y);
                if (p)
                    store.applyDragSelect(p);
            }
            onReleased: store.endDragSelect()
            onCanceled: store.endDragSelect()
        }

        // Editorial header (scrolled naturally with the timeline)
        header: Item {
            id: headerBox
            width: timelineList.width - timelineList.leftMargin - timelineList.rightMargin
            height: Math.max(headerLeftCol.implicitHeight + 52, 268)

            // Right: Large cropped MaterialShape photo showcase (image shape only, no background blob)
            Item {
                id: showcaseContainer
                visible: root.showcaseItem !== null && root.width >= 780
                anchors.right: parent.right
                anchors.rightMargin: -32   // bleed flush to the right edge of pageContainer
                anchors.top: parent.top
                width: Math.min(480, parent.width * 0.44)
                height: parent.height
                clip: true

                // Main large cropped MaterialShape with masked rotating photo
                Item {
                    id: heroMaskHost
                    anchors.right: parent.right
                    anchors.rightMargin: -48
                    anchors.top: parent.top
                    anchors.topMargin: -76
                    width: 440
                    height: 440

                    // Mask shape (hidden, rendered into MultiEffect)
                    MaterialShape {
                        id: heroShapeMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        shape: root.showcaseShapes[root.showcaseShapeIdx]
                        color: "#ffffff"
                    }

                    // Photo masked by heroShapeMask (single masked item in the whole app; unloads when hidden)
                    Image {
                        id: heroPhoto
                        anchors.fill: parent
                        source: (root.visible && !store.viewerOpen && root.showcaseItem) ? ("file://" + root.showcaseItem.path) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        autoTransform: true
                        sourceSize: Qt.size(440, 440)
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: heroPhoto
                        maskEnabled: true
                        maskSource: heroShapeMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.5
                        opacity: heroPhoto.status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
                    }

                    // Subtle hover & click to open showcase photo in viewer
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.showcaseItem)
                                store.openLocalViewer(root.showcaseItem.path, store.homeItems);
                        }
                    }
                }
            }

            // Left: Date caption, expressive title, subtitle, filter chips
            ColumnLayout {
                id: headerLeftCol
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 28
                width: showcaseContainer.visible ? (parent.width - showcaseContainer.width + 16) : parent.width
                spacing: 8

                StyledText {
                    text: store.todayCaption().toUpperCase()
                    font.family: Appearance.font.family.main
                    font.pixelSize: 12
                    font.letterSpacing: 0.9
                    font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    textFormat: Text.RichText
                    text: Translation.tr("Everything you <span style='color:%1; font-style:italic'>kept</span>,<br>in order.")
                        .arg(Appearance.colors.colPrimary)
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.width < 940 ? 40 : 54
                    lineHeight: 0.96
                    font.variableAxes: ({ "wght": 380, "wdth": 116, "ROND": 100 })
                    color: Appearance.colors.colOnSurface
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.sourcesSubtitle
                    font.family: Appearance.font.family.main
                    font.pixelSize: 15
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }

                // Filter chips
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "all",   label: Translation.tr("All") },
                            { id: "photo", label: Translation.tr("Photos") },
                            { id: "video", label: Translation.tr("Videos") },
                            { id: "fav",   label: Translation.tr("Favorites") }
                        ]

                        delegate: RippleButton {
                            id: chip
                            required property var modelData
                            readonly property bool selected: store.filter === modelData.id
                            readonly property bool chipDisabled: modelData.id === "video" && !store.showVideos

                            enabled: !chipDisabled
                            opacity: chipDisabled ? 0.38 : 1.0
                            implicitHeight: 38
                            leftPadding: 14
                            rightPadding: 16
                            buttonRadius: selected ? 19 : Appearance.rounding.small
                            colBackground: selected ? Appearance.colors.colSecondaryContainer : "transparent"
                            colBackgroundHover: selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                            onClicked: store.filter = modelData.id

                            Behavior on buttonRadius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.buttonRadius
                                color: "transparent"
                                border.width: chip.selected ? 0 : 1
                                border.color: Appearance.colors.colOutlineVariant
                            }

                            contentItem: RowLayout {
                                spacing: 6
                                MaterialSymbol {
                                    visible: chip.selected
                                    text: "check"
                                    iconSize: 17
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    text: chip.modelData.label
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 14
                                    font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
                                    color: chip.selected
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }

        // Virtualized row delegate: left scroll-reactive timeline rail + right media row
        delegate: Item {
            id: rowItem
            required property var modelData
            required property int index

            readonly property int railWidth: root.width < 880 ? 118 : 156
            readonly property int gap: 8
            readonly property int cols: store.gridColumns
            readonly property real gridAreaW: Math.max(200, width - railWidth - 18)
            readonly property real tileSize: Math.max(72, Math.floor((gridAreaW - gap * (cols - 1)) / cols))
            readonly property int bottomPad: modelData.isLastRowOfGroup ? 32 : gap
            readonly property bool isActiveDay: modelData.groupIndex === root.activeGroupIndex

            // How much of this row's vertical track segment is filled by the current scroll position
            readonly property real scrollLeadY: timelineList.contentY + timelineList.height * 0.34
            readonly property real filledHeight: Math.max(0, Math.min(height, scrollLeadY - y))

            width: timelineList.width - timelineList.leftMargin - timelineList.rightMargin
            height: Math.max(modelData.isFirstRowOfGroup ? 132 : 0, tileSize) + bottomPad

            // Continuous vertical timeline track background
            Rectangle {
                x: 13
                y: 0
                width: 4
                height: parent.height
                radius: 2
                color: Appearance.colors.colLayer2
            }

            // Scroll-following vertical progress fill
            Rectangle {
                x: 13
                y: 0
                width: 4
                height: rowItem.filledHeight
                radius: 2
                color: Appearance.colors.colPrimary
            }

            // Left day marker (shown on first row of each day group)
            Item {
                visible: rowItem.modelData.isFirstRowOfGroup
                x: 0
                y: 0
                width: rowItem.railWidth
                height: 132

                MaterialShape {
                    x: 0
                    y: 2
                    width: 30
                    height: 30
                    shape: rowItem.isActiveDay
                        ? MaterialShape.Shape.Sunny
                        : root.markerShapes[rowItem.modelData.groupIndex % root.markerShapes.length]
                    color: rowItem.isActiveDay
                        ? Appearance.colors.colPrimary
                        : Appearance.m3colors.m3surfaceContainerHighest

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: rowItem.isActiveDay ? "star" : "circle"
                        fill: 1
                        iconSize: rowItem.isActiveDay ? 15 : 9
                        color: rowItem.isActiveDay
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSurfaceVariant
                    }
                }

                ColumnLayout {
                    x: 42
                    y: 0
                    width: parent.width - 42
                    spacing: 2

                    StyledText {
                        text: rowItem.modelData.dayStr
                        font.family: Appearance.font.family.main
                        font.pixelSize: root.width < 880 ? 52 : 68
                        lineHeight: 0.82
                        font.variableAxes: rowItem.isActiveDay
                            ? ({ "wght": 760, "wdth": 36, "ROND": 100 })
                            : ({ "wght": 540, "wdth": 36, "ROND": 100 })
                        color: rowItem.isActiveDay
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: rowItem.modelData.monthStr
                        font.family: Appearance.font.family.main
                        font.pixelSize: 16
                        font.letterSpacing: 1.8
                        font.variableAxes: ({ "wght": 760, "wdth": 120, "ROND": 100 })
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: rowItem.modelData.relStr
                        font.family: Appearance.font.family.main
                        font.pixelSize: 15
                        font.italic: true
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: rowItem.modelData.groupCount === 1
                            ? Translation.tr("1 item")
                            : Translation.tr("%1 items").arg(rowItem.modelData.groupCount)
                        font.family: Appearance.font.family.main
                        font.pixelSize: 12
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Right media tiles row
            Row {
                x: rowItem.railWidth + 18
                y: 0
                spacing: rowItem.gap

                Repeater {
                    model: rowItem.modelData.cells

                    delegate: GalleryMediaTile {
                        id: homeTile
                        required property var modelData
                        width: rowItem.tileSize
                        height: rowItem.tileSize
                        itemData: modelData
                        store: root.store
                        isFavorite: root.store.isFav(modelData.path)
                        selectionMode: root.store.selectionMode
                        selected: root.store.isSelected(modelData.path)
                        videoMetaRev: root.store.videoMetaRev
                        onToggleSelectRequested: root.store.toggleSelect(modelData.path)
                        onClicked: {
                            const pt = homeTile.mapToItem(null, 0, 0);
                            root.store.openLocalViewer(modelData.path, root.store.homeItems, {
                                x: pt.x, y: pt.y, w: homeTile.width, h: homeTile.height,
                                thumb: homeTile.thumbUrl
                            });
                        }
                    }
                }
            }
        }

        // Empty / loading states
        footer: Item {
            width: timelineList.width - timelineList.leftMargin - timelineList.rightMargin
            height: (root.timelineRows.length === 0) ? 320 : 0
            visible: root.timelineRows.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                width: Math.min(420, parent.width - 32)

                MaterialShape {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 96
                    implicitHeight: 96
                    shape: MaterialShape.Shape.SoftBurst
                    color: Appearance.colors.colSecondaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: store.scanning
                            ? "hourglass_top"
                            : (root.enabledRoots.length === 0
                                ? "folder_off"
                                : (store.query.trim().length > 0
                                    ? "search_off"
                                    : (store.filter === "fav" ? "heart_plus" : "photo_library")))
                        iconSize: 40
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: store.scanning
                        ? Translation.tr("Scanning your folders…")
                        : (root.enabledRoots.length === 0
                            ? Translation.tr("Choose your Home folders")
                            : (store.query.trim().length > 0
                                ? Translation.tr("Nothing for \"%1\"").arg(store.query.trim())
                                : (store.filter === "fav"
                                    ? Translation.tr("No favorites yet")
                                    : Translation.tr("Nothing to show here"))))
                    font.family: Appearance.font.family.main
                    font.pixelSize: 24
                    font.variableAxes: ({ "wght": 600, "wdth": 110, "ROND": 100 })
                    color: Appearance.colors.colOnSurface
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: store.scanning
                        ? Translation.tr("Looking for photos and videos in your library.")
                        : (root.enabledRoots.length === 0
                            ? Translation.tr("Enable folders in Settings to show them in the timeline.")
                            : (store.query.trim().length > 0
                                ? Translation.tr("Try searching by month, folder name, or file name.")
                                : (store.filter === "fav"
                                    ? Translation.tr("Open any photo or video and tap the heart to keep it here.")
                                    : Translation.tr("Add folders with photos or videos to populate your gallery."))))
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }

                RippleButton {
                    visible: !store.scanning
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    implicitHeight: 44
                    leftPadding: 22
                    rightPadding: 22
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: {
                        if (root.enabledRoots.length === 0) {
                            store.activeTab = "settings";
                        } else if (store.query.trim().length > 0) {
                            store.query = "";
                        } else if (store.filter !== "all") {
                            store.filter = "all";
                        } else {
                            store.addSheetOpen = true;
                        }
                    }
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: root.enabledRoots.length === 0
                            ? Translation.tr("Open settings")
                            : (store.query.trim().length > 0
                                ? Translation.tr("Clear search")
                                : (store.filter !== "all"
                                    ? Translation.tr("Show all")
                                    : Translation.tr("Add folder")))
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.variableAxes: ({ "wght": 660, "wdth": 100, "ROND": 100 })
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // Circular Back-to-Top FAB (bottom-left, symmetric to the bottom-right Add Folder FAB)
    RippleButton {
        id: backToTopFab
        readonly property bool shown: timelineList.contentY > 240
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.bottomMargin: 22
        z: 10
        implicitWidth: 60
        implicitHeight: 60
        buttonRadius: 30
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        opacity: shown ? 1.0 : 0.0
        scale: shown ? 1.0 : 0.72
        visible: opacity > 0.01
        enabled: shown
        onClicked: scrollTopAnim.restart()

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_upward"
            iconSize: 26
            color: Appearance.colors.colOnSecondaryContainer
        }

        StyledToolTip {
            requireOverlay: false
            text: Translation.tr("Back to top")
        }
    }
}
