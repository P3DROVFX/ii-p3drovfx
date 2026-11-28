pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Phone Gallery page (integrated with ii tools via PhoneGalleryBridge).
 * Shows offline / setup states gracefully, or the live album strip + virtualized
 * day-grouped grid of phone photos and videos with lazy thumbnail loading.
 */
Item {
    id: root

    required property var store
    required property var phoneBridge

    readonly property var albumStrip: {
        const list = phoneBridge.albums ?? [];
        const all = {
            id: "",
            name: Translation.tr("All"),
            count: Math.max(0, phoneBridge.totalCount),
            cover: list.length > 0 ? list[0].cover : null,
            icon: "photo_library"
        };
        return [all].concat(list.map(a => ({
            id: String(a.id),
            name: String(a.name || Translation.tr("Untitled")),
            count: Number(a.count ?? 0),
            cover: a.cover ?? null,
            icon: "photo_album"
        })));
    }

    readonly property var phoneRows: {
        const items = phoneBridge.items ?? [];
        const cols = store.gridColumns;
        const rows = [];
        let i = 0;
        let groupIdx = 0;
        while (i < items.length) {
            const key = store.dayKey(items[i].taken);
            let j = i;
            while (j < items.length && store.dayKey(items[j].taken) === key)
                j++;
            const count = j - i;
            const d = new Date(Number(items[i].taken || 0));
            const rowCount = Math.ceil(count / cols);
            for (let r = 0; r < rowCount; r++) {
                const slice = items.slice(i + r * cols, Math.min(j, i + (r + 1) * cols));
                rows.push({
                    groupKey: key,
                    groupIndex: groupIdx,
                    isFirstRowOfGroup: r === 0,
                    isLastRowOfGroup: r === rowCount - 1,
                    dayStr: items[i].taken > 0 ? store.pad2(d.getDate()) : "--",
                    monthStr: items[i].taken > 0 ? store.monthShortName(d.getMonth()) : "",
                    relStr: items[i].taken > 0 ? store.relDayLabel(items[i].taken) : Translation.tr("Unknown date"),
                    groupCount: count,
                    cells: slice
                });
            }
            groupIdx++;
            i = j;
        }
        return rows;
    }

    function requestVisibleThumbs(): void {
        if (!phoneBridge.available)
            return;
        const ids = [];
        for (const a of root.albumStrip) {
            if (a.cover && a.cover.id !== undefined)
                ids.push(String(a.cover.id));
        }
        const items = phoneBridge.items ?? [];
        const limit = Math.min(items.length, 64);
        for (let i = 0; i < limit; i++) {
            if (items[i] && items[i].id !== undefined)
                ids.push(String(items[i].id));
        }
        if (ids.length > 0)
            phoneBridge.wantThumbs(ids);
    }

    Connections {
        target: phoneBridge
        function onItemsChanged() { root.requestVisibleThumbs(); }
        function onAlbumsChanged() { root.requestVisibleThumbs(); }
    }

    Component.onCompleted: {
        phoneBridge.active = true;
        root.requestVisibleThumbs();
    }

    Component.onDestruction: {
        phoneBridge.active = false;
    }

    // ── Offline / Setup state ───────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: phoneBridge.setupState !== "ready"

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(460, parent.width - 48)
            spacing: 14

            MaterialShape {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 100
                implicitHeight: 100
                shape: phoneBridge.setupState === "offline"
                    ? MaterialShape.Shape.SoftBurst
                    : MaterialShape.Shape.Cookie12Sided
                color: Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: phoneBridge.setupState === "offline" ? "phonelink_off" : "photo_library"
                    iconSize: 42
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: phoneBridge.setupState === "offline"
                    ? Translation.tr("No phone connected")
                    : Translation.tr("Enable Phone Gallery in ii tools")
                font.pixelSize: 26
                font.variableAxes: ({ "wght": 580, "wdth": 110, "ROND": 100 })
                color: Appearance.colors.colOnSurface
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: phoneBridge.setupState === "offline"
                    ? Translation.tr("Connect your Android phone with ii tools to browse its gallery, download photos, or send media from your PC.")
                    : Translation.tr("Your phone is connected, but gallery browsing is turned off on the device.")
                font.pixelSize: 14
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.WordWrap
            }

            // Setup checklist when connected without gallery cap
            Rectangle {
                visible: phoneBridge.setupState === "setup"
                Layout.fillWidth: true
                implicitHeight: stepsCol.implicitHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: stepsCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    Repeater {
                        model: [
                            Translation.tr("1. Open ii tools on your phone"),
                            Translation.tr("2. Go to Tools → Phone gallery"),
                            Translation.tr("3. Allow Photos and videos access"),
                            Translation.tr("4. Turn on Let the PC browse gallery")
                        ]
                        delegate: StyledText {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            font.pixelSize: 14
                            color: Appearance.colors.colOnSurface
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                implicitHeight: 44
                leftPadding: 22
                rightPadding: 22
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: phoneBridge.openSession()
                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: "refresh"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Check connection")
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // ── Ready state: Album strip + virtualized timeline ─────────────────
    ListView {
        id: phoneList
        anchors.fill: parent
        visible: phoneBridge.setupState === "ready"
        clip: true
        cacheBuffer: 160
        flickDeceleration: 2200
        maximumFlickVelocity: 7200
        topMargin: 28
        bottomMargin: 120
        leftMargin: 32
        rightMargin: 32
        model: root.phoneRows

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse
            onWheel: event => {
                if (event.angleDelta.y === 0)
                    return;
                const step = -event.angleDelta.y * 0.85;
                const maxY = Math.max(0, phoneList.contentHeight - phoneList.height + phoneList.bottomMargin);
                phoneList.contentY = Math.max(0, Math.min(maxY, phoneList.contentY + step));
                event.accepted = true;
            }
        }

        header: Item {
            width: phoneList.width - phoneList.leftMargin - phoneList.rightMargin
            height: phoneHeaderCol.implicitHeight + 24

            ColumnLayout {
                id: phoneHeaderCol
                width: parent.width
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            text: Translation.tr("VIA II TOOLS")
                            font.pixelSize: 12
                            font.letterSpacing: 0.9
                            font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 60 })
                            color: Appearance.colors.colPrimary
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            StyledText {
                                text: phoneBridge.deviceName || Translation.tr("Phone")
                                font.pixelSize: 48
                                lineHeight: 0.92
                                font.variableAxes: ({ "wght": 700, "wdth": 50, "ROND": 100 })
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 4
                                visible: phoneBridge.totalCount >= 0
                                text: Translation.tr("%1 items").arg(phoneBridge.totalCount)
                                font.pixelSize: 22
                                font.italic: true
                                color: Appearance.colors.colPrimary
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    RippleButton {
                        implicitHeight: 42
                        leftPadding: 16
                        rightPadding: 18
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: phoneBridge.refresh()
                        contentItem: RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "refresh"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Sync")
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                // Horizontal phone album pills
                ListView {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    model: root.albumStrip

                    delegate: RippleButton {
                        id: albChip
                        required property var modelData
                        readonly property bool selected: phoneBridge.album === modelData.id

                        implicitHeight: 42
                        leftPadding: 12
                        rightPadding: 16
                        buttonRadius: selected ? 21 : Appearance.rounding.small
                        colBackground: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        colBackgroundHover: selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                        onClicked: phoneBridge.setAlbum(modelData.id)

                        Behavior on buttonRadius { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                        contentItem: RowLayout {
                            spacing: 7
                            MaterialSymbol {
                                text: albChip.modelData.icon
                                fill: albChip.selected ? 1 : 0
                                iconSize: 18
                                color: albChip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: albChip.modelData.count > 0
                                    ? `${albChip.modelData.name} · ${albChip.modelData.count}`
                                    : albChip.modelData.name
                                font.pixelSize: 14
                                font.weight: albChip.selected ? Font.DemiBold : Font.Medium
                                color: albChip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            }
                        }
                    }
                }
            }
        }

        delegate: Item {
            id: pRow
            required property var modelData
            required property int index

            readonly property int railWidth: root.width < 880 ? 118 : 156
            readonly property int gap: 8
            readonly property int cols: store.gridColumns
            readonly property real gridAreaW: Math.max(200, width - railWidth - 18)
            readonly property real tileSize: Math.max(72, Math.floor((gridAreaW - gap * (cols - 1)) / cols))
            readonly property int bottomPad: modelData.isLastRowOfGroup ? 28 : gap

            width: phoneList.width - phoneList.leftMargin - phoneList.rightMargin
            height: Math.max(modelData.isFirstRowOfGroup ? 104 : 0, tileSize) + bottomPad

            // Left day marker
            Item {
                visible: pRow.modelData.isFirstRowOfGroup
                x: 0
                y: 0
                width: pRow.railWidth
                height: 104

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 1

                    StyledText {
                        text: pRow.modelData.dayStr
                        font.family: Appearance.font.family.main
                        font.pixelSize: 54
                        lineHeight: 0.84
                        font.variableAxes: ({ "wght": 760, "wdth": 36, "ROND": 100 })
                        color: pRow.modelData.groupIndex === 0
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: pRow.modelData.monthStr
                        font.family: Appearance.font.family.main
                        font.pixelSize: 15
                        font.letterSpacing: 1.4
                        font.variableAxes: ({ "wght": 760, "wdth": 118, "ROND": 100 })
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: pRow.modelData.relStr
                        font.pixelSize: 13
                        font.italic: true
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            // Right media row
            Row {
                x: pRow.railWidth + 18
                y: 0
                spacing: pRow.gap

                Repeater {
                    model: pRow.modelData.cells

                    delegate: Item {
                        id: pTile
                        required property var modelData
                        readonly property bool isVideo: modelData.kind === "video"
                        readonly property string thumbSrc: {
                            void phoneBridge.thumbRevision;
                            return phoneBridge.thumbPath(modelData.id);
                        }
                        readonly property bool isSaved: (phoneBridge.savedPaths[String(modelData.id)] ?? "") !== ""

                        width: pRow.tileSize
                        height: pRow.tileSize

                        Component.onCompleted: {
                            if (!thumbSrc)
                                phoneBridge.wantThumbs([String(modelData.id)]);
                        }

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: ptMouse.containsMouse ? Appearance.rounding.large : Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                            Image {
                                id: pImg
                                anchors.fill: parent
                                source: pTile.thumbSrc
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize: Qt.size(180, 180)
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: pImg.status !== Image.Ready
                                text: pTile.isVideo ? "movie" : "photo"
                                iconSize: 26
                                color: Appearance.colors.colSubtext
                                opacity: 0.45
                            }

                            // Video duration pill
                            Rectangle {
                                visible: pTile.isVideo
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 8
                                implicitWidth: pvRow.implicitWidth + 12
                                implicitHeight: 24
                                radius: 12
                                color: Appearance.colors.colSecondaryContainer

                                RowLayout {
                                    id: pvRow
                                    anchors.centerIn: parent
                                    spacing: 3
                                    MaterialSymbol {
                                        text: "play_arrow"
                                        fill: 1
                                        iconSize: 15
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        text: Number(pTile.modelData.dur || 0) > 0
                                            ? store.formatTime(Number(pTile.modelData.dur) / 1000)
                                            : "VID"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                            }

                            // Saved-to-PC badge
                            MaterialShape {
                                visible: pTile.isSaved
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                width: 26
                                height: 26
                                shape: MaterialShape.Shape.Circle
                                color: Appearance.colors.colPrimary

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "download_done"
                                    iconSize: 14
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }

                        MouseArea {
                            id: ptMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const pt = pTile.mapToItem(null, 0, 0);
                                store.openPhoneViewer(pTile.modelData.id, phoneBridge.items, {
                                    x: pt.x, y: pt.y, w: pTile.width, h: pTile.height,
                                    thumb: pTile.thumbSrc
                                });
                            }
                        }
                    }
                }
            }
        }

        footer: Item {
            width: phoneList.width - phoneList.leftMargin - phoneList.rightMargin
            height: (phoneBridge.more || phoneBridge.loading) ? 80 : 0

            RippleButton {
                anchors.centerIn: parent
                visible: phoneBridge.more && !phoneBridge.loading
                implicitHeight: 42
                leftPadding: 20
                rightPadding: 20
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: phoneBridge.loadMore()
                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Load more")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: phoneBridge.loading
                text: Translation.tr("Loading from phone…")
                font.pixelSize: 14
                color: Appearance.colors.colSubtext
            }
        }
    }
}
