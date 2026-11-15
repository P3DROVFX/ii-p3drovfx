import QtQuick
import qs.services
import ".."

/**
 * The phone is reachable (`reachable: true`, default) or out of reach, and, when it
 * is an ii tools phone, what it reports: battery above or below a level, charging,
 * Do Not Disturb, in a call, the ringer, the network it is on. A KDE Connect phone
 * only has reachable and battery. Fields left at "any" are not looked at.
 */
ModeCondition {
    id: root
    readonly property bool wantReachable: root.params?.reachable !== false
    readonly property var batteryBelow: root.params?.batteryBelow ?? null
    readonly property var batteryAbove: root.params?.batteryAbove ?? null

    readonly property bool viaLink: IiLinkService.hasPeers
    readonly property bool paired: root.viaLink || (KdeConnectService.available && KdeConnectService.activeDeviceId.length > 0)
    readonly property bool reachable: root.viaLink ? IiLinkService.phoneConnected
        : (root.paired && KdeConnectService.activeReachable)
    readonly property var status: root.viaLink ? IiLinkService.phoneStatus : null
    readonly property int charge: root.viaLink ? Number(root.status?.battery?.level ?? -1)
        : Number(KdeConnectService.activeDevice?.charge ?? -1)
    readonly property bool batteryOk: (root.batteryBelow === null || (root.charge >= 0 && root.charge < Number(root.batteryBelow)))
        && (root.batteryAbove === null || (root.charge >= 0 && root.charge > Number(root.batteryAbove)))

    function _tri(want, value) {
        // value null = the phone has not said: a wanted state is then not met.
        if (want === "any" || want === undefined)
            return true;
        if (value === null || value === undefined)
            return false;
        return want === "yes" || want === "on" ? value === true : value === false;
    }
    readonly property bool stateOk: {
        const p = root.params;
        if (!root.viaLink)
            return true;
        const charging = root.status?.battery ? root.status.battery.charging === true : null;
        const ringer = root.status?.ringer ?? "";
        const net = root.status?.net?.type ?? "";
        return root._tri(p?.charging, charging)
            && root._tri(p?.dnd, IiLinkService.phoneDnd)
            && root._tri(p?.call, PhoneCallService.active)
            && (p?.ringer === undefined || p.ringer === "any" || p.ringer === ringer)
            && (p?.net === undefined || p.net === "any" || p.net === net);
    }

    satisfied: root.paired && (root.wantReachable ? (root.reachable && root.batteryOk && root.stateOk) : !root.reachable)
    reason: {
        if (!root.paired)
            return "no phone paired";
        const name = root.viaLink ? (IiLinkService.connectedList[0]?.name || "phone")
            : (KdeConnectService.activeDeviceDisplayName || "phone");
        const charge = root.charge >= 0 ? ` ${root.charge} %` : "";
        return root.reachable ? `${name}${charge}` : `${name} out of reach`;
    }
}
