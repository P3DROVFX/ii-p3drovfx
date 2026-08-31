pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarDashboard.calendar
import qs.modules.ii.sidebarDashboard.todo
import qs.modules.ii.sidebarDashboard.pomodoro
import QtQuick
import QtQuick.Layouts
import "SidebarPerformancePolicy.js" as PerformancePolicy

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true

    // The expanded group keeps the calendar's natural 38px-cell height. Space
    // pressure is handled by the notification/bottom arbiter, not by shrinking
    // the selected widget when the sidebar banner is enabled.
    readonly property real naturalExpandedHeight: 350
    readonly property real expandedHeight: naturalExpandedHeight
    readonly property real collapsedHeight: collapsedBottomWidgetGroupRow.implicitHeight
    implicitHeight: effectivelyCollapsed ? collapsedHeight : expandedHeight
    property int selectedTab: Persistent.states.sidebar.bottomGroup.tab
    property int previousIndex: -1
    property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
    property bool forceCollapsed: false
    readonly property bool effectivelyCollapsed: collapsed || forceCollapsed
    property int entranceTrigger: -1
    property int contentEntranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    signal collapseRequested(bool shouldCollapse)
    property var tabs: [
        {
            "type": "calendar",
            "name": Translation.tr("Calendar"),
            "icon": "calendar_month",
            "widget": "calendar/CalendarWidget.qml"
        },
        {
            "type": "todo",
            "name": Translation.tr("To Do"),
            "icon": "check_circle",
            "widget": "todo/TodoWidget.qml"
        },
        {
            "type": "timer",
            "name": Translation.tr("Timer"),
            "icon": "schedule",
            "widget": "pomodoro/PomodoroWidget.qml"
        },
    ]

    // The optimized default loads the selected widget after the outer slide.
    // The explicit entrance-animation opt-in loads it with the open request;
    // either way it stays warm for this dashboard instance afterwards.
    property bool contentActivated: false
    property bool outerSidebarAnimating: GlobalStates.rightSidebarAnimating

    function activateContentWhenSafe() {
        contentActivated = PerformancePolicy.nextDeferredContentReady(
            contentActivated,
            GlobalStates.sidebarRightOpen,
            root.outerSidebarAnimating,
            root.entranceAnimationsEnabled
        );
    }

    onOuterSidebarAnimatingChanged: {
        if (!outerSidebarAnimating)
            root.activateContentWhenSafe();
    }

    Component.onCompleted: {
        if (root.entranceAnimationsEnabled)
            root.activateContentWhenSafe();
        else
            Qt.callLater(root.activateContentWhenSafe);
    }

    onEffectivelyCollapsedChanged: {
        if (!effectivelyCollapsed)
            root.activateContentWhenSafe();
    }

    function triggerContentEntrance() {
        if (!root.entranceAnimationsEnabled || root.effectivelyCollapsed)
            return;
        root.contentEntranceTrigger++;
    }

    onEntranceTriggerChanged: {
        root.activateContentWhenSafe();
        root.triggerContentEntrance();
    }

    function setCollapsed(state) {
        Persistent.states.sidebar.bottomGroup.collapsed = state;
        root.collapseRequested(state);
    }

    state: effectivelyCollapsed ? "collapsed" : "expanded"

    states: [
        State {
            name: "collapsed"
            PropertyChanges { target: collapsedBottomWidgetGroupRow; opacity: 1 }
            PropertyChanges { target: bottomWidgetGroupRow; opacity: 0 }
        },
        State {
            name: "expanded"
            PropertyChanges { target: collapsedBottomWidgetGroupRow; opacity: 0 }
            PropertyChanges { target: bottomWidgetGroupRow; opacity: 1 }
        }
    ]

    transitions: [
        Transition {
            from: "*"
            to: "*"
            SidebarGroupAnimation {
                properties: "opacity"
                animationSpec: Appearance.animation.elementMove
            }
        }
    ]

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                if (root.entranceAnimationsEnabled)
                    root.activateContentWhenSafe();
                else
                // Let target-width bindings start the outer animation first.
                    Qt.callLater(root.activateContentWhenSafe);
            }
        }
    }

    onStateChanged: {
        if (state === "collapsed") {
            chevronUpAnim.start();
        } else if (state === "expanded") {
            chevronDownAnim.start();
            if (GlobalStates.sidebarRightOpen && !root.outerSidebarAnimating
                    && root.entranceTrigger >= 0)
                root.triggerContentEntrance();
        }
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.selectedTab = Math.min(root.selectedTab + 1, root.tabs.length - 1);
            } else if (event.key === Qt.Key_PageUp) {
                root.selectedTab = Math.max(root.selectedTab - 1, 0);
            }
            event.accepted = true;
        }
    }

    // The thing when collapsed
    RowLayout {
        id: collapsedBottomWidgetGroupRow
        opacity: 0
        visible: opacity > 0

        spacing: 15

        CalendarHeaderButton {
            Layout.margins: 10
            Layout.rightMargin: 0
            forceCircle: true
            downAction: () => {
                root.setCollapsed(false);
            }
            contentItem: MaterialSymbol {
                id: chevronUpIcon
                text: "keyboard_arrow_up"
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer1

                transform: Rotation {
                    id: chevronUpRotation
                    origin.x: chevronUpIcon.width / 2
                    origin.y: chevronUpIcon.height / 2
                    angle: 0
                }

                SidebarGroupAnimation {
                    id: chevronUpAnim
                    target: chevronUpRotation
                    property: "angle"
                    from: 180
                    to: 0
                    animationSpec: Appearance.animation.elementMove
                }
            }
        }

        StyledText {
            property int remainingTasks: Todo.list.filter(task => !task.done).length
            Layout.margins: 10
            Layout.leftMargin: 0
            // text: `${DateTime.collapsedCalendarFormat}   •   ${remainingTasks} task${remainingTasks > 1 ? "s" : ""}`
            text: Translation.tr("%1   •   %2 tasks").arg(DateTime.collapsedCalendarFormat).arg(String(remainingTasks))
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
    }

    // The thing when expanded
    RowLayout {
        id: bottomWidgetGroupRow

        opacity: 0
        visible: opacity > 0

        anchors.fill: parent
        // implicitHeight: tabStack.implicitHeight
        spacing: 20

        // Navigation rail
        Item {
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.leftMargin: 10
            Layout.topMargin: 10
            implicitWidth: tabBar.implicitWidth
            // Navigation rail buttons
            NavigationRailTabArray {
                id: tabBar
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 5
                currentIndex: root.selectedTab
                expanded: false
                Repeater {
                    model: root.tabs
                    NavigationRailButton {
                        id: navButton
                        required property int index
                        required property var modelData
                        showToggledHighlight: false
                        colBackgroundHover: toggled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                        toggled: root.selectedTab == index
                        buttonText: modelData.name
                        buttonIcon: modelData.icon
                        onPressed: {
                            root.selectedTab = index;
                            Persistent.states.sidebar.bottomGroup.tab = index;
                        }

                        property real _navBtnScale: 1
                        property real _navBtnOpacity: 1
                        property bool _navBtnDone: true
                        scale: _navBtnDone ? 1 : _navBtnScale
                        opacity: _navBtnDone ? 1 : _navBtnOpacity

                        function finishEntrance() {
                            if (navEntranceController.item)
                                navEntranceController.item.stop();
                            _navBtnDone = true;
                            _navBtnScale = 1;
                            _navBtnOpacity = 1;
                        }

                        function startEntrance() {
                            if (!root.entranceAnimationsEnabled || root.contentEntranceTrigger < 0) {
                                finishEntrance();
                                return;
                            }
                            _navBtnDone = false;
                            _navBtnScale = 0.75;
                            _navBtnOpacity = 0;
                            Qt.callLater(function() {
                                if (root.entranceAnimationsEnabled && navEntranceController.item)
                                    navEntranceController.item.restart();
                            });
                        }

                        Component.onCompleted: finishEntrance()

                        Connections {
                            target: root
                            function onContentEntranceTriggerChanged() { navButton.startEntrance(); }
                            function onEntranceAnimationsEnabledChanged() {
                                if (!root.entranceAnimationsEnabled)
                                    navButton.finishEntrance();
                            }
                        }

                        Loader {
                            id: navEntranceController
                            active: root.entranceAnimationsEnabled
                            sourceComponent: Item {
                                function restart() { animation.restart(); }
                                function stop() { animation.stop(); }
                                SequentialAnimation {
                                    id: animation
                                    PauseAnimation {
                                        duration: Math.round(navButton.index
                                            * Appearance.animation.elementMove.duration * 0.15)
                                    }
                                    ParallelAnimation {
                                        SidebarGroupAnimation { target: navButton; property: "_navBtnOpacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                                        SidebarGroupAnimation { target: navButton; property: "_navBtnScale"; from: 0.75; to: 1; animationSpec: Appearance.animation.elementMove }
                                    }
                                    ScriptAction { script: navButton._navBtnDone = true }
                                }
                            }
                        }

                    }
                }
            }
            // Collapse button
            CalendarHeaderButton {
                anchors.left: parent.left
                anchors.top: parent.top
                forceCircle: true
                downAction: () => {
                    root.setCollapsed(true);
                }
                contentItem: MaterialSymbol {
                    id: chevronDownIcon
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1

                    transform: Rotation {
                        id: chevronDownRotation
                        origin.x: chevronDownIcon.width / 2
                        origin.y: chevronDownIcon.height / 2
                        angle: 0
                    }

                    SidebarGroupAnimation {
                        id: chevronDownAnim
                        target: chevronDownRotation
                        property: "angle"
                        from: -180
                        to: 0
                        animationSpec: Appearance.animation.elementMove
                    }
                }
            }
        }

        // Content area
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // implicitHeight: tabStack.implicitHeight
            Layout.topMargin: root.radius / 2
            Layout.bottomMargin: root.radius / 2
            Layout.rightMargin: root.radius / 2

            Loader {
                id: tabStack
                anchors.fill: parent
                active: root.contentActivated
                asynchronous: true

                Component.onCompleted: {
                    tabStack.source = root.tabs[root.selectedTab].widget;
                    root.previousIndex = root.selectedTab;
                }

                onLoaded: {
                    if (tabStack.item && tabStack.item.hasOwnProperty("entranceTrigger"))
                        tabStack.item.entranceTrigger = root.contentEntranceTrigger;
                }

                Connections {
                    target: root
                    function onContentEntranceTriggerChanged() {
                        if (tabStack.item && tabStack.item.hasOwnProperty("entranceTrigger"))
                            tabStack.item.entranceTrigger = root.contentEntranceTrigger;
                    }
                    function onSelectedTabChanged() {
                        if (!root.contentActivated || !tabStack.item) {
                            tabStack.source = root.tabs[root.selectedTab].widget;
                            root.previousIndex = root.selectedTab;
                            return;
                        }
                        if (root.selectedTab > root.previousIndex)
                            tabSwitchAnimation.down = true;
                        else if (root.selectedTab < root.previousIndex)
                            tabSwitchAnimation.down = false;
                        root.triggerContentEntrance();
                        tabSwitchAnimation.restart();
                    }
                }
            }

            TabSwitchAnim {
                id: tabSwitchAnimation
            }
        }
    }

    component TabSwitchAnim: SequentialAnimation {
        id: switchAnim
        property bool down: false
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                to: 10 * (switchAnim.down ? -1 : 1)
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        PropertyAction {
            target: tabStack
            property: "source"
            value: root.tabs[root.selectedTab].widget
        } // The source change happens here
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                from: 10 * -(switchAnim.down ? -1 : 1)
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
        ScriptAction {
            script: {
                root.previousIndex = root.selectedTab;
            }
        }
    }
}
