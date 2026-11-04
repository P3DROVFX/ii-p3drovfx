pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `shell` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 60
            text: Translation.tr("On start")
        }

        PlainField {
            Layout.fillWidth: true
            monospace: true
            value: String(typeof row.value === "object" ? (row.obj.start ?? "") : (row.value ?? ""))
            placeholder: Translation.tr("Command, run with sh -c")
            onCommitted: v => row.patchValue({ start: v, end: row.obj.end ?? "", track: row.obj.track === true })
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 60
            text: Translation.tr("On end")
        }

        PlainField {
            Layout.fillWidth: true
            monospace: true
            value: String(row.obj.end ?? "")
            placeholder: Translation.tr("Optional")
            onCommitted: v => row.patchValue({ start: row.obj.start ?? "", end: v, track: row.obj.track === true })
        }
    }

    // Tracked: output, exit status and the command's ::ii-report go to the
    // Activity tab and a notification when it finishes (services/modes/ModeTasks.qml).
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        StyledSwitch {
            checked: row.obj.track === true
            onClicked: row.patchValue({ start: row.obj.start ?? (typeof row.value === "string" ? row.value : ""), end: row.obj.end ?? "", track: checked })
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("Report the result")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Translation.tr("Keeps its output, notifies when it ends and shows how it went in Activity")
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }
}
