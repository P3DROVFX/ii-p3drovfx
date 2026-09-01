pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * One action of a mode: what it changes and to what. Simple values
 * (on/off, a choice) are edited right on the row; richer ones unfold a
 * form under it. The whole action object is written back on each change.
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
    readonly property bool isWait: root.type === "wait"
    readonly property int delaySec: ModeSchema.durationSec(root.action?.delaySec)
    /// Shows the drag handle; the list decides (one row has nowhere to go).
    property bool draggable: false
    /// The delegate whose copy is being dragged: keeps its slot, shows nothing.
    property bool hidden: false
    /// The copy under the pointer: lifted, no interaction.
    property bool ghost: false
    // Forms line up with the label, which the handle pushes right.
    readonly property int formIndent: root.draggable ? 62 : 34
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

    implicitHeight: column.implicitHeight + 16
    radius: Appearance.rounding.normal
    color: headerArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    clip: true
    opacity: root.hidden ? 0 : 1

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    // Hover only: lights the handle up; clicks go through to the controls.
    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // The header is the unfold button too: a click on it, outside the
    // controls, folds the form open or shut.
    MouseArea {
        id: headerArea
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: header.height + 16
        enabled: !root.isWait
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: 8
            leftMargin: root.draggable ? 4 : 14
            rightMargin: 8
        }
        spacing: 8

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: 12

            // Order is what the engine runs: drag to change it.
            MouseArea {
                id: handle
                visible: root.draggable
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: -4
                implicitWidth: 20
                implicitHeight: 36
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                opacity: rowArea.containsMouse || handle.containsMouse || root.ghost ? 1 : 0.35

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
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
                    color: Appearance.colors.colSubtext
                }
            }

            MaterialSymbol {
                text: root.entry?.icon ?? "bolt"
                iconSize: 22
                color: root.available ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        // Shrinks (elides) when the row is tight, never grows
                        // past its text, so the pills stay next to it. Rounded
                        // up: a cap a fraction of a pixel short elides the
                        // whole last word.
                        Layout.fillWidth: true
                        Layout.maximumWidth: Math.ceil(implicitWidth)
                        text: root.entry?.label ?? root.type
                        elide: Text.ElideRight
                        color: root.available ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                    }

                    Rectangle {
                        visible: !root.available
                        implicitWidth: unavailableText.implicitWidth + 14
                        implicitHeight: 20
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colErrorContainer

                        StyledText {
                            id: unavailableText
                            anchors.centerIn: parent
                            text: Translation.tr("Not available here")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }

                    // Delayed: the sequence pauses here before this action.
                    Rectangle {
                        visible: root.delaySec > 0
                        implicitWidth: delayRow.implicitWidth + 14
                        implicitHeight: 20
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colTertiaryContainer

                        RowLayout {
                            id: delayRow
                            anchors.centerIn: parent
                            spacing: 3

                            MaterialSymbol {
                                text: "timer"
                                iconSize: 12
                                color: Appearance.colors.colOnTertiaryContainer
                            }

                            StyledText {
                                text: ModeUi.actionDelayText(root.action)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnTertiaryContainer
                            }
                        }
                    }

                    // A chain that comes back to this routine: the engine
                    // would cut it after a few hops, but it should not exist.
                    Rectangle {
                        visible: root.loop !== null
                        implicitWidth: loopRow.implicitWidth + 14
                        implicitHeight: 20
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colErrorContainer

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

                        RowLayout {
                            id: loopRow
                            anchors.centerIn: parent
                            spacing: 3

                            MaterialSymbol {
                                text: "sync_problem"
                                iconSize: 12
                                color: Appearance.colors.colOnErrorContainer
                            }

                            StyledText {
                                text: Translation.tr("Loops back")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnErrorContainer
                            }
                        }
                    }

                    // A nested row is only as wide as its children unless
                    // one of them can grow: this one pushes the controls
                    // to the right edge.
                    Item {
                        Layout.fillWidth: true
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.inlineEditor || root.editor === "text"
                    text: {
                        const v = ModeUi.actionValueText(root.action);
                        return v.length ? v : Translation.tr("Not set");
                    }
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
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
                options: root.choiceOptions()
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

            StyledSpinBox {
                visible: root.editor === "stepper"
                from: 0
                to: Math.max(1, KeyboardBacklight.maxValue)
                value: Number(root.value) || 0
                onValueModified: root.setValue(value)
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
                spacing: 6

                StyledText {
                    text: Translation.tr("Undo at end")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
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
                visible: !root.isWait
                onClicked: root.expanded = !root.expanded
            }

            FormIconButton {
                buttonIcon: "close"
                onClicked: root.removeRequested()
            }
        }

        // A URL is short enough to live on the row itself.
        PlainField {
            Layout.fillWidth: true
            Layout.leftMargin: root.formIndent
            Layout.rightMargin: 6
            Layout.bottomMargin: 4
            visible: root.editor === "text"
            value: String(root.value ?? "")
            placeholder: Translation.tr("https://…")
            onCommitted: v => root.setValue(v)
        }

        // The parameter form lives in forms/Action<Editor>.qml and gets this
        // row as `row`; it is created on unfold and torn down on fold.
        Loader {
            id: formLoader
            Layout.fillWidth: true
            Layout.leftMargin: root.formIndent
            Layout.rightMargin: 6
            Layout.bottomMargin: 4
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

        // "Screens off ten minutes after Sleep starts": the list pauses here
        // before this action, so anything below waits too.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.formIndent
            Layout.rightMargin: 6
            Layout.bottomMargin: 4
            visible: root.expanded && !root.isWait
            spacing: 10

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

            // Created on demand: a field built while hidden measures its
            // unit strip at zero width and keeps it.
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
