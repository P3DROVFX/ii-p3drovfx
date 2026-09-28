import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The PIN, asked for before a protected change. Unlocking holds for ten minutes, so a
 * round of edits asks once; `unlockAction` then runs whatever was waiting on it.
 */
ClockSheet {
    id: root

    property var unlockAction: null
    property bool wrong: false

    function submit(): void {
        if (!ScreenTimeLimits.unlockEdits(pinField.text)) {
            pinField.text = "";
            root.wrong = true;
            pinField.focusInput();
            return;
        }
        const next = root.unlockAction;
        root.close();
        if (typeof next === "function")
            Qt.callLater(next);
    }

    title: Translation.tr("Enter PIN")
    subtitle: Translation.tr("Limits are protected")

    Component.onCompleted: Qt.callLater(() => pinField.focusInput())

    MaterialShapeWrappedMaterialSymbol {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: ClockStyle.gapHuge
        Layout.bottomMargin: ClockStyle.gap
        text: root.wrong ? "lock_reset" : "lock"
        iconSize: 44
        padding: 26
        shape: MaterialShape.Shape.Cookie9Sided
        color: root.wrong ? ClockStyle.colErrorContainer : ClockStyle.colSecondaryContainer
        colSymbol: root.wrong ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer
        fill: 1
        rotation: root.wrong ? 30 : 0
        Behavior on rotation {
            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
        }
    }

    ClockFormField {
        id: pinField
        symbol: "password"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        caption: Translation.tr("PIN")
        placeholder: Translation.tr("Enter your PIN")
        input.echoMode: TextInput.Password
        onAccepted: root.submit()
        onTextChanged: if (text.length > 0) root.wrong = false
    }

    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: root.wrong ? Translation.tr("Wrong PIN") : Translation.tr("Unlocks changes for 10 minutes")
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: root.wrong ? Font.Bold : Font.Normal
        color: root.wrong ? ClockStyle.colError : ClockStyle.colSubtext
    }

    actions: [
        ClockSheetAction {
            Layout.fillWidth: true
            label: Translation.tr("Cancel")
            onClicked: root.close()
        },
        ClockSheetAction {
            Layout.fillWidth: true
            primary: true
            symbol: "lock_open"
            label: Translation.tr("Unlock")
            enabled: pinField.text.length > 0
            onClicked: root.submit()
        }
    ]
}
