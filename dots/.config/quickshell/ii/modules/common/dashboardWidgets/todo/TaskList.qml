import qs.modules.common
import qs.modules.common.animations
import qs.modules.common.widgets
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
    property bool dense: false
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
                implicitHeight: Math.max(taskListRoot.dense ? 44 : 48,
                    todoContentRowLayout.implicitHeight + (taskListRoot.dense ? 8 : 16))
                
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
                    anchors.leftMargin: taskListRoot.dense ? 4 : 8
                    anchors.rightMargin: taskListRoot.dense ? 4 : 8
                    spacing: taskListRoot.dense ? 5 : 12

                    TodoItemActionButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: taskListRoot.dense ? 34 : 32
                        implicitHeight: implicitWidth
                        onClicked: {
                            todoItem._optimisticDone = !todoItem._optimisticDone;
                            checkIconScaleAnim.restart();
                            
                            if (!todoItem.modelData.done)
                                Todo.markDone(todoItem.modelData);
                            else
                                Todo.markUnfinished(todoItem.modelData);
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
                        wrapMode: taskListRoot.dense ? Text.NoWrap : Text.Wrap
                        elide: taskListRoot.dense ? Text.ElideRight : Text.ElideNone
                        maximumLineCount: taskListRoot.dense ? 1 : 3
                        color: todoItem._optimisticDone ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnSurface
                        font.strikeout: todoItem._optimisticDone

                        StyledToolTip {
                            extraVisibleCondition: cellHover.hovered && String(todoItem.modelData.notes ?? "").length > 0
                            text: todoItem.modelData.notes ?? ""
                        }
                    }

                    // Priority uses TickTick's scale, which the local schema
                    // shares, so one flag reads the same on both providers.
                    MaterialSymbol {
                        visible: todoItem.modelData.priority > 0
                        Layout.alignment: Qt.AlignVCenter
                        text: "flag"
                        iconSize: Appearance.font.pixelSize.smallie
                        color: todoItem.modelData.priority >= 5 ? Appearance.colors.colError
                            : todoItem.modelData.priority >= 3 ? Appearance.colors.colTertiary
                            : Appearance.colors.colPrimary

                        StyledToolTip {
                            extraVisibleCondition: cellHover.hovered
                            text: todoItem.modelData.priority >= 5 ? Translation.tr("High priority")
                                : todoItem.modelData.priority >= 3 ? Translation.tr("Medium priority")
                                : Translation.tr("Low priority")
                        }
                    }

                    Flow {
                        id: tagChipsFlow
                        visible: !taskListRoot.dense && tagChipsFlow.taskTags.length > 0
                        Layout.alignment: Qt.AlignVCenter
                        Layout.maximumWidth: taskListRoot.width * 0.45
                        spacing: 4

                        readonly property var allTags: Array.isArray(todoItem.modelData.tags) ? todoItem.modelData.tags : []
                        readonly property var taskTags: tagChipsFlow.allTags.slice(0, 2)
                        readonly property int extraCount: tagChipsFlow.allTags.length - tagChipsFlow.taskTags.length

                        Repeater {
                            model: tagChipsFlow.taskTags

                            Rectangle {
                                required property var modelData
                                implicitWidth: tagChipText.implicitWidth + 12
                                implicitHeight: tagChipText.implicitHeight + 4
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSecondaryContainer

                                StyledText {
                                    id: tagChipText
                                    anchors.centerIn: parent
                                    text: "#" + modelData
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }

                        Rectangle {
                            visible: tagChipsFlow.extraCount > 0
                            implicitWidth: extraTagText.implicitWidth + 12
                            implicitHeight: extraTagText.implicitHeight + 4
                            radius: Appearance.rounding.full
                            color: Appearance.m3colors.m3surfaceContainerHighest

                            StyledText {
                                id: extraTagText
                                anchors.centerIn: parent
                                text: "+" + tagChipsFlow.extraCount
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    Rectangle {
                        id: dateChip
                        visible: todoItem.modelData.hasDate && !!todoItem.modelData.date
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: dateText.implicitWidth + 16
                        implicitHeight: dateText.implicitHeight + 4
                        radius: Appearance.rounding.full
                        // A due day in the past on an open task is overdue,
                        // regardless of provider; the error container pair is
                        // reserved for exactly this kind of real failure.
                        readonly property bool overdue: {
                            if (!todoItem.modelData.hasDate || !todoItem.modelData.date || todoItem._optimisticDone)
                                return false;
                            const d = new Date(todoItem.modelData.date);
                            const t = new Date();
                            return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
                                < new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
                        }
                        color: overdue ? Appearance.colors.colErrorContainer : Appearance.m3colors.m3tertiaryContainer

                        Behavior on color { ColorAnimation { duration: 150 } }

                        StyledText {
                            id: dateText
                            anchors.centerIn: parent
                            text: (todoItem.modelData.hasDate && todoItem.modelData.date) ? Qt.formatDateTime(todoItem.modelData.date, "dd/MM") : ""
                            color: parent.overdue ? Appearance.colors.colOnErrorContainer : Appearance.m3colors.m3onTertiaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }

                        StyledToolTip {
                            extraVisibleCondition: cellHover.hovered && dateChip.overdue
                            text: Translation.tr("Overdue")
                        }
                    }

                    TodoItemActionButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: taskListRoot.dense ? 34 : 32
                        implicitHeight: implicitWidth
                        // A touchscreen has no hover phase: keep destructive
                        // task management reachable in the compact tablet host.
                        opacity: taskListRoot.dense || cellHover.hovered ? 1 : 0
                        
                        Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        
                        onClicked: {
                            Todo.deleteItem(todoItem.modelData);
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
