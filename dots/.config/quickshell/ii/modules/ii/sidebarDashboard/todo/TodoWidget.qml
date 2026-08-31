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
    // Defensive fallback for alternate hosts smaller than the dashboard's
    // fixed 350px bottom group.
    readonly property bool compact: root.height > 0 && root.height < 300

    property var tabButtonList: [
        {
            "icon": "checklist",
            "name": Translation.tr("Unfinished")
        },
        {
            "name": Translation.tr("Done"),
            "icon": "check_circle"
        }
    ]
    property int selectedTab: Math.max(0, Math.min(root.tabButtonList.length - 1,
        Persistent.states.sidebar.bottomGroup.todoTab))
    property bool showAddDialog: false
    property int dialogMargins: 20
    // 56 is FloatingActionButton's own baseSize; fabSize was never handed to it,
    // so the button was 56 while the list reserved room for 48. Compact scales
    // both buttons by the same 260/350 the bottom group itself lost.
    property int fabSize: root.compact ? 42 : 56
    property int fabMargins: root.compact ? 10 : 14
    property int syncButtonSize: root.compact ? 27 : 36

    function selectTab(index) {
        if (index < 0 || index >= root.tabButtonList.length || root.selectedTab === index)
            return;

        root.selectedTab = index;
        Persistent.states.sidebar.bottomGroup.todoTab = index;
    }

    Keys.onPressed: event => {
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
            Layout.preferredHeight: root.compact ? 44 : 52
            enableShadow: false
            colBackground: Appearance.colors.colSurfaceContainer
            ToolbarTabBar {
                id: tabBar
                tabButtonList: root.tabButtonList
                requestOnly: true
                currentIndex: root.selectedTab
                onIndexSelected: root.selectTab(index)
            }
        }

        SwipeView {
            id: swipeView
            property bool initialized: false

            Layout.topMargin: root.compact ? 4 : 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: root.selectedTab
            Component.onCompleted: initialized = true
            onCurrentIndexChanged: {
                if (initialized && currentIndex !== root.selectedTab)
                    root.selectTab(currentIndex);
            }

            // To Do tab
            Loader {
                active: root.selectedTab === 0
                asynchronous: true
                sourceComponent: TaskList {
                    listBottomPadding: root.fabSize + root.fabMargins * 2
                    emptyPlaceholderIcon: "check_circle"
                    emptyPlaceholderText: Translation.tr("Nothing here!")
                    entranceTrigger: root.entranceTrigger
                    taskList: Todo.list.map(function (item, i) {
                        return Object.assign({}, item, {
                            "originalIndex": i
                        });
                    }).filter(function (item) {
                        return !item.done;
                    }).sort(function (a, b) {
                        if (a.hasDate && !b.hasDate)
                            return -1;
                        if (!a.hasDate && b.hasDate)
                            return 1;
                        if (a.hasDate && b.hasDate)
                            return a.date - b.date;
                        return b.originalIndex - a.originalIndex;
                    })
                }
            }

            Loader {
                active: root.selectedTab === 1
                asynchronous: true
                sourceComponent: TaskList {
                    listBottomPadding: root.fabSize + root.fabMargins * 2
                    emptyPlaceholderIcon: "checklist"
                    emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                    entranceTrigger: root.entranceTrigger
                    taskList: Todo.list.map(function (item, i) {
                        return Object.assign({}, item, {
                            "originalIndex": i
                        });
                    }).filter(function (item) {
                        return item.done;
                    }).sort(function (a, b) {
                        if (a.hasDate && !b.hasDate)
                            return -1;
                        if (!a.hasDate && b.hasDate)
                            return 1;
                        if (a.hasDate && b.hasDate)
                            return b.date - a.date;
                        return b.originalIndex - a.originalIndex;
                    })
                }
            }
        }
    }

    // Provider sync / status indicator
    RippleButton {
        id: syncButton
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins
        implicitWidth: root.syncButtonSize
        implicitHeight: root.syncButtonSize
        buttonRadius: Appearance.rounding.full

        onClicked: {
            if (Todo.remoteEnabled && Todo.connected) {
                Todo.refresh();
            } else {
                GlobalStates.openSettingsPage("tasksAccounts");
            }
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: {
                if (!Todo.remoteEnabled) {
                    return "save";
                }
                if (!Todo.connected) {
                    return "cloud_off";
                }
                return Todo.syncing ? "sync" : "cloud_done";
            }
            font.pixelSize: root.compact ? 13 : 18
            color: {
                if (!Todo.remoteEnabled) {
                    return Appearance.colors.colOnSurfaceVariant;
                }
                if (!Todo.connected) {
                    return Appearance.colors.colOnSurfaceVariant;
                }
                return Todo.syncing ? Appearance.colors.colPrimary : Appearance.colors.colPrimary;
            }
            opacity: (!Todo.remoteEnabled || Todo.connected) ? 1.0 : 0.4

            RotationAnimation on rotation {
                running: Todo.remoteEnabled && Todo.syncing
                from: 360
                to: 0
                duration: 1000
                loops: Animation.Infinite
            }
        }

        StyledToolTip {
            text: {
                if (Todo.provider === "local") {
                    return Translation.tr("Tasks are stored locally.");
                }
                if (!Todo.connected) {
                    return Todo.providerName + " · " + Translation.tr("Not connected. Click to setup.");
                }
                if (Todo.syncing) {
                    return Todo.providerName + " · " + Translation.tr("Syncing...");
                }
                return Todo.providerName + " · " + Translation.tr("Synced");
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
        baseSize: root.fabSize
        iconSize: root.compact ? 20 : 26
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

                    StyledTextContextMenu {
                        id: todoContextMenu
                        targetField: todoInput
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.RightButton
                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                todoInput.forceActiveFocus();
                                todoContextMenu.popup(mouse.x, mouse.y);
                            }
                        }
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
