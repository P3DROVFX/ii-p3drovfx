pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * One pairing question, asked the same way the settings page asks it.
 *
 * The code is set large on purpose: confirming a pairing means reading it off
 * this screen and comparing it against another device held at arm's length.
 */
WindowDialog {
    id: root
    backgroundWidth: 400

    /// Set by the window. The dialog animates out of its hidden state, so it has
    /// to spend one frame in it — and the window is only built at the moment the
    /// answer is already wanted.
    property bool wanted: false
    show: false

    readonly property var request: BluetoothAgent.request
    readonly property var passkeyDisplay: BluetoothAgent.display
    // A request always wins: the agent drops any displayed code the moment one
    // arrives, so the two are never live at the same time.
    readonly property var subject: root.request ?? root.passkeyDisplay
    readonly property bool asking: root.request !== null
    readonly property bool needsValue: BluetoothAgent.needsValue
    readonly property int queued: BluetoothAgent.queue.length

    readonly property string code: {
        if (root.asking)
            return root.request?.type === "confirm" ? BluetoothAgent.formatPasskey(root.request?.passkey) : "";
        if (root.passkeyDisplay?.type === "pincode")
            return root.passkeyDisplay?.pin ?? "";
        return BluetoothAgent.formatPasskey(root.passkeyDisplay?.passkey);
    }

    // A click anywhere outside the card dismisses a WindowDialog. Answering "no"
    // to a pairing on a stray click is far too easy to do by accident, so an
    // outside click is ignored here: only Escape or one of the buttons answers.
    onDismiss: {
        if (root.asking)
            return;
        BluetoothAgent.dismissDisplay();
    }

    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Escape)
            return;
        event.accepted = true;
        if (root.asking) {
            root.refuse();
            return;
        }
        BluetoothAgent.dismissDisplay();
    }

    onWantedChanged: {
        if (!root.wanted) {
            root.show = false;
            return;
        }
        Qt.callLater(() => root.show = root.wanted);
    }

    Component.onCompleted: Qt.callLater(() => root.show = root.wanted)

    // Refusing is an answer. Leaving the question alone is not: it pins the
    // BlueZ call open until it gives up on its own.
    function refuse(): void {
        BluetoothAgent.reject();
        secretField.text = "";
    }

    function send(): void {
        if (root.needsValue)
            BluetoothAgent.accept(secretField.text);
        else
            BluetoothAgent.accept();
        secretField.text = "";
    }

    // A queued question replaces the one just answered, and the field it may
    // need has to be empty and ready rather than holding the last answer.
    onRequestChanged: {
        secretField.text = "";
        if (root.needsValue)
            secretField.forceActiveFocus();
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: Icons.getBluetoothDeviceMaterialSymbol(root.subject?.icon ?? "")
            iconSize: Appearance.font.pixelSize.huge + 8
            color: Appearance.colors.colPrimary
        }

        WindowDialogTitle {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.asking ? BluetoothAgent.requestTitle(root.request)
                : Translation.tr("Enter this code on %1").arg(BluetoothAgent.requestName(root.passkeyDisplay))
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: (root.subject?.address ?? "").length > 0
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.subject?.address ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: root.code.length > 0
        text: root.code
        font.pixelSize: Appearance.font.pixelSize.huge
        font.weight: Font.Bold
        font.family: Appearance.font.family.monospace
        color: Appearance.colors.colPrimary
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: root.request?.type === "confirm"
        text: Translation.tr("Accept only if the same code is on the other device. If it is not, something else is answering for it.")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: (root.request?.uuid ?? "").length > 0
        text: Translation.tr("Service %1").arg(root.request?.uuid ?? "")
    }

    MaterialTextField {
        id: secretField
        Layout.fillWidth: true
        visible: root.needsValue
        placeholderText: root.request?.type === "pincode" ? Translation.tr("PIN") : Translation.tr("Passkey")
        onAccepted: root.send()
    }

    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: root.queued > 1
        text: Translation.tr("%1 more waiting").arg(root.queued - 1)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            visible: root.asking
            buttonText: Translation.tr("Reject")
            onClicked: root.refuse()
        }

        DialogButton {
            buttonText: root.asking ? (root.needsValue ? Translation.tr("Send") : Translation.tr("Accept"))
                : Translation.tr("Done")
            onClicked: {
                if (root.asking)
                    root.send();
                else
                    BluetoothAgent.dismissDisplay();
            }
        }
    }
}
