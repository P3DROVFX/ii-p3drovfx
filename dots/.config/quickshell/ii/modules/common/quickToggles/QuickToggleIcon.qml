pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.dashboard.icons

Item {
    id: root

    property string toggleType: ""
    property string text: ""
    property real iconSize: 22
    property real fill: 0
    property color color: Appearance.colors.colOnLayer1
    property bool toggled: false

    readonly property Component iconComponent: {
        switch (toggleType) {
        case "network": return Network.ethernet && !GlobalStates.dashboardWifiDialogOpen ? null : wifiComponent;
        case "bluetooth": return bluetoothComponent;
        case "audio": case "volumeSlider": return volumeComponent;
        case "mic": case "micSlider": return micComponent;
        case "notifications": return bellComponent;
        case "idleInhibitor": return coffeeComponent;
        case "vpn": return vpnComponent;
        case "tailscale": return tailscaleComponent;
        case "easyEffects": return equalizerComponent;
        case "dnsOverTls": return dnsComponent;
        case "gameMode": return gamepadComponent;
        case "powerProfile": return powerComponent;
        case "musicRecognition": return musicComponent;
        case "cloudflareWarp": return warpComponent;
        default: return null;
        }
    }
    readonly property bool animated: iconComponent !== null
    implicitWidth: iconSize
    implicitHeight: iconSize

    // Unload hidden geometry, including warmed sidebars and custom BT artwork.
    Loader {
        id: iconLoader
        anchors.centerIn: parent
        active: root.animated && root.visible
        sourceComponent: root.iconComponent
        onLoaded: root.resumeActivity()
    }
    Binding {
        target: iconLoader.item
        property: "iconSize"
        value: root.iconSize
        when: iconLoader.item !== null
    }
    Binding {
        target: iconLoader.item
        property: "color"
        value: root.color
        when: iconLoader.item !== null
    }
    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.animated
        text: root.text
        iconSize: root.iconSize
        fill: root.fill
        color: root.color
    }

    // Seed only ongoing activities on creation; opening a panel is not a
    // connection event. Subsequent transitions use exactly the bar's driver.
    function resumeActivity(): void {
        const icon = iconLoader.item;
        if (!icon) return;
        const driver = QuickToggleIconDriver;
        if (root.toggleType === "network" && driver.wifiCue === "searching")
            icon.play("searching");
        else if (root.toggleType === "bluetooth" && driver.bluetoothCue === "scanning")
            icon.play("scanning");
        else if (root.toggleType === "musicRecognition" && driver.songRecRunning)
            icon.play("listening");
    }
    Connections {
        target: root.animated ? QuickToggleIconDriver : null
        function onCue(channel: string, name: string): void {
            const icon = iconLoader.item;
            if (icon && icon.cueChannel === channel)
                icon.play(name);
        }
    }
    // WARP is the one toggle whose state is owned by its existing model, not
    // a shared service. Do not start another warp-cli process for the icon.
    onToggledChanged: {
        if (root.toggleType === "cloudflareWarp" && iconLoader.item)
            iconLoader.item.play(root.toggled ? "connected" : "disconnected");
    }

    Component {
        id: wifiComponent
        WifiIcon {
            bars: {
                if (!Network.ready || Network.wifiStatus !== "connected") return 0;
                const strength = Number(Network.networkStrength);
                return isNaN(strength) ? 1 : strength > 67 ? 3 : strength > 33 ? 2 : 1;
            }
        }
    }
    Component {
        id: bluetoothComponent
        BluetoothIcon {
            connected: BluetoothStatus.connected
            poweredOff: !BluetoothStatus.enabled
        }
    }
    Component {
        id: volumeComponent
        VolumeIcon { waves: QuickToggleIconDriver.volumeWaves }
    }
    Component {
        id: micComponent
        MicIcon { muted: QuickToggleIconDriver.sourceMuted }
    }
    Component {
        id: bellComponent
        BellIcon { silent: QuickToggleIconDriver.notificationsSilent }
    }
    Component {
        id: coffeeComponent
        CoffeeIcon { active: QuickToggleIconDriver.caffeineOn }
    }
    Component {
        id: vpnComponent
        VpnKeyIcon { connected: QuickToggleIconDriver.vpnOn }
    }
    Component {
        id: tailscaleComponent
        TailscaleIcon { connected: QuickToggleIconDriver.tailscaleOn }
    }
    Component {
        id: equalizerComponent
        EqualizerIcon { active: QuickToggleIconDriver.easyEffectsActive }
    }
    Component {
        id: dnsComponent
        EncryptedDnsIcon { active: DnsOverTls.active }
    }
    Component {
        id: gamepadComponent
        GamepadIcon { active: QuickToggleIconDriver.gameModeOn }
    }
    Component {
        id: powerComponent
        PowerProfileIcon { profile: QuickToggleIconDriver.powerProfileName }
    }
    Component {
        id: musicComponent
        MusicRecognitionIcon { listening: QuickToggleIconDriver.songRecRunning }
    }
    Component {
        id: warpComponent
        CloudLockIcon { connected: root.toggled }
    }
}
