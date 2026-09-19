import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.services

Item {
    id: root

    property int sizeW: 0
    property int sizeH: 0

    readonly property bool isWide: sizeW >= 4 || (sizeW === 0 && root.width > 320 && root.height < 200)
    readonly property bool isTall: sizeH >= 4 || (sizeH === 0 && root.height > 220 && root.width < 260)
    readonly property bool isCompact: (sizeW === 2 && sizeH === 2) || (sizeW === 0 && root.width < 260 && root.height < 180)

    property int entranceTrigger: -1
    property bool keyboardEnabled: root.visible
    property bool ctrlPressed: false
    readonly property bool showShortcutHints: root.keyboardEnabled && root.ctrlPressed
        && (root.Window.window?.active ?? false)
    readonly property var activeList: root.selectedTab === 0 ? unfinishedLoader.item : doneLoader.item

    onKeyboardEnabledChanged: { if (!root.keyboardEnabled) root.ctrlPressed = false; }
    Connections {
        target: root.Window.window
        function onActiveChanged() { root.ctrlPressed = false; }
    }

    function releaseKey(event) {
        if (event.key === Qt.Key_Control || !(event.modifiers & Qt.ControlModifier))
            root.ctrlPressed = false;
    }

    function syncTasks() {
        if (Todo.connected)
            Todo.refresh();
        else
            GlobalStates.openSettingsPage("tasksAccounts");
    }
    // Defensive fallback for alternate hosts smaller than the dashboard's
    // fixed 350px bottom group.
    readonly property bool compact: (root.isCompact || root.isWide) ? true : (root.height > 0 && root.height < 300)
    readonly property bool dense: root.isCompact || (root.width > 0 && root.width < 260)

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
    property var editingTask: null
    readonly property var taskSheet: canvasViewLoader.item?.sheet ?? null
    readonly property bool viewOpen: root.activeView.length > 0
    readonly property int canvasSlideDistance: Appearance.font.pixelSize.huge * 1.5
    readonly property int canvasContentPadding: root.dense ? 10 : 16
    // Match the save FAB in NewTaskSheet, including compact and dense hosts.
    property int fabSize: root.dense ? 40 : (root.compact ? 42 : 52)
    property int fabMargins: root.dense ? 6 : (root.compact ? 10 : 14)
    property int syncButtonSize: root.dense ? 32 : (root.compact ? 36 : 40)

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

    function openTaskEditor(task = null) {
        root.editingTask = task;
        root.activeView = task ? "editTask" : "newTask";
    }

    function closeView() {
        // Clear while the view still exists: the Loader destroys its item the
        // moment activeView flips, so nothing survives to be cleaned after.
        if (root.taskSheet)
            root.taskSheet.clearInput();
        root.activeView = "";
        root.editingTask = null;
    }

    function handleKey(event) {
        if (!root.keyboardEnabled)
            return false;
        root.ctrlPressed = event.key === Qt.Key_Control || !!(event.modifiers & Qt.ControlModifier);
        if (root.viewOpen)
            return root.taskSheet?.handleKey(event) ?? false;
        const ctrl = event.modifiers === Qt.ControlModifier;
        if (ctrl && event.key === Qt.Key_N) {
            if (!event.isAutoRepeat) root.openTaskEditor();
            return true;
        }
        if (ctrl && event.key === Qt.Key_R && Todo.provider === "ticktick") {
            if (!event.isAutoRepeat && !Todo.syncing) root.syncTasks();
            return true;
        }
        if (event.modifiers === Qt.NoModifier && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
            root.selectTab(event.key === Qt.Key_PageDown ? 1 : 0);
            return true;
        }
        return root.activeList?.handleKey(event) ?? false;
    }

    Keys.onPressed: event => { event.accepted = root.handleKey(event); }
    Keys.onReleased: event => root.releaseKey(event)

    onActiveViewChanged: {
        // The view already cleared its own input in closeView(); here the
        // focus is handed back to the FAB that opened it.
        if (!root.viewOpen)
            fabButton.forceActiveFocus();
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: 0

        // Same choreography as the AiChat transcript: the list leaves to the
        // left while the subpage enters from the right, so the widget reads
        // as one surface swapping its content.
        opacity: root.viewOpen ? 0 : 1
        visible: opacity > 0.001 && !root.isCompact && !root.isWide
        enabled: !root.viewOpen && !root.isCompact && !root.isWide
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

        // The tab pill and the TickTick sync circle share one centered row, so
        // the circle reads as an attachment of the toolbar instead of a
        // floating control over the list.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: Appearance.sizes.toolbarHeight
            spacing: 6

            Toolbar {
                enableShadow: false
                colBackground: Appearance.colors.colSurfaceContainer
                ToolbarTabBar {
                    id: tabBar
                    tabButtonList: root.tabButtonList
                    collapseInactiveLabels: root.dense
                    requestOnly: true
                    currentIndex: root.selectedTab
                    onIndexSelected: index => root.selectTab(index)
                    delegate: ToolbarTabButton {
                        id: taskTab
                        required property int index
                        required property var modelData
                        current: index === root.selectedTab
                        text: modelData.name
                        materialSymbol: modelData.icon
                        collapseInactiveLabel: root.dense
                        onClicked: root.selectTab(index)
                        Accessible.name: modelData.name
                        contentItem: Row {
                            anchors.centerIn: parent
                            spacing: taskTab.labelCollapsed ? 0 : 6
                            TaskShortcutContent {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Appearance.font.pixelSize.smallest * 3
                                height: Appearance.font.pixelSize.larger
                                symbol: taskTab.materialSymbol
                                fill: taskTab.current ? 1 : 0
                                shortcut: taskTab.index === 0 ? "PgUp" : "PgDn"
                                showHint: root.showShortcutHints
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: taskTab.text
                                width: taskTab.labelCollapsed ? 0 : implicitWidth
                                visible: !taskTab.labelCollapsed
                            }
                        }
                    }
                }
            }

            // Provider sync / status action — TickTick only
            RippleButton {
                id: syncButton
                visible: Todo.provider === "ticktick"
                implicitWidth: root.syncButtonSize
                implicitHeight: root.syncButtonSize
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                colRipple: Appearance.colors.colOnSecondaryContainer

                onClicked: root.syncTasks()

                contentItem: TaskShortcutContent {
                    symbol: Todo.syncing ? "sync" : "cloud_done"
                    shortcut: "Ctrl\n+ R"
                    showHint: root.showShortcutHints
                    fill: 1
                    iconSize: root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: Todo.connected ? 1.0 : 0.4
                }

                StyledToolTip {
                    text: {
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

            // Quick add button in header when hosted in a tile
            RippleButton {
                id: headerAddButton
                visible: root.sizeW > 0
                implicitWidth: root.syncButtonSize
                implicitHeight: root.syncButtonSize
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colBackgroundActive: Appearance.colors.colPrimaryActive
                onClicked: root.openTaskEditor()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnPrimary
                }
                StyledToolTip { text: Translation.tr("Add task") }
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

            // Only the selected list owns delegates. TickTick can return a
            // sizeable inbox, and keeping both unfinished and done ListViews
            // alive made the hidden tab pay for its delegates too.
            Loader {
                id: unfinishedLoader
                active: root.selectedTab === 0
                asynchronous: true
                sourceComponent: TaskList {
                    dense: root.dense
                    showShortcutHints: root.showShortcutHints && !root.viewOpen
                    listBottomPadding: root.fabSize + root.fabMargins * 2
                    emptyPlaceholderIcon: "check_circle"
                    emptyPlaceholderText: Translation.tr("Nothing here!")
                    entranceTrigger: root.entranceTrigger
                    taskList: root.unfinishedTasks
                    onEditRequested: task => root.openTaskEditor(task)
                }
            }

            Loader {
                id: doneLoader
                active: root.selectedTab === 1
                asynchronous: true
                sourceComponent: TaskList {
                    dense: root.dense
                    showShortcutHints: root.showShortcutHints && !root.viewOpen
                    listBottomPadding: root.fabSize + root.fabMargins * 2
                    emptyPlaceholderIcon: "checklist"
                    emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                    entranceTrigger: root.entranceTrigger
                    taskList: root.doneTasks
                    onEditRequested: task => root.openTaskEditor(task)
                }
            }
        }
    }

    // ── Compact View (2x2) ────────────────────────────────────────────────
    Item {
        id: compactView
        anchors.fill: parent
        anchors.margins: 4
        visible: root.isCompact && !root.viewOpen

        ColumnLayout {
            anchors.fill: parent
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                MaterialSymbol {
                    text: "check_circle"
                    iconSize: 14
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: Translation.tr("To Do")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                Rectangle {
                    visible: root.unfinishedTasks.length > 0
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer
                    implicitWidth: compactCountText.implicitWidth + 6
                    implicitHeight: compactCountText.implicitHeight + 2
                    StyledText {
                        id: compactCountText
                        anchors.centerIn: parent
                        text: String(root.unfinishedTasks.length)
                        font.pixelSize: Appearance.font.pixelSize.smallest * 0.9
                        color: Appearance.colors.colOnPrimaryContainer
                        font.weight: Font.Bold
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitWidth: 18
                    implicitHeight: 18
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.openTaskEditor()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: 13
                        color: Appearance.colors.colPrimary
                    }
                    StyledToolTip { text: Translation.tr("Add task") }
                }
            }

            ListView {
                id: compactListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.unfinishedTasks

                delegate: Rectangle {
                    id: compactItemRect
                    required property var modelData
                    width: compactListView.width
                    implicitHeight: 22
                    radius: Appearance.rounding.small
                    color: compactItemArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                    Behavior on color {
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    MouseArea {
                        id: compactItemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openTaskEditor(modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 3

                        RippleButton {
                            implicitWidth: 16
                            implicitHeight: 16
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: Todo.markDone(modelData)

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "circle"
                                iconSize: 12
                                color: Appearance.colors.colOutline
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.content || modelData.name || ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: modelData.hasDate && !!modelData.date
                            text: Qt.formatDateTime(modelData.date, "d MMM")
                            font.pixelSize: Appearance.font.pixelSize.smallest * 0.85
                            color: Appearance.colors.colSubtext
                        }

                        MaterialSymbol {
                            visible: (modelData.priority ?? 0) > 0 || (modelData.taskPriority ?? 0) > 0
                            text: "flag"
                            iconSize: 10
                            color: Appearance.colors.colError
                        }
                    }
                }

                Item {
                    visible: root.unfinishedTasks.length === 0
                    anchors.fill: parent

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "done_all"
                            iconSize: 22
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("All caught up!")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // ── Wide View (4x2) ───────────────────────────────────────────────────
    Item {
        id: wideView
        anchors.fill: parent
        visible: root.isWide && !root.viewOpen

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 6

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "checklist"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: Translation.tr("Tasks")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                Rectangle {
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer
                    implicitWidth: Math.max(20, wideCountText.implicitWidth + 10)
                    implicitHeight: 20
                    StyledText {
                        id: wideCountText
                        anchors.centerIn: parent
                        text: String(root.unfinishedTasks.length)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                        font.weight: Font.Bold
                    }
                }

                Item { Layout.fillWidth: true }

                // Segmented tab toggle: Pending / Done
                Rectangle {
                    implicitHeight: 26
                    implicitWidth: tabRow.implicitWidth + 4
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 2

                        RippleButton {
                            implicitHeight: 22
                            implicitWidth: pendingText.implicitWidth + 14
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.selectedTab === 0 ? Appearance.colors.colPrimary : "transparent"
                            colBackgroundHover: root.selectedTab === 0 ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                            colRipple: root.selectedTab === 0 ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
                            onClicked: root.selectTab(0)

                            contentItem: StyledText {
                                id: pendingText
                                anchors.centerIn: parent
                                text: Translation.tr("Pending (%1)").arg(root.unfinishedTasks.length)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: root.selectedTab === 0 ? Font.DemiBold : Font.Normal
                                color: root.selectedTab === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                        }

                        RippleButton {
                            implicitHeight: 22
                            implicitWidth: doneText.implicitWidth + 14
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.selectedTab === 1 ? Appearance.colors.colPrimary : "transparent"
                            colBackgroundHover: root.selectedTab === 1 ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                            colRipple: root.selectedTab === 1 ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
                            onClicked: root.selectTab(1)

                            contentItem: StyledText {
                                id: doneText
                                anchors.centerIn: parent
                                text: Translation.tr("Done (%1)").arg(root.doneTasks.length)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: root.selectedTab === 1 ? Font.DemiBold : Font.Normal
                                color: root.selectedTab === 1 ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                RippleButton {
                    visible: Todo.provider === "ticktick"
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    onClicked: root.syncTasks()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: Todo.syncing ? "sync" : "cloud_done"
                        iconSize: 14
                        color: Appearance.colors.colSecondary
                    }
                    StyledToolTip {
                        extraVisibleCondition: parent.hovered
                        text: Translation.tr("Sync tasks")
                    }
                }

                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: root.openTaskEditor()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledToolTip {
                        extraVisibleCondition: parent.hovered
                        text: Translation.tr("New task")
                    }
                }
            }

            // Full-width Task List
            ListView {
                id: wideListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.selectedTab === 0 ? root.unfinishedTasks : root.doneTasks

                delegate: Rectangle {
                    id: taskDelegate
                    required property var modelData
                    width: wideListView.width
                    implicitHeight: 28
                    radius: Appearance.rounding.small
                    color: delegateMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colSurfaceContainer

                    Behavior on color {
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    MouseArea {
                        id: delegateMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openTaskEditor(modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 8
                        spacing: 8

                        RippleButton {
                            implicitWidth: 22
                            implicitHeight: 22
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: {
                                if (root.selectedTab === 0)
                                    Todo.markDone(modelData);
                                else
                                    Todo.markUnfinished(modelData);
                            }

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.selectedTab === 0 ? "circle" : "check_circle"
                                iconSize: 15
                                color: root.selectedTab === 0 ? Appearance.colors.colOutline : Appearance.colors.colPrimary
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.content || modelData.name || ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.selectedTab === 0 ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                            font.strikeout: root.selectedTab === 1
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: !!modelData.hasDate && !!modelData.date
                            implicitHeight: 18
                            implicitWidth: dateRow.implicitWidth + 8
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer1

                            RowLayout {
                                id: dateRow
                                anchors.centerIn: parent
                                spacing: 3
                                MaterialSymbol {
                                    text: "calendar_today"
                                    iconSize: 10
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: {
                                        if (!modelData.date) return "";
                                        const d = new Date(modelData.date);
                                        return `${d.getDate()}/${d.getMonth() + 1}`;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smallest * 0.85
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        MaterialSymbol {
                            visible: root.selectedTab === 0 && ((modelData.priority ?? 0) > 0 || (modelData.taskPriority ?? 0) > 0)
                            text: "flag"
                            iconSize: 12
                            color: ((modelData.priority ?? 0) >= 3 || (modelData.taskPriority ?? 0) >= 3)
                                ? Appearance.colors.colError
                                : Appearance.colors.colPrimary
                        }
                    }
                }

                Item {
                    visible: (root.selectedTab === 0 ? root.unfinishedTasks.length : root.doneTasks.length) === 0
                    anchors.fill: parent

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 3

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.selectedTab === 0 ? "done_all" : "checklist"
                            iconSize: 24
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.selectedTab === 0 ? Translation.tr("All caught up!") : Translation.tr("No completed tasks")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // One persistent action above both the list and the editor canvas.
    StyledRectangularShadow {
        target: fabButton
        visible: fabButton.visible
        z: fabButton.z
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }

    FloatingActionButton {
        id: fabButton
        visible: (!root.isCompact && !root.isWide && root.sizeW === 0) || root.viewOpen
        z: canvasViewLoader.z + 1

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins
        baseSize: root.fabSize
        iconSize: root.compact ? 20 : 24
        enabled: !root.viewOpen || ((root.taskSheet?.canSave ?? false) && !(root.taskSheet?.datePickerOpen ?? false))
        colBackground: root.viewOpen ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer
        colBackgroundHover: root.viewOpen ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colPrimaryContainerHover
        colBackgroundActive: root.viewOpen ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colPrimaryContainerActive
        colRipple: colBackgroundActive
        colOnBackground: root.viewOpen ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer
        onClicked: {
            if (root.viewOpen)
                root.taskSheet?.save();
            else
                root.openTaskEditor();
        }
        iconText: root.viewOpen ? "check" : "add"
        Accessible.name: root.viewOpen ? Translation.tr("Save task") : Translation.tr("Add task")
        contentItem: TaskShortcutContent {
            symbol: fabButton.iconText
            shortcut: root.viewOpen ? "Ctrl\n+ Enter" : "Ctrl\n+ N"
            showHint: root.showShortcutHints
            iconSize: fabButton.iconSize
            color: fabButton.colOnBackground
        }
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
            readonly property alias sheet: editor

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
                color: "transparent"
            }

            MouseArea {
                // The list is still behind this view during the cross fade;
                // without this it would take the clicks meant for the page.
                anchors.fill: parent
                onWheel: wheel => wheel.accepted = true
            }

            NewTaskSheet {
                id: editor
                anchors.fill: parent
                editTask: root.editingTask
                showShortcutHints: root.showShortcutHints
                onControlPressed: root.ctrlPressed = true
                onControlReleased: root.ctrlPressed = false
                onCloseRequested: root.closeView()
                onSaved: {
                    if (!root.editingTask)
                        root.selectTab(0);
                }
            }
        }
    }
}
