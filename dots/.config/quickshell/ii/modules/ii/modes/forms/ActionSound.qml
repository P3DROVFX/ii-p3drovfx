pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `playSound` action: a file to play once. `row` is
 * the ActionRow this form unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: soundCol
    required property var row

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        PlainField {
            Layout.fillWidth: true
            monospace: true
            value: String(row.value ?? "")
            placeholder: Translation.tr("Absolute path to an audio file")
            onCommitted: v => row.setValue(v.trim())
        }

        SmallButton {
            buttonText: Translation.tr("Try it")
            enabled: String(row.value ?? "").trim().length > 0
            opacity: enabled ? 1 : 0.5
            onClicked: SoundService.previewFile(String(row.value ?? "").trim())
        }
    }

    FormHint {
        text: Translation.tr("Plays even with system sounds off")
    }
}
