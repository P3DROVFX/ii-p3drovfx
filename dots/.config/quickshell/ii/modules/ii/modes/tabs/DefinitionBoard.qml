pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.modes
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * The Modes page — or, with `routines`, the Routines page — of the Modes & Routines app.
 *
 * Laid out like the clock's Alarms tab: one dense grid of tiles led by a wide hero tile
 * (what is on right now), the assistant's prompt above it, and the page FAB that adds
 * one. Routines close with Discover, the ready-made templates. Clicking a tile slides
 * its editor over the grid as a detail page; anything that used to be a dialog — the
 * icon picker, the condition and action catalogues, a template preview, "delete?" —
 * opens as a side sheet that pushes the page narrower instead of covering it.
 *
 * Column count and tile sizes are decided on the settled width, so a sheet sliding in
 * re-deals the tiles instead of squeezing them frame by frame.
 *
 * Keys on the grid: arrows move a cursor between tiles, Enter starts / stops the one
 * under it (as the old list did), Space opens it, Ctrl+arrows change its place in the
 * order (priority, for modes), Ctrl+D duplicates, Delete asks to delete, Ctrl+N adds.
 */
Item {
    id: root

    // ── Contract ────────────────────────────────────────────────────────
    property bool compact: false
    property bool routines: false
    /// The settled width the app gives this page (the live one animates with the rail).
    property real layoutWidth: root.width
    /// The window's ClockPickerHost; editor forms reach it through the side panel.
    property Item pickers: null

    // The assistant's run belongs to the app shell, which owns the agent; the phase and
    // the verdict come in, the gestures go out.
    property string aiPhase: "idle"
    property string aiErrorText: ""
    property string aiCreatedName: ""

    signal aiSubmitted(string text)
    signal aiStopRequested()
    signal aiDismissed()
    signal aiSuccessFinished()
    signal aiOpenChatRequested()

    readonly property var items: root.routines ? Modes.routines : Modes.modes
    readonly property int count: root.items.length
    readonly property var editingDef: root.lookup(root.editingId)
    readonly property bool detailOpen: root.editingId.length > 0 && root.editingDef !== null
    readonly property string detailTitle: root.editingDef?.name
        ?? (root.routines ? Translation.tr("Routine") : Translation.tr("Mode"))
    /// The open editor's secondary actions, drawn by the app bar as icon buttons:
    /// `{ id, symbol, tooltip, danger }`, run through `triggerDetailAction(id)`.
    readonly property var detailActions: root.detailOpen ? (detailLoader.item?.headerActions ?? []) : []

    function triggerDetailAction(id: string): void {
        detailLoader.item?.runHeaderAction(id);
    }

    readonly property string pageSubtitle: {
        const n = root.count;
        let text;
        if (root.routines) {
            const running = Modes.routineRuns.length;
            text = n === 0 ? Translation.tr("No routines")
                : (n === 1 ? Translation.tr("1 routine") : Translation.tr("%1 routines").arg(n))
                    + " · " + (running === 0 ? Translation.tr("none running") : Translation.tr("%1 running").arg(running));
        } else {
            text = n === 0 ? Translation.tr("No modes")
                : (n === 1 ? Translation.tr("1 mode") : Translation.tr("%1 modes").arg(n))
                    + " · " + (Modes.active ? Translation.tr("%1 is on").arg(Modes.activeMode.name) : Translation.tr("none on"));
        }
        return Modes.enabled ? text : text + " · " + Translation.tr("automatic starts off");
    }

    function closeDetail(): void {
        if (!root.editingId.length)
            return;
        const id = root.editingId;
        sidePanel.close();
        root.editingId = "";
        root.scrollSoon(id);
    }

    // Innermost first: a sheet, then the editor's own field, then the detail page.
    function handleEscape(): bool {
        if (sidePanel.open) {
            sidePanel.close();
            return true;
        }
        if (root.detailOpen) {
            if (detailLoader.item?.handleEscape())
                return true;
            root.closeDetail();
            return true;
        }
        if (root.cursorVisible) {
            root.cursorVisible = false;
            return true;
        }
        return false;
    }

    function handleKey(key: int, modifiers: int): bool {
        const ctrl = (modifiers & Qt.ControlModifier) !== 0;
        if (sidePanel.open)
            return false;
        if (ctrl && key === Qt.Key_N) {
            root.primaryAction();
            return true;
        }
        if (root.detailOpen)
            return detailLoader.item?.handleKey(key, modifiers) ?? false;
        if (root.count === 0)
            return false;

        const index = Math.max(0, root.items.findIndex(d => d.id === root.cursorId));
        const current = root.items[index];
        switch (key) {
        case Qt.Key_Left:
        case Qt.Key_Right:
        case Qt.Key_Up:
        case Qt.Key_Down: {
            const forward = key === Qt.Key_Right || key === Qt.Key_Down;
            const vertical = key === Qt.Key_Up || key === Qt.Key_Down;
            if (ctrl) {
                root.move(current.id, forward ? 1 : -1);
                return true;
            }
            // The first press only shows where the cursor is.
            if (!root.cursorVisible || !root.lookup(root.cursorId)) {
                root.cursorVisible = true;
                root.cursorId = current.id;
                root.scrollTo(current.id);
                return true;
            }
            const step = (vertical ? root.columns : 1) * (forward ? 1 : -1);
            const next = root.items[Math.max(0, Math.min(root.count - 1, index + step))];
            root.cursorId = next.id;
            root.scrollTo(next.id);
            return true;
        }
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!root.cursorVisible)
                return false;
            root.startStop(current.id);
            return true;
        case Qt.Key_Space:
            if (!root.cursorVisible)
                return false;
            root.openEditor(current.id, false);
            return true;
        case Qt.Key_Delete:
            if (!root.cursorVisible)
                return false;
            root.confirmDelete(current.id);
            return true;
        case Qt.Key_D:
            if (!ctrl || !root.cursorVisible)
                return false;
            root.duplicate(current.id);
            return true;
        }
        return false;
    }

    /// Open that mode or routine: its tile scrolled into view and under the cursor, its
    /// editor slid over the grid. While the assistant's success beat is on screen the
    /// editor waits for it, so "Created …" is read before the page moves on.
    function reveal(id: string): void {
        root.revealId = String(id ?? "");
        revealTimer.restart();
    }

    function primaryAction(): void {
        root.create();
    }

    // ── State ───────────────────────────────────────────────────────────
    /// The definition being edited, "" when the grid shows.
    property string editingId: ""
    /// What the detail page shows; kept while it slides away so it does not blank out.
    property string shownId: ""
    property bool focusNameOnOpen: false
    /// The keyboard cursor on the grid.
    property string cursorId: ""
    property bool cursorVisible: false
    /// Created by the assistant; opened once its success beat ends.
    property string pendingOpenId: ""
    /// The prompt bar was opened by its button (a run in flight keeps it open anyway).
    property bool aiUserOpened: false
    readonly property bool aiAllowed: SearchPanelRegistry.aiPolicyEnabled
    readonly property string previewKey: sidePanel.isShowing(templateSheet) ? String(sidePanel.current?.templateKey ?? "") : ""

    onAiPhaseChanged: {
        if (root.aiPhase === "idle")
            root.aiUserOpened = false;
    }

    // Deferred work runs on timers that die with the page, never on Qt.callLater: a
    // closure queued while the page is being torn down (a tab switch) would call into
    // an object whose functions are already gone.
    property string revealId: ""
    property string scrollId: ""

    function scrollSoon(id: string): void {
        root.scrollId = id;
        scrollTimer.restart();
    }

    Timer {
        id: revealTimer
        interval: 0
        onTriggered: root.revealNow(root.revealId)
    }

    Timer {
        id: scrollTimer
        interval: 0
        onTriggered: root.scrollTo(root.scrollId)
    }

    // A sheet that owned the keyboard is destroyed on close; hand the keys back to the
    // page so its shortcuts keep working without a click.
    Timer {
        id: focusTimer
        interval: 0
        onTriggered: root.forceActiveFocus()
    }

    Connections {
        target: sidePanel
        function onClosed() {
            focusTimer.restart();
        }
    }

    function lookup(id: string): var {
        if (!id || !id.length)
            return null;
        return root.routines ? Modes.routineById(id) : Modes.modeById(id);
    }

    function openEditor(id: string, focusName: bool): void {
        if (!root.lookup(id))
            return;
        sidePanel.close();
        root.focusNameOnOpen = focusName;
        root.shownId = id;
        root.editingId = id;
        root.cursorId = id;
        // The engine's cold path reads these to land on the same definition.
        if (root.routines) {
            if (Config.options.modes.lastRoutineId !== id)
                Config.options.modes.lastRoutineId = id;
        } else if (Config.options.modes.lastModeId !== id) {
            Config.options.modes.lastModeId = id;
        }
    }

    function revealNow(id: string): void {
        if (!root.lookup(id))
            return;
        root.cursorId = id;
        root.cursorVisible = true;
        if (root.aiPhase === "success") {
            root.pendingOpenId = id;
            sidePanel.close();
            root.editingId = "";
            root.scrollSoon(id);
            return;
        }
        root.openEditor(id, false);
    }

    function create(): void {
        const id = root.routines
            ? Modes.addRoutine({ name: Translation.tr("New routine"), icon: "bolt", enabled: true })
            : Modes.addMode({ name: Translation.tr("New mode"), icon: "tune" });
        root.openEditor(id, true);
    }

    function startStop(id: string): void {
        if (root.routines)
            Modes.toggleRoutine(id);
        else
            Modes.toggle(id);
    }

    function move(id: string, delta: int): void {
        const index = root.items.findIndex(d => d.id === id);
        const to = index + delta;
        if (index < 0 || to < 0 || to >= root.count)
            return;
        if (root.routines)
            Modes.moveRoutine(id, to);
        else
            Modes.moveMode(id, to);
        root.cursorId = id;
        root.scrollSoon(id);
    }

    function duplicate(id: string): void {
        const copy = root.routines ? Modes.duplicateRoutine(id) : Modes.duplicateMode(id);
        if (!copy.length)
            return;
        root.cursorId = copy;
        root.scrollSoon(copy);
    }

    function confirmDelete(id: string): void {
        const def = root.lookup(id);
        if (!def)
            return;
        const running = root.routines ? Modes.isRoutineRunning(id) : Modes.activeModeId === id;
        const sheet = sidePanel.show(confirmSheet, {
            title: root.routines
                ? (running ? Translation.tr("Stop and delete this routine?") : Translation.tr("Delete this routine?"))
                : (running ? Translation.tr("Turn off and delete this mode?") : Translation.tr("Delete this mode?")),
            subtitle: def.name,
            message: running
                ? Translation.tr("“%1” is put back first, then removed with its conditions and actions.").arg(def.name)
                : Translation.tr("“%1” is removed with its conditions and actions.").arg(def.name),
            confirmLabel: Translation.tr("Delete")
        });
        sheet?.confirmed.connect(() => root.remove(id));
    }

    function remove(id: string): void {
        const index = root.items.findIndex(d => d.id === id);
        if (root.editingId === id)
            root.editingId = "";
        if (root.routines)
            Modes.removeRoutine(id);
        else
            Modes.removeMode(id);
        const next = root.items[Math.min(index, root.count - 1)];
        root.cursorId = next?.id ?? "";
    }

    function previewTemplate(key: string): void {
        sidePanel.show(templateSheet, { templateKey: key });
    }

    function addTemplate(key: string): void {
        const id = Modes.addRoutineFromTemplate(key);
        if (id.length)
            root.openEditor(id, false);
    }

    /// Bring a tile into view in the grid (it may sit below the fold).
    function scrollTo(id: string): void {
        const index = root.items.findIndex(d => d.id === id);
        const tile = index >= 0 ? tileRepeater.itemAt(index) : null;
        if (!tile)
            return;
        const y = tile.mapToItem(content, 0, 0).y;
        const top = y - ClockStyle.gap;
        const bottom = y + tile.height + ClockStyle.fabClearance - flick.height;
        if (top < flick.contentY)
            flick.contentY = Math.max(0, top);
        else if (bottom > flick.contentY)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), bottom);
    }

    function scrollToDiscover(): void {
        const y = discoverHeader.mapToItem(content, 0, 0).y - ClockStyle.gap;
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), y));
    }

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real sheetWidth: root.compact
        ? root.width
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth + 20, root.layoutWidth * 0.32))
    /// Settled page width: every layout decision reads this, not the live width.
    readonly property real pageLayoutWidth: root.layoutWidth - (sidePanel.open && !root.compact ? root.sheetWidth + ClockStyle.paneGap : 0)
    readonly property real gridGap: ClockStyle.gap
    readonly property real contentWidth: pageArea.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.pageLayoutWidth - ClockStyle.gapTiny * 2
    readonly property int columns: Math.max(1, Math.floor((root.contentLayoutWidth + root.gridGap) / (ClockStyle.alarmCardMinWidth + root.gridGap)))
    readonly property real tileLayoutWidth: (root.contentLayoutWidth - root.gridGap * (root.columns - 1)) / root.columns
    /// One animated width shared by every tile, so a row never briefly holds more than
    /// it can (see LimitsRules).
    property real tileWidth: root.tileLayoutWidth
    Behavior on tileWidth {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }
    readonly property real flowWidth: Math.max(root.contentWidth, root.contentLayoutWidth,
        Math.ceil(root.tileWidth * root.columns + root.gridGap * (root.columns - 1)) + 1)
    readonly property real tileHeight: Math.round(Math.max(212, Math.min(244, root.tileLayoutWidth * 0.84)))
    readonly property int heroSpan: Math.min(2, root.columns)

    Component {
        id: confirmSheet
        ModesConfirmSheet {}
    }

    Component {
        id: templateSheet
        TemplatePreviewSheet {
            onAdded: id => root.openEditor(id, false)
        }
    }

    // A page heading in the title face, with room for buttons on its right.
    component SectionHeader: RowLayout {
        id: header
        property string title: ""
        property string subtitle: ""
        default property alias trailing: trailingRow.data

        Layout.fillWidth: true
        spacing: ClockStyle.gap

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: header.title
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle + 2
                color: ClockStyle.colOnBackground
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: header.subtitle.length > 0
                text: header.subtitle
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
                elide: Text.ElideRight
            }
        }

        RowLayout {
            id: trailingRow
            spacing: ClockStyle.gapSmall
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Page ────────────────────────────────────────────────────────
        Item {
            id: pageArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !(root.compact && sidePanel.open)
            clip: true

            StyledFlickable {
                id: flick
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight + ClockStyle.fabClearance
                clip: true
                // Hidden once the detail page fully covers it: nothing under an opaque
                // page needs drawing or input.
                visible: detailLoader.progress < 1

                ColumnLayout {
                    id: content
                    x: ClockStyle.gapTiny
                    y: ClockStyle.gapTiny
                    width: root.contentWidth
                    spacing: ClockStyle.gapLarge

                    SectionHeader {
                        title: root.routines ? Translation.tr("Your routines") : Translation.tr("Your modes")
                        subtitle: root.routines
                            ? Translation.tr("Run on their own next to any mode, as many at once as hold")
                            : Translation.tr("One at a time · among automatic starts, the first whose conditions hold wins")

                        // The assistant's seat. Open, it turns into the button that folds
                        // the prompt away again.
                        ClockIconButton {
                            visible: root.aiAllowed
                            symbol: aiBar.expanded ? "close" : "auto_awesome"
                            toggled: aiBar.expanded && root.aiPhase === "idle"
                            tooltip: aiBar.expanded ? Translation.tr("Close the assistant") : Translation.tr("Create with the assistant")
                            onClicked: {
                                if (root.aiPhase === "running")
                                    return;
                                // A verdict on screen: the press clears it and folds the
                                // bar; from idle it opens or closes the field.
                                if (root.aiPhase !== "idle") {
                                    root.aiUserOpened = false;
                                    root.aiDismissed();
                                    return;
                                }
                                root.aiUserOpened = !root.aiUserOpened;
                            }
                        }
                    }

                    ModeAiBar {
                        id: aiBar
                        Layout.fillWidth: true
                        Layout.topMargin: expanded ? 0 : -ClockStyle.gapLarge
                        visible: root.aiAllowed || root.aiPhase !== "idle"
                        // A tab switch rebuilds this page mid-run; the run's phase keeps
                        // the bar open across the rebuild, the button only ever opens it.
                        expanded: root.aiUserOpened || root.aiPhase !== "idle"
                        phase: root.aiPhase
                        errorText: root.aiErrorText
                        createdName: root.aiCreatedName
                        placeholder: root.routines ? Translation.tr("Describe a routine — “pause music when I lock the screen”")
                            : Translation.tr("Describe a mode — “quiet and dark after 22:00”")
                        onSubmitted: text => root.aiSubmitted(text)
                        onStopRequested: root.aiStopRequested()
                        onDismissed: {
                            root.aiUserOpened = false;
                            root.aiDismissed();
                        }
                        onSuccessFinished: {
                            root.aiSuccessFinished();
                            const id = root.pendingOpenId;
                            root.pendingOpenId = "";
                            if (id.length)
                                root.openEditor(id, false);
                        }
                        onOpenChatRequested: root.aiOpenChatRequested()
                    }

                    // ── Grid ────────────────────────────────────────────
                    // Tiles carry their own width and the flow animates where they land,
                    // so a sheet opening re-deals them instead of stretching them.
                    Flow {
                        id: grid
                        visible: root.count > 0
                        Layout.preferredWidth: root.flowWidth
                        spacing: root.gridGap

                        move: Transition {
                            enabled: !ClockStyle.reducedMotion
                            NumberAnimation {
                                properties: "x,y"
                                duration: ClockStyle.motionDefault.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                            }
                        }

                        // Hidden with an empty list: the empty card below says it once.
                        DefinitionHero {
                            visible: root.count > 0
                            width: Math.floor(root.tileWidth * root.heroSpan + root.gridGap * (root.heroSpan - 1))
                            height: root.tileHeight
                            layoutWidth: root.tileLayoutWidth * root.heroSpan
                            routine: root.routines
                            onOpenRequested: id => root.openEditor(id, false)

                            StaggeredEntrance {
                                index: 0
                                active: !ClockStyle.reducedMotion
                            }
                        }

                        Repeater {
                            id: tileRepeater
                            // The count, not the list: an edit re-reads a tile's data
                            // instead of rebuilding every tile.
                            model: root.count

                            DefinitionTile {
                                id: tile
                                required property int index
                                width: Math.floor(root.tileWidth)
                                height: root.tileHeight
                                def: root.items[tile.index] ?? null
                                routine: root.routines
                                position: tile.index
                                count: root.count
                                layoutWidth: root.tileLayoutWidth
                                focusRing: root.cursorVisible && root.cursorId === (tile.def?.id ?? "")
                                onOpenRequested: {
                                    root.cursorId = tile.def.id;
                                    root.openEditor(tile.def.id, false);
                                }
                                onMoveRequested: delta => root.move(tile.def.id, delta)
                                onDuplicateRequested: root.duplicate(tile.def.id)
                                onDeleteRequested: root.confirmDelete(tile.def.id)

                                StaggeredEntrance {
                                    index: tile.index + 1
                                    step: ClockStyle.staggerStep
                                    active: !ClockStyle.reducedMotion
                                }
                            }
                        }
                    }

                    // ── Empty ───────────────────────────────────────────
                    Rectangle {
                        visible: root.count === 0
                        Layout.fillWidth: true
                        implicitHeight: emptyColumn.implicitHeight + ClockStyle.gapHuge * 2
                        radius: ClockStyle.radiusCard
                        color: ClockStyle.colPane

                        ColumnLayout {
                            id: emptyColumn
                            anchors.centerIn: parent
                            width: Math.min(parent.width - ClockStyle.gapHuge * 2, 460)
                            spacing: ClockStyle.gapLarge

                            ClockEmptyState {
                                Layout.alignment: Qt.AlignHCenter
                                symbol: root.routines ? "bolt" : "tune"
                                shape: "Ghostish"
                                shapeSize: ClockStyle.emptyShapeSmall
                                title: root.routines ? Translation.tr("No routines yet") : Translation.tr("No modes yet")
                                subtitle: root.routines
                                    ? Translation.tr("Start from a template below, or build one from scratch.")
                                    : Translation.tr("Create one, or bring the presets back: Sleep, Work, Focus, Gaming and more.")
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: ClockStyle.gapSmall

                                ClockButton {
                                    variant: "filled"
                                    symbol: "add"
                                    label: root.routines ? Translation.tr("New routine") : Translation.tr("New mode")
                                    onClicked: root.create()
                                }

                                ClockButton {
                                    variant: "tonal"
                                    symbol: root.routines ? "explore" : "restore"
                                    label: root.routines ? Translation.tr("Browse templates") : Translation.tr("Restore presets")
                                    onClicked: {
                                        if (root.routines)
                                            root.scrollToDiscover();
                                        else
                                            Modes.seedPresets();
                                    }
                                }
                            }
                        }
                    }

                    // ── Discover ────────────────────────────────────────
                    SectionHeader {
                        id: discoverHeader
                        visible: root.routines
                        Layout.topMargin: ClockStyle.gapSmall
                        title: Translation.tr("Discover")
                        subtitle: Translation.tr("Ready-made routines: preview one, then add a copy you can change")
                    }

                    Flow {
                        visible: root.routines
                        Layout.preferredWidth: root.flowWidth
                        spacing: root.gridGap

                        move: Transition {
                            enabled: !ClockStyle.reducedMotion
                            NumberAnimation {
                                properties: "x,y"
                                duration: ClockStyle.motionDefault.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                            }
                        }

                        Repeater {
                            model: root.routines ? ModeSchema.routineTemplates() : []

                            TemplateTile {
                                id: templateTile
                                required property var modelData
                                required property int index
                                width: Math.floor(root.tileWidth)
                                height: 180
                                template: templateTile.modelData
                                previewing: root.previewKey === templateTile.key
                                onPreviewRequested: root.previewTemplate(templateTile.key)
                                onAddRequested: root.addTemplate(templateTile.key)

                                // Built once with the page (the templates never change), so
                                // this plays on the first build only.
                                StaggeredEntrance {
                                    index: templateTile.index
                                    step: ClockStyle.staggerStep
                                    active: !ClockStyle.reducedMotion
                                }
                            }
                        }
                    }
                }
            }

            FloatingActionButton {
                id: pageFab
                readonly property bool shown: !root.detailOpen
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: ClockStyle.gapLarge
                anchors.bottomMargin: pageFab.shown ? ClockStyle.gapLarge : -pageFab.height - ClockStyle.gapHuge
                z: 5
                baseSize: ClockStyle.fabSizeLarge
                iconSize: 34
                buttonRadius: Appearance.rounding.large
                buttonRadiusPressed: Appearance.rounding.normal
                iconText: root.routines ? "bolt" : "add"
                buttonText: root.routines ? Translation.tr("New routine") : Translation.tr("New mode")
                // The cheatsheet's FAB: the label unfolds to the left on hover.
                expanded: hovered
                shortcut: "Ctrl\n+ N"
                opacity: pageFab.shown ? 1 : 0
                enabled: pageFab.shown
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                colRipple: Appearance.colors.colPrimaryContainerActive
                colOnBackground: Appearance.colors.colOnPrimaryContainer
                onClicked: root.create()

                Behavior on anchors.bottomMargin {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                StyledToolTip {
                    text: (root.routines ? Translation.tr("New routine") : Translation.tr("New mode")) + " (Ctrl+N)"
                }
            }

            // The editor slides over the grid. The slide is a 0→1 progress, not an x
            // bound to the page width: a width that grows while the side sheet closes
            // would otherwise drag a "closed" page back into view.
            Loader {
                id: detailLoader
                property real progress: root.detailOpen ? 1 : 0

                anchors.fill: parent
                active: root.detailOpen || progress > 0
                visible: progress > 0
                z: 10
                opacity: progress

                Behavior on progress {
                    enabled: !ClockStyle.reducedMotion
                    NumberAnimation {
                        duration: root.detailOpen ? ClockStyle.motionEnter.duration : ClockStyle.motionExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.detailOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                    }
                }

                sourceComponent: DefinitionEditor {
                    defId: root.shownId
                    routine: root.routines
                    panels: sidePanel
                    compact: root.compact
                    // The page's settled width less its own open sheet.
                    layoutWidth: root.pageLayoutWidth
                    focusNameOnOpen: root.focusNameOnOpen
                    onDuplicated: id => root.openEditor(id, true)
                    onDeleteRequested: root.confirmDelete(root.shownId)
                }

                transform: Translate {
                    x: (1 - detailLoader.progress) * Math.min(pageArea.width * 0.1, 96)
                }
            }
        }

        // ── Side sheet ──────────────────────────────────────────────────
        // The slot animates its width and clips; the sheet inside keeps its own width
        // pinned to the right, so it slides in instead of reflowing.
        Item {
            id: sheetSlot
            Layout.fillHeight: true
            Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : ClockStyle.paneGap) : 0
            visible: Layout.preferredWidth > 1
            clip: true

            Behavior on Layout.preferredWidth {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }

            ClockSidePanel {
                id: sidePanel
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
                width: root.sheetWidth
                pickers: root.pickers
            }
        }
    }
}
