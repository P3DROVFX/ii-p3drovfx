import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/**
 * Files: the Downloads folder, or the one chosen in Settings — what arrived
 * last and how many are new since the panel was last opened. Square: the
 * folder glyph on a four-sided cookie; with new files the tile turns primary
 * and the count replaces the glyph. Wide: the newest file's picture, its name,
 * "3 new · 5 min ago". Dragging the widget off the dock hands the newest file
 * over.
 */
UtilityTile {
    id: tile

    readonly property string folder: {
        const chosen = String(Config.options?.dock?.utilities?.files?.folder ?? "").trim();
        return FileUtils.trimFileProtocol(chosen.length > 0 ? chosen : Directories.downloads);
    }
    readonly property bool isDownloads: tile.folder === FileUtils.trimFileProtocol(Directories.downloads)
    readonly property string folderName: UtilityFiles.baseName(tile.folder) || tile.folder
    readonly property var latest: feed.recent.length > 0 ? feed.recent[0] : null
    readonly property int newCount: feed.newCount
    readonly property bool fresh: tile.newCount > 0
    readonly property date now: DateTime.clock.date
    readonly property bool panelOpen: tile.host?.panelOpen ?? false

    function markSeen() {
        if (Persistent.ready)
            Persistent.states.dockUtilities.filesSeen = Date.now();
    }
    onPanelOpenChanged: if (tile.panelOpen) tile.markSeen()
    Component.onCompleted: {
        if (Persistent.ready && (Persistent.states.dockUtilities.filesSeen ?? 0) <= 0)
            tile.markSeen();
    }

    function exportPaths() {
        return tile.latest ? [tile.latest.path] : [];
    }

    property alias feed: feed
    FolderFeed {
        id: feed
        folder: tile.folder
        seenAfter: Persistent.ready ? (Persistent.states.dockUtilities.filesSeen ?? 0) : 0
        limit: 9
    }

    surfaceColor: tile.fresh ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
    contentColor: tile.fresh ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

    tooltipText: tile.latest
        ? Translation.tr("%1 · newest: %2").arg(tile.folderName).arg(tile.latest.name)
        : tile.folderName
    panelSubtitle: tile.folder
    panelWidth: 380
    menuActions: [
        { id: "openFolder", icon: "folder_open", text: Translation.tr("Open folder") },
        { id: "openLatest", icon: "open_in_new", text: Translation.tr("Open newest file"), visible: tile.latest !== null }
    ]
    function menuAction(actionId) {
        if (actionId === "openFolder")
            Quickshell.execDetached(["xdg-open", tile.folder]);
        else if (actionId === "openLatest" && tile.latest)
            Quickshell.execDetached(["xdg-open", tile.latest.path]);
    }

    // ── Square ──────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        TileBadge {
            anchors.centerIn: parent
            width: Math.round(tile.side * 0.74)
            height: width
            renderScale: tile.renderScale
            shape: tile.fresh ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Cookie4Sided
            color: tile.fresh ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
            colSymbol: ClockStyle.colOnSecondaryContainer
            text: tile.fresh ? "" : (tile.isDownloads ? "download" : "folder")
            iconScale: 0.5
        }
        TileValue {
            anchors.centerIn: parent
            visible: tile.fresh
            text: tile.newCount > 99 ? "99+" : String(tile.newCount)
            color: ClockStyle.colOnPrimary
            font.pixelSize: Math.round(tile.side * (text.length > 2 ? 0.26 : 0.34))
        }
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        anchors.rightMargin: tile.pad * 2
        visible: tile.wide
        spacing: tile.pad

        Item {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            FileThumb {
                anchors.fill: parent
                visible: tile.latest !== null
                path: tile.latest?.path ?? ""
                radius: Math.max(4, tile.radius - tile.pad)
                renderScale: tile.renderScale
                colPlate: tile.fresh ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                colSymbol: tile.fresh ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
            }
            TileBadge {
                anchors.fill: parent
                visible: tile.latest === null
                renderScale: tile.renderScale
                shape: MaterialShape.Shape.Cookie4Sided
                color: ClockStyle.colSecondaryContainer
                colSymbol: ClockStyle.colOnSecondaryContainer
                text: tile.isDownloads ? "download" : "folder"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: tile.latest ? tile.latest.name : Translation.tr("%1 is empty").arg(tile.folderName)
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.27)
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
            TileCaption {
                Layout.fillWidth: true
                text: !tile.latest ? tile.folderName
                    : (tile.fresh ? Translation.tr("%1 new").arg(tile.newCount) + " · " : "")
                        + UtilityFiles.age(tile.latest.modified, tile.now.getTime(), s => Translation.tr(s))
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }
    }
}
