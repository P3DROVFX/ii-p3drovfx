import QtQuick
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/**
 * A file as a small picture: images as a cropped thumbnail decoded at the
 * size shown, everything else as its type symbol on a tinted plate.
 */
Item {
    id: thumb

    property string path: ""
    property real radius: ClockStyle.radiusSmall
    // Decode larger than shown when the dock lens may enlarge it.
    property real renderScale: 1
    property color colPlate: ClockStyle.colSecondaryContainer
    property color colSymbol: ClockStyle.colOnSecondaryContainer
    // A phone's or a linked PC's entry (`phone:<id>`, `pc:<fp>:<id>`): its thumbnail came
    // over the link, the original is still there.
    readonly property bool phone: FileShelf.isRemote(thumb.path)
    readonly property bool image: thumb.phone ? FileShelf.thumbUrl(thumb.path) !== "" : UtilityFiles.isImage(thumb.path)
    readonly property bool video: thumb.phone && (FileShelf.phoneItem(thumb.path)?.kind === "video" || FileShelf.pcItem(thumb.path)?.video === true)
    readonly property real fetching: thumb.phone ? FileShelf.progress(thumb.path) : -1

    Rectangle {
        anchors.fill: parent
        visible: !thumb.image || picture.status !== Image.Ready
        radius: thumb.radius
        color: thumb.colPlate

        TileSymbol {
            anchors.centerIn: parent
            text: thumb.video ? "movie" : FileShelf.isPc(thumb.path) ? UtilityFiles.symbolFor(FileShelf.name(thumb.path)) : thumb.phone ? "image" : UtilityFiles.symbolFor(thumb.path)
            iconSize: Math.round(Math.min(parent.width, parent.height) * 0.5)
            fill: 1
            color: thumb.colSymbol
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        visible: thumb.image && picture.status === Image.Ready
        radius: thumb.radius
        color: "transparent"

        Image {
            id: picture
            anchors.fill: parent
            source: !thumb.image || !thumb.path ? "" : thumb.phone ? FileShelf.thumbUrl(thumb.path) : UtilityFiles.fileUri(thumb.path)
            sourceSize: Qt.size(Math.ceil(thumb.width * Math.max(1.5, thumb.renderScale * 1.25)), Math.ceil(thumb.height * Math.max(1.5, thumb.renderScale * 1.25)))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
        }
    }

    // Not on this PC yet: a small phone mark, and a thin bar while the original comes over.
    Rectangle {
        visible: thumb.phone && thumb.width >= 40
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 4
        width: 20
        height: 20
        radius: 10
        color: ClockStyle.colSecondaryContainer
        MaterialSymbol {
            anchors.centerIn: parent
            text: thumb.video ? "play_arrow" : "smartphone"
            iconSize: 13
            fill: 1
            color: ClockStyle.colOnSecondaryContainer
        }
    }
    Rectangle {
        visible: thumb.fetching >= 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 3
        color: ClockStyle.colSecondaryContainer
        Rectangle {
            width: parent.width * Math.max(0.06, thumb.fetching)
            height: parent.height
            color: ClockStyle.colPrimary
        }
    }
}
