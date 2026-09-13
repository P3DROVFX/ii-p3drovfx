pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
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

            delegate: RippleButton {
                id: presetChip
                required property string modelData
                readonly property bool on: hyprlandCol.presets.indexOf(presetChip.modelData) !== -1

                implicitHeight: 32
                implicitWidth: presetRow.implicitWidth + 22
                buttonRadius: Appearance.rounding.full
                colBackground: on ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                colBackgroundHover: on ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
                colRipple: on ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
                onClicked: {
                    const list = ModeSchema.stringList(row.obj.presets);
                    const idx = list.indexOf(presetChip.modelData);
                    if (idx === -1)
                        list.push(presetChip.modelData);
                    else
                        list.splice(idx, 1);
                    row.patchValue({ presets: list, options: row.obj.options ?? {} });
                }

                contentItem: RowLayout {
                    id: presetRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        visible: presetChip.on
                        text: "check"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledText {
                        text: ModeUi.hyprlandPresetLabel(presetChip.modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: presetChip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                    }
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
                color: Appearance.colors.colSubtext
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
            color: Appearance.colors.colSubtext
        }

        PlainField {
            id: newValue
            Layout.fillWidth: true
            monospace: true
            placeholder: Translation.tr("value")
        }

        SmallButton {
            buttonText: Translation.tr("Add")
            onClicked: {
                const key = newKey.value.trim();
                if (!key.length)
                    return;
                const opts = ModeSchema.clone(row.obj.options ?? {});
                opts[key] = newValue.value;
                row.patchValue({ options: opts });
                newKey.value = "";
                newValue.value = "";
            }
        }
    }
}
