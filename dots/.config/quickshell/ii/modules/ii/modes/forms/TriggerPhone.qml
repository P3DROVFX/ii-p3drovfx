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

    // What the phone itself reports (ii tools): only while it is reachable.
    FormLabel {
        visible: row.trigger.reachable !== false
        text: Translation.tr("And, on the phone")
    }

    Repeater {
        model: row.trigger.reachable !== false ? [
            { key: "charging", label: Translation.tr("Charger"), options: [
                { displayName: Translation.tr("Any"), value: "any" },
                { displayName: Translation.tr("Plugged in"), value: "yes" },
                { displayName: Translation.tr("Unplugged"), value: "no" }] },
            { key: "dnd", label: Translation.tr("Do Not Disturb"), options: [
                { displayName: Translation.tr("Any"), value: "any" },
                { displayName: Translation.tr("On"), value: "on" },
                { displayName: Translation.tr("Off"), value: "off" }] },
            { key: "call", label: Translation.tr("In a call"), options: [
                { displayName: Translation.tr("Any"), value: "any" },
                { displayName: Translation.tr("In a call"), value: "yes" },
                { displayName: Translation.tr("Not in a call"), value: "no" }] },
            { key: "ringer", label: Translation.tr("Ringer"), options: [
                { displayName: Translation.tr("Any"), value: "any" },
                { displayName: Translation.tr("Sound"), value: "normal" },
                { displayName: Translation.tr("Vibrate"), value: "vibrate" },
                { displayName: Translation.tr("Silent"), value: "silent" }] },
            { key: "net", label: Translation.tr("Network"), options: [
                { displayName: Translation.tr("Any"), value: "any" },
                { displayName: Translation.tr("Wi-Fi"), value: "wifi" },
                { displayName: Translation.tr("Mobile data"), value: "cellular" },
                { displayName: Translation.tr("Offline"), value: "none" }] }
        ] : []

        delegate: ColumnLayout {
            id: stateRow
            required property var modelData
            spacing: 4

            FormLabel {
                text: stateRow.modelData.label
            }

            FormChoice {
                current: String(row.trigger[stateRow.modelData.key] ?? "any")
                onPicked: v => {
                    const patch = {};
                    patch[stateRow.modelData.key] = v;
                    row.set(patch);
                }
                options: stateRow.modelData.options
            }
        }
    }

    RowLayout {
        visible: row.trigger.reachable !== false
        spacing: 10

        FormLabel {
            text: Translation.tr("Phone battery above")
        }

        PercentField {
            value: row.trigger.batteryAbove
            onCommitted: v => row.set({ batteryAbove: v })
        }

        FormHint {
            text: Translation.tr("Leave empty to ignore")
        }
    }

    FormHint {
        text: IiLinkService.hasPeers
            ? (IiLinkService.phoneConnected ? Translation.tr("Watches the phone paired over ii tools.") : Translation.tr("The ii tools phone is out of reach."))
            : KdeConnectService.available
            ? (KdeConnectService.activeDevice
                ? Translation.tr("Watches %1.").arg(KdeConnectService.activeDeviceDisplayName)
                : Translation.tr("No phone is paired yet."))
            : Translation.tr("Needs a paired phone (ii tools or KDE Connect).")
    }
}
