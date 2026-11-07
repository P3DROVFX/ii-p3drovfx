import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Fan curve chart: temperature across, fan duty up. Two handles shape the curve — the
 * start (where the floor ends) and the end (where full speed begins); between them the
 * daemon's exponential/linear/logarithmic rise is drawn from the same formula it runs.
 * The live temperature is a tertiary rule with a dot on the curve.
 */
Item {
    id: root

    property var curve: ({ "tStart": 60, "tMax": 80, "minPct": 40, "maxPct": 100, "steepness": 2 })
    property real liveTemp: -1
    property real livePct: -1
    property real safetyTemp: 92
    property bool editable: true
    property string yCaption: "%"

    readonly property real axisMinT: 30
    readonly property real axisMaxT: 100

    // which handle the pointer is on ("start" / "end" / ""), for the pane's subtitle
    readonly property string activeHandle: startHandle.engaged ? "start" : (endHandle.engaged ? "end" : "")

    signal edited(var curve)

    readonly property real padLeft: 40
    readonly property real padRight: 16
    readonly property real padTop: 20
    readonly property real padBottom: 28
    readonly property real plotW: Math.max(1, width - padLeft - padRight)
    readonly property real plotH: Math.max(1, height - padTop - padBottom)

    function xOf(t) { return padLeft + (t - axisMinT) / (axisMaxT - axisMinT) * plotW; }
    function yOf(p) { return padTop + (1 - p / 100) * plotH; }
    function tAt(x) { return axisMinT + (x - padLeft) / plotW * (axisMaxT - axisMinT); }
    function pAt(y) { return (1 - (y - padTop) / plotH) * 100; }

    readonly property var curvePoints: {
        const pts = [];
        const c = root.curve;
        for (let t = root.axisMinT; t <= root.axisMaxT + 0.01; t += 0.5)
            pts.push(Qt.point(root.xOf(t), root.yOf(FanControl.curvePct(c, t))));
        return pts;
    }
    readonly property var areaPoints: root.curvePoints.concat([
        Qt.point(root.xOf(root.axisMaxT), root.yOf(0)),
        Qt.point(root.xOf(root.axisMinT), root.yOf(0))
    ])

    function update(which, t, p) {
        const c = Object.assign({}, root.curve);
        t = Math.round(t);
        p = Math.round(p);
        if (which === "start") {
            c.tStart = Math.max(root.axisMinT, Math.min(c.tMax - 2, t));
            c.minPct = Math.max(0, Math.min(c.maxPct, p));
        } else {
            c.tMax = Math.max(c.tStart + 2, Math.min(root.axisMaxT, t));
            c.maxPct = Math.max(c.minPct, Math.min(100, p));
        }
        if (c.tStart !== root.curve.tStart || c.tMax !== root.curve.tMax
                || c.minPct !== root.curve.minPct || c.maxPct !== root.curve.maxPct)
            root.edited(c);
    }

    // ── grid ───────────────────────────────────────────────────────────────────
    Repeater {
        model: [0, 25, 50, 75, 100]
        delegate: Item {
            required property int modelData
            Rectangle {
                x: root.padLeft
                y: root.yOf(parent.modelData)
                width: root.plotW
                height: 1
                color: Appearance.colors.colOutlineVariant
                opacity: parent.modelData === 0 ? 0.9 : 0.4
            }
            StyledText {
                x: root.padLeft - width - 8
                y: root.yOf(parent.modelData) - height / 2
                text: `${parent.modelData}%`
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
    Repeater {
        model: [30, 40, 50, 60, 70, 80, 90, 100]
        delegate: StyledText {
            required property int modelData
            x: root.xOf(modelData) - width / 2
            y: root.height - root.padBottom + 8
            text: `${modelData}°`
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    // ── safety band: the daemon forces 100 % here whatever the curve says ──────
    Rectangle {
        x: root.xOf(root.safetyTemp)
        y: root.padTop
        width: root.xOf(root.axisMaxT) - x
        height: root.plotH
        radius: Appearance.rounding.verysmall
        color: ColorUtils.applyAlpha(Appearance.colors.colTertiaryContainer, 0.55)
    }

    // ── curve ──────────────────────────────────────────────────────────────────
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
            PathPolyline { path: root.areaPoints }
        }
        ShapePath {
            strokeColor: Appearance.colors.colPrimary
            strokeWidth: 3
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.curvePoints }
        }
    }

    // ── live temperature ───────────────────────────────────────────────────────
    Item {
        id: live
        visible: root.liveTemp >= root.axisMinT
        readonly property real lx: root.xOf(Math.min(root.axisMaxT, root.liveTemp))
        readonly property real pct: root.livePct >= 0 ? root.livePct : FanControl.curvePct(root.curve, root.liveTemp)
        anchors.fill: parent

        Rectangle {
            x: live.lx - 1
            y: root.padTop
            width: 2
            height: root.plotH
            radius: 1
            color: Appearance.colors.colTertiary
            opacity: 0.7
            Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        }
        Rectangle {
            width: 12
            height: 12
            radius: 6
            x: live.lx - 6
            y: root.yOf(live.pct) - 6
            color: Appearance.colors.colTertiary
            Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on y { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        }
        Rectangle {
            id: liveChip
            height: 22
            width: liveText.implicitWidth + 16
            radius: height / 2
            y: 0
            x: Math.max(root.padLeft, Math.min(root.width - root.padRight - width, live.lx - width / 2))
            color: Appearance.colors.colTertiary
            StyledText {
                id: liveText
                anchors.centerIn: parent
                text: `${Math.round(root.liveTemp)}° · ${Math.round(live.pct)}%`
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnTertiary
            }
        }
    }

    // ── handles ────────────────────────────────────────────────────────────────
    CurveHandle {
        id: startHandle
        which: "start"
        temp: root.curve.tStart
        pct: root.curve.minPct
    }
    CurveHandle {
        id: endHandle
        which: "end"
        temp: root.curve.tMax
        pct: root.curve.maxPct
    }

    component CurveHandle: Item {
        id: handle

        required property string which
        required property real temp
        required property real pct
        readonly property bool engaged: hover.hovered || drag.pressed

        width: 44
        height: 44
        x: root.xOf(handle.temp) - width / 2
        y: root.yOf(handle.pct) - height / 2
        z: engaged ? 3 : 2
        enabled: root.editable
        opacity: root.editable ? 1 : 0.5

        HoverHandler {
            id: hover
            cursorShape: Qt.SizeAllCursor
        }

        MaterialShape {
            anchors.centerIn: parent
            implicitSize: handle.engaged ? 30 : 24
            shape: drag.pressed ? MaterialShape.Shape.Cookie12Sided
                : (hover.hovered ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle)
            color: Appearance.colors.colPrimary
            Behavior on implicitSize { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: Appearance.colors.colOnPrimary
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            preventStealing: true
            property real grabDx: 0
            property real grabDy: 0
            onPressed: mouse => {
                grabDx = mouse.x - width / 2;
                grabDy = mouse.y - height / 2;
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const p = mapToItem(root, mouse.x - grabDx, mouse.y - grabDy);
                root.update(handle.which, root.tAt(p.x), root.pAt(p.y));
            }
        }

        // value pill above the handle while it is touched
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: -2
            height: 26
            width: pillText.implicitWidth + 18
            radius: height / 2
            color: Appearance.colors.colPrimary
            opacity: handle.engaged ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            StyledText {
                id: pillText
                anchors.centerIn: parent
                text: `${Math.round(handle.temp)}° · ${Math.round(handle.pct)}${root.yCaption}`
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
