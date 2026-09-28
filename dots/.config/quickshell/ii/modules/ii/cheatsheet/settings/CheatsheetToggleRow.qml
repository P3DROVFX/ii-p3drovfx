import QtQuick
import qs.modules.common.widgets

/** Boolean row: the whole row toggles, the switch mirrors it. */
CheatsheetSettingRow {
    id: toggleRow

    property bool checked: false

    signal toggled(bool value)

    clickable: true
    onClicked: toggleRow.toggled(!toggleRow.checked)

    StyledSwitch {
        checked: toggleRow.checked
        onToggled: toggleRow.toggled(checked)
    }
}
