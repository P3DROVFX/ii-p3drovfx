import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * HH:MM on the clock's filled field surface, in the condensed digits of the clock tiles.
 * Inside the editor the field opens the window's time picker; elsewhere (no picker host
 * up the parent chain) it is typed. `committed` fires only with a valid time; an invalid
 * one turns the field red and falls back to the last good value when focus leaves.
 */
Rectangle {
    id: root

    property string value: "00:00"
    property string pickTitle: Translation.tr("Time")
    readonly property bool valid: ModeSchema.validTime(input.text)

    // The ClockPickerHost the editor's side panel carries, if any.
    readonly property Item pickers: {
        for (let p = root.parent; p; p = p.parent) {
            if (p.panels && p.panels.pickers)
                return p.panels.pickers;
        }
        return null;
    }

    signal committed(string value)

    function openPicker() {
        const parts = root.value.split(":");
        root.pickers.pickTime(parseInt(parts[0]) || 0, parseInt(parts[1]) || 0, root.pickTitle, (hour, minute) => {
            const time = String(hour).padStart(2, "0") + ":" + String(minute).padStart(2, "0");
            if (time !== root.value)
                root.committed(time);
        });
    }

    implicitWidth: 84
    implicitHeight: 40
    radius: ClockStyle.radiusSmall
    color: !root.valid ? ClockStyle.colErrorContainer
        : input.activeFocus || pickArea.containsMouse ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    StyledTextInput {
        id: input
        anchors.fill: parent
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        readOnly: root.pickers !== null
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
        Keys.onReturnPressed: event => {
            if (!root.pickers) {
                event.accepted = false;
                return;
            }
            root.openPicker();
        }
    }

    MouseArea {
        id: pickArea
        anchors.fill: parent
        visible: root.pickers !== null
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            input.forceActiveFocus();
            root.openPicker();
        }
    }
}
