pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One fenced code block of an assistant answer: monospace on a tint of the card, with
 * Copy, and Run in terminal for shell blocks.
 *
 * Run takes two clicks: the first asks under the code for five seconds, and only its
 * "Run it" runs anything — in a terminal, where the command and its output stay in view.
 * The assistant writes with names redacted; <user> and <host> are put back first, and
 * a block that still holds an address is copy-only.
 */
Rectangle {
    id: root

    property string code: ""
    property string lang: ""
    /// The fence is still open: the answer is streaming into it.
    property bool streaming: false
    property color colOnCard: ClockStyle.colOnPrimaryContainer

    readonly property bool shell: ["", "bash", "sh", "shell", "console", "zsh", "fish"].includes(root.lang.toLowerCase())
    /// What would run: prompts ("$ ") taken off, names put back; "" when it cannot run.
    readonly property string command: {
        if (!root.shell || root.streaming)
            return "";
        const lines = root.code.split("\n").map(l => l.replace(/^\s*[$#]\s+/, ""));
        return HealthService.unredactCommand(lines.join("\n").trim());
    }
    property bool confirming: false

    implicitHeight: column.implicitHeight + ClockStyle.gapSmall * 2
    radius: ClockStyle.radiusSmall
    color: Qt.rgba(root.colOnCard.r, root.colOnCard.g, root.colOnCard.b, 0.08)

    Timer {
        id: confirmTimer
        interval: 5000
        onTriggered: root.confirming = false
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: ClockStyle.gap + 2
            rightMargin: ClockStyle.gapSmall
            topMargin: ClockStyle.gapSmall
        }
        spacing: ClockStyle.gapSmall

        // The code, with its buttons beside it on the first line.
        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                text: root.code
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                font.family: Appearance.font.family.monospace
                font.pixelSize: ClockStyle.textSmall + 1
                color: root.colOnCard
            }

            RowLayout {
                Layout.alignment: Qt.AlignTop
                visible: !root.streaming
                spacing: 2

                ClockIconButton {
                    symbol: "content_copy"
                    size: 32
                    iconSize: ClockStyle.iconSmall
                    colIcon: root.colOnCard
                    tooltip: Translation.tr("Copy")
                    onClicked: Quickshell.clipboardText = root.code
                }

                ClockIconButton {
                    visible: root.command.length > 0 && !root.confirming
                    symbol: "terminal"
                    size: 32
                    iconSize: ClockStyle.iconSmall
                    colIcon: root.colOnCard
                    tooltip: Translation.tr("Run in terminal")
                    onClicked: {
                        root.confirming = true;
                        confirmTimer.restart();
                    }
                }
            }
        }

        // The second click, said in words: nothing runs without it.
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: ClockStyle.gapTiny
            visible: root.confirming && root.command.length > 0
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Run this in a terminal?")
                font.pixelSize: ClockStyle.textSmall
                color: root.colOnCard
            }
            ClockButton {
                variant: "text"
                label: Translation.tr("Cancel")
                onClicked: root.confirming = false
            }
            ClockButton {
                variant: "filled"
                symbol: "terminal"
                label: Translation.tr("Run it")
                onClicked: {
                    root.confirming = false;
                    HealthService.runInTerminal(["bash", "-c", root.command]);
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: ClockStyle.gapTiny
            visible: root.shell && !root.streaming && root.command.length === 0
            text: Translation.tr("Fill in the redacted parts before running it.")
            wrapMode: Text.Wrap
            font.pixelSize: ClockStyle.textSmall
            color: root.colOnCard
            opacity: 0.7
        }
    }
}
