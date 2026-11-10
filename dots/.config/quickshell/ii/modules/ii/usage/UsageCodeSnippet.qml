import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A shell command in a field-coloured box with a copy button that answers with a check
 * for a moment. Used by the install screen and by the Battery page's rebuild hint, the
 * two places the app hands a command over instead of running it.
 */
Rectangle {
    id: root

    property string snippet: ""
    property bool copied: false

    function copy(text: string): void {
        Quickshell.execDetached(["bash", "-c", `wl-copy '${text.replace(/'/g, "'\\''")}'`]);
    }

    Layout.fillWidth: true
    implicitHeight: snippetRow.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusNormal
    color: ClockStyle.colField

    RowLayout {
        id: snippetRow
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        anchors.leftMargin: ClockStyle.gapLarge
        spacing: ClockStyle.gap

        StyledText {
            Layout.fillWidth: true
            text: root.snippet
            font.family: Appearance.font.family.monospace
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colOnSurface
            // Breaks the udev rule at its spaces where it can, mid-token only when a
            // single argument is wider than the box.
            wrapMode: Text.Wrap
        }

        ClockCardAction {
            Layout.alignment: Qt.AlignTop
            symbol: root.copied ? "check" : "content_copy"
            tip: Translation.tr("Copy")
            colContent: root.copied ? ClockStyle.colPrimary : ClockStyle.colOnSurface
            onClicked: {
                root.copy(root.snippet);
                root.copied = true;
                copyResetTimer.restart();
            }
        }
    }

    Timer {
        id: copyResetTimer
        interval: 1500
        onTriggered: root.copied = false
    }
}
