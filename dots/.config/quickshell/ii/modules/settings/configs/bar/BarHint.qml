import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A notice that takes one line: a small glyph, a short sentence and, when the fix lives on
 * another page, a link that goes there. It replaces the NoticeBox where a page has many
 * conditional notices: the reason a control is locked is also drawn on the control itself
 * (a lock on the option), so the sentence only has to name the cause.
 */
Rectangle {
    id: root

    readonly property real padV: 7
    readonly property real padStart: 8
    readonly property real padEnd: 14
    readonly property real glyphBox: 22
    readonly property real gap: 10

    property string icon: "info"
    property string text: ""
    /// "lock" tints the glyph tertiary (a blocked option); "info" stays neutral.
    property string tone: root.icon === "lock" ? "lock" : "info"
    property string linkText: ""
    property string targetPageId: ""
    property string targetSectionTitle: ""

    signal linkClicked()

    Layout.fillWidth: true
    implicitHeight: Math.max(root.glyphBox, row.implicitHeight) + root.padV * 2
    radius: Math.min(height / 2, Appearance.rounding.large)
    color: Appearance.colors.colLayer1

    function navigate() {
        root.linkClicked();
        if (root.targetPageId.length === 0)
            return;
        const win = root.QsWindow.window;
        if (!win || win.pageIndexById === undefined)
            return;
        const idx = win.pageIndexById(root.targetPageId);
        if (idx < 0)
            return;
        win.pendingSectionHighlight = root.targetSectionTitle;
        win.currentPage = idx;
    }

    RowLayout {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.padStart
            rightMargin: root.padEnd
        }
        spacing: root.gap

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: root.glyphBox
            implicitHeight: root.glyphBox
            radius: root.glyphBox / 2
            color: root.tone === "lock" ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSecondaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 14
                fill: 1
                color: root.tone === "lock" ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        RippleButton {
            id: link
            Layout.alignment: Qt.AlignVCenter
            visible: root.linkText.length > 0
            implicitHeight: 26
            implicitWidth: linkRow.implicitWidth + 20
            buttonRadius: height / 2
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: root.navigate()

            contentItem: Item {
                RowLayout {
                    id: linkRow
                    anchors.centerIn: parent
                    spacing: 4
                    StyledText {
                        text: root.linkText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                    MaterialSymbol {
                        text: "arrow_forward"
                        iconSize: 14
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
