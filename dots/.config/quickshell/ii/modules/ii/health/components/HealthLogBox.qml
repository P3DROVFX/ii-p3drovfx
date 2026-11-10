pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Raw log lines, as the system wrote them: monospace, selectable, on the window's own
 * colour so it reads as a hole in the sheet rather than another card. Lines matching
 * `emphasis` are drawn in the error colour.
 */
Rectangle {
    id: root

    property var lines: []
    property bool loading: false
    property string emptyText: Translation.tr("Nothing logged.")
    /// Lines containing any of these are emphasised.
    property var emphasis: ["error", "fail", "Failed", "denied", "No such file"]

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusNormal
    color: ClockStyle.colBackground

    function escapeHtml(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    readonly property string richText: Array.from(root.lines ?? []).map(line => {
        const text = root.escapeHtml(line);
        const hit = root.emphasis.some(word => String(line).indexOf(word) !== -1);
        return hit ? `<span style="color:${ClockStyle.colError}">${text}</span>` : text;
    }).join("<br>")

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: ClockStyle.gap
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.loading || (root.lines ?? []).length === 0
            text: root.loading ? Translation.tr("Reading the log…") : root.emptyText
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }

        TextEdit {
            Layout.fillWidth: true
            visible: !root.loading && (root.lines ?? []).length > 0
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            textFormat: TextEdit.RichText
            text: root.richText
            font.family: Appearance.font.family.monospace
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colOnSurfaceVariant
            selectionColor: ClockStyle.colPrimaryContainer
            selectedTextColor: ClockStyle.colOnPrimaryContainer
        }
    }
}
