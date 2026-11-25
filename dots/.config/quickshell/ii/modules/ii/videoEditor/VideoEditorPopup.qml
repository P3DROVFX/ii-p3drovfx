import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property bool notifIsLeft: (Config.options.notifications.position ?? "top_right").endsWith("left")
    readonly property bool notifIsRight: (Config.options.notifications.position ?? "top_right").endsWith("right")
    readonly property bool popupOnLeftSide: BarPlacement.vertical ? !BarPlacement.bottom : root.notifIsRight
    readonly property bool popupOnRightSide: BarPlacement.vertical ? BarPlacement.bottom : root.notifIsLeft

    LazyLoader {
        id: popupLoader
        active: GlobalStates.videoEditorPopupOpen

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: Quickshell.screens.length > 0
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

            readonly property real sidebarPush: {
                const screenName = popupWindow.screen?.name ?? "";
                if (root.popupOnLeftSide && screenName === GlobalStates.effectiveLeftMonitor)
                    return GlobalStates.animatedLeftSidebarWidth;
                if (root.popupOnRightSide && screenName === GlobalStates.effectiveRightMonitor)
                    return GlobalStates.animatedRightSidebarWidth;
                return 0;
            }

            WlrLayershell.namespace: "quickshell:videoEditorPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            readonly property bool anchoredTop: BarPlacement.vertical || (!BarPlacement.vertical && !BarPlacement.bottom)
            readonly property bool anchoredLeft: BarPlacement.vertical ? !BarPlacement.bottom : root.notifIsRight

            anchors {
                top: popupWindow.anchoredTop
                bottom: !popupWindow.anchoredTop
                left: popupWindow.anchoredLeft
                right: !popupWindow.anchoredLeft
            }

            readonly property int frameThickness: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0
            readonly property int topFrameThickness: (BarPlacement.vertical || BarPlacement.bottom) ? frameThickness : 0
            readonly property int bottomFrameThickness: (BarPlacement.vertical || !BarPlacement.bottom) ? frameThickness : 0
            readonly property int leftFrameThickness: (!BarPlacement.vertical || BarPlacement.bottom) ? frameThickness : 0
            readonly property int rightFrameThickness: (!BarPlacement.vertical || !BarPlacement.bottom) ? frameThickness : 0
            readonly property int barGaps: (BarInteraction.cornerStyle !== 0) ? Appearance.sizes.hyprlandGapsOut : 0
            readonly property real liveBarHeight: GlobalStates.horizontalBarVisibleHeightFor(popupWindow.screen?.name ?? "")
            readonly property real liveVerticalBarWidth: GlobalStates.verticalBarVisibleWidthFor(popupWindow.screen?.name ?? "")

            margins {
                top: {
                    if (BarPlacement.vertical)
                        return topFrameThickness;
                    return BarPlacement.bottom ? 0 : popupWindow.liveBarHeight + topFrameThickness;
                }
                bottom: {
                    if (BarPlacement.vertical)
                        return bottomFrameThickness;
                    return BarPlacement.bottom ? popupWindow.liveBarHeight + bottomFrameThickness : 0;
                }
                left: {
                    if (BarPlacement.vertical)
                        return (BarPlacement.bottom ? leftFrameThickness : popupWindow.liveVerticalBarWidth + leftFrameThickness) + popupWindow.sidebarPush;
                    if (root.notifIsRight)
                        return barGaps + 4 + leftFrameThickness + popupWindow.sidebarPush;
                    return leftFrameThickness + popupWindow.sidebarPush;
                }
                right: {
                    if (BarPlacement.vertical)
                        return (BarPlacement.bottom ? popupWindow.liveVerticalBarWidth + rightFrameThickness : rightFrameThickness) + popupWindow.sidebarPush;
                    if (root.notifIsLeft)
                        return barGaps + 4 + rightFrameThickness + popupWindow.sidebarPush;
                    return rightFrameThickness + popupWindow.sidebarPush;
                }
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight

            mask: Region {
                item: popupContent.staticMaskTarget
            }

            VideoEditorPopupContent {
                id: popupContent
                videoPath: GlobalStates.videoEditorPath
                transformOriginEdge: popupWindow.anchoredTop
                    ? (popupWindow.anchoredLeft ? Item.TopLeft : Item.TopRight)
                    : (popupWindow.anchoredLeft ? Item.BottomLeft : Item.BottomRight)
                onDismissed: GlobalStates.videoEditorPopupOpen = false
                onEditRequested: {
                    GlobalStates.videoEditorPopupOpen = false;
                    if (Config.options.screenRecord.openInLosslessCut) {
                        GlobalStates.launchLosslessCut(GlobalStates.videoEditorPath);
                    } else {
                        GlobalStates.videoEditorOpen = true;
                    }
                }
                onOpenFolderRequested: {
                    const cleanPath = FileUtils.trimFileProtocol(GlobalStates.videoEditorPath || "");
                    const lastSlash = cleanPath.lastIndexOf("/");
                    const folder = lastSlash > 0
                        ? cleanPath.slice(0, lastSlash)
                        : (Config.options.screenRecord?.savePath || FileUtils.trimFileProtocol(Directories.videos));
                    GlobalStates.videoEditorPopupOpen = false;
                    if (folder)
                        Quickshell.execDetached(["xdg-open", folder]);
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onDashboardPanelOpenChanged() {
            if (GlobalStates.dashboardPanelOpen)
                GlobalStates.videoEditorPopupOpen = false;
        }
        function onPoliciesPanelOpenChanged() {
            if (GlobalStates.policiesPanelOpen)
                GlobalStates.videoEditorPopupOpen = false;
        }
    }
}
