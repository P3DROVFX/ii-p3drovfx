import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Display modes popup: the Win+P card. Extend, duplicate, or show everything on a
 * single screen, plus a small stage to drag the screens into place.
 *
 * Opened by the `displayModesToggle` shortcut, `qs ipc call displayModes toggle`, or
 * by plugging in a screen the shell has not seen this session. When the island owns
 * it, the island draws the same card (see NotchContent) and this window stays unloaded.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options.bar.tooltips.enablePopups
        && Config.options.bar.tooltips.enableDisplayModesPopup

    readonly property bool notifIsLeft: (Config.options.notifications.position ?? "top_right").endsWith("left")
    readonly property bool notifIsRight: (Config.options.notifications.position ?? "top_right").endsWith("right")
    readonly property bool popupOnLeftSide: Config.options.bar.vertical ? !Config.options.bar.bottom : root.notifIsLeft
    readonly property bool popupOnRightSide: Config.options.bar.vertical ? Config.options.bar.bottom : root.notifIsRight

    GlobalShortcut {
        name: "displayModesToggle"
        description: "Toggle the display modes popup (extend, duplicate, single screen)"
        onPressed: {
            if (root.enabled)
                GlobalStates.toggleDisplayModes();
        }
    }

    IpcHandler {
        target: "displayModes"
        function toggle(): void {
            if (root.enabled)
                GlobalStates.toggleDisplayModes();
        }
        function open(): void {
            if (root.enabled)
                GlobalStates.displayModesPopupOpen = true;
        }
        function close(): void {
            GlobalStates.displayModesPopupOpen = false;
        }
    }

    Connections {
        target: Config.options.bar.tooltips
        function onEnablePopupsChanged() {
            if (!Config.options.bar.tooltips.enablePopups)
                GlobalStates.displayModesPopupOpen = false;
        }
        function onEnableDisplayModesPopupChanged() {
            if (!Config.options.bar.tooltips.enableDisplayModesPopup)
                GlobalStates.displayModesPopupOpen = false;
        }
    }

    // ── Hotplug ──────────────────────────────────────────────────────────────
    // Hyprland sends `monitoradded` for a plug-in, but also when a disabled screen is
    // enabled again — which this popup does itself. `monitors all` lists disabled and
    // mirroring outputs too, so a name missing from the last listing is a real plug-in.
    property var knownOutputs: null

    Process {
        id: outputsProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let names = [];
                try {
                    names = JSON.parse(this.text).map(m => m.name);
                } catch (e) {
                    return;
                }
                const previous = root.knownOutputs;
                root.knownOutputs = names;
                if (previous === null)
                    return;
                const added = names.some(n => previous.indexOf(n) === -1);
                if (added && root.enabled && Config.options.bar.tooltips.displayModesOnHotplug)
                    GlobalStates.displayModesPopupOpen = true;
            }
        }
    }

    Component.onCompleted: outputsProc.running = true

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "monitoraddedv2" && event.name !== "monitorremovedv2")
                return;
            outputsProc.running = false;
            Qt.callLater(() => outputsProc.running = true);
        }
    }

    LazyLoader {
        id: popupLoader
        active: GlobalStates.displayModesPopupOpen && !GlobalStates.islandOwnsDisplayModes && root.enabled

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: Quickshell.screens.length > 0 && root.enabled
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

            readonly property real sidebarPush: {
                const screenName = popupWindow.screen?.name ?? "";
                if (root.popupOnLeftSide && screenName === GlobalStates.effectiveLeftMonitor)
                    return GlobalStates.animatedLeftSidebarWidth;
                if (root.popupOnRightSide && screenName === GlobalStates.effectiveRightMonitor)
                    return GlobalStates.animatedRightSidebarWidth;
                return 0;
            }

            WlrLayershell.namespace: "quickshell:displayModesPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: BarPlacement.vertical || (!BarPlacement.vertical && !BarPlacement.bottom)
                bottom: !BarPlacement.vertical && BarPlacement.bottom
                left: BarPlacement.vertical ? (BarPlacement.bottom ? false : true) : root.notifIsRight
                right: BarPlacement.vertical ? (BarPlacement.bottom ? true : false) : root.notifIsLeft
            }

            readonly property int frameThickness: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0
            readonly property int topFrameThickness: (BarPlacement.vertical || BarPlacement.bottom) ? frameThickness : 0
            readonly property int bottomFrameThickness: (BarPlacement.vertical || !BarPlacement.bottom) ? frameThickness : 0
            readonly property int leftFrameThickness: (!BarPlacement.vertical || BarPlacement.bottom) ? frameThickness : 0
            readonly property int rightFrameThickness: (!BarPlacement.vertical || !BarPlacement.bottom) ? frameThickness : 0
            readonly property int barGaps: (BarInteraction.cornerStyle !== 0) ? Appearance.sizes.hyprlandGapsOut : 0

            margins {
                top: {
                    if (BarPlacement.vertical)
                        return topFrameThickness;
                    return BarPlacement.bottom ? 0 : Appearance.sizes.barHeight + topFrameThickness;
                }
                bottom: {
                    if (BarPlacement.vertical)
                        return bottomFrameThickness;
                    return BarPlacement.bottom ? Appearance.sizes.barHeight + bottomFrameThickness : 0;
                }
                left: {
                    if (BarPlacement.vertical)
                        return (BarPlacement.bottom ? leftFrameThickness : Appearance.sizes.verticalBarWindowWidth + leftFrameThickness) + popupWindow.sidebarPush;
                    if (root.notifIsRight)
                        return barGaps + 4 + leftFrameThickness + popupWindow.sidebarPush;
                    return leftFrameThickness + popupWindow.sidebarPush;
                }
                right: {
                    if (BarPlacement.vertical)
                        return (BarPlacement.bottom ? Appearance.sizes.verticalBarWindowWidth + rightFrameThickness : rightFrameThickness) + popupWindow.sidebarPush;
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

            DisplayModesPopupContent {
                id: popupContent
                onDismissed: GlobalStates.displayModesPopupOpen = false
            }
        }
    }
}
