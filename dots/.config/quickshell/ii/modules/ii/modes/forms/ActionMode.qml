pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `mode` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: modeCol
    required property var row

    spacing: 8

    readonly property bool stopping: (row.obj.action ?? "start") === "stop"
    // Starting a mode another routine waits for can loop back here.
    readonly property var allowed: modeCol.stopping ? Modes.modes
        : row.loopFree(Modes.modes, m => ({ action: "start", id: m.id }))
    readonly property int hiddenCount: Modes.modes.length - modeCol.allowed.length

    RowLayout {
        spacing: 10

        FormChoice {
            current: row.obj.action ?? "start"
            onPicked: v => row.patchValue({ action: v, id: v === "stop" ? "" : row.obj.id ?? "" })
            options: [
                { displayName: Translation.tr("Start"), value: "start" },
                { displayName: Translation.tr("Stop"), value: "stop" }
            ]
        }

        StyledComboBox {
            Layout.preferredWidth: 220
            model: (modeCol.stopping ? [Translation.tr("Whatever is on")] : [])
                .concat(modeCol.allowed.map(m => m.name))
            currentIndex: {
                const idx = modeCol.allowed.findIndex(m => m.id === (row.obj.id ?? ""));
                return Math.max(0, idx + (modeCol.stopping ? 1 : 0));
            }
            onActivated: index => {
                const i = modeCol.stopping ? index - 1 : index;
                row.patchValue({ id: i < 0 ? "" : (modeCol.allowed[i]?.id ?? "") });
            }
        }
    }

    FormHint {
        visible: modeCol.hiddenCount > 0
        text: modeCol.hiddenCount === 1
            ? Translation.tr("1 mode hidden: a routine waiting for it would run this one again")
            : Translation.tr("%1 modes hidden: a routine waiting for them would run this one again").arg(modeCol.hiddenCount)
    }

    FormHint {
        visible: !modeCol.stopping && !Modes.modes.length
        text: Translation.tr("There is no mode to start yet.")
    }
}
