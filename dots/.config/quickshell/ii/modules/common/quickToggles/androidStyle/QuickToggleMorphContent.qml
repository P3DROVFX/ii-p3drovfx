import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles
import qs.modules.common.functions
import "QuickToggleResize.js" as Resize

// One icon surface and one label pair survive all generic grid sizes. Only
// semantically different details (e.g. BT device/battery) dissolve in stages.
Item {
    id: root
    required property var tile
    required property var button
    readonly property real wide: tile.morphWideProgress
    readonly property real tall: tile.morphTallProgress
    readonly property real pad: tile.scaled(12)
    readonly property real detail: Resize.progress(tall, 0.28, 0.9)
    readonly property real diameter: Resize.mix(tile.baseCellHeight - tile.scaled(12),
        tile.scaled(tile.centerExpandedIcon ? Resize.mix(54, 66, wide) : Resize.mix(54, 44, wide)), tall)
    readonly property real center: tile.centerExpandedIcon ? 1 : 1 - wide
    readonly property real iconX: Resize.mix(Resize.mix((width - diameter) / 2, tile.scaled(6), wide),
        Resize.mix(tile.scaled(12), (width - diameter) / 2, center), tall)
    readonly property real iconY: Resize.mix((height - diameter) / 2,
        tile.centerExpandedIcon ? Math.max(tile.scaled(4), (height * 0.6 - diameter) / 2) : tile.scaled(12), tall)
    readonly property real labelX: Resize.mix(iconX + diameter + tile.scaled(10),
        tile.centerExpandedIcon ? tile.scaled(8) : Resize.mix(tile.scaled(8), tile.scaled(12), wide), tall)
    readonly property real labelWidth: Math.max(0, width - labelX - pad)
    readonly property real labelY: Resize.mix((height - labels.height) / 2,
        height - labels.height - tile.scaled(12), tall)
    readonly property bool differentDetails: tile.expandedTitle !== tile.name || tile.expandedStatus !== tile.statusText
    readonly property color iconColor: ColorUtils.mix(button.colIcon, tile.expandedSymbolColor, 1 - tall)

    // Keep this same surface while its geometry, size and Material shape change.
    RippleButton {
        id: iconButton
        objectName: "quickToggleSharedIcon"
        x: root.iconX
        y: root.iconY
        width: root.diameter
        height: width
        buttonRadius: width / 2
        opacity: 1
        animationsEnabled: !root.tile.editMode
        enabled: !root.tile.editMode && !root.tile.isOneByOne && !!root.tile.altAction
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colBackgroundActive: "transparent"
        onClicked: root.tile.mainAction()

        MaterialShape {
            id: iconSurface
            anchors.fill: parent
            shapeString: root.tall > 0.5 ? root.tile.expandedIconShape : "Circle"
            animation: NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Appearance.animation.elementResize.type
                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
            }
            color: ColorUtils.mix(root.tile.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3,
                root.tile.expandedSurfaceColor, 1 - root.tall)
            opacity: Resize.mix(root.tile.toggled && root.tile.hasMenu ? root.wide : 0, 1, root.tall)
        }

        QuickToggleMorphLayer {
            anchors.fill: parent
            reveal: root.tile.expandedIconComponent ? 1 - Resize.progress(root.tall, 0.05, 0.55) : 1
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(8)
            MaterialSymbol {
                visible: root.tile.backgroundIcon !== "" && !symbol.animated
                anchors.centerIn: parent
                iconSize: symbol.iconSize
                text: root.tile.backgroundIcon
                color: root.iconColor
                opacity: 0.3
            }
            QuickToggleIcon {
                id: symbol
                // A tray tile only has to be recognisable; see allowAnimated.
                allowAnimated: !root.tile.isUnused
                toggleType: root.tile.buttonData.type
                toggled: root.tile.toggled
                anchors.centerIn: parent
                iconSize: Resize.mix(Resize.mix(root.tile.scaled(24), root.tile.scaled(22), root.wide),
                    root.tile.scaled(root.tile.centerExpandedIcon ? Resize.mix(26, 28, root.wide) : Resize.mix(26, 24, root.wide)), root.tall)
                text: root.tile.buttonIcon
                fill: root.tile.toggled ? 1 : 0
                color: root.iconColor
            }
        }
        QuickToggleMorphLayer {
            anchors.fill: parent
            reveal: root.tile.expandedIconComponent ? root.detail : 0
            entering: true
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(8)
            Loader {
                anchors.fill: parent
                // A warmed custom icon survives reversal of the gesture.
                property bool warmed: false
                onVisibleChanged: { if (visible) warmed = true; }
                active: !!root.tile.expandedIconComponent && (root.tall > 0 || warmed)
                sourceComponent: root.tile.expandedIconComponent
            }
        }
    }

    QuickToggleMorphLayer {
        id: labels
        objectName: "quickToggleSharedLabels"
        x: root.labelX
        y: root.labelY
        width: root.labelWidth
        height: nameLabel.implicitHeight + statusLabel.implicitHeight
        reveal: Resize.progress(Math.max(root.wide, root.tall), 0.2, 0.85)
            * (root.differentDetails ? 1 - Resize.progress(root.tall, 0, 0.48) : 1)
        directionX: root.tile.resizeDirectionX
        directionY: root.tile.resizeDirectionY
        travel: root.tile.scaled(14)
        StyledText {
            id: nameLabel
            width: Math.min(implicitWidth, parent.width)
            x: (parent.width - width) / 2 * root.tall * root.center
            text: root.tile.name
            font.pixelSize: Resize.mix(root.tile.scaled(Appearance.font.pixelSize.smallie), root.tile.scaled(Appearance.font.pixelSize.small), root.tall * root.wide)
            font.weight: Font.DemiBold
            color: root.button.colText
            elide: Text.ElideRight
        }
        StyledText {
            id: statusLabel
            y: nameLabel.height
            width: Math.min(implicitWidth, parent.width)
            x: (parent.width - width) / 2 * root.tall * root.center
            text: root.tile.statusText
            visible: text !== ""
            font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.smaller)
            color: ColorUtils.transparentize(root.button.colText, root.tile.expandedStatusTransparency * root.tall)
            elide: Text.ElideRight
        }
    }

    QuickToggleMorphLayer {
        x: root.tile.scaled(12)
        y: height > 0 ? root.height - height - root.tile.scaled(12) : 0
        width: root.width - root.tile.scaled(24)
        height: expandedName.implicitHeight + expandedStatus.implicitHeight
        reveal: root.differentDetails ? Resize.progress(root.tall, 0.48, 0.95) : 0
        entering: true
        directionX: root.tile.resizeDirectionX
        directionY: root.tile.resizeDirectionY
        travel: root.tile.scaled(14)
        StyledText {
            id: expandedName
            width: parent.width
            text: root.tile.expandedTitle
            font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.small)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnLayer2
            elide: Text.ElideRight
        }
        QuickToggleMorphLayer {
            y: expandedName.height
            width: parent.width
            height: expandedStatus.implicitHeight
            reveal: Resize.progress(root.tall, 0.6, 1)
            entering: true
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(8)
            StyledText {
                id: expandedStatus
                width: parent.width
                text: root.tile.expandedStatus
                visible: text !== ""
                font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.smaller)
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }
}
