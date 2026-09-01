pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * The right pane: one mode, fully editable in place. Every control writes
 * straight to the engine (which queues the save); there is no Save button.
 *
 * Editing a mode that is running does not touch what it applied — the old
 * snapshot must stay reversible — so a bar offers to restart it instead.
 */
Item {
    id: root

    required property string modeId
    readonly property var mode: Modes.modeById(root.modeId)
    readonly property bool isActive: Modes.activeModeId === root.modeId
    readonly property string colorKey: root.mode?.color ?? ""
    readonly property bool hasMode: root.mode !== null && root.mode !== undefined

    property bool confirmDelete: false
    // Actions changed while the mode was running: the engine still holds
    // the snapshot of the old set, so the new one only applies on restart.
    property bool actionsEdited: false

    signal requestClose()
    signal deleted()
    signal duplicated(string id)

    onModeIdChanged: {
        root.confirmDelete = false;
        root.actionsEdited = false;
    }

    onIsActiveChanged: root.actionsEdited = false

    function patch(changes) {
        if (!root.hasMode)
            return;
        const next = Object.assign({}, ModeSchema.clone(root.mode), changes);
        Modes.upsertMode(next);
    }

    function patchEnd(changes) {
        root.patch({ end: Object.assign({}, root.mode.end, changes) });
    }

    function setTrigger(index, trigger) {
        const list = ModeSchema.clone(root.mode.triggers);
        list[index] = trigger;
        root.patch({ triggers: list });
    }

    function removeTrigger(index) {
        const list = ModeSchema.clone(root.mode.triggers);
        list.splice(index, 1);
        root.patch({ triggers: list });
    }

    function addTrigger(type) {
        const list = ModeSchema.clone(root.mode.triggers);
        list.push(ModeSchema.normalizeTrigger({ type: type }));
        root.patch({ triggers: list });
    }

    function setAction(index, action) {
        const list = ModeSchema.clone(root.mode.actions);
        list[index] = action;
        root.patch({ actions: list });
        if (root.isActive)
            root.actionsEdited = true;
    }

    function removeAction(index) {
        const list = ModeSchema.clone(root.mode.actions);
        list.splice(index, 1);
        root.patch({ actions: list });
        if (root.isActive)
            root.actionsEdited = true;
    }

    function moveAction(from, to) {
        const list = ModeSchema.clone(root.mode.actions);
        if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length)
            return;
        const [item] = list.splice(from, 1);
        list.splice(to, 0, item);
        root.patch({ actions: list });
        if (root.isActive)
            root.actionsEdited = true;
    }

    function addAction(type) {
        const list = ModeSchema.clone(root.mode.actions);
        list.push({ type: type, value: ModeUi.defaultActionValue(type) });
        root.patch({ actions: list });
        if (root.isActive)
            root.actionsEdited = true;
    }

    function focusName() {
        nameField.forceActiveFocus();
        nameField.selectAll();
    }

    // Pickers and the delete confirm take Escape before the window does.
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
            nameField.text = root.mode?.name ?? "";
            nameField.focus = false;
            return true;
        }
        return false;
    }

    function handleKey(key, modifiers) {
        // Text fields keep their own keys; the list handles the rest.
        return nameField.activeFocus;
    }

    readonly property var triggerChoices: {
        const out = [];
        for (const type in ModeSchema.TRIGGER_TYPES) {
            const meta = ModeSchema.TRIGGER_TYPES[type];
            if (meta.routineOnly)
                continue;
            out.push({
                key: type, label: Translation.tr(meta.label), icon: meta.icon,
                group: ModeUi.triggerGroupLabel(type), enabled: true, hint: ""
            });
        }
        return out;
    }

    readonly property var actionChoices: {
        const out = [];
        const used = root.mode ? root.mode.actions.map(a => a.type) : [];
        for (const type of Modes.actions.types()) {
            const entry = Modes.actions.get(type);
            if (entry.routineOnly)
                continue;
            const available = Modes.actions.isAvailable(type);
            const taken = !entry.repeatable && used.indexOf(type) !== -1;
            out.push({
                key: type,
                label: entry.label,
                icon: entry.icon,
                group: Modes.actions.categories[entry.category]?.label ?? entry.category,
                enabled: available && !taken,
                hint: !available ? Translation.tr("Not available on this machine")
                    : (taken ? Translation.tr("Already in this mode") : "")
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
                    id: iconButton
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
                            text: root.mode?.icon ?? "tune"
                            iconSize: 32
                            fill: root.isActive ? 1 : 0
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

                    // The name is edited in place; committed on Enter or when
                    // focus leaves, never per keystroke.
                    StyledTextInput {
                        id: nameField
                        Layout.fillWidth: true
                        text: root.mode?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        selectByMouse: true
                        clip: true
                        onEditingFinished: {
                            const next = nameField.text.trim();
                            if (next.length && next !== root.mode?.name)
                                root.patch({ name: next });
                            else
                                nameField.text = root.mode?.name ?? "";
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
                        text: ModeUi.modeHeaderStatus(root.mode)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.isActive ? ModeUi.accent(root.colorKey) : Appearance.colors.colSubtext
                    }

                    ColorDots {
                        Layout.topMargin: 8
                        current: root.colorKey
                        onPicked: key => root.patch({ color: key })
                    }
                }

                RippleButton {
                    id: startButton
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 4
                    implicitHeight: 48
                    implicitWidth: startRow.implicitWidth + 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.isActive ? Appearance.colors.colSecondaryContainer : ModeUi.accent(root.colorKey)
                    colBackgroundHover: root.isActive ? Appearance.colors.colSecondaryContainerHover
                        : ColorUtils.mix(ModeUi.accent(root.colorKey), ModeUi.onAccent(root.colorKey), 0.9)
                    colRipple: root.isActive ? Appearance.colors.colSecondaryContainerActive
                        : ColorUtils.mix(ModeUi.accent(root.colorKey), ModeUi.onAccent(root.colorKey), 0.8)
                    onClicked: Modes.toggle(root.modeId)

                    contentItem: RowLayout {
                        id: startRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: root.isActive ? "stop" : "play_arrow"
                            iconSize: 22
                            fill: 1
                            color: root.isActive ? Appearance.colors.colOnSecondaryContainer : ModeUi.onAccent(root.colorKey)
                        }

                        StyledText {
                            text: root.isActive ? Translation.tr("Turn off") : Translation.tr("Turn on")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: root.isActive ? Appearance.colors.colOnSecondaryContainer : ModeUi.onAccent(root.colorKey)
                        }
                    }
                }
            }

            // Running with stale actions: offer the restart instead of
            // silently re-applying under the user.
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                visible: root.isActive && root.actionsEdited
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
                        text: Translation.tr("Changes apply the next time this mode starts.")
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
                            Modes.restartActive();
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

            // -------------------------------------------------- triggers
            EditorSection {
                title: Translation.tr("Turn on automatically")
                icon: "autoplay"
                subtitle: root.mode?.triggers.length
                    ? (root.mode.auto ? Translation.tr("Starts when a condition below is met")
                        : Translation.tr("Conditions are set but automatic start is off"))
                    : Translation.tr("No conditions: this mode starts by hand only")

                headerItem: RowLayout {
                    spacing: 10

                    StyledSwitch {
                        visible: (root.mode?.triggers.length ?? 0) > 0
                        checked: root.mode?.auto ?? false
                        onClicked: root.patch({ auto: checked })
                    }
                }

                // With two or more conditions the question "all or any" exists.
                RowLayout {
                    Layout.fillWidth: true
                    visible: (root.mode?.triggers.length ?? 0) > 1
                    spacing: 10

                    StyledText {
                        text: Translation.tr("Start when")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    ConfigSelectionArray {
                        currentValue: root.mode?.match ?? "any"
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
                    model: root.mode?.triggers.length ?? 0

                    delegate: TriggerRow {
                        required property int index

                        Layout.fillWidth: true
                        trigger: root.mode?.triggers[index] ?? ({})
                        watcher: {
                            Modes.watchersRevision;
                            return Modes.watcherFor(root.modeId);
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

            // -------------------------------------------------- actions
            EditorSection {
                title: Translation.tr("When it's on")
                icon: "tune"
                subtitle: {
                    const n = root.mode?.actions.length ?? 0;
                    if (n === 0)
                        return Translation.tr("Nothing yet — add what the mode should change");
                    const span = ModeSchema.sequenceSpanSec(root.mode?.actions);
                    const base = n === 1 ? Translation.tr("1 setting applied")
                        : Translation.tr("%1 settings applied, in this order").arg(n);
                    return span > 0 ? Translation.tr("%1, over %2").arg(base).arg(ModeUi.durationText(span)) : base;
                }

                ActionList {
                    Layout.fillWidth: true
                    actions: root.mode?.actions ?? []
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

            // -------------------------------------------------- end
            EditorSection {
                title: Translation.tr("When it ends")
                icon: "undo"

                EditorRow {
                    icon: "settings_backup_restore"
                    label: Translation.tr("Put settings back")
                    hint: Translation.tr("Restore what the mode changed")

                    StyledSwitch {
                        checked: root.mode?.end.revert ?? true
                        onClicked: root.patchEnd({ revert: checked })
                    }
                }

                EditorRow {
                    icon: "rule"
                    label: Translation.tr("Strict restore")
                    hint: Translation.tr("Also undo settings you changed by hand while it was on")
                    enabled: root.mode?.end.revert ?? true
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.mode?.end.strict ?? false
                        onClicked: root.patchEnd({ strict: checked })
                    }
                }

                EditorRow {
                    icon: "timer"
                    label: Translation.tr("Turn off after")
                    hint: (root.mode?.end.autoOffMin ?? 0) > 0
                        ? Translation.tr("Ends on its own after this long") : Translation.tr("Stays on until stopped")

                    RowLayout {
                        spacing: 6

                        StyledSpinBox {
                            from: 0
                            to: 1440
                            stepSize: 5
                            value: root.mode?.end.autoOffMin ?? 0
                            onValueModified: root.patchEnd({ autoOffMin: value })
                        }

                        StyledText {
                            text: Translation.tr("min")
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // -------------------------------------------------- banners
            EditorSection {
                title: Translation.tr("Banners")
                icon: "campaign"
                subtitle: Config.options.modes.flash === "off"
                    ? Translation.tr("Banners are off for every mode in Settings")
                    : Translation.tr("A brief pop-up when the mode switches on or off")

                EditorRow {
                    icon: "play_arrow"
                    label: Translation.tr("Show a banner when it starts")
                    enabled: Config.options.modes.flash !== "off"
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.mode?.notify ?? true
                        onClicked: root.patch({ notify: checked })
                    }
                }

                EditorRow {
                    icon: "stop_circle"
                    label: Translation.tr("Show a banner when it ends")
                    enabled: Config.options.modes.flash !== "off"
                    opacity: enabled ? 1 : 0.5

                    StyledSwitch {
                        checked: root.mode?.end.notify ?? true
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
                    onClicked: root.duplicated(Modes.duplicateMode(root.modeId))
                }

                FooterButton {
                    visible: root.mode?.preset ?? false
                    buttonIcon: "restart_alt"
                    buttonText: Translation.tr("Reset to preset")
                    onClicked: Modes.resetPreset(root.modeId)
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
                    text: root.isActive ? Translation.tr("Turn off and delete this mode?")
                        : Translation.tr("Delete this mode?")
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
                        const id = root.modeId;
                        root.confirmDelete = false;
                        Modes.removeMode(id);
                        root.deleted();
                    }
                }
            }
        }
    }

    IconPicker {
        id: iconPicker
        current: root.mode?.icon ?? ""
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
