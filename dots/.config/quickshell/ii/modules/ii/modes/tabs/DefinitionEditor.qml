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
 * One mode — or, with `routine`, one routine — fully editable, as the detail page that
 * slides over the grid. Every control writes straight to the engine (which queues the
 * save); there is no Save button.
 *
 * Laid out like the clock's settings page: a centred column wide enough for the
 * condition and action forms, a header card in the definition's own colour (icon, name,
 * colour, start button), then titled sections. A mode reads "Turn on automatically /
 * When it's on / When it ends / Banners"; a routine reads "If / Then / Type / Options /
 * Banners", because that is how one reads an automation back: when this, do that, for
 * how long, with what extras.
 *
 * Editing a definition that is running does not touch what it applied — the old
 * snapshot must stay reversible — so a bar offers to restart it instead. The icon picker
 * and the "Add condition" / "Add action" catalogues open as side sheets in `panels`.
 */
Rectangle {
    id: root

    property string defId: ""
    property bool routine: false
    property ClockSidePanel panels: null
    property bool compact: false
    /// Focus the name once built (a definition just created by the New button).
    property bool focusNameOnOpen: false

    signal duplicated(string id)
    signal deleteRequested()

    // ── State ───────────────────────────────────────────────────────────
    readonly property var def: root.routine ? Modes.routineById(root.defId) : Modes.modeById(root.defId)
    readonly property bool hasDef: root.def !== null && root.def !== undefined
    readonly property bool isActive: root.routine ? Modes.isRoutineRunning(root.defId) : Modes.activeModeId === root.defId
    readonly property bool isOnce: root.routine && root.def?.kind === "once"
    readonly property string colorKey: root.def?.color ?? ""
    readonly property int triggerCount: root.def?.triggers?.length ?? 0
    readonly property int actionCount: root.def?.actions?.length ?? 0
    readonly property bool bannersOff: Config.options.modes.flash === "off"
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide

    // Actions changed while the definition was running: the engine still holds the
    // snapshot of the old set, so the new one only applies on a restart.
    property bool actionsEdited: false

    onDefIdChanged: root.actionsEdited = false
    onIsActiveChanged: root.actionsEdited = false

    Component.onCompleted: {
        if (root.focusNameOnOpen)
            Qt.callLater(root.focusName);
    }

    // ── Writes ──────────────────────────────────────────────────────────
    function patch(changes) {
        if (!root.hasDef)
            return;
        const next = Object.assign({}, ModeSchema.clone(root.def), changes);
        if (root.routine)
            Modes.upsertRoutine(next);
        else
            Modes.upsertMode(next);
    }

    function patchEnd(changes) {
        root.patch({ end: Object.assign({}, root.def.end, changes) });
    }

    function setTrigger(index, trigger) {
        const list = ModeSchema.clone(root.def.triggers);
        list[index] = trigger;
        root.patch({ triggers: list });
    }

    function removeTrigger(index) {
        const list = ModeSchema.clone(root.def.triggers);
        list.splice(index, 1);
        root.patch({ triggers: list });
    }

    function addTrigger(type) {
        const list = ModeSchema.clone(root.def.triggers);
        list.push(ModeSchema.normalizeTrigger({ type: type }));
        root.patch({ triggers: list });
    }

    function editActions(list) {
        root.patch({ actions: list });
        if (root.isActive)
            root.actionsEdited = true;
    }

    function setAction(index, action) {
        const list = ModeSchema.clone(root.def.actions);
        list[index] = action;
        root.editActions(list);
    }

    function removeAction(index) {
        const list = ModeSchema.clone(root.def.actions);
        list.splice(index, 1);
        root.editActions(list);
    }

    function moveAction(from, to) {
        const list = ModeSchema.clone(root.def.actions);
        if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length)
            return;
        const [item] = list.splice(from, 1);
        list.splice(to, 0, item);
        root.editActions(list);
    }

    function addAction(type) {
        const list = ModeSchema.clone(root.def.actions);
        list.push({ type: type, value: ModeUi.defaultActionValue(type) });
        root.editActions(list);
    }

    function startStop(): void {
        if (root.routine)
            Modes.toggleRoutine(root.defId);
        else
            Modes.toggle(root.defId);
    }

    function restart(): void {
        if (root.routine)
            Modes.restartRoutine(root.defId);
        else
            Modes.restartActive();
        root.actionsEdited = false;
    }

    function duplicate(): void {
        const id = root.routine ? Modes.duplicateRoutine(root.defId) : Modes.duplicateMode(root.defId);
        if (id.length)
            root.duplicated(id);
    }

    function focusName(): void {
        nameField.forceActiveFocus();
        nameField.selectAll();
    }

    // ── Sheets ──────────────────────────────────────────────────────────
    function pickIcon(): void {
        const sheet = root.panels?.show(iconSheet, { current: root.def?.icon ?? "" });
        sheet?.picked.connect(name => root.patch({ icon: name }));
    }

    function pickTrigger(): void {
        const sheet = root.panels?.show(typeSheet, {
            title: Translation.tr("Add a condition"),
            subtitle: root.routine ? Translation.tr("What the routine waits for") : Translation.tr("What starts the mode"),
            choices: root.triggerChoices
        });
        sheet?.picked.connect(key => root.addTrigger(key));
    }

    function pickAction(): void {
        const sheet = root.panels?.show(typeSheet, {
            title: Translation.tr("Add an action"),
            subtitle: root.routine ? Translation.tr("What the routine does") : Translation.tr("What the mode changes while it is on"),
            choices: root.actionChoices
        });
        sheet?.picked.connect(key => root.addAction(key));
    }

    Component {
        id: iconSheet
        IconPicker {}
    }

    Component {
        id: typeSheet
        TypeMenu {}
    }

    // ── Keys ────────────────────────────────────────────────────────────
    // The name field takes Escape first: it puts the saved name back.
    function handleEscape(): bool {
        if (!nameField.activeFocus)
            return false;
        nameField.text = root.def?.name ?? "";
        nameField.focus = false;
        root.forceActiveFocus();
        return true;
    }

    // Text fields keep their own keys; nothing here acts while one is being typed in.
    function handleKey(key: int, modifiers: int): bool {
        if (nameField.activeFocus)
            return false;
        if ((modifiers & Qt.ControlModifier) && key === Qt.Key_D) {
            root.duplicate();
            return true;
        }
        return false;
    }

    // ── Catalogues ──────────────────────────────────────────────────────
    readonly property var triggerChoices: {
        const out = [];
        const once = root.isOnce;
        for (const type in ModeSchema.TRIGGER_TYPES) {
            const meta = ModeSchema.TRIGGER_TYPES[type];
            if (!root.routine && meta.routineOnly)
                continue;
            const blocked = root.routine && meta.event === true && !once;
            out.push({
                key: type, label: Translation.tr(meta.label), icon: meta.icon,
                group: ModeUi.triggerGroupLabel(type), enabled: !blocked,
                hint: blocked ? Translation.tr("A moment, not a state: for \"when\" routines only") : ""
            });
        }
        return out;
    }

    // Modes: a non-repeatable action once per mode. Routines: settings (anything the
    // engine can read back) once per routine; one-shot actions may repeat — two
    // notifications, two modes.
    readonly property var actionChoices: {
        const out = [];
        const used = root.hasDef ? root.def.actions.map(a => a.type) : [];
        for (const type of Modes.actions.types()) {
            const entry = Modes.actions.get(type);
            if (!root.routine && entry.routineOnly)
                continue;
            const available = Modes.actions.isAvailable(type);
            const once = root.routine ? !!entry.read : !entry.repeatable;
            const taken = once && used.indexOf(type) !== -1;
            out.push({
                key: type,
                label: entry.label,
                icon: entry.icon,
                group: Modes.actions.categories[entry.category]?.label ?? entry.category,
                enabled: available && !taken,
                hint: !available ? Translation.tr("Not available on this machine")
                    : (taken ? (root.routine ? Translation.tr("Already in this routine") : Translation.tr("Already in this mode")) : "")
            });
        }
        return out;
    }

    color: ClockStyle.colBackground

    // The page is opaque to the pointer: nothing under it in the grid may take a click.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.forceActiveFocus()
    }

    // ── Pieces ──────────────────────────────────────────────────────────
    // Start / stop in the definition's own colours: a pill with its word, because the
    // header has room and "Run now" says more than a glyph.
    component StartButton: RippleButton {
        id: startButton
        property bool running: false
        property string label: ""
        property color colFill: ClockStyle.colPrimary
        property color colInk: ClockStyle.colOnPrimary

        implicitHeight: 52
        implicitWidth: startRow.implicitWidth + ClockStyle.gapHuge * 2
        buttonRadius: startButton.running ? ClockStyle.radiusLarge : 26
        buttonRadiusPressed: ClockStyle.radiusSmall
        colBackground: startButton.colFill
        colBackgroundHover: ColorUtils.mix(startButton.colFill, startButton.colInk, 0.9)
        colRipple: ColorUtils.mix(startButton.colFill, startButton.colInk, 0.78)

        contentItem: Item {
            implicitWidth: startRow.implicitWidth
            implicitHeight: startRow.implicitHeight

            RowLayout {
                id: startRow
                anchors.centerIn: parent
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: startButton.running ? "stop" : "play_arrow"
                    iconSize: ClockStyle.iconNormal
                    fill: 1
                    color: startButton.colInk
                }

                StyledText {
                    text: startButton.label
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: startButton.colInk
                }
            }
        }
    }

    // "Start when / Run while: any · all" above two or more conditions.
    component MatchRow: RowLayout {
        id: matchRow
        property string label: ""
        property string current: "any"
        signal picked(string value)

        Layout.fillWidth: true
        Layout.bottomMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gap

        FormLabel {
            Layout.leftMargin: ClockStyle.gapSmall
            text: matchRow.label
            color: ClockStyle.colOnSurfaceVariant
        }

        FormChoice {
            current: matchRow.current
            onPicked: value => matchRow.picked(value)
            options: [
                { displayName: Translation.tr("Any condition holds"), value: "any" },
                { displayName: Translation.tr("All conditions hold"), value: "all" }
            ]
        }
    }

    // A banner switch; greyed by the caller while banners are off for every mode.
    component BannerRow: EditorRow {
        id: bannerRow
        property bool checked: true
        signal toggled(bool value)

        opacity: enabled ? 1 : 0.5

        StyledSwitch {
            checked: bannerRow.checked
            onClicked: bannerRow.toggled(checked)
        }
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 2

        ColumnLayout {
            id: column
            x: Math.max(root.padding, (flick.width - width) / 2)
            y: ClockStyle.gapSmall
            width: Math.min(flick.width - root.padding * 2, 880)
            spacing: ClockStyle.gapHuge
            visible: root.hasDef

            // ── Header card ─────────────────────────────────────────────
            Rectangle {
                id: header
                Layout.fillWidth: true
                implicitHeight: headerColumn.implicitHeight + (ClockStyle.cardPadding + 4) * 2
                radius: ClockStyle.radiusCard
                color: root.isActive ? ModeUi.accent(root.colorKey) : ModeUi.container(root.colorKey)

                readonly property color colInk: root.isActive ? ModeUi.onAccent(root.colorKey) : ModeUi.onContainer(root.colorKey)

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    id: headerColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: ClockStyle.cardPadding + 4
                    }
                    spacing: ClockStyle.gapLarge

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapLarge + 2

                        // The icon is the button that changes it.
                        Item {
                            implicitWidth: 88
                            implicitHeight: 88

                            MaterialShapeWrappedMaterialSymbol {
                                anchors.fill: parent
                                text: root.def?.icon ?? (root.routine ? "bolt" : "tune")
                                iconSize: 40
                                padding: 24
                                shape: root.routine ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Cookie9Sided
                                fill: root.isActive ? 1 : 0
                                color: root.isActive ? header.colInk : ModeUi.accent(root.colorKey)
                                colSymbol: root.isActive ? header.color : ModeUi.onAccent(root.colorKey)
                                rotation: iconArea.containsMouse ? 25 : (root.isActive ? 12 : 0)
                            }

                            Rectangle {
                                anchors {
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                width: 28
                                height: 28
                                radius: 14
                                color: ClockStyle.colSurfaceHighest

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "edit"
                                    iconSize: 15
                                    color: ClockStyle.colOnSurface
                                }
                            }

                            MouseArea {
                                id: iconArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pickIcon()
                            }

                            StyledToolTip {
                                extraVisibleCondition: iconArea.containsMouse
                                text: Translation.tr("Change icon")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapTiny + 2

                            // The name is edited in place; committed on Enter or when focus
                            // leaves, never per keystroke.
                            StyledTextInput {
                                id: nameField
                                Layout.fillWidth: true
                                text: root.def?.name ?? ""
                                font.family: ClockStyle.fontTitle
                                font.variableAxes: ClockStyle.axesTitle
                                font.pixelSize: ClockStyle.textTitle + 8
                                color: header.colInk
                                selectByMouse: true
                                clip: true
                                onAccepted: nameField.focus = false
                                onEditingFinished: {
                                    const next = nameField.text.trim();
                                    if (next.length && next !== root.def?.name)
                                        root.patch({ name: next });
                                    else
                                        nameField.text = root.def?.name ?? "";
                                }

                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                        bottomMargin: -4
                                    }
                                    height: nameField.activeFocus ? 2 : 1
                                    radius: 1
                                    color: header.colInk
                                    opacity: nameField.activeFocus ? 1 : 0.3
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.topMargin: ClockStyle.gapTiny
                                text: root.routine ? ModeUi.routineHeaderStatus(root.def) : ModeUi.modeHeaderStatus(root.def)
                                wrapMode: Text.WordWrap
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.Medium
                                color: header.colInk
                                opacity: 0.9
                            }
                        }
                    }

                    // Colours and the start button side by side, stacked once the
                    // card is too narrow for both.
                    GridLayout {
                        id: headerControls
                        Layout.fillWidth: true
                        columns: headerColumn.width >= 500 ? 3 : 1
                        columnSpacing: ClockStyle.gap
                        rowSpacing: ClockStyle.gap

                        ColorDots {
                            id: colorDots
                            Layout.fillWidth: headerControls.columns === 1
                            Layout.maximumWidth: colorDots.oneLineWidth
                            current: root.colorKey
                            colRing: header.colInk
                            onPicked: key => root.patch({ color: key })
                        }

                        Item {
                            visible: headerControls.columns > 1
                            Layout.fillWidth: true
                        }

                        // A `while` routine and a mode toggle; a `once` routine just fires.
                        StartButton {
                            running: root.isActive
                            label: root.routine
                                ? (root.isActive ? Translation.tr("Stop") : Translation.tr("Run now"))
                                : (root.isActive ? Translation.tr("Turn off") : Translation.tr("Turn on"))
                            colFill: root.isActive ? header.colInk : ModeUi.accent(root.colorKey)
                            colInk: root.isActive ? header.color : ModeUi.onAccent(root.colorKey)
                            onClicked: root.startStop()
                        }
                    }
                }
            }

            // Running with stale actions: offer the restart instead of silently
            // re-applying under the user.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: -ClockStyle.gap
                visible: root.isActive && root.actionsEdited
                implicitHeight: restartRow.implicitHeight + ClockStyle.gap * 2
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colTertiaryContainer

                RowLayout {
                    id: restartRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: ClockStyle.gapLarge
                        rightMargin: ClockStyle.gapSmall
                    }
                    spacing: ClockStyle.gap

                    MaterialSymbol {
                        text: "published_with_changes"
                        iconSize: ClockStyle.iconNormal - 2
                        color: ClockStyle.colOnTertiaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.routine ? Translation.tr("Changes apply the next time this routine runs.")
                            : Translation.tr("Changes apply the next time this mode starts.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: ClockStyle.textNormal
                        color: ClockStyle.colOnTertiaryContainer
                    }

                    RippleButton {
                        implicitHeight: 40
                        implicitWidth: applyText.implicitWidth + ClockStyle.gapHuge * 1.5
                        buttonRadius: 20
                        buttonRadiusPressed: ClockStyle.radiusSmall
                        colBackground: ClockStyle.colTertiary
                        colBackgroundHover: ColorUtils.mix(ClockStyle.colTertiary, ClockStyle.colOnTertiary, 0.9)
                        colRipple: ColorUtils.mix(ClockStyle.colTertiary, ClockStyle.colOnTertiary, 0.78)
                        onClicked: root.restart()

                        contentItem: StyledText {
                            id: applyText
                            text: Translation.tr("Apply now")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnTertiary
                        }
                    }
                }
            }

            // ── Conditions ──────────────────────────────────────────────
            EditorSection {
                title: root.routine ? Translation.tr("If") : Translation.tr("Turn on automatically")
                icon: root.routine ? "filter_alt" : "autoplay"
                subtitle: {
                    if (root.routine) {
                        if (root.triggerCount === 0)
                            return Translation.tr("No conditions: this routine runs by hand only");
                        if (!root.def.enabled)
                            return Translation.tr("Conditions are set but automatic runs are off");
                        return root.isOnce ? Translation.tr("Fires the moment a condition below becomes true")
                            : Translation.tr("Runs for as long as a condition below holds");
                    }
                    if (root.triggerCount === 0)
                        return Translation.tr("No conditions: this mode starts by hand only");
                    return root.def.auto ? Translation.tr("Starts when a condition below is met")
                        : Translation.tr("Conditions are set but automatic start is off");
                }

                headerItem: StyledSwitch {
                    visible: root.triggerCount > 0
                    checked: root.routine ? (root.def?.enabled ?? true) : (root.def?.auto ?? false)
                    onClicked: root.patch(root.routine ? { enabled: checked } : { auto: checked })

                    StyledToolTip {
                        text: root.routine ? Translation.tr("Run on its own when the conditions hold")
                            : Translation.tr("Start on its own when the conditions hold")
                    }
                }

                // With two or more conditions the question "all or any" exists.
                MatchRow {
                    visible: root.triggerCount > 1
                    label: root.routine ? (root.isOnce ? Translation.tr("Fire when") : Translation.tr("Run while"))
                        : Translation.tr("Start when")
                    current: root.def?.match ?? "any"
                    onPicked: value => root.patch({ match: value })
                }

                Repeater {
                    // The count, not the list: rows outlive edits, so an unfolded form stays
                    // open while it is being changed.
                    model: root.triggerCount

                    delegate: TriggerRow {
                        required property int index

                        Layout.fillWidth: true
                        trigger: root.def?.triggers[index] ?? ({})
                        ownerId: root.defId
                        watcher: {
                            Modes.watchersRevision;
                            return root.routine ? Modes.routineWatcherFor(root.defId) : Modes.watcherFor(root.defId);
                        }
                        triggerIndex: index
                        onChanged: t => root.setTrigger(index, t)
                        onRemoveRequested: root.removeTrigger(index)
                    }
                }

                AddRowButton {
                    buttonText: Translation.tr("Add condition")
                    onClicked: root.pickTrigger()
                }
            }

            // ── Actions ─────────────────────────────────────────────────
            EditorSection {
                title: root.routine ? Translation.tr("Then") : Translation.tr("When it's on")
                icon: root.routine ? "bolt" : "tune"
                subtitle: {
                    const n = root.actionCount;
                    if (n === 0)
                        return root.routine ? Translation.tr("Nothing yet — add what the routine should do")
                            : Translation.tr("Nothing yet — add what the mode should change");
                    const span = ModeSchema.sequenceSpanSec(root.def?.actions);
                    const base = root.routine
                        ? (n === 1 ? Translation.tr("1 action") : Translation.tr("%1 actions, in this order").arg(n))
                        : (n === 1 ? Translation.tr("1 setting applied") : Translation.tr("%1 settings applied, in this order").arg(n));
                    return span > 0 ? Translation.tr("%1, over %2").arg(base).arg(ModeUi.durationText(span)) : base;
                }

                ActionList {
                    Layout.fillWidth: true
                    actions: root.def?.actions ?? []
                    routineKind: root.routine ? (root.def?.kind ?? "while") : ""
                    ownerId: root.routine ? root.defId : ""
                    flick: flick
                    onChanged: (index, a) => root.setAction(index, a)
                    onRemoveRequested: index => root.removeAction(index)
                    onMoved: (from, to) => root.moveAction(from, to)
                }

                AddRowButton {
                    buttonText: Translation.tr("Add action")
                    onClicked: root.pickAction()
                }
            }

            // ── Mode: when it ends ──────────────────────────────────────
            EditorSection {
                visible: !root.routine
                title: Translation.tr("When it ends")
                icon: "undo"

                EditorRow {
                    icon: "settings_backup_restore"
                    label: Translation.tr("Put settings back")
                    hint: Translation.tr("Restore what the mode changed")

                    StyledSwitch {
                        checked: root.def?.end?.revert ?? true
                        onClicked: root.patchEnd({ revert: checked })
                    }
                }

                EditorRow {
                    icon: "rule"
                    label: Translation.tr("Strict restore")
                    hint: Translation.tr("Also undo settings you changed by hand while it was on")
                    enabled: root.def?.end?.revert ?? true
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.def?.end?.strict ?? false
                        onClicked: root.patchEnd({ strict: checked })
                    }
                }

                EditorRow {
                    icon: "timer"
                    label: Translation.tr("Turn off after")
                    hint: (root.def?.end?.autoOffMin ?? 0) > 0
                        ? Translation.tr("Ends on its own after %1").arg(ModeUi.durationText((root.def?.end?.autoOffMin ?? 0) * 60))
                        : Translation.tr("Stays on until stopped")

                    StyledSpinBox {
                        // The Fusion style sizes a spin box for stacked buttons; these
                        // sit beside the value.
                        implicitHeight: baseHeight
                        from: 0
                        to: 1440
                        stepSize: 5
                        value: root.def?.end?.autoOffMin ?? 0
                        onValueModified: root.patchEnd({ autoOffMin: value })
                    }

                    StyledText {
                        text: Translation.tr("min")
                        font.pixelSize: ClockStyle.textNormal
                        color: ClockStyle.colSubtext
                    }
                }
            }

            // ── Routine: type ───────────────────────────────────────────
            EditorSection {
                visible: root.routine
                title: Translation.tr("Type")
                icon: "sync_alt"
                subtitle: root.isOnce
                    ? Translation.tr("Acts once when its conditions turn true and leaves things as they are")
                    : Translation.tr("Keeps its actions applied while its conditions hold, then puts them back")

                FormChoice {
                    Layout.leftMargin: ClockStyle.gapTiny
                    current: root.def?.kind ?? "while"
                    onPicked: value => root.patch({ kind: value })
                    options: [
                        { displayName: Translation.tr("While conditions hold"), value: "while" },
                        { displayName: Translation.tr("When conditions become true"), value: "once" }
                    ]
                }
            }

            // ── Routine: options ────────────────────────────────────────
            EditorSection {
                visible: root.routine
                title: Translation.tr("Options")
                icon: "tune"

                EditorRow {
                    visible: root.isOnce
                    icon: "timer"
                    label: Translation.tr("Cooldown")
                    hint: (root.def?.cooldownSec ?? 0) > 0
                        ? Translation.tr("Will not fire again this soon after the last time")
                        : Translation.tr("Fires on every change")

                    // Built while shown: a field built hidden measures its unit strip at
                    // zero width and keeps it.
                    Loader {
                        active: root.isOnce
                        sourceComponent: DurationField {
                            seconds: root.def?.cooldownSec ?? 0
                            maximumHours: 24
                            onCommitted: sec => root.patch({ cooldownSec: sec })
                        }
                    }
                }

                EditorRow {
                    visible: !root.isOnce
                    icon: "settings_backup_restore"
                    label: Translation.tr("Put settings back when it ends")
                    hint: Translation.tr("Each action can still opt out with its own switch")

                    StyledSwitch {
                        checked: root.def?.end?.revert ?? true
                        onClicked: root.patchEnd({ revert: checked })
                    }
                }

                EditorRow {
                    visible: !root.isOnce
                    icon: "rule"
                    label: Translation.tr("Strict restore")
                    hint: Translation.tr("Also undo settings you changed by hand while it was running")
                    enabled: root.def?.end?.revert ?? true
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.def?.end?.strict ?? false
                        onClicked: root.patchEnd({ strict: checked })
                    }
                }
            }

            // ── Banners ─────────────────────────────────────────────────
            EditorSection {
                title: Translation.tr("Banners")
                icon: "campaign"
                subtitle: {
                    if (root.bannersOff)
                        return Translation.tr("Banners are off for every mode in this app's settings");
                    if (!root.routine)
                        return Translation.tr("A brief pop-up when the mode switches on or off");
                    return root.isOnce ? Translation.tr("A brief pop-up when the routine fires")
                        : Translation.tr("A brief pop-up when the routine starts or ends");
                }

                BannerRow {
                    icon: "play_arrow"
                    label: root.isOnce ? Translation.tr("Show a banner when it fires") : Translation.tr("Show a banner when it starts")
                    enabled: !root.bannersOff
                    checked: root.def?.notify ?? true
                    onToggled: value => root.patch({ notify: value })
                }

                BannerRow {
                    visible: !root.isOnce
                    icon: "stop_circle"
                    label: Translation.tr("Show a banner when it ends")
                    enabled: !root.bannersOff
                    checked: root.def?.end?.notify ?? true
                    onToggled: value => root.patchEnd({ notify: value })
                }
            }

            // ── Footer ──────────────────────────────────────────────────
            Flow {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                FooterButton {
                    buttonIcon: "content_copy"
                    buttonText: Translation.tr("Duplicate")
                    onClicked: root.duplicate()

                    StyledToolTip {
                        text: Translation.tr("Duplicate (Ctrl+D)")
                    }
                }

                FooterButton {
                    visible: !root.routine && (root.def?.preset ?? false)
                    buttonIcon: "restart_alt"
                    buttonText: Translation.tr("Reset to preset")
                    onClicked: Modes.resetPreset(root.defId)
                }

                FooterButton {
                    buttonIcon: "delete"
                    buttonText: Translation.tr("Delete")
                    danger: true
                    onClicked: root.deleteRequested()
                }
            }
        }
    }
}
