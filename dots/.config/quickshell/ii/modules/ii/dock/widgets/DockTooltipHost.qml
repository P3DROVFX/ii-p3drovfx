import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets

/**
 * The dock's one tooltip. Every item used to own a PopupWindow of its own:
 * sweeping the dock faded one native window out and the next one in at every
 * icon, each mapping its surface on the way (40–100 ms in the compositor), and
 * each re-anchored — a Wayland round trip — on every frame the lens moved it.
 *
 * Here one surface stays mapped while the dock is: it covers the dock window
 * plus a band on its inner side, takes no input (empty mask) and is anchored
 * once. The bubble moves INSIDE it: following an item is an item position, not
 * a window move. Items ask for it through DockTooltip (request/release).
 *
 * Motion, on two scalars like the dock's menus:
 *  - appear: `grow` (scale 0.9→1 + a few px out of the dock edge, expressive
 *    enter) and `reveal` (opacity, fast) — readable at once;
 *  - switch: the bubble slides from where it is to the new item (an offset
 *    that decays to zero, so it keeps tracking the live, magnified item while
 *    it travels), its width eases, and the text crosses over: the old label
 *    leaves against the direction of travel while the new one comes in;
 *  - hide: a short grace first, so moving to the next item slides instead of
 *    fading out and back in; then one quick exit.
 */
PopupWindow {
    id: host

    property Item dockContent: null
    readonly property string pos: host.dockContent?.dockPos ?? "bottom"
    readonly property bool vertical: host.pos === "left" || host.pos === "right"
    property var dockWindow: host.dockContent?.QsWindow?.window ?? null
    readonly property real windowW: host.dockWindow?.width ?? 0
    readonly property real windowH: host.dockWindow?.height ?? 0

    // Room on the dock's inner side for the bubble.
    readonly property real zone: 72
    readonly property real gap: 8

    // ── Requests ───────────────────────────────────────────────────────────
    property var request: null          // the DockTooltip being shown
    property Item target: null          // the item the bubble points at
    property string label: ""
    property bool wanted: false         // a request is active (after dwell)

    function requestShow(spec) {
        if (!spec || !spec.parentItem)
            return;
        graceTimer.stop();
        host.request = spec;
        // Already up (or still on its way out): no dwell, slide over to it.
        if (host.reveal > 0.01 || host.wanted) {
            host._retarget(spec);
            return;
        }
        dwellTimer.restart();
    }

    function release(spec) {
        if (host.request !== spec)
            return;
        host.request = null;
        dwellTimer.stop();
        if (host.wanted)
            graceTimer.restart();
    }

    function updateText(spec) {
        if (host.request === spec && host.wanted && spec.text !== host.label)
            host._swapText(spec.text, 0);
    }

    // The first tooltip of a hover waits a beat, so a fast pass over the dock
    // shows nothing; once one is up, the next item gets it at once.
    Timer {
        id: dwellTimer
        interval: Math.round(70 * (Appearance.animMultiplier ?? 1))
        onTriggered: {
            if (host.request)
                host._retarget(host.request);
        }
    }
    // Between two items the pointer leaves one before it enters the next.
    Timer {
        id: graceTimer
        interval: 110
        onTriggered: {
            if (!host.request)
                host._hide();
        }
    }

    function _retarget(spec) {
        const item = spec.parentItem;
        const fresh = !host.wanted && host.reveal < 0.01;
        host.wanted = true;
        if (fresh) {
            // Appear where the item is: no slide, the text is simply there.
            host.target = item;
            slideAnimation.stop();
            host.slideOffset = 0;
            textSwap.stop();
            host.label = spec.text;
            host.outgoing = "";
            host.swapProgress = 1;
            host._updatePlacement();
            host._playEnter(true);
            return;
        }
        if (item !== host.target) {
            // Where the bubble is DRAWN right now (mid-slide included), read
            // before anything moves.
            host._updatePlacement();
            const before = host.pointMain + host.slideOffset;
            host.target = item;
            // The new base has to land in the same frame as the new offset:
            // left to the next tick, one frame drew the old base plus the new
            // offset — the bubble flashed a whole item-distance away.
            host._updatePlacement();
            const after = host.pointMain;
            const direction = Math.sign(after - before);
            // The bubble stays where it is on screen and glides over.
            slideAnimation.stop();
            host.slideOffset = before - after;
            slideAnimation.restart();
            if (spec.text !== host.label)
                host._swapText(spec.text, direction);
        } else if (spec.text !== host.label) {
            host._swapText(spec.text, 0);
        }
        // Coming back while it was leaving: turn around from where it is.
        if (exitMotion.running || host.reveal < 1)
            host._playEnter(false);
    }

    function _hide() {
        host.wanted = false;
        enterMotion.stop();
        exitMotion.restart();
    }

    // ── Geometry ───────────────────────────────────────────────────────────
    // The surface: the dock window grown by `zone` on the inner side.
    readonly property real originX: host.pos === "right" ? -host.zone : 0
    readonly property real originY: host.pos === "bottom" ? -host.zone : 0

    anchor.window: host.dockWindow
    anchor.rect.x: host.originX
    anchor.rect.y: host.originY
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.None

    implicitWidth: Math.max(1, host.windowW + (host.vertical ? host.zone : 0))
    implicitHeight: Math.max(1, host.windowH + (host.vertical ? 0 : host.zone))
    color: "transparent"
    // Never in the way of a click: the bubble only informs.
    mask: Region {}
    // Mapped soon after the dock and kept: the first map of a popup surface is
    // the one expensive frame (~100 ms measured), so it is paid while nothing
    // is being hovered. Never in the same breath as the dock window itself —
    // a popup mapped before its parent surface is up loses its surface
    // (VK_ERROR_SURFACE_LOST) and takes the process down.
    readonly property bool parentShown: host.dockWindow !== null && (host.dockWindow.visible ?? false)
    property bool armed: false
    onParentShownChanged: if (!host.parentShown) host.armed = false
    Timer {
        interval: 1500
        running: host.parentShown && !host.armed
        onTriggered: host.armed = true
    }
    visible: host.parentShown && (host.armed || host.wanted)

    // Where the bubble points, in surface coordinates: the item's centre on
    // the main axis, its inner edge (magnified as drawn) on the cross axis.
    property real pointMain: 0
    property real pointCross: 0
    function _updatePlacement() {
        const item = host.target;
        if (!item)
            return;
        const a = item.mapToItem(null, 0, 0);
        const b = item.mapToItem(null, item.width, item.height);
        const left = Math.min(a.x, b.x) - host.originX;
        const right = Math.max(a.x, b.x) - host.originX;
        const top = Math.min(a.y, b.y) - host.originY;
        const bottom = Math.max(a.y, b.y) - host.originY;
        if (host.vertical) {
            host.pointMain = (top + bottom) / 2;
            host.pointCross = host.pos === "left" ? right : left;
        } else {
            host.pointMain = (left + right) / 2;
            host.pointCross = host.pos === "bottom" ? top : bottom;
        }
    }
    // mapToItem() reads positions the binding engine cannot see (the lens
    // moves items by their wrappers' translations), so the placement is read
    // once per frame while the bubble is on screen — one map, not a window
    // move.
    FrameAnimation {
        running: host.visible && (host.wanted || host.reveal > 0)
        onTriggered: host._updatePlacement()
    }

    // ── Motion state ───────────────────────────────────────────────────────
    property real grow: 0
    property real reveal: 0
    property real slideOffset: 0
    readonly property bool _motion: !Appearance.reducedMotion

    ParallelAnimation {
        id: enterMotion
        NumberAnimation {
            target: host
            property: "grow"
            to: 1
            duration: host._motion ? Appearance.animation.elementMoveEnter.duration : 0
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: host
            property: "reveal"
            to: 1
            duration: host._motion ? Appearance.animation.elementMoveFast.duration : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    ParallelAnimation {
        id: exitMotion
        NumberAnimation {
            target: host
            property: "grow"
            to: 0.6
            duration: host._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: host
            property: "reveal"
            to: 0
            duration: host._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        onFinished: {
            if (!host.wanted) {
                host.target = null;
                host.slideOffset = 0;
            }
        }
    }
    function _playEnter(fromStart) {
        exitMotion.stop();
        if (fromStart) {
            host.grow = 0;
            host.reveal = 0;
        }
        enterMotion.restart();
    }

    NumberAnimation {
        id: slideAnimation
        target: host
        property: "slideOffset"
        to: 0
        duration: host._motion ? Appearance.animation.elementMove.duration : 0
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    // Text cross-over: the incoming label rises from the side the bubble is
    // travelling toward, the outgoing one leaves the other way.
    property string outgoing: ""
    property real swapProgress: 1
    property int swapDirection: 0
    function _swapText(text, direction) {
        host.outgoing = host.label;
        host.label = text;
        host.swapDirection = direction;
        textSwap.stop();
        host.swapProgress = 0;
        textSwap.start();
    }
    NumberAnimation {
        id: textSwap
        target: host
        property: "swapProgress"
        from: 0
        to: 1
        duration: host._motion ? Appearance.animation.elementMove.duration : 0
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        onFinished: host.outgoing = ""
    }

    // ── The bubble ─────────────────────────────────────────────────────────
    TextMetrics {
        id: incomingMetrics
        font: incomingText.font
        text: host.label
    }
    TextMetrics {
        id: outgoingMetrics
        font: incomingText.font
        text: host.outgoing
    }

    // The surface's content, one item so the whole of it can be grabbed in
    // tests (a window's contentItem cannot).
    Item {
        id: stage
        objectName: "tooltipStage"
        anchors.fill: parent

    Rectangle {
        id: bubble
        objectName: "tooltipBubble"
        readonly property real padH: 12
        readonly property real padV: 6
        // Eases from the old label's width to the new one's with the swap.
        readonly property real targetWidth: Math.ceil(incomingMetrics.advanceWidth) + bubble.padH * 2
        readonly property real fromWidth: host.outgoing.length > 0 ? Math.ceil(outgoingMetrics.advanceWidth) + bubble.padH * 2 : bubble.targetWidth
        width: Math.round(bubble.fromWidth + (bubble.targetWidth - bubble.fromWidth) * Math.min(1, host.swapProgress * 1.25))
        height: Math.ceil(incomingText.implicitHeight) + bubble.padV * 2
        radius: Math.min(height / 2, Appearance.rounding.small)
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
        visible: host.reveal > 0.001 && host.target !== null

        readonly property real main: host.pointMain + host.slideOffset
        // Out of the dock edge while it grows in.
        readonly property real lift: (1 - host.grow) * 6
        x: host.vertical
            ? (host.pos === "left" ? host.pointCross + host.gap - bubble.lift : host.pointCross - host.gap - bubble.width + bubble.lift)
            : Math.round(Math.max(4, Math.min(host.width - bubble.width - 4, bubble.main - bubble.width / 2)))
        y: host.vertical
            ? Math.round(Math.max(4, Math.min(host.height - bubble.height - 4, bubble.main - bubble.height / 2)))
            : (host.pos === "bottom" ? host.pointCross - host.gap - bubble.height + bubble.lift : host.pointCross + host.gap - bubble.lift)

        opacity: host.reveal
        scale: 0.9 + 0.1 * host.grow
        transformOrigin: host.pos === "top" ? Item.Top
            : host.pos === "left" ? Item.Left
            : host.pos === "right" ? Item.Right
            : Item.Bottom
        clip: true

        // The incoming label.
        StyledText {
            id: incomingText
            anchors.verticalCenter: parent.verticalCenter
            x: bubble.padH + host.swapDirection * 10 * (1 - host.swapProgress)
            text: host.label
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
            opacity: host.outgoing.length > 0 ? Math.min(1, Math.max(0, host.swapProgress * 1.6 - 0.3)) : 1
        }
        // The outgoing one, leaving against the travel.
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: host.outgoing.length > 0
            x: bubble.padH - host.swapDirection * 10 * host.swapProgress
            text: host.outgoing
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
            opacity: Math.max(0, 1 - host.swapProgress * 2)
        }
    }
    }
}
