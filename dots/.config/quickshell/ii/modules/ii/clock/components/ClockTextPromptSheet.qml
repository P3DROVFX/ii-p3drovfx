import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** One text field in a sheet: rename a city, label a timer. */
ClockSheet {
    id: root

    property string placeholder: ""
    property string confirmLabel: Translation.tr("Save")

    signal submitted(string text)

    function openWith(text: string): void {
        field.text = String(text ?? "");
        root.open();
        field.forceActiveFocus();
        field.selectAll();
    }

    function submit(): void {
        root.submitted(field.text.trim());
        root.close();
    }

    MaterialTextField {
        id: field
        Layout.fillWidth: true
        placeholderText: root.placeholder
        onAccepted: root.submit()
    }

    actions: [
        Item {
            Layout.fillWidth: true
        },
        ClockButton {
            variant: "text"
            label: Translation.tr("Cancel")
            onClicked: root.close()
        },
        ClockButton {
            variant: "filled"
            label: root.confirmLabel
            onClicked: root.submit()
        }
    ]
}
