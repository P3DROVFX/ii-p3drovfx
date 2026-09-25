pragma ComponentBehavior: Bound
import QtQuick

/**
 * Lazy host for DatePickerPopup.
 *
 * The popup carries a whole second month grid — its own `H.buildMonthCells`
 * pass, a delegate per day and a `CalendarService.eventsByDay` read per day —
 * and both calendar views declare it as a plain child, so all of that was
 * built on every open of the page whether or not the rail was ever used.
 * The host builds the real popup on the first request and keeps it afterwards,
 * so the second request is as instant as it was before.
 *
 * Interface is the popup's with the caller's selector kept on the host, which
 * is what the views already read back in their `accepted` handler: `purpose`,
 * `open(date, titleText)`, `close()` and `accepted`.
 * Same idiom as DeferredEventSidebar and DeferredKeybindEditor.
 */
Loader {
    id: root

    /** What the caller is picking a date for. Read back on `accepted`. */
    property string purpose: "form"

    active: false
    signal accepted(var pickedDate)

    function ensure() {
        if (!item) {
            active = true;
            setSource(Qt.resolvedUrl("DatePickerPopup.qml"));
        }
        return item;
    }

    function open(date, titleText) {
        const picker = ensure();
        picker.open(date, titleText);
    }

    function close() {
        if (item)
            item.close();
    }

    Connections {
        target: root.item

        function onAccepted(pickedDate) {
            root.accepted(pickedDate);
        }
    }
}