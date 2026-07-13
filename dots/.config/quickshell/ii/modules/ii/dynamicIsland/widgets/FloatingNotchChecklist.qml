import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool isExpanded: false

    // Prepare unfinished tasks mapped with their original indexes for completion triggers
    readonly property var unfinishedTasks: {
        if (!Todo.list) return [];
        return Todo.list.map((item, i) => {
            return {
                content: item.content,
                done: item.done,
                originalIndex: i
            };
        }).filter(item => !item.done);
    }

    readonly property int remainingCount: unfinishedTasks.length

    // Contracted view: task count summary
    RowLayout {
        id: contractedLayout
        anchors.centerIn: parent
        spacing: 8
        opacity: !root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        MaterialShape {
            id: iconShape
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignVCenter
            shapeString: "Cookie12Sided"
            color: root.remainingCount > 0 ? Appearance.colors.colPrimaryContainer : Appearance.m3colors.m3successContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.remainingCount > 0 ? "playlist_add_check" : "done_all"
                iconSize: 14
                color: root.remainingCount > 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3success
            }
        }

        StyledText {
            text: String(root.remainingCount)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            color: Appearance.colors.colOnSurface
        }
    }

    // Expanded view: Scrollable list of pending tasks
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 8
        anchors.bottomMargin: 4
        spacing: 4
        opacity: root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Header Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "checklist"
                iconSize: 16
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: "Checklist"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.bold: true
                color: Appearance.colors.colOnSurface
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: root.remainingCount + " remaining"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colLayer0Border
            opacity: 0.5
        }

        // Task List
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

             ListView {
                id: taskListView
                anchors.fill: parent
                model: root.unfinishedTasks
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    width: taskListView.width
                    height: 30
                    color: Appearance.colors.colSurfaceContainerLow
                    radius: 6
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        // Clickable completion checkbox
                        Item {
                            width: 20
                            height: 20
                            Layout.alignment: Qt.AlignVCenter

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "radio_button_unchecked"
                                iconSize: 16
                                color: Appearance.colors.colOnSurfaceVariant

                                HoverHandler {
                                    id: checkHover
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Todo.markDone(modelData.originalIndex);
                                    }
                                }
                            }
                        }

                        // Task Description Text
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.content
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                // Empty state display
                Label {
                    anchors.centerIn: parent
                    text: "No tasks to complete!"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    visible: root.remainingCount === 0
                }
            }
        }
    }
}
