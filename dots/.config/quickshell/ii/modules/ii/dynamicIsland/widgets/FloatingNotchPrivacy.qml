pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A sensor was just taken: which one, and by whom.
 *
 * Only ever on screen for the announcement (see PrivacySource); the rest of the time the
 * activity is a dot beside the clock, drawn by the resting face.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    // The island's controller, found the way the other legacy faces find their host.
    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.privacy : null;
    }
    readonly property string kind: root.source ? root.source.announcedKind : ""
    readonly property string apps: root.source ? root.source.announcedApps : ""

    /** Every sensor held and by whom, for the bubble's card; see below. */
    readonly property var rows: Privacy.activeItems
    readonly property real rowHeight: 34
    readonly property real preferredExpandedHeight: 52 + Math.max(1, root.rows.length) * root.rowHeight

    // ── Contracted: the announcement ─────────────────────────────────────────
    RowLayout {
        visible: !root.isExpanded
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 16
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(22, Math.min(30, root.height - 10))
            implicitHeight: implicitWidth
            radius: width / 2
            // The bar's indicator colour, not the per-sensor palette phones use: one
            // surface for one state, and the badge reads the same in the bar and here.
            color: Appearance.colors.colTertiary

            MaterialSymbol {
                anchors.centerIn: parent
                text: Privacy.iconFor(root.kind)
                fill: 1
                iconSize: Math.round(parent.width * 0.58)
                color: Appearance.colors.colOnTertiary
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.apps !== ""
                ? Translation.tr("%1 · %2").arg(root.apps).arg(Privacy.labelFor(root.kind))
                : Translation.tr("%1 in use").arg(Privacy.labelFor(root.kind))
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Expanded, in the bubble's card: who holds what ─────────────────────
    ColumnLayout {
        visible: root.isExpanded
        anchors.fill: parent
        anchors.margins: 14
        spacing: 4

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            text: Privacy.summaryTitle()
            elide: Text.ElideRight
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }

        Repeater {
            model: root.rows

            RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: 13
                    color: Appearance.colors.colTertiary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: Privacy.iconFor(String(row.modelData.kind))
                        fill: 1
                        iconSize: 15
                        color: Appearance.colors.colOnTertiary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: String(row.modelData.app ?? "") !== "" ? row.modelData.app : Translation.tr("Unknown app")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Privacy.labelFor(String(row.modelData.kind))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
