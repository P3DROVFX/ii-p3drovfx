import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import qs.modules.ii.verticalBar as VBar
import qs.modules.ii.sidebarPolicies as Policies
import qs.modules.ii.sidebarDashboard as Dashboard
import qs.modules.ii.wrappedFrame as Frame
import qs.modules.ii.topLayer.search as SearchConnect
import qs.modules.ii.topLayer.osd as OsdConnect
import qs.modules.ii.overview

PanelWindow {
    id: topPanel
    color: "transparent"
    WlrLayershell.namespace: "quickshell:topLayer"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3

    Bar.BarThemes {
        id: barThemes
    }

    Component {
        id: policiesContentComponent
        Policies.SidebarPoliciesContent {
            scopeRoot: topPanel
        }
    }

    Component {
        id: dashboardContentComponent
        Dashboard.SidebarDashboardContent {}
    }

    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    readonly property bool barVertical: Config.options.bar.vertical
    readonly property bool barBottom: Config.options.bar.bottom
    readonly property bool barOnLeft: barVertical && !barBottom
    readonly property bool barOnRight: barVertical && barBottom

    property real leftSidebarMaskWidth: 0
    property real rightSidebarMaskWidth: 0

    Connections {
        target: GlobalStates
        ignoreUnknownSignals: true
        function onLeftSidebarTargetWidthChanged() {
            if (GlobalStates.leftSidebarTargetWidth > 0) {
                topPanel.leftSidebarMaskWidth = GlobalStates.leftSidebarTargetWidth;
            }
        }
        function onRightSidebarTargetWidthChanged() {
            if (GlobalStates.rightSidebarTargetWidth > 0) {
                topPanel.rightSidebarMaskWidth = GlobalStates.rightSidebarTargetWidth;
            }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.leftSidebarTargetWidth > 0) {
            topPanel.leftSidebarMaskWidth = GlobalStates.leftSidebarTargetWidth;
        }
        if (GlobalStates.rightSidebarTargetWidth > 0) {
            topPanel.rightSidebarMaskWidth = GlobalStates.rightSidebarTargetWidth;
        }
    }

    readonly property bool leftSidebarOpenOnMonitor: GlobalStates.sidebarLeftOpen && screen.name === GlobalStates.effectiveLeftMonitor
    readonly property bool rightSidebarOpenOnMonitor: GlobalStates.sidebarRightOpen && screen.name === GlobalStates.effectiveRightMonitor
    readonly property bool leftSidebarActiveOnMonitor: GlobalStates.animatedLeftSidebarWidth > 0 && screen.name === GlobalStates.effectiveLeftMonitor && !GlobalStates.policiesDetached
    readonly property bool rightSidebarActiveOnMonitor: GlobalStates.animatedRightSidebarWidth > 0 && screen.name === GlobalStates.effectiveRightMonitor
    readonly property bool searchOpenOnMonitor: GlobalStates.overviewOpen && GlobalStates.searchConnectActive && screen.name === GlobalStates.activeSearchMonitor
    readonly property bool osdOpenOnMonitor: GlobalStates.osdVolumeOpen && GlobalStates.osdConnectActive && screen.name === (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0])?.name

    readonly property bool hasFullscreenWindowOnMonitor: {
        const monitorData = HyprlandData.monitors.find(m => m.name === topPanel.screen.name);
        const specialWsName = monitorData?.specialWorkspace?.name;
        const workspaces = Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === topPanel.screen.name);
        return workspaces.some(workspace => {
            const isWorkspaceActive = workspace.active || (specialWsName && specialWsName !== "" && (workspace.name === specialWsName || workspace.name === "special:" + specialWsName || (specialWsName === "special:special" && workspace.name === "special") || (specialWsName === "special" && workspace.name === "special:special")));

            return isWorkspaceActive && workspace.toplevels.values.some(toplevel => toplevel.wayland && toplevel.wayland.fullscreen);
        });
    }

    readonly property bool leftSidebarWarmOnMonitor: {
        if (GlobalStates.policiesDetached)
            return false;
        if (GlobalStates.effectiveLeftMonitor !== "") {
            return screen.name === GlobalStates.effectiveLeftMonitor;
        }
        return Hyprland.focusedMonitor ? (screen.name === Hyprland.focusedMonitor.name) : false;
    }
    readonly property bool rightSidebarWarmOnMonitor: {
        if (GlobalStates.effectiveRightMonitor !== "") {
            return screen.name === GlobalStates.effectiveRightMonitor;
        }
        return Hyprland.focusedMonitor ? (screen.name === Hyprland.focusedMonitor.name) : false;
    }

    onLeftSidebarActiveOnMonitorChanged: {
        // Debug removed for production performance
    }

    onRightSidebarActiveOnMonitorChanged: {
        // Debug removed for production performance
    }

    readonly property bool barMustShow: {
        if (!barVertical) {
            return horizontalBarLoader.item ? horizontalBarLoader.item.mustShow : false;
        } else {
            return verticalBarLoader.item ? verticalBarLoader.item.mustShow : false;
        }
    }

    readonly property real hBarHiddenAmount: horizontalBarLoader.item ? horizontalBarLoader.item.hiddenAmount : 0
    readonly property real vBarHiddenAmount: verticalBarLoader.item ? verticalBarLoader.item.hiddenAmount : 0

    WlrLayershell.keyboardFocus: (leftSidebarOpenOnMonitor || rightSidebarOpenOnMonitor || searchOpenOnMonitor) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // 1. Wrapped Frame Visuals
    Loader {
        id: frameLoader
        active: topPanel.usingWrappedFrame && !GlobalStates.screenLocked && (!topPanel.hasFullscreenWindowOnMonitor || GlobalStates.overviewOpen || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen)
        anchors.fill: parent
        sourceComponent: Frame.WrappedFrameVisuals {
            showBarBackground: horizontalBarLoader.item ? horizontalBarLoader.item.showBarBackground : (verticalBarLoader.item ? verticalBarLoader.item.showBarBackground : false)
            screen: topPanel.screen

            property real hBarHiddenAmount: topPanel.hBarHiddenAmount
            property real vBarHiddenAmount: topPanel.vBarHiddenAmount

            leftSidebarMaskOffset: topPanel.leftSidebarMaskWidth
            rightSidebarMaskOffset: topPanel.rightSidebarMaskWidth
        }
    }

    // 2. Horizontal Bar Visual Layer
    Loader {
        id: horizontalBarLoader
        active: !topPanel.barVertical && GlobalStates.barOpen && !GlobalStates.screenLocked && (!topPanel.hasFullscreenWindowOnMonitor || GlobalStates.overviewOpen || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen)
        anchors.fill: parent
        sourceComponent: Component {
            Item {
                id: hBarItem
                anchors.fill: parent

                property int monitorIndex: Quickshell.screens.indexOf(topPanel.screen)
                property bool hasActiveWindows: false
                property bool showBarBackground: hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1

                Connections {
                    enabled: Config.options.bar.barBackgroundStyle === 2
                    target: HyprlandData
                    function onWindowListChanged() {
                        const monitor = HyprlandData.monitors.find(m => m.name === topPanel.screen.name);
                        const wsId = monitor?.activeWorkspace?.id;
                        const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;
                        hBarItem.hasActiveWindows = hasWindow;
                    }
                }

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: hBarItem.superShow = true
                }

                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                            return;
                        if (GlobalStates.superDown)
                            showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            hBarItem.superShow = false;
                        }
                    }
                }

                property bool superShow: false
                property bool mustShow: hoverRegion.containsMouse || superShow || topPanel.leftSidebarOpenOnMonitor || topPanel.rightSidebarOpenOnMonitor

                MouseArea {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: !topPanel.barBottom ? parent.top : undefined
                        bottom: topPanel.barBottom ? parent.bottom : undefined
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && topPanel.barBottom) * 1
                    }
                    height: Appearance.sizes.barHeight + Appearance.rounding.screenRounding

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            topMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            bottomMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    Bar.BarContent {
                        id: barContent
                        monitorIndex: hBarItem.monitorIndex
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: (Config?.options.bar.autoHide.enable && !hBarItem.mustShow) ? -Appearance.sizes.barHeight : 0
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable) * -1
                        }

                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barContent)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barContent)
                        }

                        states: State {
                            name: "bottom"
                            when: topPanel.barBottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: (Config?.options.bar.autoHide.enable && !hBarItem.mustShow) ? -Appearance.sizes.barHeight : (Config.options.interactions.deadPixelWorkaround.enable) * -1
                            }
                        }
                    }

                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: hBarItem.showBarBackground && Config.options.bar.cornerStyle === 0 && Config.options.appearance.fakeScreenRounding != 3

                        states: State {
                            name: "bottom"
                            when: topPanel.barBottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                    leftMargin: topPanel.leftSidebarActiveOnMonitor ? GlobalStates.animatedLeftSidebarWidth : 0
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: hBarItem.showBarBackground ? (Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: leftCorner
                                        corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    top: !topPanel.barBottom ? parent.top : undefined
                                    bottom: topPanel.barBottom ? parent.bottom : undefined
                                    right: parent.right
                                    rightMargin: topPanel.rightSidebarActiveOnMonitor ? GlobalStates.animatedRightSidebarWidth : 0
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: hBarItem.showBarBackground ? (Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: rightCorner
                                        corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }

                property alias maskItem: hoverMaskRegion
                property real hiddenAmount: (Config?.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.barHeight : 0

                Behavior on hiddenAmount {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(hBarItem)
                }
            }
        }
    }

    // 3. Vertical Bar Visual Layer
    Loader {
        id: verticalBarLoader
        active: topPanel.barVertical && GlobalStates.barOpen && !GlobalStates.screenLocked && (!topPanel.hasFullscreenWindowOnMonitor || GlobalStates.overviewOpen || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen)
        anchors.fill: parent
        sourceComponent: Component {
            Item {
                id: vBarItem
                anchors.fill: parent

                property int monitorIndex: Quickshell.screens.indexOf(topPanel.screen)
                property bool hasActiveWindows: false
                property bool showBarBackground: hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1

                Connections {
                    enabled: Config.options.bar.barBackgroundStyle === 2
                    target: HyprlandData
                    function onWindowListChanged() {
                        const monitor = HyprlandData.monitors.find(m => m.name === topPanel.screen.name);
                        const wsId = monitor?.activeWorkspace?.id;
                        const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;
                        vBarItem.hasActiveWindows = hasWindow;
                    }
                }

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: vBarItem.superShow = true
                }

                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                            return;
                        if (GlobalStates.superDown)
                            showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            vBarItem.superShow = false;
                        }
                    }
                }

                property bool superShow: false
                property bool mustShow: hoverRegion.containsMouse || superShow || topPanel.leftSidebarOpenOnMonitor || topPanel.rightSidebarOpenOnMonitor

                MouseArea {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors.fill: parent

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            leftMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            rightMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    VBar.VerticalBarContent {
                        id: barContent
                        monitorIndex: vBarItem.monitorIndex
                        implicitWidth: Appearance.sizes.verticalBarWidth
                        width: implicitWidth
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: undefined
                            right: undefined
                        }

                        x: {
                            if (topPanel.barOnLeft) {
                                let hide = (Config?.options.bar.autoHide.enable && !vBarItem.mustShow) ? -Appearance.sizes.verticalBarWidth : 0;
                                let push = (topPanel.leftSidebarActiveOnMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0;
                                return hide + push;
                            } else if (topPanel.barOnRight) {
                                let hide = (Config?.options.bar.autoHide.enable && !vBarItem.mustShow) ? Appearance.sizes.verticalBarWidth : 0;
                                let push = (topPanel.rightSidebarActiveOnMonitor) ? GlobalStates.animatedRightSidebarWidth : 0;
                                return parent.width - width + hide - push;
                            }
                            return 0;
                        }

                        Behavior on x {
                            enabled: !GlobalStates.sidebarLeftOpen && !GlobalStates.sidebarRightOpen && GlobalStates.animatedLeftSidebarWidth === 0 && GlobalStates.animatedRightSidebarWidth === 0
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barContent)
                        }
                    }

                    Loader {
                        id: roundDecorators
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: barContent.right
                            right: undefined
                        }
                        width: Appearance.rounding.screenRounding
                        active: vBarItem.showBarBackground && Config.options.bar.cornerStyle === 0 && Config.options.appearance.fakeScreenRounding != 3

                        states: State {
                            name: "right"
                            when: topPanel.barBottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: barContent.left
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitWidth: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: topCorner
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: vBarItem.showBarBackground ? (Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: topCorner
                                        corner: RoundCorner.CornerEnum.TopRight
                                    }
                                }
                            }
                            RoundCorner {
                                id: bottomCorner
                                anchors {
                                    bottom: parent.bottom
                                    left: !topPanel.barBottom ? parent.left : undefined
                                    right: topPanel.barBottom ? parent.right : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: vBarItem.showBarBackground ? (Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.BottomLeft
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: bottomCorner
                                        corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }

                property alias maskItem: hoverMaskRegion
                property real hiddenAmount: (Config?.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.verticalBarWidth : 0

                Behavior on hiddenAmount {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(vBarItem)
                }
            }
        }
    }

    Loader {
        active: !GlobalStates.connectModeActive
        sourceComponent: Component {
            StyledRectangularShadow {
                target: leftSidebar
            }
        }
    }

    // Space reserver for pinned sidebar in Connect Mode
    PanelWindow {
        id: pinSpaceReserver
        WlrLayershell.namespace: "quickshell:pinReserver"
        exclusionMode: ExclusionMode.Normal
        color: "transparent"
        visible: GlobalStates.connectModeActive && GlobalStates.policiesPinned && topPanel.leftSidebarActiveOnMonitor
        anchors {
            top: true
            bottom: true
            left: true
        }
        implicitWidth: GlobalStates.policiesWidth
        exclusiveZone: implicitWidth - (topPanel.barOnLeft ? 0 : (Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin))
    }

    // Left Sidebar Policies Content
    Rectangle {
        id: leftSidebar
        x: -(width - GlobalStates.animatedLeftSidebarWidth)
        y: (!topPanel.barVertical && !topPanel.barBottom && Config.options.bar.cornerStyle === 0) ? Appearance.sizes.barHeight : 0
        width: Math.round(Math.max(GlobalStates.policiesWidth, GlobalStates.animatedLeftSidebarWidth))
        height: Math.round((!topPanel.barVertical && Config.options.bar.cornerStyle === 0) ? (parent.height - Appearance.sizes.barHeight) : parent.height)
        color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
        border.width: GlobalStates.connectModeActive ? 0 : 1
        border.color: GlobalStates.connectModeActive ? "transparent" : Appearance.colors.colLayer0Border
        radius: GlobalStates.connectModeActive ? 0 : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        visible: topPanel.leftSidebarWarmOnMonitor && (!topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarActiveOnMonitor)

        // GPU compositing during animation: prevents per-frame mask/Region recalc
        // which was causing Wayland surface sync stalls on every animation frame.
        // Only active DURING the open/close animation — not while the sidebar is
        // statically open. Keeping it on while open caused massive CPU usage
        // because every minor visual change (timer ticks, notification syncs,
        // infinite pulse animations, gradient behaviors) forced a full FBO
        // re-render of the entire Phone tab subtree.
        layer.enabled: GlobalStates.leftSidebarAnimating

        Loader {
            active: GlobalStates.connectModeActive && !GlobalStates.policiesDetached
            asynchronous: true
            anchors.fill: parent
            sourceComponent: {
                const pos = Config.options.sidebar.position;
                if (pos === "inverted") {
                    return dashboardContentComponent;
                } else if (pos === "left") {
                    if (GlobalStates.dashboardPanelOpen) {
                        return dashboardContentComponent;
                    } else {
                        return policiesContentComponent;
                    }
                } else {
                    return policiesContentComponent;
                }
            }
        }
    }

    // Detached Sidebar Policies Window
    Loader {
        active: GlobalStates.connectModeActive && GlobalStates.policiesDetached
        sourceComponent: FloatingWindow {
            color: "transparent"
            visible: true
            width: GlobalStates.policiesWidth
            height: topPanel.height - (Appearance.sizes.hyprlandGapsOut * 2)

            Rectangle {
                anchors.fill: parent
                focus: true
                color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                Loader {
                    anchors.fill: parent
                    active: true
                    sourceComponent: Policies.SidebarPoliciesContent {
                        scopeRoot: topPanel
                    }
                }

                Keys.onPressed: event => {
                    if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_D) {
                        GlobalStates.policiesDetached = false;
                        event.accepted = true;
                    }
                }
            }
        }
    }

    // Right Sidebar Dashboard Content
    Rectangle {
        id: rightSidebar
        x: parent.width - Math.round(GlobalStates.animatedRightSidebarWidth)
        y: (!topPanel.barVertical && !topPanel.barBottom && Config.options.bar.cornerStyle === 0) ? Appearance.sizes.barHeight : 0
        width: Math.round(GlobalStates.dashboardWidth)
        height: Math.round((!topPanel.barVertical && Config.options.bar.cornerStyle === 0) ? (parent.height - Appearance.sizes.barHeight) : parent.height)
        color: "transparent"
        border.width: 0
        visible: topPanel.rightSidebarWarmOnMonitor && (!topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarActiveOnMonitor)

        // GPU compositing during animation: prevents per-frame mask/Region recalc
        // which was causing Wayland surface sync stalls on every animation frame.
        // Only active DURING the open/close animation — not while the sidebar is
        // statically open. Keeping it on while open caused visible seam artifacts
        // at the corner junctions because the FBO edge anti-aliasing differs from
        // direct rendering of the RoundCorner overlays.
        layer.enabled: GlobalStates.rightSidebarAnimating

        Loader {
            active: GlobalStates.connectModeActive && (topPanel.rightSidebarActiveOnMonitor || Config?.options.sidebar.keepRightSidebarLoaded)
            asynchronous: true
            anchors.fill: parent
            sourceComponent: {
                const pos = Config.options.sidebar.position;
                if (pos === "inverted") {
                    return policiesContentComponent;
                } else if (pos === "right") {
                    if (GlobalStates.sidebarLeftOpen) {
                        return policiesContentComponent;
                    } else {
                        return dashboardContentComponent;
                    }
                } else {
                    return dashboardContentComponent;
                }
            }
        }
    }

    // Cantos decoradores de Workspace para o modo Hug no Connect Mode
    Loader {
        id: leftSidebarTopCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && Config.options.bar.cornerStyle !== 1 && Config.options.appearance.fakeScreenRounding != 3 && (topPanel.barBottom || Config.options.bar.cornerStyle !== 0) && (!topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarOpenOnMonitor)
        x: GlobalStates.animatedLeftSidebarWidth
        y: 0
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.TopLeft
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
    }

    Loader {
        id: leftSidebarBottomCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && Config.options.bar.cornerStyle !== 1 && Config.options.appearance.fakeScreenRounding != 3 && (topPanel.barVertical === topPanel.barBottom || Config.options.bar.cornerStyle !== 0) && (!topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarOpenOnMonitor)
        x: GlobalStates.animatedLeftSidebarWidth
        anchors.bottom: parent.bottom
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomLeft
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
    }

    Loader {
        id: rightSidebarTopCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && Config.options.bar.cornerStyle !== 1 && Config.options.appearance.fakeScreenRounding != 3 && (topPanel.barVertical !== topPanel.barBottom || Config.options.bar.cornerStyle !== 0) && (!topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarOpenOnMonitor)
        anchors.right: parent.right
        anchors.rightMargin: GlobalStates.animatedRightSidebarWidth
        y: 0
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.TopRight
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
    }

    Loader {
        id: rightSidebarBottomCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && Config.options.bar.cornerStyle !== 1 && Config.options.appearance.fakeScreenRounding != 3 && (!topPanel.barBottom || Config.options.bar.cornerStyle !== 0) && (!topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarOpenOnMonitor)
        anchors.right: parent.right
        anchors.rightMargin: GlobalStates.animatedRightSidebarWidth
        anchors.bottom: parent.bottom
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomRight
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
    }

    // 4. Search Drop (Connect Mode integration)
    Loader {
        id: searchDropLoader
        z: 10
        active: GlobalStates.searchConnectActive && !GlobalStates.screenLocked && (!topPanel.hasFullscreenWindowOnMonitor || GlobalStates.overviewOpen || (searchDropLoader.item && searchDropLoader.item.openProgress > 0.001))
        focus: searchOpenOnMonitor
        sourceComponent: Component {
            SearchConnect.SearchDrop {
                id: searchDrop
                screen: topPanel.screen
                monitorIndex: Quickshell.screens.indexOf(topPanel.screen)
                panelWindow: topPanel
                barVertical: topPanel.barVertical
                barBottom: topPanel.barBottom
                barOnLeft: topPanel.barOnLeft
                barOnRight: topPanel.barOnRight
                usingWrappedFrame: topPanel.usingWrappedFrame
                frameThickness: Config.options.appearance.wrappedFrameThickness
                barHeight: Appearance.sizes.barHeight
                verticalBarWidth: Appearance.sizes.verticalBarWidth
                hBarHiddenAmount: topPanel.hBarHiddenAmount
                vBarHiddenAmount: topPanel.vBarHiddenAmount
                animatedLeftSidebarWidth: GlobalStates.animatedLeftSidebarWidth
                animatedRightSidebarWidth: GlobalStates.animatedRightSidebarWidth
                leftSidebarActiveOnMonitor: topPanel.leftSidebarActiveOnMonitor
                rightSidebarActiveOnMonitor: topPanel.rightSidebarActiveOnMonitor
            }
        }
    }

    // 5. OSD Drop (Connect Mode integration)
    Loader {
        id: osdDropLoader
        z: 11
        active: GlobalStates.osdConnectActive && !GlobalStates.screenLocked
        sourceComponent: Component {
            OsdConnect.OsdDrop {
                screen: topPanel.screen
                panelWindow: topPanel
                barVertical: topPanel.barVertical
                barBottom: topPanel.barBottom
                barOnLeft: topPanel.barOnLeft
                barOnRight: topPanel.barOnRight
                usingWrappedFrame: topPanel.usingWrappedFrame
                frameThickness: Config.options.appearance.wrappedFrameThickness
                barHeight: Appearance.sizes.barHeight
                verticalBarWidth: Appearance.sizes.verticalBarWidth
                hBarHiddenAmount: topPanel.hBarHiddenAmount
                vBarHiddenAmount: topPanel.vBarHiddenAmount
                animatedLeftSidebarWidth: GlobalStates.animatedLeftSidebarWidth
                animatedRightSidebarWidth: GlobalStates.animatedRightSidebarWidth
                leftSidebarActiveOnMonitor: topPanel.leftSidebarActiveOnMonitor
                rightSidebarActiveOnMonitor: topPanel.rightSidebarActiveOnMonitor
                hasFullscreenWindow: topPanel.hasFullscreenWindowOnMonitor
            }
        }
    }

    // Static items for input masking to avoid per-frame Region recalculations
    Item {
        id: leftSidebarMaskItem
        x: 0
        y: (!topPanel.barVertical && !topPanel.barBottom) ? Appearance.sizes.barHeight : 0
        width: GlobalStates.animatedLeftSidebarWidth > 0 ? topPanel.leftSidebarMaskWidth : 0
        height: (!topPanel.barVertical) ? (parent.height - Appearance.sizes.barHeight) : parent.height
    }

    Item {
        id: rightSidebarMaskItem
        x: parent.width - width
        y: (!topPanel.barVertical && !topPanel.barBottom) ? Appearance.sizes.barHeight : 0
        width: GlobalStates.animatedRightSidebarWidth > 0 ? topPanel.rightSidebarMaskWidth : 0
        height: (!topPanel.barVertical) ? (parent.height - Appearance.sizes.barHeight) : parent.height
    }

    // Static corner mask items to prevent per-frame Region recalculation
    Item {
        id: leftSidebarTopCornerMaskItem
        x: topPanel.leftSidebarMaskWidth
        y: 0
        width: leftSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: leftSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: leftSidebarBottomCornerMaskItem
        x: topPanel.leftSidebarMaskWidth
        y: topPanel.height - (leftSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0)
        width: leftSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: leftSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: rightSidebarTopCornerMaskItem
        x: topPanel.width - topPanel.rightSidebarMaskWidth - width
        y: 0
        width: rightSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: rightSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: rightSidebarBottomCornerMaskItem
        x: topPanel.width - topPanel.rightSidebarMaskWidth - width
        y: topPanel.height - height
        width: rightSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: rightSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    // Static mask item for search drop bounds
    Item {
        id: searchDropMaskItem
        visible: searchDropLoader.active && searchDropLoader.item && searchDropLoader.item.isWidgetActive
        x: {
            if (searchDropLoader.item && searchDropLoader.item.isOverviewVisible)
                return 0;
            return searchDropLoader.item ? searchDropLoader.item.x + (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.x : 0) : 0;
        }
        y: {
            if (searchDropLoader.item && searchDropLoader.item.isOverviewVisible)
                return 0;
            return searchDropLoader.item ? searchDropLoader.item.y + (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.y : 0) : 0;
        }
        width: {
            if (searchDropLoader.item && searchDropLoader.item.isOverviewVisible)
                return topPanel.width;
            return searchDropLoader.item ? (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.width : 0) : 0;
        }
        height: {
            if (searchDropLoader.item && searchDropLoader.item.isOverviewVisible)
                return topPanel.height;
            return searchDropLoader.item ? (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.height : 0) : 0;
        }
    }

    // Static mask item for OSD drop bounds
    Item {
        id: osdDropMaskItem
        visible: osdDropLoader.active && osdDropLoader.item && osdDropLoader.item.isWidgetActive
        x: osdDropLoader.item ? osdDropLoader.item.x + (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.x : 0) : 0
        y: osdDropLoader.item ? osdDropLoader.item.y + (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.y : 0) : 0
        width: osdDropLoader.item ? (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.width : 0) : 0
        height: osdDropLoader.item ? (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.height : 0) : 0
    }

    // Mask region definitions
    mask: Region {
        Region {
            // Bar horizontal
            item: (horizontalBarLoader.item && horizontalBarLoader.item.maskItem) ? horizontalBarLoader.item.maskItem : null
        }
        Region {
            // Bar vertical
            item: (verticalBarLoader.item && verticalBarLoader.item.maskItem) ? verticalBarLoader.item.maskItem : null
        }
        Region {
            // Frame
            regions: frameLoader.item ? [frameLoader.item.frameMask] : []
        }
        Region {
            // Left sidebar
            item: leftSidebarMaskItem
        }
        Region {
            // Right sidebar
            item: rightSidebarMaskItem
        }
        Region {
            item: leftSidebarTopCornerMaskItem
        }
        Region {
            item: leftSidebarBottomCornerMaskItem
        }
        Region {
            item: rightSidebarTopCornerMaskItem
        }
        Region {
            item: rightSidebarBottomCornerMaskItem
        }
        Region {
            // Search drop
            item: searchDropMaskItem
        }
        Region {
            // OSD drop
            item: osdDropMaskItem
        }
    }

    Connections {
        target: GlobalStates
        function onPoliciesPinnedChanged() {
            if (GlobalStates.sidebarLeftOpen && topPanel.screen.name === GlobalStates.activeLeftSidebarMonitor) {
                if (GlobalStates.policiesPinned) {
                    GlobalFocusGrab.removeDismissable(topPanel);
                } else {
                    GlobalFocusGrab.addDismissable(topPanel);
                }
            }
        }
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen && topPanel.screen.name === GlobalStates.effectiveRightMonitor) {
                GlobalFocusGrab.addDismissable(topPanel);
            } else {
                GlobalFocusGrab.removeDismissable(topPanel);
            }
        }
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen && topPanel.screen.name === GlobalStates.effectiveLeftMonitor) {
                if (!GlobalStates.policiesPinned) {
                    GlobalFocusGrab.addDismissable(topPanel);
                }
            } else {
                GlobalFocusGrab.removeDismissable(topPanel);
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            if (GlobalStates.sidebarRightOpen && topPanel.screen.name === GlobalStates.effectiveRightMonitor) {
                GlobalStates.sidebarRightOpen = false;
            }
            if (GlobalStates.sidebarLeftOpen && topPanel.screen.name === GlobalStates.effectiveLeftMonitor) {
                if (!GlobalStates.policiesPinned) {
                    GlobalStates.sidebarLeftOpen = false;
                }
            }
        }
    }

    Item {
        id: keyFocusHandler
        focus: leftSidebarOpenOnMonitor || rightSidebarOpenOnMonitor || searchOpenOnMonitor
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                GlobalStates.sidebarRightOpen = false;
                GlobalStates.sidebarLeftOpen = false;
                if (searchOpenOnMonitor) {
                    GlobalStates.overviewOpen = false;
                }
                event.accepted = true;
            }

            if (event.modifiers === Qt.ControlModifier && leftSidebarOpenOnMonitor) {
                if (event.key === Qt.Key_O) {
                    GlobalStates.policiesExtended = !GlobalStates.policiesExtended;
                } else if (event.key === Qt.Key_D) {
                    GlobalStates.policiesDetached = !GlobalStates.policiesDetached;
                } else if (event.key === Qt.Key_P) {
                    GlobalStates.policiesPinned = !GlobalStates.policiesPinned;
                }
                event.accepted = true;
            }
        }
    }
}
