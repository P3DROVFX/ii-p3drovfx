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

PanelWindow {
    id: topPanel
    color: "transparent"
    WlrLayershell.namespace: "quickshell:topLayer"
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
    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    readonly property bool barVertical: Config.options.bar.vertical
    readonly property bool barBottom: Config.options.bar.bottom
    readonly property bool barOnLeft: barVertical && !barBottom
    readonly property bool barOnRight: barVertical && barBottom

    readonly property bool leftSidebarOpenOnMonitor: GlobalStates.sidebarLeftOpen && screen.name === GlobalStates.activeLeftSidebarMonitor
    readonly property bool rightSidebarOpenOnMonitor: GlobalStates.sidebarRightOpen && screen.name === GlobalStates.activeRightSidebarMonitor
    readonly property bool leftSidebarActiveOnMonitor: GlobalStates.animatedLeftSidebarWidth > 0 && screen.name === GlobalStates.activeLeftSidebarMonitor && !GlobalStates.policiesDetached
    readonly property bool rightSidebarActiveOnMonitor: GlobalStates.animatedRightSidebarWidth > 0 && screen.name === GlobalStates.activeRightSidebarMonitor

    onLeftSidebarActiveOnMonitorChanged: {
        console.log("[TopLayerPanel] leftSidebarActiveOnMonitor changed:", leftSidebarActiveOnMonitor, "screen:", screen.name, "activeLeftSidebarMonitor:", GlobalStates.activeLeftSidebarMonitor, "width:", GlobalStates.animatedLeftSidebarWidth);
    }

    onRightSidebarActiveOnMonitorChanged: {
        console.log("[TopLayerPanel] rightSidebarActiveOnMonitor changed:", rightSidebarActiveOnMonitor, "screen:", screen.name, "activeRightSidebarMonitor:", GlobalStates.activeRightSidebarMonitor, "width:", GlobalStates.animatedRightSidebarWidth);
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

    WlrLayershell.keyboardFocus: (leftSidebarOpenOnMonitor || rightSidebarOpenOnMonitor) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // 1. Wrapped Frame Visuals
    Loader {
        id: frameLoader
        active: topPanel.usingWrappedFrame && !GlobalStates.screenLocked
        anchors.fill: parent
        sourceComponent: Frame.WrappedFrameVisuals {
            showBarBackground: horizontalBarLoader.item ? horizontalBarLoader.item.showBarBackground : (verticalBarLoader.item ? verticalBarLoader.item.showBarBackground : false)
            screen: topPanel.screen
            
            property real hBarHiddenAmount: topPanel.hBarHiddenAmount
            property real vBarHiddenAmount: topPanel.vBarHiddenAmount
        }
    }

    // 2. Horizontal Bar Visual Layer
    Loader {
        id: horizontalBarLoader
        active: !topPanel.barVertical && GlobalStates.barOpen && !GlobalStates.screenLocked
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
                        const monitor = HyprlandData.monitors.find(m => m.id === hBarItem.monitorIndex);
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
        active: topPanel.barVertical && GlobalStates.barOpen && !GlobalStates.screenLocked
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
                        const monitor = HyprlandData.monitors.find(m => m.id === vBarItem.monitorIndex);
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
        y: (!topPanel.barVertical && !topPanel.barBottom) ? Appearance.sizes.barHeight : 0
        width: Math.round(Math.max(GlobalStates.policiesWidth, GlobalStates.animatedLeftSidebarWidth))
        height: Math.round((!topPanel.barVertical) ? (parent.height - Appearance.sizes.barHeight) : parent.height)
        color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
        border.width: GlobalStates.connectModeActive ? 0 : 1
        border.color: GlobalStates.connectModeActive ? "transparent" : Appearance.colors.colLayer0Border
        radius: GlobalStates.connectModeActive ? 0 : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        visible: topPanel.leftSidebarActiveOnMonitor && !GlobalStates.policiesDetached

        Loader {
            active: !GlobalStates.policiesDetached
            asynchronous: true
            anchors.fill: parent
            sourceComponent: Policies.SidebarPoliciesContent {
                scopeRoot: topPanel
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
                
                Keys.onPressed: (event) => {
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
        y: (!topPanel.barVertical && !topPanel.barBottom) ? Appearance.sizes.barHeight : 0
        width: Math.round(GlobalStates.dashboardWidth)
        height: Math.round((!topPanel.barVertical) ? (parent.height - Appearance.sizes.barHeight) : parent.height)
        color: "transparent"
        border.width: 0
        visible: topPanel.rightSidebarActiveOnMonitor

        Loader {
            active: true
            asynchronous: true
            anchors.fill: parent
            sourceComponent: Dashboard.SidebarDashboardContent {}
        }
    }

    // Cantos decoradores de Workspace para o modo Hug no Connect Mode
    Loader {
        id: leftSidebarTopCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && Config.options.bar.cornerStyle === 0 && Config.options.appearance.fakeScreenRounding != 3 && topPanel.barBottom
        x: GlobalStates.animatedLeftSidebarWidth
        y: 0
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            corner: RoundCorner.CornerEnum.TopLeft
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
    }

    Loader {
        id: leftSidebarBottomCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && Config.options.bar.cornerStyle === 0 && Config.options.appearance.fakeScreenRounding != 3 && (topPanel.barVertical === topPanel.barBottom)
        x: GlobalStates.animatedLeftSidebarWidth
        anchors.bottom: parent.bottom
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            corner: RoundCorner.CornerEnum.BottomLeft
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
    }

    Loader {
        id: rightSidebarTopCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && Config.options.bar.cornerStyle === 0 && Config.options.appearance.fakeScreenRounding != 3 && (topPanel.barVertical !== topPanel.barBottom)
        anchors.right: parent.right
        anchors.rightMargin: GlobalStates.animatedRightSidebarWidth
        y: 0
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            corner: RoundCorner.CornerEnum.TopRight
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
    }

    Loader {
        id: rightSidebarBottomCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && Config.options.bar.cornerStyle === 0 && Config.options.appearance.fakeScreenRounding != 3 && (!topPanel.barBottom)
        anchors.right: parent.right
        anchors.rightMargin: GlobalStates.animatedRightSidebarWidth
        anchors.bottom: parent.bottom
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            corner: RoundCorner.CornerEnum.BottomRight
            color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        }
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
            item: leftSidebar
        }
        Region {
            // Right sidebar
            item: rightSidebar
        }
        Region {
            item: leftSidebarTopCornerLoader.item
        }
        Region {
            item: leftSidebarBottomCornerLoader.item
        }
        Region {
            item: rightSidebarTopCornerLoader.item
        }
        Region {
            item: rightSidebarBottomCornerLoader.item
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
            if (GlobalStates.sidebarRightOpen && topPanel.screen.name === GlobalStates.activeRightSidebarMonitor) {
                GlobalFocusGrab.addDismissable(topPanel);
            } else {
                GlobalFocusGrab.removeDismissable(topPanel);
            }
        }
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen && topPanel.screen.name === GlobalStates.activeLeftSidebarMonitor) {
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
            if (GlobalStates.sidebarRightOpen && topPanel.screen.name === GlobalStates.activeRightSidebarMonitor) {
                GlobalStates.sidebarRightOpen = false;
            }
            if (GlobalStates.sidebarLeftOpen && topPanel.screen.name === GlobalStates.activeLeftSidebarMonitor) {
                if (!GlobalStates.policiesPinned) {
                    GlobalStates.sidebarLeftOpen = false;
                }
            }
        }
    }

    Item {
        id: keyFocusHandler
        focus: leftSidebarOpenOnMonitor || rightSidebarOpenOnMonitor
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                GlobalStates.sidebarRightOpen = false;
                GlobalStates.sidebarLeftOpen = false;
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
