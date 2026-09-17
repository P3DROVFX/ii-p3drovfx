import qs.modules.common
import qs.modules.common.animations
import qs.modules.common.functions
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
    property int todoListItemSpacing: 2
    property int todoListItemPadding: 8
    property int listBottomPadding: 80
    property int entranceTrigger: -1
    property bool dense: false
    property bool showShortcutHints: false

    function toggleTask(index) {
        const task = taskListRoot.taskList[index];
        if (!task)
            return;
        const delegate = listView.itemAtIndex(index);
        if (delegate) delegate._optimisticDone = !task.done;
        if (task.done)
            Todo.markUnfinished(task);
        else
            Todo.markDone(task);
    }

    function handleKey(event) {
        const ctrl = event.modifiers === Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            if (!event.isAutoRepeat) taskListRoot.toggleTask(event.key - Qt.Key_1);
            return true;
        }
        if (event.modifiers !== Qt.NoModifier)
            return false;
        let target = listView.currentIndex;
        if (event.key === Qt.Key_Down) target++;
        else if (event.key === Qt.Key_Up) target = Math.max(0, target - 1);
        else if (event.key === Qt.Key_Home) target = 0;
        else if (event.key === Qt.Key_End) target = listView.count - 1;
        else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) taskListRoot.toggleTask(listView.currentIndex);
            return true;
        } else {
            return false;
        }
        if (listView.count > 0) {
            listView.currentIndex = Math.max(0, Math.min(listView.count - 1, target));
            listView.positionViewAtIndex(listView.currentIndex, ListView.Contain);
            const item = listView.itemAtIndex(listView.currentIndex);
            if (item && item.y + item.height > listView.contentY + listView.height - taskListRoot.listBottomPadding)
                listView.contentY = Math.min(listView.contentHeight - listView.height,
                    item.y + item.height - listView.height + taskListRoot.listBottomPadding);
            // The root owns Space/Enter after arrow navigation, not a stale
            // checkbox delegate that may disappear when its task is completed.
            taskListRoot.forceActiveFocus();
        }
        return true;
    }
    signal editRequested(var task)
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    StyledListView {
        id: listView
        anchors.fill: parent
        currentIndex: -1
        keyNavigationEnabled: false
        // The add and sync buttons float over the bottom corners of this list.
        // Priority cards slide under the fades instead of reading as cut
        // through, and the list stops reading as elastic on a quick flick.
        boundsBehavior: Flickable.StopAtBounds
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
                entranceStarter.stop();
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
                entranceStarter.requestStart();
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

            DeferredAnimationStarter {
                id: entranceStarter
                controller: entranceController
                enabled: taskListRoot.entranceAnimationsEnabled
            }

            property bool _optimisticDone: modelData.done
            onModelDataChanged: _optimisticDone = modelData.done

            // Priority uses TickTick's scale (0 none, 1 low, 3 medium, 5 high),
            // which the local schema shares. A prioritized task takes the full
            // container pair of its level so the row itself carries the signal;
            // content on top always uses the matching on-color for contrast.
            // Priority 0 keeps the legacy colLayer2 surface untouched.
            readonly property int taskPriority: todoItem.modelData.priority ?? 0
            readonly property color priorityContainer: todoItem.taskPriority >= 5 ? Appearance.colors.colError
                : todoItem.taskPriority >= 3 ? Appearance.colors.colTertiaryContainer
                : todoItem.taskPriority > 0 ? Appearance.colors.colSecondaryContainer
                : Appearance.colors.colLayer2
            readonly property color priorityContainerHover: todoItem.taskPriority >= 5 ? Appearance.colors.colErrorHover
                : todoItem.taskPriority >= 3 ? Appearance.colors.colTertiaryContainerHover
                : todoItem.taskPriority > 0 ? Appearance.colors.colSecondaryContainerHover
                : Appearance.colors.colSurfaceContainerHigh
            readonly property color priorityOnContainer: todoItem.taskPriority >= 5 ? Appearance.colors.colOnError
                : todoItem.taskPriority >= 3 ? Appearance.colors.colOnTertiaryContainer
                : todoItem.taskPriority > 0 ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnSurface

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
                implicitHeight: cardContent.implicitHeight + taskListRoot.todoListItemPadding * 2
                radius: Appearance.rounding.normal
                color: engaged ? todoItem.priorityContainerHover : todoItem.priorityContainer

                readonly property bool engaged: cellHover.hovered || completeButton.activeFocus
                    || (taskListRoot.activeFocus && listView.currentIndex === todoItem.index)
                    || editButton.activeFocus || deleteButton.activeFocus
                readonly property string notes: String(todoItem.modelData.notes ?? "").trim()
                readonly property var tags: Array.isArray(todoItem.modelData.tags) ? todoItem.modelData.tags : []

                HoverHandler { id: cellHover }

                Behavior on color {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }

                ColumnLayout {
                    id: cardContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: taskListRoot.todoListItemPadding
                    anchors.leftMargin: taskListRoot.todoListItemPadding / 2
                    spacing: 4

                    Item {
                        id: taskHeader
                        Layout.fillWidth: true
                        implicitHeight: completeButton.implicitHeight

                        TodoItemActionButton {
                            id: completeButton
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: taskListRoot.dense ? 30 : 32
                            implicitHeight: taskListRoot.dense ? 34 : 40
                            buttonRadius: Appearance.rounding.full
                            colBackground: activeFocus ? colBackgroundHover : "transparent"
                            colBackgroundHover: ColorUtils.applyAlpha(todoItem.priorityOnContainer, 0.12)
                            colBackgroundActive: ColorUtils.applyAlpha(todoItem.priorityOnContainer, 0.2)
                            colRipple: colBackgroundActive
                            Accessible.name: (todoItem._optimisticDone ? Translation.tr("Mark as unfinished")
                                : Translation.tr("Mark as done")) + ": " + todoItem.modelData.content
                            onClicked: taskListRoot.toggleTask(todoItem.index)
                            contentItem: TaskShortcutContent {
                                symbol: todoItem._optimisticDone ? "check_circle" : "radio_button_unchecked"
                                shortcut: todoItem.index < 9 ? String(todoItem.index + 1) : ""
                                showHint: taskListRoot.showShortcutHints
                                circle: true
                                fill: todoItem._optimisticDone ? 1 : 0
                                iconSize: Appearance.font.pixelSize.larger
                                badgeColor: todoItem.priorityOnContainer
                                badgeTextColor: todoItem.priorityContainer
                                color: todoItem.taskPriority > 0 ? todoItem.priorityOnContainer
                                    : todoItem._optimisticDone ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }
                        }

                        StyledText {
                            id: todoContentText
                            x: completeButton.width + 2
                            width: Math.max(0, (dateChip.visible ? dateChip.x - 4 : actionSlot.x) - x)
                            clip: true
                            anchors.verticalCenter: parent.verticalCenter
                            text: todoItem.modelData.content
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            font.strikeout: todoItem._optimisticDone
                            color: todoItem.priorityOnContainer
                            opacity: todoItem._optimisticDone ? 0.6 : 1

                            HoverHandler { id: titleHover }
                            StyledToolTip {
                                extraVisibleCondition: titleHover.hovered && todoContentText.truncated
                                text: todoContentText.text
                            }
                        }
                        Rectangle {
                            id: dateChip
                            visible: todoItem.modelData.hasDate && !!todoItem.modelData.date
                            anchors.right: actionSlot.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, Math.min(dateContent.implicitWidth + 16,
                                actionSlot.x - completeButton.width - 2 - Appearance.font.pixelSize.normal * 2))
                            clip: true
                            height: dateContent.implicitHeight + 8
                            radius: Appearance.rounding.full
                            readonly property bool overdue: {
                                if (!todoItem.modelData.hasDate || !todoItem.modelData.date || todoItem._optimisticDone)
                                    return false;
                                const d = new Date(todoItem.modelData.date);
                                const t = new Date();
                                return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
                                    < new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
                            }
                            color: todoItem.taskPriority > 0 ? ColorUtils.applyAlpha(todoItem.priorityOnContainer, 0.1)
                                : overdue ? Appearance.colors.colErrorContainer : Appearance.m3colors.m3tertiaryContainer

                            RowLayout {
                                id: dateContent
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 4
                                MaterialSymbol {
                                    text: dateChip.overdue ? "event_busy" : "event"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: dateText.color
                                }
                                StyledText {
                                    id: dateText
                                    Layout.fillWidth: true
                                    text: dateChip.visible ? Qt.formatDateTime(todoItem.modelData.date, "dd MMM") : ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: todoItem.taskPriority > 0 ? todoItem.priorityOnContainer
                                        : dateChip.overdue ? Appearance.colors.colOnErrorContainer : Appearance.m3colors.m3onTertiaryContainer
                                }
                            }
                            HoverHandler { id: dateHover }
                            StyledToolTip {
                                extraVisibleCondition: dateHover.hovered
                                text: (dateChip.overdue ? Translation.tr("Overdue") + " · " : "")
                                    + (dateChip.visible ? Qt.formatDateTime(todoItem.modelData.date, "dddd, dd MMMM yyyy") : "")
                            }
                        }


                        // One animated extent drives the date, title elision and
                        // action reveal together, including interrupted hovers.
                        Item {
                            id: actionSlot
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: (actionButtons.implicitWidth + 4) * revealProgress
                            height: actionButtons.implicitHeight
                            clip: true
                            property real revealProgress: todoItemRectangle.engaged ? 1 : 0

                            Behavior on revealProgress {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                        }
                        RowLayout {
                            id: actionButtons
                            parent: actionSlot
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            enabled: taskListRoot.dense || todoItemRectangle.engaged
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            opacity: actionSlot.revealProgress

                            TodoItemActionButton {
                                id: editButton
                                implicitWidth: taskListRoot.dense ? 34 : 36
                                implicitHeight: implicitWidth
                                visible: Todo.canEditTask(todoItem.modelData)
                                enabled: taskListRoot.dense || todoItemRectangle.engaged
                                hoverEnabled: todoItemRectangle.engaged
                                useDynamicRadius: true
                                colBackground: ColorUtils.applyAlpha(todoItem.priorityOnContainer, activeFocus ? 0.2 : 0.08)
                                colBackgroundHover: ColorUtils.applyAlpha(todoItem.priorityOnContainer, 0.16)
                                colBackgroundActive: ColorUtils.applyAlpha(todoItem.priorityOnContainer, 0.24)
                                colRipple: colBackgroundActive
                                tooltipText: Translation.tr("Edit task")
                                onClicked: taskListRoot.editRequested(todoItem.modelData)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "edit"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: todoItem.priorityOnContainer
                                }
                            }

                            TodoItemActionButton {
                                id: deleteButton
                                implicitWidth: taskListRoot.dense ? 34 : 36
                                implicitHeight: implicitWidth
                                hoverEnabled: todoItemRectangle.engaged
                                enabled: taskListRoot.dense || todoItemRectangle.engaged
                                useDynamicRadius: true
                                colBackground: activeFocus ? colBackgroundHover : Appearance.colors.colErrorContainer
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                colBackgroundActive: Appearance.colors.colErrorContainerActive
                                colRipple: colBackgroundActive
                                tooltipText: Translation.tr("Delete task")
                                Accessible.name: tooltipText
                                onClicked: Todo.deleteItem(todoItem.modelData)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnErrorContainer
                                }
                            }
                        }
                    }

                    StyledText {
                        id: descriptionText
                        Layout.fillWidth: true
                        Layout.leftMargin: completeButton.implicitWidth + 2
                        visible: todoItemRectangle.notes.length > 0
                        text: todoItemRectangle.notes
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: todoItem.taskPriority > 0 ? todoItem.priorityOnContainer : Appearance.colors.colOnSurfaceVariant
                        opacity: todoItem._optimisticDone ? 0.6 : 1
                        wrapMode: Text.Wrap
                        maximumLineCount: taskListRoot.dense ? 1 : 2
                        elide: Text.ElideRight

                        HoverHandler { id: descriptionHover }
                        StyledToolTip {
                            extraVisibleCondition: descriptionHover.hovered && descriptionText.truncated
                            text: todoItemRectangle.notes
                        }
                    }

                    Flow {
                        id: metadataFlow
                        Layout.fillWidth: true
                        Layout.leftMargin: completeButton.implicitWidth + 2
                        Layout.topMargin: visible ? 4 : 0
                        visible: todoItem.taskPriority > 0 || tagRepeater.count > 0
                        spacing: 4


                        MaterialSymbol {
                            id: priorityChip
                            visible: todoItem.taskPriority > 0
                            height: dateContent.implicitHeight + 8
                            verticalAlignment: Text.AlignVCenter
                            text: "flag"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.smallie
                            color: todoItem.priorityOnContainer
                            HoverHandler { id: priorityHover }
                            StyledToolTip {
                                extraVisibleCondition: priorityHover.hovered
                                text: todoItem.taskPriority >= 5 ? Translation.tr("High priority")
                                    : todoItem.taskPriority >= 3 ? Translation.tr("Medium priority")
                                    : Translation.tr("Low priority")
                            }
                        }

                        Repeater {
                            id: tagRepeater
                            model: taskListRoot.dense ? [] : todoItemRectangle.tags

                            Rectangle {
                                required property var modelData
                                width: Math.min(metadataFlow.width, tagText.implicitWidth + 16)
                                height: dateContent.implicitHeight + 8
                                radius: Appearance.rounding.full
                                color: todoItem.taskPriority > 0 ? ColorUtils.applyAlpha(todoItem.priorityOnContainer, 0.08)
                                    : Appearance.colors.colSecondaryContainer

                                StyledText {
                                    id: tagText
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: Text.AlignVCenter
                                    text: "#" + modelData
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: todoItem.taskPriority > 0 ? todoItem.priorityOnContainer : Appearance.colors.colOnSecondaryContainer
                                }
                                HoverHandler { id: tagHover }
                                StyledToolTip {
                                    extraVisibleCondition: tagHover.hovered && tagText.truncated
                                    text: tagText.text
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ScrollEdgeFade {
        // The task cards sit directly on the group's colLayer1 surface, so
        // the fade paints exactly that and dissolves the edges the same way
        // the AI chat transcript does. It costs no blur here: a short list of
        // rows does not need it, and the blur band is the expensive part.
        target: listView
        color: Appearance.colors.colLayer1
    }
    StyledText {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.rightMargin: taskListRoot.listBottomPadding
        text: "↑ ↓ · Home · End\nSpace / Enter · Ctrl + 1–9"
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnSurfaceVariant
        opacity: taskListRoot.showShortcutHints ? 1 : 0
        visible: opacity > 0 && taskListRoot.taskList.length > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
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
