pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Hiding a note behind a PIN, and saying plainly what that is worth.
 *
 * The first version of this offered a field pre-filled with the placeholder "1234", took
 * "1234" as the default when the field was left empty, wrote the PIN in clear beside the
 * note it was supposed to protect, and — because it wrote it into a `meta` field the index
 * has never had — did not persist any of it: every lock survived until the next reload.
 *
 * This one asks for a PIN once, keeps `md5(salt + pin)` instead of the PIN, has no default,
 * and refuses to be set at all until four characters are typed. It still tells the truth in
 * the last line: the notes on disk are plain files, so this hides a note from somebody
 * glancing over a shoulder and from nobody else.
 */
Rectangle {
    id: root

    /// Whether a PIN has been chosen for the app at all.
    property bool hasPin: false
    /// Whether *this* note is locked.
    property bool noteLocked: false

    /// A new PIN, chosen here. The caller stores the digest and locks the note.
    signal pinChosen(string pin)
    /// Lock this note with the PIN that already exists.
    signal lockRequested()
    /// Take the lock off this note. The PIN itself stays for the others.
    signal unlockRequested()

    implicitWidth: 320
    implicitHeight: layout.implicitHeight + 32
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainerHighest

    onVisibleChanged: {
        if (!root.visible)
            return;
        pinField.text = "";
        if (!root.hasPin)
            pinField.forceActiveFocus();
    }

    StyledRectangularShadow {
        target: root
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 10

        StyledText {
            Layout.fillWidth: true
            text: root.noteLocked
                ? Translation.tr("This note is locked")
                : (root.hasPin ? Translation.tr("Lock this note") : Translation.tr("Choose a PIN"))
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            text: root.noteLocked
                ? Translation.tr("It asks for the PIN each time the shell starts.")
                : (root.hasPin
                    ? Translation.tr("It will ask for the PIN you already use.")
                    : Translation.tr("The same PIN opens every locked note. At least four characters."))
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        MaterialTextField {
            id: pinField
            Layout.fillWidth: true
            // The label floats up out of the field when it takes focus, into whatever is
            // above it — which was the line explaining what the PIN is for.
            Layout.topMargin: 6
            visible: !root.noteLocked && !root.hasPin
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData
            placeholderText: Translation.tr("New PIN")

            onAccepted: {
                if (pinField.text.length >= 4)
                    root.pinChosen(pinField.text);
            }
        }

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 44
            buttonRadius: NotesMetrics.pillRadius(44)
            enabled: root.noteLocked || root.hasPin || pinField.text.length >= 4
            colBackground: root.noteLocked
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colPrimary
            colBackgroundHover: root.noteLocked
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colPrimaryHover

            onClicked: {
                if (root.noteLocked)
                    root.unlockRequested();
                else if (root.hasPin)
                    root.lockRequested();
                else if (pinField.text.length >= 4)
                    root.pinChosen(pinField.text);
            }

            contentItem: StyledText {
                anchors.centerIn: parent
                text: root.noteLocked
                    ? Translation.tr("Remove the lock")
                    : Translation.tr("Lock")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.noteLocked
                    ? Appearance.m3colors.m3onErrorContainer
                    : Appearance.colors.colOnPrimary
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 2
            text: Translation.tr("The note itself is stored as a plain file. This hides it on screen; it does not encrypt it.")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}
