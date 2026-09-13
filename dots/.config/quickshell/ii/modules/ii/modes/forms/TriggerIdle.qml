pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `idle` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("No input for")
        }

        DurationField {
            seconds: row.trigger.sec
            minimum: 1
            onCommitted: sec => row.set({ sec: Math.max(5, sec) })
        }
    }

    RowLayout {
        spacing: 10

        StyledSwitch {
            checked: row.trigger.ignoreInhibitors === true
            onClicked: row.set({ ignoreInhibitors: checked })
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            FormLabel {
                text: Translation.tr("Even while Keep Awake is on")
            }

            FormHint {
                text: Translation.tr("Off: an idle inhibitor (a movie, Keep Awake) counts as activity")
            }
        }
    }
}
