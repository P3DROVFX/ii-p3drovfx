import QtQuick

// Keyed adapter between immutable JS records and QML delegates. ScriptModel
// updates equal-key JS clones with dataChanged and removes only the trailing
// row, which is unsafe for DelegateChooser. This model emits exact insert,
// remove and move operations and never changes the type attached to an id.
ListModel {
    id: root

    property list<var> sourceValues: []
    property bool syncing: false

    function toArray(values) {
        if (!values)
            return [];
        if (Array.isArray(values))
            return values;
        var result = [];
        for (var index = 0; index < values.length; index++)
            result.push(values[index]);
        return result;
    }

    function normalizedRecord(value) {
        if (!value || typeof value.id !== "string" || value.id.length === 0
                || typeof value.type !== "string" || value.type.length === 0)
            return null;

        var payload = {
            id: value.id,
            type: value.type,
            sizeW: Math.max(1, Math.floor(Number(value.sizeW) || 1)),
            sizeH: Math.max(1, Math.floor(Number(value.sizeH) || 1))
        };
        if (value.layoutX !== undefined && value.layoutY !== undefined) {
            payload.layoutX = Number(value.layoutX);
            payload.layoutY = Number(value.layoutY);
        }
        return {
            itemId: payload.id,
            toggleType: payload.type,
            modelData: payload
        };
    }

    function indexOfId(itemId) {
        for (var index = 0; index < root.count; index++) {
            if (root.get(index).itemId === itemId)
                return index;
        }
        return -1;
    }

    function sameOptionalNumber(left, right) {
        if (left === undefined || right === undefined)
            return left === undefined && right === undefined;
        return Number(left) === Number(right);
    }

    function samePayload(left, right) {
        return left && right
            && left.id === right.id
            && left.type === right.type
            && Number(left.sizeW) === Number(right.sizeW)
            && Number(left.sizeH) === Number(right.sizeH)
            && root.sameOptionalNumber(left.layoutX, right.layoutX)
            && root.sameOptionalNumber(left.layoutY, right.layoutY);
    }

    function sync() {
        if (root.syncing)
            return;
        root.syncing = true;

        var desired = [];
        var desiredIds = Object.create(null);
        var source = root.toArray(root.sourceValues);
        for (var sourceIndex = 0; sourceIndex < source.length; sourceIndex++) {
            var record = root.normalizedRecord(source[sourceIndex]);
            if (!record) {
                console.warn("[StableQuickToggleModel] Ignoring invalid toggle record at index " + sourceIndex);
                continue;
            }
            if (desiredIds[record.itemId]) {
                console.warn("[StableQuickToggleModel] Ignoring duplicate toggle id: " + record.itemId);
                continue;
            }
            desiredIds[record.itemId] = true;
            desired.push(record);
        }

        // Remove by stable id, never by the new list length.
        for (var oldIndex = root.count - 1; oldIndex >= 0; oldIndex--) {
            if (!desiredIds[root.get(oldIndex).itemId])
                root.remove(oldIndex, 1);
        }

        for (var desiredIndex = 0; desiredIndex < desired.length; desiredIndex++) {
            var wanted = desired[desiredIndex];
            var existingIndex = root.indexOfId(wanted.itemId);
            if (existingIndex < 0) {
                root.insert(desiredIndex, wanted);
                continue;
            }

            // An id is permanently bound to one functional component. If
            // malformed input violates that contract, rebuild only this row.
            if (root.get(existingIndex).toggleType !== wanted.toggleType) {
                root.remove(existingIndex, 1);
                root.insert(desiredIndex, wanted);
                continue;
            }

            if (existingIndex !== desiredIndex)
                root.move(existingIndex, desiredIndex, 1);
            if (!root.samePayload(root.get(desiredIndex).modelData, wanted.modelData))
                root.setProperty(desiredIndex, "modelData", wanted.modelData);
        }

        root.syncing = false;
    }

    onSourceValuesChanged: root.sync()
    Component.onCompleted: root.sync()
}
