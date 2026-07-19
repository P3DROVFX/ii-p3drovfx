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
            id: sidebarContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: sidebarContainer.width
                    height: sidebarContainer.height
                    radius: sidebarContainer.radius
                }
            }

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

                            readonly property string groupId: modelData.id ?? ""
                            readonly property bool containsCurrentPage: (modelData.pages ?? []).some(p => p.pageIndex === sidebarRoot.currentPage)
                            readonly property bool expanded: groupId === "" || Persistent.states.settings.collapsedGroups.indexOf(groupId) === -1

                            function setCollapsed(collapsed) {
                                if (groupId === "")
                                    return;
                                const list = Array.from(Persistent.states.settings.collapsedGroups);
                                const i = list.indexOf(groupId);
                                if (collapsed && i === -1)
                                    list.push(groupId);
                                else if (!collapsed && i !== -1)
                                    list.splice(i, 1);
                                else
                                    return;
                                Persistent.states.settings.collapsedGroups = list;
                            }

                            // Jumping to a page (search, deep link) reveals its group
                            onContainsCurrentPageChanged: {
                                if (containsCurrentPage)
                                    setCollapsed(false);
                            }
                            Component.onCompleted: {
                                if (containsCurrentPage)
                                    setCollapsed(false);
                            }

                            // Group title — click to collapse/expand
                            Item {
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                Layout.rightMargin: 6
                                Layout.bottomMargin: 2
                                implicitHeight: groupHeaderRow.implicitHeight

                                RowLayout {
                                    id: groupHeaderRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 4

                                    StyledText {
                                        text: groupDelegate.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        opacity: groupHeaderMouse.containsMouse ? 0.85 : 0.55
                                        Layout.fillWidth: true

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: 150
                                            }
                                        }
                                    }

                                    MaterialSymbol {
                                        text: "keyboard_arrow_down"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1
                                        opacity: groupHeaderMouse.containsMouse ? 0.85 : 0.55
                                        rotation: groupDelegate.expanded ? 0 : -90

                                        Behavior on rotation {
                                            NumberAnimation {
                                                duration: 150
                                                easing.type: Easing.OutQuad
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: groupHeaderMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: groupDelegate.setCollapsed(groupDelegate.expanded)
                                }
                            }

                            // Pages in this group, clipped away when collapsed
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: groupDelegate.expanded ? pagesColumn.implicitHeight : 0
                                clip: true

                                Behavior on Layout.preferredHeight {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                                    }
                                }

                                ColumnLayout {
                                    id: pagesColumn
                                    anchors.top: parent.top
                                    width: parent.width
                                    spacing: 4

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
    }
}
