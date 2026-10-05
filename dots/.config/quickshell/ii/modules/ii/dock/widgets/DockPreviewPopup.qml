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

    // ── What the card shows ────────────────────────────────────────────────
    // Two pages, front and back. The front shows the app on screen; a new
    // target is built on the BACK page, hidden, with its captures already
    // running, and replaces the front in one frame once every capture holds a
    // frame. The old row used to dip to nothing, commit, and rise into views
    // that had no frame yet - an empty card for as long as the compositor
    // took to export the first one, every time the pointer moved to another
    // app. Now the card never shows less than one complete set of frames.
    // No crossfade either: two half-transparent rows over the card read as
    // the content flickering, so the rows are swapped outright.
    //
    // The target still needs a short dwell before its captures start, so a
    // sweep across the dock does not open one capture per icon it crosses;
    // the card's position does not wait for it (see popupBackground.x).
    property bool frontIsA: true
    readonly property Item frontPage: frontIsA ? pageA : pageB
    readonly property Item backPage: frontIsA ? pageB : pageA
    readonly property var displayedApp: frontPage.app
    readonly property var pendingApp: backPage.app
    // The page whose size the card grows toward: the front, or the back once
    // it is about to replace it.
    readonly property Item layoutPage: backPage.ready ? backPage : frontPage
    // Kept for callers/tests written against the old dip: the card no longer
    // dims while it swaps.
    readonly property real swapOpacity: 1.0
    readonly property int targetDwellMs: Math.round(60 * (Appearance.animMultiplier ?? 1))
    // A window the compositor will not export never produces a frame; past
    // this the swap goes ahead with whatever the back page has.
    readonly property int frameWaitMs: 220

    // Nothing on screen to crossfade: take the hovered app as it is.
    function adoptDisplayedAppNow() {
        targetSettleTimer.stop()
        frameWaitTimer.stop()
        backPage.app = null
        frontPage.app = appTopLevel
    }

    // Something is on screen: let the cursor rest on the new app first.
    function requestDisplayedAppSwap() {
        // A target that moved on must not be committed by the wait that was
        // running for the previous one.
        frameWaitTimer.stop()
        if (displayedApp === appTopLevel) {
            targetSettleTimer.stop()
            backPage.app = null
            return
        }
        targetSettleTimer.restart()
    }

    function prepareSwap() {
        if (displayedApp === appTopLevel)
            return
        if (backPage.app !== appTopLevel)
            backPage.app = appTopLevel
        if (backPage.ready)
            commitSwap()
        else
            frameWaitTimer.restart()
    }

    function commitSwap() {
        frameWaitTimer.stop()
        if (!backPage.app || backPage.app === displayedApp || backPage.app !== appTopLevel)
            return
        const oldFront = frontPage
        frontIsA = !frontIsA
        // The page that left releases its captures at once.
        oldFront.app = null
    }

    // The closed popup does not track the hovered app at all: adoption is
    // what builds the row and arms the captures, and a sweep across the dock
    // while closed would otherwise rebuild that machinery on every icon
    // crossed. The popup adopts its target on the frame it opens (see
    // onShowChanged) — nothing is missed, because nothing was on screen.
    onAppTopLevelChanged: {
        if (active && show)
            requestDisplayedAppSwap()
    }

    // Closing stops any pending swap. The committed front page is kept so a
    // re-hover of the same app re-opens without rebuilding anything; the back
    // page is dropped with its captures.
    onActiveChanged: {
        if (active) {
            everShown = true
            return
        }
        targetSettleTimer.stop()
        frameWaitTimer.stop()
        backPage.app = null
    }

    // ── Open and close ─────────────────────────────────────────────────────
    // The dock menus' contract (DockContextMenuBase): `showProgress` carries
    // the shape — the card grows out of the dock edge on the expressive enter
    // clock — and `revealProgress` the opacity on the fast clock, so the card
    // is readable at once instead of fading in across its whole grow. Closing
    // takes both on one short exit clock, so nothing inside outlives the card.
    property real showProgress: 0
    property real revealProgress: 0
    readonly property real slideDistance: 14
    readonly property bool _motion: !(Appearance.reducedMotion ?? false)

    onShowChanged: {
        if (show) {
            closeMotion.stop()
            openMotion.restart()
            adoptDisplayedAppNow()
            if (compactMode)
                requestCompactAnchor()
        } else {
            openMotion.stop()
            closeMotion.restart()
        }
    }

    ParallelAnimation {
        id: openMotion
        NumberAnimation {
            target: previewPopup
            property: "showProgress"
            to: 1
            duration: previewPopup._motion ? Appearance.animation.elementMoveEnter.duration : 0
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: previewPopup
            property: "revealProgress"
            to: 1
            duration: previewPopup._motion ? Appearance.animation.elementMoveFast.duration : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    ParallelAnimation {
        id: closeMotion
        NumberAnimation {
            target: previewPopup
            property: "showProgress"
            to: 0
            duration: previewPopup._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: previewPopup
            property: "revealProgress"
            to: 0
            duration: previewPopup._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }

    // The dwell that confirms a target, so crossing icons never starts a
    // capture more than once.
    Timer {
        id: targetSettleTimer
        interval: previewPopup.targetDwellMs
        onTriggered: previewPopup.prepareSwap()
    }

    Timer {
        id: frameWaitTimer
        interval: previewPopup.frameWaitMs
        onTriggered: previewPopup.commitSwap()
    }

    Connections {
        target: previewPopup.backPage
        function onReadyChanged() {
            if (previewPopup.backPage.ready && previewPopup.backPage.app)
                previewPopup.commitSwap()
        }
    }

    // On screen (or on its way off): what captures, swaps and the dock's
    // "keep me revealed" follow. The WINDOW stays mapped once used: mapping a
    // popup surface costs 40–100 ms in the compositor, and paying it on every
    // open was the hitch at the start of each preview. Closed, the surface is
    // transparent and takes no input (empty mask).
    readonly property bool active: show || showProgress > 0 || revealProgress > 0
    // Mapped soon after the dock (its first map is the expensive frame) and
    // kept; never together with the dock window itself, whose surface has to
    // exist first (see DockTooltipHost). Group popups build theirs on demand.
    property bool everShown: false
    readonly property bool _parentShown: (dockWindow?.visible ?? false)
    on_ParentShownChanged: if (!_parentShown && !compactMode) everShown = false
    Timer {
        interval: 1500
        running: !previewPopup.compactMode && previewPopup._parentShown && !previewPopup.everShown
        onTriggered: previewPopup.everShown = true
    }
    visible: (everShown || active) && (compactMode || _parentShown)
    color: "transparent"
    readonly property Region cardRegion: Region { item: popupBackground }
    readonly property Region noRegion: Region {}
    mask: active ? cardRegion : noRegion

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
            // Static: the unmagnified icons' inner edge. Following the lens
            // here re-anchored the popup (a Wayland round trip) on every frame
            // the hovered icon grew; the card now lifts inside the surface
            // instead (popupBackground.lensLift), which has room for it.
            x: compactMode ? 0 : dockPos === "left" ? ((dockWindow?.width ?? 0) - (dockWindow?.magCrossExtra ?? 0)) : (dockPos === "right" ? (dockWindow?.magCrossExtra ?? 0) : 0)
            y: compactMode ? 0 : dockPos === "bottom" ? (dockWindow?.magCrossExtra ?? 0) : dockPos === "top" ? ((dockWindow?.height ?? 0) - (dockWindow?.magCrossExtra ?? 0)) : 0
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

    // Room for the card to lift over a magnified icon without moving the window.
    readonly property real _lensRoom: compactMode ? 0 : (dockWindow?.magCrossExtra ?? 0)
    implicitWidth: compactMode
        ? dockRoot.maxWindowPreviewWidth + (isVertical ? dockRoot.windowControlsHeight : 0) + _extra
        : isVertical ? dockRoot.maxWindowPreviewWidth + dockRoot.windowControlsHeight + _extra - 25 + _lensRoom : dockWindow?.width ?? 0
    implicitHeight: compactMode
        ? dockRoot.maxWindowPreviewHeight + (isVertical ? 0 : dockRoot.windowControlsHeight) + _extra + 5
        : isVertical ? dockWindow?.height ?? 0 : dockRoot.maxWindowPreviewHeight + dockRoot.windowControlsHeight + _extra + 5 + _lensRoom

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

        // The card travels with the pointer: its centre follows the hovered
        // icon on its own clock, independent of the row it is showing, so
        // moving across the dock reads as one card sliding along rather than
        // a card that jumps and then reloads. The clamp runs on the animated
        // centre, and the width animation never restarts the slide.
        property real followX: dockRoot.hoveredButtonCenter.x
        property real followY: dockRoot.hoveredButtonCenter.y
        readonly property bool sliding: previewPopup.show && previewPopup.showProgress > 0.98
        Behavior on followX {
            enabled: popupBackground.sliding
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(popupBackground)
        }
        Behavior on followY {
            enabled: popupBackground.sliding
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(popupBackground)
        }
        readonly property real _clampedX: Math.max(margins, Math.min(followX - implicitWidth  / 2, parent.width  - implicitWidth  - margins))
        readonly property real _clampedY: Math.max(margins, Math.min(followY - implicitHeight / 2, parent.height - implicitHeight - margins))
        // How far the hovered icon has grown toward the card: the card lifts
        // by that much inside the surface, frame by frame, at no window cost.
        readonly property real lensLift: compactMode ? 0 : previewPopup.hoveredScaleExtra
        x: compactMode ? margins : isVertical ? (dockPos === "left" ? margins + lensLift : parent.width - implicitWidth - margins - lensLift) : _clampedX
        y: compactMode ? margins : isVertical ? _clampedY : (dockPos === "top" ? margins + lensLift : parent.height - implicitHeight - margins - lensLift)

        opacity: previewPopup.revealProgress
        scale: 0.92 + 0.08 * previewPopup.showProgress
        transform: Translate {
            x: (dockPos === "left" ? -1 : dockPos === "right" ? 1 : 0) * previewPopup.slideDistance * (1 - previewPopup.showProgress)
            y: (dockPos === "top" ? -1 : dockPos === "bottom" ? 1 : 0) * previewPopup.slideDistance * (1 - previewPopup.showProgress)
        }
        transformOrigin: {
            if (dockPos === "top") return Item.Top
            if (dockPos === "left") return Item.Left
            if (dockPos === "right") return Item.Right
            return Item.Bottom
        }

        visible: (displayedApp?.toplevels?.length ?? 0) > 0
        clip: true
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
        readonly property bool opaqueSurface: color.a >= 0.999
        radius: (Config.options?.dock?.widgetRadius ?? -1) >= 0 ? Config.options.dock.widgetRadius : Appearance.rounding.normal
        implicitHeight: previewPopup.layoutPage.implicitHeight + padding * 2
        implicitWidth: previewPopup.layoutPage.implicitWidth + padding * 2

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        HoverHandler {
            id: backgroundHover
        }

        PreviewPage {
            id: pageA
            isFront: previewPopup.frontIsA
        }
        PreviewPage {
            id: pageB
            isFront: !previewPopup.frontIsA
        }
    }

    // One row of window previews for one app. Pages are centred in the card
    // so the crossfade between two rows of different widths stays centred
    // while the card's width eases between them.
    component PreviewPage: GridLayout {
        id: page
        property var app: null
        property bool isFront: false
        // Every capture on the page holds a frame (or there is nothing to
        // capture). Recomputed by the delegates as their frames land.
        property bool ready: false
        readonly property var windows: (page.app?.toplevels ?? []).slice(0, previewPopup.maxPreviews)

        function updateReady() {
            if (!page.app || page.windows.length === 0 || windowRepeater.count < page.windows.length) {
                page.ready = false
                return
            }
            for (let i = 0; i < windowRepeater.count; i++) {
                if (!windowRepeater.itemAt(i)?.frameReady) {
                    page.ready = false
                    return
                }
            }
            page.ready = true
        }
        onAppChanged: updateReady()

        anchors.top: parent.top
        anchors.topMargin: popupBackground.padding
        anchors.horizontalCenter: parent.horizontalCenter
        // The back page builds and captures at opacity 0 until the swap; the
        // renderer skips a transparent subtree, so it costs no drawing.
        visible: page.app !== null
        opacity: page.isFront ? 1 : 0
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: 6
        rowSpacing: 6

        Repeater {
            id: windowRepeater
            model: ScriptModel { values: page.windows }
            onCountChanged: page.updateReady()

            delegate: RippleButton {
                id: windowButton
                required property var modelData
                readonly property bool frameReady: screencopyView.hasContent
                onFrameReadyChanged: page.updateReady()
                padding: 0
                enabled: page.isFront

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
                    // frame arrives later (or never, for a window the
                    // compositor refuses to export), and a popup that resizes
                    // to chase it keeps resizing its surface under the cursor
                    // while the dock magnifies.
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
                            captureSource: previewPopup.active ? windowButton.modelData : null
                            live: true
                            paintCursor: true
                            // Fits the frame inside the slot; it is the
                            // display size, not the capture size.
                            constraintSize: Qt.size(previewSlot.implicitWidth, previewSlot.implicitHeight)
                            // A translucent card cannot hide corners under
                            // pieces of its own colour; only then pay for a
                            // mask pass.
                            layer.enabled: !popupBackground.opaqueSurface
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: screencopyView.width
                                    height: screencopyView.height
                                    radius: Appearance.rounding.small
                                }
                            }
                        }

                        // Rounds the live frame with four corner pieces in the
                        // card's colour instead of re-rendering it offscreen
                        // through a mask on every captured frame.
                        CornerCutouts {
                            visible: popupBackground.opaqueSurface && screencopyView.hasContent
                            anchors.fill: screencopyView
                            radius: Appearance.rounding.small
                            color: popupBackground.color
                        }
                    }
                }
            }
        }
    }
}
