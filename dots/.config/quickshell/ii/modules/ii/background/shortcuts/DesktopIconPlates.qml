import QtQuick
import qs.modules.common

/**
 * The desktop icons' plates - hover, selection, landing ghost - drawn on the
 * wallpaper surface, which the compositor never blurs, so they stay plainly
 * see-through. One slot per published entry, updated in place, so a plate
 * fades instead of popping.
 */
Item {
    id: root

    required property string screenName

    readonly property real radius: Appearance.rounding.large
    readonly property var kinds: ({
        "hover": { "color": Appearance.m3colors.m3surfaceContainerHighest, "alpha": 0.45 },
        "selected": { "color": Appearance.colors.colSecondaryContainer, "alpha": 0.7 },
        "focus": { "color": Appearance.colors.colSecondaryContainer, "alpha": 0.88 },
        "ghost": { "color": Appearance.colors.colSecondaryContainer, "alpha": 0.5 }
    })

    readonly property var entries: DesktopShortcuts.plates[root.screenName] ?? []
    onEntriesChanged: root.sync()

    // Selection plates are drawn opaque into one layer that takes the alpha
    // as a whole, so neighbours merge into a single shape instead of
    // stacking where they overlap. Bridges fill the notches the rounded
    // corners leave between aligned neighbours.
    readonly property var selectionEntries: root.entries.filter(e => e.kind === "selected" || e.kind === "focus")
    readonly property bool selectionShown: root.selectionEntries.length > 0
    onSelectionShownChanged: if (!root.selectionShown) selectionLinger.restart()
    Timer {
        id: selectionLinger
        interval: 600
    }
    readonly property var bridges: {
        const list = root.selectionEntries, out = [];
        const near = (a, b) => Math.abs(a - b) < 1;
        for (let i = 0; i < list.length; ++i) {
            for (let j = i + 1; j < list.length; ++j) {
                const a = list[i], b = list[j];
                const acx = a.x + a.w / 2, acy = a.y + a.h / 2, bcx = b.x + b.w / 2, bcy = b.y + b.h / 2;
                if (near(a.x, b.x) && near(a.w, b.w) && a.y <= b.y + b.h + 1 && b.y <= a.y + a.h + 1)
                    out.push({ "x": a.x, "y": Math.min(acy, bcy), "w": a.w, "h": Math.abs(acy - bcy) });
                else if (near(a.y, b.y) && near(a.h, b.h) && a.x <= b.x + b.w + 1 && b.x <= a.x + a.w + 1)
                    out.push({ "x": Math.min(acx, bcx), "y": a.y, "w": Math.abs(acx - bcx), "h": a.h });
            }
        }
        return out;
    }
    Component.onCompleted: root.sync()

    // Slots are keyed by the tile's id: a plate fades out where it was and a
    // new one fades in where it lands, reusing a slot that has gone idle.
    function sync() {
        const wanted = new Map(root.entries.map(e => [e.id, e]));
        const seen = new Set();
        for (let i = 0; i < slots.count; ++i) {
            const slot = slots.get(i);
            if (wanted.has(slot.pid)) {
                root.write(i, wanted.get(slot.pid));
                seen.add(slot.pid);
            } else if (slot.kind !== "none") {
                slots.setProperty(i, "kind", "none");
            }
        }
        for (const e of root.entries) {
            if (seen.has(e.id))
                continue;
            let free = -1;
            for (let i = 0; i < slots.count; ++i) {
                const slot = slots.get(i);
                if (slot.kind === "none" && !wanted.has(slot.pid)) {
                    free = i;
                    break;
                }
            }
            if (free < 0)
                slots.append({ "pid": e.id, "px": e.x, "py": e.y, "pw": e.w, "ph": e.h, "kind": e.kind });
            else {
                slots.setProperty(free, "pid", e.id);
                root.write(free, e);
            }
        }
    }
    function write(i, e) {
        const slot = slots.get(i);
        const row = { "px": e.x, "py": e.y, "pw": e.w, "ph": e.h, "kind": e.kind };
        for (const key of Object.keys(row))
            if (slot[key] !== row[key])
                slots.setProperty(i, key, row[key]);
    }

    ListModel {
        id: slots
    }

    Item {
        id: selectionGroup
        anchors.fill: parent
        opacity: root.kinds.selected.alpha
        visible: root.selectionShown || selectionLinger.running
        layer.enabled: visible

        Repeater {
            model: slots

            delegate: Rectangle {
                id: selPlate
                required property real px
                required property real py
                required property real pw
                required property real ph
                required property string kind
                readonly property bool on: selPlate.kind === "selected" || selPlate.kind === "focus"

                x: selPlate.px
                y: selPlate.py
                width: selPlate.pw
                height: selPlate.ph
                radius: root.radius
                color: root.kinds.selected.color
                opacity: selPlate.on ? 1 : 0
                visible: opacity > 0.001

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(selPlate)
                }
            }
        }
        Repeater {
            model: root.bridges
            delegate: Rectangle {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
                color: root.kinds.selected.color
            }
        }
    }

    Repeater {
        model: slots

        delegate: Rectangle {
            id: plate
            required property real px
            required property real py
            required property real pw
            required property real ph
            required property string kind
            // Selected plates live in the merged group; focus adds only the
            // difference on top of it (0.7 group + 0.6 here ≈ 0.88).
            readonly property var look: plate.kind === "selected" ? null
                : plate.kind === "focus" ? ({ "color": root.kinds.focus.color, "alpha": 0.6 })
                : (root.kinds[plate.kind] ?? null)

            x: plate.px
            y: plate.py
            width: plate.pw
            height: plate.ph
            radius: root.radius
            color: plate.look ? Qt.alpha(plate.look.color, plate.look.alpha) : "transparent"
            opacity: plate.look ? 1 : 0
            visible: opacity > 0.001

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(plate)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(plate)
            }
        }
    }
}
