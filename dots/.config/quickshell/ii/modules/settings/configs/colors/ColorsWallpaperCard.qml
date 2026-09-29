import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One wallpaper target as a picture card. The desktop card is the page's hero: the
 * image fills it, with its name and a filled "Change wallpaper" action on top. The
 * lock screen and light-mode cards show their own image once they have one; until
 * then they are an invitation — an expressive shape that morphs on hover — and the
 * whole card turns the separate wallpaper on and opens the picker.
 */
Item {
    id: root

    /// "desktop", "lockscreen" or "lightmode".
    property string targetMode: "desktop"
    property string title: ""
    property string symbol: "wallpaper"
    /// False while the target just follows the desktop wallpaper.
    property bool isSet: true
    property bool hero: false
    property string emptyHint: ""
    property var emptyShape: MaterialShape.Shape.Cookie7Sided
    property var emptyShapeHover: MaterialShape.Shape.Cookie12Sided
    property string swapTooltip: ""

    signal pickRequested()
    signal swapRequested()
    signal removeRequested()

    readonly property real cardRadius: Appearance.rounding.verylarge
    readonly property bool engaged: cardHover.hovered || swapButton.activeFocus || removeButton.activeFocus
    readonly property bool compact: root.height < 150 || root.width < 220

    HoverHandler {
        id: cardHover
    }

    // ── Picture ─────────────────────────────────────────────────────────
    ClippingRectangle {
        anchors.fill: parent
        visible: root.isSet
        radius: root.cardRadius
        color: Appearance.colors.colLayer1

        ColorsWallpaperImage {
            id: picture
            anchors.fill: parent
            targetMode: root.targetMode
        }

        // Darkens slightly under the pointer so the card reads as pressable.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
            opacity: root.engaged ? 0.35 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        RippleButton {
            anchors.fill: parent
            buttonRadius: root.cardRadius
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.3)
            onClicked: root.pickRequested()
        }
    }

    // ── Name tag ────────────────────────────────────────────────────────
    Rectangle {
        id: tag
        visible: root.isSet
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: root.hero ? 16 : 12
        }
        width: Math.min(tagRow.implicitWidth + 24, parent.width - anchors.margins * 2
            - (root.hero ? changeButton.width + 12 : 0))
        height: root.hero ? 40 : 32
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHigh

        RowLayout {
            id: tagRow
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 14
            }
            spacing: 6

            MaterialSymbol {
                text: root.symbol
                iconSize: root.hero ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.normal
                fill: 1
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: root.title
                font.pixelSize: root.hero ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.hero && picture.fileName.length > 0
                text: picture.fileName
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideMiddle
            }
        }
    }

    // ── Hero action ─────────────────────────────────────────────────────
    RippleButton {
        id: changeButton
        visible: root.hero
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 16
        }
        // Same height as the name tag across the image, so the two read as a pair.
        implicitHeight: tag.height
        implicitWidth: root.width < 420 ? implicitHeight : changeRow.implicitWidth + 36
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.normal
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        onClicked: root.pickRequested()

        contentItem: Item {
            RowLayout {
                id: changeRow
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    text: "imagesmode"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnPrimary
                }
                StyledText {
                    visible: root.width >= 420
                    text: Translation.tr("Change wallpaper")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        StyledToolTip {
            text: Translation.tr("Change wallpaper")
            extraVisibleCondition: root.width < 420
        }
    }

    // The palette the wallpaper produced, as a strip of the current accents.
    Rectangle {
        visible: root.hero
        anchors {
            top: parent.top
            right: parent.right
            margins: 16
        }
        width: paletteRow.implicitWidth + 16
        height: 40
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHigh

        Row {
            id: paletteRow
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: [Appearance.colors.colPrimary, Appearance.colors.colSecondary,
                    Appearance.colors.colTertiary, Appearance.colors.colPrimaryContainer]

                Rectangle {
                    required property color modelData
                    width: 24
                    height: 24
                    radius: 12
                    color: modelData
                }
            }
        }

    }

    // Wallpaper Engine is what the desktop shows: say so, on the image.
    Rectangle {
        visible: root.hero && picture.usesWallpaperEngine
        anchors {
            top: parent.top
            left: parent.left
            margins: 16
        }
        width: wpeRow.implicitWidth + 24
        height: 32
        radius: height / 2
        color: Appearance.colors.colTertiaryContainer

        RowLayout {
            id: wpeRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                text: "play_circle"
                iconSize: Appearance.font.pixelSize.normal
                fill: 1
                color: Appearance.colors.colOnTertiaryContainer
            }
            StyledText {
                text: Translation.tr("Wallpaper Engine")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnTertiaryContainer
            }
        }
    }

    // ── Hover actions of a variant ──────────────────────────────────────
    Row {
        visible: root.isSet && !root.hero
        anchors {
            top: parent.top
            right: parent.right
            margins: 10
        }
        spacing: 6
        opacity: root.engaged ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        CardIconButton {
            id: swapButton
            symbol: "swap_horiz"
            tooltip: root.swapTooltip
            onClicked: root.swapRequested()
        }
        CardIconButton {
            id: removeButton
            symbol: "close"
            tooltip: Translation.tr("Use the desktop wallpaper")
            onClicked: root.removeRequested()
        }
    }

    // ── Not set yet ─────────────────────────────────────────────────────
    RippleButton {
        id: emptyCard
        anchors.fill: parent
        visible: !root.isSet
        buttonRadius: root.cardRadius
        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        onClicked: root.pickRequested()

        contentItem: Item {
            GridLayout {
                anchors.centerIn: parent
                width: parent.width - 32
                columns: root.compact ? 2 : 1
                columnSpacing: 12
                rowSpacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: root.compact ? Qt.AlignVCenter : Qt.AlignHCenter
                    text: root.symbol
                    iconSize: root.compact ? 20 : 24
                    padding: root.compact ? 10 : 14
                    fill: 1
                    shape: emptyCard.hovered ? root.emptyShapeHover : root.emptyShape
                    color: emptyCard.hovered ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                    colSymbol: emptyCard.hovered ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: root.compact ? Text.AlignLeft : Text.AlignHCenter
                        text: root.title
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: root.compact ? Text.AlignLeft : Text.AlignHCenter
                        text: root.emptyHint
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    component CardIconButton: RippleButton {
        id: iconButton
        property string symbol: ""
        property string tooltip: ""
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.small
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colRipple: Appearance.colors.colSurfaceContainerHighestActive

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: iconButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurface
        }

        StyledToolTip {
            text: iconButton.tooltip
        }
    }
}
