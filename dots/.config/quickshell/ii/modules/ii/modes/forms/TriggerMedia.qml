pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

/**
 * Parameters of the `media` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.playing === false ? "silent" : "playing"
        onPicked: v => row.set({ playing: v === "playing" })
        options: [
            { displayName: Translation.tr("Something is playing"), value: "playing" },
            { displayName: Translation.tr("Nothing is playing"), value: "silent" }
        ]
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            text: Translation.tr("Player")
        }

        PlainField {
            Layout.fillWidth: true
            value: row.trigger.player
            placeholder: Translation.tr("Part of the player's name — empty means any")
            onCommitted: v => row.set({ player: v })
        }
    }

    FormHint {
        readonly property var names: Array.from(Mpris.players?.values ?? []).map(p => p?.identity).filter(n => n)
        visible: names.length > 0
        text: Translation.tr("Open now: %1").arg(names.join(", "))
    }
}
