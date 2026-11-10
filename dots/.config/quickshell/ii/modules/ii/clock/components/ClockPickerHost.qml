import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The shell's time and date pickers — the same TimePickerPopup the dashboard's clock uses
 * and the timetable's rail mirrors — owned by the window so they centre over the whole
 * app rather than over the narrow side sheet that asked for them.
 *
 * Built on the first request and released once closed. A caller hands a callback with the
 * request, so a sheet never needs to know where the picker lives.
 */
Item {
    id: root

    property var timeCallback: null
    property var dateCallback: null

    function pickTime(hour: int, minute: int, title: string, callback): void {
        root.timeCallback = callback;
        timeLoader.active = true;
        timeLoader.item.open(hour, minute, title);
    }

    function pickDate(date, title: string, callback): void {
        root.dateCallback = callback;
        dateLoader.active = true;
        dateLoader.item.open(date, title);
    }

    Loader {
        id: timeLoader
        anchors.fill: parent
        active: false
        sourceComponent: TimePickerPopup {
            keyboardShortcutsEnabled: true
            onAccepted: (hour, minute) => {
                if (typeof root.timeCallback === "function")
                    root.timeCallback(hour, minute);
            }
            onOpenedChanged: if (!opened) releaseTimer.restart()
        }
    }

    Loader {
        id: dateLoader
        anchors.fill: parent
        active: false
        sourceComponent: DatePickerPopup {
            onAccepted: date => {
                if (typeof root.dateCallback === "function")
                    root.dateCallback(date);
            }
            onOpenedChanged: if (!opened) releaseTimer.restart()
        }
    }

    Timer {
        id: releaseTimer
        interval: ClockStyle.motionExit.duration + ClockStyle.motionFast.duration
        onTriggered: {
            if (timeLoader.item && !timeLoader.item.opened) {
                timeLoader.active = false;
                root.timeCallback = null;
            }
            if (dateLoader.item && !dateLoader.item.opened) {
                dateLoader.active = false;
                root.dateCallback = null;
            }
        }
    }
}
