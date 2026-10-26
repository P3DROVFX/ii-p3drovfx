pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.modules.ii.bar.shared

// ── Animation strategy ──────────────────────────────────────────────────────
// The drop is a liquid SDF surface pulled out of the bar (SearchDropSurface):
// its own linear clock drives the morph, and a spring carries every later size
// change (typing, panels), so a retarget keeps its velocity instead of kinking.
// `openProgress` keeps its old curve: the overview's entrance still rides it.

Item {
    id: root
    focus: true
    width: screenWidth
    height: screenHeight
    IpcHandler {
        target: "searchSuggestionsProbe" + root.screen.name
        function inspect(): string {
            return JSON.stringify({ open: root.isOpen, suggestions: root.searchWidgetRef?.showSuggestionsPanel, wanted: root.overviewWanted, shown: root.isOverviewVisible, classicActive: overviewLoader.active, classicLoaded: overviewLoader.item !== null, scrollingActive: scrollingOverviewLoader.active, scrollingLoaded: scrollingOverviewLoader.item !== null });
        }
        function setSuggestions(enabled: bool): void {
            Config.options.search.suggestions.enable = enabled;
        }
    }

    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    readonly property color themeBgColor: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0

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
    readonly property bool isBottomBar: !barVertical && barBottom
    property bool usingWrappedFrame: false
    property int frameThickness: 0
    property int barHeight: Appearance.sizes.barHeight
    property int verticalBarWidth: Appearance.sizes.verticalBarWidth
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0
    property real barMargin: 0
    property real animatedLeftSidebarWidth: 0
    property real animatedRightSidebarWidth: 0
    property bool leftSidebarActiveOnMonitor: false
    property bool rightSidebarActiveOnMonitor: false

    readonly property bool isOpen: GlobalStates.overviewOpen && GlobalStates.searchConnectActive && screen.name === GlobalStates.activeSearchMonitor
    readonly property bool isWidgetActive: isOpen || openProgress > 0.001 || dropSurface.active || overviewBubble.active
    readonly property string mode: isWidgetActive ? "launcher" : "idle"

    onIsWidgetActiveChanged: {
        if (isWidgetActive) {
            searchWidgetLoader.loadedOnce = true;
            if (!root.isScrollingLayout)
                overviewLoader.loadedOnce = true;
            else
                scrollingOverviewLoader.loadedOnce = true;
        }
    }

    readonly property real screenWidth: screen ? screen.width : 1920
    readonly property real screenHeight: screen ? screen.height : 1080

    property var searchWidgetRef: null

    // What the grid would want right now, from the live query. A hosted panel
    // (Commands, Tools, Email, AI…) owns the drop's surface the same way it
    // owns the classic overview's: while one is open the grid stays out, even
    // though opening it clears the query.
    readonly property bool overviewWanted: (root.searchWidgetRef ? (root.searchWidgetRef.searchingText === "" && !root.searchWidgetRef.isAnySpecialMode) : true) && !GlobalStates.searchOnlyMode && !Config.options.search.alwaysListApps && !Config.options.search.suggestions.enable && (Config?.options.overview.enable ?? true)
    /**
     * The grid's visibility, decided only while the drop is open.
     *
     * Closing the overview clears the query while `openProgress` is still
     * running down. Read live, that turned the grid back on for the close:
     * launching an app from the results made the grid rise out of the closing
     * drop. The default overview never did, because its reveal ignores every
     * change once the overview is closed. This latch does the same.
     */
    property bool overviewShown: root.overviewWanted
    readonly property bool isOverviewVisible: root.isWidgetActive && (root.overviewShown || overviewBubble.active)

    function syncOverviewShown() {
        // Frozen outside the open state; see `overviewShown`.
        if (!root.isOpen)
            return;
        const wanted = root.overviewWanted;
        if (wanted === root.overviewShown)
            return;
        // The overview drop carries the change: tucked back into the search
        // while a query owns it, pulled out again when the query is cleared.
        root.overviewShown = wanted;
    }

    onOverviewWantedChanged: root.syncOverviewShown()
    onIsOpenChanged: {
        Qt.callLater(root._updateBlurExclusion);
        if (!root.isOpen)
            return;
        // Shortcuts queue the prefix before opening; a retained widget does
        // not run Component.onCompleted again to consume it.
        if (GlobalStates.activeSearchQuery && root.searchWidgetRef) {
            root.searchWidgetRef.setSearchingText(GlobalStates.activeSearchQuery);
            GlobalStates.activeSearchQuery = "";
        }
        // A new session starts from the query it opens with.
        root.overviewShown = root.overviewWanted;
    }

    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    readonly property real launcherContentWidth: searchWidgetRef ? searchWidgetRef.implicitWidth : 0
    readonly property real launcherContentHeight: searchWidgetRef ? searchWidgetRef.implicitHeight : 0

    property real lastActiveW: 360
    property real lastActiveH: 120

    // Frozen once the drop starts closing: closing clears the query, and following
    // that would shrink the shape under its own close.
    readonly property bool _followsContent: root.isOpen || root.heldByGesture
    function _syncLastActive() {
        if (!root._followsContent)
            return;
        if (launcherContentWidth > 0)
            lastActiveW = launcherContentWidth;
        if (launcherContentHeight > 0)
            lastActiveH = launcherContentHeight;
    }
    onLauncherContentWidthChanged: root._syncLastActive()
    onLauncherContentHeightChanged: root._syncLastActive()
    on_FollowsContentChanged: root._syncLastActive()

    /**
     * The size the surface is drawn at: the content's target, carried by a spring.
     *
     * The widget no longer eases its own size (`hostDrivesSize`), so this is the one
     * animator. A spring keeps its velocity when the target moves again mid-flight, which
     * is what typing does - every eased restart was a visible kink. No visible overshoot;
     * at multiplier 0.75, 90% of the way in ~150 ms and settled in ~0.35 s. While the drop is still opening the morph owns the motion, and
     * a late first measurement is taken as is.
     */
    property real dropW: dropState.targetW
    property real dropH: dropState.targetH
    readonly property bool _springSizes: root.animStyle !== "none" && root.isOpen && dropSurface.clock > 0.3
    // Time scale of the spring: stiffness goes with its square and damping with it, so
    // the overshoot stays the same and the animation multiplier applies here as well.
    readonly property real _springSpeed: 1.5 / Math.max(0.1, Appearance.animMultiplier)
    Behavior on dropW {
        enabled: root._springSizes
        SpringAnimation { spring: 1.5 * root._springSpeed * root._springSpeed; damping: 0.25 * root._springSpeed; epsilon: 0.25 }
    }
    Behavior on dropH {
        enabled: root._springSizes
        SpringAnimation { spring: 1.5 * root._springSpeed * root._springSpeed; damping: 0.25 * root._springSpeed; epsilon: 0.25 }
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
    }

    readonly property string animStyle: Config.options.overview.animationStyle ?? "bounce"

    // ── Shared animation spec ────────────────────────────────────────────────
    // Open:  emphasizedDecel [0.05,0.7,0.1,1] — fast-start, slow-settle (EaseOut).
    // Close: same curve but shorter — panel snaps shut quickly then eases out.
    readonly property int _animDurationOpen: root.animStyle === "none" ? 0 : Math.round(450 * Appearance.animMultiplier)
    readonly property int _animDurationClose: root.animStyle === "none" ? 0 : Math.round(280 * Appearance.animMultiplier)
    readonly property var _openBezier: Appearance.animationCurves.emphasizedDecel
    readonly property var _closeBezier: Appearance.animationCurves.emphasizedDecel

    // openProgress: 0 = fully closed, 1 = fully open
    property real openProgress: 0.0

    // A touchpad gesture is holding the drop where the fingers are. No transition leads in
    // or out of this state: the gesture settles the value itself before it lets go.
    readonly property bool heldByGesture: GlobalStates.overviewDragging && GlobalStates.searchConnectActive
        && screen.name === GlobalStates.activeSearchMonitor

    state: heldByGesture ? "held" : (isOpen ? "open" : "closed")

    states: [
        State {
            name: "held"
            PropertyChanges {
                target: root
                openProgress: GlobalStates.gestureDragProgress
            }
        },
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
            enabled: root.animStyle !== "none"
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
            enabled: root.animStyle !== "none"
            NumberAnimation {
                target: root
                property: "openProgress"
                duration: root._animDurationClose
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root._closeBezier
            }
        }
    ]

    /** The bar's edge on this screen; the drop grows away from it. */
    readonly property real barEdgeY: root.isBottomBar ? positioner.anchorY + dropState.targetH : positioner.anchorY

    SearchDropSurface {
        id: dropSurface
        x: positioner.horizontalCenter - width / 2
        y: root.isBottomBar ? root.barEdgeY - height : root.barEdgeY
        width: root.dropW
        height: root.dropH
        open: root.isOpen
        held: root.heldByGesture
        heldProgress: GlobalStates.gestureDragProgress
        animationsEnabled: root.animStyle !== "none"
        openDuration: Math.round(600 * Appearance.animMultiplier)
        closeDuration: Math.round(260 * Appearance.animMultiplier)
        targetWidth: root.dropW
        targetHeight: root.dropH
        shoulderRadius: Appearance.rounding.windowRounding
        cornerRadius: Appearance.rounding.windowRounding
        surfaceColor: root.themeBgColor
        transform: Scale {
            yScale: root.isBottomBar ? -1 : 1
            origin.y: dropSurface.height / 2
        }
    }

    // The part of the screen the drop covers right now: input mask, blur exclusion,
    // and the content's clip.
    Item {
        id: dropContainer
        x: positioner.horizontalCenter - width / 2
        y: root.isBottomBar ? root.barEdgeY - height : root.barEdgeY
        width: Math.min(root.dropW, dropSurface.visibleWidth)
        height: dropSurface.visibleHeight
        visible: dropSurface.visible

        onXChanged: root._updateBlurExclusion()
        onYChanged: root._updateBlurExclusion()
        onWidthChanged: root._updateBlurExclusion()
        onHeightChanged: root._updateBlurExclusion()

        // ── Content (clipped to the drop's length, never its width) ──────────
        Item {
            id: clippingClip
            x: (dropContainer.width - width) / 2
            width: root.dropW + 400
            height: parent.height
            clip: true

            Item {
                id: contentWrapper
                x: 200
                width: root.dropW
                height: root.dropH
                y: root.isBottomBar ? parent.height - height : 0
                opacity: dropSurface.contentOpacity
                visible: opacity > 0.001

                Loader {
                    id: searchWidgetLoader
                    property bool loadedOnce: false
                    active: loadedOnce || root.isWidgetActive
                    focus: root.isOpen
                    anchors.fill: parent
                    sourceComponent: Component {
                        SearchWidget {
                            id: searchWidget
                            hostWidth: root.dropW
                            hostHeight: root.dropH
                            surfaceAnimating: dropSurface.morphing
                            Component.onCompleted: {
                                root.searchWidgetRef = searchWidget;
                                if (GlobalStates.activeSearchQuery) {
                                    searchWidget.setSearchingText(GlobalStates.activeSearchQuery);
                                    GlobalStates.activeSearchQuery = "";
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
            if (root.isOpen) {
                GlobalFocusGrab.addDismissable(root);
                if (root.searchWidgetRef) {
                    Qt.callLater(() => root.searchWidgetRef.focusSearchInput());
                }
            } else {
                GlobalFocusGrab.removeDismissable(root);
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
            if (root.isOpen && GlobalStates.activeSearchQuery && root.searchWidgetRef) {
                root.searchWidgetRef.setSearchingText(GlobalStates.activeSearchQuery);
                GlobalStates.activeSearchQuery = "";
            }
        }
    }

    /**
     * The classic overview, pulled out of the search as a drop of its own
     * (SearchOverviewBubble). It leaves with the search's first frame and is
     * tucked back into it while a query owns the drop. Hosted: the drop paints
     * the overview's panel, so the widget draws no panel or shadow of its own.
     */
    SearchOverviewBubble {
        id: overviewBubble
        anchors.fill: parent
        readonly property var overview: overviewLoader.item
        searchOpen: root.isOpen
        wanted: root.overviewShown && overview !== null
        held: root.heldByGesture && root.overviewShown
        heldProgress: GlobalStates.gestureDragProgress
        animationsEnabled: root.animStyle !== "none"
        // Coming back out of a search that is already open (the query was cleared) is a
        // smaller move than leaving the bar with it, and waiting on the full opening read
        // as a slow collapse.
        openDuration: Math.round((dropSurface.clock >= 1 ? 440 : 700) * Appearance.animMultiplier)
        closeDuration: Math.round(240 * Appearance.animMultiplier)
        tuckDuration: Math.round(460 * Appearance.animMultiplier)

        barEdgeY: root.barEdgeY
        away: root.isBottomBar ? -1 : 1
        searchCenterX: positioner.horizontalCenter
        searchBodyWidth: dropSurface.liveBodyWidth
        searchHeight: dropSurface.visibleHeight
        searchRadius: dropSurface.liveCornerRadius
        searchRestHeight: root.dropH
        searchColor: root.themeBgColor

        overviewCenterX: root.width / 2
        overviewWidth: overview ? overview.implicitWidth : 0
        overviewHeight: overview ? overview.implicitHeight : 0
        overviewRadius: OverviewStyle.radiusCellOuter + OverviewStyle.panelPadding
        // Where the floating panel used to sit: 10 px under the drop plus the
        // elevation margin it drew its shadow in.
        gap: 10 + Appearance.sizes.elevationMargin
        panelColor: OverviewStyle.colPanel

        Loader { // Classic overview
            id: overviewLoader
            property bool loadedOnce: false
            active: (loadedOnce || root.isWidgetActive) && !root.isScrollingLayout && !Config.options.search.suggestions.enable
            sourceComponent: OverviewWidget {
                panelWindow: root.panelWindow
                monitorIndex: root.monitorIndex
                hosted: true
            }
        }
    }

    Loader { // Scrolling overview
        id: scrollingOverviewLoader
        property bool loadedOnce: false
        // Under the drop: with a fullscreen window the overview paints a screen-wide backdrop.
        z: -1
        // The whole screen, not the space left under the drop: the rows fade out
        // above the collapsed search instead of riding the drop as it grows.
        anchors.fill: parent
        active: (loadedOnce || root.isWidgetActive) && root.isScrollingLayout && !Config.options.search.suggestions.enable
        // The rows play their own entrance and exit (staggered in, quick out);
        // the drop only shows and hides the layer they live on.
        visible: root.isWidgetActive

        sourceComponent: ScrollingOverviewWidget {
            anchors.fill: parent
            panelWindow: root.panelWindow
            monitorIndex: root.monitorIndex
            presented: root.overviewShown
            // Only a real measurement is taken: the field reports a few pixels
            // for its first frames, and following that re-laid every row out
            // (and re-aimed the background zoom) at the start of each open.
            topInset: Appearance.sizes.elevationMargin * 2
            bottomInset: Appearance.sizes.elevationMargin
            Binding on topInset {
                when: root.isOpen && !root.isBottomBar && (root.searchWidgetRef?.normalSearchChromeHeight ?? 0) > 24
                value: positioner.anchorY + (root.searchWidgetRef?.normalSearchChromeHeight ?? 52) + 8 + Appearance.sizes.elevationMargin
                restoreMode: Binding.RestoreNone
            }
            Binding on bottomInset {
                when: root.isOpen && root.isBottomBar && (root.searchWidgetRef?.normalSearchChromeHeight ?? 0) > 24
                value: root.height - (positioner.anchorY + dropState.targetH) + (root.searchWidgetRef?.normalSearchChromeHeight ?? 52) + 8 + Appearance.sizes.elevationMargin
                restoreMode: Binding.RestoreNone
            }
        }
    }

    readonly property var maskItem: dropContainer

    function _updateBlurExclusion() {
        var active = root.isOpen && dropContainer.width > 0 && dropContainer.height > 0;
        var sx = dropContainer.x;
        var sy = dropContainer.y;
        var sw = dropContainer.width;
        var sh = dropContainer.height;

        const topR = dropSurface.liveFillet;
        const bottomR = dropSurface.liveCornerRadius;
        if (GlobalStates.searchDropActive !== active || GlobalStates.searchDropExclusionX !== sx || GlobalStates.searchDropExclusionY !== sy || GlobalStates.searchDropExclusionWidth !== sw || GlobalStates.searchDropExclusionHeight !== sh || GlobalStates.searchDropTopRadius !== topR || GlobalStates.searchDropBottomRadius !== bottomR) {
            GlobalStates.searchDropActive = active;
            GlobalStates.searchDropExclusionX = sx;
            GlobalStates.searchDropExclusionY = sy;
            GlobalStates.searchDropExclusionWidth = sw;
            GlobalStates.searchDropExclusionHeight = sh;
            GlobalStates.searchDropTopRadius = topR;
            GlobalStates.searchDropBottomRadius = bottomR;
        }
    }

    onIsOverviewVisibleChanged: Qt.callLater(_updateBlurExclusion)
    Component.onCompleted: Qt.callLater(_updateBlurExclusion)
}
