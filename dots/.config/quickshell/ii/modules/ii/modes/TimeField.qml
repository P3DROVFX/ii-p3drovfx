import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * HH:MM on the clock's filled field surface, in the condensed digits of the clock tiles.
 * `committed` fires only with a valid time; an invalid one turns the indicator red and
 * falls back to the last good value when focus leaves.
 */
Rectangle {
    id: root

    property string value: "00:00"
    readonly property bool valid: ModeSchema.validTime(input.text)

    signal committed(string value)

    implicitWidth: 84
    implicitHeight: 40
    radius: ClockStyle.radiusSmall
    color: !root.valid ? ClockStyle.colErrorContainer
        : input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    StyledTextInput {
        id: input
        anchors.fill: parent
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        color: root.valid ? ClockStyle.colOnSurface : ClockStyle.colOnErrorContainer
        inputMask: "99:99"
        font.family: ClockStyle.fontMain
        font.variableAxes: ClockStyle.axesDigitsBold
        font.pixelSize: ClockStyle.textLarge + 3
        onEditingFinished: {
            if (root.valid && input.text !== root.value)
                root.committed(input.text);
            else if (!root.valid)
                input.text = root.value;
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: root.radius / 2
            rightMargin: root.radius / 2
        }
        height: 2
        radius: 1
        color: root.valid ? ClockStyle.colPrimary : ClockStyle.colError
        opacity: input.activeFocus || !root.valid ? 1 : 0
    }
}
