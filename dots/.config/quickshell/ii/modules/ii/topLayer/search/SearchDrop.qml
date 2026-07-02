pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.modules.ii.bar

// ── Animation strategy ──────────────────────────────────────────────────────
// Caestelia-inspired: uses expressiveFastSpatial (spring overshoot y1=1.67)
// for open, emphasizedAccel for close. The spring curve makes the drop feel
// physical and alive. The Notch shape renders at full target size from the
// start; the clip + corner radius scaling handles the visual reveal cleanly.

Item {
    id: root
    focus: true
    width: screenWidth
    height: screenHeight

    BarThemes {
        id: barThemes
    }
    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.overviewOpen = false;
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.searchWidgetRef) {
                root.searchWidgetRef.focusFirstItem();
                event.accepted = true;
            }
            return;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            if (root.searchWidgetRef) {
                root.searchWidgetRef.focusSearchInput();
                event.accepted = true;
            }
            return;
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
    property real barMargin: 0
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

    readonly property bool isOverviewVisible: root.isOpen
        && (root.searchWidgetRef ? root.searchWidgetRef.searchingText === "" : true)
        && !GlobalStates.searchOnlyMode
        && !Config.options.search.alwaysListApps
        && (Config?.options.overview.enable ?? true)

    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    readonly property real launcherContentWidth: searchWidgetRef ? searchWidgetRef.implicitWidth : 0
    readonly property real launcherContentHeight: searchWidgetRef ? searchWidgetRef.implicitHeight : 0

    property real lastActiveW: 360
    property real lastActiveH: 120

    onLauncherContentWidthChanged: {
        if (launcherContentWidth > 0)
            lastActiveW = launcherContentWidth;
    }

    onLauncherContentHeightChanged: {
        if (launcherContentHeight > 0)
            lastActiveH = launcherContentHeight;
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
        barMargin: root.barMargin
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

    // ── Shared animation spec ────────────────────────────────────────────────
    // Open:  emphasizedDecel [0.05,0.7,0.1,1] — fast-start, slow-settle (EaseOut).
    // Close: same curve but shorter — panel snaps shut quickly then eases out.
    readonly property int _animDurationOpen: Math.round(450 * Appearance.animMultiplier)
    readonly property int _animDurationClose: Math.round(280 * Appearance.animMultiplier)
    readonly property var _openBezier: Appearance.animationCurves.emphasizedDecel
    readonly property var _closeBezier: Appearance.animationCurves.emphasizedDecel

    // openProgress: 0 = fully closed, 1 = fully open
    property real openProgress: 0.0

    // animHeight: the visible reveal height — drives both the clip and the Notch radii
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
            from: "closed"
            to: "open"
            NumberAnimation {
                target: root
                property: "openProgress"
                duration: root._animDurationOpen
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root._openBezier
            }
        },
        Transition {
            from: "open"
            to: "closed"
            NumberAnimation {
                target: root
                property: "openProgress"
                duration: root._animDurationClose
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root._closeBezier
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

        // Publish drop bounds to GlobalStates for background blur exclusion
        onXChanged: root._updateBlurExclusion()
        onYChanged: root._updateBlurExclusion()
        onWidthChanged: root._updateBlurExclusion()
        onHeightChanged: root._updateBlurExclusion()

        // ── Notch background (unclipped) ─────────────────────────────────────
        Notch {
            id: dropNotch
            width: dropContainer.width
            height: dropContainer.height   // = animHeight, always matches clip edge
            y: barBottom ? (dropContainer.height - height) : 0
            disableBehaviors: true
            readonly property real _wr: Appearance.rounding.windowRounding
            // Grow topRadius from 0 immediately — no dead zone threshold.
            // animHeight * 0.8 reaches windowRounding quickly without overshoot.
            topRadius: Math.min(_wr, root.animHeight * 0.8)
            bottomRadius: Math.min(_wr, root.animHeight)
            fillColor: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            transform: Scale {
                xScale: 1
                yScale: barBottom ? -1 : 1
                origin.y: dropNotch.height / 2
            }
        }

        // ── Concave corners at bar attachment edge ────────────────────────────
        // RoundCorners flush at the TOP of dropContainer, outside its left/right edges,
        // painting colLayer0 (bar background) to create a smooth concave curve where
        // the bar bottom meets the drop panel. Grow from radius 0 with animHeight.
        //
        // Corner enum semantics for "drop below bar" layout:
        //   Left side:  BottomRight fills bottom-right quadrant → arc faces inward → concave ✓
        //   Right side: BottomLeft  fills bottom-left  quadrant → arc faces inward → concave ✓
        readonly property real _cornerRadius: Math.min(
            Appearance.rounding.windowRounding,
            root.animHeight
        )
        readonly property bool _showCorners: !root.barVertical && root.animHeight > 0.5

        RoundCorner {
            id: topLeftCorner
            visible: false
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.BottomRight
            anchors.right: parent.left
            anchors.top: parent.top
        }

        RoundCorner {
            id: topRightCorner
            visible: false
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.BottomLeft
            anchors.left: parent.right
            anchors.top: parent.top
        }

        // barBottom variant: corners at the BOTTOM edge (drop grows upward)
        RoundCorner {
            id: bottomLeftCorner
            visible: dropContainer._showCorners && root.barBottom
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.TopRight
            extendHorizontal: true
            extendVertical: true
            anchors.right: parent.left
            anchors.bottom: parent.bottom
        }

        RoundCorner {
            id: bottomRightCorner
            visible: dropContainer._showCorners && root.barBottom
            implicitSize: dropContainer._cornerRadius
            color: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.TopLeft
            extendHorizontal: true
            extendVertical: true
            anchors.left: parent.right
            anchors.bottom: parent.bottom
        }

        // ── Content (clipped to growing height) ──────────────────────────────
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

                Loader {
                    id: searchWidgetLoader
                    active: root.isWidgetActive
                    focus: root.isOpen
                    anchors.fill: parent
                    sourceComponent: Component {
                        SearchWidget {
                            id: searchWidget
                            Component.onCompleted: {
                                root.searchWidgetRef = searchWidget;
                                if (GlobalStates.activeSearchQuery) {
                                    searchWidget.setSearchingText(GlobalStates.activeSearchQuery);
                                    GlobalStates.activeSearchQuery = "";
                                } else {
                                    searchWidget.cancelSearch();
                                }
                                Qt.callLater(() => searchWidget.focusSearchInput());
                            }
                            Component.onDestruction: {
                                if (root.searchWidgetRef === searchWidget)
                                    root.searchWidgetRef = null;
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onPressed: event => {
                event.accepted = false;
            }
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen && root.screen.name === GlobalStates.activeSearchMonitor) {
                GlobalFocusGrab.addDismissable(root);
                if (root.searchWidgetRef) {
                    Qt.callLater(() => root.searchWidgetRef.focusSearchInput());
                }
            } else {
                GlobalFocusGrab.removeDismissable(root);
                if (root.searchWidgetRef) {
                    root.searchWidgetRef.cancelSearch();
                }
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            if (root.isOpen) {
                GlobalStates.overviewOpen = false;
            }
        }
    }

    Connections {
        target: GlobalStates
        ignoreUnknownSignals: true
        function onActiveSearchQueryChanged() {
            if (GlobalStates.activeSearchQuery && root.searchWidgetRef) {
                root.searchWidgetRef.setSearchingText(GlobalStates.activeSearchQuery);
                GlobalStates.activeSearchQuery = "";
            }
        }
    }

    Loader { // Classic overview
        id: overviewLoader
        anchors.top: dropContainer.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        active: root.isWidgetActive && !root.isScrollingLayout
        visible: opacity > 0.01

        opacity: root.isOverviewVisible ? 1.0 : 0.0
        transform: Translate {
            y: root.isOverviewVisible ? 0 : 30
            Behavior on y {
                NumberAnimation {
                    duration: root.isOverviewVisible ? root._animDurationOpen : root._animDurationClose
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.isOverviewVisible ? root._openBezier : root._closeBezier
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.isOverviewVisible ? root._animDurationOpen : Math.round(60 * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.isOverviewVisible ? root._openBezier : root._closeBezier
            }
        }

        sourceComponent: OverviewWidget {
            panelWindow: root.panelWindow
            monitorIndex: root.monitorIndex
        }
    }

    Loader { // Scrolling overview
        id: scrollingOverviewLoader
        anchors.top: dropContainer.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: root.isWidgetActive && root.isScrollingLayout
        visible: opacity > 0.01

        opacity: root.isOverviewVisible ? 1.0 : 0.0
        transform: Translate {
            y: root.isOverviewVisible ? 0 : 30
            Behavior on y {
                NumberAnimation {
                    duration: root.isOverviewVisible ? root._animDurationOpen : root._animDurationClose
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.isOverviewVisible ? root._openBezier : root._closeBezier
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.isOverviewVisible ? root._animDurationOpen : Math.round(120 * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.isOverviewVisible ? root._openBezier : root._closeBezier
            }
        }

        sourceComponent: ScrollingOverviewWidget {
            anchors.fill: parent
            panelWindow: root.panelWindow
            monitorIndex: root.monitorIndex
        }
    }

    readonly property var maskItem: dropContainer

    function _updateBlurExclusion() {
        var active = root.isOpen && dropContainer.width > 0 && dropContainer.height > 0;
        var sx = dropContainer.x;
        var sy = dropContainer.y;
        var sw = dropContainer.width;
        var sh = dropContainer.height;

        const topR = dropNotch.topRadius;
        const bottomR = dropNotch.bottomRadius;
        if (GlobalStates.searchDropActive !== active
            || GlobalStates.searchDropExclusionX !== sx
            || GlobalStates.searchDropExclusionY !== sy
            || GlobalStates.searchDropExclusionWidth !== sw
            || GlobalStates.searchDropExclusionHeight !== sh
            || GlobalStates.searchDropTopRadius !== topR
            || GlobalStates.searchDropBottomRadius !== bottomR) {
            GlobalStates.searchDropActive = active;
            GlobalStates.searchDropExclusionX = sx;
            GlobalStates.searchDropExclusionY = sy;
            GlobalStates.searchDropExclusionWidth = sw;
            GlobalStates.searchDropExclusionHeight = sh;
            GlobalStates.searchDropTopRadius = topR;
            GlobalStates.searchDropBottomRadius = bottomR;
        }
    }

    onIsOpenChanged: Qt.callLater(_updateBlurExclusion)
    onIsOverviewVisibleChanged: Qt.callLater(_updateBlurExclusion)
    Component.onCompleted: Qt.callLater(_updateBlurExclusion)
}
