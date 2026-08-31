pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `phone` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.reachable === false ? "away" : "near"
        onPicked: v => row.set({ reachable: v === "near" })
        options: [
            { displayName: Translation.tr("Reachable"), value: "near" },
            { displayName: Translation.tr("Out of reach"), value: "away" }
        ]
    }

    RowLayout {
        visible: row.trigger.reachable !== false
        spacing: 10

        FormLabel {
            text: Translation.tr("Phone battery below")
        }

        PercentField {
            value: row.trigger.batteryBelow
            onCommitted: v => row.set({ batteryBelow: v })
        }

        FormHint {
            text: Translation.tr("Leave empty to ignore")
        }
    }

    FormHint {
        text: KdeConnectService.available
            ? (KdeConnectService.activeDevice
                ? Translation.tr("Watches %1 through KDE Connect.").arg(KdeConnectService.activeDeviceDisplayName)
                : Translation.tr("No phone is paired in KDE Connect yet."))
            : Translation.tr("Needs KDE Connect.")
    }
}
