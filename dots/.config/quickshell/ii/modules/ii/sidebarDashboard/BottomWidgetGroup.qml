pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarDashboard.calendar
import qs.modules.ii.sidebarDashboard.todo
import qs.modules.ii.sidebarDashboard.pomodoro
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true

    // layer.enabled and layer.effect: OpacityMask removed to optimize performance and prevent lag on dashboard open
    // layer.enabled: true
    // layer.effect: OpacityMask {
    //     maskSource: Rectangle {
    //         width: root.width
    //         height: root.height
    //         radius: root.radius
    //     }
    // }

    implicitHeight: effectivelyCollapsed ? collapsedBottomWidgetGroupRow.implicitHeight : 350
    property int selectedTab: Persistent.states.sidebar.bottomGroup.tab
    property int previousIndex: -1
    property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
    property bool forceCollapsed: false
    readonly property bool effectivelyCollapsed: collapsed || forceCollapsed
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

    property int entranceTrigger: -1

    function triggerContentEntrance() {
        entranceTrigger++;
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    function setCollapsed(state) {
        Persistent.states.sidebar.bottomGroup.collapsed = state;
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
            NumberAnimation {
                properties: "opacity"
                duration: Appearance.animation.elementMove.duration / 2
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
    ]

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen && !root.effectivelyCollapsed) {
                // Call immediately: widgets reset to opacity 0 synchronously,
                // then Qt.callLater inside each widget fires the animation on next frame.
                root.triggerContentEntrance();
            }
        }
    }

    onStateChanged: {
        if (state === "collapsed") {
            chevronUpAnim.start();
        } else if (state === "expanded") {
            chevronDownAnim.start();
            if (GlobalStates.sidebarRightOpen) {
                root.triggerContentEntrance();
            }
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

                NumberAnimation {
                    id: chevronUpAnim
                    target: chevronUpRotation
                    property: "angle"
                    from: 180
                    to: 0
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
        }

        StyledText {
            property int remainingTasks: Todo.list.filter(task => !task.done).length
            Layout.margins: 10
            Layout.leftMargin: 0
            // text: `${DateTime.collapsedCalendarFormat}   •   ${remainingTasks} task${remainingTasks > 1 ? "s" : ""}`
            text: Translation.tr("%1   •   %2 tasks").arg(DateTime.collapsedCalendarFormat).arg(remainingTasks)
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
                        required property int index
                        required property var modelData
                        showToggledHighlight: false
                        toggled: root.selectedTab == index
                        buttonText: modelData.name
                        buttonIcon: modelData.icon
                        onPressed: {
                            root.selectedTab = index;
                            Persistent.states.sidebar.bottomGroup.tab = index;
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

                    NumberAnimation {
                        id: chevronDownAnim
                        target: chevronDownRotation
                        property: "angle"
                        from: -180
                        to: 0
                        duration: 300
                        easing.type: Easing.OutCubic
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

                Component.onCompleted: {
                    tabStack.source = root.tabs[root.selectedTab].widget;
                }

                onLoaded: {
                    root.triggerContentEntrance();
                }

                Connections {
                    target: root
                    function onEntranceTriggerChanged() {
                        if (tabStack.item && tabStack.item.hasOwnProperty("entranceTrigger")) {
                            tabStack.item.entranceTrigger = root.entranceTrigger;
                        }
                    }
                }

                Connections {
                    target: root
                    function onSelectedTabChanged() {
                        if (root.currentTab > root.previousIndex)
                            tabSwitchBehavior.animation.down = true;
                        else if (root.currentTab < root.previousIndex)
                            tabSwitchBehavior.animation.down = false;
                        tabStack.source = root.tabs[root.selectedTab].widget;
                    }
                }

                Behavior on source {
                    id: tabSwitchBehavior
                    animation: TabSwitchAnim {
                        id: upAnim
                        down: true
                    }
                }
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
