import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import "../"

PopupWindow {
    id: previewPopup

    property var dockRoot: null
    property var appTopLevel: null
    property var dockWindow: null
    property Item anchorItem: null
    property bool compactMode: false

    readonly property bool isVertical: dockRoot?.isVertical ?? false
    readonly property string dockPos: dockRoot?.dockPos ?? dock.dockEffectivePosition
    
    readonly property int maxPreviews: {
        if (compactMode)
            return 1
        if (!dockWindow || !dockRoot) return 1

        const spacing = 6
        const previewSize = isVertical ? dockRoot.maxWindowPreviewHeight + dockRoot.windowControlsHeight : dockRoot.maxWindowPreviewWidth

        const availableSpace = isVertical ? (dockWindow.height ?? 1080) - popupBackground.margins * 2 - popupBackground.padding * 2 : (dockWindow.width ?? 1920) - popupBackground.margins * 2 - popupBackground.padding * 2
        return Math.max(1, Math.floor((availableSpace + spacing) / (previewSize + spacing)))
    }

    property bool show: false
    readonly property bool shouldShow:
        !dockRoot.dragging &&
        !dockRoot.anyContextMenuOpen &&
        (backgroundHover.hovered || dockRoot.buttonHovered || dockRoot.popupIsResizing) &&
        (appTopLevel?.toplevels?.length > 0)

    // Opening waits out a small dwell — 70 ms, under the time a pointer
    // needs to cross one icon on purpose, over the time a sweep spends on
    // each icon it passes. The thing that costs during a sweep is everything
    // behind `show`: the surface map, the row rebuild, one live capture per
    // window. While the popup is closed those never run (see
    // onAppTopLevelChanged), so a fast pass through the dock costs nothing
    // here; a resting hover sees the popup at the next frame after the dwell.
    readonly property int openDwellMs: Math.round(70 * (Appearance.animMultiplier ?? 1))

    onShouldShowChanged: {
        if (shouldShow) {
            hideTimer.stop()
            showTimer.restart()
        } else if (dockRoot.anyContextMenuOpen) {
            showTimer.stop()
            hideTimer.stop()
            show = false
        } else {
            showTimer.stop()
            hideTimer.restart()
        }
    }

    Timer {
        id: showTimer
        interval: previewPopup.openDwellMs
        onTriggered: {
            if (previewPopup.shouldShow)
                previewPopup.show = true
        }
    }

    Timer {
        id: hideTimer
        interval: 150
        onTriggered: previewPopup.show = previewPopup.shouldShow
    }

    // The previewed app, which is not always the hovered one. Crossing icons
    // used to rebuild the preview row — and start a live capture per window —
    // for every icon the cursor passed over. The dwell below confirms the
    // target first: 80 ms is under the time a pointer rests on an icon once
    // the user has decided on one, so a deliberate move from app to app swaps
    // the row nearly as fast as the anchor follows it — an open popup showing
    // another app's windows is the worse failure mode. The row swaps under a
    // short dip so the change reads as one surface reloading, not a hard cut.
    property var displayedApp: null
    property real swapOpacity: 1.0
    readonly property int targetDwellMs: Math.round(80 * (Appearance.animMultiplier ?? 1))
    readonly property int swapFadeMs: Math.max(50, Math.round(Appearance.animation.elementMoveFast.duration * 0.25))
    readonly property int swapRiseMs: Math.max(70, Math.round(Appearance.animation.elementMoveFast.duration * 0.45))

    function commitDisplayedApp() {
        if (!previewPopup.appTopLevel)
            return
        previewPopup.displayedApp = previewPopup.appTopLevel
    }

    // Nothing on screen to crossfade: take the hovered app as it is.
    function adoptDisplayedAppNow() {
        targetSettleTimer.stop()
        targetSwap.stop()
        swapOpacity = 1.0
        commitDisplayedApp()
    }

    // Something is on screen: let the cursor rest on the new app first.
    function requestDisplayedAppSwap() {
        if (displayedApp === appTopLevel) {
            targetSettleTimer.stop()
            return
        }
        targetSettleTimer.restart()
    }

    function swapDisplayedApp() {
        if (displayedApp === appTopLevel)
            return
        targetSwap.restart()
    }

    // The closed popup does not track the hovered app at all: adoption is
    // what builds the row and arms the captures, and a sweep across the dock
    // while closed would otherwise rebuild that machinery on every icon
    // crossed. The popup adopts its target on the frame it opens (see
    // onShowChanged) — nothing is missed, because nothing was on screen.
    onAppTopLevelChanged: {
        if (visible)
            requestDisplayedAppSwap()
    }

    // Closing leaves nothing to crossfade: reset the dip and stop the
    // pending swap. The committed row is kept (displayedApp is untouched) so
    // a re-hover of the same app re-opens without rebuilding anything.
    onVisibleChanged: {
        if (visible)
            return
        targetSettleTimer.stop()
        targetSwap.stop()
        swapOpacity = 1.0
    }

    SequentialAnimation {
        id: targetSwap
        NumberAnimation {
            target: previewPopup
            property: "swapOpacity"
            to: 0.0
            duration: previewPopup.swapFadeMs
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        ScriptAction { script: previewPopup.commitDisplayedApp() }
        NumberAnimation {
            target: previewPopup
            property: "swapOpacity"
            to: 1.0
            duration: previewPopup.swapRiseMs
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // The dwell that confirms a target, so crossing icons never swaps the row
    // (nor starts a capture) more than once.
    Timer {
        id: targetSettleTimer
        interval: previewPopup.targetDwellMs
        onTriggered: previewPopup.swapDisplayedApp()
    }

    visible: show || popupBackground.opacity > 0
    color: "transparent"

    readonly property Item hoveredBtn: dockRoot?.lastHoveredButton ?? null
    readonly property real hoveredMagScale: (hoveredBtn && dockRoot) ? dockRoot._getSlotMagScale(hoveredBtn) : 1.0
    readonly property real hoveredScaleExtra: hoveredBtn ? (hoveredMagScale - 1.0) * (isVertical ? hoveredBtn.width : hoveredBtn.height) : 0
    // Keep the same small gap used by DockTooltip so both surfaces share the
    // exact same visual anchor above an app in the group popup.
    readonly property real compactAnchorGap: Appearance.sizes.elevationMargin

    function updateCompactAnchor() {
        if (!compactMode || !anchorItem || !dockWindow)
            return

        // PopupAnchor coordinate mapping is not reactive. Re-anchor after the
        // group popup has laid out the hovered delegate and after each hover
        // transition so the preview follows that delegate's real position.
        anchor.updateAnchor()
    }

    function requestCompactAnchor() {
        if (compactMode)
            compactAnchorTimer.restart()
    }

    Timer {
        id: compactAnchorTimer
        interval: 0
        repeat: false
        onTriggered: previewPopup.updateCompactAnchor()
    }

    onAnchorItemChanged: {
        if (compactMode)
            requestCompactAnchor()
    }

    onShowChanged: {
        if (!show)
            return
        adoptDisplayedAppNow()
        if (compactMode)
            requestCompactAnchor()
    }

    anchor {
        // Group previews live inside DockGroupPopup's PopupWindow. The app
        // tile itself is not guaranteed to expose a QsWindow attached
        // property, so anchor to the host window supplied by the group.
        window: compactMode && anchorItem
            ? (anchorItem.QsWindow?.window ?? dockWindow)
            : dockWindow
        adjustment: PopupAdjustment.None
        edges: Edges.Top | Edges.Left

        onAnchoring: {
            if (!compactMode || !anchorItem)
                return

            const gap = compactAnchorGap
            // PopupWindow's implicit size also contains the compact preview's
            // transparent control/margin budget. Anchor the visible surface
            // instead; otherwise that unused height moves the preview much
            // farther away from the hovered app than the tooltip.
            const surfaceX = popupBackground.x
            const surfaceY = popupBackground.y
            const surfaceWidth = popupBackground.width || popupBackground.implicitWidth
            const surfaceHeight = popupBackground.height || popupBackground.implicitHeight
            const top = anchorItem.mapToItem(null, anchorItem.width / 2, 0)
            const bottom = anchorItem.mapToItem(null, anchorItem.width / 2, anchorItem.height)

            if (dockPos === "bottom") {
                anchor.rect.x = Math.round(top.x - surfaceX - surfaceWidth / 2)
                anchor.rect.y = Math.round(top.y - surfaceY - surfaceHeight - gap)
            } else if (dockPos === "top") {
                anchor.rect.x = Math.round(bottom.x - surfaceX - surfaceWidth / 2)
                anchor.rect.y = Math.round(bottom.y + gap - surfaceY)
            } else if (dockPos === "left") {
                const right = anchorItem.mapToItem(null, anchorItem.width, anchorItem.height / 2)
                anchor.rect.x = Math.round(right.x + gap - surfaceX)
                anchor.rect.y = Math.round(right.y - surfaceY - surfaceHeight / 2)
            } else {
                const left = anchorItem.mapToItem(null, 0, anchorItem.height / 2)
                anchor.rect.x = Math.round(left.x - surfaceX - surfaceWidth - gap)
                anchor.rect.y = Math.round(left.y - surfaceY - surfaceHeight / 2)
            }
        }

        rect {
            // Compact positions are assigned by onAnchoring. Keeping these
            // bindings at zero provides a safe initial value before the host
            // window is mapped for the first time.
            x: compactMode ? 0 : dockPos === "left" ? ((dockWindow?.width ?? 0) - (dockWindow?.magCrossExtra ?? 0) + hoveredScaleExtra) : (dockPos === "right" ? Math.max(0, (dockWindow?.magCrossExtra ?? 0) - hoveredScaleExtra) : 0)
            y: compactMode ? 0 : dockPos === "bottom" ? Math.max(0, (dockWindow?.magCrossExtra ?? 0) - hoveredScaleExtra) : dockPos === "top" ? ((dockWindow?.height ?? 0) - (dockWindow?.magCrossExtra ?? 0) + hoveredScaleExtra) : 0
        }

        gravity: {
            if (compactMode)
                return Edges.Bottom | Edges.Right
            if (dockPos === "left") return Edges.Right | Edges.Bottom
            if (dockPos === "right") return Edges.Left | Edges.Bottom
            if (dockPos === "top") return Edges.Bottom | Edges.Right
            return Edges.Top | Edges.Right
        }
    }

    // The group popup can move when the dock loses magnification after
    // the pointer leaves the dock tile. Recalculate the preview against
    // the host window instead of leaving it at the old screen position.
    Connections {
        target: previewPopup.anchorItem
        function onScaleChanged() { previewPopup.requestCompactAnchor() }
        function onXChanged() { previewPopup.requestCompactAnchor() }
        function onYChanged() { previewPopup.requestCompactAnchor() }
        function onWidthChanged() { previewPopup.requestCompactAnchor() }
        function onHeightChanged() { previewPopup.requestCompactAnchor() }
    }

    // dockRoot is either a DockContent (no hoveredAppButton) or a DockGroupPopup,
    // so one of these handlers is always unknown on the current target.
    Connections {
        target: previewPopup.dockRoot
        ignoreUnknownSignals: true
        function onLastHoveredButtonChanged() { previewPopup.requestCompactAnchor() }
        function onHoveredAppButtonChanged() { previewPopup.requestCompactAnchor() }
    }

    // Only non-null when dockRoot is a DockGroupPopup: follow the parent dock's hover state.
    Connections {
        target: previewPopup.dockRoot?.dockContent ?? null
        function onButtonHoveredChanged() { previewPopup.requestCompactAnchor() }
        function onHoveredSlotChanged() { previewPopup.requestCompactAnchor() }
        function onLastHoveredButtonChanged() { previewPopup.requestCompactAnchor() }
    }

    readonly property int _extra: popupBackground.padding * 2 + popupBackground.margins * 2

    implicitWidth: compactMode
        ? dockRoot.maxWindowPreviewWidth + (isVertical ? dockRoot.windowControlsHeight : 0) + _extra
        : isVertical ? dockRoot.maxWindowPreviewWidth + dockRoot.windowControlsHeight + _extra - 25 : dockWindow?.width ?? 0
    implicitHeight: compactMode
        ? dockRoot.maxWindowPreviewHeight + (isVertical ? 0 : dockRoot.windowControlsHeight) + _extra + 5
        : isVertical ? dockWindow?.height ?? 0 : dockRoot.maxWindowPreviewHeight + dockRoot.windowControlsHeight + _extra + 5

    StyledRectangularShadow {
        target: popupBackground
        opacity: popupBackground.opacity
        visible: popupBackground.visible
    }

    Rectangle {
        id: popupBackground
        // Public handle for the offscreen tests: QML ids are context-scoped,
        // so the test cannot read them off the instance.
        objectName: "popupBackground"

        property real margins: 5
        property real padding: 6

        onImplicitWidthChanged: {
            dockRoot.popupIsResizing = true
            resizeTimer.restart()
            previewPopup.requestCompactAnchor()
        }
        onImplicitHeightChanged: {
            dockRoot.popupIsResizing = true
            resizeTimer.restart()
            previewPopup.requestCompactAnchor()
        }

        Timer {
            id: resizeTimer
            interval: 500
            onTriggered: dockRoot.popupIsResizing = false
        }

        readonly property real _clampedX: Math.max(margins, Math.min(dockRoot.hoveredButtonCenter.x - implicitWidth  / 2, parent.width  - implicitWidth  - margins))
        readonly property real _clampedY: Math.max(margins, Math.min(dockRoot.hoveredButtonCenter.y - implicitHeight / 2, parent.height - implicitHeight - margins))
        x: compactMode ? margins : isVertical ? (dockPos === "left" ? margins : parent.width - implicitWidth - margins) : _clampedX
        y: compactMode ? margins : isVertical ? _clampedY : (dockPos === "top" ? margins : parent.height - implicitHeight - margins)

        opacity: previewPopup.show ? 1 : 0
        scale: previewPopup.show ? 1.0 : 0.90
        transformOrigin: {
            if (dockPos === "top") return Item.Top
            if (dockPos === "left") return Item.Left
            if (dockPos === "right") return Item.Right
            return Item.Bottom
        }

        visible: (displayedApp?.toplevels?.length ?? 0) > 0
        clip: true
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
        radius: (Config.options?.dock?.widgetRadius ?? -1) >= 0 ? Config.options.dock.widgetRadius : Appearance.rounding.normal
        implicitHeight: previewRowLayout.implicitHeight + padding * 2
        implicitWidth: previewRowLayout.implicitWidth + padding * 2

        // Blur belongs to the transition, not to the open state: the layer
        // exists only while the radius is non-zero, because an open popup was
        // paying an offscreen pass per frame for a blur of zero. The radius
        // lives outside the effect so toggling the layer cannot restart it.
        property real blurRadius: previewPopup.show ? 0 : 16

        Behavior on blurRadius {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        layer.enabled: blurRadius > 0
        layer.effect: FastBlur {
            radius: popupBackground.blurRadius
        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(previewPopup)
        }

        HoverHandler {
            id: backgroundHover
        }

        GridLayout {
            id: previewRowLayout
            anchors {
                top: parent.top
                left: parent.left
                topMargin: popupBackground.padding
                leftMargin: popupBackground.padding
            }
            // Dips while the row swaps to another app, so the change is one
            // surface reloading instead of a hard cut between two windows.
            opacity: previewPopup.swapOpacity
            flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: 6
            rowSpacing: 6

            Repeater {
                model: ScriptModel { values: (previewPopup.displayedApp?.toplevels ?? []).slice(0, previewPopup.maxPreviews) }

                delegate: RippleButton {
                    id: windowButton
                    required property var modelData
                    padding: 0

                    onClicked: {
                        modelData?.activate()
                        dockRoot.buttonHovered = false
                        dockRoot.lastHoveredButton = null
                    }
                    middleClickAction: () => modelData?.close()

                    contentItem: ColumnLayout {
                        ButtonGroup {
                            contentWidth: parent.width - anchors.margins * 2

                            WrapperRectangle {
                                Layout.fillWidth: true
                                color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                radius: Appearance.rounding.small
                                margin: 5

                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    text: windowButton.modelData?.title ?? ""
                                    elide: Text.ElideRight
                                    color: Appearance.m3colors.m3onSurface
                                }
                            }

                            RippleButton {
                                id: closeButton
                                colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                implicitWidth: dockRoot.windowControlsHeight
                                implicitHeight: dockRoot.windowControlsHeight
                                buttonRadius: Appearance.rounding.full

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.m3colors.m3onSurface
                                }
                                onClicked: windowButton.modelData?.close()
                            }
                        }

                        // Fixed geometry, never the captured frame's: the first
                        // frame arrives hundreds of milliseconds later (or never,
                        // for a window the compositor refuses to export), and a
                        // popup that resizes to chase it keeps resizing its
                        // surface under the cursor while the dock magnifies.
                        Item {
                            id: previewSlot
                            objectName: "previewSlot"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            implicitWidth: dockRoot.maxWindowPreviewWidth
                            implicitHeight: dockRoot.maxWindowPreviewHeight

                            ScreencopyView {
                                id: screencopyView
                                anchors.centerIn: parent
                                captureSource: previewPopup.visible ? windowButton.modelData : null
                                live: true
                                paintCursor: true
                                // Fits the frame inside the slot; it is the
                                // display size, not the capture size.
                                constraintSize: Qt.size(previewSlot.implicitWidth, previewSlot.implicitHeight)
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: screencopyView.width
                                        height: screencopyView.height
                                        radius: Appearance.rounding.small
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
