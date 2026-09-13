pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * GNOME-style workspace strip for the Tablet App Drawer.
 *
 * Sits between the category chips and the app grid: one card per workspace, with the
 * wallpaper behind live screencopies of the windows laid out the way Hyprland tiles them.
 *
 * Which workspaces: every id from the first to the last one this monitor uses, plus the
 * next free one — the way GNOME always keeps one empty workspace at the end. Hyprland
 * destroys a workspace the moment its last window leaves, so listing only the ones that
 * exist made a card vanish mid-drag and shifted every card after it one slot left, which
 * read as "the workspace I dropped on disappeared".
 *
 * Input, the same for mouse and touch where it can be:
 * - Tap a window: focus it and close the drawer. Middle click or its × closes it.
 * - Tap a workspace: switch to it. Tapping the one already shown enters it.
 * - Mouse: dragging a window moves it at once. Onto another workspace moves it there,
 *   onto a window of the same workspace swaps the two, a floating one follows the drop.
 * - Touch: a horizontal swipe scrolls the strip even when it starts on a window, since
 *   windows cover most of every card; a long press or a vertical pull picks the window up.
 * - Wheel, the side buttons, and PageUp/PageDown in the search field (see
 *   TabletAppDrawerContent) move through workspaces.
 */
Item {
    id: root

    property var screen: null
    property bool drawerVisible: true
    /// How far the strip may run past its own box on each side. The drawer's content has an
    /// outer margin; spending it here lets cards slide under a fade at the screen edge
    /// instead of being cut by a hard line in the middle of the margin.
    property real horizontalBleed: 0

    signal workspaceSelected(int workspaceId)
    signal windowSelected(string windowAddress)

    // ── Monitor geometry ──────────────────────────────────────────────────────
    readonly property HyprlandMonitor monitor: screen
        ? Hyprland.monitorFor(screen)
        : (Hyprland.focusedMonitor ?? (Hyprland.monitors.length > 0 ? Hyprland.monitors[0] : null))

    readonly property var monitorData: {
        const monList = HyprlandData.monitors ?? [];
        return monList.find(m => m && (m.id === root.monitor?.id || m.name === root.monitor?.name)) ?? null;
    }

    readonly property real monitorScale: (root.monitorData?.scale > 0) ? root.monitorData.scale : 1
    readonly property bool monitorRotated: ((root.monitorData?.transform ?? 0) % 2) === 1
    /// hyprctl reports the mode in physical pixels, window geometry in logical ones.
    readonly property real logicalWidth: {
        const w = root.monitorRotated ? root.monitorData?.height : root.monitorData?.width;
        return w > 0 ? w / root.monitorScale : (root.screen?.width > 0 ? root.screen.width : 1920);
    }
    readonly property real logicalHeight: {
        const h = root.monitorRotated ? root.monitorData?.width : root.monitorData?.height;
        return h > 0 ? h / root.monitorScale : (root.screen?.height > 0 ? root.screen.height : 1080);
    }
    /// [left, top, right, bottom]: the bar's exclusive zone. Cards show the work area only,
    /// or every card carried an empty wallpaper stripe where the bar sits.
    readonly property var reserved: root.monitorData?.reserved ?? [0, 0, 0, 0]
    readonly property real workX: (root.monitorData?.x ?? 0) + (root.reserved[0] ?? 0)
    readonly property real workY: (root.monitorData?.y ?? 0) + (root.reserved[1] ?? 0)
    readonly property real workWidth: Math.max(1, root.logicalWidth - (root.reserved[0] ?? 0) - (root.reserved[2] ?? 0))
    readonly property real workHeight: Math.max(1, root.logicalHeight - (root.reserved[1] ?? 0) - (root.reserved[3] ?? 0))

    readonly property int activeWorkspaceId: root.monitor?.activeWorkspace?.id ?? 1

    // ── Sizing ────────────────────────────────────────────────────────────────
    /// Room above the cards for the active ring and for a close button that overhangs a
    /// window on the top edge, both of which the edge-fade layer would otherwise clip.
    readonly property real cardTopMargin: 12
    readonly property real captionHeight: 34
    readonly property real cardHeight: Math.max(110, Math.min(250, Math.round((root.screen?.height ?? 1080) * 0.19)))
    readonly property real cardWidth: Math.round(root.cardHeight * root.workWidth / root.workHeight)
    readonly property real cardSpacing: Math.max(18, Math.round(root.cardWidth * 0.07))
    readonly property real cardStep: root.cardWidth + root.cardSpacing
    readonly property real cardRadius: Appearance.rounding.normal
    readonly property real targetHeight: root.cardTopMargin + root.cardHeight + root.captionHeight
    readonly property real edgeFadeSize: Math.max(48, Math.min(120, root.horizontalBleed + 40))

    /// Set by the last press: touch shows every close button, since there is no hover.
    property bool touchMode: false

    // ── Drag state ────────────────────────────────────────────────────────────
    property bool pressedOnWindow: false
    property bool isDraggingWindow: false
    property int draggingFromWorkspace: -1
    property string draggingFromWindowAddress: ""
    property int draggingTargetWorkspace: -1
    property string draggingTargetWindowAddress: ""
    property var draggedWindowData: null
    property var draggedToplevel: null
    property real draggedWidth: 0
    property real draggedHeight: 0
    /// Where inside the window it was grabbed, so it does not jump to centre on the finger.
    property real dragGrabX: 0
    property real dragGrabY: 0
    property real dragCurrentX: 0
    property real dragCurrentY: 0

    readonly property var workspaceList: {
        const monitorName = root.monitor?.name ?? "";
        const ours = new Set();
        const elsewhere = new Set();
        const all = HyprlandData.workspaces ?? [];
        for (let i = 0; i < all.length; i++) {
            const ws = all[i];
            if (!ws || ws.id < 1 || ws.id > 99)
                continue;
            if (!monitorName || ws.monitor === monitorName)
                ours.add(ws.id);
            else
                elsewhere.add(ws.id);
        }
        if (root.activeWorkspaceId >= 1 && root.activeWorkspaceId <= 99)
            ours.add(root.activeWorkspaceId);
        // Keep the card being dragged from, even if Hyprland just destroyed it.
        if (root.isDraggingWindow && root.draggingFromWorkspace >= 1)
            ours.add(root.draggingFromWorkspace);
        if (ours.size === 0)
            ours.add(1);

        const ids = Array.from(ours);
        const last = Math.max(...ids);
        const first = elsewhere.size === 0 ? 1 : Math.min(...ids);
        const list = [];
        for (let id = first; id <= last; id++) {
            if (!elsewhere.has(id))
                list.push(id);
        }
        let next = last + 1;
        while (next <= 99 && elsewhere.has(next))
            next++;
        if (next <= 99)
            list.push(next);
        return list;
    }

    implicitHeight: root.targetHeight

    // ── Helpers ───────────────────────────────────────────────────────────────
    function cardForWorkspace(wsId) {
        for (let i = 0; i < workspaceRepeater.count; i++) {
            const item = workspaceRepeater.itemAt(i);
            if (item && item.wsId === wsId)
                return item;
        }
        return null;
    }

    function hitTestWorkspace(rootX, rootY) {
        const local = workspaceRow.mapFromItem(root, rootX, rootY);
        const slackX = root.cardSpacing / 2;
        for (let i = 0; i < workspaceRepeater.count; i++) {
            const item = workspaceRepeater.itemAt(i);
            // Generous vertically: the caption and the space above count as the card.
            if (item && local.x >= item.x - slackX && local.x <= item.x + item.width + slackX
                    && local.y >= -root.cardTopMargin - 40 && local.y <= item.height + root.captionHeight + 40)
                return item.wsId;
        }
        return -1;
    }

    function hitTestWindow(rootX, rootY, cardItem) {
        if (!cardItem)
            return null;
        const local = cardItem.windowsLayer.mapFromItem(root, rootX, rootY);
        let best = null;
        const repeater = cardItem.windowRepeater;
        for (let j = 0; j < repeater.count; j++) {
            const w = repeater.itemAt(j);
            if (w && local.x >= w.x && local.x <= w.x + w.width && local.y >= w.y && local.y <= w.y + w.height
                    && (!best || w.z >= best.z))
                best = w;
        }
        return best;
    }

    function updateDragTargets() {
        const targetWs = root.hitTestWorkspace(root.dragCurrentX, root.dragCurrentY);
        root.draggingTargetWorkspace = targetWs;
        const win = targetWs === -1 ? null
            : root.hitTestWindow(root.dragCurrentX, root.dragCurrentY, root.cardForWorkspace(targetWs));
        const addr = win?.winData?.address ?? "";
        // Swapping only means something between tiled windows of the same workspace;
        // dropped anywhere else, the window just goes to that workspace.
        const swappable = addr && addr !== root.draggingFromWindowAddress
            && targetWs === root.draggingFromWorkspace
            && !win.winData.floating && !root.draggedWindowData?.floating;
        root.draggingTargetWindowAddress = swappable ? addr : "";
    }

    function beginWindowDrag(winItem, grabX, grabY) {
        root.draggingFromWorkspace = winItem.wsId;
        root.draggingFromWindowAddress = winItem.winData.address;
        root.draggedWindowData = winItem.winData;
        root.draggedToplevel = winItem.toplevel;
        root.draggedWidth = winItem.width;
        root.draggedHeight = winItem.height;
        root.dragGrabX = grabX;
        root.dragGrabY = grabY;
        root.isDraggingWindow = true;
        root.updateDragTargets();
    }

    function finishWindowDrag(winItem) {
        const targetWs = root.draggingTargetWorkspace;
        const targetAddr = root.draggingTargetWindowAddress;
        const fromAddr = root.draggingFromWindowAddress;
        const fromWs = root.draggingFromWorkspace;

        if (targetWs !== -1 && fromAddr) {
            if (targetAddr) {
                Hyprland.dispatch(`hl.dsp.window.swap({ target = "address:${targetAddr}", window = "address:${fromAddr}" })`);
            } else if (targetWs !== fromWs) {
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetWs}, follow = false, window = "address:${fromAddr}" })`);
            } else if (root.draggedWindowData?.floating) {
                const card = root.cardForWorkspace(targetWs);
                if (card) {
                    const local = card.mapFromItem(root, root.dragCurrentX - root.dragGrabX, root.dragCurrentY - root.dragGrabY);
                    const px = Math.max(0, Math.min(1, local.x / card.width));
                    const py = Math.max(0, Math.min(1, local.y / card.height));
                    Hyprland.dispatch(`hl.dsp.window.move({ x = "${Math.round(px * root.workWidth + (root.reserved[0] ?? 0))}", y = "${Math.round(py * root.workHeight + (root.reserved[1] ?? 0))}", window = "address:${fromAddr}" })`);
                }
            }
        }
        root.resetDrag();
        HyprlandData.updateWindowList();
    }

    function resetDrag() {
        root.isDraggingWindow = false;
        root.pressedOnWindow = false;
        root.draggingFromWorkspace = -1;
        root.draggingFromWindowAddress = "";
        root.draggingTargetWorkspace = -1;
        root.draggingTargetWindowAddress = "";
        root.draggedWindowData = null;
        root.draggedToplevel = null;
    }

    function closeWindow(address) {
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${address}" })`);
    }

    readonly property real maxContentX: Math.max(0, flickable.contentWidth - flickable.width)

    function scrollTo(x, animated) {
        const target = Math.max(0, Math.min(root.maxContentX, x));
        scrollAnim.stop();
        if (animated === false) {
            flickable.contentX = target;
            return;
        }
        scrollAnim.to = target;
        scrollAnim.start();
    }

    /// A page at a time, keeping one card from the old page in view for continuity.
    function scrollByPage(direction) {
        const visibleCards = Math.max(1, Math.floor((flickable.width - 2 * root.edgeFadeSize) / root.cardStep));
        const base = scrollAnim.running ? scrollAnim.to : flickable.contentX;
        root.scrollTo(base + direction * Math.max(1, visibleCards - 1) * root.cardStep);
    }

    function centerWorkspace(wsId, animated) {
        const index = root.workspaceList.indexOf(wsId);
        if (index === -1 || root.maxContentX <= 0)
            return;
        const cardCenter = workspaceRow.x + index * root.cardStep + root.cardWidth / 2;
        root.scrollTo(cardCenter - flickable.width / 2, animated);
    }

    /// PageUp/PageDown from the drawer: step to the neighbouring workspace.
    function focusAdjacentWorkspace(delta) {
        const list = root.workspaceList;
        const index = list.indexOf(root.activeWorkspaceId);
        const next = list[Math.max(0, Math.min(list.length - 1, (index === -1 ? 0 : index) + delta))];
        if (next !== undefined && next !== root.activeWorkspaceId)
            root.workspaceSelected(next);
    }

    onActiveWorkspaceIdChanged: Qt.callLater(() => root.centerWorkspace(root.activeWorkspaceId, true))
    onDrawerVisibleChanged: {
        if (root.drawerVisible)
            Qt.callLater(() => root.centerWorkspace(root.activeWorkspaceId, false));
        else
            root.resetDrag();
    }
    onWidthChanged: Qt.callLater(() => root.centerWorkspace(root.activeWorkspaceId, false))

    NumberAnimation {
        id: scrollAnim
        target: flickable
        property: "contentX"
        duration: 320
        easing.type: Easing.OutCubic
    }

    // Scrolls while a window is held near either edge, faster the closer it gets.
    Timer {
        interval: 16
        repeat: true
        running: root.isDraggingWindow
        onTriggered: {
            const leftEdge = -root.horizontalBleed + root.edgeFadeSize;
            const rightEdge = root.width + root.horizontalBleed - root.edgeFadeSize;
            let delta = 0;
            if (root.dragCurrentX < leftEdge)
                delta = -Math.min(1, (leftEdge - root.dragCurrentX) / root.edgeFadeSize) * 14;
            else if (root.dragCurrentX > rightEdge)
                delta = Math.min(1, (root.dragCurrentX - rightEdge) / root.edgeFadeSize) * 14;
            if (delta !== 0) {
                scrollAnim.stop();
                flickable.contentX = Math.max(0, Math.min(root.maxContentX, flickable.contentX + delta));
                root.updateDragTargets();
            }
        }
    }

    // ── Strip ─────────────────────────────────────────────────────────────────
    Flickable {
        id: flickable
        anchors {
            fill: parent
            leftMargin: -root.horizontalBleed
            rightMargin: -root.horizontalBleed
        }
        contentWidth: Math.max(flickable.width, workspaceRow.width + 2 * (root.horizontalBleed + root.cardSpacing))
        contentHeight: flickable.height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.pressedOnWindow && !root.isDraggingWindow && root.maxContentX > 0
        onMovementStarted: scrollAnim.stop()

        readonly property real leftFade: Math.max(0, Math.min(1, flickable.contentX / 40))
        readonly property real rightFade: Math.max(0, Math.min(1, (root.maxContentX - flickable.contentX) / 40))

        // Fades the strip's own alpha rather than painting a colour band: the drawer sits
        // on a blurred screencopy, so no colour would match what is behind it.
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: Math.max(1, flickable.width)
                height: Math.max(1, flickable.height)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1 - flickable.leftFade) }
                    GradientStop { position: Math.min(0.45, root.edgeFadeSize / Math.max(1, flickable.width)); color: "white" }
                    GradientStop { position: Math.max(0.55, 1 - root.edgeFadeSize / Math.max(1, flickable.width)); color: "white" }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 1 - flickable.rightFade) }
                }
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const pixel = event.pixelDelta.x !== 0 ? -event.pixelDelta.x : -event.pixelDelta.y;
                if (pixel !== 0) {
                    scrollAnim.stop();
                    flickable.contentX = Math.max(0, Math.min(root.maxContentX, flickable.contentX + pixel));
                    return;
                }
                const angle = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                if (angle !== 0) {
                    const base = scrollAnim.running ? scrollAnim.to : flickable.contentX;
                    root.scrollTo(base - angle / 120 * root.cardStep * 0.5);
                }
            }
        }

        Row {
            id: workspaceRow
            x: Math.round((flickable.contentWidth - workspaceRow.width) / 2)
            y: root.cardTopMargin
            spacing: root.cardSpacing

            Repeater {
                id: workspaceRepeater
                // A ScriptModel diffs the ids, so a workspace appearing or vanishing adds or
                // removes one card instead of rebuilding every card and its screencopies.
                model: ScriptModel {
                    values: root.workspaceList
                }

                delegate: Item {
                    id: card
                    required property int modelData
                    readonly property int wsId: card.modelData
                    readonly property bool isActive: card.wsId === root.activeWorkspaceId
                    readonly property bool isDropTarget: root.isDraggingWindow
                        && root.draggingTargetWorkspace === card.wsId
                        && card.wsId !== root.draggingFromWorkspace
                    readonly property bool isEmpty: windowRepeater.count === 0
                    readonly property alias windowsLayer: windowsLayer
                    readonly property alias windowRepeater: windowRepeater
                    /// Title of the window under the pointer, shown in place of the number.
                    property string hoveredTitle: ""

                    width: root.cardWidth
                    height: root.cardHeight

                    HoverHandler {
                        id: cardHover
                    }

                    // Selection halo: a filled plate behind the card, not a border, reading as a
                    // ring only where it shows past the card's edge.
                    Rectangle {
                        anchors {
                            fill: parent
                            margins: -4
                        }
                        radius: root.cardRadius + 4
                        color: card.isDropTarget ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                        opacity: card.isActive || card.isDropTarget ? 1 : 0

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                        }
                    }

                    StyledRectangularShadow {
                        target: cardSurface
                        blur: 14
                        offset: Qt.vector2d(0, 3)
                    }

                    Rectangle {
                        id: cardSurface
                        anchors.fill: parent
                        radius: root.cardRadius
                        color: Appearance.colors.colLayer1
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: cardSurface.width
                                height: cardSurface.height
                                radius: cardSurface.radius
                            }
                        }

                        Image {
                            anchors.fill: parent
                            source: Config.options?.background?.wallpaperPath ?? ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(root.cardWidth * 2, root.cardHeight * 2)
                            asynchronous: true
                            cache: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: card.isDropTarget ? 0.05 : (cardHover.hovered && !card.isActive ? 0.12 : 0.22)

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                            }
                        }
                    }

                    // Empty workspace hint, which is also where a window can be dropped to make one.
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: card.isEmpty
                        text: "add"
                        iconSize: Math.round(root.cardHeight * (card.isDropTarget ? 0.34 : 0.26))
                        color: "white"
                        opacity: card.isDropTarget ? 0.95 : (cardHover.hovered ? 0.8 : 0.5)

                        Behavior on iconSize {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => root.touchMode = (mouse.source ?? 0) !== Qt.MouseEventNotSynthesized
                        onClicked: root.workspaceSelected(card.wsId)
                    }

                    Item {
                        id: windowsLayer
                        anchors.fill: parent

                        Repeater {
                            id: windowRepeater
                            model: ScriptModel {
                                objectProp: "address"
                                values: (HyprlandData.windowList ?? []).filter(win => win && win.workspace?.id === card.wsId
                                    && win.mapped !== false && win.hidden !== true)
                            }

                            delegate: Item {
                                id: winItem
                                required property var modelData
                                readonly property int wsId: card.wsId
                                readonly property Item cardItem: card

                                /// Fresh per event: the model keeps delegates by address, this keeps the geometry current.
                                readonly property var winData: HyprlandData.windowByAddress[winItem.modelData.address] ?? winItem.modelData
                                readonly property var toplevel: {
                                    const addr = String(winItem.winData?.address ?? "").replace(/^0x/, "").toLowerCase();
                                    const toplevels = ToplevelManager.toplevels.values ?? [];
                                    return toplevels.find(t => (t.HyprlandToplevel?.address ?? "").toLowerCase() === addr) ?? null;
                                }
                                readonly property bool isDragged: root.isDraggingWindow && root.draggingFromWindowAddress === winItem.winData?.address
                                readonly property bool isSwapTarget: root.isDraggingWindow && root.draggingTargetWindowAddress === winItem.winData?.address
                                readonly property bool hovered: thumbHover.hovered && !root.isDraggingWindow

                                readonly property real sx: winItem.cardItem.width / root.workWidth
                                readonly property real sy: winItem.cardItem.height / root.workHeight
                                readonly property bool fills: (winItem.winData?.fullscreen ?? 0) > 0
                                readonly property real thumbLeft: winItem.fills ? 0 : Math.max(0, ((winItem.winData?.at?.[0] ?? root.workX) - root.workX) * winItem.sx)
                                readonly property real thumbTop: winItem.fills ? 0 : Math.max(0, ((winItem.winData?.at?.[1] ?? root.workY) - root.workY) * winItem.sy)

                                x: Math.round(Math.min(winItem.thumbLeft, winItem.cardItem.width - 24))
                                y: Math.round(Math.min(winItem.thumbTop, winItem.cardItem.height - 18))
                                width: Math.round(Math.max(24, Math.min(winItem.cardItem.width - x,
                                    winItem.fills ? winItem.cardItem.width : (winItem.winData?.size?.[0] ?? 100) * winItem.sx)))
                                height: Math.round(Math.max(18, Math.min(winItem.cardItem.height - y,
                                    winItem.fills ? winItem.cardItem.height : (winItem.winData?.size?.[1] ?? 100) * winItem.sy)))
                                // Floating above tiled, the hovered one above both so its close button is reachable.
                                z: (winItem.hovered ? 20 : 0) + (winItem.fills ? 10 : 0) + (winItem.winData?.floating ? 5 : 0)
                                    - Math.min(4, winItem.winData?.focusHistoryID ?? 4) * 0.1

                                opacity: winItem.isDragged ? 0.3 : 1

                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(winItem)
                                }
                                Behavior on x {
                                    enabled: !root.isDraggingWindow
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(winItem)
                                }
                                Behavior on y {
                                    enabled: !root.isDraggingWindow
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(winItem)
                                }
                                Behavior on width {
                                    enabled: !root.isDraggingWindow
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(winItem)
                                }
                                Behavior on height {
                                    enabled: !root.isDraggingWindow
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(winItem)
                                }

                                onHoveredChanged: {
                                    if (winItem.hovered)
                                        winItem.cardItem.hoveredTitle = winItem.winData?.title || winItem.winData?.class || "";
                                    else if (winItem.cardItem.hoveredTitle === (winItem.winData?.title || winItem.winData?.class || ""))
                                        winItem.cardItem.hoveredTitle = "";
                                }
                                Component.onDestruction: {
                                    if (winItem.hovered && winItem.cardItem)
                                        winItem.cardItem.hoveredTitle = "";
                                }

                                HoverHandler {
                                    id: thumbHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                StyledRectangularShadow {
                                    target: thumbBody
                                    blur: 8
                                    offset: Qt.vector2d(0, 2)
                                }

                                Rectangle {
                                    id: thumbBody
                                    anchors.fill: parent
                                    // Scaled from the thumbnail, not from the real window: the
                                    // window's own rounding shrunk to card size came out ~4px,
                                    // which reads as a square corner.
                                    radius: Math.round(Math.max(6, Math.min(14, Math.min(winItem.width, winItem.height) * 0.08)))
                                    color: Appearance.colors.colLayer2
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: thumbBody.width
                                            height: thumbBody.height
                                            radius: thumbBody.radius
                                        }
                                    }

                                    ScreencopyView {
                                        id: preview
                                        anchors.fill: parent
                                        captureSource: (winItem.toplevel && root.drawerVisible && (Config.options?.overview?.showWindowPreviews ?? true)) ? winItem.toplevel : null
                                        live: root.drawerVisible && (Config.options?.background?.windowZoomLiveCapture ?? true)
                                    }

                                    // Before the first frame lands, or with previews off, the icon stands in.
                                    Image {
                                        anchors.centerIn: parent
                                        width: Math.min(40, Math.min(parent.width, parent.height) * 0.5)
                                        height: width
                                        sourceSize: Qt.size(64, 64)
                                        source: Quickshell.iconPath(AppSearch.guessIcon(winItem.winData?.class), "image-missing")
                                        visible: !preview.hasContent
                                    }
                                }

                                // Hover / swap halo, behind the thumbnail rather than a border on it.
                                Rectangle {
                                    anchors {
                                        fill: parent
                                        margins: -3
                                    }
                                    z: -1
                                    radius: thumbBody.radius + 3
                                    color: winItem.isSwapTarget ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                                    opacity: winItem.hovered || winItem.isSwapTarget ? 1 : 0

                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(winItem)
                                    }
                                }

                                // GNOME puts the app icon on the thumbnail's bottom edge, which identifies a window
                                // even when its screencopy is a wall of text.
                                Image {
                                    readonly property real iconSize: Math.round(Math.max(16, Math.min(30, Math.min(winItem.width, winItem.height) * 0.26)))
                                    anchors {
                                        horizontalCenter: parent.horizontalCenter
                                        bottom: parent.bottom
                                        bottomMargin: 6
                                    }
                                    width: iconSize
                                    height: iconSize
                                    sourceSize: Qt.size(iconSize * 2, iconSize * 2)
                                    source: Quickshell.iconPath(AppSearch.guessIcon(winItem.winData?.class), "image-missing")
                                    visible: preview.hasContent && winItem.width >= 44 && winItem.height >= 40
                                }

                                MouseArea {
                                    id: winMouse
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    preventStealing: true

                                    readonly property real mouseThreshold: 6
                                    readonly property real touchThreshold: 14
                                    property bool touch: false
                                    property int mode: 0 // 0: undecided, 1: panning the strip, 2: dragging the window
                                    property real startX: 0
                                    property real startY: 0
                                    property real startContentX: 0
                                    property real grabX: 0
                                    property real grabY: 0
                                    property real lastX: 0
                                    property real lastTime: 0
                                    property real velocity: 0

                                    onPressed: mouse => {
                                        winMouse.touch = (mouse.source ?? 0) !== Qt.MouseEventNotSynthesized;
                                        root.touchMode = winMouse.touch;
                                        if (mouse.button !== Qt.LeftButton)
                                            return;
                                        const pt = winMouse.mapToItem(root, mouse.x, mouse.y);
                                        winMouse.startX = pt.x;
                                        winMouse.startY = pt.y;
                                        winMouse.lastX = pt.x;
                                        winMouse.lastTime = Date.now();
                                        winMouse.velocity = 0;
                                        winMouse.grabX = mouse.x;
                                        winMouse.grabY = mouse.y;
                                        winMouse.startContentX = flickable.contentX;
                                        winMouse.mode = 0;
                                        scrollAnim.stop();
                                        root.pressedOnWindow = true;
                                        if (winMouse.touch)
                                            longPress.restart();
                                    }

                                    onPositionChanged: mouse => {
                                        if (!(mouse.buttons & Qt.LeftButton))
                                            return;
                                        const pt = winMouse.mapToItem(root, mouse.x, mouse.y);
                                        const dx = pt.x - winMouse.startX;
                                        const dy = pt.y - winMouse.startY;

                                        if (winMouse.mode === 0) {
                                            const threshold = winMouse.touch ? winMouse.touchThreshold : winMouse.mouseThreshold;
                                            if (Math.hypot(dx, dy) < threshold)
                                                return;
                                            longPress.stop();
                                            if (winMouse.touch && Math.abs(dx) > Math.abs(dy) && root.maxContentX > 0) {
                                                winMouse.mode = 1;
                                            } else {
                                                winMouse.mode = 2;
                                                root.beginWindowDrag(winItem, winMouse.grabX, winMouse.grabY);
                                            }
                                        }

                                        if (winMouse.mode === 1) {
                                            const now = Date.now();
                                            const dt = Math.max(1, now - winMouse.lastTime);
                                            winMouse.velocity = winMouse.velocity * 0.4 + ((pt.x - winMouse.lastX) / dt * 1000) * 0.6;
                                            winMouse.lastX = pt.x;
                                            winMouse.lastTime = now;
                                            flickable.contentX = Math.max(0, Math.min(root.maxContentX, winMouse.startContentX - dx));
                                        } else if (winMouse.mode === 2) {
                                            root.dragCurrentX = pt.x;
                                            root.dragCurrentY = pt.y;
                                            root.updateDragTargets();
                                        }
                                    }

                                    onReleased: mouse => {
                                        longPress.stop();
                                        const mode = winMouse.mode;
                                        winMouse.mode = 0;
                                        root.pressedOnWindow = false;
                                        if (mode === 2) {
                                            root.finishWindowDrag(winItem);
                                        } else if (mode === 1) {
                                            if (Math.abs(winMouse.velocity) > 150)
                                                flickable.flick(winMouse.velocity, 0);
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            root.closeWindow(winItem.winData.address);
                                        } else if (mouse.button === Qt.LeftButton) {
                                            root.windowSelected(winItem.winData.address);
                                        }
                                    }

                                    onCanceled: {
                                        longPress.stop();
                                        winMouse.mode = 0;
                                        root.resetDrag();
                                    }

                                    Timer {
                                        id: longPress
                                        interval: 380
                                        onTriggered: {
                                            if (winMouse.pressed && winMouse.mode === 0) {
                                                winMouse.mode = 2;
                                                root.dragCurrentX = winMouse.startX;
                                                root.dragCurrentY = winMouse.startY;
                                                root.beginWindowDrag(winItem, winMouse.grabX, winMouse.grabY);
                                            }
                                        }
                                    }
                                }

                                // Close, GNOME-style: overhangs the top-right corner, on hover (always on touch).
                                Rectangle {
                                    id: closeButton
                                    readonly property real size: winItem.width < 90 ? 20 : 26
                                    readonly property bool shown: !root.isDraggingWindow && winItem.width >= 48
                                        && (winItem.hovered || closeHover.hovered || (root.touchMode && winItem.cardItem.isActive))
                                    anchors {
                                        top: parent.top
                                        right: parent.right
                                        topMargin: -size * 0.3
                                        rightMargin: -size * 0.3
                                    }
                                    width: size
                                    height: size
                                    radius: size / 2
                                    z: 5
                                    color: closeArea.pressed ? Appearance.colors.colErrorHover
                                        : (closeHover.hovered ? Appearance.colors.colError : Appearance.colors.colLayer3)
                                    opacity: closeButton.shown ? 1 : 0
                                    scale: closeButton.shown ? 1 : 0.6
                                    visible: opacity > 0

                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(closeButton)
                                    }
                                    Behavior on scale {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(closeButton)
                                    }

                                    HoverHandler {
                                        id: closeHover
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: Math.round(closeButton.size * 0.62)
                                        color: closeHover.hovered ? Appearance.colors.colOnError : Appearance.colors.colOnLayer3
                                    }

                                    MouseArea {
                                        id: closeArea
                                        anchors {
                                            fill: parent
                                            margins: -6 // a finger-sized target around a mouse-sized button
                                        }
                                        preventStealing: true
                                        onClicked: root.closeWindow(winItem.winData.address)
                                    }
                                }
                            }
                        }
                    }

                    // Caption: the number, or the title of the window being pointed at.
                    Item {
                        anchors {
                            top: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        height: root.captionHeight

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(card.width, captionText.implicitWidth + 20)
                            height: 24
                            radius: height / 2
                            color: card.isActive && !card.hoveredTitle ? Appearance.colors.colPrimary : "transparent"

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
                            }

                            StyledText {
                                id: captionText
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, card.width - 20)
                                elide: Text.ElideRight
                                text: card.hoveredTitle || card.wsId
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: card.isActive ? Font.DemiBold : Font.Normal
                                font.family: card.hoveredTitle ? Appearance.font.family.main : Appearance.font.family.numbers
                                color: card.isActive && !card.hoveredTitle
                                    ? Appearance.colors.colOnPrimary
                                    : (card.hoveredTitle ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Side navigation ───────────────────────────────────────────────────────
    NavButton {
        anchors {
            left: flickable.left
            leftMargin: Math.max(12, root.horizontalBleed * 0.35)
        }
        y: root.cardTopMargin + (root.cardHeight - height) / 2
        symbol: "chevron_left"
        shown: flickable.contentX > 4
        onTriggered: root.scrollByPage(-1)
    }

    NavButton {
        anchors {
            right: flickable.right
            rightMargin: Math.max(12, root.horizontalBleed * 0.35)
        }
        y: root.cardTopMargin + (root.cardHeight - height) / 2
        symbol: "chevron_right"
        shown: flickable.contentX < root.maxContentX - 4
        onTriggered: root.scrollByPage(1)
    }

    // ── Drag proxy, above everything so it can travel between cards ───────────
    Item {
        id: dragProxy
        visible: root.isDraggingWindow
        z: 100
        width: Math.max(40, root.draggedWidth)
        height: Math.max(30, root.draggedHeight)
        x: Math.round(root.dragCurrentX - root.dragGrabX)
        y: Math.round(root.dragCurrentY - root.dragGrabY)
        // Lifts off, then shrinks over a workspace it would be dropped into.
        scale: !root.isDraggingWindow ? 1
            : (root.draggingTargetWorkspace !== -1 && root.draggingTargetWorkspace !== root.draggingFromWorkspace ? 0.7 : 1.06)
        transformOrigin: Item.TopLeft

        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dragProxy)
        }

        StyledRectangularShadow {
            target: dragProxyBody
            blur: 22
            offset: Qt.vector2d(0, 8)
        }

        Rectangle {
            id: dragProxyBody
            anchors.fill: parent
            radius: Math.round(Math.max(6, Math.min(14, Math.min(dragProxy.width, dragProxy.height) * 0.08)))
            color: Appearance.colors.colLayer2
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: dragProxyBody.width
                    height: dragProxyBody.height
                    radius: dragProxyBody.radius
                }
            }

            ScreencopyView {
                id: proxyPreview
                anchors.fill: parent
                captureSource: root.isDraggingWindow ? root.draggedToplevel : null
                live: root.isDraggingWindow
            }

            Image {
                anchors.centerIn: parent
                width: 32
                height: 32
                sourceSize: Qt.size(64, 64)
                source: root.draggedWindowData ? Quickshell.iconPath(AppSearch.guessIcon(root.draggedWindowData.class), "image-missing") : ""
                visible: !proxyPreview.hasContent
            }
        }

        // Lifted halo behind the carried window.
        Rectangle {
            anchors {
                fill: parent
                margins: -3
            }
            z: -1
            radius: dragProxyBody.radius + 3
            color: Appearance.colors.colPrimary
        }
    }

    // ── Components ────────────────────────────────────────────────────────────
    component NavButton: Rectangle {
        id: navButton
        required property string symbol
        property bool shown: true
        signal triggered()

        z: 50
        width: 48
        height: 48
        radius: height / 2
        color: navArea.pressed ? Appearance.colors.colSecondaryContainerActive
            : (navArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
        opacity: navButton.shown ? 1 : 0
        scale: navButton.shown ? (navArea.pressed ? 0.92 : 1) : 0.7
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(navButton)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(navButton)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(navButton)
        }

        StyledRectangularShadow {
            target: navButton
            blur: 16
            offset: Qt.vector2d(0, 4)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: navButton.symbol
            iconSize: 28
            color: Appearance.colors.colOnSecondaryContainer
        }

        MouseArea {
            id: navArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: navButton.triggered()
        }
    }
}
