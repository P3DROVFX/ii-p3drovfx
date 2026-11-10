import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * AnkiWeb sign-in. The password goes to AnkiWeb once, through Anki's own client code;
 * only the session key it returns is kept (~/.local/share/ii-anki/auth.json, 0600).
 */
AnkiSheet {
    id: root

    property bool busy: false
    property string error: ""

    title: Translation.tr("Sign in to AnkiWeb")
    subtitle: Translation.tr("Syncs this computer with your Anki account. An empty collection downloads everything from AnkiWeb.")

    function submit() {
        if (root.busy || emailField.text.trim().length === 0 || passwordField.text.length === 0)
            return;
        root.busy = true;
        root.error = "";
        Anki.login(emailField.text, passwordField.text, (ok, data) => {
            root.busy = false;
            if (ok)
                root.dismissed();
            else
                root.error = String(data);
        });
    }

    Component.onCompleted: emailField.focusInput()

    ClockFormField {
        id: emailField
        symbol: "mail"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        caption: Translation.tr("Email")
        placeholder: "you@example.com"
        onAccepted: passwordField.focusInput()
    }

    ClockFormField {
        id: passwordField
        symbol: "key"
        shapeKind: MaterialShape.Shape.Clover4Leaf
        caption: Translation.tr("Password")
        input.echoMode: TextInput.Password
        onAccepted: root.submit()
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: ClockStyle.gapTiny
        visible: root.error.length > 0
        wrapMode: Text.Wrap
        text: root.error
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.m3colors.m3error
    }

    footer: [
        ClockSheetAction {
            label: Translation.tr("Cancel")
            onClicked: root.dismissed()
        },
        ClockSheetAction {
            primary: true
            enabled: !root.busy
            symbol: root.busy ? "hourglass_top" : "login"
            label: root.busy ? Translation.tr("Signing in…") : Translation.tr("Sign in")
            onClicked: root.submit()
        }
    ]
}
