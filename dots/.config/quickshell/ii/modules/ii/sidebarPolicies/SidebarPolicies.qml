import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.shared
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    // Keep the native and connect implementations on one state graph.
    property bool detach: GlobalStates.policiesDetached
    property bool pin: GlobalStates.policiesPinned
    property Component contentComponent: SidebarPoliciesContent {}
    property Item sidebarContent

    // Same deal as the right sidebar: the window controller stays cheap and always
    // alive, while the expensive content tree obeys the user's keep-alive preference.
    // Pinned counts as wanted so a pinned-but-closed sidebar never loses its content.
    readonly property bool keepContentLoaded: Config.ready && Config.options.sidebar.keepLeftSidebarLoaded
    readonly property bool contentWanted: GlobalStates.sidebarLeftOpen || root.pin || root.keepContentLoaded

    BarThemes { id: barThemes }
    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    readonly property bool isOnLeft: {
        const pos = Config.options.sidebar.position;
        return pos === "default" || pos === "left"; 
    }

    readonly property string policyMonitorName: isOnLeft ? GlobalStates.effectiveLeftMonitor : GlobalStates.effectiveRightMonitor
    readonly property real sidebarWidth: GlobalStates.policiesWidth
    readonly property real topBarOffset: !Config.options.bar.vertical && !Config.options.bar.bottom && GlobalStates.barOpen ? Appearance.sizes.barHeight : 0
    readonly property real bottomBarOffset: !Config.options.bar.vertical && Config.options.bar.bottom && GlobalStates.barOpen ? Appearance.sizes.barHeight : 0
    readonly property real leftBarOffset: Config.options.bar.vertical && !Config.options.bar.bottom && isOnLeft && GlobalStates.barOpen ? Appearance.sizes.verticalBarWindowWidth : 0
    readonly property real rightBarOffset: Config.options.bar.vertical && Config.options.bar.bottom && !isOnLeft && GlobalStates.barOpen ? Appearance.sizes.verticalBarWindowWidth : 0

    function togglePoliciesExtended() {
        GlobalStates.policiesExtended = !GlobalStates.policiesExtended;
    }

    function togglePoliciesDetach() {
        GlobalStates.policiesDetached = !GlobalStates.policiesDetached;
    }

    function toggleDetach() {
        togglePoliciesDetach();
    }

    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            GlobalStates.policiesPinned = !GlobalStates.policiesPinned;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!GlobalStates.policiesPinned) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else GlobalStates.policiesPinned = !GlobalStates.policiesPinned;
    }

    function togglePoliciesPin() {
        // The virtual reserver in connect mode does not need the native
        // cursor workaround used by a real PanelWindow.
        if (GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate) {
            GlobalStates.policiesPinned = !GlobalStates.policiesPinned;
            return;
        }
        togglePin();
    }

    // Reattaches the content to whichever window is currently up. Safe to call before
    // either side is ready, so the window loading and the content being built no longer
    // have to happen in a particular order.
    function attachContent() {
        if (!root.sidebarContent) return;
        const window = root.detach ? detachedSidebarLoader.item : sidebarLoader.item;
        if (!window) return;
        window.contentParent.children = [root.sidebarContent];
    }

    // Builds the content tree once and hands it to whichever window is up. Idempotent,
    // so every caller can just ask for it without checking first.
    function ensureContent() {
        if (root.sidebarContent) return;
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        root.attachContent();
    }

    // Drops the content tree. Detached from its window first so the window is never
    // left holding a dangling child, and destroy() itself is deferred by QML to the
    // end of the current event loop pass.
    function releaseContent() {
        if (root.contentWanted) return;
        if (!root.sidebarContent) return;
        const content = root.sidebarContent;
        root.sidebarContent = null;
        content.parent = null;
        content.destroy();
    }

    onContentWantedChanged: {
        if (root.contentWanted) {
            root.ensureContent();
            return;
        }
        // Closing is often triggered from inside the content itself (a button, a focus
        // grab dismissal), so let the current event unwind before tearing it down.
        Qt.callLater(root.releaseContent);
    }

    Component.onCompleted: {
        if (root.contentWanted) root.ensureContent();
    }

    onDetachChanged: {
        if (sidebarContent)
            sidebarContent.parent = null;
        if (root.detach && sidebarLoader.item)
            GlobalFocusGrab.removeDismissable(sidebarLoader.item);
        // Loader.active is bound to root.detach. Reparent after the selected
        // window has had a chance to be created or destroyed.
        Qt.callLater(root.attachContent);
    }

    Loader {
        id: sidebarLoader
        active: (!GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate) && !root.detach
        onLoaded: root.attachContent()

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: GlobalStates.sidebarLeftOpen
            
            readonly property real sidebarWidth: {
                return root.sidebarWidth;
            }
            
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.pin ? Math.max(0, sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin - (root.isOnLeft ? root.leftBarOffset : root.rightBarOffset)) : 0
            implicitWidth: sidebarWidth
            WlrLayershell.namespace: root.isOnLeft ? "quickshell:sidebarLeft" : "quickshell:sidebarRight"
            // Hyprland hands pointer focus to any layer surface that maps asking for keyboard
            // interactivity, no matter where the cursor really is, and only re-evaluates it on the
            // next pointer event — so the click meant to close the sidebar again gets spent
            // restoring focus instead. Mapping exclusive and downgrading to on-demand right after
            // makes Hyprland re-evaluate pointer focus itself, handing it back to whatever is
            // actually under the cursor, while the sidebar keeps its keyboard focus.
            // The downgrade has to happen after the surface is mapped, so it's driven by
            // Hyprland's own openlayer event; the timer is only a fallback if that never arrives.
            property bool keyboardExclusive: true
            WlrLayershell.keyboardFocus: panelWindow.keyboardExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

            // Window shortcuts are resolved before a focused TextEdit can consume
            // Ctrl+D when its text selection is active.
            Shortcut {
                sequence: "Ctrl+D"
                enabled: panelWindow.visible
                onActivated: root.togglePoliciesDetach()
            }
            Shortcut {
                sequence: "Ctrl+O"
                enabled: panelWindow.visible
                onActivated: root.togglePoliciesExtended()
            }
            Shortcut {
                sequence: "Ctrl+P"
                enabled: panelWindow.visible
                onActivated: root.togglePoliciesPin()
            }

            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (!panelWindow.keyboardExclusive) return;
                    if (event.name !== "openlayer") return;
                    if (event.data !== panelWindow.WlrLayershell.namespace) return;
                    panelWindow.keyboardExclusive = false;
                }
            }

            Timer {
                id: keyboardFocusDowngrade
                interval: 200
                onTriggered: panelWindow.keyboardExclusive = false
            }
            color: "transparent"

            anchors {
                top: true
                left: root.isOnLeft
                right: !root.isOnLeft
                bottom: true
            }

            // exclusiveZone changes compositor layout, not the surface's own
            // geometry. A pinned sidebar therefore needs explicit margins to
            // avoid covering the bar visually.
            margins {
                top: root.pin ? root.topBarOffset : 0
                bottom: root.pin ? root.bottomBarOffset : 0
                left: root.pin ? root.leftBarOffset : 0
                right: root.pin ? root.rightBarOffset : 0
            }

            mask: Region {
                item: sidebarLeftBackground
            }

            onVisibleChanged: {
                if (visible) {
                    keyboardFocusDowngrade.restart();
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    keyboardFocusDowngrade.stop();
                    panelWindow.keyboardExclusive = true;
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }

            Connections {
                target: root
                function onPinChanged() {
                    if (panelWindow.visible) {
                        if (root.pin) GlobalFocusGrab.removeDismissable(panelWindow);
                        else GlobalFocusGrab.addDismissable(panelWindow);
                    }
                }
            }

            
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (root.pin) return;
                    // Something the sidebar opened has the focus. The grab was
                    // given up all the same, so it is taken back once that
                    // thing is done with — see below.
                    if (GlobalStates.policiesHoldOpen > 0) return;
                    panelWindow.hide();
                }
            }

            Connections {
                target: GlobalStates
                function onPoliciesHoldOpenChanged() {
                    if (GlobalStates.policiesHoldOpen > 0) return;
                    if (!panelWindow.visible || root.pin) return;
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }

            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
            }

            Rectangle {
                id: sidebarLeftBackground
                focus: GlobalStates.sidebarLeftOpen
                color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
                border.width: root.pin ? 0 : 1
                border.color: root.pin ? "transparent" : Appearance.colors.colLayer0Border
                radius: root.pin ? 0 : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
                
                height: root.pin ? parent.height : parent.height - (Appearance.sizes.hyprlandGapsOut * 2)
                y: root.pin ? 0 : Appearance.sizes.hyprlandGapsOut
                width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                property bool _initialized: false

                Timer {
                    interval: 2500 // Avoid animations on first show
                    running: true
                    onTriggered: sidebarLeftBackground._initialized = true
                }

                Behavior on height {
                    enabled: sidebarLeftBackground._initialized
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Behavior on anchors.leftMargin {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on anchors.rightMargin {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }

                state: root.isOnLeft ? "left" : "right"
                states: [
                    State {
                        name: "left"
                        AnchorChanges { 
                            target: sidebarLeftBackground
                            anchors.left: parent.left
                            anchors.right: undefined 
                        }
                        PropertyChanges {
                            target: sidebarLeftBackground
                            anchors.leftMargin: root.pin ? 0 : Appearance.sizes.hyprlandGapsOut
                            anchors.rightMargin: 0
                        }
                    },
                    State {
                        name: "right"
                        AnchorChanges { 
                            target: sidebarLeftBackground
                            anchors.left: undefined
                            anchors.right: parent.right 
                        }
                        PropertyChanges {
                            target: sidebarLeftBackground
                            anchors.rightMargin: root.pin ? 0 : Appearance.sizes.hyprlandGapsOut
                            anchors.leftMargin: 0
                        }
                    }
                ]

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if ((event.modifiers & Qt.ControlModifier) !== 0) {
                        if (event.key === Qt.Key_O) {
                            root.togglePoliciesExtended();
                        } else if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        } else if (event.key === Qt.Key_P) {
                            root.togglePoliciesPin();
                        } else if (event.key === Qt.Key_Tab) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        } else if (event.key === Qt.Key_Backtab) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab(-1);
                        } else if (event.key === Qt.Key_PageDown) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab(1);
                        } else if (event.key === Qt.Key_PageUp) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab(-1);
                        }
                        event.accepted = true;
                    }
                }
            }

            property bool pinned: root.pin
            onPinnedChanged: {
                if (root.pin) return;
                roundDecorators.active = false
            }

            Timer {
                running: root.pin
                interval: 150
                onTriggered: {
                    if (!root.pin) return;
                    roundDecorators.active = true
                }
            }

            Loader {
                id: roundDecorators
                active: false
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: root.isOnLeft ? sidebarLeftBackground.right : undefined
                    right: !root.isOnLeft ? sidebarLeftBackground.left : undefined
                }
                width: Appearance.rounding.screenRounding

                sourceComponent: Item {
                    RoundCorner {
                        anchors {
                            top: parent.top
                            left: root.isOnLeft ? parent.left : undefined
                            right: !root.isOnLeft ? parent.right : undefined
                        }
                        implicitSize: Appearance.rounding.screenRounding
                        color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
                        corner: root.isOnLeft ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.TopRight
                    }
                    RoundCorner {
                        anchors {
                            bottom: parent.bottom
                            left: root.isOnLeft ? parent.left : undefined
                            right: !root.isOnLeft ? parent.right : undefined
                        }
                        implicitSize: Appearance.rounding.screenRounding
                        color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
                        corner: root.isOnLeft ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight
                    }
                }
            }
        }
    }
    
    Loader {
        id: detachedSidebarLoader
        active: root.detach && (!GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate)
        onLoaded: root.attachContent()

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            screen: Quickshell.screens.find(s => s.name === root.policyMonitorName)
                ?? Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""))
                ?? Quickshell.screens[0]
                ?? null
            width: root.sidebarWidth
            height: detachedSidebarRoot.screen ? Math.max(0, detachedSidebarRoot.screen.height - root.topBarOffset - root.bottomBarOffset - Appearance.sizes.hyprlandGapsOut * 2) : 0

            Shortcut {
                sequence: "Ctrl+D"
                enabled: detachedSidebarRoot.visible
                onActivated: root.togglePoliciesDetach()
            }
            Shortcut {
                sequence: "Ctrl+O"
                enabled: detachedSidebarRoot.visible
                onActivated: root.togglePoliciesExtended()
            }
            Shortcut {
                sequence: "Ctrl+P"
                enabled: detachedSidebarRoot.visible
                onActivated: root.togglePoliciesPin()
            }

            onVisibleChanged: {
                if (visible) {
                    if (!root.pin) GlobalFocusGrab.addDismissable(detachedSidebarRoot);
                } else {
                    GlobalFocusGrab.removeDismissable(detachedSidebarRoot);
                }
            }

            Component.onDestruction: GlobalFocusGrab.removeDismissable(detachedSidebarRoot)

            Connections {
                target: root
                function onPinChanged() {
                    if (!detachedSidebarRoot.visible)
                        return;
                    if (root.pin)
                        GlobalFocusGrab.removeDismissable(detachedSidebarRoot);
                    else
                        GlobalFocusGrab.addDismissable(detachedSidebarRoot);
                }
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (!root.pin)
                        GlobalStates.sidebarLeftOpen = false;
                }
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                focus: true
                color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0

                Keys.onPressed: (event) => {
                    if ((event.modifiers & Qt.ControlModifier) !== 0) {
                        if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        } else if (event.key === Qt.Key_O) {
                            root.togglePoliciesExtended();
                        } else if (event.key === Qt.Key_P) {
                            root.togglePoliciesPin();
                        } else if (event.key === Qt.Key_Tab) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        } else if (event.key === Qt.Key_Backtab) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab(-1);
                        } else if (event.key === Qt.Key_PageDown) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab(1);
                        } else if (event.key === Qt.Key_PageUp) {
                            if (root.sidebarContent && typeof root.sidebarContent.cycleTab === "function")
                                root.sidebarContent.cycleTab(-1);
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }



    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.toggleDetach();
        }
    }

}
