pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `pingPhone` action, over KDE Connect. `row` is the
 * ActionRow this form unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: phoneCol
    required property var row

    spacing: 10

    readonly property bool ringing: (row.obj.kind ?? "ping") === "ring"

    FormChoice {
        current: phoneCol.ringing ? "ring" : "ping"
        onPicked: v => row.patchValue({ kind: v })
        options: [
            { displayName: Translation.tr("Send a ping"), value: "ping" },
            { displayName: Translation.tr("Make it ring"), value: "ring" }
        ]
    }

    PlainField {
        Layout.fillWidth: true
        visible: !phoneCol.ringing
        value: String(row.obj.message ?? "")
        placeholder: Translation.tr("Message shown on the phone (optional)")
        onCommitted: v => row.patchValue({ message: v })
    }

    FormHint {
        text: KdeConnectService.activeReachable
            ? Translation.tr("To %1, which is reachable now").arg(KdeConnectService.activeDeviceDisplayName)
            : Translation.tr("To the paired phone; skipped while it is out of reach")
    }
}
