pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `routine` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: routineCol
    required property var row

    spacing: 8

    readonly property bool stopping: (row.obj.action ?? "run") === "stop"
    readonly property var others: Modes.routines.filter(r => r.id !== row.ownerId)
    readonly property var allowed: routineCol.stopping ? routineCol.others
        : row.loopFree(routineCol.others, r => ({ action: "run", id: r.id }))
    readonly property int hiddenCount: routineCol.others.length - routineCol.allowed.length

    RowLayout {
        spacing: 10

        FormChoice {
            current: row.obj.action ?? "run"
            onPicked: v => row.patchValue({ action: v })
            options: [
                { displayName: Translation.tr("Run"), value: "run" },
                { displayName: Translation.tr("Stop"), value: "stop" }
            ]
        }

        StyledComboBox {
            Layout.preferredWidth: 220
            model: [Translation.tr("Choose…")].concat(routineCol.allowed.map(r => r.name))
            currentIndex: Math.max(0, routineCol.allowed.findIndex(r => r.id === (row.obj.id ?? "")) + 1)
            onActivated: index => row.patchValue({ id: index === 0 ? "" : (routineCol.allowed[index - 1]?.id ?? "") })
        }
    }

    FormHint {
        visible: routineCol.hiddenCount > 0
        text: routineCol.hiddenCount === 1
            ? Translation.tr("1 routine hidden: it would run this one again")
            : Translation.tr("%1 routines hidden: they would run this one again").arg(routineCol.hiddenCount)
    }

    FormHint {
        visible: !routineCol.others.length
        text: Translation.tr("There is no other routine yet.")
    }
}
