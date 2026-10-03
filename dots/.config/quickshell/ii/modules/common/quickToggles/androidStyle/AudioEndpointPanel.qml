pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The tall (height > 1) face of the audio output / input quick toggles.
 *
 * One level, shown big and nothing else: the volume in tall condensed digits, and a
 * Material shape that is both the mute button and the state (cookie while live, circle
 * while muted). There is deliberately no slider - the tile reads, mutes, and opens the
 * device & mixer menu. Output speaks in the primary family and input in the tertiary one,
 * so the two tiles side by side never read as twins.
 *
 * Every part is placed from the tile's settled size by `geometry`, so 1x2, 1x3+, 2x2, 2x3,
 * 4x2 and 2x4 are the same three parts arranged for the room they have - the digits are
 * the element that absorbs spare space, the shape keeps a stable size.
 *
 * Tapping anywhere that is not the shape falls through to the tile, which opens the
 * device & mixer menu (the generic tall behaviour for a toggle that has one).
 */
Item {
    id: root

    /** The AndroidQuickToggleButton this face is drawn for. */
    required property var tile
    required property bool isInput

    readonly property var node: root.isInput ? Audio.source : Audio.sink
    readonly property real volume: root.node?.audio?.volume ?? 0
    readonly property bool muted: root.node?.audio?.muted ?? false
    readonly property bool live: !root.muted
    readonly property string deviceName: Audio.friendlyDeviceName(root.node)
    readonly property string kindLabel: root.isInput ? Translation.tr("Audio input") : Translation.tr("Audio output")

    // Accent family of the tile (never mixed: shape, bar and chevron share it).
    readonly property color colAccent: root.isInput ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
    readonly property color colAccentContainer: root.isInput ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer
    readonly property color colOnAccentContainer: root.isInput ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer
    readonly property color colMutedFill: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.55)

    readonly property string symbol: {
        if (root.isInput)
            return root.muted ? "mic_off" : "mic";
        if (root.muted)
            return "volume_off";
        if (root.volume <= 0.001)
            return "volume_mute";
        return root.volume < 0.5 ? "volume_down" : "volume_up";
    }

    function s(value) {
        return root.tile.scaled(value);
    }
    function clamp(value, lo, hi) {
        return Math.max(lo, Math.min(hi, value));
    }

    // ── Format: decided on the SETTLED size, so it does not flip while the tile animates ──
    readonly property real settledW: Math.max(1, root.tile.allocatedWidth - root.tile.scaled(24))
    readonly property real settledH: Math.max(1, root.tile.baseHeight - root.tile.scaled(24))
    readonly property string format: {
        const w = root.settledW, h = root.settledH;
        if (w < root.s(100))
            return "narrow";
        if (w >= root.s(250) && w >= h * 2)
            return "wide";
        if (h >= w * 1.2)
            return "tall";
        return "compact";
    }

    // ── Geometry of the three parts for the current format and the live size ──
    readonly property var geometry: {
        const W = root.width, H = root.height;
        const s = root.s;
        const g = {};
        switch (root.format) {
        case "wide": {
            const size = root.clamp(Math.round(H * 0.72), s(40), s(84));
            const digitsW = Math.round(Math.min(W * 0.46, H * 1.8));
            const colX = size + s(16);
            const nameH = s(44);
            g.shape = { x: 0, y: (H - size) / 2, size: size };
            g.digits = { x: W - digitsW, y: 0, w: digitsW, h: H, align: Text.AlignRight };
            g.name = { x: colX, y: (H - nameH) / 2, w: Math.max(0, W - colX - digitsW - s(12)), h: nameH, single: false, show: true };
            break;
        }
        case "tall": {
            const size = Math.min(W, s(52));
            const nameH = s(36);
            g.shape = { x: 0, y: 0, size: size };
            g.digits = { x: 0, y: size + s(4), w: W, h: Math.max(0, H - size - s(4) - nameH - s(6)), align: Text.AlignLeft };
            g.name = { x: 0, y: H - nameH, w: W, h: nameH, single: false, show: true };
            break;
        }
        case "narrow": {
            const size = Math.min(W, Math.round(H * 0.42), s(44));
            const gap = s(4);
            g.shape = { x: (W - size) / 2, y: 0, size: size };
            g.digits = { x: 0, y: size + gap, w: W, h: Math.max(0, H - size - gap), align: Text.AlignHCenter };
            g.name = { x: 0, y: 0, w: 0, h: 0, single: true, show: false };
            break;
        }
        default: { // compact: 2x2, 2x3, 3x2 ...
            const nameH = s(18);
            const gap = s(6);
            const topH = Math.max(s(24), H - nameH - gap);
            const size = Math.min(topH, s(46));
            g.shape = { x: 0, y: 0, size: size };
            g.digits = { x: size + s(8), y: 0, w: Math.max(0, W - size - s(8)), h: topH, align: Text.AlignRight };
            g.name = { x: 0, y: topH + gap, w: W, h: nameH, single: true, show: true };
        }
        }
        return g;
    }

    // ═════════════════════════ Parts ═════════════════════════

    // ═════════════════════════ The tile face ═════════════════════════

    // Mute button: the shape is the state. Live = cookie, muted = circle.
    Item {
        id: shapeSlot
        x: root.geometry.shape.x
        y: root.geometry.shape.y
        width: root.geometry.shape.size
        height: width

        MaterialShapeWrappedMaterialSymbol {
            id: muteShape
            anchors.fill: parent
            implicitSize: parent.width
            padding: 0
            shapeString: !root.live ? "Circle"
                : (muteHover.hovered ? (root.isInput ? "Sunny" : "Cookie12Sided")
                                     : (root.isInput ? "Clover4Leaf" : "Cookie9Sided"))
            color: root.live ? root.colAccentContainer : Appearance.colors.colLayer3
            colSymbol: root.live ? root.colOnAccentContainer : Appearance.colors.colOnLayer3
            text: root.symbol
            iconSize: Math.round(parent.width * 0.5)
            fill: root.live ? 1 : 0
            scale: muteArea.pressed ? 0.95 : (muteHover.hovered ? 1.02 : 1)
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(muteShape)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(muteShape)
            }
        }
        HoverHandler {
            id: muteHover
            enabled: !root.tile.editMode
        }
        MouseArea {
            id: muteArea
            anchors.fill: parent
            enabled: !root.tile.editMode
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tile.mainAction()
        }
    }

    // The one number.
    Item {
        id: digitsBox
        x: root.geometry.digits.x
        y: root.geometry.digits.y
        width: root.geometry.digits.w
        height: root.geometry.digits.h
        clip: false

        property real boldness: root.live ? 1 : 0
        Behavior on boldness {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(digitsBox)
        }
        readonly property string text: String(Math.round(root.volume * 100))
        readonly property var axes: ({
            "wght": 560 + 200 * boldness,
            "wdth": 30 + 10 * boldness,
            "ROND": 100
        })
        // Calibrated on the real font: how wide one digit is per pixel of size.
        TextMetrics {
            id: digitMetrics
            text: "0"
            font.family: Appearance.font.family.main
            font.pixelSize: 100
            font.variableAxes: digitsBox.axes
        }
        readonly property real digitW: Math.max(0.3, digitMetrics.advanceWidth / 100)
        readonly property real pctRatio: 0.34
        readonly property real px: Math.round(Math.max(root.s(12), Math.min(height * 0.92,
            width / (text.length * digitW + pctRatio * 0.62))))

        Row {
            id: digitsRow
            spacing: 1
            anchors.verticalCenter: parent.verticalCenter
            x: root.geometry.digits.align === Text.AlignRight ? parent.width - width
                : (root.geometry.digits.align === Text.AlignHCenter ? (parent.width - width) / 2 : 0)

            StyledText {
                id: digitsText
                text: digitsBox.text
                font.family: Appearance.font.family.main
                font.pixelSize: digitsBox.px
                font.variableAxes: digitsBox.axes
                verticalAlignment: Text.AlignVCenter
                color: root.live ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(digitsText)
                }
            }
            Item {
                width: pctText.implicitWidth
                height: digitsText.implicitHeight
                StyledText {
                    id: pctText
                    anchors.top: parent.top
                    anchors.topMargin: Math.round(digitsBox.px * 0.18)
                    text: "%"
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.max(root.s(9), Math.round(digitsBox.px * digitsBox.pctRatio))
                    font.weight: Font.Bold
                    color: root.live ? root.colAccent : Appearance.colors.colSubtext
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pctText)
                    }
                }
            }
        }
    }

    // Caption + device. Single line in compact (the chevron says "opens the menu").
    Item {
        id: nameBlock
        visible: root.geometry.name.show
        x: root.geometry.name.x
        y: root.geometry.name.y
        width: root.geometry.name.w
        height: root.geometry.name.h

        readonly property bool single: root.geometry.name.single

        StyledText {
            id: captionText
            visible: !nameBlock.single
            width: parent.width
            text: root.muted ? root.kindLabel + " · " + Translation.tr("Muted") : root.kindLabel
            font.pixelSize: root.s(Appearance.font.pixelSize.smallest + 1)
            font.weight: Font.Bold
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
        StyledText {
            id: deviceText
            y: nameBlock.single ? (parent.height - height) / 2 : captionText.height
            width: nameBlock.single ? Math.max(0, parent.width - chevron.width - root.s(2)) : parent.width
            text: nameBlock.single && root.muted ? Translation.tr("Muted") + " · " + root.deviceName : root.deviceName
            font.family: nameBlock.single ? Appearance.font.family.main : Appearance.font.family.title
            font.pixelSize: nameBlock.single ? root.s(Appearance.font.pixelSize.smaller)
                : root.s(root.format === "wide" ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.small)
            font.variableAxes: nameBlock.single ? Appearance.font.variableAxes.main : Appearance.font.variableAxes.titleRounded
            font.weight: nameBlock.single ? Font.DemiBold : Font.Medium
            color: Appearance.colors.colOnLayer2
            elide: Text.ElideRight
        }
        MaterialSymbol {
            id: chevron
            visible: nameBlock.single
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "unfold_more"
            iconSize: root.s(16)
            color: root.live ? root.colAccent : Appearance.colors.colSubtext
        }
    }
}
