pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One indicator carrying both quota windows of the shown provider.
 *  - capsule: the pill fills with the first window, a ring around it closes with the second
 *  - mood: a Material shape that grows spikier as the first window runs out, both values beside it
 *  - duo: two cells, one per window, each filling with its number printed inside
 */
Item {
    id: root

    property var primaryQuota: null
    property var secondaryQuota: null
    property string visualization: "capsule"
    property bool vertical: false
    property bool useAccentForeground: false
    property color contentColor: Appearance.colors.colOnLayer1

    // 28 px at the default 40 px bar; every size below scales from it.
    readonly property int unit: Math.max(24, Math.round(root.vertical
        ? Appearance.sizes.verticalBarWidth - 16
        : Appearance.sizes.baseBarHeight - 12))
    readonly property bool hasSecondary: root.secondaryQuota !== null && root.secondaryQuota !== undefined
    readonly property string iconSource: String(root.primaryQuota?.providerIcon
        ?? AiPlanUsage.providerIcon(String(root.primaryQuota?.providerId ?? "")))

    function fraction(quota): real {
        if (!quota || quota.available === false)
            return 0;
        return Math.max(0, Math.min(1, AiPlanUsage.displayFraction(quota)));
    }
    // Pressure is always "how much is spent", whatever the percentage setting says.
    function usedFraction(quota): real {
        if (!quota || quota.available === false || String(quota.metricKind ?? "quota") === "credits")
            return 0;
        return Math.max(0, Math.min(1, 1 - (Number(quota.remainingPercent) || 0) / 100));
    }
    function numberText(quota): string {
        return AiPlanUsage.percentText(quota).replace("%", "");
    }
    function shortWindowLabel(quota): string {
        switch (String(quota?.windowKind ?? "short")) {
        case "balance": return String(quota?.currency ?? "USD");
        case "weekly": return "7d";
        case "daily": return "24h";
        case "monthly": return "30d";
        default:
            return Number(quota?.windowMinutes ?? 0) === 300 ? "5h" : Translation.tr("Now");
        }
    }

    implicitWidth: styleLoader.implicitWidth
    implicitHeight: styleLoader.implicitHeight
    opacity: primaryPalette.available ? 1.0 : 0.5

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    AiQuotaPalette {
        id: primaryPalette
        quota: root.primaryQuota
    }
    AiQuotaPalette {
        id: secondaryPalette
        quota: root.secondaryQuota
    }

    Loader {
        id: styleLoader
        anchors.centerIn: parent
        sourceComponent: root.visualization === "mood" ? moodComponent
            : root.visualization === "duo" ? duoComponent
            : capsuleComponent
    }

    // A pill face: rounded fill, provider icon and value. Drawn twice by the capsule
    // (container colours underneath, accent colours clipped to the filled part).
    component CapsuleFace: Item {
        id: face

        property bool vertical: false
        property color fill
        property color ink
        property string iconSource
        property string valueText
        property real iconSize
        property real fontSize

        Rectangle {
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            color: face.fill
        }
        CustomIcon {
            x: face.vertical ? (face.width - width) / 2 : Math.round(face.height * 0.35)
            y: face.vertical ? Math.round(face.width * 0.25) : (face.height - height) / 2
            width: face.iconSize
            height: face.iconSize
            source: face.iconSource
            colorize: true
            color: face.ink
        }
        StyledText {
            x: face.vertical ? (face.width - width) / 2 : face.width - width - Math.round(face.height * 0.4)
            y: face.vertical ? face.height - height - Math.round(face.width * 0.2) : (face.height - height) / 2
            text: face.valueText
            font.pixelSize: face.fontSize
            font.weight: Font.Bold
            color: face.ink
        }
    }

    component CellFace: Item {
        id: cellFace

        property color fill
        property color ink
        property string valueText
        property real fontSize
        property real cellRadius

        Rectangle {
            anchors.fill: parent
            radius: cellFace.cellRadius
            color: cellFace.fill
        }
        StyledText {
            anchors.centerIn: parent
            text: cellFace.valueText
            font.pixelSize: cellFace.fontSize
            font.weight: Font.Bold
            color: cellFace.ink
        }
    }

    // One filling cell for the duo style; fills bottom-up (horizontal bar) or left-right (vertical bar).
    component FillCell: Item {
        id: cell

        property bool fillsSideways: false
        property real fraction: 0
        property color fill
        property color fillInk
        property color track
        property color trackInk
        property string valueText
        property real fontSize
        property real cellRadius

        Behavior on fraction {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        CellFace {
            anchors.fill: parent
            fill: cell.track
            ink: cell.trackInk
            valueText: cell.valueText
            fontSize: cell.fontSize
            cellRadius: cell.cellRadius
        }
        Item {
            visible: cell.fraction > 0
            clip: true
            x: 0
            y: cell.fillsSideways ? 0 : cell.height - height
            width: cell.fillsSideways ? cell.width * cell.fraction : cell.width
            height: cell.fillsSideways ? cell.height : cell.height * cell.fraction

            CellFace {
                y: -parent.y
                width: cell.width
                height: cell.height
                fill: cell.fill
                ink: cell.fillInk
                valueText: cell.valueText
                fontSize: cell.fontSize
                cellRadius: cell.cellRadius
            }
        }
    }

    Component {
        id: capsuleComponent

        Item {
            id: capsule

            // Whole pixels only: a fractional ring or gap snaps differently from the pill and
            // leaves it off-centre inside the ring.
            readonly property int ringWidth: Math.max(2, Math.round(root.unit * 0.075))
            readonly property int inset: capsule.ringWidth + Math.max(2, Math.round(root.unit * 0.07))
            readonly property real pillThickness: Math.round(root.vertical ? root.unit - 4 : root.unit - capsule.inset * 2)
            readonly property real pillLength: Math.round(root.vertical ? root.unit * 1.6 : capsule.pillThickness * 3)
            property real fillFraction: root.fraction(root.primaryQuota)
            property real ringFraction: root.fraction(root.secondaryQuota)

            implicitWidth: (root.vertical ? capsule.pillThickness : capsule.pillLength) + capsule.inset * 2
            implicitHeight: (root.vertical ? capsule.pillLength : capsule.pillThickness) + capsule.inset * 2

            Behavior on fillFraction {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on ringFraction {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Second window: a stadium ring that closes from the leading cap along both sides at once,
            // meeting at the trailing cap, so it grows the same way the pill fills.
            Rectangle {
                visible: root.hasSecondary
                anchors.fill: parent
                radius: Math.min(width, height) / 2
                color: "transparent"
                border.width: capsule.ringWidth
                border.color: secondaryPalette.container
            }
            Canvas {
                id: ring

                readonly property color strokeColor: secondaryPalette.accent

                visible: root.hasSecondary && capsule.ringFraction > 0
                anchors.fill: parent
                onStrokeColorChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: capsule
                    function onRingFractionChanged() {
                        ring.requestPaint();
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const s = capsule.ringWidth;
                    // Draw in "long axis along x" space; the vertical bar rotates it so the ring grows upward.
                    const len = root.vertical ? height : width;
                    const thick = root.vertical ? width : height;
                    if (root.vertical) {
                        ctx.translate(0, height);
                        ctx.rotate(-Math.PI / 2);
                    }
                    const r = (thick - s) / 2;
                    const straight = Math.max(0, len - s - 2 * r);
                    const cy = thick / 2;
                    const leftX = s / 2 + r;
                    const rightX = leftX + straight;
                    const quarter = Math.PI * r / 2;
                    const distance = capsule.ringFraction * (2 * quarter + straight);

                    ctx.lineWidth = s;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = ring.strokeColor;
                    for (const side of [1, -1]) {
                        ctx.beginPath();
                        const a1 = Math.min(Math.PI / 2, distance / r);
                        ctx.arc(leftX, cy, r, Math.PI, Math.PI + side * a1, side < 0);
                        if (distance > quarter)
                            ctx.lineTo(leftX + Math.min(straight, distance - quarter), cy - side * r);
                        if (distance > quarter + straight) {
                            const a3 = Math.min(Math.PI / 2, (distance - quarter - straight) / r);
                            const start = side > 0 ? Math.PI * 1.5 : Math.PI / 2;
                            ctx.arc(rightX, cy, r, start, start + side * a3, side < 0);
                        }
                        ctx.stroke();
                    }
                }
            }

            Item {
                id: pill
                x: capsule.inset
                y: capsule.inset
                width: root.vertical ? capsule.pillThickness : capsule.pillLength
                height: root.vertical ? capsule.pillLength : capsule.pillThickness

                CapsuleFace {
                    anchors.fill: parent
                    vertical: root.vertical
                    fill: primaryPalette.container
                    ink: primaryPalette.containerInk
                    iconSource: root.iconSource
                    valueText: root.vertical ? root.numberText(root.primaryQuota) : AiPlanUsage.percentText(root.primaryQuota)
                    iconSize: Math.round(root.unit / 2)
                    fontSize: Math.round(capsule.pillThickness * (root.vertical ? 0.42 : 0.55))
                }
                // Same face in accent colours, clipped to the filled part: icon and value invert as the fill passes.
                Item {
                    visible: capsule.fillFraction > 0
                    clip: true
                    y: root.vertical ? pill.height - height : 0
                    width: root.vertical ? pill.width : pill.width * capsule.fillFraction
                    height: root.vertical ? pill.height * capsule.fillFraction : pill.height

                    CapsuleFace {
                        y: -parent.y
                        width: pill.width
                        height: pill.height
                        vertical: root.vertical
                        fill: primaryPalette.accent
                        ink: primaryPalette.accentInk
                        iconSource: root.iconSource
                        valueText: root.vertical ? root.numberText(root.primaryQuota) : AiPlanUsage.percentText(root.primaryQuota)
                        iconSize: Math.round(root.unit / 2)
                        fontSize: Math.round(capsule.pillThickness * (root.vertical ? 0.42 : 0.55))
                    }
                }
            }
        }
    }

    Component {
        id: moodComponent

        Item {
            id: mood

            readonly property real used: root.usedFraction(root.primaryQuota)
            readonly property bool filled: primaryPalette.low || mood.used >= 0.5
            readonly property color valueColor: primaryPalette.low ? Appearance.colors.colError
                : (root.useAccentForeground ? primaryPalette.accent : root.contentColor)

            implicitWidth: root.vertical ? Math.max(shape.width, valueColumn.implicitWidth) : shape.width + 6 + valueColumn.implicitWidth
            implicitHeight: root.vertical ? shape.height + 2 + valueColumn.implicitHeight : root.unit

            MaterialShape {
                id: shape

                x: root.vertical ? (mood.width - width) / 2 : 0
                y: root.vertical ? 0 : (mood.height - height) / 2
                implicitSize: root.unit
                // Calm circle → cookie → sun → burst at the warning threshold. Morphs only on change.
                shapeString: !primaryPalette.available ? "Circle"
                    : primaryPalette.low ? "Burst"
                    : mood.used >= 0.65 ? "Sunny"
                    : mood.used >= 0.4 ? "Cookie9Sided"
                    : "Circle"
                color: mood.filled ? primaryPalette.accent : primaryPalette.container

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                CustomIcon {
                    anchors.centerIn: parent
                    width: Math.round(root.unit / 2)
                    height: width
                    source: root.iconSource
                    colorize: true
                    color: mood.filled ? primaryPalette.accentInk : primaryPalette.containerInk
                }
            }

            Column {
                id: valueColumn

                x: root.vertical ? (mood.width - width) / 2 : shape.width + 6
                y: root.vertical ? shape.height + 2 : (mood.height - height) / 2
                spacing: -2

                StyledText {
                    text: root.vertical ? root.numberText(root.primaryQuota) : AiPlanUsage.percentText(root.primaryQuota)
                    font.pixelSize: root.vertical ? Appearance.font.pixelSize.smallest : Math.round(root.unit * 0.46)
                    font.weight: Font.Bold
                    color: mood.valueColor
                }
                StyledText {
                    visible: root.hasSecondary && !root.vertical
                    text: root.shortWindowLabel(root.secondaryQuota) + " " + AiPlanUsage.percentText(root.secondaryQuota)
                    font.pixelSize: Math.round(root.unit * 0.34)
                    font.weight: Font.DemiBold
                    color: secondaryPalette.low ? Appearance.colors.colError : root.contentColor
                    opacity: secondaryPalette.low ? 1 : 0.72
                }
            }
        }
    }

    Component {
        id: duoComponent

        Item {
            id: duo

            readonly property real cellThickness: root.vertical ? Math.round(root.unit * 0.7) : root.unit - 4
            readonly property real cellMinLength: root.vertical ? root.unit : Math.round(root.unit * 0.82)
            readonly property real fontSize: Math.round(root.unit * 0.38)
            readonly property var quotas: root.hasSecondary ? [root.primaryQuota, root.secondaryQuota] : [root.primaryQuota]
            readonly property bool anyLow: primaryPalette.low || secondaryPalette.low

            implicitWidth: root.vertical ? Math.max(duoIcon.width, cells.implicitWidth) : duoIcon.width + 8 + cells.implicitWidth
            implicitHeight: root.vertical ? duoIcon.height + 6 + cells.implicitHeight : root.unit

            CustomIcon {
                id: duoIcon
                x: root.vertical ? (duo.width - width) / 2 : 0
                y: root.vertical ? 0 : (duo.height - height) / 2
                width: Math.round(root.unit / 2)
                height: width
                source: root.iconSource
                colorize: true
                color: !primaryPalette.available ? primaryPalette.containerInk
                    : duo.anyLow ? Appearance.colors.colError
                    : (root.useAccentForeground ? primaryPalette.accent : root.contentColor)
            }

            Grid {
                id: cells

                x: root.vertical ? (duo.width - width) / 2 : duoIcon.width + 8
                y: root.vertical ? duoIcon.height + 6 : (duo.height - height) / 2
                columns: root.vertical ? 1 : duo.quotas.length
                spacing: 3

                Repeater {
                    model: duo.quotas

                    delegate: FillCell {
                        id: fillCell
                        required property var modelData
                        required property int index

                        readonly property AiQuotaPalette quotaPalette: fillCell.index === 0 ? primaryPalette : secondaryPalette

                        width: root.vertical ? duo.cellMinLength : Math.max(duo.cellMinLength, cellMetrics.advanceWidth + 8)
                        height: duo.cellThickness
                        fillsSideways: root.vertical
                        fraction: root.fraction(fillCell.modelData)
                        fill: fillCell.quotaPalette.accent
                        fillInk: fillCell.quotaPalette.accentInk
                        track: fillCell.quotaPalette.container
                        trackInk: fillCell.quotaPalette.containerInk
                        valueText: root.numberText(fillCell.modelData)
                        fontSize: duo.fontSize
                        cellRadius: Math.round(root.unit * 0.29)

                        TextMetrics {
                            id: cellMetrics
                            font.pixelSize: duo.fontSize
                            font.weight: Font.Bold
                            text: fillCell.valueText
                        }
                    }
                }
            }
        }
    }
}
