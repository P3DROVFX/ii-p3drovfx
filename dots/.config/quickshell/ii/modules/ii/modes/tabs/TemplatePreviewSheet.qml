pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.modes
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * A ready-made routine, previewed in the side sheet before it is in the list: the
 * routine it would create, laid out like the editor but read-only — If / Then / Type /
 * Options — with one button to add it. Adding makes a copy that is an ordinary routine
 * from then on; the template stays in Discover.
 *
 * Enter adds, Escape closes.
 */
ClockSheet {
    id: root

    property string templateKey: ""

    signal added(string id)

    readonly property var template: ModeSchema.routineTemplate(root.templateKey)
    readonly property bool isOnce: root.template?.kind === "once"
    readonly property string colorKey: root.template?.color ?? ""
    readonly property var triggers: Array.from(root.template?.triggers ?? [])
    // Not `actions`: that is the sheet's footer slot.
    readonly property var steps: Array.from(root.template?.actions ?? [])
    readonly property int copies: Modes.routines.filter(r => r.template === root.templateKey).length

    function add(): void {
        const id = Modes.addRoutineFromTemplate(root.templateKey);
        root.close();
        if (id.length)
            root.added(id);
    }

    title: root.template?.name ?? ""
    subtitle: Translation.tr("Template")

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.add();
            event.accepted = true;
        }
    }

    // A small value chip on a read-only row.
    component ValueChip: Rectangle {
        id: valueChip
        property string label: ""

        implicitWidth: valueText.implicitWidth + ClockStyle.gap * 2
        implicitHeight: 28
        radius: ClockStyle.radiusSmall
        color: ClockStyle.colSecondaryContainer

        StyledText {
            id: valueText
            anchors.centerIn: parent
            text: valueChip.label
            font.pixelSize: ClockStyle.textSmall
            font.weight: Font.DemiBold
            color: ClockStyle.colOnSecondaryContainer
        }
    }

    // ── What it is ──────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: introColumn.implicitHeight + ClockStyle.gapLarge * 2
        radius: ClockStyle.radiusLarge
        color: ModeUi.container(root.colorKey)

        ColumnLayout {
            id: introColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                MaterialShapeWrappedMaterialSymbol {
                    text: root.template?.icon ?? "bolt"
                    iconSize: 26
                    padding: 14
                    shape: MaterialShape.Shape.Cookie6Sided
                    color: ModeUi.accent(root.colorKey)
                    colSymbol: ModeUi.onAccent(root.colorKey)
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapTiny + 2

                    Rectangle {
                        implicitWidth: kindRow.implicitWidth + ClockStyle.gap * 2
                        implicitHeight: 28
                        radius: ClockStyle.radiusSmall
                        color: ColorUtils.applyAlpha(ModeUi.onContainer(root.colorKey), 0.12)

                        RowLayout {
                            id: kindRow
                            anchors.centerIn: parent
                            spacing: ClockStyle.gapTiny

                            MaterialSymbol {
                                text: root.isOnce ? "bolt" : "sync_alt"
                                iconSize: ClockStyle.iconSmall - 1
                                color: ModeUi.onContainer(root.colorKey)
                            }

                            StyledText {
                                text: ModeUi.routineKindText(root.template?.kind ?? "while")
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.DemiBold
                                color: ModeUi.onContainer(root.colorKey)
                            }
                        }
                    }

                    Rectangle {
                        visible: root.copies > 0
                        implicitWidth: copiesRow.implicitWidth + ClockStyle.gap * 2
                        implicitHeight: 28
                        radius: ClockStyle.radiusSmall
                        color: ClockStyle.colSecondaryContainer

                        RowLayout {
                            id: copiesRow
                            anchors.centerIn: parent
                            spacing: ClockStyle.gapTiny

                            MaterialSymbol {
                                text: "check"
                                iconSize: ClockStyle.iconSmall - 1
                                color: ClockStyle.colOnSecondaryContainer
                            }

                            StyledText {
                                text: root.copies === 1 ? Translation.tr("In your list")
                                    : Translation.tr("In your list ×%1").arg(root.copies)
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.DemiBold
                                color: ClockStyle.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: ModeUi.templateText(root.template)
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textNormal
                color: ModeUi.onContainer(root.colorKey)
            }
        }
    }

    // ── If ──────────────────────────────────────────────────────────────
    EditorSection {
        title: Translation.tr("If")
        icon: "filter_alt"
        subtitle: {
            if (root.triggers.length === 0)
                return Translation.tr("No conditions: runs by hand only");
            const how = root.isOnce ? Translation.tr("Fires the moment a condition below becomes true")
                : Translation.tr("Runs for as long as a condition below holds");
            if (root.triggers.length < 2)
                return how;
            return how + " · " + (root.template?.match === "all"
                ? Translation.tr("all of them") : Translation.tr("any of them"));
        }

        Repeater {
            model: root.triggers

            delegate: EditorRow {
                id: triggerRow
                required property var modelData

                onSheet: true
                icon: ModeUi.triggerTypeIcon(triggerRow.modelData.type)
                label: ModeUi.triggerTypeLabel(triggerRow.modelData.type)
                hint: ModeUi.triggerText(triggerRow.modelData)

                ValueChip {
                    visible: triggerRow.modelData.not === true
                    label: Translation.tr("Inverted")
                }
            }
        }
    }

    // ── Then ────────────────────────────────────────────────────────────
    EditorSection {
        title: Translation.tr("Then")
        icon: "bolt"
        subtitle: {
            const span = ModeSchema.sequenceSpanSec(root.steps);
            const base = root.steps.length === 1 ? Translation.tr("1 action")
                : Translation.tr("%1 actions, in this order").arg(root.steps.length);
            return span > 0 ? Translation.tr("%1, over %2").arg(base).arg(ModeUi.durationText(span)) : base;
        }

        Repeater {
            model: root.steps

            delegate: EditorRow {
                id: actionRow
                required property var modelData

                onSheet: true
                icon: ModeUi.actionIcon(actionRow.modelData.type)
                label: ModeUi.actionLabel(actionRow.modelData.type)
                hint: {
                    const delay = ModeUi.actionDelayText(actionRow.modelData);
                    const value = ModeUi.actionValueText(actionRow.modelData);
                    return delay.length ? `${delay} · ${value}` : value;
                }
            }
        }
    }

    // ── Type and options ────────────────────────────────────────────────
    EditorSection {
        title: Translation.tr("Options")
        icon: "tune"
        subtitle: root.isOnce
            ? Translation.tr("Acts once when its conditions turn true and leaves things as they are")
            : Translation.tr("Keeps its actions applied while its conditions hold, then puts them back")

        EditorRow {
            visible: root.isOnce
            onSheet: true
            icon: "timer"
            label: Translation.tr("Cooldown")
            hint: (root.template?.cooldownSec ?? 0) > 0
                ? Translation.tr("Will not fire again this soon after the last time")
                : Translation.tr("Fires on every change")

            ValueChip {
                label: (root.template?.cooldownSec ?? 0) > 0
                    ? ModeUi.durationText(root.template?.cooldownSec ?? 0) : Translation.tr("None")
            }
        }

        EditorRow {
            visible: !root.isOnce
            onSheet: true
            icon: "settings_backup_restore"
            label: Translation.tr("Put settings back when it ends")

            ValueChip {
                label: ModeUi.onOff(root.template?.end?.revert ?? true)
            }
        }

        EditorRow {
            onSheet: true
            icon: "play_arrow"
            label: root.isOnce ? Translation.tr("Show a banner when it fires")
                : Translation.tr("Show a banner when it starts")

            ValueChip {
                label: ModeUi.onOff(root.template?.notify ?? true)
            }
        }

        EditorRow {
            visible: !root.isOnce
            onSheet: true
            icon: "stop_circle"
            label: Translation.tr("Show a banner when it ends")

            ValueChip {
                label: ModeUi.onOff(root.template?.end?.notify ?? root.template?.notify ?? true)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Adding makes a copy you can rename and edit freely; the template stays here.")
        wrapMode: Text.Wrap
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Close")
            symbol: "close"
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            symbol: "add"
            label: root.copies > 0 ? Translation.tr("Add another copy") : Translation.tr("Add to my routines")
            onClicked: root.add()
        }
    ]
}
