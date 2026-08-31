import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Hotspot tab: turns the machine into an access point, and says up front which
 * parts of that it cannot do.
 *
 * The checks above the switch are the whole point of the tab. NetworkManager
 * will build a shared connection on a machine with no DHCP server and no
 * firewall backend, and the access point then associates clients and hands them
 * nothing — a failure that looks like a broken router rather than a missing
 * package.
 */
ContentPage {
    id: root
    forceWidth: false

    property string securityValue: "wpa-psk"
    property string bandValue: ""
    property bool profileLoaded: false
    property string errorText: ""

    readonly property bool openNetwork: root.securityValue === "open"
    readonly property bool hasProfile: Hotspot.profile !== null
    readonly property bool waiting: Hotspot.busy || !Hotspot.probed

    // Connection sharing is an optional dependency everywhere, and the package
    // that carries it is not called the same thing everywhere either.
    function installCommandFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "yay -S dnsmasq";
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "sudo dnf install dnsmasq";
        // dnsmasq-base is the one NetworkManager drives. The full dnsmasq
        // package also starts a system resolver that fights it for port 53.
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "sudo apt install dnsmasq-base";
        if (["opensuse", "opensuse-tumbleweed", "opensuse-leap", "suse"].indexOf(distro) >= 0)
            return "sudo zypper install dnsmasq";
        return "# Install the dnsmasq package for " + (SystemInfo.distroName || "your distribution");
    }

    readonly property string installCommand: root.installCommandFor(SystemInfo.distroId)

    function dataLabel(bytes: real): string {
        if (bytes < 1024)
            return Translation.tr("%1 B").arg(bytes);
        const units = ["kB", "MB", "GB", "TB"];
        let value = bytes / 1024;
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return `${value.toFixed(1)} ${units[unit]}`;
    }

    component InfoRow: RowLayout {
        id: infoRow
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        visible: infoRow.value.length > 0
        spacing: 12

        StyledText {
            Layout.preferredWidth: 150
            text: infoRow.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: infoRow.value
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
    }

    component Selector: ColumnLayout {
        id: selector
        property string label: ""
        property list<var> options: []
        property var currentValue: null
        signal picked(var value)

        Layout.fillWidth: true
        spacing: 2

        StyledText {
            text: selector.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        ConfigSelectionArray {
            options: selector.options
            currentValue: selector.currentValue
            onSelected: newValue => selector.picked(newValue)
        }
    }

    function loadProfile(): void {
        const profile = Hotspot.profile;
        if (!profile)
            return;
        ssidField.text = profile.ssid;
        hiddenSwitch.checked = profile.hidden;
        root.bandValue = profile.band;
        root.securityValue = Hotspot.securityOf(profile.keyMgmt);
        root.profileLoaded = true;
    }

    /**
     * A pre-shared key shorter than 8 characters is refused by the radio rather
     * than by NetworkManager, so the access point comes up and no client can
     * ever join it.
     */
    function apply(startAfter: bool): void {
        root.errorText = "";
        if (ssidField.text.length === 0) {
            root.errorText = Translation.tr("The hotspot needs a name.");
            return;
        }
        const secret = passwordField.text;
        const needsSecret = !root.openNetwork && (!root.hasProfile || secret.length > 0);
        if (needsSecret && (secret.length < 8 || secret.length > 63)) {
            root.errorText = Translation.tr("The password has to be between 8 and 63 characters.");
            return;
        }
        Hotspot.save({
            ssid: ssidField.text,
            security: root.securityValue,
            band: root.bandValue,
            hidden: hiddenSwitch.checked
        }, secret, startAfter, () => passwordField.text = "");
    }

    Connections {
        target: Hotspot

        // The profile arrives a moment after the page does, and it should not
        // land on top of something already being typed.
        function onProfileChanged(): void {
            if (!root.profileLoaded)
                root.loadProfile();
        }
    }

    Component.onCompleted: {
        Hotspot.refreshProfile();
        root.loadProfile();
    }

    ContentSection {
        icon: "wifi_tethering"
        title: Translation.tr("Hotspot")

        NoticeBox {
            Layout.fillWidth: true
            visible: !NetworkState.backendAvailable
            materialIcon: "error"
            text: Translation.tr("NetworkManager is not running, so no hotspot can be started. Start it with `systemctl enable --now NetworkManager`.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: NetworkState.backendAvailable && !NetworkState.hasWifiDevice
            materialIcon: "wifi_off"
            text: Translation.tr("No Wi-Fi adapter is available, so there is nothing to run an access point on.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Hotspot.probed && NetworkState.hasWifiDevice && !Hotspot.apCapable
            materialIcon: "block"
            text: Translation.tr("This adapter cannot act as an access point. That is a limit of the chipset or its driver, and no setting here can lift it.")
        }

        HelperCodeBox {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: Hotspot.probed && Hotspot.supported && !Hotspot.dnsmasqAvailable
            topLeftRadius: Appearance.rounding.large
            topRightRadius: Appearance.rounding.large
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            icon: "terminal"
            title: Translation.tr("dnsmasq is missing")
            text: Translation.tr("NetworkManager hands out addresses on a shared connection through dnsmasq, which it does not depend on. Without it the hotspot starts, devices join, and none of them get an address or a name server.")
            codeSnippet: root.installCommand
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Hotspot.probed && Hotspot.supported && !Hotspot.firewallAvailable
            materialIcon: "shield"
            text: Translation.tr("Neither iptables nor nftables is installed, so NetworkManager cannot set up the address translation a shared connection needs.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Hotspot.probed && Hotspot.supported && !Hotspot.concurrentCapable
                && NetworkState.wifiConnected
            materialIcon: "warning"
            text: Translation.tr("This radio cannot serve an access point and stay on a Wi-Fi network at the same time. Starting the hotspot will drop the current connection, and it will have nothing to share unless a cable is plugged in.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Hotspot.probed && Hotspot.ready && Hotspot.sharedChannel && Hotspot.sharesOwnRadio
            materialIcon: "info"
            text: Translation.tr("The radio holds one channel at a time, so the hotspot has to use the channel of the network it is sharing. The band picked below is ignored while that network is connected.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Hotspot.lastError.length > 0
            materialIcon: "error"
            text: Hotspot.lastError
        }

        ConfigSwitch {
            id: hotspotSwitch
            buttonIcon: "wifi_tethering"
            text: Translation.tr("Share this connection")
            enabled: Hotspot.ready && root.hasProfile && !Hotspot.busy
            checked: Hotspot.active
            // Hotspot owns this state, so the switch has to be handed its
            // binding back after the click that broke it.
            onCheckedChanged: {
                if (checked === Hotspot.active)
                    return;
                if (checked)
                    Hotspot.start(Hotspot.profile?.uuid ?? "");
                else
                    Hotspot.stop();
                checked = Qt.binding(() => Hotspot.active);
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: Hotspot.supported && !root.hasProfile
            text: Translation.tr("Give the hotspot a name and a password below, then save it to switch it on.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        InfoRow {
            label: Translation.tr("Network name")
            value: Hotspot.profile?.ssid ?? ""
        }

        InfoRow {
            label: Translation.tr("Sharing")
            value: {
                if (Hotspot.uplinkName.length === 0)
                    return Translation.tr("Nothing — no connection to share");
                if (Hotspot.sharesOwnRadio)
                    return Translation.tr("%1 (the same radio)").arg(Hotspot.uplinkName);
                return Hotspot.uplinkName;
            }
        }

        InfoRow {
            label: Translation.tr("Adapter")
            value: Hotspot.interfaceName
        }

        InfoRow {
            label: Translation.tr("Band in use")
            value: Hotspot.active ? Hotspot.bandLabel(Hotspot.profile?.band ?? "") : ""
        }
    }

    ContentSection {
        icon: "router"
        title: Translation.tr("Access point")
        enabled: Hotspot.supported

        NoticeBox {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            materialIcon: "error"
            text: root.errorText
        }

        MaterialTextField {
            id: ssidField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Hotspot name (SSID)")
        }

        Selector {
            label: Translation.tr("Security")
            currentValue: root.securityValue
            options: [
                { "displayName": Translation.tr("WPA2"), "value": "wpa-psk" },
                { "displayName": Translation.tr("WPA3"), "value": "sae" },
                { "displayName": Translation.tr("Open"), "value": "open" }
            ]
            onPicked: newValue => root.securityValue = newValue
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.openNetwork
            materialIcon: "lock_open"
            text: Translation.tr("An open hotspot lets anyone in range join and read the traffic of everyone on it.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.securityValue === "sae"
            materialIcon: "info"
            text: Translation.tr("WPA3 keeps out devices that only speak WPA2 — most phones from before 2019, and a lot of printers and consoles.")
        }

        MaterialTextField {
            id: passwordField
            Layout.fillWidth: true
            visible: !root.openNetwork
            echoMode: revealPassword.checked ? TextInput.Normal : TextInput.Password
            placeholderText: Translation.tr("Password")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.openNetwork
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.hasProfile ? Translation.tr("Leave empty to keep the stored password.")
                    : Translation.tr("Show password")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledSwitch {
                id: revealPassword
            }
        }

        Selector {
            label: Translation.tr("Band")
            currentValue: root.bandValue
            options: {
                const entries = [{
                    "displayName": Translation.tr("Automatic"),
                    "value": ""
                }];
                if (!Hotspot.probed || Hotspot.band24Capable)
                    entries.push({ "displayName": Translation.tr("2.4 GHz"), "value": "bg" });
                if (!Hotspot.probed || Hotspot.band5Capable)
                    entries.push({ "displayName": Translation.tr("5 GHz"), "value": "a" });
                return entries;
            }
            onPicked: newValue => root.bandValue = newValue
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("2.4 GHz reaches further and through more walls; 5 GHz is faster and much less crowded.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        ConfigSwitch {
            id: hiddenSwitch
            buttonIcon: "visibility_off"
            text: Translation.tr("Do not broadcast the name")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            RippleButtonWithIcon {
                enabled: !root.waiting
                materialIcon: "save"
                mainText: Translation.tr("Save")
                onClicked: root.apply(false)
            }

            RippleButtonWithIcon {
                enabled: !root.waiting && Hotspot.ready
                materialIcon: "wifi_tethering"
                mainText: Hotspot.active ? Translation.tr("Save and restart") : Translation.tr("Save and start")
                colBackground: Appearance.colors.colPrimary
                colText: Appearance.colors.colOnPrimary
                onClicked: root.apply(true)
            }

            RippleButtonWithIcon {
                visible: root.hasProfile
                enabled: !root.waiting
                materialIcon: "delete"
                mainText: Translation.tr("Remove")
                onClicked: Hotspot.forget()
            }

            MaterialLoadingIndicator {
                visible: root.waiting
                loading: root.waiting
                implicitSize: 20
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }

    ContentSection {
        icon: "devices"
        title: Translation.tr("Connected devices")
        visible: Hotspot.active

        NoticeBox {
            Layout.fillWidth: true
            visible: !Hotspot.iwAvailable
            materialIcon: "info"
            text: Translation.tr("Listing the devices on the hotspot needs the iw tool, which is not installed. The hotspot itself works without it.")
        }

        StyledText {
            Layout.fillWidth: true
            visible: Hotspot.iwAvailable
            text: Hotspot.stations.length === 0 ? Translation.tr("Nothing has joined yet")
                : Translation.tr("%1 connected").arg(Hotspot.stations.length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: ScriptModel {
                values: Hotspot.stations
                objectProp: "mac"
            }

            delegate: InfoRow {
                required property var modelData

                label: modelData.mac
                value: {
                    const parts = [];
                    if (modelData.signal !== 0)
                        parts.push(Translation.tr("%1 dBm").arg(modelData.signal));
                    parts.push(Translation.tr("%1 down").arg(root.dataLabel(modelData.txBytes)));
                    parts.push(Translation.tr("%1 up").arg(root.dataLabel(modelData.rxBytes)));
                    return parts.join("  •  ");
                }
            }
        }
    }
}
