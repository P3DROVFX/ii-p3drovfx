pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Connected to a wireless network.
 *
 * Re-associating with the network that is already on screen - a resume, roaming between
 * access points, a driver reset - is not a connection the user made, so the SSID has to
 * have actually changed.
 */
TransientSource {
    id: source

    activityId: "wifi"
    ttlMs: 3000
    cooldownMs: 800

    property string announcedSsid: ""

    property Connections _network: Connections {
        target: Network
        function onWifiStatusChanged() {
            if (Network.wifiStatus !== "connected" || Network.networkName === "")
                return;
            if (Network.networkName === source.announcedSsid)
                return;
            if (source.trigger({ ssid: Network.networkName }))
                source.announcedSsid = Network.networkName;
        }
    }
}
