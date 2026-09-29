import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/**
 * The desktop widgets the lock screen keeps, at screen size: each one the real
 * widget built as a preview (`isPreview`, as the Widgets page shows them — no
 * drag, no placement of its own) and put where the lock puts it:
 *
 *  - "keep", "custom" and "lockOnly" at their lock placement (WidgetPlacement's lock
 *    fork, or the desktop position when there is none);
 *  - "center" ones in a row or a column through the middle of the screen, with the
 *    configured spacing — the same arithmetic as AbstractBackgroundWidget's
 *    centeredOffsetX/Y, measured on the built widgets.
 *
 * Every widget scales about its centre, like the real ones, by its own scale times
 * the global widget scale.
 *
 * `atLock: false` puts every widget back on its desktop placement instead; flipping
 * it glides them between the two, which is how the Always On Display raised from the
 * desktop carries the widgets to where the lock keeps them.
 */
Item {
    id: root

    property string monitorName: ""
    property bool atLock: true
    property real burnInShiftX: 0
    property real burnInShiftY: 0

    readonly property var lock: Config.options.lock
    readonly property real globalScale: Config.options.background.widgets.widgetsScale ?? 1.0
    readonly property var registry: {
        const map = {};
        const list = WidgetsRegistry.allWidgets;
        for (let i = 0; i < list.length; i++)
            map[list[i].widgetId] = list[i];
        return map;
    }
    readonly property var entries: {
        const list = Config.options.background.activeWidgets || [];
        const shown = [];
        for (let i = 0; i < list.length; i++) {
            const behavior = list[i].lockBehavior || "hide";
            if (behavior === "hide" || !root.registry[list[i].widgetId])
                continue;
            shown.push(list[i]);
        }
        return shown;
    }
    readonly property var centeredIds: root.entries.filter(e => e.lockBehavior === "center").map(e => e.id)

    // Built sizes by instance id, filled in as the widgets load.
    property var sizes: ({})
    property int sizesVersion: 0
    function report(id: string, width: real, height: real) {
        const old = root.sizes[id];
        if (old && old.width === width && old.height === height)
            return;
        root.sizes[id] = { "width": width, "height": height };
        root.sizesVersion++;
    }

    function scaleOf(entry: var): real {
        const placement = WidgetPlacement.resolve(entry, root.monitorName, root.atLock, root.width, root.height);
        return (placement.scale ?? 1.0) * root.globalScale;
    }

    // Visual (scaled) offset of a centred widget from the group's start, and the group's length.
    function centeredLayout(): var {
        root.sizesVersion;
        const vertical = root.lock.centerAlignment === "vertical";
        const spacing = root.lock.centerSpacing || 20;
        const offsets = {};
        let total = 0;
        for (let i = 0; i < root.centeredIds.length; i++) {
            const id = root.centeredIds[i];
            const entry = root.entries.find(e => e.id === id);
            const size = root.sizes[id] || { "width": 0, "height": 0 };
            const length = (vertical ? size.height : size.width) * root.scaleOf(entry);
            offsets[id] = { "start": total, "length": length };
            total += length + (i < root.centeredIds.length - 1 ? spacing : 0);
        }
        return { "vertical": vertical, "offsets": offsets, "total": total };
    }

    Repeater {
        model: root.entries

        Item {
            id: slot

            required property var modelData
            readonly property var meta: root.registry[slot.modelData.widgetId]
            readonly property bool centered: root.atLock && slot.modelData.lockBehavior === "center"
            readonly property var placement: WidgetPlacement.resolve(slot.modelData, root.monitorName, root.atLock, root.width, root.height)
            readonly property real naturalWidth: widgetLoader.item ? (widgetLoader.item.implicitWidth || widgetLoader.item.width) : 0
            readonly property real naturalHeight: widgetLoader.item ? (widgetLoader.item.implicitHeight || widgetLoader.item.height) : 0
            readonly property var centeredPlace: {
                if (!slot.centered)
                    return null;
                const layout = root.centeredLayout();
                const offset = layout.offsets[slot.modelData.id] ?? { "start": 0, "length": 0 };
                // The scaled box's start along the axis, then back to the unscaled item's corner.
                const visualStart = (layout.vertical ? root.height : root.width) / 2 - layout.total / 2 + offset.start;
                const along = visualStart - ((layout.vertical ? slot.height : slot.width) * (1 - slot.scale)) / 2;
                return layout.vertical
                    ? { "x": (root.width - slot.width) / 2, "y": along }
                    : { "x": along, "y": (root.height - slot.height) / 2 };
            }

            width: slot.naturalWidth
            height: slot.naturalHeight
            scale: root.scaleOf(slot.modelData)
            x: (slot.centered ? slot.centeredPlace.x : slot.placement.x) + root.burnInShiftX
            y: (slot.centered ? slot.centeredPlace.y : slot.placement.y) + root.burnInShiftY
            opacity: widgetLoader.status === Loader.Ready ? 1 : 0
            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on scale {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            onNaturalWidthChanged: root.report(slot.modelData.id, slot.naturalWidth, slot.naturalHeight)
            onNaturalHeightChanged: root.report(slot.modelData.id, slot.naturalWidth, slot.naturalHeight)

            Loader {
                id: widgetLoader
                asynchronous: true
                source: slot.meta ? slot.meta.qmlPath : ""

                Binding {
                    target: widgetLoader.item
                    property: "isPreview"
                    value: true
                    when: widgetLoader.status === Loader.Ready
                }
                Binding {
                    target: widgetLoader.item
                    property: "screenWidth"
                    value: root.width
                    when: widgetLoader.status === Loader.Ready
                }
                Binding {
                    target: widgetLoader.item
                    property: "screenHeight"
                    value: root.height
                    when: widgetLoader.status === Loader.Ready
                }
                Binding {
                    target: widgetLoader.item
                    property: "scaledScreenWidth"
                    value: root.width
                    when: widgetLoader.status === Loader.Ready
                }
                Binding {
                    target: widgetLoader.item
                    property: "scaledScreenHeight"
                    value: root.height
                    when: widgetLoader.status === Loader.Ready
                }
                Binding {
                    target: widgetLoader.item
                    property: "wallpaperScale"
                    value: 1.0
                    when: widgetLoader.status === Loader.Ready
                }
                Binding {
                    target: widgetLoader.item
                    property: "styleOverride"
                    value: WidgetsRegistry.getStyleOverride(slot.modelData.widgetId) || ""
                    when: widgetLoader.status === Loader.Ready
                }
            }
        }
    }
}
