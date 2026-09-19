import QtQuick

/**
 * The tray's sections, keyed by section id.
 *
 * A Repeater over a plain JS array rebuilds every delegate whenever the array is
 * replaced, and the tray's section list is recomputed on every edit - so adding or
 * removing one tile destroyed and recreated every section and every tile in the tray
 * (~165 ms with the full catalog, the same as opening edit mode). This adapter keeps a
 * section's delegate for as long as its id exists: a changed section only has its
 * `sectionData` role updated, and the tiles inside it are kept by their own keyed model
 * (StableQuickToggleModel), so an edit touches only the tiles that actually moved.
 */
ListModel {
    id: root

    dynamicRoles: true

    /** The sections, as AndroidQuickPanel.traySections builds them: { id, ... }. */
    property var sourceValues: []

    function indexOfId(sectionId) {
        for (let index = 0; index < root.count; index++) {
            if (root.get(index).sectionId === sectionId)
                return index;
        }
        return -1;
    }

    function sync() {
        const next = root.sourceValues || [];
        const wanted = next.map(section => section.id);

        // Drop sections that are gone, from the end so indices stay valid.
        for (let index = root.count - 1; index >= 0; index--) {
            if (wanted.indexOf(root.get(index).sectionId) === -1)
                root.remove(index);
        }

        // Insert, move and update in order.
        for (let target = 0; target < next.length; target++) {
            const section = next[target];
            const current = root.indexOfId(section.id);
            if (current === -1) {
                root.insert(target, { sectionId: section.id, sectionData: section });
                continue;
            }
            if (current !== target)
                root.move(current, target, 1);
            root.setProperty(target, "sectionData", section);
        }
    }

    onSourceValuesChanged: root.sync()
    Component.onCompleted: root.sync()
}
