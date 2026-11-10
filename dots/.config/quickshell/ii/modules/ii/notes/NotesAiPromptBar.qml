pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * The compact prompt used to ask the note writer for new content.
 *
 * The field and its action stay together so opening AI does not make the title bar jump
 * between unrelated layouts. A running request keeps the same surface and turns the send
 * action into a stop action, which makes the waiting state visible without another sheet.
 */
Item {
    id: root

    property bool running: false
    property string errorText: ""
    property string modelName: ""
    property alias text: promptInput.text

    signal submitted(string prompt)
    signal cancelled()
    signal dismissed()

    implicitHeight: NotesMetrics.iconButtonSize

    function submit(): void {
        if (root.running) {
            root.cancelled();
            return;
        }
        const prompt = promptInput.text.trim();
        if (prompt.length > 0)
            root.submitted(prompt);
    }

    function focusInput(): void {
        promptInput.forceActiveFocus();
        promptInput.cursorPosition = promptInput.length;
    }

    RowLayout {
        anchors.fill: parent
        spacing: NotesMetrics.cardSpacing

        Rectangle {
            id: promptPill
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: NotesMetrics.pillRadius(height)
            color: Appearance.m3colors.m3surfaceContainerHighest
            clip: true

            StyledTextInput {
                id: promptInput
                anchors.fill: parent
                anchors.leftMargin: NotesMetrics.cardPadding
                anchors.rightMargin: NotesMetrics.cardPadding
                verticalAlignment: TextInput.AlignVCenter
                activeFocusOnTab: true
                readOnly: root.running
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.normal
                clip: true

                onAccepted: root.submit()

                Keys.onEscapePressed: event => {
                    event.accepted = true;
                    if (root.running)
                        root.cancelled();
                    else
                        root.dismissed();
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.errorText.length > 0
                        ? Translation.tr("Try again…")
                        : Translation.tr("Describe what to write…")
                    font: promptInput.font
                    color: root.errorText.length > 0
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colOnLayer1Inactive
                    visible: promptInput.text.length === 0
                }
            }
        }

        NotesIconButton {
            id: sendButton
            size: NotesMetrics.iconButtonSize
            iconSize: Appearance.font.pixelSize.large
            symbol: root.running ? "stop" : "send"
            tooltipText: root.running
                ? Translation.tr("Stop writing")
                : root.errorText.length > 0
                    ? root.errorText
                    : Translation.tr("Write with %1").arg(root.modelName)
            colIcon: root.errorText.length > 0
                ? Appearance.m3colors.m3error
                : root.running ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
            onTriggered: root.submit()
        }
    }
}
