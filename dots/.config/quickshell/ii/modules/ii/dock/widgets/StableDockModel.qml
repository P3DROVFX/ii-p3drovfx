import QtQuick

// Keep QObject payloads (including live windows) out of ListModel roles. Only
// identity goes through the model; immutable records remain ordinary JS data.
ListModel {
    id: root

    property var sourceValues: []
    property string keyRole: "orderKey"
    property var keyFunction: null
    property var itemsByKey: ({})
    property bool syncing: false

    function sync() {
        if (syncing)
            return;
        syncing = true;
        const desired = [];
        const records = Object.create(null);
        for (const value of sourceValues ?? []) {
            const key = String(keyFunction ? keyFunction(value) : (value?.[keyRole] ?? ""));
            if (!key || records[key] !== undefined)
                continue;
            records[key] = value;
            desired.push({ entryKey: key, entryType: String(value.type ?? "") });
        }
        // Retain departing payloads until their delegates have been removed.
        itemsByKey = Object.assign({}, itemsByKey, records);
        for (let index = count - 1; index >= 0; index--) {
            if (records[get(index).entryKey] === undefined)
                remove(index);
        }
        for (let index = 0; index < desired.length; index++) {
            const row = desired[index];
            let found = index;
            while (found < count && get(found).entryKey !== row.entryKey)
                found++;
            if (found === count) {
                insert(index, row);
            } else if (get(found).entryType !== row.entryType) {
                remove(found);
                insert(index, row);
            } else if (found !== index) {
                move(found, index, 1);
            }
        }
        itemsByKey = records;
        syncing = false;
    }

    onSourceValuesChanged: sync()
    Component.onCompleted: sync()
}
