pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `hyprland` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: hyprlandCol
    required property var row

    spacing: 10

    readonly property var presets: ModeSchema.stringList(row.obj.presets)
    readonly property var options: row.obj.options ?? ({})
    readonly property var optionKeys: Object.keys(row.obj.options ?? {})

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: Object.keys(ModeSchema.HYPRLAND_PRESETS)

            delegate: ClockChip {
                id: presetChip
                required property string modelData
                readonly property bool on: hyprlandCol.presets.indexOf(presetChip.modelData) !== -1

                height_: 32
                selected: presetChip.on
                symbol: presetChip.on ? "check" : ""
                label: ModeUi.hyprlandPresetLabel(presetChip.modelData)
                onClicked: {
                    const list = ModeSchema.stringList(row.obj.presets);
                    const idx = list.indexOf(presetChip.modelData);
                    if (idx === -1)
                        list.push(presetChip.modelData);
                    else
                        list.splice(idx, 1);
                    row.patchValue({ presets: list, options: row.obj.options ?? {} });
                }
            }
        }
    }

    FormHint {
        text: Translation.tr("Presets turn the named effect off for the duration of the mode "
            + "(tearing: on). Add raw options below for anything else.")
    }

    Repeater {
        model: hyprlandCol.optionKeys

        delegate: RowLayout {
            id: optionRow
            required property string modelData
            Layout.fillWidth: true
            spacing: 6

            PlainField {
                Layout.preferredWidth: 240
                monospace: true
                value: optionRow.modelData
                placeholder: "general:gaps_out"
                onCommitted: v => {
                    const opts = ModeSchema.clone(row.obj.options ?? {});
                    const val = opts[optionRow.modelData];
                    delete opts[optionRow.modelData];
                    if (v.trim().length)
                        opts[v.trim()] = val;
                    row.patchValue({ options: opts });
                }
            }

            StyledText {
                text: "="
                color: ClockStyle.colSubtext
            }

            PlainField {
                Layout.fillWidth: true
                monospace: true
                value: String((row.obj.options ?? {})[optionRow.modelData] ?? "")
                placeholder: "0"
                onCommitted: v => {
                    const opts = ModeSchema.clone(row.obj.options ?? {});
                    opts[optionRow.modelData] = v;
                    row.patchValue({ options: opts });
                }
            }

            FormIconButton {
                buttonIcon: "close"
                onClicked: {
                    const opts = ModeSchema.clone(row.obj.options ?? {});
                    delete opts[optionRow.modelData];
                    row.patchValue({ options: opts });
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        PlainField {
            id: newKey
            Layout.preferredWidth: 240
            monospace: true
            placeholder: Translation.tr("option, e.g. general:gaps_out")
        }

        StyledText {
            text: "="
            color: ClockStyle.colSubtext
        }

        PlainField {
            id: newValue
            Layout.fillWidth: true
            monospace: true
            placeholder: Translation.tr("value")
        }

        // Reads what is typed, not `value`: these two fields have nothing to commit to,
        // and their `value` never left "".
        SmallButton {
            buttonText: Translation.tr("Add")
            onClicked: {
                const key = newKey.text.trim();
                if (!key.length)
                    return;
                const opts = ModeSchema.clone(row.obj.options ?? {});
                opts[key] = newValue.text;
                row.patchValue({ options: opts });
                newKey.clear();
                newValue.clear();
            }
        }
    }
}
