pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import qs.modules.ii.dock.utilities
import "../../../dock/utilities/UtilityFiles.js" as UtilityFiles

/*
 * Drop Shelf: a place to leave files halfway through a drag and pick them up
 * later - the same shelf as the dock's Shelf tile and the island's (FileShelf).
 * Drop files anywhere on the card. The deck (the newest file on a short stack)
 * hands every file over at once when dragged into another app; each file in
 * the list goes on its own, and a click opens it. Three footprints share the
 * pieces: 1x1 is the deck alone, 2x1 puts the files in a grid beside it, 1x2
 * lists them under it.
 */
ExpressiveCardWidget {
    id: root

    // "1x1", "2x1" or "1x2"; set by the wrappers.
    property string footprint: "1x1"
    readonly property bool wide: root.footprint === "2x1"
    readonly property bool tall: root.footprint === "1x2"
    // Empty, every footprint is the header over one big drop target.
    readonly property bool sideBySide: root.wide && root.count > 0

    designWidth: root.wide ? 492 : 240
    designHeight: root.tall ? 492 : 240

    readonly property real padding: 14
    readonly property real headerHeight: 40

    readonly property var items: FileShelf.items
    readonly property int count: FileShelf.count
    // Newest first, the way the files are shown.
    readonly property var newestFirst: root.items.slice().reverse()
    property bool dragOver: false

    function open(path) {
        if (root.actionsEnabled)
            Quickshell.execDetached(["xdg-open", path]);
    }

    DropArea {
        anchors.fill: parent
        enabled: root.actionsEnabled
        keys: ["text/uri-list"]
        onEntered: root.dragOver = true
        onExited: root.dragOver = false
        onDropped: drop => {
            root.dragOver = false;
            FileShelf.add(Array.from(drop.urls ?? []).map(url => String(url)));
            drop.accept(Qt.CopyAction);
        }
    }

    // ── Header: glyph, name, count, clear ──
    Item {
        id: header
        x: root.sideBySide ? deckBlock.x + deckBlock.width + 12 : root.padding
        y: root.padding
        width: root.designWidth - header.x - root.padding
        height: root.headerHeight
        opacity: root.dragOver ? 0 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialShape {
            id: glyphShape
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            shape: MaterialShape.Shape.Cookie7Sided
            color: WidgetColorScheme.pillFillColor
        }
        MaterialSymbol {
            anchors.centerIn: glyphShape
            text: "shelves"
            iconSize: 20
            fill: 1
            color: WidgetColorScheme.textColorOnPillFill
        }

        StyledText {
            id: titleText
            anchors.left: glyphShape.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Shelf")
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
        }

        Rectangle {
            visible: root.count > 0
            anchors.left: titleText.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, countText.implicitWidth + 14)
            height: 22
            radius: root.pill(height)
            color: WidgetColorScheme.accentColor

            StyledText {
                id: countText
                anchors.centerIn: parent
                text: String(root.count)
                color: WidgetColorScheme.onAccentColor
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.variableAxes: ({ "wght": 750, "wdth": 100, "ROND": 100 })
            }
        }

        WidgetButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.count > 0
            width: 36
            height: 36
            symbol: "clear_all"
            symbolSize: 20
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: if (root.actionsEnabled) FileShelf.clear()

            StyledToolTip {
                text: Translation.tr("Clear shelf")
            }
        }
    }

    // ── The deck: every file at once ──
    Rectangle {
        id: deckBlock
        x: root.padding
        y: root.sideBySide ? root.padding : header.y + header.height + 8
        width: root.sideBySide ? 200 : root.designWidth - root.padding * 2
        height: root.sideBySide ? root.designHeight - root.padding * 2
            : root.tall && root.count > 0 ? 190 : root.designHeight - deckBlock.y - root.padding
        radius: Appearance.rounding.large
        color: allDrag.containsMouse && root.count > 0
            ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, WidgetColorScheme.pillBgColor, 0.06)
            : WidgetColorScheme.pillBgColor
        opacity: root.dragOver ? 0 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        readonly property real card: Math.round(Math.min(deckBlock.width * 0.62, (deckBlock.height - deckCaption.height - 24) * 0.86))
        readonly property real step: Math.max(4, Math.round(deckBlock.card * 0.09))
        readonly property real cardX: (deckBlock.width - deckBlock.card) / 2 - deckBlock.step / 2
        readonly property real cardY: (deckBlock.height - deckCaption.height - 10 - deckBlock.card) / 2 + deckBlock.step / 2

        // Up to two plain cards behind the newest.
        Repeater {
            model: Math.min(2, Math.max(0, root.count - 1))
            delegate: Rectangle {
                required property int index
                readonly property int depth: index + 1
                z: -depth
                width: deckBlock.card
                height: deckBlock.card
                x: deckBlock.cardX + deckBlock.step * depth
                y: deckBlock.cardY - deckBlock.step * depth
                radius: Math.round(deckBlock.card * 0.24)
                color: ColorUtils.applyAlpha(WidgetColorScheme.accentColor, 0.5 - depth * 0.18)
            }
        }

        FileThumb {
            visible: root.count > 0
            x: deckBlock.cardX
            y: deckBlock.cardY
            width: deckBlock.card
            height: deckBlock.card
            path: FileShelf.newest
            radius: Math.round(deckBlock.card * 0.24)
            colPlate: WidgetColorScheme.pillFillColor
            colSymbol: WidgetColorScheme.textColorOnPillFill
            scale: allDrag.pressed ? 0.94 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // Empty: the shelf waiting, a square that softens under the pointer.
        Item {
            visible: root.count === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: deckBlock.cardY
            width: deckBlock.card
            height: deckBlock.card

            MaterialShape {
                anchors.fill: parent
                shape: emptyHover.hovered ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Square
                color: WidgetColorScheme.cardBgColor
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "move_to_inbox"
                iconSize: Math.round(parent.width * 0.4)
                color: WidgetColorScheme.subtextColorOnBg
            }
            HoverHandler {
                id: emptyHover
            }
        }

        StyledText {
            id: deckCaption
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: root.count === 0 ? Translation.tr("Drop files here")
                : root.count === 1 ? UtilityFiles.baseName(FileShelf.newest)
                : Translation.tr("Drag all %1").arg(root.count)
            color: root.count === 0 ? WidgetColorScheme.subtextColorOnBg : WidgetColorScheme.textColorOnBg
            font.pixelSize: Appearance.font.pixelSize.small
            font.variableAxes: ({ "wght": 620, "wdth": 92, "ROND": 100 })
        }

        FileDragArea {
            id: allDrag
            anchors.fill: parent
            enabled: root.actionsEnabled && root.count > 0
            paths: root.items
            dragIcon: root.count === 1 && UtilityFiles.isImage(FileShelf.newest) ? "image-x-generic" : "text-x-generic"
            onClicked: if (root.count === 1) root.open(FileShelf.newest)
            onDragFinished: FileShelf.dragged(allDrag.paths)
        }
    }

    // ── One file: its picture, dragged on its own, removable on hover ──
    component FileCell: Item {
        id: cell

        required property string path
        property bool showName: false
        readonly property bool hovered: cellDrag.containsMouse || removeHover.hovered

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: cell.hovered ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, WidgetColorScheme.pillBgColor, 0.06) : WidgetColorScheme.pillBgColor
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        FileThumb {
            id: cellThumb
            x: 6
            y: 6
            width: cell.showName ? cell.height - 12 : cell.width - 12
            height: cell.height - 12
            path: cell.path
            radius: Appearance.rounding.small
            colPlate: WidgetColorScheme.cardBgColor
            colSymbol: WidgetColorScheme.textColorOnBg
        }

        StyledText {
            visible: cell.showName
            anchors.left: cellThumb.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 40
            anchors.verticalCenter: parent.verticalCenter
            text: UtilityFiles.baseName(cell.path)
            elide: Text.ElideMiddle
            color: WidgetColorScheme.textColorOnBg
            font.pixelSize: Appearance.font.pixelSize.small
            font.variableAxes: ({ "wght": 560, "wdth": 95, "ROND": 100 })
        }

        FileDragArea {
            id: cellDrag
            anchors.fill: parent
            enabled: root.actionsEnabled
            paths: [cell.path]
            dragIcon: UtilityFiles.isImage(cell.path) ? "image-x-generic" : "text-x-generic"
            onClicked: root.open(cell.path)
            onDragFinished: FileShelf.dragged([cell.path])
        }

        WidgetButton {
            z: 2
            visible: cell.hovered && root.actionsEnabled
            x: cell.width - width - (cell.showName ? 12 : 4)
            y: cell.showName ? (cell.height - height) / 2 : 4
            width: 26
            height: 26
            symbol: "close"
            symbolSize: 14
            colFill: WidgetColorScheme.cardBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: FileShelf.remove(cell.path)

            HoverHandler {
                id: removeHover
            }
        }

        StyledToolTip {
            text: UtilityFiles.baseName(cell.path)
            extraVisibleCondition: !cell.showName && cellDrag.containsMouse
        }
    }

    // ── 2x1: the files in a grid beside the deck; 1x2: listed under it ──
    Flickable {
        id: listFlick
        visible: (root.wide || root.tall) && root.count > 0
        x: root.sideBySide ? deckBlock.x + deckBlock.width + 12 : root.padding
        y: root.sideBySide ? header.y + header.height + 8 : deckBlock.y + deckBlock.height + 10
        width: root.designWidth - listFlick.x - root.padding
        height: root.designHeight - listFlick.y - root.padding
        clip: true
        contentWidth: width
        contentHeight: fileGrid.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        opacity: root.dragOver ? 0 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Grid {
            id: fileGrid
            width: listFlick.width
            columns: root.wide ? 3 : 1
            spacing: 8

            readonly property real cellWidth: (fileGrid.width - fileGrid.spacing * (fileGrid.columns - 1)) / fileGrid.columns

            Repeater {
                model: root.newestFirst

                delegate: FileCell {
                    required property string modelData
                    path: modelData
                    showName: root.tall
                    width: fileGrid.cellWidth
                    height: root.tall ? 52 : fileGrid.cellWidth
                }
            }
        }
    }

    // ── Files held over the card ──
    Item {
        anchors.fill: parent
        opacity: root.dragOver ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialShape {
            id: dropShape
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -14
            width: Math.min(root.designWidth, root.designHeight) * 0.5
            height: width
            shape: MaterialShape.Shape.SoftBurst
            color: WidgetColorScheme.accentColor
        }
        MaterialSymbol {
            anchors.centerIn: dropShape
            text: "file_download"
            iconSize: Math.round(dropShape.width * 0.4)
            fill: 1
            color: WidgetColorScheme.onAccentColor
        }
        StyledText {
            anchors.top: dropShape.bottom
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("Drop to keep")
            color: WidgetColorScheme.textColorOnBg
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 650, "wdth": 95, "ROND": 100 })
        }
    }
}
