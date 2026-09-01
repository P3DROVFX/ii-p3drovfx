pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `shortcut` event. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 *
 * This is the one trigger with a second half somewhere else: the routine
 * only listens, and nothing runs it until a key is bound to its global.
 * So the form both binds it and says whether it already is.
 */
ColumnLayout {
    id: form
    required property var row

    spacing: 10

    readonly property string name: ModeSchema.shortcutName(row.trigger, row.ownerId)
    readonly property string globalName: `quickshell:modes-${form.name}`

    /// Reading this builds the shortcut service, which parses the config files - so it happens
    /// when the form is unfolded and not before.
    readonly property var boundRow: HyprlandBinds.boundToGlobal(form.globalName)

    // The shortcut service stops following config reloads while the hub is closed, so ask it to
    // catch up before reading which key this routine is on.
    Component.onCompleted: HyprlandBinds.ensureFresh()

    readonly property string boundLabel: form.boundRow
        ? HyprlandBinds.comboLabel(form.boundRow.mods, form.boundRow.key) : ""

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            text: Translation.tr("Name")
        }

        PlainField {
            Layout.preferredWidth: 200
            monospace: true
            value: row.trigger.name
            placeholder: form.name
            onCommitted: v => row.set({ name: v })
        }

        FormHint {
            text: Translation.tr("Optional; the routine's id otherwise")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        SmallButton {
            buttonText: form.boundRow ? Translation.tr("Change the key") : Translation.tr("Bind a key")
            onClicked: {
                GlobalStates.modesOpen = false;
                if (form.boundRow) {
                    HyprlandBinds.requestEditBind(form.boundRow);
                    return;
                }
                HyprlandBinds.requestNewBind("global", form.globalName,
                    Translation.tr("Run the %1 routine").arg(form.name));
            }
        }

        FormHint {
            Layout.fillWidth: true
            text: {
                if (!HyprlandBinds.ready)
                    return Translation.tr("Looking for a key…");
                if (form.boundRow)
                    return Translation.tr("%1 runs this now").arg(form.boundLabel);
                return Translation.tr("Nothing runs this yet");
            }
        }
    }

    FormHint {
        text: Translation.tr("Or bind it by hand, in your Hyprland config:")
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: bindText.implicitHeight + 16
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer3

        StyledText {
            id: bindText
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
                topMargin: 8
            }
            text: `hl.bind("SUPER + SHIFT + R", hl.dsp.global("${form.globalName}"))\n`
                + `bind = SUPER SHIFT, R, global, ${form.globalName}`
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer3
        }
    }

    FormHint {
        text: Translation.tr("First line for the Lua config, second for a classic hyprland.conf.")
    }
}
