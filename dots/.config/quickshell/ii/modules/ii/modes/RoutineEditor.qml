pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * The right pane of the Routines tab: one routine, edited in place. If /
 * Then / Type / Options, in that order, because that is how one reads an
 * automation back: when this, do that, for how long, with what extras.
 */
Item {
    id: root

    required property string routineId
    readonly property var routine: Modes.routineById(root.routineId)
    readonly property bool hasRoutine: root.routine !== null && root.routine !== undefined
    readonly property bool isRunning: Modes.isRoutineRunning(root.routineId)
    readonly property bool isOnce: root.routine?.kind === "once"
    readonly property string colorKey: root.routine?.color ?? ""

    property bool confirmDelete: false
    // Actions changed while a `while` routine was running: the engine keeps
    // the old snapshot, so the new set only applies on a restart.
    property bool actionsEdited: false

    signal requestClose()
    signal deleted()
    signal duplicated(string id)

    onRoutineIdChanged: {
        root.confirmDelete = false;
        root.actionsEdited = false;
    }

    onIsRunningChanged: root.actionsEdited = false

    function patch(changes) {
        if (!root.hasRoutine)
            return;
        const next = Object.assign({}, ModeSchema.clone(root.routine), changes);
        Modes.upsertRoutine(next);
    }

    function patchEnd(changes) {
        root.patch({ end: Object.assign({}, root.routine.end, changes) });
    }

    function setTrigger(index, trigger) {
        const list = ModeSchema.clone(root.routine.triggers);
        list[index] = trigger;
        root.patch({ triggers: list });
    }

    function removeTrigger(index) {
        const list = ModeSchema.clone(root.routine.triggers);
        list.splice(index, 1);
        root.patch({ triggers: list });
    }

    function addTrigger(type) {
        const list = ModeSchema.clone(root.routine.triggers);
        list.push(ModeSchema.normalizeTrigger({ type: type }));
        root.patch({ triggers: list });
    }

    function setAction(index, action) {
        const list = ModeSchema.clone(root.routine.actions);
        list[index] = action;
        root.patch({ actions: list });
        if (root.isRunning)
            root.actionsEdited = true;
    }

    function removeAction(index) {
        const list = ModeSchema.clone(root.routine.actions);
        list.splice(index, 1);
        root.patch({ actions: list });
        if (root.isRunning)
            root.actionsEdited = true;
    }

    function moveAction(from, to) {
        const list = ModeSchema.clone(root.routine.actions);
        if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length)
            return;
        const [item] = list.splice(from, 1);
        list.splice(to, 0, item);
        root.patch({ actions: list });
        if (root.isRunning)
            root.actionsEdited = true;
    }

    function addAction(type) {
        const list = ModeSchema.clone(root.routine.actions);
        list.push({ type: type, value: ModeUi.defaultActionValue(type) });
        root.patch({ actions: list });
        if (root.isRunning)
            root.actionsEdited = true;
    }

    function focusName() {
        nameField.forceActiveFocus();
        nameField.selectAll();
    }

    function handleEscape() {
        if (iconPicker.opened) {
            iconPicker.close();
            return true;
        }
        if (triggerMenu.opened) {
            triggerMenu.close();
            return true;
        }
        if (actionMenu.opened) {
            actionMenu.close();
            return true;
        }
        if (root.confirmDelete) {
            root.confirmDelete = false;
            return true;
        }
        if (nameField.activeFocus) {
            nameField.text = root.routine?.name ?? "";
            nameField.focus = false;
            return true;
        }
        return false;
    }

    function handleKey(key, modifiers) {
        return nameField.activeFocus;
    }

    readonly property var triggerChoices: {
        const out = [];
        const once = (root.routine?.kind ?? "while") === "once";
        for (const type in ModeSchema.TRIGGER_TYPES) {
            const meta = ModeSchema.TRIGGER_TYPES[type];
            const blocked = meta.event === true && !once;
            out.push({
                key: type, label: Translation.tr(meta.label), icon: meta.icon,
                group: ModeUi.triggerGroupLabel(type), enabled: !blocked,
                hint: blocked ? Translation.tr("A moment, not a state: for \"when\" routines only") : ""
            });
        }
        return out;
    }

    // Settings (anything the engine can read back) make sense once per
    // routine; one-shot actions may repeat — two notifications, two modes.
    readonly property var actionChoices: {
        const out = [];
        const used = root.routine ? root.routine.actions.map(a => a.type) : [];
        for (const type of Modes.actions.types()) {
            const entry = Modes.actions.get(type);
            const available = Modes.actions.isAvailable(type);
            const taken = !!entry.read && used.indexOf(type) !== -1;
            out.push({
                key: type,
                label: entry.label,
                icon: entry.icon,
                group: Modes.actions.categories[entry.category]?.label ?? entry.category,
                enabled: available && !taken,
                hint: !available ? Translation.tr("Not available on this machine")
                    : (taken ? Translation.tr("Already in this routine") : "")
            });
        }
        return out;
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.implicitHeight + 24
        clip: true

        ColumnLayout {
            id: column
            width: flick.width - 8
            x: 4
            y: 8
            spacing: 18

            // -------------------------------------------------- header
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                spacing: 14

                RippleButton {
                    implicitWidth: 64
                    implicitHeight: 64
                    buttonRadius: Appearance.rounding.full
                    colBackground: ModeUi.container(root.colorKey)
                    colBackgroundHover: ColorUtils.mix(ModeUi.container(root.colorKey), ModeUi.onContainer(root.colorKey), 0.9)
                    colRipple: ColorUtils.mix(ModeUi.container(root.colorKey), ModeUi.onContainer(root.colorKey), 0.8)
                    onClicked: iconPicker.open()

                    StyledToolTip {
                        text: Translation.tr("Change icon")
                    }

                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.routine?.icon ?? "bolt"
                            iconSize: 32
                            fill: root.isRunning ? 1 : 0
                            color: ModeUi.onContainer(root.colorKey)
                        }

                        Rectangle {
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                            }
                            width: 22
                            height: 22
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            border.width: 2
                            border.color: Appearance.colors.colLayer1

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "edit"
                                iconSize: 12
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledTextInput {
                        id: nameField
                        Layout.fillWidth: true
                        text: root.routine?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        selectByMouse: true
                        clip: true
                        onEditingFinished: {
                            const next = nameField.text.trim();
                            if (next.length && next !== root.routine?.name)
                                root.patch({ name: next });
                            else
                                nameField.text = root.routine?.name ?? "";
                        }

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                                bottomMargin: -3
                            }
                            height: nameField.activeFocus ? 2 : 1
                            color: nameField.activeFocus ? Appearance.colors.colPrimary
                                : ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        text: ModeUi.routineHeaderStatus(root.routine)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.isRunning ? ModeUi.accent(root.colorKey) : Appearance.colors.colSubtext
                    }

                    ColorDots {
                        Layout.topMargin: 8
                        current: root.colorKey
                        onPicked: key => root.patch({ color: key })
                    }
                }

                // A `while` routine toggles; a `once` routine just fires.
                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 4
                    implicitHeight: 48
                    implicitWidth: runRow.implicitWidth + 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.isRunning ? Appearance.colors.colSecondaryContainer : ModeUi.accent(root.colorKey)
                    colBackgroundHover: root.isRunning ? Appearance.colors.colSecondaryContainerHover
                        : ColorUtils.mix(ModeUi.accent(root.colorKey), ModeUi.onAccent(root.colorKey), 0.9)
                    colRipple: root.isRunning ? Appearance.colors.colSecondaryContainerActive
                        : ColorUtils.mix(ModeUi.accent(root.colorKey), ModeUi.onAccent(root.colorKey), 0.8)
                    onClicked: Modes.toggleRoutine(root.routineId)

                    contentItem: RowLayout {
                        id: runRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: root.isRunning ? "stop" : "play_arrow"
                            iconSize: 22
                            fill: 1
                            color: root.isRunning ? Appearance.colors.colOnSecondaryContainer : ModeUi.onAccent(root.colorKey)
                        }

                        StyledText {
                            text: root.isRunning ? Translation.tr("Stop") : Translation.tr("Run now")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: root.isRunning ? Appearance.colors.colOnSecondaryContainer : ModeUi.onAccent(root.colorKey)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                visible: root.isRunning && root.actionsEdited
                implicitHeight: 46
                radius: Appearance.rounding.normal
                color: Appearance.colors.colTertiaryContainer

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 8
                    }
                    spacing: 10

                    MaterialSymbol {
                        text: "published_with_changes"
                        iconSize: 20
                        color: Appearance.colors.colOnTertiaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Changes apply the next time this routine runs.")
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnTertiaryContainer
                    }

                    RippleButton {
                        implicitHeight: 32
                        implicitWidth: applyNowText.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colTertiary
                        colBackgroundHover: Appearance.colors.colTertiaryHover
                        colRipple: Appearance.colors.colTertiaryActive
                        onClicked: {
                            Modes.restartRoutine(root.routineId);
                            root.actionsEdited = false;
                        }

                        contentItem: StyledText {
                            id: applyNowText
                            text: Translation.tr("Apply now")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnTertiary
                        }
                    }
                }
            }

            // -------------------------------------------------- if
            EditorSection {
                title: Translation.tr("If")
                icon: "filter_alt"
                subtitle: {
                    const n = root.routine?.triggers.length ?? 0;
                    if (n === 0)
                        return Translation.tr("No conditions: this routine runs by hand only");
                    if (!root.routine.enabled)
                        return Translation.tr("Conditions are set but automatic runs are off");
                    return root.isOnce ? Translation.tr("Fires the moment a condition below becomes true")
                        : Translation.tr("Runs for as long as a condition below holds");
                }

                headerItem: StyledSwitch {
                    visible: (root.routine?.triggers.length ?? 0) > 0
                    checked: root.routine?.enabled ?? true
                    onClicked: root.patch({ enabled: checked })
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: (root.routine?.triggers.length ?? 0) > 1
                    spacing: 10

                    StyledText {
                        text: root.isOnce ? Translation.tr("Fire when") : Translation.tr("Run while")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    ConfigSelectionArray {
                        currentValue: root.routine?.match ?? "any"
                        onSelected: value => root.patch({ match: value })
                        options: [
                            { displayName: Translation.tr("Any condition holds"), value: "any" },
                            { displayName: Translation.tr("All conditions hold"), value: "all" }
                        ]
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                Repeater {
                    // The count, not the list: rows outlive edits, so an
                    // unfolded form stays open while it is being changed.
                    model: root.routine?.triggers.length ?? 0

                    delegate: TriggerRow {
                        required property int index

                        Layout.fillWidth: true
                        trigger: root.routine?.triggers[index] ?? ({})
                        ownerId: root.routineId
                        watcher: {
                            Modes.watchersRevision;
                            return Modes.routineWatcherFor(root.routineId);
                        }
                        triggerIndex: index
                        onChanged: t => root.setTrigger(index, t)
                        onRemoveRequested: root.removeTrigger(index)
                    }
                }

                AddRowButton {
                    buttonText: Translation.tr("Add condition")
                    onClicked: triggerMenu.openAt(this)
                }
            }

            // -------------------------------------------------- then
            EditorSection {
                title: Translation.tr("Then")
                icon: "bolt"
                subtitle: {
                    const n = root.routine?.actions.length ?? 0;
                    if (n === 0)
                        return Translation.tr("Nothing yet — add what the routine should do");
                    const span = ModeSchema.sequenceSpanSec(root.routine?.actions);
                    const base = n === 1 ? Translation.tr("1 action") : Translation.tr("%1 actions, in this order").arg(n);
                    return span > 0 ? Translation.tr("%1, over %2").arg(base).arg(ModeUi.durationText(span)) : base;
                }

                ActionList {
                    Layout.fillWidth: true
                    actions: root.routine?.actions ?? []
                    routineKind: root.routine?.kind ?? "while"
                    ownerId: root.routineId
                    flick: flick
                    onChanged: (index, a) => root.setAction(index, a)
                    onRemoveRequested: index => root.removeAction(index)
                    onMoved: (from, to) => root.moveAction(from, to)
                }

                AddRowButton {
                    buttonText: Translation.tr("Add action")
                    onClicked: actionMenu.openAt(this)
                }
            }

            // -------------------------------------------------- type
            EditorSection {
                title: Translation.tr("Type")
                icon: "sync_alt"
                subtitle: root.isOnce
                    ? Translation.tr("Acts once when its conditions turn true and leaves things as they are")
                    : Translation.tr("Keeps its actions applied while its conditions hold, then puts them back")

                ConfigSelectionArray {
                    Layout.leftMargin: 4
                    currentValue: root.routine?.kind ?? "while"
                    onSelected: value => root.patch({ kind: value })
                    options: [
                        { displayName: Translation.tr("While conditions hold"), value: "while" },
                        { displayName: Translation.tr("When conditions become true"), value: "once" }
                    ]
                }
            }

            // -------------------------------------------------- options
            EditorSection {
                title: Translation.tr("Options")
                icon: "tune"

                EditorRow {
                    visible: root.isOnce
                    icon: "timer"
                    label: Translation.tr("Cooldown")
                    hint: (root.routine?.cooldownSec ?? 0) > 0
                        ? Translation.tr("Will not fire again this soon after the last time")
                        : Translation.tr("Fires on every change")

                    RowLayout {
                        spacing: 6

                        StyledSpinBox {
                            from: 0
                            to: 86400
                            stepSize: 10
                            value: root.routine?.cooldownSec ?? 0
                            onValueModified: root.patch({ cooldownSec: value })
                        }

                        StyledText {
                            text: Translation.tr("s")
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                EditorRow {
                    visible: !root.isOnce
                    icon: "settings_backup_restore"
                    label: Translation.tr("Put settings back when it ends")
                    hint: Translation.tr("Each action can still opt out with its own switch")

                    StyledSwitch {
                        checked: root.routine?.end.revert ?? true
                        onClicked: root.patchEnd({ revert: checked })
                    }
                }

                EditorRow {
                    visible: !root.isOnce
                    icon: "rule"
                    label: Translation.tr("Strict restore")
                    hint: Translation.tr("Also undo settings you changed by hand while it was running")
                    enabled: root.routine?.end.revert ?? true
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.routine?.end.strict ?? false
                        onClicked: root.patchEnd({ strict: checked })
                    }
                }
            }

            // -------------------------------------------------- banners
            EditorSection {
                title: Translation.tr("Banners")
                icon: "campaign"
                subtitle: {
                    if (Config.options.modes.flash === "off")
                        return Translation.tr("Banners are off for every mode in Settings");
                    return root.isOnce ? Translation.tr("A brief pop-up when the routine fires")
                        : Translation.tr("A brief pop-up when the routine starts or ends");
                }

                EditorRow {
                    icon: "play_arrow"
                    label: root.isOnce ? Translation.tr("Show a banner when it fires")
                        : Translation.tr("Show a banner when it starts")
                    enabled: Config.options.modes.flash !== "off"
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.routine?.notify ?? true
                        onClicked: root.patch({ notify: checked })
                    }
                }

                EditorRow {
                    visible: !root.isOnce
                    icon: "stop_circle"
                    label: Translation.tr("Show a banner when it ends")
                    enabled: Config.options.modes.flash !== "off"
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.routine?.end.notify ?? true
                        onClicked: root.patchEnd({ notify: checked })
                    }
                }
            }

            // -------------------------------------------------- footer
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.topMargin: 4
                spacing: 8

                FooterButton {
                    buttonIcon: "content_copy"
                    buttonText: Translation.tr("Duplicate")
                    onClicked: root.duplicated(Modes.duplicateRoutine(root.routineId))
                }

                Item {
                    Layout.fillWidth: true
                }

                FooterButton {
                    visible: !root.confirmDelete
                    buttonIcon: "delete"
                    buttonText: Translation.tr("Delete")
                    danger: true
                    onClicked: root.confirmDelete = true
                }

                StyledText {
                    visible: root.confirmDelete
                    text: root.isRunning ? Translation.tr("Stop and delete this routine?")
                        : Translation.tr("Delete this routine?")
                    color: Appearance.colors.colOnLayer1
                }

                FooterButton {
                    visible: root.confirmDelete
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.confirmDelete = false
                }

                FooterButton {
                    visible: root.confirmDelete
                    buttonIcon: "delete_forever"
                    buttonText: Translation.tr("Delete")
                    danger: true
                    filled: true
                    onClicked: {
                        const id = root.routineId;
                        root.confirmDelete = false;
                        Modes.removeRoutine(id);
                        root.deleted();
                    }
                }
            }
        }
    }

    IconPicker {
        id: iconPicker
        current: root.routine?.icon ?? ""
        onPicked: name => root.patch({ icon: name })
    }

    TypeMenu {
        id: triggerMenu
        parent: root
        choices: root.triggerChoices
        onPicked: key => root.addTrigger(key)
    }

    TypeMenu {
        id: actionMenu
        parent: root
        choices: root.actionChoices
        onPicked: key => root.addAction(key)
    }
}
