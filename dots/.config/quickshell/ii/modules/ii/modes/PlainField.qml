import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * A single-line text field in the editor's pill style. The value is
 * committed on Enter or when focus leaves, never per keystroke, so a half
 * typed command is not saved (and applied) mid-way.
 */
Rectangle {
    id: root

    property string value: ""
    property string placeholder: ""
    property bool monospace: false

    signal committed(string value)

    implicitHeight: 36
    implicitWidth: 200
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer3
    border.width: input.activeFocus ? 2 : 0
    border.color: Appearance.colors.colPrimary

    StyledTextInput {
        id: input
        anchors {
            fill: parent
            leftMargin: 14
            rightMargin: 14
        }
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        color: Appearance.colors.colOnLayer3
        clip: true
        selectByMouse: true
        font.family: root.monospace ? Appearance.font.family.monospace : Appearance.font.family.main
        onEditingFinished: {
            if (input.text !== root.value)
                root.committed(input.text);
        }

        StyledText {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: !input.text.length
            text: root.placeholder
            elide: Text.ElideRight
            color: Appearance.colors.colSubtext
        }
    }
}
