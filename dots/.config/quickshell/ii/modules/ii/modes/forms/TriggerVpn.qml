pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `vpn` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.kind === "tailscale" ? "tailscale" : "vpn"
        onPicked: v => row.set({ kind: v })
        options: [
            { displayName: Translation.tr("VPN"), value: "vpn" },
            { displayName: Translation.tr("Tailscale"), value: "tailscale" }
        ]
    }

    FormChoice {
        current: row.trigger.connected === false ? "down" : "up"
        onPicked: v => row.set({ connected: v === "up" })
        options: [
            { displayName: Translation.tr("Connected"), value: "up" },
            { displayName: Translation.tr("Disconnected"), value: "down" }
        ]
    }
}
