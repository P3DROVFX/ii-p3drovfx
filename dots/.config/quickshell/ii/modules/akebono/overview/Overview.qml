pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.akebono
import qs.modules.ii.overview as IiOverview
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property string activeScreen: Hyprland.focusedMonitor?.name ?? Quickshell.primaryScreen?.name ?? ""
    readonly property bool classic: Config.options.akebono?.overview.classic ?? false
    onClassicChanged: {
        GlobalStates.desktopOverviewOpen = false;
        GlobalStates.overviewOpen = false;
    }

    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles the akebono workspace overview"
        onPressed: {
            if (root.classic)
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            else
                GlobalStates.desktopOverviewOpen = !GlobalStates.desktopOverviewOpen;
        }
    }

    IpcHandler {
        target: "akebonoOverview"

        function toggle(): void {
            if (root.classic)
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            else
                GlobalStates.desktopOverviewOpen = !GlobalStates.desktopOverviewOpen;
        }
        function close(): void {
            GlobalStates.desktopOverviewOpen = false;
            GlobalStates.overviewOpen = false;
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData
            property real overviewAnim: 0

            Loader {
                id: classicLoader
                active: root.classic && GlobalStates.overviewOpen && root.activeScreen === screenScope.modelData.name

                sourceComponent: PanelWindow {
                    id: classicRoot
                    readonly property var modelData: screenScope.modelData
                    screen: modelData
                    visible: !GlobalStates.screenLocked
                    color: "transparent"
                    WlrLayershell.namespace: "quickshell:overview"
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    mask: Region {
                        item: classicHost
                    }

                    HyprlandFocusGrab {
                        active: GlobalStates.overviewOpen
                        windows: [classicRoot]
                        onCleared: GlobalStates.overviewOpen = false
                    }

                    Item {
                        id: classicHost
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: classicWidget.implicitWidth
                        implicitHeight: classicWidget.implicitHeight
                        width: implicitWidth
                        height: implicitHeight
                        focus: true

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                GlobalStates.overviewOpen = false;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Left) {
                                Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Right) {
                                Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
                                event.accepted = true;
                            }
                        }

                        IiOverview.OverviewWidget {
                            id: classicWidget
                            panelWindow: classicRoot
                        }
                    }
                }
            }

            Loader {
                id: ovLoader
                active: GlobalStates.desktopOverviewOpen || screenScope.overviewAnim > 0.01

                sourceComponent: PanelWindow {
                    id: ovRoot
                    readonly property var modelData: screenScope.modelData
                    screen: modelData
                    visible: !GlobalStates.screenLocked
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.namespace: "quickshell:akebonoOverview"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: GlobalStates.desktopOverviewOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    property real anim: 0
                    Behavior on anim {
                        NumberAnimation { duration: 440; easing.type: Easing.OutCubic }
                    }
                    onAnimChanged: screenScope.overviewAnim = ovRoot.anim

                    Connections {
                        target: GlobalStates
                        function onDesktopOverviewOpenChanged() {
                            ovRoot.anim = GlobalStates.desktopOverviewOpen ? 1 : 0;
                        }
                    }
                    function lerp(from, to) {
                        return from + (to - from) * ovRoot.anim;
                    }

                    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(ovRoot.screen)
                    readonly property var monitorData: HyprlandData.monitors.find(m => m.id === ovRoot.monitor?.id)
                    readonly property var windowByAddress: HyprlandData.windowByAddress

                    readonly property var rowWorkspaces: {
                        const set = new Set();
                        for (const w of HyprlandData.windowList) {
                            if ((w.workspace?.id ?? -1) > 0 && w.monitor === ovRoot.monitor?.id)
                                set.add(w.workspace.id);
                        }
                        const focused = ovRoot.monitor?.activeWorkspace?.id ?? 1;
                        if (focused > 0)
                            set.add(focused);
                        const arr = Array.from(set).sort((a, b) => a - b);
                        arr.push((arr.length ? arr[arr.length - 1] : 0) + 1);
                        return arr;
                    }
                    function wsIndex(id) {
                        return ovRoot.rowWorkspaces.indexOf(id);
                    }

                    readonly property real wsScale: (ovRoot.height * 0.26 * (monitor?.scale ?? 1)) / Math.max(1, (monitor?.height ?? 1080) - (monitorData?.reserved[1] ?? 0) - (monitorData?.reserved[3] ?? 0))
                    readonly property real cardW: ((monitor?.width ?? 1920) - (monitorData?.reserved[0] ?? 0) - (monitorData?.reserved[2] ?? 0)) * wsScale / (monitor?.scale ?? 1)
                    readonly property real cardH: ((monitor?.height ?? 1080) - (monitorData?.reserved[1] ?? 0) - (monitorData?.reserved[3] ?? 0)) * wsScale / (monitor?.scale ?? 1)
                    readonly property real cardGap: 18
                    readonly property real shadowPad: 26

                    property int draggingFromWorkspace: -1
                    property int draggingTargetWorkspace: -1

                    readonly property int zoomIdx: Math.max(0, ovRoot.wsIndex(ovRoot.monitor?.activeWorkspace?.id ?? 1))
                    readonly property real zoomTX: flick.x + ovRoot.shadowPad + ovRoot.zoomIdx * (ovRoot.cardW + ovRoot.cardGap) - flick.contentX
                    readonly property real zoomTY: flick.y + ovRoot.shadowPad

                    property int selectedIdx: -1

                    function centerOnIndex(i) {
                        flick.contentX = Math.max(0, Math.min(ovRoot.shadowPad + i * (ovRoot.cardW + ovRoot.cardGap) - (flick.width - ovRoot.cardW) / 2, Math.max(0, flick.contentWidth - flick.width)));
                    }
                    function centerOnFocused() {
                        ovRoot.centerOnIndex(ovRoot.zoomIdx);
                    }
                    function moveSelection(d) {
                        const base = ovRoot.selectedIdx === -1 ? ovRoot.zoomIdx : ovRoot.selectedIdx;
                        ovRoot.selectedIdx = Math.max(0, Math.min(base + d, ovRoot.rowWorkspaces.length - 1));
                        ovRoot.centerOnIndex(ovRoot.selectedIdx);
                    }
                    function commitSelection() {
                        const idx = ovRoot.selectedIdx === -1 ? ovRoot.zoomIdx : ovRoot.selectedIdx;
                        GlobalStates.desktopOverviewOpen = false;
                        Hyprland.dispatch(`hl.dsp.focus({workspace = ${ovRoot.rowWorkspaces[idx]}})`);
                    }

                    Component.onCompleted: {
                        ovRoot.centerOnFocused();
                        ovRoot.anim = 1;
                    }

                    Item {
                        anchors.fill: parent
                        focus: true
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                GlobalStates.desktopOverviewOpen = false;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Left) {
                                ovRoot.moveSelection(-1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Right) {
                                ovRoot.moveSelection(1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                ovRoot.commitSelection();
                                event.accepted = true;
                            }
                        }

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (event) => {
                                const step = (event.angleDelta.y / 120) * (ovRoot.cardW + ovRoot.cardGap) * 0.6;
                                flick.contentX = Math.max(0, Math.min(flick.contentX - step, Math.max(0, flick.contentWidth - flick.width)));
                            }
                        }

                        Image {
                            id: backdropWall
                            anchors.fill: parent
                            source: Config.options.background.wallpaperPath
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                        }
                        FastBlur {
                            anchors.fill: parent
                            source: backdropWall
                            radius: 64
                            opacity: ovRoot.anim
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: 0.38 * ovRoot.anim
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: GlobalStates.desktopOverviewOpen = false
                        }

                        Flickable {
                            id: flick
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(canvas.width, ovRoot.width - 120)
                            height: canvas.height
                            contentWidth: canvas.width
                            contentHeight: canvas.height
                            interactive: false
                            clip: true
                            opacity: ovRoot.anim
                            onWidthChanged: if (ovRoot.anim < 0.5) ovRoot.centerOnFocused()
                            onContentWidthChanged: if (ovRoot.anim < 0.5) ovRoot.centerOnFocused()
                            transform: Scale {
                                origin.x: flick.width / 2
                                origin.y: flick.height / 2
                                xScale: 0.92 + 0.08 * ovRoot.anim
                                yScale: 0.92 + 0.08 * ovRoot.anim
                            }

                            Behavior on contentX {
                                enabled: ovRoot.anim > 0.9 && !flick.dragging && !flick.flicking
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }

                            Item {
                                id: canvas
                                width: ovRoot.rowWorkspaces.length * (ovRoot.cardW + ovRoot.cardGap) - ovRoot.cardGap + 2 * ovRoot.shadowPad
                                height: ovRoot.cardH + 2 * ovRoot.shadowPad

                                Repeater {
                                    model: ovRoot.rowWorkspaces

                                    delegate: Item {
                                        id: wsCard
                                        required property int modelData
                                        required property int index
                                        readonly property bool focusedWs: ovRoot.monitor?.activeWorkspace?.id === wsCard.modelData
                                        readonly property bool keySelected: ovRoot.selectedIdx === wsCard.index
                                        property bool hoveredWhileDragging: false
                                        x: ovRoot.shadowPad + index * (ovRoot.cardW + ovRoot.cardGap)
                                        y: ovRoot.shadowPad
                                        width: ovRoot.cardW
                                        height: ovRoot.cardH

                                        ShaderEffect {
                                            id: cardShadow
                                            readonly property real pad: ovRoot.shadowPad
                                            readonly property real offY: 6
                                            x: -pad
                                            y: -pad + offY
                                            width: wsCard.width + 2 * pad
                                            height: wsCard.height + 2 * pad
                                            property vector2d size: Qt.vector2d(width, height)
                                            property color color: Qt.rgba(0, 0, 0, 0.36)
                                            property real radius: 22
                                            property real smoothing: AkebonoAppearance.squircleSmoothing
                                            property real spread: 15
                                            property vector2d boxHalf: Qt.vector2d(wsCard.width / 2, wsCard.height / 2)
                                            property vector2d boxCenter: Qt.vector2d(width / 2, height / 2)
                                            fragmentShader: Quickshell.shellPath("assets/shaders/akebono/shadow.frag.qsb")
                                        }

                                        Rectangle {
                                            id: cardBg
                                            anchors.fill: parent
                                            radius: 22
                                            color: wsCard.hoveredWhileDragging ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer0
                                            border.width: (wsCard.keySelected || wsCard.focusedWs) ? 2.5 : 1
                                            border.color: wsCard.keySelected ? Appearance.colors.colPrimary
                                                : wsCard.focusedWs ? Appearance.colors.colSecondary
                                                : wsCard.hoveredWhileDragging ? Appearance.colors.colLayer2Hover
                                                : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                                        }

                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            source: Config.options.background.wallpaperPath
                                            fillMode: Image.PreserveAspectCrop
                                            opacity: 0.55
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: wsCard.width - 4
                                                    height: wsCard.height - 4
                                                    radius: 20
                                                }
                                            }
                                        }

                                        StyledText {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 12
                                            text: wsCard.modelData
                                            font.pixelSize: Appearance.font.pixelSize.huge
                                            font.weight: Font.DemiBold
                                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.35)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (ovRoot.draggingTargetWorkspace !== -1)
                                                    return;
                                                GlobalStates.desktopOverviewOpen = false;
                                                Hyprland.dispatch(`hl.dsp.focus({workspace = ${wsCard.modelData}})`);
                                            }
                                        }

                                        DropArea {
                                            anchors.fill: parent
                                            onEntered: {
                                                ovRoot.draggingTargetWorkspace = wsCard.modelData;
                                                if (ovRoot.draggingFromWorkspace === ovRoot.draggingTargetWorkspace)
                                                    return;
                                                wsCard.hoveredWhileDragging = true;
                                            }
                                            onExited: {
                                                wsCard.hoveredWhileDragging = false;
                                                if (ovRoot.draggingTargetWorkspace === wsCard.modelData)
                                                    ovRoot.draggingTargetWorkspace = -1;
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: ToplevelManager.toplevels.values.filter((toplevel) => {
                                            const win = ovRoot.windowByAddress[`0x${toplevel.HyprlandToplevel?.address}`];
                                            return win && win.monitor === ovRoot.monitor?.id && (win.workspace?.id ?? -1) > 0 && ovRoot.wsIndex(win.workspace.id) >= 0;
                                        })
                                    }
                                    delegate: OverviewWindow {
                                        required property var modelData
                                        toplevel: modelData
                                        windowData: ovRoot.windowByAddress[`0x${modelData.HyprlandToplevel?.address}`]
                                        overview: ovRoot
                                        xOffset: ovRoot.shadowPad + ovRoot.wsIndex(windowData?.workspace.id ?? -1) * (ovRoot.cardW + ovRoot.cardGap)
                                        yOffset: ovRoot.shadowPad
                                    }
                                }
                            }
                        }

                        Item {
                            id: zoomItem
                            visible: GlobalStates.desktopOverviewOpen && ovRoot.anim < 0.995
                            x: ovRoot.lerp(0, ovRoot.zoomTX)
                            y: ovRoot.lerp(0, ovRoot.zoomTY)
                            width: ovRoot.lerp(ovRoot.width, ovRoot.cardW)
                            height: ovRoot.lerp(ovRoot.height, ovRoot.cardH)
                            z: 50

                            ScreencopyView {
                                id: zoomShot
                                anchors.fill: parent
                                captureSource: zoomItem.visible ? ovRoot.screen : null
                                live: false
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: zoomItem.width
                                        height: zoomItem.height
                                        radius: 22 * ovRoot.anim
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
