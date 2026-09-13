pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `calendar` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            text: Translation.tr("Title contains")
        }

        PlainField {
            Layout.fillWidth: true
            value: row.trigger.match
            placeholder: Translation.tr("Empty means any event")
            onCommitted: v => row.set({ match: v })
        }
    }

    FormHint {
        text: CalendarService.khalAvailable
            ? Translation.tr("Holds from the event's start to its end; also matches the calendar's name.")
            : Translation.tr("Needs khal, which the calendar widget reads events from.")
    }
}
