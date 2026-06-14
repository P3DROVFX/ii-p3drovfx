pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings v2 – Sidebar
 *
 * Structure
 * ─────────
 *  • Fixed outer Rectangle (colLayer0 bg)
 *  • User header button (full-radius, avatar circle + greeting)
 *  • Scrollable group area
 *      For each group:
 *        – Group title label
 *        – Repeater of SidebarNavButton (smart-radius system)
 *
 * The sidebar is fully data-driven via `root.groups` (array of group objects).
 * No page items are hard-coded here.
 *
 * Expected shape of root.groups:
 *   [
 *     {
 *       name: "Look & Feel",
 *       pages: [
 *         { name: "Colors & Themes", icon: "palette", pageIndex: 0 },
 *         ...
 *       ]
 *     },
 *     ...
 *   ]
 *
 * root.currentPage (int) and root.onCurrentPageChanged are expected to live
 * in the parent scope (settings.qml root).
 */
Item {
    id: sidebarRoot

    // ── Public API ─────────────────────────────────────────────────────────
    // Array of group objects – provided by the parent (settings.qml)
    property var groups: []
    property int currentPage: 0
    signal pageSelected(int pageIndex)

    // ── Geometry ───────────────────────────────────────────────────────────
    property real sidebarPadding: 10

    // ── Layout ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ── Pages container rectangle ───────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding

            StyledFlickable {
                id: pagesScrollView
                anchors.fill: parent
                clip: true
                contentHeight: groupsColumn.implicitHeight + topMargin + bottomMargin
                contentWidth: width
                flickableDirection: Flickable.VerticalFlick

                topMargin: 10
                bottomMargin: 10
                leftMargin: 10
                rightMargin: 10

                ColumnLayout {
                    id: groupsColumn
                    width: pagesScrollView.width - pagesScrollView.leftMargin - pagesScrollView.rightMargin
                    spacing: 12   // gap between groups

                    Repeater {
                        id: groupRepeater
                        model: sidebarRoot.groups

                        // ── Single group ────────────────────────────────────
                        delegate: ColumnLayout {
                            id: groupDelegate
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: 4   // gap between pages within a group

                            // Group title
                            StyledText {
                                text: groupDelegate.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.55
                                Layout.leftMargin: 10
                                Layout.bottomMargin: 2
                            }

                            // Pages in this group
                            Repeater {
                                id: pageRepeater
                                model: groupDelegate.modelData.pages

                                property int pressedIndex: -1

                                SidebarNavButton {
                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true

                                    // Provide position context for smart radius
                                    isFirst:      index === 0
                                    isLast:       index === pageRepeater.count - 1
                                    isActive:     sidebarRoot.currentPage === modelData.pageIndex
                                    prevIsActive: index > 0 && sidebarRoot.currentPage === pageRepeater.itemAt(index - 1)?.modelData?.pageIndex
                                    nextIsActive: index < pageRepeater.count - 1 && sidebarRoot.currentPage === pageRepeater.itemAt(index + 1)?.modelData?.pageIndex
                                    prevIsPressed: pageRepeater.pressedIndex === index - 1
                                    nextIsPressed: pageRepeater.pressedIndex === index + 1

                                    onIsPressedChanged: {
                                        if (isPressed) {
                                            pageRepeater.pressedIndex = index;
                                        } else if (pageRepeater.pressedIndex === index) {
                                            pageRepeater.pressedIndex = -1;
                                        }
                                    }

                                    iconName:  modelData.icon
                                    pageLabel: modelData.name

                                    onClicked: sidebarRoot.pageSelected(modelData.pageIndex)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
