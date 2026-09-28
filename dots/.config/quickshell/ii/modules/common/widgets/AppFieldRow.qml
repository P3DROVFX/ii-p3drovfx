import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

/** Text row: the field sits under the title, full width. */
AppSettingRow {
    id: fieldRow

    property string value: ""
    property string placeholder: ""
    property alias field: textField

    signal edited(string text)
    signal accepted()

    below: MaterialTextField {
        id: textField
        Layout.fillWidth: true
        placeholderText: fieldRow.placeholder
        text: fieldRow.value
        onTextChanged: if (text !== fieldRow.value) fieldRow.edited(text)
        onAccepted: fieldRow.accepted()
    }
}
