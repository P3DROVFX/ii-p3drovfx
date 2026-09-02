import QtQuick
import qs
import qs.modules.common
import qs.modules.common.functions

MouseArea {
    id: root

    readonly property bool isWidgetCanvas: true
    property real snapLineX: -1
    property real snapLineY: -1
    property bool draggingActive: false
    property bool gridOverlayEnabled: false
    property int alignmentGridStep: 10
    onAlignmentGridStepChanged: dotGrid.requestPaint()

    // The area the lattice belongs to, and the corner it is cut to, in canvas
    // coordinates. Edit Mode shrinks the desktop into a rounded card, and a
    // square lattice would spill out past its corners; the host hands the card
    // in so the dots stop where the card does. Left alone it is the whole
    // canvas with no corner, which paints exactly as it always did.
    property rect gridCardRect: Qt.rect(0, 0, root.width, root.height)
    property real gridCardRadius: 0

    // Handed in by the surface that owns this canvas - the desktop's, and only
    // the desktop's. The overlay reuses this component and has its own
    // dismissal, so it must not follow the mode.
    property bool editMode: false

    // ── Selection ────────────────────────────────────────────────────────────
    // Marquee multi-select. Opt-in per canvas: the overlay's canvas closes
    // itself on a plain click, so a marquee defaulting on would turn every
    // dismiss-click into a selection gesture. The desktop widgets window is
    // the one canvas that opts in.
    //
    // The selection is session state on this canvas - it does not survive a
    // reload, cannot leak across monitors (each window owns its canvas), and
    // is never persisted anywhere.
    property bool selectionEnabled: false
    property var selectedWidgets: []
    property bool marqueeActive: false
    property real marqueeAnchorX: 0
    property real marqueeAnchorY: 0

    // A widget's right-click, announced rather than handled: the canvas knows
    // nothing about what a widget is, and the surface owning the canvas
    // decides what a menu about it looks like. Canvas coordinates.
    signal contextMenuRequested(string instanceId, real atX, real atY)
    // A right-click that landed on no widget: the desktop's own menu.
    signal canvasContextMenuRequested(real atX, real atY)
    // A long press on the wallpaper, from a touch screen: the way into Edit
    // Mode for a hand that has no right button and no Super key.
    signal canvasLongPressed()
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    TapHandler {
        acceptedDevices: PointerDevice.TouchScreen
        gesturePolicy: TapHandler.WithinBounds
        onLongPressed: {
            if (root.editMode || root.draggingWidget() !== null)
                return;
            root.canvasLongPressed();
        }
    }

    // The selection, taken off the desktop - one history entry for the lot.
    function removeSelection() {
        const ids = [];
        for (const widget of root.selectedWidgets) {
            if (widget && widget.widgetInstance && widget.widgetInstance.id)
                ids.push(widget.widgetInstance.id);
        }
        if (ids.length === 0)
            return;
        root.flushNudge();
        root.clearSelection();
        GlobalStates.editHistoryBeginBatch();
        for (const id of ids)
            Config.removeWidgetInstance(id);
        GlobalStates.editHistoryEndBatch();
    }

    // One more of each selected widget, beside its original.
    function duplicateSelection() {
        const members = [];
        for (const widget of root.selectedWidgets) {
            if (widget && widget.widgetInstance && widget.widgetInstance.id)
                members.push({ "id": widget.widgetInstance.id, "monitor": widget.widgetInstance.monitorName ?? "" });
        }
        if (members.length === 0)
            return;
        root.flushNudge();
        GlobalStates.editHistoryBeginBatch();
        for (const member of members)
            Config.duplicateWidgetInstance(member.id, member.monitor);
        GlobalStates.editHistoryEndBatch();
    }

    // The desktop's layer surface only takes keys while it is OnDemand; the
    // owning window reads this to arm it. A live selection needs the arrows
    // and Escape, the mode needs its keys throughout.
    readonly property bool keyboardFocusHeld: root.selectedWidgets.length > 0 || root.editMode
    onKeyboardFocusHeldChanged: {
        if (root.keyboardFocusHeld)
            root.forceActiveFocus();
    }
    focus: root.selectionEnabled

    // The global lock clears the selection unless the mode suppresses it: two
    // widgets still haloed under a lock would look live while doing nothing.
    readonly property bool positionsLocked: Config.options.background.widgets.lockWidgetPositions ?? false
    onPositionsLockedChanged: {
        if (root.positionsLocked && !root.editMode)
            root.clearSelection();
    }

    // Leaving the mode mid-drag cancels the gesture - it cannot commit, the
    // mode ending is not the user letting go. The selection goes with it: a
    // halo surviving the mode is a marquee with no visible way to clear it.
    onEditModeChanged: {
        if (root.editMode)
            return;
        root.cancelActiveDrag();
        root.clearSelection();
    }

    // The lock screen borrows this surface as its backdrop; a selection halo
    // has no business there, and a drag cannot outlive the desktop it was on.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked)
                return;
            root.cancelActiveDrag();
            root.clearSelection();
        }
    }

    // ── Keys ─────────────────────────────────────────────────────────────────
    // The arrows are not gated on the mode: selecting a widget is what takes
    // this surface's keyboard focus, in the mode and out of it, so a
    // selection the user can make is a selection they can move. Outside the
    // mode the move still commits and simply records no history entry, which
    // is the existing grain: a drag outside the mode is unrecorded too.
    Keys.onPressed: event => {
        // Ctrl+Z / Ctrl+Shift+Z, by keysym so AZERTY's physical Z works.
        // Auto-repeat is dropped: every step is a config write, and a held
        // key would queue writes faster than the file's own reload settles.
        if (root.editMode && event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = true;
            if (event.isAutoRepeat)
                return;
            if (event.modifiers & Qt.ShiftModifier)
                GlobalStates.editRedo();
            else
                GlobalStates.editUndo();
            return;
        }
        // Ctrl+F opens the catalogue and puts the caret in its search field.
        // The field is on the chrome's surface, which holds no keyboard until
        // it asks for one, so the request travels rather than the key.
        if (root.editMode && event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = true;
            if (event.isAutoRepeat)
                return;
            GlobalStates.editDrawerOpen = true;
            GlobalStates.editSearchFocusRequested();
            return;
        }
        // Delete takes the selection off; Ctrl+D doubles it. By keysym, like
        // Ctrl+Z above, so the layout does not matter; auto-repeat dropped so
        // a held key is one edit.
        if (root.editMode && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
            && root.selectedWidgets.length > 0) {
            event.accepted = true;
            if (event.isAutoRepeat)
                return;
            root.removeSelection();
            return;
        }
        if (root.editMode && event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)
            && root.selectedWidgets.length > 0) {
            event.accepted = true;
            if (event.isAutoRepeat)
                return;
            root.duplicateSelection();
            return;
        }
        const nudge = WidgetNudge.direction(event.key, root.arrowKeys);
        if (!nudge || root.selectedWidgets.length === 0)
            return;
        root.nudgeSelection(nudge.dx, nudge.dy);
        event.accepted = true;
    }
    // Escape is overloaded: it cancels a drag in flight and clears a
    // selection, and the mode may take it for its own exit only once neither
    // applies. EditModeLogic.resolveEscape owns that precedence.
    Keys.onEscapePressed: event => {
        const action = EditModeLogic.resolveEscape({
            "menuOpen": (GlobalStates.editWidgetMenuOpen && GlobalStates.editWidgetMenuCanvas === root) || GlobalStates.editBarMenuOpen,
            "desktopMenuOpen": GlobalStates.desktopMenuOpen,
            "drawerOpen": root.editMode && GlobalStates.editDrawerOpen,
            "gestureInFlight": root.draggingWidget() !== null || GlobalStates.editBarDragActive,
            "selectionCount": root.selectedWidgets.length,
            "tab": EditModeLogic.desktopTab
        });
        if (action === "closeMenu") {
            GlobalStates.closeEditWidgetMenu();
            GlobalStates.closeEditBarMenu();
            GlobalStates.closeDesktopMenu();
        }
        else if (action === "closeDrawer")
            GlobalStates.editDrawerOpen = false;
        else if (action === "cancelGesture") {
            root.cancelActiveDrag();
            GlobalStates.editBarDragCancel();
        }
        else if (action === "clearSelection")
            root.clearSelection();
        else if (action === "exit" && root.editMode)
            GlobalStates.editMode = false;
        else
            return;
        event.accepted = true;
    }
    // The four keys, named once. The module takes them as an argument rather
    // than reaching for Qt itself, because a `.pragma library` has no engine
    // context.
    readonly property var arrowKeys: ({
        "left": Qt.Key_Left,
        "right": Qt.Key_Right,
        "up": Qt.Key_Up,
        "down": Qt.Key_Down
    })

    // ── Arrow-key nudge ──────────────────────────────────────────────────────
    // One press moves the selection one lattice cell, rigidly: the delta is
    // decided by the first selected widget and shrunk to what every member's
    // own clamp allows, so a cluster stops at the first wall instead of
    // deforming against it. The first press of a run also puts an off-lattice
    // widget back on the lattice (WidgetNudge.step).
    //
    // The run is committed once, a beat after its last press, rather than per
    // press: auto-repeat delivers a press every ~30 ms, and a config write
    // each would both fill the undo stack (one Ctrl+Z per repeat) and run
    // into the config file's own reload, which clobbers writes made within
    // ~250 ms of each other. The widgets move immediately; only the store
    // waits. A key repeat has no release to hang the commit on, which is why
    // it is a timer and not a release handler.
    property var _nudgeRun: null
    Timer {
        id: nudgeCommit
        interval: 400
        repeat: false
        onTriggered: root.flushNudge()
    }

    function nudgeSelection(dirX, dirY) {
        const lattice = Math.max(1, root.alignmentGridStep);
        if (root._nudgeRun === null) {
            const members = [];
            for (const widget of root.selectedWidgets) {
                if (!widget || !widget.draggable || !widget.nudgeTo)
                    continue;
                members.push({
                    "widget": widget,
                    "x": widget.targetX,
                    "y": widget.targetY
                });
            }
            if (members.length === 0)
                return;
            root._nudgeRun = {
                "members": members
            };
        }
        const members = root._nudgeRun.members;
        if (members.length === 0)
            return;
        const leader = members[0];
        // Where the leader would land: a whole cell along, snapped back onto
        // the lattice. Every member then travels by that difference, so the
        // cluster keeps its shape.
        const wantX = dirX === 0 ? leader.x : WidgetNudge.step(leader.x, dirX * lattice, lattice, 0);
        const wantY = dirY === 0 ? leader.y : WidgetNudge.step(leader.y, dirY * lattice, lattice, 0);
        // Each member's own bounds, asked of its own clamp rather than
        // recomputed here: the widgets differ in size.
        const bounded = WidgetNudge.groupDelta(members.map(m => ({
            "x": m.x,
            "y": m.y,
            "minX": m.widget.dragMinimumX(),
            "maxX": m.widget.dragMaximumX(),
            "minY": m.widget.dragMinimumY(),
            "maxY": m.widget.dragMaximumY()
        })), wantX - leader.x, wantY - leader.y);
        nudgeCommit.restart();
        if (bounded.dx === 0 && bounded.dy === 0)
            return;
        for (const m of members) {
            m.x += bounded.dx;
            m.y += bounded.dy;
            m.widget.nudgeTo(m.x, m.y);
        }
    }

    // Commit the run: every member's new position in one history entry, so a
    // held key is one Ctrl+Z. Also called when something else needs the store
    // current - a drag starting, the selection changing.
    function flushNudge() {
        nudgeCommit.stop();
        const run = root._nudgeRun;
        root._nudgeRun = null;
        if (run === null)
            return;
        GlobalStates.editHistoryBeginBatch();
        for (const m of run.members) {
            if (m.widget && m.widget.commitPlacement)
                m.widget.commitPlacement(m.x, m.y);
        }
        GlobalStates.editHistoryEndBatch();
    }

    // ── Selection set ────────────────────────────────────────────────────────
    // Widgets are found by walking the subtree rather than kept in a registry:
    // each one sits inside its own FadeLoader, and a registry filled from
    // Component.onCompleted would depend on the loader having parented the
    // widget under the canvas by then.
    // The widget item behind an instance id, for the menu that acts on it;
    // null once the widget is gone.
    function widgetById(instanceId) {
        const all = root.widgetsUnder(root, []);
        for (let i = 0; i < all.length; i++) {
            const inst = all[i].widgetInstance;
            if (inst && inst.id === instanceId)
                return all[i];
        }
        return null;
    }

    function widgetsUnder(item, found) {
        const children = item.children;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (child.isCanvasWidget === true)
                found.push(child);
            else
                root.widgetsUnder(child, found);
        }
        return found;
    }

    // The widget's drawn box in canvas coordinates: its Item scale is applied
    // around its centre, so the visual bounds differ from x/y/width/height by
    // the offsets AbstractBackgroundWidget publishes.
    function widgetVisualRect(widget) {
        const pos = widget.parent.mapToItem(root, widget.x, widget.y);
        return Qt.rect(pos.x + (widget.visualLeftOffset ?? 0), pos.y + (widget.visualTopOffset ?? 0), widget.visualWidth ?? widget.width, widget.visualHeight ?? widget.height);
    }

    // `draggable` is the selection filter on purpose: it already folds in
    // everything that must exclude a widget from a group move - the global
    // lock, a pin, a preview, a non-free placement strategy. Filtering on
    // anything narrower re-opens one of those.
    function selectWidgetsInRect(rect) {
        const picked = [];
        for (const widget of root.widgetsUnder(root, [])) {
            if (!widget.draggable || !widget.visible)
                continue;
            const box = root.widgetVisualRect(widget);
            if (box.x < rect.x + rect.width && box.x + box.width > rect.x && box.y < rect.y + rect.height && box.y + box.height > rect.y)
                picked.push(widget);
        }
        root.applySelection(picked);
    }

    function applySelection(widgets) {
        root.flushNudge();
        for (const widget of root.selectedWidgets) {
            if (widget && widgets.indexOf(widget) === -1)
                widget.selected = false;
        }
        for (const widget of widgets)
            widget.selected = true;
        root.selectedWidgets = widgets;
    }

    function clearSelection() {
        if (root.selectedWidgets.length === 0)
            return;
        root.applySelection([]);
    }

    // ── Align and distribute ─────────────────────────────────────────────────
    // The selection could be moved as a rigid cluster and nothing else. Putting
    // three widgets on one line meant dragging each of them at a dot grid until
    // they looked right, which is the job an editor is supposed to do for you.
    //
    // The arithmetic is in widget_align.js, for the same reason the nudge's is:
    // nothing about a rendered widget is reachable from a test, so where each
    // member lands has to live somewhere that can be called without one.

    // The selection's drawn bounds, in canvas coordinates. A binding rather
    // than a function so the toolbar over it follows a group drag: reading
    // each member's x/y here is what makes this re-run when they move.
    readonly property rect selectionRect: {
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const widget of root.selectedWidgets) {
            if (!widget || !widget.visible)
                continue;
            const box = root.widgetVisualRect(widget);
            minX = Math.min(minX, box.x);
            minY = Math.min(minY, box.y);
            maxX = Math.max(maxX, box.x + box.width);
            maxY = Math.max(maxY, box.y + box.height);
        }
        if (!isFinite(minX))
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(minX, minY, maxX - minX, maxY - minY);
    }

    // Members in the shape widget_align.js wants: the DRAWN box, the STORED
    // coordinate, and each widget's own clamp. The two coordinates differ for
    // a scaled widget, which is why the module answers in deltas.
    function alignMembers() {
        const members = [];
        for (let i = 0; i < root.selectedWidgets.length; i++) {
            const widget = root.selectedWidgets[i];
            if (!widget || !widget.draggable || !widget.commitPlacement)
                continue;
            members.push({
                "id": widget.widgetInstance ? widget.widgetInstance.id : ("member" + i),
                "widget": widget,
                "x": widget.targetX,
                "y": widget.targetY,
                "box": root.widgetVisualRect(widget),
                "minX": widget.dragMinimumX(),
                "maxX": widget.dragMaximumX(),
                "minY": widget.dragMinimumY(),
                "maxY": widget.dragMaximumY()
            });
        }
        return members;
    }

    function alignSelection(mode) {
        root.flushNudge();
        const members = root.alignMembers();
        const moves = WidgetAlign.deltas(members, mode);
        // One gesture, one Ctrl+Z, however many widgets it moved.
        GlobalStates.editHistoryBeginBatch();
        for (const member of members) {
            const move = moves[member.id];
            if (!move)
                continue;
            // Only the commit: the widget re-reads its own placement and
            // slides there through the position Behavior it already has, so
            // asking it to draw the move as well would be the same movement
            // written twice.
            member.widget.commitPlacement(member.x + move.dx, member.y + move.dy);
        }
        GlobalStates.editHistoryEndBatch();
    }

    // A widget destroyed while selected or mid-drag never reaches its own
    // release, so the canvas drops it here (the widget calls this from
    // Component.onDestruction).
    function widgetRemoved(widget) {
        if (widget.isDragging)
            root.draggingActive = false;
        const idx = root.selectedWidgets.indexOf(widget);
        if (idx !== -1) {
            const next = root.selectedWidgets.slice();
            next.splice(idx, 1);
            root.selectedWidgets = next;
        }
        if (root._nudgeRun !== null)
            root._nudgeRun.members = root._nudgeRun.members.filter(m => m.widget !== widget);
        const group = root.groupDrag;
        if (group && (group.leader === widget || group.followers.some(entry => entry.widget === widget)))
            root.groupDrag = null;
    }

    // A press that starts on a widget is that widget's drag and never reaches
    // this handler. A press on empty canvas anchors the marquee; releasing it
    // replaces the selection with whatever the band covered, so a plain click
    // - a zero-size band over nothing - is the click-away deselect.
    onPressed: mouse => {
        // A press on the desktop lets the catalogue's search field go. The
        // field is on another surface, holding the keyboard exclusively, so no
        // click can take it away by itself.
        if (GlobalStates.editSearchFocused)
            GlobalStates.editSearchReleaseRequested();
        if (mouse.button === Qt.RightButton) {
            root.canvasContextMenuRequested(mouse.x, mouse.y);
            return;
        }
        if (!root.selectionEnabled || mouse.button !== Qt.LeftButton)
            return;
        // The mode subtracts the global lock rather than writing it: the
        // stored preference is untouched and the desktop is locked again on
        // the way out.
        if (root.positionsLocked && !root.editMode)
            return;
        root.marqueeAnchorX = mouse.x;
        root.marqueeAnchorY = mouse.y;
        root.marqueeActive = true;
    }
    onReleased: {
        if (!root.marqueeActive)
            return;
        root.marqueeActive = false;
        root.selectWidgetsInRect(Qt.rect(marqueeRect.x, marqueeRect.y, marqueeRect.width, marqueeRect.height));
    }
    onCanceled: root.marqueeActive = false

    // ── Group drag ───────────────────────────────────────────────────────────
    // Dragging any selected widget (the leader) moves the whole selection by
    // one delta. The leader reports its press and release; followers are moved
    // here by the leader's travel and committed here, through the same store
    // write a release runs - a follower never gets a release event.
    property var groupDrag: null

    function widgetDragStarted(widget) {
        root.flushNudge();
        // Escape has to reach this surface while the pointer is down.
        root.forceActiveFocus();
        if (root.selectedWidgets.indexOf(widget) === -1) {
            // Grabbing a widget outside the selection is a click-away.
            root.clearSelection();
            return;
        }
        // Re-filtered: a member may have been pinned or locked since it was
        // selected. It keeps its halo, it just does not move.
        const members = root.selectedWidgets.filter(member => member && member.draggable);
        let deltaMinX = -Infinity;
        let deltaMaxX = Infinity;
        let deltaMinY = -Infinity;
        let deltaMaxY = Infinity;
        const followers = [];
        for (const member of members) {
            // Each member's own clamp, in its own frame: the bounds are how
            // far it may travel, and the group may travel no further than its
            // tightest member.
            deltaMinX = Math.max(deltaMinX, member.dragMinimumX() - member.x);
            deltaMaxX = Math.min(deltaMaxX, member.dragMaximumX() - member.x);
            deltaMinY = Math.max(deltaMinY, member.dragMinimumY() - member.y);
            deltaMaxY = Math.min(deltaMaxY, member.dragMaximumY() - member.y);
            if (member !== widget) {
                member.groupDragging = true;
                followers.push({
                    "widget": member,
                    "startX": member.x,
                    "startY": member.y
                });
            }
        }
        widget.groupDragMinX = widget.x + deltaMinX;
        widget.groupDragMaxX = widget.x + deltaMaxX;
        widget.groupDragMinY = widget.y + deltaMinY;
        widget.groupDragMaxY = widget.y + deltaMaxY;
        root.groupDrag = {
            "leader": widget,
            "startX": widget.x,
            "startY": widget.y,
            "followers": followers
        };
    }

    function syncGroupFollowers() {
        const group = root.groupDrag;
        if (group === null)
            return;
        const deltaX = group.leader.x - group.startX;
        const deltaY = group.leader.y - group.startY;
        for (const entry of group.followers) {
            entry.widget.x = entry.startX + deltaX;
            entry.widget.y = entry.startY + deltaY;
        }
    }

    Connections {
        target: root.groupDrag ? root.groupDrag.leader : null
        function onXChanged() {
            root.syncGroupFollowers();
        }
        function onYChanged() {
            root.syncGroupFollowers();
        }
    }

    // Called by the leader after it has landed and before it commits itself.
    // The landing point is passed in rather than read back off the leader: the
    // leader is told where it lands and may still be drawing its way there, and
    // a follower placed from a position that is still moving keeps whatever of
    // the gesture had not been drawn yet as a permanent offset - the cluster
    // lands out of shape.
    function widgetDragEnded(widget, finalX, finalY) {
        const group = root.groupDrag;
        if (group && group.leader === widget)
            root.groupDrag = null;
        widget.groupDragMinX = -Infinity;
        widget.groupDragMaxX = Infinity;
        widget.groupDragMinY = -Infinity;
        widget.groupDragMaxY = Infinity;
        if (!group || group.leader !== widget)
            return;
        // One gesture, one undo entry: every follower's commit below and the
        // leader's own - which runs after this returns, later in the same
        // release - collect into one batch, closed a turn later so the
        // leader's push cannot miss it. Without this the leader's entry sits
        // on top and the first Ctrl+Z would move the leader alone.
        GlobalStates.editHistoryBeginBatch();
        Qt.callLater(() => GlobalStates.editHistoryEndBatch());
        const deltaX = (finalX === undefined ? group.leader.x : finalX) - group.startX;
        const deltaY = (finalY === undefined ? group.leader.y : finalY) - group.startY;
        for (const entry of group.followers) {
            const landedX = entry.startX + deltaX;
            const landedY = entry.startY + deltaY;
            entry.widget.x = landedX;
            entry.widget.y = landedY;
            if (entry.widget.commitPlacement)
                entry.widget.commitPlacement(landedX, landedY);
            // Last: the flag is what holds the follower's own position
            // animation off, and the placement above is not a move to animate.
            entry.widget.groupDragging = false;
        }
    }

    // The cancel half: followers go back where the press found them, the
    // leader's bounds are handed back, and nothing is written.
    function widgetDragCancelled(widget) {
        const group = root.groupDrag;
        if (group && group.leader === widget)
            root.groupDrag = null;
        widget.groupDragMinX = -Infinity;
        widget.groupDragMaxX = Infinity;
        widget.groupDragMinY = -Infinity;
        widget.groupDragMaxY = Infinity;
        if (!group || group.leader !== widget)
            return;
        for (const entry of group.followers) {
            entry.widget.groupDragging = false;
            entry.widget.x = entry.startX;
            entry.widget.y = entry.startY;
        }
    }

    function draggingWidget() {
        for (const widget of root.widgetsUnder(root, [])) {
            if (widget.isDragging)
                return widget;
        }
        return null;
    }

    function cancelActiveDrag() {
        const widget = root.draggingWidget();
        if (widget && widget.cancelDrag)
            widget.cancelDrag();
    }

    Canvas {
        id: dotGrid
        anchors.fill: parent
        z: -1
        // The lattice shows for a drag, and throughout the mode: in the mode
        // the desktop is being laid out, and the grid is what it is laid out on.
        readonly property bool wanted: (root.draggingActive || root.editMode) && root.gridOverlayEnabled
        visible: wanted && opacity > 0.001
        opacity: wanted ? 0.55 : 0

        readonly property real dotSize: 1.5
        readonly property color dotColor: Appearance.colors.colPrimary

        // Uniform on purpose. A radial falloff around the dragged widget was
        // tried and reverted: it repainted this full-screen canvas on every
        // pointer frame with a per-dot alpha, which is ~20k Qt.rgba allocations
        // and fillStyle switches per frame — the grid could not keep up and
        // read as simply missing. Painted once per size/step change, it costs
        // nothing while you drag.

        // The card, and how far into a row the corner has eaten. Solved per row
        // rather than per dot: one square root a row instead of ~200 distance
        // tests, so the corner costs nothing on top of the loop that was
        // already here.
        readonly property rect card: root.gridCardRect
        readonly property real cardRadius: Math.max(0, Math.min(root.gridCardRadius, Math.min(card.width, card.height) / 2))

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = dotGrid.dotColor;

            const offset = dotGrid.dotSize / 2;
            const step = Math.max(1, root.alignmentGridStep);
            const left = dotGrid.card.x;
            const top = dotGrid.card.y;
            const right = left + dotGrid.card.width;
            const bottom = top + dotGrid.card.height;
            const radius = dotGrid.cardRadius;

            for (let y = 0; y <= height; y += step) {
                if (y < top || y > bottom)
                    continue;
                // How deep this row sits inside the corner's band, and so how
                // far the arc has pulled the row's ends in.
                const depth = Math.max(0, Math.max(top + radius - y, y - (bottom - radius)));
                if (depth > radius)
                    continue;
                const inset = depth > 0 ? radius - Math.sqrt(Math.max(0, radius * radius - depth * depth)) : 0;
                const rowLeft = left + inset;
                const rowRight = right - inset;
                for (let x = 0; x <= width; x += step) {
                    if (x < rowLeft || x > rowRight)
                        continue;
                    ctx.fillRect(x - offset, y - offset, dotGrid.dotSize, dotGrid.dotSize);
                }
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onDotColorChanged: requestPaint()
        onCardChanged: requestPaint()
        // Whole pixels only: the corner grows with the shrink, and repainting a
        // full-screen lattice on every sub-pixel step of that animation is a
        // hitch nobody asked for.
        property int roundedRadius: Math.round(cardRadius)
        onRoundedRadiusChanged: requestPaint()
        onVisibleChanged: {
            if (visible)
                requestPaint();
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // The rubber band. Same family as the region selector's target frame, but
    // an in-place interaction on the canvas, not a modal overlay. mouseX/Y
    // track the pointer for the whole press.
    Rectangle {
        id: marqueeRect
        visible: root.marqueeActive
        z: 10
        x: Math.min(root.marqueeAnchorX, root.mouseX)
        y: Math.min(root.marqueeAnchorY, root.mouseY)
        width: Math.abs(root.mouseX - root.marqueeAnchorX)
        height: Math.abs(root.mouseY - root.marqueeAnchorY)
        color: Qt.alpha(Appearance.colors.colPrimary, 0.08)
        border.color: Appearance.colors.colPrimary
        border.width: 1.5
        radius: Appearance.rounding.unsharpenmore
    }

    // Snap guides. They used to be toggled by `visible`, which made them blink
    // in and out at full strength; they now fade, and carry a soft bloom so the
    // line reads as a guide rather than as a 1.5px scratch on the wallpaper.
    Item {
        id: snapLineV
        visible: opacity > 0.001
        opacity: root.snapLineX >= 0 ? 1 : 0
        x: root.snapLineX
        width: 1.5
        height: root.height
        z: 999
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(snapLineV)
        }
        Rectangle {
            anchors.centerIn: parent
            width: 9
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.28) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimary
        }
    }
    Item {
        id: snapLineH
        visible: opacity > 0.001
        opacity: root.snapLineY >= 0 ? 1 : 0
        y: root.snapLineY
        width: root.width
        height: 1.5
        z: 999
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(snapLineH)
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 9
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.28) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimary
        }
    }
}
