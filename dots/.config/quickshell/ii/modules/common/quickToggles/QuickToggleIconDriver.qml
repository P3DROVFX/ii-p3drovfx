pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.bar.widgets.dashboard.icons

// One service observer for every toggle, independent of the bar's visibility.
// Targets forward the existing driver's cues without constructing hidden shapes.
DashboardIconDriver {
    id: root

    signal cue(string channel, string name)
    readonly property int volumeWaves: volumeTarget.waves

    component CueTarget: Item {
        required property string channel
        readonly property Item presenceController: null
        property int waves: 2
        function play(name: string): void {
            root.cue(channel, name);
        }
    }

    wifiIcon: CueTarget { channel: "wifi" }
    bluetoothIcon: CueTarget { channel: "bluetooth" }
    volumeIcon: CueTarget { id: volumeTarget; channel: "volume" }
    micIcon: CueTarget { channel: "mic" }
    notificationIcon: CueTarget { channel: "notification" }
    caffeineIcon: CueTarget { channel: "caffeine" }
    vpnIcon: CueTarget { channel: "vpn" }
    tailscaleIcon: CueTarget { channel: "tailscale" }
    easyEffectsIcon: CueTarget { channel: "easyeffects" }
    dnsIcon: CueTarget { channel: "dns" }
    gameModeIcon: CueTarget { channel: "gamemode" }
    powerProfileIcon: CueTarget { channel: "powerprofile" }
    songRecIcon: CueTarget { channel: "songrec" }
}
