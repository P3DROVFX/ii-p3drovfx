pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.menu
import "TabletSplitGeometry.js" as SplitGeometry

/**
 * A pill in the gutter between tiled windows, like the divider of Android's split screen.
 *
 * Drag it to move the split; tap it for the actions a split needs — swap the two sides,
 * even them out, float one, close one. Hyprland's own resize is a pointer binding, so on a
 * tablet a tiled layout was fixed at whatever ratio it opened with.
 *
 * Only the pill is drawn. The whole length of the gutter still takes the finger, but the
 * gutter itself stays the wallpaper it is. Appearance widens `gaps_in` in this family to the
 * handle's width, so the compositor leaves exactly that space empty for it.
 *
 * A layer surface does not move with Hyprland's workspace animation — it would sit still
 * while the windows slide away and pop up in the middle of the next workspace. So on a
 * switch the old workspace's pills slide out and the new ones slide in, with the duration,
 * curve and direction Hyprland is using for the windows, read from `hyprctl animations`.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready && (Config.options?.tablet?.windows?.splitHandles ?? true)
                sourceComponent: PanelWindow {
                    id: handlesWindow

                    screen: screenScope.modelData
                    readonly property string screenName: handlesWindow.screen?.name ?? ""
                    readonly property var monitor: (HyprlandData.monitors ?? [])
                        .find(m => String(m?.name ?? "") === handlesWindow.screenName) ?? null
                    readonly property real originX: Number(handlesWindow.monitor?.x ?? 0)
                    readonly property real originY: Number(handlesWindow.monitor?.y ?? 0)
                    /// From the event stream, not `hyprctl monitors`: the slide has to start
                    /// when Hyprland's does, not a process round trip later.
                    readonly property int workspaceId: Hyprland.monitorFor(handlesWindow.screen)?.activeWorkspace?.id ?? -1
                    /// The pill's own width. The gutter is this plus the spacing on both sides —
                    /// Appearance.effectiveGapsIn asks Hyprland for exactly that.
                    readonly property real pillThickness: Math.max(4, Config.options?.tablet?.windows?.splitHandleWidth ?? 12)
                    readonly property real pillLength: 56

                    readonly property var workspaceWindows: (HyprlandData.windowList ?? []).filter(w => w
                        && Number(w.workspace?.id ?? -2) === handlesWindow.workspaceId
                        && w.hidden !== true && w.mapped !== false)
                    readonly property bool hasFullscreen: handlesWindow.workspaceWindows.some(w => (w.fullscreen ?? 0) > 0)
                    readonly property var tiled: handlesWindow.workspaceWindows.filter(w => !w.floating).map(w => ({
                        address: TabletWindowActions.normalizeAddress(w.address),
                        cls: String(w.class ?? ""),
                        title: String(w.title ?? ""),
                        x: w.at[0],
                        y: w.at[1],
                        width: w.size[0],
                        height: w.size[1]
                    }))
                    readonly property var dividers: SplitGeometry.dividers(handlesWindow.tiled, {
                        maxGap: Appearance.effectiveGapsIn * 2 + 8,
                        minOverlap: 96
                    })

                    /// Floating windows over this workspace, in surface coordinates. The pill is
                    /// on a layer above every window, so wherever a floating window covers it the
                    /// pill has to get out of the way — visually and for input.
                    readonly property var floatingRects: handlesWindow.workspaceWindows.filter(w => w.floating).map(w => ({
                        x: w.at[0] - handlesWindow.originX,
                        y: w.at[1] - handlesWindow.originY,
                        width: w.size[0],
                        height: w.size[1]
                    }))

                    function coveredByFloating(rect) {
                        return handlesWindow.floatingRects.some(r => rect.x < r.x + r.width && rect.x + rect.width > r.x
                            && rect.y < r.y + r.height && rect.y + rect.height > r.y);
                    }

                    /// Covered, counting the length a held pill grows to and a little air around it.
                    function dividerOccluded(divider, position) {
                        const rect = handlesWindow.pillRect(divider, position, 88);
                        return handlesWindow.coveredByFloating({ x: rect.x - 6, y: rect.y - 6, width: rect.width + 12, height: rect.height + 12 });
                    }

                    // Same list as the floating controls: a shell surface covers the windows,
                    // and handles for windows nobody can see are handles in the way.
                    readonly property bool shellSurfaceOpen: GlobalStates.appDrawerOpen
                        || GlobalStates.recentsOpen
                        || GlobalStates.dashboardPanelOpen
                        || GlobalStates.sessionOpen
                        || GlobalStates.screenLocked
                    readonly property bool shown: !handlesWindow.shellSurfaceOpen
                        && !handlesWindow.hasFullscreen
                        && handlesWindow.dividers.length > 0

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.namespace: "quickshell:tabletSplitHandles"
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    visible: !GlobalStates.screenLocked

                    // ── Input ───────────────────────────────────────────────
                    /// Registered by each handle, so the mask always matches what exists.
                    property var handleItems: []
                    readonly property bool menuOpen: handlesWindow.menuDivider !== null

                    // Handles add their hit areas; floating windows are then cut back out, so a
                    // floating window over the gutter keeps every touch that lands on it.
                    mask: Region {
                        item: handlesWindow.menuOpen ? menuCatcher : null
                        regions: handlesWindow.shown && !handlesWindow.menuOpen && !slideAnimation.running
                            ? handleRegions.instances.concat(floatingRegions.instances)
                            : []
                    }

                    Variants {
                        id: handleRegions
                        model: handlesWindow.handleItems.filter(item => !item.occluded)
                        delegate: Region {
                            required property var modelData
                            item: modelData
                        }
                    }

                    Variants {
                        id: floatingRegions
                        model: handlesWindow.floatingRects
                        delegate: Region {
                            required property var modelData
                            x: modelData.x
                            y: modelData.y
                            width: modelData.width
                            height: modelData.height
                            intersection: Intersection.Subtract
                        }
                    }

                    onShownChanged: {
                        if (!handlesWindow.shown)
                            handlesWindow.closeMenu();
                    }

                    // ── Workspace slide ─────────────────────────────────────
                    property bool slideEnabled: true
                    property int slideDuration: 700
                    property bool slideVertical: false
                    /// 1 for a full-screen slide; less for `slidefade`, 0 for a plain fade.
                    property real slideFraction: 1
                    property bool slideFades: false
                    property var slideCurve: [0.0, 0.75, 0.15, 1.0, 1, 1]
                    property int workspaceGap: 0

                    /// Where the new workspace comes from: +1 from the right (or below).
                    property int slideDirection: 1
                    property real slideProgress: 1
                    property var outgoingDividers: []
                    property int settledWorkspaceId: -1
                    /// The last pills each workspace showed, so the one being left can slide out.
                    property var dividersByWorkspace: ({})

                    readonly property real slideDistance: ((handlesWindow.slideVertical ? handlesWindow.height : handlesWindow.width)
                        + handlesWindow.workspaceGap) * handlesWindow.slideFraction
                    readonly property real incomingOffset: handlesWindow.slideDirection * handlesWindow.slideDistance * (1 - handlesWindow.slideProgress)
                    readonly property real outgoingOffset: -handlesWindow.slideDirection * handlesWindow.slideDistance * handlesWindow.slideProgress

                    NumberAnimation {
                        id: slideAnimation
                        target: handlesWindow
                        property: "slideProgress"
                        from: 0
                        to: 1
                        duration: handlesWindow.slideDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: handlesWindow.slideCurve
                        onFinished: handlesWindow.outgoingDividers = []
                    }

                    onDividersChanged: {
                        const record = Object.assign({}, handlesWindow.dividersByWorkspace);
                        record[handlesWindow.workspaceId] = handlesWindow.shown
                            ? handlesWindow.dividers.filter(d => !handlesWindow.dividerOccluded(d, d.position)) : [];
                        handlesWindow.dividersByWorkspace = record;
                    }

                    onWorkspaceIdChanged: {
                        const previous = handlesWindow.settledWorkspaceId;
                        handlesWindow.settledWorkspaceId = handlesWindow.workspaceId;
                        handlesWindow.closeMenu();
                        animationProbe.running = true;
                        if (previous < 1 || handlesWindow.workspaceId < 1 || !handlesWindow.slideEnabled) {
                            slideAnimation.stop();
                            handlesWindow.outgoingDividers = [];
                            handlesWindow.slideProgress = 1;
                            return;
                        }
                        handlesWindow.outgoingDividers = handlesWindow.dividersByWorkspace[previous] ?? [];
                        handlesWindow.slideDirection = handlesWindow.workspaceId > previous ? 1 : -1;
                        slideAnimation.restart();
                    }

                    Component.onCompleted: {
                        handlesWindow.settledWorkspaceId = handlesWindow.workspaceId;
                        animationProbe.running = true;
                    }

                    /// Hyprland's own workspace animation, so the pills keep time with windows.
                    Process {
                        id: animationProbe
                        command: ["bash", "-c", "hyprctl -j animations; echo '@@'; hyprctl -j getoption animations:enabled; echo '@@'; hyprctl -j getoption general:gaps_workspaces"]
                        stdout: StdioCollector {
                            id: animationCollector
                            onStreamFinished: handlesWindow.readAnimation(animationCollector.text)
                        }
                    }

                    function readAnimation(text) {
                        try {
                            const parts = text.split("@@");
                            const data = JSON.parse(parts[0]);
                            const leaves = data[0] ?? [];
                            const curves = data[1] ?? [];
                            const leaf = leaves.find(a => a.name === "workspacesIn" && a.overridden)
                                ?? leaves.find(a => a.name === "workspaces") ?? null;
                            const globallyOn = Number(JSON.parse(parts[1]).int ?? 1) !== 0;
                            handlesWindow.workspaceGap = Number(JSON.parse(parts[2]).int ?? 0) || 0;

                            const style = String(leaf?.style ?? "slide").trim();
                            const percent = /(\d+(?:\.\d+)?)%/.exec(style);
                            handlesWindow.slideEnabled = globallyOn && (leaf?.enabled ?? true);
                            handlesWindow.slideDuration = Math.max(50, Number(leaf?.speed ?? 7) * 100);
                            handlesWindow.slideVertical = style.indexOf("vert") !== -1;
                            handlesWindow.slideFades = style.indexOf("fade") !== -1;
                            handlesWindow.slideFraction = style.startsWith("slidefade")
                                ? (percent ? Number(percent[1]) / 100 : 0.2)
                                : (style.startsWith("fade") ? 0 : 1);

                            const curve = curves.find(c => c.name === leaf?.bezier);
                            handlesWindow.slideCurve = curve
                                ? [Number(curve.X0), Number(curve.Y0), Number(curve.X1), Number(curve.Y1), 1, 1]
                                : [0.0, 0.75, 0.15, 1.0, 1, 1];
                        } catch (e) {
                            // Keep the last good values: a slide slightly off Hyprland's beats none.
                        }
                    }

                    // ── Actions ─────────────────────────────────────────────
                    function windowFor(address) {
                        return handlesWindow.tiled.find(w => w.address === address) ?? null;
                    }

                    function nameOf(w) {
                        const entry = DesktopEntries.heuristicLookup(w?.cls ?? "");
                        return entry?.name || w?.cls || w?.title || "";
                    }

                    function applyResize(plan) {
                        for (const change of plan.resizes)
                            TabletWindowActions.resizeTo(change.address, change.width, change.height);
                    }

                    function swap(divider) {
                        const first = divider.before[0];
                        const second = divider.after[0];
                        if (!first || !second)
                            return;
                        Hyprland.dispatch(`hl.dsp.window.swap({ target = "address:${second}", window = "address:${first}" })`);
                        TabletWindowActions.requestGeometryRefresh();
                    }

                    function splitEvenly(divider) {
                        const plan = SplitGeometry.resizePlan(divider, handlesWindow.tiled,
                            SplitGeometry.evenPosition(divider, handlesWindow.tiled), handlesWindow.minimumSpan(divider));
                        handlesWindow.applyResize(plan);
                    }

                    function minimumSpan(divider) {
                        return divider.orientation === "vertical" ? TabletWindowActions.minimumWidth : TabletWindowActions.minimumHeight;
                    }

                    /// The pill's rect for a divider, in surface coordinates: centred in the gutter,
                    /// so the spacing either side of it is equal.
                    function pillRect(divider, position, length) {
                        const vertical = divider.orientation === "vertical";
                        const middle = (divider.start + divider.end) / 2;
                        const across = position + (divider.thickness - handlesWindow.pillThickness) / 2;
                        return vertical
                            ? { x: across - handlesWindow.originX, y: middle - handlesWindow.originY - length / 2, width: handlesWindow.pillThickness, height: length }
                            : { x: middle - handlesWindow.originX - length / 2, y: across - handlesWindow.originY, width: length, height: handlesWindow.pillThickness };
                    }

                    // ── Menu ────────────────────────────────────────────────
                    property var menuDivider: null
                    property real menuAnchorX: 0
                    property real menuAnchorY: 0

                    function openMenu(divider, anchorX, anchorY) {
                        const first = handlesWindow.windowFor(divider.before[0]);
                        const second = handlesWindow.windowFor(divider.after[0]);
                        const vertical = divider.orientation === "vertical";
                        const actions = [];
                        if (first && second) {
                            actions.push({
                                symbol: vertical ? "swap_horiz" : "swap_vert",
                                label: Translation.tr("Swap windows"),
                                trigger: () => handlesWindow.swap(divider)
                            });
                        }
                        actions.push({
                            symbol: vertical ? "vertical_split" : "horizontal_split",
                            label: Translation.tr("Split evenly"),
                            trigger: () => handlesWindow.splitEvenly(divider)
                        });
                        for (const w of [first, second]) {
                            if (!w)
                                continue;
                            actions.push({
                                symbol: "picture_in_picture_alt",
                                label: Translation.tr("Float") + " " + handlesWindow.nameOf(w),
                                trigger: () => TabletWindowActions.setFloating(w.address, true)
                            });
                        }
                        for (const w of [first, second]) {
                            if (!w)
                                continue;
                            actions.push({
                                symbol: "close",
                                label: Translation.tr("Close") + " " + handlesWindow.nameOf(w),
                                destructive: true,
                                trigger: () => TabletWindowActions.closeWindow(w.address)
                            });
                        }
                        menuCard.actions = actions;
                        handlesWindow.menuAnchorX = anchorX;
                        handlesWindow.menuAnchorY = anchorY;
                        handlesWindow.menuDivider = divider;
                        TransientLayerRegistry.push("tabletSplitMenu", () => handlesWindow.closeMenu());
                    }

                    function closeMenu() {
                        if (handlesWindow.menuDivider === null)
                            return;
                        handlesWindow.menuDivider = null;
                        TransientLayerRegistry.remove("tabletSplitMenu");
                    }

                    Component.onDestruction: TransientLayerRegistry.remove("tabletSplitMenu")

                    // ── The workspace being left ────────────────────────────
                    // Drawn only, never touched: these pills are on their way off screen.
                    Item {
                        anchors.fill: parent
                        visible: handlesWindow.outgoingDividers.length > 0
                        opacity: handlesWindow.slideFades ? 1 - handlesWindow.slideProgress : 1
                        transform: Translate {
                            x: handlesWindow.slideVertical ? 0 : handlesWindow.outgoingOffset
                            y: handlesWindow.slideVertical ? handlesWindow.outgoingOffset : 0
                        }

                        Repeater {
                            model: handlesWindow.outgoingDividers

                            delegate: Pill {
                                required property var modelData
                                readonly property var rect: handlesWindow.pillRect(modelData, modelData.position, handlesWindow.pillLength)
                                x: rect.x
                                y: rect.y
                                vertical: modelData.orientation === "vertical"
                                thickness: handlesWindow.pillThickness
                                active: false
                            }
                        }
                    }

                    // ── The workspace in front ──────────────────────────────
                    Item {
                        anchors.fill: parent
                        opacity: handlesWindow.slideFades && slideAnimation.running ? handlesWindow.slideProgress : 1
                        transform: Translate {
                            x: handlesWindow.slideVertical ? 0 : handlesWindow.incomingOffset
                            y: handlesWindow.slideVertical ? handlesWindow.incomingOffset : 0
                        }

                        Repeater {
                            model: ScriptModel {
                                objectProp: "key"
                                values: handlesWindow.dividers
                            }

                            delegate: Item {
                                id: handle
                                required property var modelData

                                /// The live divider for this key: the model keeps the delegate,
                                /// this keeps its geometry current.
                                readonly property var divider: handlesWindow.dividers.find(d => d.key === handle.modelData.key) ?? handle.modelData
                                readonly property bool vertical: handle.divider.orientation === "vertical"
                                readonly property real thickness: handle.divider.thickness

                                /// Where the finger has put the divider, in layout coordinates, or
                                /// -1 for "where Hyprland says it is".
                                property real dragPosition: -1
                                readonly property real position: handle.dragPosition >= 0 ? handle.dragPosition : handle.divider.position
                                readonly property bool active: handleArea.pressed || handlesWindow.menuDivider?.key === handle.divider.key
                                /// Wider than the gutter: a 12px target is not a target.
                                readonly property real hitSpan: Math.max(Appearance.sizes.minimumTouchTarget, handle.thickness + 28)

                                x: handle.vertical
                                    ? handle.position - handlesWindow.originX + handle.thickness / 2 - handle.hitSpan / 2
                                    : handle.divider.start - handlesWindow.originX
                                y: handle.vertical
                                    ? handle.divider.start - handlesWindow.originY
                                    : handle.position - handlesWindow.originY + handle.thickness / 2 - handle.hitSpan / 2
                                width: handle.vertical ? handle.hitSpan : handle.divider.end - handle.divider.start
                                height: handle.vertical ? handle.divider.end - handle.divider.start : handle.hitSpan

                                /// A floating window is over the pill: hide it and stop taking input,
                                /// or it draws on top of that window and steals its touches.
                                readonly property bool occluded: handlesWindow.dividerOccluded(handle.divider, handle.position)
                                enabled: !handle.occluded
                                opacity: handlesWindow.shown && !handle.occluded ? 1 : 0

                                Component.onCompleted: handlesWindow.handleItems = handlesWindow.handleItems.concat([handle])
                                Component.onDestruction: handlesWindow.handleItems = handlesWindow.handleItems.filter(item => item !== handle)

                                // Follows the windows when Hyprland resizes them; under the finger
                                // it has to be exactly where the finger is. Off during a workspace
                                // slide, which already moves the whole layer.
                                Behavior on x {
                                    enabled: handle.dragPosition < 0 && !slideAnimation.running
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(handle)
                                }
                                Behavior on y {
                                    enabled: handle.dragPosition < 0 && !slideAnimation.running
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(handle)
                                }
                                Behavior on width {
                                    enabled: handle.dragPosition < 0 && !slideAnimation.running
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(handle)
                                }
                                Behavior on height {
                                    enabled: handle.dragPosition < 0 && !slideAnimation.running
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(handle)
                                }
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(handle)
                                }

                                /// Hold the dragged position until the report agrees with it, so
                                /// the pill does not jump back to the old split for a frame.
                                readonly property real reportedPosition: handle.divider.position
                                onReportedPositionChanged: {
                                    if (!handleArea.pressed && handle.dragPosition >= 0
                                            && Math.abs(handle.reportedPosition - handle.dragPosition) <= 3)
                                        handle.dragPosition = -1;
                                }

                                Timer {
                                    id: settleTimeout
                                    interval: 700
                                    onTriggered: handle.dragPosition = -1
                                }

                                /// One resize per frame at most.
                                Timer {
                                    id: commitTimer
                                    interval: 32
                                    property var plan: null
                                    onTriggered: {
                                        if (commitTimer.plan)
                                            handlesWindow.applyResize(commitTimer.plan);
                                    }
                                }

                                Pill {
                                    id: grip
                                    anchors.centerIn: parent
                                    vertical: handle.vertical
                                    thickness: handlesWindow.pillThickness
                                    active: handle.active
                                }

                                MouseArea {
                                    id: handleArea
                                    anchors.fill: parent
                                    preventStealing: true
                                    cursorShape: handle.vertical ? Qt.SplitHCursor : Qt.SplitVCursor

                                    property real pressCoordinate: 0
                                    property real originPosition: 0
                                    property bool moved: false

                                    onPressed: mouse => {
                                        const point = handleArea.mapToItem(null, mouse.x, mouse.y);
                                        handleArea.pressCoordinate = handle.vertical ? point.x : point.y;
                                        handleArea.originPosition = handle.position;
                                        handleArea.moved = false;
                                        settleTimeout.stop();
                                    }

                                    onPositionChanged: mouse => {
                                        if (!handleArea.pressed)
                                            return;
                                        const point = handleArea.mapToItem(null, mouse.x, mouse.y);
                                        const delta = (handle.vertical ? point.x : point.y) - handleArea.pressCoordinate;
                                        if (!handleArea.moved && Math.abs(delta) < 8)
                                            return;
                                        if (!handleArea.moved) {
                                            handleArea.moved = true;
                                            handlesWindow.closeMenu();
                                        }
                                        const plan = SplitGeometry.resizePlan(handle.divider, handlesWindow.tiled,
                                            handleArea.originPosition + delta, handlesWindow.minimumSpan(handle.divider));
                                        handle.dragPosition = plan.position;
                                        commitTimer.plan = plan;
                                        if (!commitTimer.running)
                                            commitTimer.start();
                                    }

                                    onReleased: mouse => {
                                        if (handleArea.moved) {
                                            commitTimer.stop();
                                            if (commitTimer.plan)
                                                handlesWindow.applyResize(commitTimer.plan);
                                            commitTimer.plan = null;
                                            settleTimeout.restart();
                                            return;
                                        }
                                        if (handlesWindow.menuDivider?.key === handle.divider.key) {
                                            handlesWindow.closeMenu();
                                            return;
                                        }
                                        const center = grip.mapToItem(null, grip.width / 2, grip.height / 2);
                                        handlesWindow.openMenu(handle.divider, center.x, center.y);
                                    }

                                    onCanceled: {
                                        commitTimer.stop();
                                        commitTimer.plan = null;
                                        handle.dragPosition = -1;
                                    }
                                }
                            }
                        }
                    }

                    // ── Menu surface ────────────────────────────────────────
                    MouseArea {
                        id: menuCatcher
                        anchors.fill: parent
                        enabled: handlesWindow.menuOpen
                        onClicked: handlesWindow.closeMenu()
                    }

                    TabletMenuCard {
                        id: menuCard
                        readonly property real margin: 16
                        readonly property bool fitsRight: handlesWindow.menuAnchorX + 28 + menuCard.width + menuCard.margin <= handlesWindow.width

                        x: menuCard.fitsRight
                            ? handlesWindow.menuAnchorX + 28
                            : Math.max(menuCard.margin, handlesWindow.menuAnchorX - 28 - menuCard.width)
                        y: Math.max(menuCard.margin, Math.min(handlesWindow.height - menuCard.height - menuCard.margin,
                            handlesWindow.menuAnchorY - menuCard.height / 2))

                        headerText: Translation.tr("Split view")
                        headerSymbol: "splitscreen"
                        useDynamicRadius: true
                        menuWidth: 320
                        maximumHeight: handlesWindow.height - menuCard.margin * 2

                        opacity: handlesWindow.menuOpen ? 1 : 0
                        scale: handlesWindow.menuOpen ? 1 : 0.9
                        transformOrigin: menuCard.fitsRight ? Item.Left : Item.Right
                        visible: opacity > 0.01

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(menuCard)
                        }
                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(menuCard)
                        }

                        onActionTriggered: handlesWindow.closeMenu()
                    }
                }
            }
        }
    }

    /// The only visible part of a handle: a pill with three dots, lit while held.
    /// Takes everything as properties — an inline component does not see the file's ids.
    component Pill: Rectangle {
        id: pill
        property bool vertical: true
        property real thickness: 12
        property bool active: false
        readonly property real length: pill.active ? 88 : 56

        width: pill.vertical ? pill.thickness : pill.length
        height: pill.vertical ? pill.length : pill.thickness
        radius: Appearance.rounding.full
        color: pill.active ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pill)
        }
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pill)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pill)
        }

        Grid {
            anchors.centerIn: parent
            columns: pill.vertical ? 1 : 3
            spacing: 4

            Repeater {
                model: 3
                delegate: Rectangle {
                    width: Math.max(3, Math.min(5, pill.thickness - 6))
                    height: width
                    radius: Appearance.rounding.full
                    color: pill.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }
}
