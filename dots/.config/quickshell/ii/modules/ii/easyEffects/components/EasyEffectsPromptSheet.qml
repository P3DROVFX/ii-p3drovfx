import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** One text field in a side sheet: name a preset. Enter confirms, Escape backs out. */
EasyEffectsSheet {
    id: root

    property string initialText: ""
    property string caption: Translation.tr("Name")
    property string placeholder: ""
    property string symbol: "edit"
    property string confirmLabel: Translation.tr("Save")

    signal submitted(string text)

    badge: root.symbol

    function submit(): void {
        root.submitted(field.text.trim());
        root.close();
    }

    Component.onCompleted: {
        field.text = root.initialText;
        Qt.callLater(field.focusInput);
    }

    ClockFormField {
        id: field
        symbol: root.symbol
        caption: root.caption
        placeholder: root.placeholder
        onAccepted: root.submit()
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Cancel")
            symbol: "close"
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            label: root.confirmLabel
            symbol: "check"
            onClicked: root.submit()
        }
    ]
}
