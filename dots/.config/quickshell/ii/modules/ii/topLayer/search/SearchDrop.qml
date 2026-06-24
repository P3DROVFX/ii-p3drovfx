pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview

Item {
    id: root
    focus: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.overviewOpen = false
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.searchWidgetRef) {
                root.searchWidgetRef.focusFirstItem()
                event.accepted = true
            }
            return
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            if (root.searchWidgetRef) {
                root.searchWidgetRef.focusSearchInput()
                event.accepted = true
            }
            return
        }
    }
    property var screen: null
    property int monitorIndex: 0
    property var panelWindow: null
    property bool barVertical: false
    property bool barBottom: false
    property bool barOnLeft: false
    property bool barOnRight: false
    property bool usingWrappedFrame: false
    property int frameThickness: 0
    property int barHeight: Appearance.sizes.barHeight
    property int verticalBarWidth: Appearance.sizes.verticalBarWidth
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0
    property real animatedLeftSidebarWidth: 0
    property real animatedRightSidebarWidth: 0
    property bool leftSidebarActiveOnMonitor: false
    property bool rightSidebarActiveOnMonitor: false

    readonly property bool isOpen: GlobalStates.overviewOpen && screen.name === GlobalStates.activeSearchMonitor
    readonly property bool isWidgetActive: isOpen || openProgress > 0.001
    readonly property string mode: isWidgetActive ? "launcher" : "idle"

    readonly property real screenWidth: screen ? screen.width : 1920
    readonly property real screenHeight: screen ? screen.height : 1080

    property var searchWidgetRef: null
    readonly property var nowPlayingBubble: searchWidgetRef ? searchWidgetRef.nowPlayingBubble : null
    readonly property real launcherContentWidth: searchWidgetRef ? searchWidgetRef.implicitWidth : 0
    readonly property real launcherContentHeight: searchWidgetRef ? searchWidgetRef.implicitHeight : 0

    property real lastActiveW: 360
    property real lastActiveH: 120

    onLauncherContentWidthChanged: {
        if (launcherContentWidth > 0)
            lastActiveW = launcherContentWidth
    }

    onLauncherContentHeightChanged: {
        if (launcherContentHeight > 0)
            lastActiveH = launcherContentHeight
    }

    SearchDropState {
        id: dropState
        mode: root.mode
        launcherContentWidth: root.lastActiveW
        launcherContentHeight: root.lastActiveH
        screenWidth: root.screenWidth
        screenHeight: root.screenHeight
    }

    SearchDropPositioner {
        id: positioner
        barVertical: root.barVertical
        barBottom: root.barBottom
        barOnLeft: root.barOnLeft
        barOnRight: root.barOnRight
        usingWrappedFrame: root.usingWrappedFrame
        frameThickness: root.frameThickness
        barHeight: root.barHeight
        verticalBarWidth: root.verticalBarWidth
        hBarHiddenAmount: root.hBarHiddenAmount
        vBarHiddenAmount: root.vBarHiddenAmount
        screenWidth: root.screenWidth
        screenHeight: root.screenHeight
        dropWidth: dropState.targetW
        dropHeight: dropState.targetH
        animatedLeftSidebarWidth: root.animatedLeftSidebarWidth
        animatedRightSidebarWidth: root.animatedRightSidebarWidth
        leftSidebarActiveOnMonitor: root.leftSidebarActiveOnMonitor
        rightSidebarActiveOnMonitor: root.rightSidebarActiveOnMonitor
    }

    HyprlandFocusGrab {
        id: keyboardGrab
        windows: root.panelWindow ? [root.panelWindow] : []
        active: root.isOpen
        onCleared: () => {
            if (!active)
                GlobalStates.overviewOpen = false;
        }
    }

    property real openProgress: 0.0
    readonly property real animHeight: openProgress * dropState.targetH

    state: isOpen ? "open" : "closed"

    states: [
        State {
            name: "closed"
            PropertyChanges {
                target: root
                openProgress: 0.0
            }
        },
        State {
            name: "open"
            PropertyChanges {
                target: root
                openProgress: 1.0
            }
        }
    ]

    transitions: [
        Transition {
            from: "closed"; to: "open"
            NumberAnimation {
                target: root
                property: "openProgress"
                duration: 350
                easing.type: Easing.InOutCubic
            }
        },
        Transition {
            from: "open"; to: "closed"
            NumberAnimation {
                target: root
                property: "openProgress"
                duration: 350
                easing.type: Easing.InOutCubic
            }
        }
    ]

    Item {
        id: dropContainer
        x: positioner.anchorX
        y: positioner.anchorY
        width: dropState.targetW
        height: root.animHeight
        visible: root.animHeight > 0.001

        Item {
            id: clippingClip
            x: -200
            width: parent.width + 400
            height: parent.height
            clip: true

            Item {
                id: contentWrapper
                x: 200
                width: dropContainer.width
                height: dropState.targetH
                y: barBottom ? parent.height - height : 0

                Notch {
                    anchors.fill: parent
                    topRadius: Appearance.rounding.windowRounding
                    bottomRadius: Appearance.rounding.windowRounding
                    fillColor: Appearance.colors.colBackgroundSurfaceContainer
                }

                Loader {
                    id: searchWidgetLoader
                    active: root.isWidgetActive
                    focus: root.isOpen
                    anchors.fill: parent
                    sourceComponent: Component {
                        SearchWidget {
                            id: searchWidget
                            Component.onCompleted: {
                                root.searchWidgetRef = searchWidget
                                if (GlobalStates.activeSearchQuery) {
                                    searchWidget.setSearchingText(GlobalStates.activeSearchQuery)
                                    GlobalStates.activeSearchQuery = ""
                                } else {
                                    searchWidget.cancelSearch()
                                }
                                Qt.callLater(() => searchWidget.focusSearchInput())
                            }
                            Component.onDestruction: {
                                if (root.searchWidgetRef === searchWidget)
                                    root.searchWidgetRef = null
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onPressed: (event) => { event.accepted = false }
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen && root.screen.name === GlobalStates.activeSearchMonitor) {
                GlobalFocusGrab.addDismissable(root)
                if (root.searchWidgetRef) {
                    Qt.callLater(() => root.searchWidgetRef.focusSearchInput())
                }
            } else {
                GlobalFocusGrab.removeDismissable(root)
                if (root.searchWidgetRef) {
                    root.searchWidgetRef.cancelSearch()
                }
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            if (root.isOpen) {
                GlobalStates.overviewOpen = false
            }
        }
    }

    Connections {
        target: GlobalStates
        ignoreUnknownSignals: true
        function onActiveSearchQueryChanged() {
            if (GlobalStates.activeSearchQuery && root.searchWidgetRef) {
                root.searchWidgetRef.setSearchingText(GlobalStates.activeSearchQuery)
                GlobalStates.activeSearchQuery = ""
            }
        }
    }

    readonly property var maskItem: dropContainer
}
