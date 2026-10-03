import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// A command in a monospace pill with a copy button, for setup steps a user may
// prefer to run by hand.
Rectangle {
    id: chip

    required property string command
    property bool copied: false

    Layout.fillWidth: true
    implicitHeight: chipRow.implicitHeight + 12
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer3

    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: chip.copied = false
    }

    RowLayout {
        id: chipRow
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 14
            rightMargin: 6
        }
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: chip.command
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer3
            font {
                family: Appearance.font.family.monospace
                pixelSize: Appearance.font.pixelSize.small
            }
        }
        AppRowButton {
            symbol: chip.copied ? "check" : "content_copy"
            label: chip.copied ? Translation.tr("Copied") : Translation.tr("Copy")
            onClicked: {
                Quickshell.clipboardText = chip.command;
                chip.copied = true;
                copiedTimer.restart();
            }
        }
    }
}
