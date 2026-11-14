pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/*
 * The phone's gallery in the Phone tab: albums as a strip of shaped covers, the photos
 * grouped by day (each day one grouped shape: large outer corners, small joins), and
 * the viewer in place of the grid, which stays alive underneath to keep its scroll.
 */
Rectangle {
    id: root
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    property bool showBackButton: true
    signal goBack()

    readonly property int columns: 4
    readonly property int gridGap: 3
    readonly property bool viewerActive: PhoneGalleryService.setupState === "ready"
        && PhoneGalleryService.viewerOpen
        && PhoneGalleryService.viewerItem !== null

    // Fixed faces (never animated: every distinct axes value opens a new font face).
    readonly property var axesTitle: ({ "wght": 720, "wdth": 118, "ROND": 100 })
    readonly property var axesDay: ({ "wght": 680, "wdth": 108, "ROND": 100 })
    readonly property var axesDigits: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var axesDigitsLight: ({ "wght": 560, "wdth": 40, "ROND": 100 })

    property var rows: []
    property var _instantiatedRows: ({})
    property bool _thumbsQueued: false

    readonly property var _setupSteps: [
        Translation.tr("Open <b>ii tools</b> on the phone"),
        Translation.tr("Go to <b>Tools → Phone gallery</b>"),
        Translation.tr("Allow <b>Photos and videos</b>"),
        Translation.tr("Turn on <b>Let the PC browse gallery</b>")
    ]

    // "All" first, then the phone's albums (newest first); the first album's cover is
    // the newest item overall, so it doubles as the cover of "All".
    readonly property var albumStrip: {
        const albums = PhoneGalleryService.albums ?? [];
        const all = {
            id: "",
            name: Translation.tr("All"),
            count: Math.max(0, PhoneGalleryService.totalCount),
            cover: albums.length > 0 ? albums[0].cover : null,
            icon: "photo_library"
        };
        return [all].concat(albums.map(a => ({
            id: String(a.id),
            name: String(a.name || Translation.tr("Untitled")),
            count: Number(a.count ?? 0),
            cover: a.cover ?? null,
            icon: "photo_album"
        })));
    }

    onViewerActiveChanged: {
        if (!viewerActive)
            scheduleVisibleThumbCheck();
    }

    // Sub-page entrance animation (as Contacts)
    opacity: 0
    transform: Translate { id: pageTranslate; y: 16 }

    Component.onCompleted: {
        pageEntranceAnim.start();
        PhoneGalleryService.open();
        rebuildRows();
    }

    Component.onDestruction: {
        PhoneGalleryService.close();
    }

    SequentialAnimation {
        id: pageEntranceAnim
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                from: 0
                to: 1
                duration: 280
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: pageTranslate
                property: "y"
                from: 16
                to: 0
                duration: 360
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
        }
    }

    Connections {
        target: PhoneGalleryService

        function onItemsChanged() {
            root.rebuildRows();
        }

        function onAlbumsChanged() {
            root.scheduleVisibleThumbCheck();
        }

        function onAlbumChanged() {
            gridList.positionViewAtBeginning();
        }
    }

    function dayKey(takenMs) {
        const ms = Number(takenMs || 0);
        if (ms <= 0)
            return "unknown";
        const d = new Date(ms);
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function formatDayLabel(takenMs) {
        const ms = Number(takenMs || 0);
        if (ms <= 0)
            return Translation.tr("Unknown date");
        const d = new Date(ms);
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const itemStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const diffDays = Math.round((todayStart - itemStart) / 86400000);
        if (diffDays === 0)
            return Translation.tr("Today");
        if (diffDays === 1)
            return Translation.tr("Yesterday");
        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "ddd, MMM d" : "MMM d, yyyy");
    }

    function formatBytes(bytes) {
        const n = Number(bytes || 0);
        if (n <= 0)
            return "";
        if (n < 1024)
            return n.toFixed(0) + " B";
        if (n < 1024 * 1024)
            return (n / 1024).toFixed(1) + " KB";
        if (n < 1024 * 1024 * 1024)
            return (n / (1024 * 1024)).toFixed(1) + " MB";
        return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
    }

    function viewerSubtitle(item) {
        if (!item)
            return "";
        const parts = [];
        const taken = Number(item.taken || 0);
        if (taken > 0) {
            const d = new Date(taken);
            const sameYear = d.getFullYear() === new Date().getFullYear();
            parts.push(Qt.formatDateTime(d, sameYear ? "MMM d, HH:mm" : "MMM d, yyyy, HH:mm"));
        }
        const sz = formatBytes(item.size);
        if (sz.length > 0)
            parts.push(sz);
        if (item.w > 0 && item.h > 0)
            parts.push("%1×%2".arg(String(item.w)).arg(String(item.h)));
        if (item.kind === "video" && Number(item.dur || 0) > 0)
            parts.push(PhoneGalleryService.formatDuration(item.dur));
        return parts.join(" · ");
    }

    function activeAlbumName() {
        if (PhoneGalleryService.album.length === 0)
            return Translation.tr("photos and videos");
        const a = PhoneGalleryService.albums.find(x => String(x.id) === PhoneGalleryService.album);
        return a ? String(a.name) : "";
    }

    function activeAlbumCount() {
        if (PhoneGalleryService.album.length === 0)
            return PhoneGalleryService.totalCount;
        const a = PhoneGalleryService.albums.find(x => String(x.id) === PhoneGalleryService.album);
        return a ? Number(a.count ?? -1) : -1;
    }

    /// Rows for the ListView: a header per day, then rows of `columns` cells. Each cell
    /// knows which of its corners are outer corners of its day's block.
    function rebuildRows() {
        const items = PhoneGalleryService.items || [];
        const C = root.columns;
        const built = [];
        let i = 0;
        while (i < items.length) {
            const key = dayKey(items[i].taken);
            let j = i;
            while (j < items.length && dayKey(items[j].taken) === key)
                j++;
            const n = j - i;
            const R = Math.ceil(n / C);
            const L = n - (R - 1) * C;
            built.push({ type: "header", label: formatDayLabel(items[i].taken), count: n });
            for (let r = 0; r < R; r++) {
                const cells = [];
                for (let c = 0; c < C && r * C + c < n; c++) {
                    const k = r * C + c;
                    cells.push({
                        item: items[i + k],
                        index: i + k,
                        tl: r === 0 && c === 0,
                        tr: r === 0 && c === Math.min(C, n) - 1,
                        bl: r === R - 1 && c === 0,
                        br: (r === R - 1 && c === L - 1) || (r === R - 2 && c === C - 1 && L < C)
                    });
                }
                built.push({ type: "row", cells: cells });
            }
            i = j;
        }
        _instantiatedRows = {};
        rows = built;
        scheduleVisibleThumbCheck();
    }

    function scheduleVisibleThumbCheck() {
        if (_thumbsQueued)
            return;
        _thumbsQueued = true;
        Qt.callLater(() => {
            root._thumbsQueued = false;
            root.requestVisibleThumbs();
        });
    }

    function requestVisibleThumbs() {
        if (root.viewerActive || PhoneGalleryService.setupState !== "ready")
            return;

        const indices = Object.keys(_instantiatedRows)
            .map(k => parseInt(k, 10))
            .filter(n => !isNaN(n))
            .sort((a, b) => a - b);

        const ids = [];
        for (let i = 0; i < indices.length; i++) {
            const row = _instantiatedRows[indices[i]];
            if (!row || row.type !== "row" || !row.cells)
                continue;
            for (let j = 0; j < row.cells.length; j++) {
                const cell = row.cells[j];
                if (cell && cell.item)
                    ids.push(cell.item.id);
            }
        }
        // The album covers after the visible photos: the request replaces the phone's
        // queue, so they must ride along every time.
        for (const a of root.albumStrip.slice(0, 24)) {
            if (a.cover !== null && a.cover !== undefined)
                ids.push(a.cover);
        }
        if (ids.length > 0)
            PhoneGalleryService.wantThumbs(ids);

        maybeLoadMore();
    }

    function maybeLoadMore() {
        if (!PhoneGalleryService.more || PhoneGalleryService.loading || PhoneGalleryService.items.length === 0)
            return;
        if (gridList.contentHeight <= 0)
            return;
        if (gridList.contentY + gridList.height >= gridList.contentHeight - 240)
            PhoneGalleryService.loadMore();
    }

    // An empty state: expressive shape, title, body.
    component GalleryEmptyState: ColumnLayout {
        id: emptyState
        property string icon: "photo_library"
        property var shape: MaterialShape.Shape.Cookie9Sided
        property color colShape: Appearance.colors.colSecondaryContainer
        property color colSymbol: Appearance.colors.colOnSecondaryContainer
        property string title: ""
        property string body: ""
        default property alias extra: extraSlot.data

        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 300)
        spacing: 10

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 4
            text: emptyState.icon
            iconSize: 30
            padding: 18
            fill: 1.0
            color: emptyState.colShape
            colSymbol: emptyState.colSymbol
            shape: emptyState.shape
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: root.axesTitle
            color: Appearance.colors.colOnLayer2
            text: emptyState.title
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: emptyState.body
        }

        ColumnLayout {
            id: extraSlot
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // ─── Header ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                visible: root.viewerActive || root.showBackButton
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colBackgroundActive: Appearance.colors.colLayer3Active ?? Appearance.colors.colLayer3Hover
                onClicked: root.viewerActive ? PhoneGalleryService.closeViewer() : root.goBack()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.viewerActive ? "grid_view" : "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer3
                    animateChange: true
                }

                StyledToolTip {
                    text: root.viewerActive ? Translation.tr("Back to gallery") : Translation.tr("Back")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: -2

                StyledText {
                    Layout.fillWidth: true
                    text: root.viewerActive
                        ? (PhoneGalleryService.viewerItem?.name || "")
                        : Translation.tr("Gallery")
                    font.pixelSize: root.viewerActive
                        ? Appearance.font.pixelSize.normal
                        : Appearance.font.pixelSize.huge
                    font.variableAxes: root.viewerActive
                        ? ({ "wght": 680, "wdth": 92, "ROND": 100 })
                        : root.axesTitle
                    color: Appearance.colors.colOnLayer2
                    elide: root.viewerActive ? Text.ElideMiddle : Text.ElideRight
                }

                // Grid: the count in condensed digits, then what it counts.
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.viewerActive && PhoneGalleryService.setupState === "ready"
                    spacing: 4

                    StyledText {
                        visible: root.activeAlbumCount() >= 0
                        text: String(root.activeAlbumCount())
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.variableAxes: root.axesDigits
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.activeAlbumName()
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.viewerActive
                    text: root.viewerSubtitle(PhoneGalleryService.viewerItem)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                id: refreshBtn
                visible: !root.viewerActive && PhoneGalleryService.setupState === "ready"
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colBackgroundActive: Appearance.colors.colLayer3Active ?? Appearance.colors.colLayer3Hover
                enabled: !PhoneGalleryService.loading
                onClicked: PhoneGalleryService.refresh()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 18
                    color: refreshBtn.enabled ? Appearance.colors.colOnLayer3 : Appearance.colors.colSubtext
                }

                StyledToolTip {
                    text: Translation.tr("Refresh")
                }
            }

            // Viewer: where we are, the index in tall condensed digits.
            Row {
                visible: root.viewerActive
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    anchors.baseline: totalText.baseline
                    text: String(PhoneGalleryService.viewerIndex + 1)
                    font.pixelSize: Appearance.font.pixelSize.hugeass + 5
                    font.variableAxes: root.axesDigits
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    id: totalText
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: "/" + String(PhoneGalleryService.items.length) + (PhoneGalleryService.more ? "+" : "")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.variableAxes: root.axesDigitsLight
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GalleryEmptyState {
                visible: PhoneGalleryService.setupState === "offline"
                icon: "phonelink_off"
                shape: MaterialShape.Shape.Ghostish
                colShape: Appearance.colors.colLayer3
                colSymbol: Appearance.colors.colOnLayer3
                title: Translation.tr("Phone not connected")
                body: Translation.tr("Open ii tools on the phone to connect.")
            }

            // Phone connected, gallery off or permission missing: the steps to turn it on.
            GalleryEmptyState {
                visible: PhoneGalleryService.setupState === "setup"
                icon: "photo_library"
                shape: MaterialShape.Shape.Cookie12Sided
                colShape: Appearance.colors.colTertiaryContainer
                colSymbol: Appearance.colors.colOnTertiaryContainer
                title: Translation.tr("Set up gallery on the phone")
                body: Translation.tr("This page updates by itself once it is on.")

                Repeater {
                    model: root._setupSteps

                    delegate: RowLayout {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        spacing: 10

                        MaterialShape {
                            Layout.alignment: Qt.AlignVCenter
                            implicitSize: 26
                            color: Appearance.colors.colSecondaryContainer
                            shape: [MaterialShape.Shape.Circle, MaterialShape.Shape.Cookie4Sided,
                                MaterialShape.Shape.Cookie6Sided, MaterialShape.Shape.Cookie7Sided][index % 4]

                            StyledText {
                                anchors.centerIn: parent
                                text: String(index + 1)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.variableAxes: root.axesDigits
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }

            // Ready: the grid (kept alive underneath) and the viewer over it.
            Item {
                anchors.fill: parent
                visible: PhoneGalleryService.setupState === "ready"

                ColumnLayout {
                    id: gridLayer
                    anchors.fill: parent
                    spacing: 6
                    opacity: root.viewerActive ? 0 : 1
                    scale: root.viewerActive ? 0.96 : 1
                    visible: opacity > 0.001
                    enabled: !root.viewerActive

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }

                    // ─── Albums ──────────────────────────────────────
                    ListView {
                        id: albumList
                        visible: PhoneGalleryService.albums.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 104
                        orientation: ListView.Horizontal
                        spacing: 2
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.albumStrip

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                                const maxX = Math.max(0, albumList.contentWidth - albumList.width);
                                albumList.contentX = Math.max(0, Math.min(maxX, albumList.contentX - delta * 0.6));
                            }
                        }

                        delegate: PhoneGalleryAlbumTile {
                            required property var modelData
                            name: modelData.name
                            count: modelData.count
                            coverId: modelData.cover
                            glyph: modelData.icon
                            selected: PhoneGalleryService.album === modelData.id
                            onClicked: PhoneGalleryService.setAlbum(modelData.id)
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        GalleryEmptyState {
                            visible: PhoneGalleryService.error.length > 0 && PhoneGalleryService.items.length === 0
                            icon: "cloud_off"
                            shape: MaterialShape.Shape.Puffy
                            colShape: Appearance.colors.colErrorContainer
                            colSymbol: Appearance.colors.colOnErrorContainer
                            title: Translation.tr("Couldn't load gallery")
                            body: PhoneGalleryService.error === "timeout"
                                ? Translation.tr("The phone did not answer")
                                : PhoneGalleryService.error

                            RippleButtonWithIcon {
                                Layout.alignment: Qt.AlignHCenter
                                materialIcon: "refresh"
                                mainText: Translation.tr("Retry")
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colPrimaryContainer
                                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                                colText: Appearance.colors.colOnPrimaryContainer
                                onClicked: PhoneGalleryService.refresh()
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10
                            visible: PhoneGalleryService.loading && PhoneGalleryService.items.length === 0 && PhoneGalleryService.error.length === 0

                            MaterialLoadingIndicator {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 44
                                loading: true
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Loading gallery…")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        GalleryEmptyState {
                            visible: !PhoneGalleryService.loading
                                && PhoneGalleryService.loadedOnce
                                && PhoneGalleryService.items.length === 0
                                && PhoneGalleryService.error.length === 0
                            icon: "imagesmode"
                            shape: MaterialShape.Shape.Flower
                            title: Translation.tr("No photos or videos")
                            body: PhoneGalleryService.album.length > 0
                                ? Translation.tr("Nothing in this album yet.")
                                : Translation.tr("Photos and videos from your phone will appear here.")
                        }

                        // ─── Photos by day ───────────────────────────
                        StyledListView {
                            id: gridList
                            anchors.fill: parent
                            visible: PhoneGalleryService.items.length > 0
                            model: root.rows
                            spacing: root.gridGap
                            clip: true
                            cacheBuffer: 320
                            animateAppearance: false

                            onContentYChanged: root.maybeLoadMore()

                            delegate: Item {
                                id: rowDelegate
                                required property var modelData
                                required property int index

                                readonly property bool isHeader: modelData && modelData.type === "header"
                                readonly property real cellSize: Math.max(40, Math.floor((gridList.width - root.gridGap * (root.columns - 1)) / root.columns))

                                property int _trackedIndex: -1

                                width: gridList.width
                                height: isHeader ? (index === 0 ? 30 : 42) : cellSize

                                function syncTrackedRow() {
                                    if (_trackedIndex >= 0 && _trackedIndex !== index)
                                        delete root._instantiatedRows[_trackedIndex];
                                    _trackedIndex = index;
                                    root._instantiatedRows[index] = modelData;
                                    root.scheduleVisibleThumbCheck();
                                }

                                Component.onCompleted: syncTrackedRow()
                                onIndexChanged: syncTrackedRow()
                                onModelDataChanged: syncTrackedRow()
                                Component.onDestruction: {
                                    if (_trackedIndex >= 0)
                                        delete root._instantiatedRows[_trackedIndex];
                                }

                                // Day header: the day in the wide face, its count in digits.
                                RowLayout {
                                    visible: rowDelegate.isHeader
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    anchors.bottomMargin: 6
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: rowDelegate.isHeader ? (rowDelegate.modelData.label || "") : ""
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.variableAxes: root.axesDay
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        text: rowDelegate.isHeader ? String(rowDelegate.modelData.count ?? "") : ""
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.variableAxes: root.axesDigitsLight
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                Row {
                                    visible: !rowDelegate.isHeader
                                    spacing: root.gridGap

                                    Repeater {
                                        model: rowDelegate.isHeader ? [] : rowDelegate.modelData.cells

                                        delegate: RippleButton {
                                            id: cell
                                            required property var modelData

                                            readonly property var mediaItem: modelData.item
                                            readonly property bool isVideo: mediaItem.kind === "video"
                                            readonly property bool thumbReady: PhoneGalleryService.thumbRevision >= 0
                                                && PhoneGalleryService.hasThumb(mediaItem.id)

                                            // Shape is state: the day's grouped corners, all
                                            // rounding to one radius under the pointer. One
                                            // value drives every corner.
                                            property real hoverT: cell.hovered ? 1 : 0
                                            Behavior on hoverT {
                                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                            }
                                            function corner(outer) {
                                                const base = outer ? Appearance.rounding.large : Appearance.rounding.unsharpenmore;
                                                return base + (Appearance.rounding.normal - base) * cell.hoverT;
                                            }

                                            width: rowDelegate.cellSize
                                            height: rowDelegate.cellSize
                                            topLeftRadius: corner(modelData.tl)
                                            topRightRadius: corner(modelData.tr)
                                            bottomLeftRadius: corner(modelData.bl)
                                            bottomRightRadius: corner(modelData.br)
                                            colBackground: Appearance.colors.colLayer3
                                            colBackgroundHover: Appearance.colors.colLayer3Hover
                                            colBackgroundActive: Appearance.colors.colLayer3Active ?? Appearance.colors.colLayer3Hover
                                            scale: cell.down ? 0.95 : 1
                                            Behavior on scale {
                                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                                            }
                                            onClicked: PhoneGalleryService.openViewer(modelData.index)

                                            contentItem: ClippingRectangle {
                                                anchors.fill: parent
                                                color: "transparent"
                                                topLeftRadius: cell.topLeftRadius
                                                topRightRadius: cell.topRightRadius
                                                bottomLeftRadius: cell.bottomLeftRadius
                                                bottomRightRadius: cell.bottomRightRadius

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    visible: thumbImage.status !== Image.Ready
                                                    text: cell.isVideo ? "movie" : "image"
                                                    iconSize: 22
                                                    color: Appearance.colors.colSubtext
                                                }

                                                Image {
                                                    id: thumbImage
                                                    anchors.fill: parent
                                                    source: cell.thumbReady ? PhoneGalleryService.thumbPath(cell.mediaItem.id) : ""
                                                    asynchronous: true
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    sourceSize.width: 240
                                                    sourceSize.height: 240
                                                    opacity: status === Image.Ready ? 1 : 0

                                                    Behavior on opacity {
                                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                                    }
                                                }

                                                // Video: a secondary pill with the duration in digits.
                                                Rectangle {
                                                    visible: cell.isVideo
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 5
                                                    radius: height / 2
                                                    color: Appearance.colors.colSecondaryContainer
                                                    implicitWidth: durRow.implicitWidth + 10
                                                    implicitHeight: durRow.implicitHeight + 2

                                                    Row {
                                                        id: durRow
                                                        anchors.centerIn: parent
                                                        spacing: 1

                                                        MaterialSymbol {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "play_arrow"
                                                            fill: 1
                                                            iconSize: 13
                                                            color: Appearance.colors.colOnSecondaryContainer
                                                        }

                                                        StyledText {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: PhoneGalleryService.formatDuration(cell.mediaItem.dur)
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            font.variableAxes: root.axesDigits
                                                            color: Appearance.colors.colOnSecondaryContainer
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            footer: Item {
                                width: gridList.width
                                height: (PhoneGalleryService.loading || PhoneGalleryService.more) ? 56 : 10

                                MaterialLoadingIndicator {
                                    anchors.centerIn: parent
                                    visible: PhoneGalleryService.loading && PhoneGalleryService.items.length > 0
                                    implicitSize: 28
                                    loading: visible
                                }

                                RippleButtonWithIcon {
                                    anchors.centerIn: parent
                                    visible: !PhoneGalleryService.loading && PhoneGalleryService.more
                                    materialIcon: PhoneGalleryService.error.length > 0 ? "refresh" : "expand_more"
                                    mainText: PhoneGalleryService.error.length > 0 ? Translation.tr("Retry") : Translation.tr("Load more")
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                                    colText: Appearance.colors.colOnSecondaryContainer
                                    onClicked: PhoneGalleryService.loadMore()
                                }
                            }
                        }
                    }
                }

                PhoneGalleryViewer {
                    id: viewerLayer
                    anchors.fill: parent
                    active: root.viewerActive
                    opacity: root.viewerActive ? 1 : 0
                    scale: root.viewerActive ? 1 : 0.96
                    visible: root.viewerActive || opacity > 0.001
                    enabled: root.viewerActive

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
