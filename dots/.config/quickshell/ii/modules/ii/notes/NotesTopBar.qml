pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * The bar across the top: where you are, and the way out.
 *
 * It also holds the one action that is about the whole store rather than about any note —
 * the statistics — because the rail's bottom is full at two, and a third full-width button
 * there would read as a third place to go rather than as a thing to look at.
 */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool showBack: false
    property bool showRailToggle: false
    property bool railExpanded: true
    /// Drawn as held down while the statistics page is the one open.
    property bool statsActive: false

    signal backRequested()
    signal railToggled()
    signal statsRequested()
    signal closeRequested()

    implicitHeight: NotesMetrics.topBarHeight

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 0
        spacing: 8

        NotesIconButton {
            symbol: "arrow_back"
            tooltipText: Translation.tr("Back to the list")
            visible: root.showBack
            onTriggered: root.backRequested()
        }

        // Where a navigation toggle belongs. On top of the rail it sat above the button
        // that makes notes, which is the one thing there that should be first.
        NotesIconButton {
            symbol: root.railExpanded ? "menu_open" : "menu"
            tooltipText: root.railExpanded ? Translation.tr("Collapse the sidebar") : Translation.tr("Expand the sidebar")
            visible: root.showRailToggle && !root.showBack
            onTriggered: root.railToggled()
        }

        ColumnLayout {
            // Its natural width, not a share of the bar. Given `fillWidth` it claimed
            // room it had no text for, and the search box ended up marooned in the middle
            // of a gap.
            Layout.maximumWidth: 280
            Layout.leftMargin: root.showBack ? 0 : NotesMetrics.panePadding - 4
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title.length > 0 ? root.title : Translation.tr("Untitled note")
                // Expressive typography leans on contrast between the title and everything
                // around it, so this is deliberately large for a bar.
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.subtitle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        NotesIconButton {
            symbol: "analytics"
            tooltipText: Translation.tr("Statistics")
            toggled: root.statsActive
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colIcon: root.statsActive
                ? Appearance.m3colors.m3onSecondaryContainer
                : Appearance.colors.colOnLayer1
            onTriggered: root.statsRequested()
        }

        NotesIconButton {
            symbol: "close"
            tooltipText: Translation.tr("Close notes")
            onTriggered: root.closeRequested()
        }
    }

}
