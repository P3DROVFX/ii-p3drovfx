import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/**
 * Screenshots: the latest captures, to drag straight to where they are needed.
 * Square: the newest capture is the tile; dragging the widget off the dock
 * hands it over. Wide: the last three side by side, each one draggable on its
 * own. A capture newer than the last look at the panel gets a primary ring.
 */
UtilityTile {
    id: tile

    readonly property string folder: {
        const chosen = String(Config.options?.dock?.utilities?.screenshots?.folder ?? "").trim();
        if (chosen.length > 0)
            return FileUtils.trimFileProtocol(chosen);
        const snips = String(Config.options?.screenSnip?.savePath ?? "").trim();
        return snips.length > 0 ? FileUtils.trimFileProtocol(snips) : FileUtils.trimFileProtocol(Directories.pictures) + "/Screenshots";
    }
    readonly property var latest: feed.recent.length > 0 ? feed.recent[0] : null
    readonly property bool panelOpen: tile.host?.panelOpen ?? false

    function markSeen() {
        if (Persistent.ready)
            Persistent.states.dockUtilities.screenshotsSeen = Date.now();
    }
    onPanelOpenChanged: if (tile.panelOpen) tile.markSeen()
    Component.onCompleted: {
        if (Persistent.ready && (Persistent.states.dockUtilities.screenshotsSeen ?? 0) <= 0)
            tile.markSeen();
    }

    function exportPaths() {
        return tile.latest ? [tile.latest.path] : [];
    }

    property alias feed: feed
    FolderFeed {
        id: feed
        folder: tile.folder
        seenAfter: Persistent.ready ? (Persistent.states.dockUtilities.screenshotsSeen ?? 0) : 0
        limit: 8
        extensions: ["png", "jpg", "jpeg", "webp", "avif"]
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: tile.latest ? Translation.tr("Screenshots · drag off the dock to use the latest") : Translation.tr("Screenshots")
    panelSubtitle: tile.folder
    panelWidth: 400
    menuActions: [
        { id: "take", icon: "screenshot_region", text: Translation.tr("Take screenshot") },
        { id: "copy", icon: "content_copy", text: Translation.tr("Copy the latest"), visible: tile.latest !== null },
        { id: "openFolder", icon: "folder_open", text: Translation.tr("Open folder") }
    ]

    function menuAction(actionId) {
        if (actionId === "take")
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "screenshot"]);
        else if (actionId === "copy" && tile.latest)
            Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", tile.latest.path]);
        else if (actionId === "openFolder")
            Quickshell.execDetached(["xdg-open", tile.folder]);
    }

    // A capture not looked at yet: a primary dot in the corner, standing on
    // a ring of the dock's colour so it reads over any picture.
    component NewDot: Rectangle {
        property real size: 8
        width: size
        height: size
        radius: size / 2
        color: ClockStyle.colPrimary
    }

    // ── Square: the newest capture is the tile ─────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        FileThumb {
            anchors.fill: parent
            visible: tile.latest !== null
            path: tile.latest?.path ?? ""
            radius: tile.radius
            renderScale: tile.renderScale
        }
        TileBadge {
            anchors.centerIn: parent
            visible: tile.latest === null
            width: Math.round(tile.side * 0.74)
            height: width
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Square
            color: ClockStyle.colSecondaryContainer
            colSymbol: ClockStyle.colOnSecondaryContainer
            text: "screenshot_region"
        }
        NewDot {
            visible: feed.newCount > 0
            size: Math.max(6, Math.round(tile.side * 0.2))
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Math.round(tile.side * 0.08)
        }
    }

    // ── Wide: the last three, each one draggable on its own ────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: Math.round(tile.pad * 0.7)
        visible: tile.wide
        spacing: Math.round(tile.pad * 0.6)

        Repeater {
            model: feed.recent.slice(0, 3)
            delegate: Item {
                id: shot
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: true
                FileThumb {
                    anchors.fill: parent
                    path: shot.modelData.path
                    radius: Math.max(4, tile.radius - Math.round(tile.pad * 0.7))
                    renderScale: tile.renderScale
                }
                NewDot {
                    visible: feed.seenAfter > 0 && shot.modelData.modified > feed.seenAfter
                    size: Math.max(6, Math.round(tile.height * 0.18))
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Math.round(tile.height * 0.08)
                }
                FileDragArea {
                    anchors.fill: parent
                    paths: [shot.modelData.path]
                    dragIcon: "image-x-generic"
                    onClicked: tile.host?.openPanel()
                }
            }
        }

        TileBadge {
            visible: feed.recent.length === 0
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Square
            color: ClockStyle.colSecondaryContainer
            colSymbol: ClockStyle.colOnSecondaryContainer
            text: "screenshot_region"
        }
        ColumnLayout {
            visible: feed.recent.length === 0
            Layout.fillWidth: true
            spacing: 0
            TileText {
                text: Translation.tr("No captures")
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.27)
                font.weight: Font.DemiBold
            }
            TileCaption {
                text: Translation.tr("Right-click to take one")
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }
    }
}
