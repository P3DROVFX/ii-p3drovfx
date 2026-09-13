import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import "../../../services/modes/ModeSchema.js" as ModeSchema

/** HH:MM field in the pill style; `committed` fires only with a valid time. */
Rectangle {
    id: root
    property string value: "00:00"
    signal committed(string value)
    readonly property bool valid: ModeSchema.validTime(input.text)

    implicitWidth: 72
    implicitHeight: 36
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer3
    border.width: input.activeFocus ? 2 : (root.valid ? 0 : 1)
    border.color: root.valid ? Appearance.colors.colPrimary : Appearance.colors.colError

    StyledTextInput {
        id: input
        anchors.fill: parent
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        color: Appearance.colors.colOnLayer3
        inputMask: "99:99"
        font.family: Appearance.font.family.numbers
        onEditingFinished: {
            if (root.valid && input.text !== root.value)
                root.committed(input.text);
            else if (!root.valid)
                input.text = root.value;
        }
    }
}
