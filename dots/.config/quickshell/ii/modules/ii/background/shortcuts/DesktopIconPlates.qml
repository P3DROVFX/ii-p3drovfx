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

    Repeater {
        model: slots

        delegate: Rectangle {
            id: plate
            required property real px
            required property real py
            required property real pw
            required property real ph
            required property string kind
            readonly property var look: root.kinds[plate.kind] ?? null

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
