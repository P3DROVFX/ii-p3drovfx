import QtQuick
import qs.modules.common.widgets

/** Number row: the Settings app's StyledSpinBox (− value +, editable, wheel). */
CheatsheetSettingRow {
    id: stepRow

    property int value: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1

    signal moved(int value)

    StyledSpinBox {
        from: stepRow.from
        to: stepRow.to
        stepSize: stepRow.stepSize
        value: stepRow.value
        wheelEnabled: true
        onValueModified: stepRow.moved(value)
    }
}
