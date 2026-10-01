pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * One action of a mode or routine: what it changes and to what. Simple values (on/off,
 * a choice) are edited right on the row; richer ones unfold a form under it. The whole
 * action object is written back on each change.
 *
 * Drawn like the condition rows, on the secondary hue so the two lists of an editor
 * tell apart at a glance: a drag handle when the order can change, a shaped icon, the
 * label with its state pills, and the inline editor or the fold button on the right.
 */
Rectangle {
    id: root

    required property var action
    property bool expanded: false
    /// "" for a mode; "while" / "once" when the row belongs to a routine.
    property string routineKind: ""
    /// The owning routine's id, for the loop check on mode/routine actions.
    property string ownerId: ""

    readonly property string type: root.action?.type ?? ""
    readonly property var entry: Modes.actions.get(root.type)
    readonly property string editor: root.entry?.editor ?? "none"
    readonly property bool available: Modes.actions.isAvailable(root.type)
    readonly property var value: root.action?.value
    readonly property var obj: (root.value && typeof root.value === "object" && !Array.isArray(root.value))
        ? root.value : ({})
    readonly property bool inlineEditor: ModeUi.inlineActionEditors.indexOf(root.editor) !== -1
    readonly property bool hasForm: !root.inlineEditor && root.editor !== "none"
    /// The row prints its value as text (inline controls show it themselves).
    readonly property bool showsValue: !root.inlineEditor || root.editor === "text"
    readonly property bool isWait: root.type === "wait"
    readonly property int delaySec: ModeSchema.durationSec(root.action?.delaySec)
    /// Shows the drag handle; the list decides (one row has nowhere to go).
    property bool draggable: false
    /// The delegate whose copy is being dragged: keeps its slot, shows nothing.
    property bool hidden: false
    /// The copy under the pointer: lifted, no interaction.
    property bool ghost: false
    // Forms line up with the label, which the handle pushes right.
    readonly property int formIndent: root.draggable ? 70 : 46
    // Only actions the engine can put back offer the "undo at end" choice.
    readonly property bool revertible: root.routineKind === "while" && !!root.entry?.read && !!root.entry?.revert
    readonly property bool undoAtEnd: root.action?.revert !== false
    // Routine ids this action would loop back through, or null.
    readonly property var loop: {
        Modes.routines;
        if (!root.ownerId.length || (root.type !== "mode" && root.type !== "routine"))
            return null;
        return Modes.routineLoop(root.ownerId, [root.action]);
    }

    onExpandedChanged: formLoader.sync()

    signal changed(var action)
    signal removeRequested()
    signal dragStarted(real y)
    signal dragMoved(real y)
    signal dragEnded()

    function setValue(v) {
        root.changed(Object.assign({}, ModeSchema.clone(root.action), { value: v }));
    }

    function patchValue(changes) {
        root.setValue(Object.assign({}, ModeSchema.clone(root.obj), changes));
    }

    function setRevert(on) {
        const next = ModeSchema.clone(root.action);
        if (on)
            delete next.revert;
        else
            next.revert = false;
        root.changed(next);
    }

    function setDelay(sec) {
        const next = ModeSchema.clone(root.action);
        if (sec > 0)
            next.delaySec = sec;
        else
            delete next.delaySec;
        root.changed(next);
    }

    // Targets a mode/routine action may point at without closing a loop.
    function loopFree(candidates, makeValue) {
        return candidates.filter(c => Modes.routineLoop(root.ownerId, [{ type: root.type, value: makeValue(c) }]) === null);
    }

    function choiceOptions() {
        let list = [];
        try {
            list = Array.from(root.entry?.choices?.() ?? []);
        } catch (e) {
            list = [];
        }
        return list.map(c => ({ displayName: ModeUi.choiceLabel(root.entry, c), value: c }));
    }

    // A pill beside the label: state the row is in (unavailable, delayed, looping).
    component StatePill: Rectangle {
        id: pill
        property string symbol: ""
        property string label: ""
        property color colFill: ClockStyle.colTertiaryContainer
        property color colInk: ClockStyle.colOnTertiaryContainer

        implicitWidth: pillRow.implicitWidth + ClockStyle.gapSmall * 2
        implicitHeight: 22
        radius: ClockStyle.radiusSmall / 2 + 2
        color: pill.colFill

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 3

            MaterialSymbol {
                visible: pill.symbol.length > 0
                text: pill.symbol
                iconSize: 13
                color: pill.colInk
            }

            StyledText {
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: pill.colInk
            }
        }
    }

    implicitHeight: column.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusSmall
    color: root.ghost ? ClockStyle.colSurfaceHigh
        : (headerArea.containsMouse && !root.expanded) ? ClockStyle.colIdleCardHover : ClockStyle.colPane
    clip: true
    opacity: root.hidden ? 0 : 1

    Behavior on implicitHeight {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    // Hover only: lights the handle up; clicks go through to the controls.
    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // The header is the unfold button too: a click on it, outside the controls, folds
    // the form open or shut.
    MouseArea {
        id: headerArea
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: header.height + ClockStyle.gap * 2
        enabled: !root.isWait
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: ClockStyle.gap
            leftMargin: root.draggable ? ClockStyle.gapTiny : ClockStyle.gap
            rightMargin: ClockStyle.gapSmall
        }
        spacing: ClockStyle.gap

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            // Order is what the engine runs: drag to change it.
            MouseArea {
                id: handle
                visible: root.draggable
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: -ClockStyle.gapTiny
                implicitWidth: 20
                implicitHeight: 36
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                opacity: rowArea.containsMouse || handle.containsMouse || root.ghost ? 1 : 0.35

                Behavior on opacity {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                onPressed: mouse => root.dragStarted(handle.mapToItem(root, mouse.x, mouse.y).y)
                onPositionChanged: mouse => {
                    if (handle.pressed)
                        root.dragMoved(handle.mapToItem(root, mouse.x, mouse.y).y);
                }
                onReleased: root.dragEnded()
                onCanceled: root.dragEnded()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "drag_indicator"
                    iconSize: 20
                    color: ClockStyle.colOnSurfaceVariant
                }
            }

            // The category's shape; hovering or unfolding morphs it into its sibling.
            MaterialShapeWrappedMaterialSymbol {
                text: root.entry?.icon ?? "bolt"
                iconSize: 18
                padding: 9
                shape: ModeUi.actionShape(root.type, root.expanded || headerArea.containsMouse)
                color: !root.available ? ClockStyle.colSurfaceHigh
                    : root.expanded ? ClockStyle.colTertiaryContainer : ClockStyle.colSecondaryContainer
                colSymbol: !root.available ? ClockStyle.colOnSurfaceVariant
                    : root.expanded ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall - 2

                    StyledText {
                        // Shrinks (elides) when the row is tight, never grows past its
                        // text, so the pills stay next to it. Rounded up: a cap a
                        // fraction of a pixel short elides the whole last word.
                        // A caption over the value when the row prints one; the row's
                        // only line when an inline control stands in for the value.
                        Layout.fillWidth: true
                        Layout.maximumWidth: Math.ceil(implicitWidth)
                        text: root.entry?.label ?? root.type
                        elide: Text.ElideRight
                        font.pixelSize: root.showsValue ? Appearance.font.pixelSize.smallest : ClockStyle.textNormal + 1
                        font.weight: root.showsValue ? Font.Bold : Font.DemiBold
                        color: !root.available ? ClockStyle.colSubtext
                            : root.showsValue ? ClockStyle.colOnSurfaceVariant : ClockStyle.colOnSurface
                    }

                    StatePill {
                        visible: !root.available
                        label: Translation.tr("Not available here")
                        colFill: ClockStyle.colErrorContainer
                        colInk: ClockStyle.colOnErrorContainer
                    }

                    // Delayed: the sequence pauses here before this action.
                    StatePill {
                        visible: root.delaySec > 0
                        symbol: "timer"
                        label: ModeUi.actionDelayText(root.action)
                    }

                    // A chain that comes back to this routine: the engine would cut it
                    // after a few hops, but it should not exist.
                    StatePill {
                        id: loopPill
                        visible: root.loop !== null
                        symbol: "sync_problem"
                        label: Translation.tr("Loops back")
                        colFill: ClockStyle.colErrorContainer
                        colInk: ClockStyle.colOnErrorContainer

                        MouseArea {
                            id: loopArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        StyledToolTip {
                            extraVisibleCondition: loopArea.containsMouse
                            text: {
                                const names = (root.loop ?? []).map(id => Modes.routineById(id)?.name ?? id);
                                const chain = names.length ? names.join(" → ") + " → " : "";
                                return Translation.tr("Runs %1this routine again. Pick another target.").arg(chain);
                            }
                        }
                    }

                    // A nested row is only as wide as its children unless one of them
                    // can grow: this one pushes the controls to the right edge.
                    Item {
                        Layout.fillWidth: true
                    }
                }

                StyledText {
                    id: valueText
                    Layout.fillWidth: true
                    visible: root.showsValue
                    text: {
                        const v = ModeUi.actionValueText(root.action);
                        return v.length ? v : Translation.tr("Not set");
                    }
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.Bold
                    color: root.available ? ClockStyle.colOnSurface : ClockStyle.colSubtext

                    HoverHandler {
                        id: valueHover
                    }

                    StyledToolTip {
                        extraVisibleCondition: valueHover.hovered && valueText.truncated
                        text: valueText.text
                    }
                }
            }

            // ---- inline editors
            StyledSwitch {
                visible: root.editor === "switch"
                checked: !!root.value
                onClicked: root.setValue(checked)
            }

            FormChoice {
                visible: root.editor === "segmented"
                Layout.fillWidth: false
                current: root.value ?? ""
                options: root.editor === "segmented" ? root.choiceOptions() : []
                onPicked: v => root.setValue(v)
            }

            StyledComboBox {
                visible: root.editor === "dropdown"
                Layout.fillWidth: false
                Layout.preferredWidth: 200
                model: root.editor === "dropdown"
                    ? root.choiceOptions().map(o => o.value === "" ? Translation.tr("None") : o.displayName) : []
                currentIndex: {
                    const opts = root.choiceOptions();
                    return Math.max(0, opts.findIndex(o => o.value === (root.value ?? "")));
                }
                onActivated: index => root.setValue(root.choiceOptions()[index]?.value ?? "")
            }

            ClockStepper {
                visible: root.editor === "stepper"
                from: 0
                to: Math.max(1, KeyboardBacklight.maxValue)
                value: Number(root.value) || 0
                onMoved: v => root.setValue(v)
            }

            DurationField {
                visible: root.editor === "wait"
                seconds: ModeSchema.durationSec(root.value) || 60
                minimum: 1
                onCommitted: sec => root.setValue(sec)
            }

            // Routines: keep the effect after the routine ends, or put it back.
            RowLayout {
                visible: root.revertible
                spacing: ClockStyle.gapSmall - 2

                StyledText {
                    text: Translation.tr("Undo at end")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                }

                StyledSwitch {
                    checked: root.undoAtEnd
                    onClicked: root.setRevert(checked)

                    StyledToolTip {
                        text: Translation.tr("Off: what this sets stays after the routine ends")
                    }
                }
            }

            FormIconButton {
                buttonIcon: root.expanded ? "expand_less" : "expand_more"
                tooltip: root.expanded ? Translation.tr("Fold") : Translation.tr("Edit")
                visible: !root.isWait
                onClicked: root.expanded = !root.expanded
            }

            FormIconButton {
                buttonIcon: "close"
                tooltip: Translation.tr("Remove action")
                onClicked: root.removeRequested()
            }
        }

        // A URL is short enough to live on the row itself.
        PlainField {
            Layout.fillWidth: true
            Layout.leftMargin: root.formIndent
            Layout.rightMargin: ClockStyle.gapSmall
            Layout.bottomMargin: ClockStyle.gapTiny
            visible: root.editor === "text"
            value: String(root.value ?? "")
            placeholder: Translation.tr("https://…")
            onCommitted: v => root.setValue(v)
        }

        // The parameter form lives in forms/Action<Editor>.qml and gets this row as
        // `row`; it is created on unfold and torn down on fold.
        Loader {
            id: formLoader
            Layout.fillWidth: true
            Layout.leftMargin: root.formIndent
            Layout.rightMargin: ClockStyle.gapSmall
            Layout.bottomMargin: ClockStyle.gapTiny
            visible: status === Loader.Ready && item !== null
            readonly property string formUrl: ModeUi.actionFormUrl(root.editor)
            onFormUrlChanged: formLoader.sync()

            function sync() {
                if (!root.expanded || !formLoader.formUrl.length) {
                    formLoader.source = "";
                    return;
                }
                formLoader.setSource(formLoader.formUrl, { row: root });
            }
        }

        // "Screens off ten minutes after Sleep starts": the list pauses here before this
        // action, so anything below waits too.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.formIndent
            Layout.rightMargin: ClockStyle.gapSmall
            Layout.bottomMargin: ClockStyle.gapTiny
            visible: root.expanded && !root.isWait
            spacing: ClockStyle.gap

            StyledSwitch {
                checked: root.delaySec > 0
                onClicked: root.setDelay(checked ? 300 : 0)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                FormLabel {
                    text: Translation.tr("Delay")
                }

                FormHint {
                    text: root.delaySec > 0
                        ? Translation.tr("Runs %1 after the step above; the rest of the list waits with it").arg(ModeUi.durationText(root.delaySec))
                        : Translation.tr("Runs as soon as its turn comes")
                }
            }

            // Created on demand: a field built while hidden measures its unit strip at
            // zero width and keeps it.
            Loader {
                active: root.delaySec > 0
                visible: active

                sourceComponent: DurationField {
                    seconds: root.delaySec
                    minimum: 1
                    onCommitted: sec => root.setDelay(sec)
                }
            }
        }
    }
}
