pragma ComponentBehavior: Bound
import QtQuick

/**
 * Lazy host for TimePickerPopup.
 *
 * The dial, its two rings, the typed fields and their geometry bindings are
 * only meaningful once the rail editor asks for a time, but both calendar
 * views declare the popup as a plain child, so it was built on every open of
 * the page: `visible: false` does not stop QML from constructing a tree, and
 * the popup still cost its 24 ring delegates plus every binding inside them
 * during the burst a tab click has to pay. The host builds the real popup on
 * the first request and keeps it afterwards, so the second request is as
 * instant as it was before.
 *
 * Interface is the popup's with the caller's selector kept on the host, which
 * is what the views already read back in their `accepted` handler: `target`,
 * `open(startHour, startMinute, titleText)`, `close()` and `accepted`.
 * Same idiom as DeferredEventSidebar and DeferredKeybindEditor.
 */
Loader {
    id: root

    /** Which end of the range the caller is editing. Read back on `accepted`. */
    property string target: "start"

    active: false
    signal accepted(int pickedHour, int pickedMinute)

    function ensure() {
        if (!item) {
            active = true;
            setSource(Qt.resolvedUrl("TimePickerPopup.qml"));
        }
        return item;
    }

    function open(startHour, startMinute, titleText) {
        const picker = ensure();
        picker.open(startHour, startMinute, titleText);
    }

    function close() {
        if (item)
            item.close();
    }

    Connections {
        target: root.item

        function onAccepted(pickedHour, pickedMinute) {
            root.accepted(pickedHour, pickedMinute);
        }
    }
}