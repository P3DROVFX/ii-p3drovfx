pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `deviceInUse` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.what
        onPicked: v => row.set({ what: v })
        options: [
            { displayName: Translation.tr("Microphone"), value: "mic" },
            { displayName: Translation.tr("Camera"), value: "camera" },
            { displayName: Translation.tr("Screen capture"), value: "screen" }
        ]
    }

    FormHint {
        text: Translation.tr("An app is reading from it right now — a call, a recording, a screen share.")
    }
}
