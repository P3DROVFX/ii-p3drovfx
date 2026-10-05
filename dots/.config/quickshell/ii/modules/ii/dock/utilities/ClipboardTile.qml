import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/**
 * Clipboard: the history of what was copied, with pins — text, images and
 * files (Cliphist). Square: the kind of the last copy (text, link, image,
 * file) on a gem. Wide: that badge, the last copy in one line and what it
 * is, with the pin count. The panel holds the pins and the history.
 */
UtilityTile {
    id: tile

    readonly property var entries: Cliphist.entries ?? []
    readonly property var pinned: Cliphist.pinnedEntries ?? []
    readonly property var latest: tile.entries.length > 0 ? tile.entries[0] : ""

    function textOf(entry) {
        return String(entry ?? "").replace(/^\s*\S+\s+/, "").trim();
    }
    function kindOf(entry) {
        if (Cliphist.entryIsImage(entry))
            return "image";
        const text = tile.textOf(entry);
        if (/^file:\/\//.test(text) || Cliphist.classifyEntry(entry) === "filepath")
            return "file";
        if (Cliphist.classifyEntry(entry) === "url")
            return "link";
        return "text";
    }
    function symbolOf(entry) {
        switch (tile.kindOf(entry)) {
        case "image": return "image";
        case "file": return UtilityFiles.symbolFor(UtilityFiles.pathFromUrl(tile.textOf(entry).split(/\r?\n/)[0]));
        case "link": return "link";
        default: return "notes";
        }
    }
    function labelOf(entry) {
        const kind = tile.kindOf(entry);
        if (kind === "image") {
            const size = String(entry).match(/(\d+)x(\d+)/);
            const format = String(entry).match(/\b(png|jpe?g|webp|gif|bmp)\b/i);
            return size ? size[1] + " × " + size[2] + (format ? " " + format[1].toUpperCase() : "") : Translation.tr("Image");
        }
        const text = tile.textOf(entry);
        if (kind === "file")
            return UtilityFiles.baseName(UtilityFiles.pathFromUrl(text.split(/\r?\n/)[0]));
        return text.replace(/\s+/g, " ");
    }

    function kindName(entry) {
        switch (tile.kindOf(entry)) {
        case "image": return Translation.tr("Image");
        case "file": return Translation.tr("File");
        case "link": return Translation.tr("Link");
        default: return Translation.tr("Text");
        }
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: tile.latest !== "" ? Translation.tr("Clipboard · %1").arg(tile.labelOf(tile.latest).substring(0, 60)) : Translation.tr("Clipboard")
    panelSubtitle: tile.pinned.length > 0 ? Translation.tr("%1 pinned · %2 in history").arg(tile.pinned.length).arg(tile.entries.length)
        : Translation.tr("%1 in history").arg(tile.entries.length)
    panelWidth: 380

    // ── Square ──────────────────────────────────────────────────────────
    TileBadge {
        anchors.centerIn: parent
        visible: !tile.wide
        width: Math.round(tile.side * 0.74)
        height: width
        renderScale: tile.renderScale
        shape: MaterialShape.Shape.Gem
        color: ClockStyle.colPrimaryContainer
        colSymbol: ClockStyle.colOnPrimaryContainer
        text: tile.latest !== "" ? tile.symbolOf(tile.latest) : "content_paste"
        iconScale: 0.48
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        anchors.rightMargin: tile.pad * 2
        visible: tile.wide
        spacing: tile.pad

        TileBadge {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Gem
            color: ClockStyle.colPrimaryContainer
            colSymbol: ClockStyle.colOnPrimaryContainer
            text: tile.latest !== "" ? tile.symbolOf(tile.latest) : "content_paste"
            iconScale: 0.48
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: tile.latest !== "" ? tile.labelOf(tile.latest) : Translation.tr("Nothing copied yet")
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.27)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            TileCaption {
                Layout.fillWidth: true
                text: (tile.latest !== "" ? tile.kindName(tile.latest) : Translation.tr("Clipboard"))
                    + (tile.pinned.length > 0 ? " · " + Translation.tr("%1 pinned").arg(tile.pinned.length) : "")
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }
    }
}
