import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    signal setSearchingTextRequested(string text)

    Loader {
        id: overviewVariantsLoader
        active: !GlobalStates.searchConnectActive
        sourceComponent: Component {
            Variants {
                id: overviewVariant

                property var variantModel: Quickshell.screens

                model: overviewVariant.variantModel

                LazyLoader {
                    id: realOverviewLoader
                    required property var modelData
                    property int monitorIndex: overviewVariant.variantModel.indexOf(modelData)
                    property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitorIndex)
                    active: monitorIsFocused

                    component: PanelWindow {
                        id: root

                        readonly property bool monitorIsFocused: realOverviewLoader.monitorIsFocused
                        readonly property int monitorIndex: realOverviewLoader.monitorIndex

                        readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
                        property string searchingText: ""

                        WlrLayershell.namespace: "quickshell:overview"
                        WlrLayershell.layer: WlrLayer.Overlay
                        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                        color: "transparent"

                        property var zoomLevels: {  // has to be reverted compared to background
                            "in": {
                                default: 1,
                                zoomed: 1.04
                            },
                            "out": {
                                default: 1.04,
                                zoomed: 1
                            }
                        }

                        readonly property bool isZoomInStyle: Config.options.overview.scrollingStyle.zoomStyle === "in"
                        readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation

                        property real defaultRatio: isZoomInStyle ? zoomLevels.in.default : zoomLevels.out.default
                        property real zoomedRatio: isZoomInStyle ? zoomLevels.in.zoomed : zoomLevels.out.zoomed

                        property bool isResettingZoom: false
                        property real scaleAnimated: showOpeningAnimation ? GlobalStates.overviewOpen ? zoomedRatio : defaultRatio : 1
                        property real effectiveScale: showOpeningAnimation ? zoomedRatio - scaleAnimated + 1 : 1

                        onIsZoomInStyleChanged: isResettingZoom = true
                        onScaleAnimatedChanged: {
                            if (scaleAnimated === defaultRatio) {
                                isResettingZoom = false;
                            }
                        }

                        // Animation timing constants — single source of truth
                        // Small bounce on enter (expressiveFastSpatial has overshoot ~1.2x)
                        readonly property int animDurationEnter: 480
                        readonly property int animDurationExit: 200
                        readonly property list<real> animCurveEnter: Appearance.animationCurves.expressiveFastSpatial
                        readonly property list<real> animCurveExit: Appearance.animationCurves.emphasizedAccel

                        // Track if we are in exit animation so window stays visible during slide-out
                        property bool exitAnimating: false
                        Timer {
                            id: exitAnimTimer
                            interval: root.animDurationExit + 30
                            onTriggered: root.exitAnimating = false
                        }

                        Connections {
                            target: GlobalStates
                            function onOverviewOpenChanged() {
                                if (!GlobalStates.overviewOpen) {
                                    root.exitAnimating = true;
                                    exitAnimTimer.restart();
                                    searchWidget.disableExpandAnimation();
                                    overviewScope.dontAutoCancelSearch = false;
                                    GlobalStates.searchOnlyMode = false;
                                } else {
                                    root.exitAnimating = false;
                                    exitAnimTimer.stop();
                                    if (!overviewScope.dontAutoCancelSearch) {
                                        searchWidget.cancelSearch();
                                    }
                                    delayedGrabTimer.start();
                                }
                            }
                        }

                        visible: {
                            if (isResettingZoom)
                                return false;
                            if (!showOpeningAnimation)
                                return GlobalStates.overviewOpen || exitAnimating;

                            return isZoomInStyle ? scaleAnimated > defaultRatio : scaleAnimated < defaultRatio;
                        }

                        Behavior on scaleAnimated {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
                        }

                        anchors {
                            top: true
                            bottom: true
                            left: true
                            right: true
                        }
                        property int barSize: Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
                        property int margin: isZoomInStyle ? barSize : barSize * 2
                        margins {
                            top: -margin * 2
                            bottom: -margin * 2
                            left: -margin * 2
                            right: -margin * 2
                        }

                        HyprlandFocusGrab {
                            id: grab
                            windows: [root]
                            property bool canBeActive: root.monitorIsFocused
                            active: false
                            onCleared: () => {
                                if (!active)
                                    GlobalStates.overviewOpen = false;
                            }
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                GlobalStates.overviewOpen = false;
                            }
                        }

                        Timer {
                            id: delayedGrabTimer
                            interval: Config.options.hacks.arbitraryRaceConditionDelay
                            repeat: false
                            onTriggered: {
                                if (!grab.canBeActive)
                                    return;
                                grab.active = GlobalStates.overviewOpen;
                            }
                        }

                        Connections {
                            target: overviewScope
                            function onSetSearchingTextRequested(text) {
                                root.setSearchingText(text);
                            }
                        }

                        function setSearchingText(text) {
                            searchWidget.setSearchingText(text);
                            searchWidget.focusFirstItem();
                        }

                        Item {
                            id: contentItem
                            anchors.fill: parent

                            MouseArea { // We could have used PanelWindow.mask to detect this, but this is more stable
                                anchors.fill: parent
                                onClicked: GlobalStates.overviewOpen = false
                            }

                            Item { // Wrapper for animation
                                id: searchWidgetWrapper
                                implicitHeight: searchWidget.implicitHeight
                                implicitWidth: searchWidget.implicitWidth
                                z: 999

                                // Slide from absolute top of screen — offset large enough to hide above top edge
                                readonly property real slideOffset: -(implicitHeight + root.margin * 2 + Appearance.sizes.elevationMargin + 40)

                                // Driven directly — no Behavior, to avoid QML skipping anim while invisible
                                property real slideY: slideOffset
                                property real slideOpacity: 0.0

                                opacity: slideOpacity
                                transform: Translate {
                                    y: searchWidgetWrapper.slideY
                                }

                                Timer {
                                    id: slideInStartTimer
                                    interval: 16 // 1 frame at 60fps — ensures QML paints reset before animating
                                    repeat: false
                                    onTriggered: {
                                        slideInYAnim.from = searchWidgetWrapper.slideOffset;
                                        slideInYAnim.to = 0;
                                        slideInOpacityAnim.from = 0.0;
                                        slideInOpacityAnim.to = 1.0;
                                        slideInParallel.start();
                                    }
                                }

                                function triggerSlideIn() {
                                    slideOutParallel.stop();
                                    slideInParallel.stop();
                                    slideInStartTimer.stop();
                                    searchWidgetWrapper.slideY = searchWidgetWrapper.slideOffset;
                                    searchWidgetWrapper.slideOpacity = 0.0;
                                    slideInStartTimer.start();
                                }

                                function triggerSlideOut() {
                                    slideInParallel.stop();
                                    slideOutYAnim.from = searchWidgetWrapper.slideY;
                                    slideOutYAnim.to = searchWidgetWrapper.slideOffset;
                                    slideOutOpacityAnim.from = searchWidgetWrapper.slideOpacity;
                                    slideOutOpacityAnim.to = 0.0;
                                    slideOutParallel.start();
                                }

                                ParallelAnimation {
                                    id: slideInParallel
                                    NumberAnimation {
                                        id: slideInYAnim
                                        target: searchWidgetWrapper
                                        property: "slideY"
                                        duration: root.animDurationEnter
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: root.animCurveEnter // bounce curve
                                    }
                                    NumberAnimation {
                                        id: slideInOpacityAnim
                                        target: searchWidgetWrapper
                                        property: "slideOpacity"
                                        duration: root.animDurationEnter
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel // no bounce for opacity
                                    }
                                }

                                ParallelAnimation {
                                    id: slideOutParallel
                                    NumberAnimation {
                                        id: slideOutYAnim
                                        target: searchWidgetWrapper
                                        property: "slideY"
                                        duration: root.animDurationExit
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: root.animCurveExit
                                    }
                                    NumberAnimation {
                                        id: slideOutOpacityAnim
                                        target: searchWidgetWrapper
                                        property: "slideOpacity"
                                        duration: root.animDurationExit
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: root.animCurveExit
                                    }
                                }

                                Connections {
                                    target: root
                                    function onVisibleChanged() {
                                        if (root.visible && GlobalStates.overviewOpen) {
                                            // Window just became visible — trigger slide-in from scratch
                                            searchWidgetWrapper.triggerSlideIn();
                                        }
                                    }
                                }

                                Connections {
                                    target: GlobalStates
                                    function onOverviewOpenChanged() {
                                        if (GlobalStates.overviewOpen) {
                                            if (root.visible) {
                                                searchWidgetWrapper.triggerSlideIn();
                                            }
                                            // If not visible yet, onVisibleChanged will handle it
                                        } else {
                                            searchWidgetWrapper.triggerSlideOut();
                                        }
                                    }
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        GlobalStates.overviewOpen = false;
                                    }
                                }

                                anchors {
                                    horizontalCenter: parent.horizontalCenter
                                    top: parent.top
                                    topMargin: root.margin * 2 + Appearance.sizes.elevationMargin
                                }
                                SearchWidget {
                                    id: searchWidget
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Synchronizer on searchingText {
                                        property alias source: root.searchingText
                                    }
                                }
                            }

                            Loader { // Classic overview
                                id: overviewLoader
                                anchors.top: searchWidgetWrapper.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                active: root.visible && (Config?.options.overview.enable ?? true) && !root.isScrollingLayout

                                readonly property bool isOverviewVisible: GlobalStates.overviewOpen && (root.searchingText == "") && !GlobalStates.searchOnlyMode && !Config.options.search.alwaysListApps

                                visible: opacity > 0

                                // Smooth slide, fade and scale when opening/closing or typing
                                opacity: isOverviewVisible ? 1.0 : 0.0
                                scale: isOverviewVisible ? root.effectiveScale : root.effectiveScale * 0.92

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: overviewLoader.isOverviewVisible ? root.animDurationEnter : root.animDurationExit
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: overviewLoader.isOverviewVisible ? root.animCurveEnter : root.animCurveExit
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: overviewLoader.isOverviewVisible ? root.animDurationEnter : root.animDurationExit
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: overviewLoader.isOverviewVisible ? root.animCurveEnter : root.animCurveExit
                                    }
                                }

                                transform: Translate {
                                    y: overviewLoader.isOverviewVisible ? 0 : 30
                                    Behavior on y {
                                        NumberAnimation {
                                            duration: overviewLoader.isOverviewVisible ? root.animDurationEnter : root.animDurationExit
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: overviewLoader.isOverviewVisible ? root.animCurveEnter : root.animCurveExit
                                        }
                                    }
                                }

                                sourceComponent: OverviewWidget {
                                    panelWindow: root
                                    monitorIndex: root.monitorIndex
                                }
                            }

                            Loader { // Scrolling overview
                                id: scrollingOverviewLoader
                                anchors.fill: parent
                                active: root.visible && (Config?.options.overview.enable ?? true) && root.isScrollingLayout

                                readonly property bool isOverviewVisible: GlobalStates.overviewOpen && (root.searchingText == "") && !GlobalStates.searchOnlyMode && !Config.options.search.alwaysListApps

                                visible: opacity > 0

                                // Smooth slide, fade and scale when opening/closing or typing
                                opacity: isOverviewVisible ? 1.0 : 0.0
                                scale: isOverviewVisible ? root.effectiveScale : root.effectiveScale * 0.92

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: scrollingOverviewLoader.isOverviewVisible ? root.animDurationEnter : root.animDurationExit
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: scrollingOverviewLoader.isOverviewVisible ? root.animCurveEnter : root.animCurveExit
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: scrollingOverviewLoader.isOverviewVisible ? root.animDurationEnter : root.animDurationExit
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: scrollingOverviewLoader.isOverviewVisible ? root.animCurveEnter : root.animCurveExit
                                    }
                                }

                                transform: Translate {
                                    y: scrollingOverviewLoader.isOverviewVisible ? 0 : 30
                                    Behavior on y {
                                        NumberAnimation {
                                            duration: scrollingOverviewLoader.isOverviewVisible ? root.animDurationEnter : root.animDurationExit
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: scrollingOverviewLoader.isOverviewVisible ? root.animCurveEnter : root.animCurveExit
                                        }
                                    }
                                }
                                sourceComponent: ScrollingOverviewWidget {
                                    anchors.fill: parent
                                    panelWindow: root
                                    monitorIndex: root.monitorIndex
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    onSetSearchingTextRequested: (text) => {
        if (GlobalStates.searchConnectActive) {
            GlobalStates.activeSearchQuery = text
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.setSearchingTextRequested(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.setSearchingTextRequested(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    function toggleBluetooth() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.setSearchingTextRequested(Config.options.search.prefix.bluetooth);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function setQuery(text: string): void {
            overviewScope.setSearchingTextRequested(text);
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
        function bluetoothToggle() {
            overviewScope.toggleBluetooth();
        }
        function searchOnlyToggle() {
            if (GlobalStates.overviewOpen) {
                GlobalStates.overviewOpen = false;
            } else {
                GlobalStates.searchOnlyMode = true;
                GlobalStates.overviewOpen = true;
            }
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchOnlyToggle"
        description: "Toggles search only mode on press"

        onPressed: {
            if (GlobalStates.overviewOpen) {
                GlobalStates.overviewOpen = false;
            } else {
                GlobalStates.searchOnlyMode = true;
                GlobalStates.overviewOpen = true;
            }
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
