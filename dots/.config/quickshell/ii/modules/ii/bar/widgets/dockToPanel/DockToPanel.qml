import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.modules.ii.bar.shared

Item {
    id: root

    property real iconSize:      Config.options.dockToPanel.iconSize
    property real btnSize:       iconSize + 5
    property real btnSpacing:    Config.options.dockToPanel.buttonSpacing
    property bool vertical:    Config.options.bar.vertical
    property bool isMaterial:  Config.options.bar.cornerStyle === 3
    property var pinnedApps: Config.options?.dock.pinnedApps ?? []

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1
    readonly property bool alignToWorkspace: Config.options?.dockToPanel?.alignToWorkspace ?? false
    readonly property bool enableWorkspaceScroll: Config.options?.dockToPanel?.enableWorkspaceScroll ?? true

    // Scratchpad detection (matching Workspaces.qml pattern)
    readonly property var currentHyprlandMonitorData: HyprlandData.monitors.find(mon => mon.name === root.monitor?.name)
    readonly property bool scratchpadOpen: !!(currentHyprlandMonitorData && currentHyprlandMonitorData.specialWorkspace && currentHyprlandMonitorData.specialWorkspace.name !== "")
    readonly property var scratchpadWin: scratchpadOpen ? HyprlandData.windowList.find(w => w.workspace && w.workspace.id === currentHyprlandMonitorData.specialWorkspace.id) : null
    readonly property string scratchpadAppId: scratchpadWin ? TaskbarApps.normalizeAppId(scratchpadWin.class) : ""

    // Hover, Tooltip and Preview state
    property Item lastHoveredButton: null
    property point hoveredButtonCenter: Qt.point(0, 0)
    property bool buttonHovered: false
    property bool suppressHover: false
    property bool popupIsResizing: false
    readonly property bool anyContextMenuOpen: false
    readonly property real maxWindowPreviewHeight: 200
    readonly property real maxWindowPreviewWidth: 300
    readonly property real windowControlsHeight: 30
    readonly property bool isVertical: root.vertical
    property Item hoveredSlot: null
    // ── Magnification Customization Tokens ──
    readonly property bool enableMacOsMagnification: Config.options?.dockToPanel?.enableMacOsMagnification ?? false
    readonly property real macOsMagnificationScale: Config.options?.dockToPanel?.macOsMagnificationScale ?? 1.6
    readonly property real magInfluenceRadius: Config.options?.dockToPanel?.magInfluenceRadius ?? 2.5
    readonly property string magCurveType: Config.options?.dockToPanel?.magCurveType ?? "parabolic"
    readonly property real magGaussianSigma: 1.1

    readonly property int magTransformOrigin: {
        let pos = root.dockEffectivePosition;
        if (pos === "top") return Item.Top;
        if (pos === "bottom") return Item.Bottom;
        if (pos === "left") return Item.Left;
        if (pos === "right") return Item.Right;
        return Item.Center;
    }

    function _getSlotMagScale(targetSlot) {
        if (!enableMacOsMagnification || !buttonHovered || !hoveredSlot) return 1.0;
        let maxScale = macOsMagnificationScale;
        let children = [];
        for (let i = 0; i < flow.children.length; i++) {
            let child = flow.children[i];
            if (child && child.isAppSlot) children.push(child);
        }
        let myIdx = children.indexOf(targetSlot);
        let hvdIdx = children.indexOf(hoveredSlot);
        if (myIdx < 0 || hvdIdx < 0) return 1.0;

        let dist = Math.abs(myIdx - hvdIdx);
        let radius = magInfluenceRadius;
        if (dist >= radius) return 1.0;

        let factor = 0.0;
        if (magCurveType === "gaussian") {
            let sigma = magGaussianSigma;
            let val = Math.exp(-(dist * dist) / (2.0 * sigma * sigma));
            let cutoff = Math.exp(-(radius * radius) / (2.0 * sigma * sigma));
            factor = Math.max(0.0, (val - cutoff) / (1.0 - cutoff));
        } else {
            factor = 0.5 * (1.0 + Math.cos((Math.PI * dist) / radius));
        }

        return 1.0 + (maxScale - 1.0) * factor;
    }

    Timer {
        id: hoverGraceTimer
        interval: 150
        onTriggered: {
            root.buttonHovered = false;
            root.hoveredSlot = null;
        }
    }

    onLastHoveredButtonChanged: {
        if (root.lastHoveredButton) {
            let p = root.lastHoveredButton.mapToItem(null, root.lastHoveredButton.width / 2, root.lastHoveredButton.height / 2);
            root.hoveredButtonCenter = p;
        }
    }

    readonly property bool isolateMonitors: Config.options?.dockToPanel?.isolateMonitors ?? false

    function _isWinOnMonitor(win, monName, monId) {
        if (!win) return false;
        if (win.monitor !== undefined && win.monitor !== null) {
            if (win.monitor === monId || win.monitor === monName) return true;
            let monObj = HyprlandData.monitors.find(m => m.id === win.monitor || m.name === win.monitor);
            if (monObj && (monObj.name === monName || monObj.id === monId)) return true;
        }
        if (win.workspace) {
            if (win.workspace.monitor === monName || win.workspace.monitorID === monId) return true;
            let wsObj = HyprlandData.workspaces.find(w => w.id === win.workspace.id);
            if (wsObj && (wsObj.monitor === monName || wsObj.monitorID === monId)) return true;
        }
        return false;
    }

    function _isToplevelOnMonitor(toplevel, monName, monId) {
        if (!toplevel || !monName) return false;
        
        let addr = toplevel.HyprlandToplevel?.address;
        if (addr) {
            let hexAddr = addr.startsWith("0x") ? addr : ("0x" + addr);
            let win = HyprlandData.windowByAddress[hexAddr];
            if (!win) win = HyprlandData.windowList.find(w => w.address === hexAddr || w.address === addr);
            if (win) {
                return root._isWinOnMonitor(win, monName, monId);
            }
        }

        if (toplevel.appId) {
            let normAppId = TaskbarApps.normalizeAppId(toplevel.appId);
            let matchingWins = HyprlandData.windowList.filter(w => 
                w.class && TaskbarApps.normalizeAppId(w.class) === normAppId
            );
            if (matchingWins.length > 0) {
                return matchingWins.some(w => root._isWinOnMonitor(w, monName, monId));
            }
        }

        if (toplevel.title) {
            let matchingWins = HyprlandData.windowList.filter(w => w.title && w.title === toplevel.title);
            if (matchingWins.length > 0) {
                return matchingWins.some(w => root._isWinOnMonitor(w, monName, monId));
            }
        }

        return false;
    }

    // Helper to find lowest workspace ID for an app
    function _getAppMinWorkspace(appId) {
        let entry = TaskbarApps.apps.find(a => a.appId === appId);
        if (!entry || !entry.toplevels || entry.toplevels.length === 0) return 999;
        let minWs = 999;
        for (let t of entry.toplevels) {
            let win = HyprlandData.windowList.find(w => w.address === t.address || w.title === t.title);
            if (win && win.workspace && win.workspace.id > 0) {
                if (win.workspace.id < minWs) minWs = win.workspace.id;
            }
        }
        return minWs;
    }

    property var activeUnpinned: {
        let list = TaskbarApps.apps.filter(a => !a.pinned && a.appId !== "SEPARATOR" && a.toplevels.length > 0);
        if (root.isolateMonitors && root.monitor && root.monitor.name && !(Config.options?.bar?.onlyShowOnSingleMonitor ?? false)) {
            let monName = root.monitor.name;
            let monId = root.monitor.id;
            list = list.filter(a => a.toplevels.some(t => root._isToplevelOnMonitor(t, monName, monId)));
        }
        if (root.alignToWorkspace) {
            list.sort((a, b) => root._getAppMinWorkspace(a.appId) - root._getAppMinWorkspace(b.appId));
        }
        return list;
    }
    property bool showSeparator: _workOrder.length > 0 && activeUnpinned.length > 0
    property var  _workOrder: {
        let list = pinnedApps.slice();
        if (root.alignToWorkspace) {
            list.sort((a, b) => root._getAppMinWorkspace(a) - root._getAppMinWorkspace(b));
        }
        return list;
    }
    property bool _dragging:             false

    // ── Drag animation state ──────────────────────────────────────────────
    property bool dragging: false
    property bool _suppressTranslateAnim: false
    property int dragSourceIndex: -1
    property int _dragTargetIndex: -1
    property real dragCursorX: 0
    property real dragStartCursorX: 0
    property real slotWidth: root.btnSize + root.btnSpacing
    // Half of the padding the pill adds around the icon flow, so the flow can be
    // anchored to the leading edge and still sit where centring used to put it.
    readonly property real flowPadding: root.isMaterial ? 5 : 2

    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical

    function _getPinnedItemWrapper(index) {
        return pinnedRepeater.itemAt(index)
    }

    function _getPinnedItemWidth(index) {
        var wrapper = _getPinnedItemWrapper(index)
        return wrapper ? (root.vertical ? wrapper.height : wrapper.width) : root.btnSize
    }

    function _getMaxDragOffset(index) {
        var count = _workOrder.length
        if (count <= 1) return { left: 0, right: 0 }
        var left = 0, right = 0
        for (var i = 0; i < count; i++) {
            var w = _getPinnedItemWidth(i) + root.btnSpacing
            if (i < index) left += w
            else if (i > index) right += w
        }
        return { left: -left, right: right }
    }

    function _recomputeDragTarget() {
        if (!dragging) {
            _dragTargetIndex = dragSourceIndex
            return
        }

        var count = _workOrder.length
        if (count <= 1) {
            _dragTargetIndex = dragSourceIndex
            return
        }

        var delta = dragCursorX - dragStartCursorX

        // dragged item center
        var draggedCenter = delta

        var target = dragSourceIndex

        if (delta > 0) {
            // moving right/down
            var pos = 0
            for (var i = dragSourceIndex + 1; i < count; ++i) {
                pos += (_getPinnedItemWidth(i - 1) + root.btnSpacing) / 2
                pos += (_getPinnedItemWidth(i) + root.btnSpacing) / 2

                if (draggedCenter >= pos)
                    target = i
                else
                    break
            }
        } else if (delta < 0) {
            var pos = 0
            for (var i = dragSourceIndex - 1; i >= 0; --i) {
                pos -= (_getPinnedItemWidth(i + 1) + root.btnSpacing) / 2
                pos -= (_getPinnedItemWidth(i) + root.btnSpacing) / 2

                if (draggedCenter <= pos)
                    target = i
                else
                    break
            }
        }

        _dragTargetIndex = target
    }

    function _startPinnedItemDrag(index) {
        _suppressTranslateAnim = true
        dragSourceIndex = index
        _dragTargetIndex = index
        slotWidth = root.btnSize + root.btnSpacing
        dragStartCursorX = 0
        dragCursorX = 0
        dragging = true
        Qt.callLater(function() { _suppressTranslateAnim = false })
    }

    // ── FIXED: move instead of swap ──────────────────────────────────────
    function _endPinnedItemDrag() {
        _suppressTranslateAnim = true

        var src = dragSourceIndex
        var tgt = _dragTargetIndex

        if (dragging &&
            src >= 0 &&
            tgt >= 0 &&
            src < _workOrder.length &&
            tgt < _workOrder.length &&
            src !== tgt) {

            var arr = _workOrder.slice()

            var item = arr[src]
            arr.splice(src, 1)
            arr.splice(tgt, 0, item)

            _workOrder = arr
            Config.options.dock.pinnedApps = arr
        }

        dragging = false
        dragSourceIndex = -1
        _dragTargetIndex = -1
        dragCursorX = 0
        dragStartCursorX = 0

        Qt.callLater(function() {
            _suppressTranslateAnim = false
        })
    }

    function _cancelPinnedDrag() {
        _suppressTranslateAnim = true
        dragging = false
        dragSourceIndex = -1
        _dragTargetIndex = -1
        Qt.callLater(function() { _suppressTranslateAnim = false })
    }

    onPinnedAppsChanged: {
        if (!_dragging)
            _workOrder = pinnedApps.slice()
    }

    implicitWidth:  vertical
        ? (isMaterial ? Appearance.sizes.verticalBarWidth : Appearance.sizes.verticalBarWidth - 10)
        : pill.implicitWidth
    implicitHeight: vertical
        ? pill.implicitHeight
        : Appearance.sizes.barHeight


    Rectangle {
        id: pill
        anchors.centerIn: parent
        color: "transparent"
        radius: Appearance.rounding.full

        implicitWidth: root.isMaterial && !root.vertical
            ? flow.implicitWidth + 10
            : root.vertical
                ? (root.isMaterial ? 32 : Appearance.sizes.verticalBarWidth - 10)
                : flow.implicitWidth + 4

        implicitHeight: root.isMaterial && root.vertical
            ? flow.implicitHeight + 10
            : root.isMaterial
                ? 32
                : root.vertical
                    ? flow.implicitHeight + 4
                    : Appearance.sizes.barHeight

        Behavior on implicitWidth {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: root.enableWorkspaceScroll
            acceptedButtons: Qt.NoButton
            onWheel: event => {
                let delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                if (delta > 0) {
                    let target = Math.max(1, root.activeWsId - 1);
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + target + " })");
                } else if (delta < 0) {
                    let target = root.activeWsId + 1;
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + target + " })");
                }
            }
        }

        Flow {
            id: flow
            // Pinned to the leading edge instead of centred. A Flow re-lays out
            // the instant an item is added or removed, so its own width jumps in
            // one frame; centring it inside a pill that is still animating threw
            // every icon sideways by half the delta before anything moved — the
            // "brusque" shift when an app opens. Anchored to the edge, the pill's
            // growth and the icons' `move` transition are the only motion left,
            // and both run on Appearance.animation.barResize.
            anchors.left: root.vertical ? undefined : parent.left
            anchors.leftMargin: root.vertical ? 0 : root.flowPadding
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
            anchors.top: root.vertical ? parent.top : undefined
            anchors.topMargin: root.vertical ? root.flowPadding : 0
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            flow:    root.vertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: root.btnSpacing

            // Reordering during a drag is already driven by the per-slot
            // Translate below, so the positioner must stay out of the way there.
            move: Transition {
                enabled: !root._suppressTranslateAnim && !root.dragging
                NumberAnimation {
                    properties: "x,y"
                    duration: Appearance.animation.barResize.duration
                    easing.type: Appearance.animation.barResize.type
                    easing.bezierCurve: Appearance.animation.barResize.bezierCurve
                }
            }

            // ── 1. PINNED APPS ───────────────────────────────────────────
            Repeater {
                id: pinnedRepeater
                model: root._workOrder.length

                delegate: Item {
                    id: slotItem
                    required property int index

                    property string appId:        root._workOrder[index] ?? ""
                    property var    appEntry:     TaskbarApps.apps.find(a => a.appId === appId) ?? null
                    property var    appToplevel:  appEntry
                    property var    appToplevels: appEntry?.toplevels ?? []
                    property var    deskEntry:    TaskbarApps.getCachedDesktopEntry(appId)
                    property string appTitle:     deskEntry?.name ?? appId
                    property bool   appActive:    appToplevels.find(t => t.activated) !== undefined
                    readonly property bool isScratchpadApp: root.scratchpadOpen && TaskbarApps.normalizeAppId(appId) === root.scratchpadAppId
                    readonly property bool hovered: root.lastHoveredButton === slotItem && root.buttonHovered
                    property int    _lastFocused: -1

                    // ── Animation properties (with clamping) ──────────────
                    readonly property bool isDragged: root.dragging && index === root.dragSourceIndex
                    readonly property real dragTranslate: {
                        if (!root.dragging) return 0
                        if (isDragged) {
                            var raw = root.dragCursorX - root.dragStartCursorX
                            var maxOff = root._getMaxDragOffset(index)
                            var clamped = Math.max(maxOff.left, Math.min(maxOff.right, raw))
                            return clamped
                        }
                        var src = root.dragSourceIndex
                        var tgt = root._dragTargetIndex
                        var idx = index
                        var sw = root.slotWidth
                        if (src < tgt && idx > src && idx <= tgt) return -sw
                        if (src > tgt && idx >= tgt && idx < src) return sw
                        return 0
                    }

                    readonly property bool isAppSlot: true
                    readonly property real magScale: root._getSlotMagScale(slotItem)
                    readonly property real baseScale: root.scratchpadOpen ? (isScratchpadApp ? 1.0 : 0.85) : (isDragged ? 1.05 : 1.0)
                    opacity: root.scratchpadOpen ? (isScratchpadApp ? 1.0 : 0.35) : (isDragged ? 0.85 : 1.0)
                    scale: baseScale

                    width:  root.btnSize
                    height: root.btnSize

                    Behavior on opacity {
                        enabled: !root._suppressTranslateAnim
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on scale {
                        enabled: !root._suppressTranslateAnim
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    transform: Translate {
                        x: root.vertical ? 0 : slotItem.dragTranslate
                        y: root.vertical ? slotItem.dragTranslate : 0
                        Behavior on x {
                            enabled: !slotItem.isDragged && !root._suppressTranslateAnim
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        Behavior on y {
                            enabled: !slotItem.isDragged && !root._suppressTranslateAnim
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }

                    // ── DragHandler ──────────────────────────────────────────
                    DragHandler {
                        id: dragHandler
                        enabled: !root.alignToWorkspace
                        target: null
                        grabPermissions: PointerHandler.CanTakeOverFromAnything

                        onActiveChanged: {
                            if (active) {
                                root._startPinnedItemDrag(index)
                                var pos = root.vertical ? centroid.scenePosition.y : centroid.scenePosition.x
                                root.dragStartCursorX = pos
                                root.dragCursorX = pos
                            } else {
                                if (root.dragging) {
                                    root._endPinnedItemDrag()
                                }
                            }
                        }

                        onCentroidChanged: {
                            if (!active || !root.dragging) return
                            var pos = root.vertical ? centroid.scenePosition.y : centroid.scenePosition.x
                            root.dragCursorX = pos
                            root._recomputeDragTarget()
                        }
                    }

                    // ── Main button ──────────────────────────────────────────
                    RippleButton {
                        id: mainBtn
                        width:  root.vertical ? Math.round(root.btnSize * slotItem.magScale) : parent.width
                        height: root.vertical ? parent.height : Math.round(root.btnSize * slotItem.magScale)
                        z: slotItem.isDragged ? 100 : Math.round(slotItem.magScale * 10)

                        anchors.top:    (!root.vertical && root.dockEffectivePosition === "top")    ? parent.top    : undefined
                        anchors.bottom: (!root.vertical && root.dockEffectivePosition === "bottom") ? parent.bottom : undefined
                        anchors.left:   (root.vertical  && root.dockEffectivePosition === "left")   ? parent.left   : undefined
                        anchors.right:  (root.vertical  && root.dockEffectivePosition === "right")  ? parent.right  : undefined

                        buttonRadius: Appearance.rounding.small
                        hoverEnabled: true
                        colBackgroundHover: root.enableMacOsMagnification ? "transparent" : (Appearance?.colors.colLayer1Hover ?? "#E5DFED")
                        colBackgroundActive: root.enableMacOsMagnification ? "transparent" : (Appearance?.colors.colLayer1Active ?? colBackgroundHover)

                        Behavior on width {
                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                        }

                        enteredAction: () => {
                            if (root.suppressHover || root.dragging) return;
                            hoverGraceTimer.stop();
                            root.hoveredSlot = slotItem;
                            root.lastHoveredButton = slotItem;
                            root.buttonHovered = true;
                        }
                        exitedAction: () => {
                            if (root.lastHoveredButton === slotItem)
                                hoverGraceTimer.restart();
                        }

                        onClicked: {
                            if (root.dragging) return
                            const entry = slotItem.appEntry
                            if (!entry || entry.toplevels.length === 0) {
                                slotItem.deskEntry?.execute()
                                return
                            }
                            const next = (slotItem._lastFocused + 1) % entry.toplevels.length
                            slotItem._lastFocused = next
                            entry.toplevels[next].activate()
                        }
                        middleClickAction: () => { slotItem.deskEntry?.execute() }
                        altAction:         () => { TaskbarApps.togglePin(slotItem.appId) }
                        backClickAction: () => {
                            root.buttonHovered = false;
                            root.lastHoveredButton = null;
                            Hyprland.dispatch("hl.dsp.workspace.toggle_special('special')");
                        }

                        StyledToolTip {
                            text: slotItem.appTitle
                            extraVisibleCondition: (Config.options?.dockToPanel?.enableTooltip ?? true) && !(Config.options?.dockToPanel?.enablePreview ?? false)
                        }

                        contentItem: Item {
                            anchors.fill: parent

                            IconImage {
                                id: pinnedIcon
                                source: Quickshell.iconPath(
                                    AppSearch.guessIcon(slotItem.appId), "image-missing")
                                implicitSize: Math.round(root.iconSize * slotItem.magScale)

                                anchors.top: (!root.vertical && root.dockEffectivePosition === "top") ? parent.top : undefined
                                anchors.bottom: (!root.vertical && root.dockEffectivePosition === "bottom") ? parent.bottom : undefined
                                anchors.left: (root.vertical && root.dockEffectivePosition === "left") ? parent.left : undefined
                                anchors.right: (root.vertical && root.dockEffectivePosition === "right") ? parent.right : undefined

                                anchors.topMargin: (!root.vertical && root.dockEffectivePosition === "top") ? Math.round((root.btnSize - root.iconSize) / 2) : 0
                                anchors.bottomMargin: (!root.vertical && root.dockEffectivePosition === "bottom") ? Math.round((root.btnSize - root.iconSize) / 2) : 0
                                anchors.leftMargin: (root.vertical && root.dockEffectivePosition === "left") ? Math.round((root.btnSize - root.iconSize) / 2) : 0
                                anchors.rightMargin: (root.vertical && root.dockEffectivePosition === "right") ? Math.round((root.btnSize - root.iconSize) / 2) : 0

                                anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                                anchors.verticalCenter: !root.vertical ? (
                                    (root.dockEffectivePosition === "top" || root.dockEffectivePosition === "bottom") ? undefined : parent.verticalCenter
                                ) : undefined

                                Behavior on implicitSize {
                                    animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                }
                            }

                            Loader {
                                active: Config.options?.dock?.monochromeIcons ?? false
                                anchors.fill: pinnedIcon
                                sourceComponent: Item {
                                    Desaturate {
                                        id: desat; visible: false
                                        anchors.fill: parent
                                        source: pinnedIcon; desaturation: 0.8
                                    }
                                    ColorOverlay {
                                        anchors.fill: desat; source: desat
                                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, Config.options.appearance.iconTintPercentage)
                                    }
                                }
                            }

                            Flow {
                                flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                                spacing: 2
                                anchors {
                                    left:   root.vertical ? pinnedIcon.right    : undefined
                                    top:    root.vertical ? undefined            : pinnedIcon.bottom
                                    leftMargin:  root.vertical ? 1 : 0
                                    topMargin:   root.vertical ? 0 : 1
                                    horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                                    verticalCenter:   root.vertical ? parent.verticalCenter : undefined
                                }
                                Repeater {
                                    model: Math.min(slotItem.appToplevels.length, 3)
                                    delegate: Rectangle {
                                        required property int index
                                        readonly property int topCount: slotItem.appToplevels.length
                                        readonly property bool isSingleActive: slotItem.appActive && topCount === 1

                                        radius: Appearance.rounding.full
                                        implicitWidth: root.vertical
                                            ? 3
                                            : (isSingleActive ? 14 : (topCount <= 3 ? 4 : 3))
                                        implicitHeight: root.vertical
                                            ? (isSingleActive ? 14 : (topCount <= 3 ? 4 : 3))
                                            : 3
                                        color: slotItem.appActive
                                            ? Appearance.colors.colPrimary
                                            : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.75)

                                        Behavior on implicitWidth {
                                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                        }
                                        Behavior on implicitHeight {
                                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                        }
                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── 2. SEPARATOR ─────────────────────────────────────────────
            Item {
                width:   root.vertical ? root.btnSize          : (root.showSeparator ? (1 + root.btnSpacing * 3) : 0)
                height:  root.vertical ? (root.showSeparator ? (1 + root.btnSpacing * 3) : 0) : root.btnSize
                visible: root.showSeparator

                Rectangle {
                    anchors.centerIn: parent
                    width:  root.vertical ? Math.round(root.btnSize * 0.6) : 1
                    height: root.vertical ? 1 : Math.round(root.btnSize * 0.6)
                    color:  root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                }
            }

            // ── 3. ACTIVE UNPINNED APPS ───────────────────────────────────
            Repeater {
                id: activeRepeater
                model: root.activeUnpinned

                delegate: Item {
                    id: activeSlot
                    required property var modelData

                    property var activeToplevels: modelData.toplevels ?? []
                    property var appToplevel: modelData
                    property string appTitle: TaskbarApps.getCachedDesktopEntry(modelData.appId)?.name ?? modelData.appId
                    property bool appIsActive: activeToplevels.find(t => t.activated) !== undefined
                    readonly property bool isScratchpadApp: root.scratchpadOpen && TaskbarApps.normalizeAppId(modelData.appId) === root.scratchpadAppId
                    readonly property bool hovered: root.lastHoveredButton === activeSlot && root.buttonHovered
                    property int  _lastFocused: -1

                    readonly property bool isAppSlot: true
                    readonly property real magScale: root._getSlotMagScale(activeSlot)
                    readonly property real baseScale: root.scratchpadOpen ? (isScratchpadApp ? 1.0 : 0.85) : 1.0
                    opacity: root.scratchpadOpen ? (isScratchpadApp ? 1.0 : 0.35) : 1.0
                    scale: baseScale

                    width:  root.btnSize
                    height: root.btnSize

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    RippleButton {
                        id: activeBtn
                        width:  root.vertical ? Math.round(root.btnSize * activeSlot.magScale) : parent.width
                        height: root.vertical ? parent.height : Math.round(root.btnSize * activeSlot.magScale)
                        z: Math.round(activeSlot.magScale * 10)

                        anchors.top:    (!root.vertical && root.dockEffectivePosition === "top")    ? parent.top    : undefined
                        anchors.bottom: (!root.vertical && root.dockEffectivePosition === "bottom") ? parent.bottom : undefined
                        anchors.left:   (root.vertical  && root.dockEffectivePosition === "left")   ? parent.left   : undefined
                        anchors.right:  (root.vertical  && root.dockEffectivePosition === "right")  ? parent.right  : undefined

                        buttonRadius: Appearance.rounding.small
                        hoverEnabled: true
                        colBackgroundHover: root.enableMacOsMagnification ? "transparent" : (Appearance?.colors.colLayer1Hover ?? "#E5DFED")
                        colBackgroundActive: root.enableMacOsMagnification ? "transparent" : (Appearance?.colors.colLayer1Active ?? colBackgroundHover)

                        Behavior on width {
                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                        }

                        enteredAction: () => {
                            if (root.suppressHover || root.dragging) return;
                            hoverGraceTimer.stop();
                            root.hoveredSlot = activeSlot;
                            root.lastHoveredButton = activeSlot;
                            root.buttonHovered = true;
                        }
                        exitedAction: () => {
                            if (root.lastHoveredButton === activeSlot)
                                hoverGraceTimer.restart();
                        }

                        onClicked: {
                            if (activeSlot.modelData.toplevels.length === 0) return
                            const next = (activeSlot._lastFocused + 1) % activeSlot.modelData.toplevels.length
                            activeSlot._lastFocused = next
                            activeSlot.modelData.toplevels[next].activate()
                        }
                        middleClickAction: () => {
                            DesktopEntries.heuristicLookup(activeSlot.modelData.appId)?.execute()
                        }
                        altAction: () => {
                            TaskbarApps.togglePin(activeSlot.modelData.appId)
                        }
                        backClickAction: () => {
                            root.buttonHovered = false;
                            root.lastHoveredButton = null;
                            Hyprland.dispatch("hl.dsp.workspace.toggle_special('special')");
                        }

                        StyledToolTip {
                            text: activeSlot.appTitle
                            extraVisibleCondition: (Config.options?.dockToPanel?.enableTooltip ?? true) && !(Config.options?.dockToPanel?.enablePreview ?? false)
                        }

                        contentItem: Item {
                            anchors.fill: parent

                            IconImage {
                                id: activeIcon
                                source: Quickshell.iconPath(
                                    AppSearch.guessIcon(activeSlot.modelData.appId), "image-missing")
                                implicitSize: Math.round(root.iconSize * activeSlot.magScale)

                                anchors.top: (!root.vertical && root.dockEffectivePosition === "top") ? parent.top : undefined
                                anchors.bottom: (!root.vertical && root.dockEffectivePosition === "bottom") ? parent.bottom : undefined
                                anchors.left: (root.vertical && root.dockEffectivePosition === "left") ? parent.left : undefined
                                anchors.right: (root.vertical && root.dockEffectivePosition === "right") ? parent.right : undefined

                                anchors.topMargin: (!root.vertical && root.dockEffectivePosition === "top") ? Math.round((root.btnSize - root.iconSize) / 2) : 0
                                anchors.bottomMargin: (!root.vertical && root.dockEffectivePosition === "bottom") ? Math.round((root.btnSize - root.iconSize) / 2) : 0
                                anchors.leftMargin: (root.vertical && root.dockEffectivePosition === "left") ? Math.round((root.btnSize - root.iconSize) / 2) : 0
                                anchors.rightMargin: (root.vertical && root.dockEffectivePosition === "right") ? Math.round((root.btnSize - root.iconSize) / 2) : 0

                                anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                                anchors.verticalCenter: !root.vertical ? (
                                    (root.dockEffectivePosition === "top" || root.dockEffectivePosition === "bottom") ? undefined : parent.verticalCenter
                                ) : undefined

                                Behavior on implicitSize {
                                    animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                }
                            }

                            Loader {
                                active: Config.options?.dock?.monochromeIcons ?? false
                                anchors.fill: activeIcon
                                sourceComponent: Item {
                                    Desaturate {
                                        id: desat2; visible: false
                                        anchors.fill: parent
                                        source: activeIcon; desaturation: 0.8
                                    }
                                    ColorOverlay {
                                        anchors.fill: desat2; source: desat2
                                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, Config.options.appearance.iconTintPercentage)
                                    }
                                }
                            }

                            Flow {
                                flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                                spacing: 2
                                anchors {
                                    left:   root.vertical ? activeIcon.right    : undefined
                                    top:    root.vertical ? undefined            : activeIcon.bottom
                                    leftMargin:  root.vertical ? 1 : 0
                                    topMargin:   root.vertical ? 0 : 1
                                    horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                                    verticalCenter:   root.vertical ? parent.verticalCenter : undefined
                                }
                                Repeater {
                                    model: Math.min(activeSlot.activeToplevels.length, 3)
                                    delegate: Rectangle {
                                        required property int index
                                        readonly property int topCount: activeSlot.activeToplevels.length
                                        readonly property bool isSingleActive: activeSlot.appIsActive && topCount === 1

                                        radius: Appearance.rounding.full
                                        implicitWidth: root.vertical
                                            ? 3
                                            : (isSingleActive ? 14 : (topCount <= 3 ? 4 : 3))
                                        implicitHeight: root.vertical
                                            ? (isSingleActive ? 14 : (topCount <= 3 ? 4 : 3))
                                            : 3
                                        color: activeSlot.appIsActive
                                            ? Appearance.colors.colPrimary
                                            : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.45)

                                        Behavior on implicitWidth {
                                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                        }
                                        Behavior on implicitHeight {
                                            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                        }
                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
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
    }

    // ── Window Preview Popup (Bar Native) ──────────────────────────────
    StyledPopup {
        id: previewPopup
        hoverTarget: root.lastHoveredButton
        stickyHover: true
        active: (Config.options?.dockToPanel?.enablePreview ?? true) && !(Config.options?.dockToPanel?.enableTooltip ?? false) && !root.scratchpadOpen && (root.buttonHovered || previewPopup._popupHovered) && (root.lastHoveredButton?.appToplevel?.toplevels?.length ?? 0) > 0

        contentItem: RowLayout {
            spacing: 8
            Repeater {
                model: ScriptModel {
                    values: (root.lastHoveredButton?.appToplevel?.toplevels ?? []).slice(0, 4)
                }
                delegate: RippleButton {
                    id: winBtn
                    required property var modelData
                    required property int index
                    implicitWidth: screencopyView.implicitWidth + 12
                    implicitHeight: screencopyView.implicitHeight + 36
                    buttonRadius: Appearance.rounding.small

                    readonly property bool startAnim: previewPopup.opened && previewPopup.popupOpenProgress > 0.6

                    // A preview can join while the popup is already open (new window
                    // spawns); startAnim won't re-fire for it, so enter right away.
                    Component.onCompleted: {
                        if (startAnim) {
                            Qt.callLater(function() {
                                winBtnAnim.start();
                            });
                        }
                    }

                    onStartAnimChanged: {
                        if (startAnim) {
                            winBtn.opacity = 0.0;
                            winBtn.scale = 0.85;
                            winBtnTransform.y = 25;
                            Qt.callLater(function() {
                                winBtnAnim.start();
                            });
                        }
                    }

                    Connections {
                        target: previewPopup
                        function onPopupOpenProgressChanged() {
                            if (previewPopup.popupOpenProgress === 0.0) {
                                winBtnAnim.stop();
                                winBtn.opacity = 0.0;
                                winBtn.scale = 0.85;
                                winBtnTransform.y = 25;
                            }
                        }
                    }

                    opacity: 0.0
                    scale: 0.85
                    transform: Translate {
                        id: winBtnTransform
                        y: 25
                    }

                    SequentialAnimation {
                        id: winBtnAnim
                        PauseAnimation { duration: 40 + winBtn.index * 60 }
                        ParallelAnimation {
                            NumberAnimation { target: winBtn; property: "opacity"; to: 1.0; duration: 300 }
                            NumberAnimation { target: winBtn; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: winBtnTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        }
                    }

                    onClicked: {
                        modelData?.activate();
                        root.buttonHovered = false;
                    }
                    middleClickAction: () => modelData?.close()

                    contentItem: ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                text: winBtn.modelData?.title ?? ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurface
                            }
                            RippleButton {
                                implicitWidth: 18
                                implicitHeight: 18
                                buttonRadius: Appearance.rounding.full
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 12
                                    color: Appearance.colors.colOnSurface
                                }
                                onClicked: winBtn.modelData?.close()
                            }
                        }

                        ScreencopyView {
                            id: screencopyView
                            captureSource: winBtn.modelData
                            live: true
                            paintCursor: true
                            constraintSize: Qt.size(240, 150)
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