import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Effects
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
                    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
                    property int monitorIndex: overviewVariant.variantModel.indexOf(modelData)
                    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name === monitor?.name) || (Hyprland.focusedMonitor?.id == monitorIndex)
                    active: monitorIsFocused

                    component: PanelWindow {
                        id: root

                        screen: realOverviewLoader.modelData
                        readonly property bool monitorIsFocused: realOverviewLoader.monitorIsFocused
                        readonly property int monitorIndex: realOverviewLoader.monitorIndex
                        readonly property bool isBottomBar: !Config.options.bar.vertical && Config.options.bar.bottom

                        readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
                        property string searchingText: ""

                        WlrLayershell.namespace: "quickshell:overview"
                        WlrLayershell.layer: WlrLayer.Overlay
                        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                        color: "transparent"

                        property int animDurationEnter: Math.round(420 * Appearance.animMultiplier)
                        property int animDurationExit: Math.round(260 * Appearance.animMultiplier)
                        property list<real> animCurveEnter: Appearance.animationCurves.expressiveFastSpatial
                        property list<real> animCurveExit: Appearance.animationCurves.emphasizedAccel

                        visible: GlobalStates.overviewOpen || searchWidgetWrapper.slideOpacity > 0

                        mask: Region {
                            item: GlobalStates.overviewOpen ? contentItem : null
                        }

                        anchors {
                            top: true
                            bottom: true
                            left: true
                            right: true
                        }
                        property int barSize: Config.options.bar.vertical ? Appearance.sizes.verticalBarWindowWidth : Appearance.sizes.barHeight
                        property int margin: barSize * 2
                        margins {
                            top: -margin * 2
                            bottom: -margin * 2
                            left: -margin * 2
                            right: -margin * 2
                        }

                        Connections {
                            target: GlobalStates
                            function onOverviewOpenChanged() {
                                if (!GlobalStates.overviewOpen) {
                                    searchWidget.disableExpandAnimation();
                                    overviewScope.dontAutoCancelSearch = false;
                                } else {
                                    if (!overviewScope.dontAutoCancelSearch) {
                                        searchWidget.cancelSearch();
                                    }
                                    delayedGrabTimer.start();
                                }
                            }
                        }

                        HyprlandFocusGrab {
                            id: grab
                            windows: [root]
                            property bool canBeActive: root.monitorIsFocused
                            active: false
                            onCleared: () => {
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
                                if (grab.active) {
                                    searchWidget.focusSearchInput();
                                }
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
                                enabled: GlobalStates.overviewOpen
                                onClicked: GlobalStates.overviewOpen = false
                            }

                            Item { // Wrapper for animation
                                id: searchWidgetWrapper
                                readonly property bool isNotchMode: Config.ready && Config.options.bar.dynamicIsland.notchMode.enable
                                implicitHeight: isNotchMode ? GlobalStates.activeSearchHeight : searchWidget.implicitHeight
                                implicitWidth: isNotchMode ? GlobalStates.activeSearchWidth : searchWidget.implicitWidth
                                z: 999
                                visible: !isNotchMode
                                height: isNotchMode ? implicitHeight : searchWidget.height

                                // Slide from top/bottom — direction matches top bar / bottom bar
                                readonly property real slideOffset: (root.isBottomBar ? 1 : -1) * (implicitHeight + root.margin * 2 + Appearance.sizes.elevationMargin + 40)

                                // Driven directly — no Behavior, to avoid QML skipping anim while invisible
                                property real slideY: slideOffset
                                property real slideOpacity: 0.0

                                opacity: isNotchMode ? 0.0 : slideOpacity
                                transform: Translate {
                                    y: searchWidgetWrapper.slideY
                                }

                                layer.enabled: !isNotchMode
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 64.0
                                    blur: (1.0 - searchWidgetWrapper.slideOpacity) * 1.0
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
                                    slideInYAnim.from = searchWidgetWrapper.slideOffset;
                                    slideInYAnim.to = 0;
                                    slideInOpacityAnim.from = 0.0;
                                    slideInOpacityAnim.to = 1.0;
                                    slideInParallel.start();
                                }

                                function triggerSlideOut() {
                                    slideInParallel.stop();
                                    slideOutParallel.stop();
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
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.2
                                    }
                                    NumberAnimation {
                                        id: slideInOpacityAnim
                                        target: searchWidgetWrapper
                                        property: "slideOpacity"
                                        duration: root.animDurationEnter
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                ParallelAnimation {
                                    id: slideOutParallel
                                    NumberAnimation {
                                        id: slideOutYAnim
                                        target: searchWidgetWrapper
                                        property: "slideY"
                                        duration: root.animDurationExit
                                        easing.type: Easing.InCubic
                                    }
                                    NumberAnimation {
                                        id: slideOutOpacityAnim
                                        target: searchWidgetWrapper
                                        property: "slideOpacity"
                                        duration: root.animDurationExit
                                        easing.type: Easing.InCubic
                                        onFinished: {
                                            root.isClosing = false;
                                        }
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

                                width: implicitWidth
                                y: root.isBottomBar ? (parent.height - height - (root.margin * 2 + Appearance.sizes.elevationMargin)) : (root.margin * 2 + Appearance.sizes.elevationMargin)
                                anchors.horizontalCenter: parent.horizontalCenter

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
                                anchors.bottom: root.isBottomBar ? searchWidgetWrapper.top : undefined
                                anchors.top: root.isBottomBar ? undefined : searchWidgetWrapper.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                active: root.visible && !GlobalStates.searchOnlyMode && (Config?.options.overview.enable ?? true) && !root.isScrollingLayout
                                opacity: searchWidgetWrapper.slideOpacity

                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 64.0
                                    blur: (1.0 - Math.min(1.0, Math.max(0.0, overviewLoader.opacity))) * 1.0
                                }

                                transform: Translate {
                                    y: (1.0 - Math.min(1.0, Math.max(0.0, overviewLoader.opacity))) * (root.isBottomBar ? 40 : -40)
                                }

                                sourceComponent: OverviewWidget {
                                    panelWindow: root
                                    visible: (root.searchingText == "") && !GlobalStates.searchOnlyMode
                                    monitorIndex: root.monitorIndex
                                }
                            }

                            Loader { // Scrolling overview
                                id: scrollingOverviewLoader
                                anchors.fill: parent
                                active: root.visible && !GlobalStates.searchOnlyMode && (Config?.options.overview.enable ?? true) && root.isScrollingLayout
                                opacity: searchWidgetWrapper.slideOpacity

                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 64.0
                                    blur: (1.0 - Math.min(1.0, Math.max(0.0, scrollingOverviewLoader.opacity))) * 1.0
                                }

                                transform: Translate {
                                    y: (1.0 - Math.min(1.0, Math.max(0.0, scrollingOverviewLoader.opacity))) * (root.isBottomBar ? 40 : -40)
                                }

                                sourceComponent: ScrollingOverviewWidget {
                                    anchors.fill: parent
                                    panelWindow: root
                                    visible: (root.searchingText == "") && !GlobalStates.searchOnlyMode
                                    monitorIndex: root.monitorIndex
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    onSetSearchingTextRequested: text => {
        if (GlobalStates.searchConnectActive) {
            GlobalStates.activeSearchQuery = text;
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

    function toggleMaterialSymbols() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.setSearchingTextRequested(Config.options.search.prefix.materialSymbols);
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
        function materialSymbolsToggle() {
            overviewScope.toggleMaterialSymbols();
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

        // Debounce: prevents double-fire from the global shortcuts protocol.
        // When SUPER_L is bound as both modifier (SUPER) and trigger key (SUPER_L),
        // the compositor sends `released` twice: once for the key release and once
        // for the modifier state change. The 50ms window catches both without
        // affecting normal press-release cycles.
        property int _lastToggleTime: 0

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            const now = Date.now();
            if (now - _lastToggleTime < 50)
                return;
            _lastToggleTime = now;

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

    GlobalShortcut {
        name: "overviewMaterialSymbolsToggle"
        description: "Toggle Material Symbols search on overview widget"

        onPressed: {
            overviewScope.toggleMaterialSymbols();
        }
    }
}
