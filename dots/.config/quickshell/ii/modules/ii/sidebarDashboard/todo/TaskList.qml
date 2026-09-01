import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarDashboard
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: taskListRoot
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 5
    property int todoListItemPadding: 8
    property int listBottomPadding: 80
    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    StyledListView {
        id: listView
        anchors.fill: parent
        // The add and sync buttons float over the bottom corners of this list.
        // Without the reserve the last task sits underneath them with no way to
        // scroll it clear - the property existed for this and was never applied.
        bottomMargin: taskListRoot.listBottomPadding
        spacing: taskListRoot.todoListItemSpacing
        animateAppearance: false
        model: ScriptModel {
            values: taskListRoot.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            required property int index
            property bool pendingDoneToggle: false
            property bool pendingDelete: false
            property bool enableHeightAnimation: false
            property real _entranceOpacity: 1
            property real _entranceOffset: 0
            property bool _entranceDone: true

            opacity: _entranceDone ? 1 : _entranceOpacity
            transform: Translate { y: todoItem._entranceDone ? 0 : todoItem._entranceOffset }

            function finishEntrance() {
                if (entranceController.item)
                    entranceController.item.stop();
                _entranceDone = true;
                _entranceOpacity = 1;
                _entranceOffset = 0;
            }

            function startEntrance() {
                if (!taskListRoot.entranceAnimationsEnabled || taskListRoot.entranceTrigger < 0) {
                    finishEntrance();
                    return;
                }
                _entranceDone = false;
                _entranceOpacity = 0;
                _entranceOffset = 20;
                Qt.callLater(function() {
                    if (taskListRoot.entranceAnimationsEnabled && entranceController.item)
                        entranceController.item.restart();
                });
            }

            Component.onCompleted: startEntrance()

            Connections {
                target: taskListRoot
                function onEntranceTriggerChanged() { todoItem.startEntrance(); }
                function onEntranceAnimationsEnabledChanged() {
                    if (!taskListRoot.entranceAnimationsEnabled)
                        todoItem.finishEntrance();
                }
            }

            Loader {
                id: entranceController
                active: taskListRoot.entranceAnimationsEnabled
                sourceComponent: Item {
                    function restart() { animation.restart(); }
                    function stop() { animation.stop(); }
                    SequentialAnimation {
                        id: animation
                        PauseAnimation {
                            duration: Math.round(Math.min(Math.max(todoItem.index, 0), 20)
                                * Appearance.animation.elementMove.duration * 0.1)
                        }
                        ParallelAnimation {
                            SidebarGroupAnimation { target: todoItem; property: "_entranceOpacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                            SidebarGroupAnimation { target: todoItem; property: "_entranceOffset"; from: 20; to: 0; animationSpec: Appearance.animation.elementMove }
                        }
                        ScriptAction { script: todoItem._entranceDone = true }
                    }
                }
            }

            property bool _optimisticDone: modelData.done
            onModelDataChanged: _optimisticDone = modelData.done

            implicitHeight: todoItemRectangle.implicitHeight
            width: ListView.view.width
            clip: true

            Behavior on implicitHeight {
                enabled: enableHeightAnimation
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                id: todoItemRectangle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: Math.max(48, todoContentRowLayout.implicitHeight + 16)
                
                HoverHandler {
                    id: cellHover
                }
                
                color: cellHover.hovered ? Appearance.colors.colSurfaceContainerHigh : Appearance.colors.colLayer2
                radius: Appearance.rounding.small
                
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    id: todoContentRowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 12

                    TodoItemActionButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: {
                            todoItem._optimisticDone = !todoItem._optimisticDone;
                            checkIconScaleAnim.restart();
                            
                            if (!todoItem.modelData.done)
                                Todo.markDone(todoItem.modelData.originalIndex);
                            else
                                Todo.markUnfinished(todoItem.modelData.originalIndex);
                        }
                        contentItem: MaterialSymbol {
                            id: checkIcon
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: todoItem._optimisticDone ? "check_circle" : "radio_button_unchecked"
                            iconSize: Appearance.font.pixelSize.larger
                            color: todoItem._optimisticDone ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            NumberAnimation {
                                id: checkIconScaleAnim
                                target: checkIcon
                                property: "scale"
                                from: 0.5
                                to: 1.0
                                duration: 400
                                easing.type: Easing.OutBack
                            }
                        }
                    }

                    StyledText {
                        id: todoContentText
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: todoItem.modelData.content
                        wrapMode: Text.Wrap
                        color: todoItem._optimisticDone ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnSurface
                        font.strikeout: todoItem._optimisticDone
                    }

                    Rectangle {
                        id: dateChip
                        visible: todoItem.modelData.hasDate
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: dateText.implicitWidth + 16
                        implicitHeight: dateText.implicitHeight + 4
                        color: Appearance.m3colors.m3tertiaryContainer
                        radius: Appearance.rounding.full

                        StyledText {
                            id: dateText
                            anchors.centerIn: parent
                            text: todoItem.modelData.hasDate ? Qt.formatDateTime(todoItem.modelData.date, "dd/MM") : ""
                            color: Appearance.m3colors.m3onTertiaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }
                    }

                    TodoItemActionButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        opacity: cellHover.hovered ? 1 : 0
                        
                        Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        
                        onClicked: {
                            Todo.deleteItem(todoItem.modelData.originalIndex);
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: cellHover.hovered ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskListRoot.taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: taskListRoot.emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: taskListRoot.emptyPlaceholderText
            }
        }
    }
}
