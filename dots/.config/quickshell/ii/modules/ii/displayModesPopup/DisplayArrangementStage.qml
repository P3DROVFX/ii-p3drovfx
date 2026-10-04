pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The screens as tiles, scaled to fit, in their real arrangement.
 *
 * Only screens that draw their own picture are tiles: a mirroring screen is a badge on
 * the screen it copies, and a disabled one is not on the desk at all. In extend mode a
 * tile can be dragged; on release it snaps flush to the nearest free edge of another
 * screen (a ghost shows where while dragging) and `arranged` hands back the positions.
 */
Item {
    id: stage

    /// Every monitor, as MonitorConfigOption lists them.
    property var monitors: []
    property bool draggable: false
    /// Logical size of a monitor (scale and rotation applied); MonitorConfigOption's.
    property var logicalWidth: m => m.width
    property var logicalHeight: m => m.height

    /// name → {x, y} for every tile, in logical pixels.
    signal arranged(var positions)

    readonly property real pad: 18

    readonly property var tiles: {
        const list = [];
        const all = stage.monitors || [];
        for (let i = 0; i < all.length; i++) {
            const m = all[i];
            if (!m || m.disabled || (m.mirrorOf && m.mirrorOf !== "none"))
                continue;
            list.push({
                name: m.name,
                number: i + 1,
                x: m.x,
                y: m.y,
                w: stage.logicalWidth(m),
                h: stage.logicalHeight(m),
                mirrors: all.filter(o => o && !o.disabled && o.mirrorOf === m.name).length
            });
        }
        return list;
    }

    readonly property var bounds: {
        if (stage.tiles.length === 0)
            return { x: 0, y: 0, w: 1, h: 1 };
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const t of stage.tiles) {
            x0 = Math.min(x0, t.x);
            y0 = Math.min(y0, t.y);
            x1 = Math.max(x1, t.x + t.w);
            y1 = Math.max(y1, t.y + t.h);
        }
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
    }

    readonly property real k: Math.min((stage.width - 2 * stage.pad) / stage.bounds.w, (stage.height - 2 * stage.pad) / stage.bounds.h)
    readonly property real offX: (stage.width - stage.bounds.w * stage.k) / 2
    readonly property real offY: (stage.height - stage.bounds.h * stage.k) / 2

    function toPx(lx) { return stage.offX + (lx - stage.bounds.x) * stage.k; }
    function toPy(ly) { return stage.offY + (ly - stage.bounds.y) * stage.k; }

    // ── Drag state ───────────────────────────────────────────────────────────
    property string dragName: ""
    property real dragX: 0
    property real dragY: 0
    /// Where the dragged tile lands if released now, logical; null when nowhere fits.
    readonly property var snap: stage.dragName === "" ? null : stage.snapFor(stage.dragName,
        stage.bounds.x + (stage.dragX - stage.offX) / stage.k,
        stage.bounds.y + (stage.dragY - stage.offY) / stage.k)

    function overlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
    }

    function snapFor(name, px, py) {
        const d = stage.tiles.find(t => t.name === name);
        if (!d)
            return null;
        const others = stage.tiles.filter(t => t.name !== name);
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const align = (v, a, b, size, span) => {
            const thr = span * 0.08;
            if (Math.abs(v - a) < thr) return a;
            if (Math.abs(v + size - b) < thr) return b - size;
            return v;
        };
        let best = null;
        let bestDist = Infinity;
        for (const o of others) {
            const yOn = align(clamp(py, o.y - d.h + 1, o.y + o.h - 1), o.y, o.y + o.h, d.h, o.h);
            const xOn = align(clamp(px, o.x - d.w + 1, o.x + o.w - 1), o.x, o.x + o.w, d.w, o.w);
            const candidates = [
                { x: o.x + o.w, y: yOn },
                { x: o.x - d.w, y: yOn },
                { x: xOn, y: o.y + o.h },
                { x: xOn, y: o.y - d.h }
            ];
            for (const c of candidates) {
                const r = { x: Math.round(c.x), y: Math.round(c.y), w: d.w, h: d.h };
                if (others.some(t => stage.overlaps(r, t)))
                    continue;
                const dist = Math.hypot(r.x - px, r.y - py);
                if (dist < bestDist) {
                    bestDist = dist;
                    best = r;
                }
            }
        }
        return best;
    }

    function commitDrag() {
        const target = stage.snap;
        const name = stage.dragName;
        stage.dragName = "";
        if (!target)
            return;
        const d = stage.tiles.find(t => t.name === name);
        if (!d || (d.x === target.x && d.y === target.y))
            return;
        // Keep the desk's origin where it was, so a screen that did not move keeps its
        // coordinates (scripts and screenshots read them).
        const moved = stage.tiles.map(t => t.name === name ? Object.assign({}, t, { x: target.x, y: target.y }) : t);
        const nx = Math.min(...moved.map(t => t.x)), ny = Math.min(...moved.map(t => t.y));
        const dx = stage.bounds.x - nx, dy = stage.bounds.y - ny;
        const positions = {};
        for (const t of moved)
            positions[t.name] = { x: t.x + dx, y: t.y + dy };
        stage.arranged(positions);
    }

    // The ghost: where the dragged screen will land.
    Rectangle {
        visible: stage.snap !== null
        x: stage.snap ? stage.toPx(stage.snap.x) : 0
        y: stage.snap ? stage.toPy(stage.snap.y) : 0
        width: stage.snap ? stage.snap.w * stage.k : 0
        height: stage.snap ? stage.snap.h * stage.k : 0
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)

        Behavior on x {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on y {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Repeater {
        model: stage.tiles

        delegate: Rectangle {
            id: tile
            required property var modelData

            readonly property bool dragging: stage.dragName === tile.modelData.name
            readonly property bool focusedScreen: (Hyprland.focusedMonitor?.name ?? "") === tile.modelData.name
            readonly property color colContent: tile.focusedScreen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

            z: tile.dragging ? 2 : 1
            x: tile.dragging ? stage.dragX : stage.toPx(tile.modelData.x)
            y: tile.dragging ? stage.dragY : stage.toPy(tile.modelData.y)
            width: Math.max(8, tile.modelData.w * stage.k - 4)
            height: Math.max(8, tile.modelData.h * stage.k - 4)

            // Shape is state: a held screen rounds off, and settles square again on drop.
            radius: tile.dragging ? Appearance.rounding.normal : Appearance.rounding.small
            color: tile.focusedScreen
                ? (tileMa.containsMouse && stage.draggable ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                : (tileMa.containsMouse && stage.draggable ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)

            Behavior on x {
                enabled: !tile.dragging && !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on y {
                enabled: !tile.dragging && !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on width {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on height {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on radius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            Column {
                anchors.centerIn: parent
                spacing: -2

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.modelData.number
                    color: tile.colContent
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                    font.pixelSize: Math.round(Math.max(14, Math.min(tile.height * 0.5, 44)))
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: tile.height > 58 && tile.width > 64
                    text: tile.modelData.name
                    color: tile.colContent
                    opacity: 0.8
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                }
            }

            // A screen copying this one.
            Rectangle {
                visible: tile.modelData.mirrors > 0
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 5
                }
                implicitWidth: mirrorRow.implicitWidth + 10
                implicitHeight: 20
                radius: Appearance.rounding.full
                color: Appearance.colors.colTertiaryContainer

                Row {
                    id: mirrorRow
                    anchors.centerIn: parent
                    spacing: 2
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "content_copy"
                        iconSize: 12
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "×" + (tile.modelData.mirrors + 1)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                }
            }

            MouseArea {
                id: tileMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: stage.draggable
                cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true

                property real grabX: 0
                property real grabY: 0

                onPressed: mouse => {
                    tileMa.grabX = mouse.x;
                    tileMa.grabY = mouse.y;
                    stage.dragX = tile.x;
                    stage.dragY = tile.y;
                    stage.dragName = tile.modelData.name;
                }
                onPositionChanged: mouse => {
                    if (!tile.dragging)
                        return;
                    const p = tileMa.mapToItem(stage, mouse.x, mouse.y);
                    stage.dragX = p.x - tileMa.grabX;
                    stage.dragY = p.y - tileMa.grabY;
                }
                onReleased: stage.commitDrag()
                onCanceled: stage.dragName = ""
            }
        }
    }
}
