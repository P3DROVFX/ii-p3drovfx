import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.services

Item {
    id: root

    property int entranceTrigger: -1

    property var tabButtonList: [{
        "icon": "checklist",
        "name": Translation.tr("Unfinished")
    }, {
        "name": Translation.tr("Done"),
        "icon": "check_circle"
    }]
    property bool showAddDialog: false
    property int dialogMargins: 20
    property int fabSize: 48
    property int fabMargins: 14

    Keys.onPressed: (event) => {
        // Open add dialog on "N" (any modifiers)
        // Close dialog on Esc if open

        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown)
                tabBar.incrementCurrentIndex();
            else if (event.key === Qt.Key_PageUp)
                tabBar.decrementCurrentIndex();
            event.accepted = true;
        } else if (event.key === Qt.Key_N) {
            root.showAddDialog = true;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Toolbar {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 48
            enableShadow: false
            colBackground: Appearance.colors.colSurfaceContainer
            ToolbarTabBar {
                id: tabBar
                tabButtonList: root.tabButtonList
                currentIndex: swipeView.currentIndex
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < root.tabButtonList.length)
                        swipeView.currentIndex = currentIndex;
                }
            }
        }

        SwipeView {
            id: swipeView

            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: tabBar.currentIndex

            // To Do tab
            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                entranceTrigger: root.entranceTrigger
                taskList: Todo.list.map(function(item, i) {
                    return Object.assign({
                    }, item, {
                        "originalIndex": i
                    });
                }).filter(function(item) {
                    return !item.done;
                }).sort(function(a, b) {
                    if (a.hasDate && !b.hasDate) return -1;
                    if (!a.hasDate && b.hasDate) return 1;
                    if (a.hasDate && b.hasDate) return a.date - b.date;
                    return b.originalIndex - a.originalIndex;
                })
            }

            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                entranceTrigger: root.entranceTrigger
                taskList: Todo.list.map(function(item, i) {
                    return Object.assign({
                    }, item, {
                        "originalIndex": i
                    });
                }).filter(function(item) {
                    return item.done;
                }).sort(function(a, b) {
                    if (a.hasDate && !b.hasDate) return -1;
                    if (!a.hasDate && b.hasDate) return 1;
                    if (a.hasDate && b.hasDate) return b.date - a.date; // Newest finished tasks first
                    return b.originalIndex - a.originalIndex;
                })
            }

        }

    }

    // TickTick sync indicator
    RippleButton {
        id: syncButton
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full

        onClicked: {
            if (Todo.useTickTick) {
                Todo.refresh();
            } else {
                GlobalStates.settingsPendingPageName = "tasksAccounts";
                GlobalStates.openSettings();
            }
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: {
                if (Todo.useTickTick) {
                    return Todo.syncing ? "sync" : "cloud_done";
                } else {
                    return "cloud_off";
                }
            }
            font.pixelSize: 18
            color: {
                if (Todo.useTickTick) {
                    return Todo.syncing ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant;
                } else {
                    return Appearance.colors.colOnSurfaceVariant;
                }
            }
            opacity: Todo.useTickTick ? 1.0 : 0.4

            RotationAnimation on rotation {
                running: Todo.useTickTick && Todo.syncing
                from: 360
                to: 0
                duration: 1000
                loops: Animation.Infinite
            }
        }

        StyledToolTip {
            text: {
                if (Todo.useTickTick) {
                    return Todo.syncing ? Translation.tr("Syncing...") : Translation.tr("TickTick synced");
                } else {
                    return Translation.tr("TickTick sync not configured. Click to setup.");
                }
            }
        }
    }

    // + FAB
    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }

    FloatingActionButton {
        id: fabButton

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins
        onClicked: root.showAddDialog = true
        iconText: "add"
    }

    Item {
        anchors.fill: parent
        z: 9999
        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        onVisibleChanged: {
            if (!visible) {
                todoInput.text = "";
                fabButton.focus = true;
            }
        }

        // Scrim
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim

            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
            }

        }

        // The dialog
        Rectangle {
            id: dialog

            function addTask() {
                if (todoInput.text.length > 0) {
                    Todo.addTask(todoInput.text);
                    todoInput.text = "";
                    root.showAddDialog = false;
                    tabBar.setCurrentIndex(0); // Show unfinished tasks
                }
            }

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: dialogColumnLayout.implicitHeight

            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            ColumnLayout {
                id: dialogColumnLayout

                anchors.fill: parent
                spacing: 16

                StyledText {
                    Layout.topMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Add task")
                }

                TextField {
                    id: todoInput

                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Task description")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    focus: root.showAddDialog
                    onAccepted: dialog.addTask()

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: todoInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }

                    cursorDelegate: Rectangle {
                        width: 1
                        color: todoInput.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }

                }

                RowLayout {
                    Layout.bottomMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignRight
                    spacing: 5

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }

                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: todoInput.text.length > 0
                        onClicked: dialog.addTask()
                    }

                }

            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }

        }

    }

}
