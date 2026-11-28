pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Albums page matching the M3 Expressive Bento prototype:
 *  - Top 4-col bento block (356px tall):
 *      Col 1-2: Hero root album (colPrimaryContainer, Cookie12Sided ornament, 3-photo mosaic)
 *      Col 3:   Tall 2nd root album (colSecondaryContainer, stacked bold/thin digits, photo strip)
 *      Col 4:   2 stacked photo album cards (top subfolders)
 *  - Below: 4-col grid of remaining albums (all clipped with rounded corners & colLayer2 band)
 *    + dashed Add Folder card.
 *  - Album detail view: Back button, breadcrumbs, subfolder chips, virtualized GridView.
 */
Item {
    id: root

    required property var store
    property real layoutWidth: width

    readonly property var allAlbums: store.albumsData ?? []
    readonly property var videosAlbum: allAlbums.find(a => a.depth === 1 && String(a.name).toLowerCase() === "videos") ?? null
    readonly property var rootAlbums: allAlbums
        .filter(a => a.depth === 1 && a !== videosAlbum)
        .sort((a, b) => b.items.length - a.items.length)
    readonly property var subAlbums: allAlbums.filter(a => a.depth > 1).sort((a, b) => b.items.length - a.items.length)
    readonly property var sideStackAlbums: subAlbums.slice(0, videosAlbum ? 1 : 2)
    readonly property var gridAlbums: rootAlbums.slice(2).concat(subAlbums.slice(videosAlbum ? 1 : 2))

    readonly property var detailItems: store.activeAlbum ? store.albumItems(store.activeAlbum) : []
    readonly property var detailSubs: store.activeAlbum ? store.subfoldersOf(store.activeAlbum) : []

    function coverPhotoUrl(album, idx): string {
        if (!album || !album.items || album.items.length === 0)
            return "";
        const photos = album.items.filter(x => x.type === "photo");
        const pick = photos[idx] ?? album.items[idx] ?? null;
        return pick ? store.thumbUrlFor(pick) : "";
    }

    function subfolderCount(albumPath): int {
        const prefix = String(albumPath ?? "") + "/";
        return root.allAlbums.filter(a => a.path.startsWith(prefix)).length;
    }

    // Reusable Photo Album Card (rounded ClippingRectangle with cover + colLayer2 bottom band)
    component PhotoAlbumCard: ClippingRectangle {
        id: cardRoot
        required property var albumData
        readonly property string coverUrl: albumData ? root.coverPhotoUrl(albumData, 0) : ""

        radius: cardMouse.containsMouse ? 30 : Appearance.rounding.large
        color: Appearance.colors.colLayer2

        Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.fill: parent
                    color: Appearance.m3colors.m3surfaceContainerHigh
                }

                Image {
                    anchors.fill: parent
                    visible: cardRoot.coverUrl.length > 0
                    source: cardRoot.coverUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize: Qt.size(220, 160)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: cardRoot.coverUrl.length === 0
                    text: cardRoot.albumData ? store.folderIcon(cardRoot.albumData.name) : "folder"
                    iconSize: 34
                    color: Appearance.colors.colSubtext
                    opacity: 0.45
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 58
                color: cardMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                Behavior on color { ColorAnimation { duration: 140 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            text: cardRoot.albumData ? cardRoot.albumData.name : ""
                            font.family: Appearance.font.family.main
                            font.pixelSize: 16
                            font.variableAxes: ({ "wght": 640, "wdth": 106, "ROND": 100 })
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: !cardRoot.albumData
                                ? ""
                                : (cardRoot.albumData.path.includes("/")
                                    ? cardRoot.albumData.path.split("/").slice(0, -1).join(" › ")
                                    : cardRoot.albumData.displayPath)
                            font.family: Appearance.font.family.main
                            font.pixelSize: 12
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    StyledText {
                        text: cardRoot.albumData ? store.pad2(cardRoot.albumData.items.length) : "00"
                        font.family: Appearance.font.family.main
                        font.pixelSize: 32
                        lineHeight: 0.88
                        font.variableAxes: ({ "wght": 760, "wdth": 36, "ROND": 100 })
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (cardRoot.albumData) store.activeAlbum = cardRoot.albumData.path
        }
    }

    NumberAnimation {
        id: albumsScrollTopAnim
        target: overviewGrid
        property: "contentY"
        to: 0
        duration: 420
        easing.type: Easing.OutCubic
    }

    // ── Albums overview (virtualized GridView with top Bento block in header) ─
    Item {
        id: overviewHost
        anchors.fill: parent
        visible: store.activeAlbum === ""

        readonly property int gridCols: root.layoutWidth < 860 ? 2 : (root.layoutWidth < 1180 ? 3 : 4)
        readonly property int gridGap: 12
        readonly property var bottomModel: (root.layoutWidth >= 960 ? root.gridAlbums : root.rootAlbums.slice(2).concat(root.subAlbums))
            .concat([{ isAddCard: true }])

        GridView {
            id: overviewGrid
            anchors.fill: parent
            anchors.leftMargin: 32
            anchors.rightMargin: 32 - overviewHost.gridGap
            topMargin: 28
            bottomMargin: 140
            clip: true
            cacheBuffer: 180
            flickDeceleration: 2200
            maximumFlickVelocity: 7200
            cellWidth: Math.max(160, Math.floor((root.layoutWidth - 64 + overviewHost.gridGap) / overviewHost.gridCols))
            cellHeight: 196 + overviewHost.gridGap
            model: overviewHost.bottomModel

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse
                onWheel: event => {
                    if (event.angleDelta.y === 0)
                        return;
                    const step = -event.angleDelta.y * 0.85;
                    const maxY = Math.max(0, overviewGrid.contentHeight - overviewGrid.height + overviewGrid.bottomMargin);
                    overviewGrid.contentY = Math.max(0, Math.min(maxY, overviewGrid.contentY + step));
                    event.accepted = true;
                }
            }

            header: Item {
                width: overviewGrid.width - overviewHost.gridGap
                height: overviewCol.implicitHeight + 16

                ColumnLayout {
                    id: overviewCol
                    width: parent.width
                    spacing: 16

            // Header (aligned with top bento cards)
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 24

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        text: Translation.tr("ORGANIZED BY YOUR FOLDERS")
                        font.family: Appearance.font.family.main
                        font.pixelSize: 12
                        font.letterSpacing: 0.9
                        font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        StyledText {
                            text: Translation.tr("Albums")
                            font.family: Appearance.font.family.main
                            font.pixelSize: 68
                            lineHeight: 0.86
                            font.variableAxes: ({ "wght": 760, "wdth": 38, "ROND": 100 })
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 6
                            text: root.allAlbums.length === 1
                                ? Translation.tr("1 folder")
                                : Translation.tr("%1 folders").arg(root.allAlbums.length)
                            font.family: Appearance.font.family.main
                            font.pixelSize: 28
                            font.italic: true
                            color: Appearance.colors.colPrimary
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // Right-aligned square-rounded library counter badge (matches green prototype)
                Rectangle {
                    Layout.alignment: Qt.AlignBottom
                    implicitWidth: Math.max(108, libStatCol.implicitWidth + 32)
                    implicitHeight: 102
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colPrimary

                    ColumnLayout {
                        id: libStatCol
                        anchors.centerIn: parent
                        spacing: 2

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: store.pad2(store.libraryItems.length)
                            font.family: Appearance.font.family.main
                            font.pixelSize: 52
                            lineHeight: 0.86
                            font.variableAxes: ({ "wght": 760, "wdth": 36, "ROND": 100 })
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("IN LIBRARY")
                            font.family: Appearance.font.family.main
                            font.pixelSize: 10
                            font.letterSpacing: 0.8
                            font.variableAxes: ({ "wght": 740, "wdth": 100, "ROND": 100 })
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            // Top Bento Row (4-col proportions: 2 hero + 1 tall + 1 stacked pair)
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                visible: root.rootAlbums.length > 0

                // Cols 1-2: Hero Album Card
                Rectangle {
                    id: heroAlbumCard
                    readonly property var album: root.rootAlbums[0] ?? null
                    visible: album !== null
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    implicitHeight: 356
                    radius: heroMouse.containsMouse ? 36 : Appearance.rounding.large
                    color: heroMouse.containsMouse
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colPrimaryContainer
                    clip: true

                    Behavior on radius { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MaterialShape {
                        x: -90
                        y: 110
                        width: 380
                        height: 380
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.08
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 18

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            MaterialShape {
                                implicitWidth: 50
                                implicitHeight: 50
                                shape: heroMouse.containsMouse
                                    ? MaterialShape.Shape.Sunny
                                    : MaterialShape.Shape.Cookie12Sided
                                color: Appearance.colors.colPrimary

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: heroAlbumCard.album ? store.folderIcon(heroAlbumCard.album.name) : "folder"
                                    fill: 1
                                    iconSize: 25
                                    color: Appearance.colors.colOnPrimary
                                }
                            }

                            StyledText {
                                Layout.topMargin: 4
                                text: heroAlbumCard.album ? heroAlbumCard.album.name : ""
                                font.family: Appearance.font.family.main
                                font.pixelSize: 28
                                font.variableAxes: ({ "wght": 660, "wdth": 110, "ROND": 100 })
                                color: Appearance.colors.colOnPrimaryContainer
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            StyledText {
                                readonly property int subsCount: heroAlbumCard.album ? root.subfolderCount(heroAlbumCard.album.path) : 0
                                text: heroAlbumCard.album
                                    ? (subsCount > 0
                                        ? `${heroAlbumCard.album.displayPath} · ${subsCount} ${Translation.tr("subfolders")}`
                                        : heroAlbumCard.album.displayPath)
                                    : ""
                                font.family: Appearance.font.family.main
                                font.pixelSize: 13
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.8
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Item { Layout.fillHeight: true }

                            StyledText {
                                text: heroAlbumCard.album ? store.pad2(heroAlbumCard.album.items.length) : "00"
                                font.family: Appearance.font.family.main
                                font.pixelSize: 112
                                lineHeight: 0.8
                                font.variableAxes: ({ "wght": 760, "wdth": 34, "ROND": 100 })
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        // 3-photo mosaic (left tall + right 2 stacked, all rounded ClippingRectangles)
                        RowLayout {
                            visible: heroAlbumCard.album && heroAlbumCard.album.items.length > 0 && root.width >= 760
                            Layout.preferredWidth: Math.min(280, heroAlbumCard.width * 0.48)
                            Layout.fillHeight: true
                            spacing: 8

                            ClippingRectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Appearance.rounding.large
                                color: Appearance.colors.colLayer2
                                Image {
                                    anchors.fill: parent
                                    source: root.coverPhotoUrl(heroAlbumCard.album, 0)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                    sourceSize: Qt.size(280, 360)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8

                                ClippingRectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2
                                    Image {
                                        anchors.fill: parent
                                        source: root.coverPhotoUrl(heroAlbumCard.album, 1)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                        sourceSize: Qt.size(220, 220)
                                    }
                                }

                                ClippingRectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2
                                    Image {
                                        anchors.fill: parent
                                        source: root.coverPhotoUrl(heroAlbumCard.album, 2)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                        sourceSize: Qt.size(220, 220)
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: heroMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (heroAlbumCard.album) store.activeAlbum = heroAlbumCard.album.path
                    }
                }

                // Col 3: Tall Second Root Album Card (stacked bold/thin expressive digits)
                Rectangle {
                    id: secondAlbumCard
                    readonly property var album: root.rootAlbums.length > 1 ? root.rootAlbums[1] : null
                    readonly property string countStr: album ? store.pad2(album.items.length) : "00"
                    readonly property int splitAt: Math.ceil(countStr.length / 2)
                    visible: album !== null
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 356
                    radius: secMouse.containsMouse ? 36 : Appearance.rounding.large
                    color: secMouse.containsMouse
                        ? Appearance.colors.colSecondaryContainerHover
                        : Appearance.colors.colSecondaryContainer
                    clip: true

                    Behavior on radius { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: secondAlbumCard.album ? secondAlbumCard.album.name : ""
                                font.family: Appearance.font.family.main
                                font.pixelSize: 22
                                font.variableAxes: ({ "wght": 640, "wdth": 108, "ROND": 100 })
                                color: Appearance.colors.colOnSecondaryContainer
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            StyledText {
                                text: secondAlbumCard.album ? secondAlbumCard.album.displayPath : ""
                                font.family: Appearance.font.family.main
                                font.pixelSize: 13
                                color: Appearance.colors.colOnSecondaryContainer
                                opacity: 0.78
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Expressive stacked digits (top bold condensed, bottom tall thin condensed)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: -8

                            Item { Layout.fillHeight: true }
                            StyledText {
                                text: secondAlbumCard.countStr.slice(0, secondAlbumCard.splitAt)
                                font.family: Appearance.font.family.main
                                font.pixelSize: 82
                                lineHeight: 0.8
                                font.variableAxes: ({ "wght": 760, "wdth": 32, "ROND": 100 })
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: secondAlbumCard.countStr.slice(secondAlbumCard.splitAt)
                                font.family: Appearance.font.family.main
                                font.pixelSize: 82
                                lineHeight: 0.8
                                font.variableAxes: ({ "wght": 300, "wdth": 32, "ROND": 100 })
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            Item { Layout.fillHeight: true }
                        }

                        // Rounded photo strip at bottom
                        RowLayout {
                            visible: secondAlbumCard.album && secondAlbumCard.album.items.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 62
                            Layout.minimumHeight: 62
                            spacing: 6

                            Repeater {
                                model: 3
                                delegate: ClippingRectangle {
                                    id: stripClip
                                    required property int index
                                    readonly property string u: root.coverPhotoUrl(secondAlbumCard.album, index)
                                    visible: u.length > 0
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer2
                                    Image {
                                        anchors.fill: parent
                                        source: stripClip.u
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                        sourceSize: Qt.size(140, 140)
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: secMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (secondAlbumCard.album) store.activeAlbum = secondAlbumCard.album.path
                    }
                }

                // Col 4: Expressive System Videos card + top subfolder PhotoAlbumCard
                ColumnLayout {
                    visible: (root.videosAlbum !== null || root.sideStackAlbums.length > 0) && root.width >= 960
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 356
                    spacing: 12

                    // Expressive System Videos card (colTertiaryContainer)
                    Rectangle {
                        id: videosCard
                        visible: root.videosAlbum !== null
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: vidCardMouse.containsMouse ? 32 : Appearance.rounding.large
                        color: Appearance.m3colors.m3tertiaryContainer
                        clip: true

                        Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        MaterialShape {
                            x: parent.width - 110
                            y: -40
                            width: 170
                            height: 170
                            shape: MaterialShape.Shape.SoftBurst
                            color: Appearance.m3colors.m3onTertiaryContainer
                            opacity: 0.1
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                MaterialShape {
                                    implicitWidth: 40
                                    implicitHeight: 40
                                    shape: vidCardMouse.containsMouse
                                        ? MaterialShape.Shape.Flower
                                        : MaterialShape.Shape.Cookie9Sided
                                    color: Appearance.m3colors.m3tertiary

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "movie"
                                        fill: 1
                                        iconSize: 20
                                        color: Appearance.m3colors.m3onTertiary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        text: root.videosAlbum ? root.videosAlbum.name : Translation.tr("Videos")
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: 18
                                        font.variableAxes: ({ "wght": 680, "wdth": 108, "ROND": 100 })
                                        color: Appearance.m3colors.m3onTertiaryContainer
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    StyledText {
                                        text: root.videosAlbum ? root.videosAlbum.displayPath : "~/Videos"
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: 12
                                        color: Appearance.m3colors.m3onTertiaryContainer
                                        opacity: 0.78
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    text: root.videosAlbum ? store.pad2(root.videosAlbum.items.length) : "00"
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 56
                                    lineHeight: 0.84
                                    font.variableAxes: ({ "wght": 760, "wdth": 36, "ROND": 100 })
                                    color: Appearance.m3colors.m3onTertiaryContainer
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 4
                                    text: Translation.tr("System videos")
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 12
                                    font.italic: true
                                    color: Appearance.m3colors.m3onTertiaryContainer
                                    opacity: 0.85
                                }
                            }
                        }

                        MouseArea {
                            id: vidCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.videosAlbum) store.activeAlbum = root.videosAlbum.path
                        }
                    }

                    Repeater {
                        model: root.sideStackAlbums
                        delegate: PhotoAlbumCard {
                            required property var modelData
                            albumData: modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }
                    }
                }
            }
                }
            }

            delegate: Item {
                id: albGridCell
                required property var modelData
                width: overviewGrid.cellWidth
                height: overviewGrid.cellHeight

                Loader {
                    x: 0
                    y: 0
                    width: overviewGrid.cellWidth - overviewHost.gridGap
                    height: 196
                    sourceComponent: albGridCell.modelData.isAddCard === true ? addFolderCardComp : photoAlbumCardComp
                    property var itemAlbum: albGridCell.modelData
                }
            }
        }

        Component {
            id: photoAlbumCardComp
            PhotoAlbumCard {
                albumData: parent ? parent.itemAlbum : null
            }
        }

        Component {
            id: addFolderCardComp
            Rectangle {
                radius: addCardMouse.containsMouse ? 32 : Appearance.rounding.large
                color: addCardMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 140 } }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 56
                        implicitHeight: 56
                        shape: addCardMouse.containsMouse
                            ? MaterialShape.Shape.Flower
                            : MaterialShape.Shape.Clover4Leaf
                        color: Appearance.colors.colSecondaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"
                            iconSize: 26
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Add folder")
                        font.family: Appearance.font.family.main
                        font.pixelSize: 16
                        font.variableAxes: ({ "wght": 620, "wdth": 108, "ROND": 100 })
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                MouseArea {
                    id: addCardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: store.addSheetOpen = true
                }
            }
        }
    }

    // Back-to-Top circular FAB on Albums overview
    RippleButton {
        readonly property bool shown: store.activeAlbum === "" && overviewGrid.contentY > 240
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
        onClicked: albumsScrollTopAnim.restart()

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_upward"
            iconSize: 26
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledToolTip { requireOverlay: false; text: Translation.tr("Back to top") }
    }

    // ── Album detail view (virtualized GridView, exact edge-to-edge columns) ─
    Item {
        id: detailHost
        anchors.fill: parent
        visible: store.activeAlbum !== ""

        readonly property int cols: store.gridColumns
        readonly property int gap: 8

        GridView {
            id: detailGrid
            anchors.fill: parent
            anchors.leftMargin: 32
            anchors.rightMargin: 32 - detailHost.gap
            topMargin: 24
            bottomMargin: 120
            clip: true
            cacheBuffer: 160
            flickDeceleration: 2200
            maximumFlickVelocity: 7200
            // Exact division so `cols * cellWidth <= detailGrid.width` (zero empty right column!)
            cellWidth: Math.max(88, Math.floor(width / detailHost.cols))
            cellHeight: cellWidth
            model: root.detailItems

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse
                onWheel: event => {
                    if (event.angleDelta.y === 0)
                        return;
                    const step = -event.angleDelta.y * 0.85;
                    const maxY = Math.max(0, detailGrid.contentHeight - detailGrid.height + detailGrid.bottomMargin);
                    detailGrid.contentY = Math.max(0, Math.min(maxY, detailGrid.contentY + step));
                    event.accepted = true;
                }
            }

            // Click-and-drag swipe multi-selection overlay in Album detail
            MouseArea {
                id: albDragSelectArea
                anchors.fill: parent
                z: 8
                visible: store.selectionMode
                preventStealing: true
                property real dragY: -1

                function pathAt(mx, my): string {
                    const idx = detailGrid.indexAt(mx, my + detailGrid.contentY);
                    if (idx < 0 || idx >= root.detailItems.length)
                        return "";
                    return String(root.detailItems[idx].path ?? "");
                }

                Timer {
                    interval: 24
                    repeat: true
                    running: albDragSelectArea.pressed && (albDragSelectArea.dragY < 56 || albDragSelectArea.dragY > detailGrid.height - 56)
                    onTriggered: {
                        const delta = albDragSelectArea.dragY < 56 ? -18 : 18;
                        const maxY = Math.max(0, detailGrid.contentHeight - detailGrid.height + detailGrid.bottomMargin);
                        detailGrid.contentY = Math.max(0, Math.min(maxY, detailGrid.contentY + delta));
                    }
                }

                onPressed: mouse => {
                    dragY = mouse.y;
                    const p = pathAt(mouse.x, mouse.y);
                    if (p)
                        store.startDragSelect(p);
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    dragY = mouse.y;
                    const p = pathAt(mouse.x, mouse.y);
                    if (p)
                        store.applyDragSelect(p);
                }
                onReleased: store.endDragSelect()
                onCanceled: store.endDragSelect()
            }

            header: Item {
                width: detailGrid.width - detailHost.gap
                height: detailHeadCol.implicitHeight + 20

                ColumnLayout {
                    id: detailHeadCol
                    width: parent.width
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RippleButton {
                            implicitWidth: 48
                            implicitHeight: 48
                            buttonRadius: hovered ? 16 : 24
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: store.activeAlbum = ""
                            Behavior on buttonRadius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_back"
                                iconSize: 22
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4

                            RippleButton {
                                implicitHeight: 32
                                leftPadding: 10
                                rightPadding: 10
                                buttonRadius: 8
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                onClicked: store.activeAlbum = ""
                                contentItem: StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Albums")
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 14
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            Repeater {
                                model: store.activeAlbum ? store.activeAlbum.split("/") : []

                                delegate: RowLayout {
                                    required property string modelData
                                    required property int index
                                    readonly property var segs: store.activeAlbum.split("/")
                                    readonly property bool isLast: index === segs.length - 1
                                    spacing: 4

                                    MaterialSymbol {
                                        text: "chevron_right"
                                        iconSize: 16
                                        color: Appearance.colors.colSubtext
                                    }

                                    RippleButton {
                                        enabled: !parent.isLast
                                        implicitHeight: 32
                                        leftPadding: 10
                                        rightPadding: 10
                                        buttonRadius: 8
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        onClicked: store.activeAlbum = parent.segs.slice(0, parent.index + 1).join("/")
                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: parent.parent.modelData
                                            font.family: Appearance.font.family.main
                                            font.pixelSize: 14
                                            font.variableAxes: parent.parent.isLast
                                                ? ({ "wght": 660, "wdth": 100, "ROND": 100 })
                                                : ({ "wght": 460, "wdth": 100, "ROND": 100 })
                                            color: parent.parent.isLast
                                                ? Appearance.colors.colOnSurface
                                                : Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        StyledText {
                            readonly property var segs: store.activeAlbum ? store.activeAlbum.split("/") : [""]
                            text: segs[segs.length - 1]
                            font.family: Appearance.font.family.main
                            font.pixelSize: 52
                            lineHeight: 0.9
                            font.variableAxes: ({ "wght": 760, "wdth": 42, "ROND": 100 })
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 4
                            text: root.detailItems.length === 1
                                ? Translation.tr("1 item")
                                : Translation.tr("%1 items").arg(root.detailItems.length)
                            font.family: Appearance.font.family.main
                            font.pixelSize: 22
                            font.italic: true
                            color: Appearance.colors.colPrimary
                        }
                    }

                    Flow {
                        visible: root.detailSubs.length > 0
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: root.detailSubs

                            delegate: RippleButton {
                                required property var modelData
                                implicitHeight: 36
                                leftPadding: 12
                                rightPadding: 14
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                onClicked: store.activeAlbum = modelData.path
                                contentItem: RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "folder"
                                        fill: 1
                                        iconSize: 17
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        text: `${modelData.name} · ${modelData.items.length}`
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: 13
                                        font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                            }
                        }
                    }
                }
            }

            delegate: Item {
                required property var modelData
                width: detailGrid.cellWidth
                height: detailGrid.cellHeight

                GalleryMediaTile {
                    id: albDetailTile
                    x: 0
                    y: 0
                    width: detailGrid.cellWidth - detailHost.gap
                    height: detailGrid.cellHeight - detailHost.gap
                    itemData: parent.modelData
                    store: root.store
                    isFavorite: root.store.isFav(parent.modelData.path)
                    selectionMode: root.store.selectionMode
                    selected: root.store.isSelected(parent.modelData.path)
                    videoMetaRev: root.store.videoMetaRev
                    onToggleSelectRequested: root.store.toggleSelect(parent.modelData.path)
                    onClicked: {
                        const pt = albDetailTile.mapToItem(null, 0, 0);
                        root.store.openLocalViewer(parent.modelData.path, root.detailItems, {
                            x: pt.x, y: pt.y, w: albDetailTile.width, h: albDetailTile.height,
                            thumb: albDetailTile.thumbUrl
                        });
                    }
                }
            }
        }
    }
}
