import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles
import qs.modules.common.functions

// Material 3 Expressive faces for the generic quick toggle (sidebar setting
// `quickToggles.expressive`). Each footprint gets its own idea, and no idea is
// used twice: the size is a design decision, not just more room for the same one.
//
//   orb      0x1   the tile *is* a Material shape; toggling morphs the polygon
//   pill     1x1   a switch: the icon rides a thumb across the track
//   type     2x1   type carries the state: the status line goes thin -> heavy
//                  (+ a level, as a cut scalloped shape, when there is one)
//   chip     3+x1  the state lives in a status chip that grows with its label
//   column   1x2   a level rises from the bottom (volume, battery, signal, on/off)
//   spine    1x3+  the name runs up the tile in slanted condensed type
//   ornament 2x2   a big clipped shape slides in behind the content
//   poster   2x3+  the name (or the reading) set as a poster, re-dealt on toggle
//   split    3+x2+ an icon block that turns circle -> rounded square
//
// The bigger designs that have a dialog show it as a thin ring with a ↗ arrow.
// A click on a tile with a dialog opens it; switching the toggle itself is the
// PowerSpot, a circle that appears under the pointer on the icon.
Item {
    id: root
    required property var tile
    required property var button

    readonly property string variant: tile.expressiveVariant
    readonly property bool isOn: tile.toggled
    readonly property bool hovered: tile.hovered
    readonly property string heroValue: tile.toggleModel?.heroValue ?? ""
    readonly property string heroUnit: tile.toggleModel?.heroUnit ?? ""
    readonly property real heroLevel: tile.toggleModel?.heroLevel ?? -1
    readonly property bool hasHero: heroValue !== ""
    readonly property bool sharp: Config.options.appearance.sharpMode

    function s(value) {
        return Math.round(tile.scaled(value));
    }

    // A shape that belongs to the toggle, so two orbs side by side differ.
    readonly property var signatureShapes: ["Cookie7Sided", "SoftBurst", "Clover4Leaf", "Sunny", "Cookie9Sided", "Puffy", "Flower", "Gem", "Cookie6Sided", "Clover8Leaf", "PuffyDiamond", "SoftBoom"]
    readonly property string signatureShape: {
        const type = tile.buttonData?.type ?? "";
        let hash = 0;
        for (let i = 0; i < type.length; i++)
            hash = (hash * 31 + type.charCodeAt(i)) | 0;
        return signatureShapes[Math.abs(hash) % signatureShapes.length];
    }

    // Static axes. Only `type` interpolates, and only through blend().
    readonly property var axesCaption: ({ "wght": 700, "wdth": 100, "ROND": 100 })
    readonly property var axesCondensed: ({ "wght": 560, "wdth": 80, "ROND": 100 })
    readonly property var axesPoster: ({ "wght": 820, "wdth": 28, "ROND": 40 })
    readonly property var axesDigitsBold: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var axesDigitsThin: ({ "wght": 260, "wdth": 50, "ROND": 100 })
    readonly property var axesWide: ({ "wght": 640, "wdth": 122, "ROND": 100 })
    readonly property var axesExtended: ({ "wght": 820, "wdth": 140, "ROND": 100 })
    readonly property var axesCompressed: ({ "wght": 760, "wdth": 68, "ROND": 100 })
    readonly property var axesGrotesk: ({ "wght": 700 })
    readonly property var axesSpine: ({ "wght": 680, "wdth": 62, "ROND": 0, "slnt": -10 })

    opacity: tile.available || tile.editMode ? 1 : 0.45

    // A new face arrives with a short fade instead of popping in.
    Loader {
        id: faceLoader
        anchors.fill: parent
        sourceComponent: {
            switch (root.variant) {
            case "orb": return orbFace;
            case "pill": return pillFace;
            case "type": return typeFace;
            case "chip": return chipFace;
            case "column": return columnFace;
            case "spine": return spineFace;
            case "ornament": return ornamentFace;
            case "poster": return posterFace;
            default: return splitFace;
            }
        }
        onLoaded: faceFade.restart()
    }
    NumberAnimation {
        id: faceFade
        target: faceLoader
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration
        easing.type: Easing.OutCubic
    }

    // ------------------------------------------------------------------ shared

    component Icon: QuickToggleIcon {
        allowAnimated: !root.tile.isUnused
        toggleType: root.tile.buttonData.type
        toggled: root.isOn
        text: root.tile.buttonIcon
        fill: root.isOn ? 1 : 0
    }

    // Hover target on the icon that switches the toggle without opening the dialog.
    // Declared before the icon it centres on, so the icon draws over the tint.
    component PowerSpot: Item {
        id: spot
        property real size: root.s(40)
        property color ink: Appearance.colors.colOnLayer2
        readonly property bool hovered: spotHover.hovered && !root.tile.editMode
        width: size
        height: size

        Rectangle {
            anchors.fill: parent
            radius: root.sharp ? Appearance.rounding.unsharpen : width / 2
            color: ColorUtils.transparentize(spot.ink, spotArea.pressed ? 0.7 : 0.82)
            opacity: spot.hovered ? 1 : 0
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }
        HoverHandler {
            id: spotHover
            enabled: !root.tile.editMode
            cursorShape: Qt.PointingHandCursor
        }
        MouseArea {
            id: spotArea
            anchors.fill: parent
            enabled: !root.tile.editMode && root.tile.available
            // A MouseArea sets its own cursor (arrow by default) over the HoverHandler's.
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tile.mainAction()
        }
        StyledToolTip {
            extraVisibleCondition: root.tile.hasMenu
            text: root.isOn ? Translation.tr("Turn off") : Translation.tr("Turn on")
        }
    }

    component DialogArrow: RippleButton {
        id: arrow
        property color contentColor
        width: root.s(30)
        height: width
        buttonRadius: width / 2
        visible: root.tile.expressiveDialogArrow
        enabled: !root.tile.editMode
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(arrow.contentColor, 0.88)
        colRipple: ColorUtils.transparentize(arrow.contentColor, 0.76)
        onClicked: root.tile.altAction()

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: ColorUtils.transparentize(arrow.contentColor, 0.45)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_outward"
            iconSize: root.s(16)
            color: arrow.contentColor
        }
    }

    // --------------------------------------------------------------------- orb

    Component {
        id: orbFace
        Item {
            MaterialShape {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                shapeString: root.isOn ? root.signatureShape : (root.hovered ? "Cookie12Sided" : "Circle")
                color: root.isOn ? (root.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                    : (root.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
            PowerSpot {
                anchors.centerIn: parent
                size: Math.round(Math.min(parent.width, parent.height) * 0.72)
                ink: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
            Icon {
                anchors.centerIn: parent
                iconSize: root.s(22)
                color: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }
    }

    // -------------------------------------------------------------------- pill

    Component {
        id: pillFace
        Item {
            id: pill
            readonly property real pad: root.s(6)
            readonly property real slot: height - pad * 2
            readonly property real thumbSize: root.isOn ? slot : Math.round(slot * 0.78)
            readonly property real labelSpace: width - slot - pad * 2 - root.s(14)

            Rectangle {
                id: thumb
                width: pill.thumbSize
                height: width
                radius: root.sharp ? 0 : width / 2
                x: root.isOn ? pill.width - pill.pad - pill.slot + (pill.slot - width) / 2
                           : pill.pad + (pill.slot - width) / 2
                y: (pill.height - height) / 2
                color: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colLayer3
                Behavior on x { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                Behavior on width { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                PowerSpot {
                    anchors.centerIn: parent
                    size: Math.min(pill.height, pill.slot + root.s(8))
                    ink: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
                Icon {
                    anchors.centerIn: parent
                    iconSize: root.s(20)
                    color: root.isOn ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
            }

            StyledText {
                visible: pill.labelSpace >= root.s(44)
                width: pill.labelSpace
                x: root.isOn ? pill.pad + root.s(8) : pill.pad + pill.slot + root.s(6)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: root.isOn ? Text.AlignLeft : Text.AlignRight
                text: root.tile.name
                elide: Text.ElideRight
                font.pixelSize: root.s(Appearance.font.pixelSize.smallie)
                font.variableAxes: root.axesCondensed
                color: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                Behavior on x { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }
    }

    // -------------------------------------------------------------------- type

    Component {
        id: typeFace
        Item {
            id: typeItem
            readonly property real pad: root.s(16)
            readonly property color ink: root.isOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
            property real boldness: root.isOn ? 1 : 0
            Behavior on boldness {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            readonly property bool hasLevel: root.heroLevel >= 0
            readonly property real level: Math.max(0, Math.min(1, root.heroLevel))

            // Progress: a scalloped shape far bigger than the tile, cut by the tile's
            // outline, whose right edge stands at the level. It turns a quarter over
            // the whole range, so the scallops along the edge move with the value.
            // Tinted with the ink, so the text reads the same over it and beside it.
            Rectangle {
                id: typeMask
                anchors.fill: parent
                radius: root.button.buttonRadius
                visible: false
                layer.enabled: true
            }
            // A full level is the whole tile anyway: the shape fades out instead of
            // drawing an edge that no longer marks anything.
            Item {
                anchors.fill: parent
                opacity: typeItem.level >= 0.995 ? 0 : 1
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                visible: typeItem.hasLevel && opacity > 0
                layer.enabled: visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: typeMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
                MaterialShape {
                    readonly property real size: Math.round(Math.max(typeItem.width * 1.25, typeItem.height * 4))
                    property real shownLevel: typeItem.level
                    Behavior on shownLevel {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    width: size
                    height: size
                    x: typeItem.width * shownLevel - size
                    y: (typeItem.height - size) / 2
                    rotation: shownLevel * 90
                    shapeString: "Cookie12Sided"
                    color: ColorUtils.transparentize(typeItem.ink, root.isOn ? 0.84 : 0.9)
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }

            PowerSpot {
                anchors.centerIn: typeIcon
                ink: typeItem.ink
            }
            Icon {
                id: typeIcon
                x: typeItem.pad
                anchors.verticalCenter: parent.verticalCenter
                iconSize: root.s(24)
                color: typeItem.ink
            }
            Column {
                x: typeIcon.x + typeIcon.width + root.s(12)
                width: typeItem.width - x - typeItem.pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: -root.s(2)
                StyledText {
                    width: parent.width
                    text: root.tile.name.toUpperCase()
                    elide: Text.ElideRight
                    font.pixelSize: root.s(Appearance.font.pixelSize.smallest)
                    font.letterSpacing: 0.8
                    font.variableAxes: root.axesCaption
                    color: typeItem.ink
                    opacity: 0.72
                }
                StyledText {
                    width: parent.width
                    text: root.hasHero ? root.heroValue + root.heroUnit : root.tile.statusText
                    elide: Text.ElideRight
                    font.pixelSize: root.s(Appearance.font.pixelSize.larger)
                    font.variableAxes: ({
                        "wght": Appearance.font.variableAxes.blend(300, 780, typeItem.boldness),
                        "wdth": Appearance.font.variableAxes.blend(62, 100, typeItem.boldness),
                        "ROND": 100
                    })
                    color: typeItem.ink
                }
            }
        }
    }

    // -------------------------------------------------------------------- chip

    Component {
        id: chipFace
        Item {
            id: chipItem
            readonly property real pad: root.s(8)

            Rectangle {
                id: chipBadge
                x: chipItem.pad
                width: chipItem.height - chipItem.pad * 2
                height: width
                anchors.verticalCenter: parent.verticalCenter
                radius: root.sharp ? 0 : Appearance.rounding.normal
                color: Appearance.colors.colSecondaryContainer
                PowerSpot {
                    anchors.fill: parent
                    ink: Appearance.colors.colOnSecondaryContainer
                }
                Icon {
                    anchors.centerIn: parent
                    iconSize: root.s(22)
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            Column {
                x: chipBadge.x + chipBadge.width + root.s(12)
                width: chip.x - x - root.s(10)
                anchors.verticalCenter: parent.verticalCenter
                StyledText {
                    width: parent.width
                    text: root.tile.name
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.s(Appearance.font.pixelSize.normal)
                    font.variableAxes: root.axesWide
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    width: parent.width
                    visible: text !== "" && root.hasHero
                    text: root.tile.statusText
                    elide: Text.ElideRight
                    font.pixelSize: root.s(Appearance.font.pixelSize.smaller)
                    color: Appearance.colors.colSubtext
                }
            }

            TextMetrics {
                id: chipMetrics
                font.family: Appearance.font.family.main
                font.pixelSize: root.s(Appearance.font.pixelSize.smallie)
                font.weight: Font.DemiBold
                text: chip.label
            }
            Rectangle {
                id: chip
                readonly property string label: root.hasHero ? root.heroValue + root.heroUnit
                    : (root.isOn ? (root.tile.statusText || Translation.tr("On")) : Translation.tr("Off"))
                readonly property real checkSpace: root.isOn ? root.s(16) + root.s(4) : 0
                width: Math.round(Math.min(chipMetrics.advanceWidth + checkSpace + root.s(24), chipItem.width * 0.5))
                height: root.s(32)
                x: chipItem.width - width - root.s(12)
                anchors.verticalCenter: parent.verticalCenter
                radius: root.sharp ? 0 : height / 2
                color: root.isOn ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                Behavior on width { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                MaterialSymbol {
                    x: root.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "check"
                    iconSize: root.s(16)
                    color: Appearance.colors.colOnPrimary
                    opacity: root.isOn ? 1 : 0
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
                StyledText {
                    x: root.s(12) + chip.checkSpace
                    width: chip.width - x - root.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.label
                    elide: Text.ElideRight
                    font.pixelSize: root.s(Appearance.font.pixelSize.smallie)
                    font.weight: Font.DemiBold
                    color: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                }
            }
        }
    }

    // ------------------------------------------------------------------ column

    Component {
        id: columnFace
        Item {
            id: column
            readonly property real pad: root.s(12)
            readonly property real level: root.heroLevel >= 0
                ? Math.max(0.1, Math.min(1, root.heroLevel)) : (root.isOn ? 1 : 0)
            readonly property real fillTop: height - fill.height
            readonly property real radius: root.button.buttonRadius

            // A level reads under a text when it covers the text's middle.
            function inkAt(item) {
                const covered = column.fillTop < item.y + item.height / 2;
                if (!covered)
                    return Appearance.colors.colOnLayer2;
                return root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3;
            }

            Rectangle {
                id: fill
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.round(parent.height * column.level)
                radius: root.sharp ? 0 : Math.min(column.radius, height / 2)
                color: root.isOn ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                Behavior on height {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }

            PowerSpot {
                anchors.centerIn: columnIcon
                ink: column.inkAt(columnIcon)
            }
            Icon {
                id: columnIcon
                x: column.pad
                y: column.pad
                iconSize: root.s(24)
                color: column.inkAt(columnIcon)
            }

            Row {
                id: columnHero
                visible: root.hasHero
                x: column.pad
                anchors.bottom: columnName.top
                StyledText {
                    text: root.heroValue
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.s(30)
                    font.variableAxes: root.axesDigitsBold
                    color: column.inkAt(columnHero)
                }
                StyledText {
                    text: root.heroUnit
                    font.pixelSize: root.s(Appearance.font.pixelSize.smaller)
                    font.weight: Font.Bold
                    color: column.inkAt(columnHero)
                }
            }

            StyledText {
                id: columnName
                x: column.pad
                width: column.width - column.pad * 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: column.pad
                text: root.tile.name
                wrapMode: Text.Wrap
                maximumLineCount: root.hasHero ? 1 : 2
                elide: Text.ElideRight
                lineHeight: 0.9
                font.family: Appearance.font.family.main
                font.pixelSize: root.s(root.hasHero ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.larger)
                font.variableAxes: root.hasHero ? root.axesCaption : root.axesCompressed
                color: column.inkAt(columnName)
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }
    }

    // ------------------------------------------------------------------- spine

    Component {
        id: spineFace
        Item {
            id: spine
            readonly property real pad: root.s(10)
            readonly property real run: height - badge.y - badge.height - pad * 2

            Rectangle {
                id: badge
                width: spine.width - spine.pad * 2
                height: width
                x: spine.pad
                y: spine.pad
                radius: root.sharp ? 0 : width / 2
                color: root.isOn ? Appearance.colors.colTertiary : Appearance.colors.colLayer3
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                PowerSpot {
                    anchors.fill: parent
                    ink: root.isOn ? Appearance.colors.colOnTertiary : Appearance.colors.colOnLayer3
                }
                Icon {
                    anchors.centerIn: parent
                    iconSize: root.s(26)
                    color: root.isOn ? Appearance.colors.colOnTertiary : Appearance.colors.colOnLayer3
                }
            }

            // Two rotated lines when the name has two words or more, so a long name
            // grows instead of shrinking to fit one line along a short run.
            readonly property var words: root.tile.name.split(/\s+/).filter(word => word.length > 0)
            readonly property int split: Math.ceil(words.length / 2)
            readonly property string lineA: words.length > 1 ? words.slice(0, split).join(" ") : root.tile.name
            readonly property string lineB: words.length > 1 ? words.slice(split).join(" ") : ""
            readonly property int lines: lineB === "" ? 1 : 2
            readonly property real across: width - pad * 2

            TextMetrics {
                id: spineMetricsA
                font.family: Appearance.font.family.main
                font.pixelSize: 100
                font.variableAxes: root.axesSpine
                text: spine.lineA
            }
            TextMetrics {
                id: spineMetricsB
                font.family: Appearance.font.family.main
                font.pixelSize: 100
                font.variableAxes: root.axesSpine
                text: spine.lineB
            }

            // Read bottom to top, sized so the longer line spans the free run.
            StyledText {
                readonly property real longest: Math.max(spineMetricsA.advanceWidth, spine.lines > 1 ? spineMetricsB.advanceWidth : 0) / 100
                width: spine.run
                rotation: -90
                transformOrigin: Item.Center
                x: (spine.width - width) / 2
                y: badge.y + badge.height + spine.pad + (spine.run - height) / 2
                text: spine.lines > 1 ? spine.lineA + "\n" + spine.lineB : spine.lineA
                clip: true
                lineHeight: 0.86
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                font.family: Appearance.font.family.main
                font.pixelSize: longest > 0
                    ? Math.max(10, Math.floor(Math.min(spine.run / longest, spine.across * 0.8 / (spine.lines * 0.86)))) : 10
                font.variableAxes: root.axesSpine
                color: root.isOn ? Appearance.colors.colOnTertiaryContainer : ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.35)
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }
    }

    // ---------------------------------------------------------------- ornament

    Component {
        id: ornamentFace
        Item {
            id: ornament
            readonly property real pad: root.s(14)
            readonly property color ink: root.isOn ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

            // The shape parks off the right edge and slides in when the toggle turns
            // on. Clipped by the tile's own outline, never by a rectangle.
            Rectangle {
                id: ornamentMask
                anchors.fill: parent
                radius: root.button.buttonRadius
                visible: false
                layer.enabled: true
            }
            Item {
                id: ornamentArt
                anchors.fill: parent
                opacity: root.isOn ? 0.14 : 0.06
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: ornamentMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
                MaterialShape {
                    readonly property real size: Math.round(ornament.height * 1.9)
                    width: size
                    height: size
                    x: ornament.width - size * (root.isOn ? 0.62 : 0.38)
                    y: (ornament.height - size) / 2
                    shapeString: root.signatureShape
                    color: ornament.ink
                    Behavior on x {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }

            PowerSpot {
                anchors.centerIn: ornamentIcon
                size: root.s(48)
                ink: ornament.ink
            }
            Icon {
                id: ornamentIcon
                x: ornament.pad
                y: ornament.pad
                iconSize: root.s(30)
                color: ornament.ink
            }
            DialogArrow {
                x: ornament.width - width - ornament.pad + root.s(4)
                y: ornament.pad - root.s(4)
                contentColor: ornament.ink
            }
            Column {
                x: ornament.pad
                width: ornament.width - ornament.pad * 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: ornament.pad
                // Fitted by the text itself: TextMetrics measures without the axes.
                StyledText {
                    width: parent.width
                    height: root.s(34)
                    text: root.tile.name
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignBottom
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: root.s(15)
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.s(30)
                    font.variableAxes: root.axesExtended
                    color: ornament.ink
                }
                StyledText {
                    width: parent.width
                    visible: text !== ""
                    text: root.hasHero ? root.heroValue + root.heroUnit + " · " + root.tile.statusText : root.tile.statusText
                    elide: Text.ElideRight
                    font.pixelSize: root.s(Appearance.font.pixelSize.smaller)
                    color: ornament.ink
                    opacity: 0.7
                }
            }
        }
    }

    // ------------------------------------------------------------------ poster

    Component {
        id: posterFace
        Item {
            id: poster
            readonly property real pad: root.s(16)
            readonly property color ink: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            readonly property var lines: root.hasHero ? [root.heroValue]
                : root.tile.name.toUpperCase().split(/\s+/).filter(word => word.length > 0).slice(0, 3)
            readonly property real stageTop: posterIcon.y + posterIcon.height + root.s(8)
            readonly property real stageHeight: posterFooter.y - stageTop - root.s(6)

            PowerSpot {
                anchors.centerIn: posterIcon
                size: root.s(38)
                ink: poster.ink
            }
            Icon {
                id: posterIcon
                x: poster.pad
                y: poster.pad
                iconSize: root.s(22)
                color: poster.ink
            }
            DialogArrow {
                x: poster.width - width - poster.pad + root.s(4)
                y: poster.pad - root.s(4)
                contentColor: poster.ink
            }

            Column {
                x: poster.pad
                y: poster.stageTop
                width: poster.width - poster.pad * 2
                Repeater {
                    model: poster.lines
                    delegate: Item {
                        id: line
                        required property string modelData
                        required property int index
                        width: parent.width
                        height: Math.floor(poster.stageHeight / poster.lines.length)
                        clip: true

                        // On every toggle the lines re-deal from below, one after another.
                        property real deal: 0
                        Connections {
                            target: root
                            function onIsOnChanged() { dealIn.restart(); }
                        }
                        SequentialAnimation {
                            id: dealIn
                            PropertyAction { target: line; property: "deal"; value: 1 }
                            PauseAnimation { duration: Appearance.reducedMotion ? 0 : line.index * 60 }
                            NumberAnimation {
                                target: line
                                property: "deal"
                                to: 0
                                duration: Appearance.reducedMotion ? 0 : Appearance.animation.elementMove.duration
                                easing.type: Easing.OutBack
                            }
                        }

                        TextMetrics {
                            id: lineMetrics
                            font.family: Appearance.font.family.main
                            font.pixelSize: 100
                            font.variableAxes: root.hasHero ? root.axesDigitsBold : root.axesPoster
                            text: line.modelData
                        }
                        StyledText {
                            readonly property real inkW: lineMetrics.tightBoundingRect.width / 100
                            readonly property real inkH: lineMetrics.tightBoundingRect.height / 100
                            x: -lineMetrics.tightBoundingRect.x / 100 * font.pixelSize
                            anchors.baseline: parent.bottom
                            transform: Translate { y: line.deal * line.height * 0.6 }
                            opacity: 1 - line.deal * 0.8
                            text: line.modelData
                            font.family: Appearance.font.family.main
                            font.pixelSize: inkW > 0 && inkH > 0
                                ? Math.max(10, Math.floor(Math.min(line.width / inkW, (line.height - root.s(4)) / inkH))) : 10
                            font.variableAxes: root.hasHero ? root.axesDigitsBold : root.axesPoster
                            color: poster.ink
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }
                    }
                }
            }

            Column {
                id: posterFooter
                x: poster.pad
                width: poster.width - poster.pad * 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: poster.pad
                StyledText {
                    width: parent.width
                    visible: root.hasHero
                    text: root.tile.name + (root.heroUnit !== "" ? " (" + root.heroUnit + ")" : "")
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.s(Appearance.font.pixelSize.normal)
                    font.variableAxes: root.axesWide
                    color: poster.ink
                }
                StyledText {
                    width: parent.width
                    visible: text !== ""
                    text: root.tile.statusText
                    elide: Text.ElideRight
                    font.pixelSize: root.s(Appearance.font.pixelSize.smaller)
                    color: poster.ink
                    opacity: 0.72
                }
            }
        }
    }

    // ------------------------------------------------------------------- split

    Component {
        id: splitFace
        Item {
            id: split
            readonly property real pad: root.s(8)
            readonly property real blockSize: Math.min(height - pad * 2, width * 0.42)

            Rectangle {
                id: block
                x: split.pad
                y: split.pad
                width: split.blockSize
                height: split.height - split.pad * 2
                // Circle while idle, rounded square (concentric with the tile) when on.
                radius: root.sharp ? 0 : (root.isOn ? Math.max(0, root.button.buttonRadius - split.pad)
                                                  : Math.min(width, height) / 2)
                color: root.isOn ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                Behavior on radius {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                PowerSpot {
                    anchors.centerIn: parent
                    size: Math.round(Math.min(block.width, block.height) * 0.8)
                    ink: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                }
                Icon {
                    anchors.centerIn: parent
                    iconSize: Math.round(Math.min(block.width, block.height) * 0.46)
                    color: root.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                }
            }

            Item {
                id: splitInfo
                x: block.x + block.width + root.s(14)
                y: split.pad + root.s(6)
                width: split.width - x - root.s(14)
                height: split.height - y - split.pad - root.s(6)

                StyledText {
                    id: splitName
                    width: parent.width - (splitArrow.visible ? splitArrow.width + root.s(8) : 0)
                    text: root.tile.name
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: root.s(Appearance.font.pixelSize.hugeass)
                    font.variableAxes: root.axesGrotesk
                    font.letterSpacing: -0.4
                    color: Appearance.colors.colOnLayer2
                }
                DialogArrow {
                    id: splitArrow
                    x: parent.width - width + root.s(4)
                    y: -root.s(2)
                    contentColor: Appearance.colors.colOnLayer2
                }

                Row {
                    visible: root.hasHero
                    anchors.left: parent.left
                    anchors.bottom: splitStatus.top
                    StyledText {
                        id: splitDigits
                        text: root.heroValue
                        font.family: Appearance.font.family.main
                        font.pixelSize: Math.round(Math.min(splitInfo.height * 0.55, root.s(52)))
                        font.variableAxes: root.axesDigitsThin
                        color: root.isOn ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    }
                    StyledText {
                        anchors.baseline: splitDigits.baseline
                        text: root.heroUnit
                        font.pixelSize: root.s(Appearance.font.pixelSize.normal)
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledText {
                    id: splitStatus
                    anchors.bottom: parent.bottom
                    width: parent.width
                    text: root.tile.statusText
                    wrapMode: Text.Wrap
                    maximumLineCount: root.hasHero ? 1 : 2
                    elide: Text.ElideRight
                    font.pixelSize: root.s(root.hasHero ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.normal)
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
