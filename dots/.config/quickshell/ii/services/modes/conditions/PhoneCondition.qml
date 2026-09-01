import QtQuick
import qs.services
import ".."

/**
 * The KDE Connect phone is reachable (`reachable: true`, default) or out
 * of reach; optionally its battery is below `batteryBelow` percent.
 */
ModeCondition {
    id: root
    readonly property bool wantReachable: root.params?.reachable !== false
    readonly property var batteryBelow: root.params?.batteryBelow ?? null

    readonly property bool paired: KdeConnectService.available && KdeConnectService.activeDeviceId.length > 0
    readonly property bool reachable: root.paired && KdeConnectService.activeReachable
    readonly property int charge: Number(KdeConnectService.activeDevice?.charge ?? -1)
    readonly property bool batteryOk: root.batteryBelow === null
        || (root.charge >= 0 && root.charge < Number(root.batteryBelow))

    satisfied: root.paired && (root.wantReachable ? (root.reachable && root.batteryOk) : !root.reachable)
    reason: {
        if (!root.paired)
            return "no phone paired";
        const name = KdeConnectService.activeDeviceDisplayName || "phone";
        const charge = root.charge >= 0 ? ` ${root.charge} %` : "";
        return root.reachable ? `${name}${charge}` : `${name} out of reach`;
    }
}
