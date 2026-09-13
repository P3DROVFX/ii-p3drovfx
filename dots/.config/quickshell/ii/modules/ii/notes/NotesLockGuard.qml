pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * What a locked note shows instead of itself.
 *
 * The digest comparison happens here rather than in the pane, so the PIN never becomes a
 * property anything else can read: the field's text goes into `Qt.md5` and nowhere.
 */
Rectangle {
    id: root

    /// `md5(salt + pin)`, from the app's own state.
    property string digest: ""
    property string salt: ""

    signal unlocked()

    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainerHigh

    onVisibleChanged: {
        if (!root.visible)
            return;
        pinField.text = "";
        root.wrong = false;
        // The caret belongs in the one field on screen. Anything else asks the reader to
        // find it first, and this cover is the only thing they can interact with.
        focusTimer.restart();
    }

    Timer {
        id: focusTimer
        interval: 60
        onTriggered: pinField.forceActiveFocus()
    }

    property bool wrong: false

    function attempt(): void {
        if (root.digest.length > 0 && Qt.md5(root.salt + pinField.text) === root.digest) {
            pinField.text = "";
            root.wrong = false;
            root.unlocked();
        } else {
            root.wrong = true;
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 360)
        spacing: 12

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "lock"
            iconSize: 48
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("This note is locked")
            font.pixelSize: Appearance.font.pixelSize.huge
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Type the PIN to read it.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        MaterialTextField {
            id: pinField
            Layout.alignment: Qt.AlignHCenter
            // Room for the label to float into, instead of on top of the line above.
            Layout.topMargin: 6
            Layout.preferredWidth: 200
            horizontalAlignment: TextInput.AlignHCenter
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData
            error: root.wrong
            placeholderText: Translation.tr("PIN")

            onTextChanged: root.wrong = false
            onAccepted: root.attempt()
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("That is not the PIN.")
            visible: root.wrong
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3error
        }

        RippleButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 44
            implicitWidth: 140
            buttonRadius: NotesMetrics.pillRadius(44)
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colBackgroundActive: Appearance.colors.colPrimaryActive
            enabled: pinField.text.length > 0

            onClicked: root.attempt()

            contentItem: StyledText {
                anchors.centerIn: parent
                text: Translation.tr("Unlock")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
