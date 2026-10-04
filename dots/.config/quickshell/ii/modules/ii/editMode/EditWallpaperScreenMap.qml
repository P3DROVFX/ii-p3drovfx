import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The Wallpaper catalogue's screens, where they stand: each monitor drawn at
 * its place in the layout, showing its own picture, named the way a person
 * knows it (WallpaperLayout.displayName). The screen being edited wears the
 * selection ring; a click on another one moves the mode there, with the
 * catalogue open (GlobalStates.switchEditMonitor).
 *
 * Hovering another screen offers what is done between two screens: trading
 * pictures with this one, and giving it this one's framing. The screen the
 * colours come from carries the palette badge.
 */
Item {
    id: root

    // The screen the mode is on.
    property string screenName: ""

    readonly property var rects: WallpaperLayout.screenRects
    readonly property var box: WallpaperLayout.screensBox
    // The map is as wide as the panel and at most this tall; the layout is
    // scaled to fit both and centred.
    readonly property real maxHeight: 168
    readonly property real fit: root.box.width > 0 && root.box.height > 0
        ? Math.min(root.width / root.box.width, root.maxHeight / root.box.height) : 0
    readonly property real gap: 6

    implicitHeight: Math.round(root.box.height * root.fit)

    Item {
        id: canvas
        width: root.box.width * root.fit
        height: root.box.height * root.fit
        anchors.horizontalCenter: parent.horizontalCenter

        Repeater {
            model: root.rects
            delegate: ScreenTile {}
        }
    }

    component ScreenTile: Item {
        id: tile
        required property var modelData
        readonly property string name: tile.modelData.name
        readonly property bool current: tile.name === root.screenName
        readonly property bool coloursHere: WallpaperLayout.distinctWallpapers && WallpaperLayout.colourScreen === tile.name
        readonly property string picture: WallpaperLayout.sourcePathFor(tile.name)
        readonly property bool hovered: tileHover.hovered
        // Small screens get small actions; the pills keep one height.
        readonly property int actionSize: tile.height >= 76 ? 32 : 26

        x: (tile.modelData.x - root.box.x) * root.fit + root.gap / 2
        y: (tile.modelData.y - root.box.y) * root.fit + root.gap / 2
        width: tile.modelData.width * root.fit - root.gap
        height: tile.modelData.height * root.fit - root.gap

        // The selection ring (settings-expressive §3): 2.5px of primary,
        // standing 2px off the screen.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4.5
            radius: face.radius + 4.5
            color: "transparent"
            border.width: 2.5
            border.color: Appearance.colors.colPrimary
            opacity: tile.current ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        ClippingRectangle {
            id: face
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            Loader {
                anchors.fill: parent
                active: tile.picture !== "" && !Wallpapers.isVideoFile(tile.picture)
                sourceComponent: ThumbnailImage {
                    sourcePath: tile.picture
                    thumbnailService: Wallpapers
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: tile.picture === "" || Wallpapers.isVideoFile(tile.picture)
                text: Wallpapers.isVideoFile(tile.picture) ? "movie" : "monitor"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }

            // Hover scrim, as on the hero.
            Rectangle {
                anchors.fill: parent
                color: Appearance.m3colors.m3scrim
                opacity: tile.hovered && !tile.current ? 0.35 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        HoverHandler {
            id: tileHover
            cursorShape: tile.current ? Qt.ArrowCursor : Qt.PointingHandCursor
        }
        TapHandler {
            enabled: !tile.current
            onTapped: GlobalStates.switchEditMonitor(tile.name)
        }

        StyledToolTip {
            requireOverlay: false
            extraVisibleCondition: !tile.current && tile.hovered && !swapButton.hovered && !copyButton.hovered
            text: Translation.tr("Edit %1").arg(WallpaperLayout.displayName(tile.name))
        }

        // The name, bottom-left; the colour source's badge before it.
        Row {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 6
            spacing: 4
            width: Math.min(implicitWidth, tile.width - 12)

            Rectangle {
                visible: tile.coloursHere
                width: nameTag.height
                height: nameTag.height
                radius: height / 2
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "palette"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnPrimaryContainer
                }

                // A Rectangle has no `hovered` of its own, and a StyledToolTip
                // on a parent without one shows unconditionally.
                HoverHandler {
                    id: badgeHover
                }
                StyledToolTip {
                    requireOverlay: false
                    extraVisibleCondition: badgeHover.hovered
                    text: Translation.tr("The colours come from this screen's picture")
                }
            }

            Rectangle {
                id: nameTag
                width: Math.min(nameLabel.implicitWidth + 16,
                    tile.width - 12 - (tile.coloursHere ? nameTag.height + 4 : 0))
                height: 22
                radius: Appearance.rounding.full
                color: tile.current ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                StyledText {
                    id: nameLabel
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: Text.AlignVCenter
                    text: WallpaperLayout.displayName(tile.name)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: tile.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
            }
        }

        // Between this screen and the edited one, top-right; they fade in
        // with the hover (settings-expressive §2.1).
        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 4
            visible: !tile.current && opacity > 0
            opacity: tile.hovered ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            TileAction {
                id: swapButton
                size: tile.actionSize
                symbol: "swap_horiz"
                enabled: WallpaperLayout.canSwap(root.screenName, tile.name)
                tooltip: Translation.tr("Swap pictures with this screen")
                onClicked: WallpaperLayout.swapWallpapers(root.screenName, tile.name)
            }
            TileAction {
                id: copyButton
                size: tile.actionSize
                symbol: "crop"
                enabled: WallpaperLayout.canCopyFraming(root.screenName, tile.name)
                tooltip: Translation.tr("Give it this screen's position and zoom")
                onClicked: WallpaperLayout.copyFraming(root.screenName, tile.name)
            }
        }
    }

    component TileAction: RippleButton {
        id: action
        property int size: 32
        property string symbol: ""
        property string tooltip: ""
        implicitWidth: action.size
        implicitHeight: action.size
        buttonRadius: action.size / 2
        opacity: action.enabled ? 1 : 0.5
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colRipple: Appearance.colors.colSurfaceContainerHighestActive

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: action.symbol
            iconSize: Math.round(action.size * 0.55)
            color: Appearance.colors.colOnSurface
        }

        StyledToolTip {
            requireOverlay: false
            text: action.tooltip
        }
    }
}
