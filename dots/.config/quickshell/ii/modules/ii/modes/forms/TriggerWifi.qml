pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `wifi` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.connected === false ? "off" : "on"
        onPicked: v => row.set({ connected: v === "on" })
        options: [
            { displayName: Translation.tr("Connected"), value: "on" },
            { displayName: Translation.tr("Disconnected"), value: "off" }
        ]
    }

    ChipInput {
        Layout.fillWidth: true
        visible: row.trigger.connected !== false
        values: row.trigger.ssids
        placeholder: Translation.tr("Network name — empty means any")
        suggestions: Array.from(Network.friendlyWifiNetworks ?? [])
            .map(n => n?.ssid).filter(s => s && s.length)
            .filter((s, i, arr) => arr.indexOf(s) === i)
            .map(s => ({ label: s, value: s }))
        onChanged: list => row.set({ ssids: list })
    }

    FormChoice {
        current: row.trigger.ethernet === true ? "yes" : (row.trigger.ethernet === false ? "no" : "any")
        onPicked: v => row.set({ ethernet: v === "any" ? null : v === "yes" })
        options: [
            { displayName: Translation.tr("Ethernet: any"), value: "any" },
            { displayName: Translation.tr("Ethernet up"), value: "yes" },
            { displayName: Translation.tr("Ethernet down"), value: "no" }
        ]
    }
}
