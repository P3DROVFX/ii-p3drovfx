pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything the note can do that does not deserve a permanent button.
 *
 * The header had eleven icon buttons in a row: outline, history, reminder, lock, focus,
 * page, pin, star, export, delete, and restore. Eleven of anything is not a toolbar, it is
 * a wall — 484 pixels of identical grey circles, in front of which nobody finds the third
 * one, and on a narrow pane they left the title with no room to be a title.
 *
 * So four stay outside, chosen by how often a hand reaches for them, and the rest live
 * here behind one. Written as rows rather than a `Menu`, like the page picker beside it:
 * an item inside the pane cannot be clipped by a window that does not know about it, and
 * it keeps the app's own surface and shape.
 */
Rectangle {
    id: root

    /**
     * `[{ id, symbol, label, hint, tone }]`, where `tone` is "normal" or "error" and a
     * separator is `{ id: "" }`. A separator here is air, not a rule.
     */
    property var items: []

    /// Names the set when it is not obvious from the items — "Remind me", say. Takes no
    /// room while empty.
    property string title: ""

    signal picked(string id)

    implicitWidth: 260
    implicitHeight: layout.implicitHeight + 12
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainerHighest

    StyledRectangularShadow {
        target: root
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.topMargin: 6
            Layout.bottomMargin: 2
            text: root.title
            visible: root.title.length > 0
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: root.items

            delegate: Item {
                id: entry
                required property var modelData

                readonly property bool isSeparator: String(entry.modelData.id ?? "").length === 0

                Layout.fillWidth: true
                implicitHeight: entry.isSeparator ? 8 : 44

                RippleButton {
                    id: button
                    anchors.fill: parent
                    visible: !entry.isSeparator
                    buttonRadius: NotesMetrics.pillRadius(entry.implicitHeight)
                    colBackground: "transparent"
                    colBackgroundHover: entry.modelData.tone === "error"
                        ? Appearance.colors.colErrorContainer
                        : Appearance.colors.colLayer2Hover
                    colBackgroundActive: entry.modelData.tone === "error"
                        ? Appearance.colors.colErrorContainer
                        : Appearance.colors.colLayer2Active

                    onClicked: root.picked(String(entry.modelData.id))

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: entry.modelData.symbol ?? ""
                            iconSize: 20
                            color: entry.modelData.tone === "error"
                                ? Appearance.m3colors.m3error
                                : Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: entry.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: entry.modelData.tone === "error"
                                ? Appearance.m3colors.m3error
                                : Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        /// A word about the state, where a checkmark would be too coy: the
                        /// date a reminder is set for, or that a note is locked.
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: entry.modelData.hint ?? ""
                            visible: String(entry.modelData.hint ?? "").length > 0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
