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
    readonly property bool dense: root.width > 0 && root.width < 260

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
    /**
     * Canvas views in the AiChat fashion: the FAB does not open a dialog over
     * the list, it swaps the whole surface for a subpage that slides in from
     * the right while the list leaves to the left.
     */
    property string activeView: ""
    readonly property bool viewOpen: root.activeView.length > 0
    readonly property int canvasSlideDistance: Appearance.font.pixelSize.huge * 1.5
    readonly property int canvasContentPadding: root.dense ? 10 : 16
    // 56 is FloatingActionButton's own baseSize; fabSize was never handed to it,
    // so the button was 56 while the list reserved room for 48. Compact scales
    // both buttons by the same 260/350 the bottom group itself lost.
    property int fabSize: root.dense ? 40 : (root.compact ? 42 : 56)
    property int fabMargins: root.dense ? 6 : (root.compact ? 10 : 14)
    property int syncButtonSize: root.dense ? 36 : (root.compact ? 27 : 36)

    readonly property var unfinishedTasks: {
        const source = Todo.list ?? [];
        const result = [];
        for (let i = 0; i < source.length; i++) {
            const item = source[i];
            if (!item || item.done)
                continue;
            result.push(Object.assign({}, item, {
                "originalIndex": i
            }));
        }
        return result.sort(function (a, b) {
            if (a.hasDate && !b.hasDate)
                return -1;
            if (!a.hasDate && b.hasDate)
                return 1;
            if (a.hasDate && b.hasDate && a.date && b.date)
                return a.date - b.date;
            return b.originalIndex - a.originalIndex;
        });
    }

    readonly property var doneTasks: {
        const source = Todo.doneTasks ?? [];
        const result = [];
        for (let i = 0; i < source.length; i++) {
            const item = source[i];
            if (!item)
                continue;
            result.push(Object.assign({}, item, {
                "originalIndex": i
            }));
        }
        return result.sort(function (a, b) {
            const timeA = a.completedAt ? Number(a.completedAt) : 0;
            const timeB = b.completedAt ? Number(b.completedAt) : 0;
            if (timeA && timeB && timeA !== timeB)
                return timeB - timeA;
            if (a.hasDate && !b.hasDate)
                return -1;
            if (!a.hasDate && b.hasDate)
                return 1;
            if (a.hasDate && b.hasDate && a.date && b.date)
                return b.date - a.date;
            return a.originalIndex - b.originalIndex;
        });
    }

    function selectTab(index) {
        if (index === undefined || index === null || isNaN(index))
            return;
        const target = Math.max(0, Math.min(root.tabButtonList.length - 1, Number(index)));
        if (root.selectedTab === target)
            return;

        root.selectedTab = target;
        Persistent.states.sidebar.bottomGroup.todoTab = target;
    }

    function closeView() {
        // Clear while the view still exists: the Loader destroys its item the
        // moment activeView flips, so nothing survives to be cleaned after.
        if (canvasViewLoader.item?.clearInput)
            canvasViewLoader.item.clearInput();
        root.activeView = "";
    }

    Keys.onPressed: event => {
        // Open the new-task subpage on "N" (any modifiers)
        // Close the subpage on Esc if open

        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown)
                tabBar.incrementCurrentIndex();
            else if (event.key === Qt.Key_PageUp)
                tabBar.decrementCurrentIndex();
            event.accepted = true;
        } else if (event.key === Qt.Key_N) {
            root.activeView = "newTask";
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.viewOpen) {
            root.closeView();
            event.accepted = true;
        }
    }

    onActiveViewChanged: {
        // The view already cleared its own input in closeView(); here the
        // focus is handed back to the FAB that opened it.
        if (!root.viewOpen)
            fabButton.focus = true;
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: 0

        // Same choreography as the AiChat transcript: the list leaves to the
        // left while the subpage enters from the right, so the widget reads
        // as one surface swapping its content.
        opacity: root.viewOpen ? 0 : 1
        visible: opacity > 0.001
        transform: Translate {
            x: root.viewOpen ? -root.canvasSlideDistance : 0

            Behavior on x {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        Toolbar {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.compact ? 44 : 52
            enableShadow: false
            colBackground: Appearance.colors.colSurfaceContainer
            ToolbarTabBar {
                id: tabBar
                tabButtonList: root.tabButtonList
                collapseInactiveLabels: root.dense
                requestOnly: true
                currentIndex: root.selectedTab
                onIndexSelected: index => root.selectTab(index)
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
            TaskList {
                dense: root.dense
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                entranceTrigger: root.entranceTrigger
                taskList: root.unfinishedTasks
            }

            // Done tab
            TaskList {
                dense: root.dense
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                entranceTrigger: root.entranceTrigger
                taskList: root.doneTasks
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
        opacity: root.viewOpen ? 0 : 1
        visible: opacity > 0.001

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

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
            font.pixelSize: root.dense
                ? Appearance.font.pixelSize.normal
                : (root.compact ? Appearance.font.pixelSize.smallie : Appearance.font.pixelSize.larger)
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
        opacity: root.viewOpen ? 0 : 1
        visible: opacity > 0.001

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        onClicked: root.activeView = "newTask"
        iconText: "add"
    }

    /**
     * The subpage shell. Built once per opening and then only swaps what it
     * holds, like ChatControlBar's canvas view: no scrim, nothing anchored —
     * the view slides in from the right over the faded list.
     */
    Loader {
        id: canvasViewLoader
        anchors.fill: parent
        z: 100
        active: root.viewOpen

        sourceComponent: Item {
            id: canvasView

            opacity: 0
            transform: Translate {
                id: canvasViewTransform
                x: root.canvasSlideDistance
            }

            Component.onCompleted: canvasViewEnter.start()

            ParallelAnimation {
                id: canvasViewEnter

                NumberAnimation {
                    target: canvasView
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }

                NumberAnimation {
                    target: canvasViewTransform
                    property: "x"
                    from: root.canvasSlideDistance
                    to: 0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainer
            }

            MouseArea {
                // The list is still behind this view during the cross fade;
                // without this it would take the clicks meant for the page.
                anchors.fill: parent
                onWheel: wheel => wheel.accepted = true
            }

            NewTaskSheet {
                anchors.fill: parent
                onCloseRequested: root.closeView()
                onSaved: root.selectTab(0)
            }
        }
    }
}
