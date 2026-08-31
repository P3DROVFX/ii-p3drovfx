import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

pragma ComponentBehavior: Bound

Scope {
    id: dock

    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    readonly property string dockEffectivePosition: {
        const pos = Config.options?.dock.position ?? "bottom"
        if (pos !== "auto") return pos
        return (Config.options?.bar.bottom && !Config.options?.bar.vertical) ? "top" : "bottom"
    }

    readonly property bool isVertical: dockEffectivePosition === "left" || dockEffectivePosition === "right"

    function computeSizes(opts) {
        const isDynamic = opts.isDynamicIsland ?? false
        const isHug = opts.isHug ?? false
        const isAttached = opts.isAttachedToEdge ?? false
        const gapsOut = opts.gapsOut
        const shadowPad = Math.round(Appearance.sizes.elevationMargin * 1.2)

        const concaveReserve = isDynamic ? Math.max(0, opts.concaveCornerRadius || 0) : 0
        // A floating shadow is larger than gapsOut. Reserve its complete blur
        // envelope on both sides so the layer surface never becomes a clip wall.
        const floatingPad = isAttached ? 0 : shadowPad
        const mainPad = isDynamic ? (concaveReserve * 2) : (isHug ? (shadowPad * 2) : (floatingPad * 2))
        const crossPad = isAttached ? (isHug ? shadowPad : 0) : (floatingPad * 2)

        const barConflicts = opts.barActive && (opts.isVertical !== opts.barIsVertical)
        const barOffset = barConflicts ? (opts.isVertical ? opts.barThickness : 0) : 0
        const barOffsetH = barConflicts ? (!opts.isVertical ? opts.barThickness : 0) : 0

        const maxW = Math.max(1, opts.availableW - (isAttached ? 0 : gapsOut * 2) - barOffsetH)
        const maxH = Math.max(1, opts.availableH - (isAttached ? 0 : gapsOut * 2) - barOffset)

        const contentW = opts.contentVisualWidth + opts.dockPadding * 2
        const contentH = opts.contentVisualHeight + opts.dockPadding * 2
        const baseContentW = opts.baseVisualWidth + opts.dockPadding * 2
        const baseContentH = opts.baseVisualHeight + opts.dockPadding * 2
        const mainSafety = (opts.maxMainExtra || 0)
        const crossSafety = opts.maxCrossExtra || 0

        // The PanelWindow reserves a stable safe envelope. Only the visible
        // tray follows the actual animated content geometry.
        const bgW = Math.max(1, opts.isVertical ? baseContentW : Math.min(contentW + (isDynamic ? concaveReserve * 2 : 0), maxW - (isDynamic ? 0 : (isHug ? shadowPad * 2 : floatingPad * 2))))
        const bgH = Math.max(1, opts.isVertical ? Math.min(contentH + (isDynamic ? concaveReserve * 2 : 0), maxH - (isDynamic ? 0 : (isHug ? shadowPad * 2 : floatingPad * 2))) : baseContentH)

        const baseDockW = opts.isVertical ? baseContentW + crossSafety + crossPad : Math.min(baseContentW + mainSafety + mainPad, maxW)
        const baseDockH = opts.isVertical ? Math.min(baseContentH + mainSafety + mainPad, maxH) : Math.min(baseContentH + crossSafety + crossPad, maxH)

        const fullDockW = Math.min(baseDockW, maxW)
        const fullDockH = Math.min(baseDockH, maxH)

        return {
            maxWidth: maxW,
            maxHeight: maxH,
            dockWidth: fullDockW,
            dockHeight: fullDockH,
            dockThickness: opts.isVertical ? fullDockW : fullDockH,
            unmagnifiedThickness: opts.isVertical ? baseContentW + crossPad : baseContentH + crossPad,
            surfaceMargin: floatingPad,
            backgroundWidth: bgW,
            backgroundHeight: bgH
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData
            
            visible: !GlobalStates.screenLocked && !positionChanging && !GlobalStates.oledSaverMonitors.includes(modelData.name) && !GlobalStates.isMediaModeActiveForScreen(modelData ? modelData.name : "")
            // using a flag for positionChanging is not really necessary, but it prevents some graphical issues caused by qml when the dock is moving

            readonly property real availableW: screen?.width ?? 1920
            readonly property real availableH: screen?.height ?? 1080
            readonly property bool barActive: GlobalStates.barOpen
            readonly property bool barIsVertical: Config.options?.bar?.vertical ?? false
            readonly property real barThickness: barActive? (barIsVertical ? (Config.options?.bar?.sizes?.width ?? Appearance.sizes.verticalBarWidth) : (Config.options?.bar?.sizes?.height ?? Appearance.sizes.barHeight)) : 0

            readonly property bool enableMagnification: Config.options?.dock?.enableMagnification ?? false
            readonly property real magnificationScale: Config.options?.dock?.magnificationScale ?? 1.5
            // Safe interaction/render reserve; the visual background follows
            // dockContent.visualWidth/visualHeight independently.
            readonly property real magExtra: enableMagnification ? dockContent.maximumMagnificationExtra : 0
            readonly property real magCrossExtra: enableMagnification ? dockContent.maximumMagnificationCrossExtra : 0

            readonly property bool isVertical: dock.isVertical
            readonly property real dockThickness: dockRoot.sizing.dockThickness
            readonly property real unmagnifiedThickness: dockRoot.sizing.unmagnifiedThickness
            readonly property real surfaceMargin: dockRoot.sizing.surfaceMargin
            readonly property bool anySidebarOpen: GlobalStates.effectiveLeftOpen || GlobalStates.effectiveRightOpen

            readonly property bool isSpecialWorkspaceOpen: {
                if (!dockRoot.screen) return false;
                const monitor = HyprlandData.monitors.find(m => m.name === dockRoot.screen.name);
                if (!monitor || !monitor.specialWorkspace) return false;
                return monitor.specialWorkspace.name !== "";
            }

            property bool reveal: dock.pinned || (!anySidebarOpen && ((Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || (dockContent.requestDockShow) || (workspaceEmpty && !isSpecialWorkspaceOpen && (!(Config.options?.dock.showOnlyOnFocusedMonitor ?? false) || isFocusedMonitor))))
            property bool positionChanging: false

            // TODO: check for multi-monitor situations
            readonly property bool workspaceEmpty: {
                const wsId = HyprlandData.activeWorkspace?.id ?? -1
                if (wsId === -1) return true
                return HyprlandData.hyprlandClientsForWorkspace(wsId).length === 0
            }

            readonly property bool isFocusedMonitor: {
                return (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") === (dockRoot.screen ? dockRoot.screen.name : "")
            }

            readonly property bool isDynamicIsland: dockContent.isDynamicIsland
            readonly property bool isHug: dockContent.isHug
            readonly property bool isAttachedToEdge: dockContent.isAttachedToEdge
            readonly property real concaveCornerRadius: {
                if ((Config.options?.dock?.dockRadius ?? -1) >= 0) {
                    return Math.min(Config.options.dock.dockRadius, dockRoot.dockThickness * 0.8)
                }
                return Math.min(Appearance.rounding.large, dockRoot.dockThickness * 0.8)
            }
            readonly property var sizing: dock.computeSizes({
                gapsOut: Appearance.sizes.hyprlandGapsOut,
                isDynamicIsland: dockRoot.isDynamicIsland,
                isHug: dockRoot.isHug,
                isAttachedToEdge: dockRoot.isAttachedToEdge,
                concaveCornerRadius: dockRoot.concaveCornerRadius,
                isVertical: dock.isVertical,
                barActive: barActive,
                barIsVertical: barIsVertical,
                barThickness: barThickness,
                availableW: availableW,
                availableH: availableH,
                contentVisualWidth: dockContent.visualWidth,
                contentVisualHeight: dockContent.visualHeight,
                baseVisualWidth: dockContent.baseVisualWidth,
                baseVisualHeight: dockContent.baseVisualHeight,
                dockPadding: dockContent.dockPadding,
                maxMainExtra: dockRoot.magExtra,
                maxCrossExtra: dockRoot.magCrossExtra
            })

            implicitWidth: Math.max(1, dockRoot.sizing.dockWidth)
            implicitHeight: Math.max(1, dockRoot.sizing.dockHeight)

            anchors {
                top: dock.dockEffectivePosition !== "bottom"
                bottom: dock.dockEffectivePosition !== "top"
                left: dock.dockEffectivePosition !== "right"
                right: dock.dockEffectivePosition !== "left"
            }

            // Expose the raw window geometry for global gesture tracking,
            // independent of any interactive child item bounds.
            readonly property real actualWindowWidth: width
            readonly property real actualWindowHeight: height

            exclusiveZone: (dock.pinned && reveal) ? unmagnifiedThickness : 0
            WlrLayershell.namespace: "quickshell:dock"
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"

            mask: Region {
                item: dockMouseArea
            }

            Timer {
                id: positionChangeTimer
                interval: 200
                onTriggered: dockRoot.positionChanging = false
            }

            Connections {
                target: Config.options.dock
                function onPositionChanged() {
                    dockRoot.positionChanging = true
                    positionChangeTimer.restart()
                }
            }

            HyprlandFocusGrab {
                id: dragFocusGrab
                active: dockContent.dragging
                windows: [dockRoot]
                onCleared: {
                    dockContent.cancelDrag()
                }
            }

            MouseArea {
                id: dockMouseArea
                hoverEnabled: true

                property real hoverRegion: Config.options?.dock?.hoverRegionHeight ?? 2
                property real hiddenOffset: dockRoot.dockThickness - hoverRegion
                property real fullyHiddenOffset: dockRoot.dockThickness + 1
                property real currentOffset: dockRoot.reveal ? 0 : (Config.options?.dock.hoverToReveal ? hiddenOffset : fullyHiddenOffset)

                width: dock.isVertical ? dockRoot.dockThickness : dockRoot.sizing.dockWidth
                height: dock.isVertical ? dockRoot.sizing.dockHeight : dockRoot.dockThickness

                state: dock.dockEffectivePosition

                states: [
                    State {
                        name: "top"
                        AnchorChanges { target: dockMouseArea; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.topMargin: -currentOffset }
                    },
                    State {
                        name: "bottom"
                        AnchorChanges { target: dockMouseArea; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.bottomMargin: -currentOffset }
                    },
                    State {
                        name: "left"
                        AnchorChanges { target: dockMouseArea; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.leftMargin: -currentOffset }
                    },
                    State {
                        name: "right"
                        AnchorChanges { target: dockMouseArea; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
                        PropertyChanges { target: dockMouseArea; anchors.rightMargin: -currentOffset }
                    }
                ]

                Behavior on anchors.topMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }
                Behavior on anchors.bottomMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }
                Behavior on anchors.leftMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }
                Behavior on anchors.rightMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockMouseArea) }

                // Stable safe bounds feed one continuous magnification field,
                // including the overflow area above/next to enlarged icons.
                HoverHandler {
                    id: magnificationHover
                    blocking: false
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                    onPointChanged: {
                        const position = point.position
                        dockContent.updateMagnificationPointerFrom(dockMouseArea, position.x, position.y)
                    }
                    onHoveredChanged: dockContent.setMagnificationHovered(hovered)
                }

                // Neutral host: the classic surface, DropArea and content are
                // siblings so hiding the global rectangle never hides items.
                Item {
                    id: dockSurfaceHost
                    anchors.fill: parent
                    clip: false

                    Rectangle {
                        id: dockVisualBackground
                        clip: false

                        width: Math.max(1, Math.min(
                            dockRoot.sizing.backgroundWidth,
                            dockRoot.sizing.dockWidth
                        ))
                        height: Math.max(1, Math.min(
                            dockRoot.sizing.backgroundHeight,
                            dockRoot.sizing.dockHeight
                        ))

                        color: dockRoot.isDynamicIsland ? "transparent" : Appearance.colors.colLayer0
                        radius: (dockRoot.isDynamicIsland || dockRoot.isHug) ? 0 : dockContent.dockCornerRadius
                        topLeftRadius: dockRoot.isHug ? ((dock.dockEffectivePosition === "bottom" || dock.dockEffectivePosition === "right") ? dockContent.dockCornerRadius : 0) : (dockRoot.isDynamicIsland ? 0 : dockContent.dockCornerRadius)
                        topRightRadius: dockRoot.isHug ? ((dock.dockEffectivePosition === "bottom" || dock.dockEffectivePosition === "left") ? dockContent.dockCornerRadius : 0) : (dockRoot.isDynamicIsland ? 0 : dockContent.dockCornerRadius)
                        bottomLeftRadius: dockRoot.isHug ? ((dock.dockEffectivePosition === "top" || dock.dockEffectivePosition === "right") ? dockContent.dockCornerRadius : 0) : (dockRoot.isDynamicIsland ? 0 : dockContent.dockCornerRadius)
                        bottomRightRadius: dockRoot.isHug ? ((dock.dockEffectivePosition === "top" || dock.dockEffectivePosition === "left") ? dockContent.dockCornerRadius : 0) : (dockRoot.isDynamicIsland ? 0 : dockContent.dockCornerRadius)

                        opacity: dockContent.islandsStyle ? 0.0 : 1.0

                        layer.enabled: !dockContent.islandsStyle && !dockRoot.isDynamicIsland && opacity > 0.01 && !Config.options.appearance.transparency.popups && !Config.options.appearance.transparency.enable
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: Qt.rgba(0, 0, 0, 0.35)
                            shadowHorizontalOffset: {
                                if (dock.dockEffectivePosition === "left") return 2;
                                if (dock.dockEffectivePosition === "right") return -2;
                                return 0;
                            }
                            shadowVerticalOffset: {
                                if (dock.dockEffectivePosition === "bottom") return -2;
                                if (dock.dockEffectivePosition === "top") return 2;
                                return 0;
                            }
                            shadowBlur: 1.0
                        }

                        anchors.horizontalCenter: (!dock.isVertical) ? parent.horizontalCenter : undefined
                        anchors.verticalCenter: dock.isVertical ? parent.verticalCenter : undefined

                        anchors.bottom: dock.dockEffectivePosition === "bottom" ? parent.bottom : undefined
                        anchors.bottomMargin: dock.dockEffectivePosition === "bottom" ? (dockRoot.reveal ? dockRoot.surfaceMargin : -(dockMouseArea.hoverRegion + 4)) : 0

                        anchors.top: dock.dockEffectivePosition === "top" ? parent.top : undefined
                        anchors.topMargin: dock.dockEffectivePosition === "top" ? (dockRoot.reveal ? dockRoot.surfaceMargin : -(dockMouseArea.hoverRegion + 4)) : 0

                        anchors.left: dock.dockEffectivePosition === "left" ? parent.left : undefined
                        anchors.leftMargin: dock.dockEffectivePosition === "left" ? (dockRoot.reveal ? dockRoot.surfaceMargin : -(dockMouseArea.hoverRegion + 4)) : 0

                        anchors.right: dock.dockEffectivePosition === "right" ? parent.right : undefined
                        anchors.rightMargin: dock.dockEffectivePosition === "right" ? (dockRoot.reveal ? dockRoot.surfaceMargin : -(dockMouseArea.hoverRegion + 4)) : 0

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockVisualBackground)
                        }
                        Behavior on anchors.bottomMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockVisualBackground) }
                        Behavior on anchors.topMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockVisualBackground) }
                        Behavior on anchors.leftMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockVisualBackground) }
                        Behavior on anchors.rightMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dockVisualBackground) }

                        Notch {
                            id: dynamicIslandNotch
                            visible: dockRoot.isDynamicIsland && !dockContent.islandsStyle && !dock.isVertical
                            anchors.fill: parent
                            bodyWidth: parent.width
                            bodyHeight: parent.height
                            disableBehaviors: true
                            topRadius: dockRoot.concaveCornerRadius
                            bottomRadius: Math.min(dockContent.dockCornerRadius, parent.height)
                            fillColor: Appearance.colors.colLayer0

                            transform: Scale {
                                xScale: 1
                                yScale: dock.dockEffectivePosition === "bottom" ? -1 : 1
                                origin.y: dynamicIslandNotch.height / 2
                            }
                        }

                        RoundCorner {
                            id: concaveCorner1
                            visible: dockRoot.isDynamicIsland && !dockContent.islandsStyle && dock.isVertical && opacity > 0.01
                            opacity: dockVisualBackground.opacity
                            implicitSize: Math.max(1, dockRoot.concaveCornerRadius)
                            color: dockVisualBackground.color
                            corner: {
                                if (dock.dockEffectivePosition === "left") return RoundCorner.CornerEnum.BottomLeft;
                                return RoundCorner.CornerEnum.BottomRight;
                            }
                            anchors {
                                bottom: (dock.dockEffectivePosition === "left" || dock.dockEffectivePosition === "right") ? parent.top : undefined
                                bottomMargin: (dock.dockEffectivePosition === "left" || dock.dockEffectivePosition === "right") ? -1 : 0
                                right: (dock.dockEffectivePosition === "right") ? parent.right : undefined
                                left: (dock.dockEffectivePosition === "left") ? parent.left : undefined
                            }
                        }

                        RoundCorner {
                            id: concaveCorner2
                            visible: dockRoot.isDynamicIsland && !dockContent.islandsStyle && dock.isVertical && opacity > 0.01
                            opacity: dockVisualBackground.opacity
                            implicitSize: Math.max(1, dockRoot.concaveCornerRadius)
                            color: dockVisualBackground.color
                            corner: {
                                if (dock.dockEffectivePosition === "left") return RoundCorner.CornerEnum.TopLeft;
                                return RoundCorner.CornerEnum.TopRight;
                            }
                            anchors {
                                top: (dock.dockEffectivePosition === "left" || dock.dockEffectivePosition === "right") ? parent.bottom : undefined
                                topMargin: (dock.dockEffectivePosition === "left" || dock.dockEffectivePosition === "right") ? -1 : 0
                                left: (dock.dockEffectivePosition === "left") ? parent.left : undefined
                                right: (dock.dockEffectivePosition === "right") ? parent.right : undefined
                            }
                        }
                    }

                    DropArea {
                        id: fileDropArea
                        anchors.fill: parent
                        z: 10
                        keys: ["text/uri-list"]

                        // We delay the re-enablement slightly after an internal drag ends
                        // to prevent the "exited" event from firing for the internal drag.
                        property bool blockDueToInternal: dockContent.dragging
                        onBlockDueToInternalChanged: {
                            if (!blockDueToInternal) {
                                reEnableTimer.restart()
                            } else {
                                enabled = false
                            }
                        }

                        Timer {
                            id: reEnableTimer
                            interval: 50
                            onTriggered: fileDropArea.enabled = true
                        }

                        onEntered: (drag) => {
                            if (!drag.hasUrls) return
                            //console.log("[Dock] External drag entered")
                            const url = drag.urls[0]?.toString() ?? ""
                            dockContent.externalDragIcon = dockContent.mimeIconFromPath(url)
                            dockContent.externalDragOver = true
                        }
                        onExited: {
                            //console.log("[Dock] External drag exited")
                            dockContent.externalDragIcon = ""
                            dockContent.externalDragOver = false
                        }
                        onDropped: (drop) => {
                            if (!drop.hasUrls) return
                            //console.log("[Dock] External drag dropped")
                            for (let i = 0; i < drop.urls.length; i++)
                                TaskbarApps.addPinnedFile(drop.urls[i])
                            drop.accept(Qt.CopyAction)
                            dockContent.externalDragIcon = ""
                            dockContent.externalDragOver = false
                        }
                    }

                    DockContent {
                        id: dockContent
                        anchors.fill: dockVisualBackground
                        anchors.leftMargin: (dockRoot.isDynamicIsland && !dock.isVertical) ? dockRoot.concaveCornerRadius : 0
                        anchors.rightMargin: (dockRoot.isDynamicIsland && !dock.isVertical) ? dockRoot.concaveCornerRadius : 0
                        anchors.topMargin: (dockRoot.isDynamicIsland && dock.isVertical) ? dockRoot.concaveCornerRadius : 0
                        anchors.bottomMargin: (dockRoot.isDynamicIsland && dock.isVertical) ? dockRoot.concaveCornerRadius : 0
                        z: 1
                        isPinned: dock.pinned
                        currentScreen: dockRoot.screen
                        dockRevealed: dockRoot.reveal
                        dockWindowVisible: dockRoot.visible
                        onTogglePinRequested: {
                            dock.pinned = !dock.pinned
                        }
                    }
                }
            }
        }
    }
}
