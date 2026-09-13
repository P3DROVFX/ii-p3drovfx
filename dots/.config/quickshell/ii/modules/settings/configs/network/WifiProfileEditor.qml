import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The saved Wi-Fi profile editor, and the only place in the shell that can
 * build an 802.1X connection.
 *
 * Which profile it edits comes from NetworkProfiles.editUuid, because a
 * sub-page is loaded by URL and a URL cannot carry an argument. An empty uuid
 * means a new profile is being created.
 *
 * Stored secrets are never read back — nmcli returns them as "<hidden>" and
 * this page keeps it that way. An empty password field leaves whatever is
 * already stored alone.
 */
ContentPage {
    id: root

    property bool showBackButton: false
    signal goBack()

    forceWidth: false

    readonly property string uuid: NetworkProfiles.editUuid
    readonly property bool createMode: root.uuid.length === 0
    property var original: ({})
    property bool loaded: false
    property bool busy: false
    property string errorText: ""

    property string keyMgmtValue: "wpa-psk"
    property string macValue: ""
    property string eapValue: "peap"
    property string phase2Value: "mschapv2"
    property string meteredValue: "unknown"
    property string ipv4MethodValue: "auto"
    property string ipv6MethodValue: "auto"

    readonly property bool secured: root.keyMgmtValue !== "none"
    readonly property bool enterprise: root.keyMgmtValue === "wpa-eap"
    readonly property bool certificateAuth: root.enterprise && root.eapValue === "tls"
    readonly property string storedKeyMgmt: root.original["802-11-wireless-security.key-mgmt"] ?? ""
    readonly property bool wasEnterprise: root.storedKeyMgmt === "wpa-eap"
    readonly property bool wasSecured: root.storedKeyMgmt.length > 0

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

    // nmcli prints an unset value as an empty string and a stored secret as
    // "<hidden>"; neither is something a field should be filled with.
    function value(key: string, fallback: string): string {
        const stored = root.original[key];
        if (stored === undefined || stored === "<hidden>" || stored.length === 0)
            return fallback;
        return stored;
    }

    function applyLoaded(): void {
        nameField.text = root.value("connection.id", "");
        autoconnectSwitch.checked = root.value("connection.autoconnect", "yes") === "yes";
        prioritySpin.value = parseInt(root.value("connection.autoconnect-priority", "0")) || 0;
        root.meteredValue = root.value("connection.metered", "unknown");
        ssidField.text = root.value("802-11-wireless.ssid", "");
        hiddenSwitch.checked = root.value("802-11-wireless.hidden", "no") === "yes";
        root.macValue = root.value("802-11-wireless.cloned-mac-address", "");
        const keyMgmt = root.value("802-11-wireless-security.key-mgmt", "");
        root.keyMgmtValue = keyMgmt.length > 0 ? keyMgmt : "none";
        // NetworkManager stores eap as a list even when only one method is set.
        root.eapValue = root.value("802-1x.eap", "peap").split(",")[0];
        identityField.text = root.value("802-1x.identity", "");
        anonymousField.text = root.value("802-1x.anonymous-identity", "");
        root.phase2Value = root.value("802-1x.phase2-auth", "mschapv2");
        caCertField.text = root.value("802-1x.ca-cert", "");
        domainField.text = root.value("802-1x.domain-suffix-match", "");
        systemCaSwitch.checked = root.value("802-1x.system-ca-certs", "no") === "yes";
        clientCertField.text = root.value("802-1x.client-cert", "");
        privateKeyField.text = root.value("802-1x.private-key", "");
        root.ipv4MethodValue = root.value("ipv4.method", "auto");
        ipv4Address.text = root.value("ipv4.addresses", "");
        ipv4Gateway.text = root.value("ipv4.gateway", "");
        ipv4Dns.text = root.value("ipv4.dns", "");
        ipv4IgnoreDns.checked = root.value("ipv4.ignore-auto-dns", "no") === "yes";
        root.ipv6MethodValue = root.value("ipv6.method", "auto");
        ipv6Address.text = root.value("ipv6.addresses", "");
        ipv6Gateway.text = root.value("ipv6.gateway", "");
        ipv6Dns.text = root.value("ipv6.dns", "");
        root.loaded = true;
    }

    // Only what actually changed is written, so a profile someone else set up
    // keeps every property this page does not show.
    function put(changes: var, key: string, newValue): void {
        const text = String(newValue);
        if (root.createMode) {
            if (text.length > 0)
                changes[key] = text;
            return;
        }
        if (String(root.original[key] ?? "") !== text)
            changes[key] = text;
    }

    function collect(): var {
        const changes = ({});
        if (!root.createMode) {
            root.put(changes, "connection.id", nameField.text);
            root.put(changes, "802-11-wireless.ssid", ssidField.text);
        }
        root.put(changes, "connection.autoconnect", autoconnectSwitch.checked ? "yes" : "no");
        root.put(changes, "connection.autoconnect-priority", prioritySpin.value);
        root.put(changes, "connection.metered", root.meteredValue);
        root.put(changes, "802-11-wireless.hidden", hiddenSwitch.checked ? "yes" : "no");
        root.put(changes, "802-11-wireless.cloned-mac-address", root.macValue);
        if (root.secured)
            root.put(changes, "802-11-wireless-security.key-mgmt", root.keyMgmtValue);
        if (root.enterprise) {
            root.put(changes, "802-1x.eap", root.eapValue);
            root.put(changes, "802-1x.identity", identityField.text);
            root.put(changes, "802-1x.anonymous-identity", anonymousField.text);
            root.put(changes, "802-1x.domain-suffix-match", domainField.text);
            root.put(changes, "802-1x.ca-cert", caCertField.text);
            root.put(changes, "802-1x.system-ca-certs", systemCaSwitch.checked ? "yes" : "no");
            if (root.certificateAuth) {
                root.put(changes, "802-1x.client-cert", clientCertField.text);
                root.put(changes, "802-1x.private-key", privateKeyField.text);
            } else {
                root.put(changes, "802-1x.phase2-auth", root.phase2Value);
            }
        }
        root.put(changes, "ipv4.method", root.ipv4MethodValue);
        if (root.ipv4MethodValue === "manual") {
            root.put(changes, "ipv4.addresses", ipv4Address.text);
            root.put(changes, "ipv4.gateway", ipv4Gateway.text);
        }
        root.put(changes, "ipv4.dns", ipv4Dns.text);
        root.put(changes, "ipv4.ignore-auto-dns", ipv4IgnoreDns.checked ? "yes" : "no");
        root.put(changes, "ipv6.method", root.ipv6MethodValue);
        if (root.ipv6MethodValue === "manual") {
            root.put(changes, "ipv6.addresses", ipv6Address.text);
            root.put(changes, "ipv6.gateway", ipv6Gateway.text);
        }
        root.put(changes, "ipv6.dns", ipv6Dns.text);
        return changes;
    }

    function fail(code: int, out: string, err: string): bool {
        if (code === 0)
            return false;
        root.busy = false;
        const message = err.trim().length > 0 ? err.trim() : out.trim();
        root.errorText = message.length > 0 ? message : Translation.tr("NetworkManager refused the change.");
        return true;
    }

    function apply(activateAfter: bool): void {
        if (root.busy)
            return;
        root.errorText = "";
        if (nameField.text.length === 0 || ssidField.text.length === 0) {
            root.errorText = Translation.tr("A profile needs both a name and a network name.");
            return;
        }
        const secretKey = root.enterprise ? "802-1x.password"
            : root.secured ? "802-11-wireless-security.psk" : "";
        const secret = root.secured ? secretField.text : "";
        // A new secured profile with no secret is saved happily and then fails
        // on every connection attempt, which reads as a bug rather than a gap.
        if (root.createMode && secretKey.length > 0 && secret.length === 0 && !root.certificateAuth) {
            root.errorText = Translation.tr("A secured network needs a password.");
            return;
        }
        root.busy = true;
        const changes = root.collect();
        if (root.createMode) {
            NetworkProfiles.create(nameField.text, ssidField.text, changes, secretKey, secret,
                (code, out, err) => {
                    if (root.fail(code, out, err))
                        return;
                    // nmcli only reports the new uuid in its success line, and
                    // it is the one safe handle: profile names are not unique.
                    const match = out.match(/\(([0-9a-fA-F-]{36})\)/);
                    root.finish(activateAfter && match ? match[1] : "");
                });
            return;
        }
        // An empty key-mgmt is rejected as "property is missing", so dropping
        // security off a profile means removing the whole setting group. The
        // command queue runs these in order, ahead of the modify below.
        if (root.wasSecured && !root.secured)
            NetworkProfiles.removeSetting(root.uuid, "802-11-wireless-security");
        if (root.wasEnterprise && !root.enterprise)
            NetworkProfiles.removeSetting(root.uuid, "802-1x");
        NetworkProfiles.save(root.uuid, changes, secretKey, secret, (code, out, err) => {
            if (root.fail(code, out, err))
                return;
            root.finish(activateAfter ? root.uuid : "");
        });
    }

    function finish(activateUuid: string): void {
        root.busy = false;
        if (activateUuid.length > 0)
            NetworkProfiles.activate(activateUuid);
        root.goBack();
    }

    Component.onCompleted: {
        if (root.createMode) {
            root.loaded = true;
            return;
        }
        NetworkProfiles.readSettings(root.uuid, settings => {
            root.original = settings;
            root.applyLoaded();
        });
    }

    RowLayout {
        visible: root.showBackButton
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: root.createMode ? Translation.tr("New Wi-Fi network") : Translation.tr("Edit saved network")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "badge"
        title: Translation.tr("Profile")

        NoticeBox {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            materialIcon: "error"
            text: root.errorText
        }

        MaterialTextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Profile name")
        }

        MaterialTextField {
            id: ssidField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Network name (SSID)")
        }

        ConfigSwitch {
            id: autoconnectSwitch
            buttonIcon: "autorenew"
            text: Translation.tr("Connect automatically")
            checked: true
        }

        ConfigSwitch {
            id: hiddenSwitch
            buttonIcon: "visibility_off"
            text: Translation.tr("This network is hidden")
        }

        ConfigSpinBox {
            id: prioritySpin
            icon: "low_priority"
            text: Translation.tr("Autoconnect priority")
            from: -999
            to: 999
            stepSize: 1
        }

        Selector {
            label: Translation.tr("Data usage")
            currentValue: root.meteredValue
            options: [
                { "displayName": Translation.tr("Automatic"), "value": "unknown" },
                { "displayName": Translation.tr("Metered"), "value": "yes" },
                { "displayName": Translation.tr("Unmetered"), "value": "no" }
            ]
            onPicked: newValue => root.meteredValue = newValue
        }

        Selector {
            label: Translation.tr("Hardware address seen by this network")
            currentValue: root.macValue
            options: [
                { "displayName": Translation.tr("Default"), "value": "" },
                { "displayName": Translation.tr("Permanent"), "value": "permanent" },
                { "displayName": Translation.tr("Stable"), "value": "stable" },
                { "displayName": Translation.tr("Random"), "value": "random" }
            ]
            onPicked: newValue => root.macValue = newValue
        }
    }

    ContentSection {
        icon: "lock"
        title: Translation.tr("Security")

        Selector {
            label: Translation.tr("Authentication")
            currentValue: root.keyMgmtValue
            options: [
                { "displayName": Translation.tr("Open"), "value": "none" },
                { "displayName": Translation.tr("WPA/WPA2 Personal"), "value": "wpa-psk" },
                { "displayName": Translation.tr("WPA3 Personal"), "value": "sae" },
                { "displayName": Translation.tr("WPA/WPA2 Enterprise"), "value": "wpa-eap" }
            ]
            onPicked: newValue => root.keyMgmtValue = newValue
        }

        MaterialTextField {
            id: secretField
            Layout.fillWidth: true
            visible: root.secured
            echoMode: revealSecret.checked ? TextInput.Normal : TextInput.Password
            placeholderText: root.enterprise ? Translation.tr("Password") : Translation.tr("Pre-shared key")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.secured
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.createMode ? Translation.tr("Show password")
                    : Translation.tr("Leave empty to keep the stored password.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledSwitch {
                id: revealSecret
            }
        }
    }

    ContentSection {
        icon: "verified_user"
        title: Translation.tr("Enterprise authentication")
        visible: root.enterprise

        Selector {
            label: Translation.tr("EAP method")
            currentValue: root.eapValue
            options: [
                { "displayName": "PEAP", "value": "peap" },
                { "displayName": "TTLS", "value": "ttls" },
                { "displayName": "TLS", "value": "tls" },
                { "displayName": "PWD", "value": "pwd" }
            ]
            onPicked: newValue => root.eapValue = newValue
        }

        MaterialTextField {
            id: identityField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Identity (often your full account address)")
        }

        MaterialTextField {
            id: anonymousField
            Layout.fillWidth: true
            visible: !root.certificateAuth
            placeholderText: Translation.tr("Anonymous identity (optional)")
        }

        Selector {
            label: Translation.tr("Inner authentication")
            visible: !root.certificateAuth
            currentValue: root.phase2Value
            options: [
                { "displayName": "MSCHAPv2", "value": "mschapv2" },
                { "displayName": "GTC", "value": "gtc" },
                { "displayName": "PAP", "value": "pap" },
                { "displayName": "MD5", "value": "md5" }
            ]
            onPicked: newValue => root.phase2Value = newValue
        }

        ConfigSwitch {
            id: systemCaSwitch
            buttonIcon: "shield"
            text: Translation.tr("Use the system certificate store")
        }

        MaterialTextField {
            id: caCertField
            Layout.fillWidth: true
            placeholderText: Translation.tr("CA certificate path (optional)")
        }

        MaterialTextField {
            id: domainField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Domain suffix match, e.g. example.edu")
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("Without a CA certificate or a domain match, anything advertising this network name can collect the password. Campus and corporate networks publish both.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        MaterialTextField {
            id: clientCertField
            Layout.fillWidth: true
            visible: root.certificateAuth
            placeholderText: Translation.tr("Client certificate path")
        }

        MaterialTextField {
            id: privateKeyField
            Layout.fillWidth: true
            visible: root.certificateAuth
            placeholderText: Translation.tr("Private key path")
        }
    }

    ContentSection {
        icon: "lan"
        title: Translation.tr("IPv4")

        Selector {
            label: Translation.tr("Addressing")
            currentValue: root.ipv4MethodValue
            options: [
                { "displayName": Translation.tr("Automatic"), "value": "auto" },
                { "displayName": Translation.tr("Manual"), "value": "manual" },
                { "displayName": Translation.tr("Link-local"), "value": "link-local" },
                { "displayName": Translation.tr("Shared"), "value": "shared" }
            ]
            onPicked: newValue => root.ipv4MethodValue = newValue
        }

        MaterialTextField {
            id: ipv4Address
            Layout.fillWidth: true
            visible: root.ipv4MethodValue === "manual"
            placeholderText: Translation.tr("Address with prefix, e.g. 192.168.1.20/24")
        }

        MaterialTextField {
            id: ipv4Gateway
            Layout.fillWidth: true
            visible: root.ipv4MethodValue === "manual"
            placeholderText: Translation.tr("Gateway")
        }

        MaterialTextField {
            id: ipv4Dns
            Layout.fillWidth: true
            placeholderText: Translation.tr("DNS servers, comma separated")
        }

        ConfigSwitch {
            id: ipv4IgnoreDns
            buttonIcon: "dns"
            text: Translation.tr("Ignore DNS servers offered by the network")
        }
    }

    ContentSection {
        icon: "dns"
        title: Translation.tr("IPv6")

        Selector {
            label: Translation.tr("Addressing")
            currentValue: root.ipv6MethodValue
            options: [
                { "displayName": Translation.tr("Automatic"), "value": "auto" },
                { "displayName": Translation.tr("Manual"), "value": "manual" },
                { "displayName": Translation.tr("Link-local"), "value": "link-local" },
                { "displayName": Translation.tr("Disabled"), "value": "disabled" }
            ]
            onPicked: newValue => root.ipv6MethodValue = newValue
        }

        MaterialTextField {
            id: ipv6Address
            Layout.fillWidth: true
            visible: root.ipv6MethodValue === "manual"
            placeholderText: Translation.tr("Address with prefix")
        }

        MaterialTextField {
            id: ipv6Gateway
            Layout.fillWidth: true
            visible: root.ipv6MethodValue === "manual"
            placeholderText: Translation.tr("Gateway")
        }

        MaterialTextField {
            id: ipv6Dns
            Layout.fillWidth: true
            placeholderText: Translation.tr("DNS servers, comma separated")
        }
    }

    ContentSection {
        icon: "save"
        title: Translation.tr("Apply")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                enabled: root.loaded && !root.busy
                materialIcon: "save"
                mainText: Translation.tr("Save")
                onClicked: root.apply(false)
            }

            RippleButtonWithIcon {
                enabled: root.loaded && !root.busy
                materialIcon: "link"
                mainText: Translation.tr("Save and connect")
                colBackground: Appearance.colors.colPrimary
                colText: Appearance.colors.colOnPrimary
                onClicked: root.apply(true)
            }

            MaterialLoadingIndicator {
                visible: root.busy || !root.loaded
                loading: root.busy || !root.loaded
                implicitSize: 20
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
