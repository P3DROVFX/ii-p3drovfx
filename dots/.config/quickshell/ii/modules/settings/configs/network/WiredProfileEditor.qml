import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The saved wired profile editor.
 *
 * Which profile it edits comes from NetworkProfiles.editUuid, because a
 * sub-page is loaded by URL and a URL cannot carry an argument. An empty uuid
 * means a new profile is being created.
 *
 * Wired 802.1X is the same supplicant as the wireless kind with no radio in
 * front of it, so the fields match — but there is no key management to pick,
 * because the switch either asks for a certificate or it does not.
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

    property string ifnameValue: ""
    property string macValue: ""
    property string meteredValue: "unknown"
    property string eapValue: "peap"
    property string phase2Value: "mschapv2"
    property string ipv4MethodValue: "auto"
    property string ipv6MethodValue: "auto"
    property bool enterprise: false

    readonly property bool certificateAuth: root.enterprise && root.eapValue === "tls"
    readonly property bool wasEnterprise: (root.original["802-1x.eap"] ?? "").length > 0

    // "Any port" is the sane default on a machine with one socket, and the only
    // workable one on a dock whose interface name changes with the dock.
    readonly property var portOptions: {
        const options = [{
            "displayName": Translation.tr("Any port"),
            "value": ""
        }];
        NetworkState.wiredDevices.forEach(device => options.push({
            "displayName": device.name,
            "value": device.name
        }));
        return options;
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
        root.ifnameValue = root.value("connection.interface-name", "");
        autoconnectSwitch.checked = root.value("connection.autoconnect", "yes") === "yes";
        prioritySpin.value = parseInt(root.value("connection.autoconnect-priority", "0")) || 0;
        root.meteredValue = root.value("connection.metered", "unknown");
        root.macValue = root.value("802-3-ethernet.cloned-mac-address", "");
        mtuSpin.value = parseInt(root.value("802-3-ethernet.mtu", "0")) || 0;
        enterpriseSwitch.checked = root.wasEnterprise;
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
            root.put(changes, "connection.interface-name", root.ifnameValue);
        }
        root.put(changes, "connection.autoconnect", autoconnectSwitch.checked ? "yes" : "no");
        root.put(changes, "connection.autoconnect-priority", prioritySpin.value);
        root.put(changes, "connection.metered", root.meteredValue);
        root.put(changes, "802-3-ethernet.cloned-mac-address", root.macValue);
        // A zero MTU is not a size, it is "whatever the driver picks", which is
        // also how the field is cleared once something else has set it.
        root.put(changes, "802-3-ethernet.mtu", mtuSpin.value);
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
        if (nameField.text.length === 0) {
            root.errorText = Translation.tr("A profile needs a name.");
            return;
        }
        const secretKey = root.enterprise && !root.certificateAuth ? "802-1x.password" : "";
        const secret = root.enterprise ? secretField.text : "";
        if (root.createMode && root.enterprise && !root.certificateAuth && secret.length === 0) {
            root.errorText = Translation.tr("An 802.1X network needs a password.");
            return;
        }
        root.busy = true;
        const changes = root.collect();
        if (root.createMode) {
            NetworkProfiles.createWired(nameField.text, root.ifnameValue, changes, secretKey, secret,
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
        // The command queue runs this ahead of the modify below, so dropping
        // 802.1X off a profile takes the whole setting group with it rather
        // than leaving half of it behind.
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
            text: root.createMode ? Translation.tr("New wired connection")
                : Translation.tr("Edit wired connection")
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

        Selector {
            label: Translation.tr("Port this connection is for")
            currentValue: root.ifnameValue
            options: root.portOptions
            onPicked: newValue => root.ifnameValue = newValue
        }

        ConfigSwitch {
            id: autoconnectSwitch
            buttonIcon: "autorenew"
            text: Translation.tr("Connect automatically")
            checked: true
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

        ConfigSpinBox {
            id: mtuSpin
            icon: "straighten"
            text: Translation.tr("MTU (0 lets the driver decide)")
            from: 0
            to: 9000
            stepSize: 100
        }
    }

    ContentSection {
        icon: "verified_user"
        title: Translation.tr("802.1X authentication")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("Some managed networks authenticate the machine at the switch port itself. Until it answers, the port carries nothing — which looks exactly like a dead cable.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        ConfigSwitch {
            id: enterpriseSwitch
            buttonIcon: "shield_lock"
            text: Translation.tr("This port needs 802.1X")
            onCheckedChanged: root.enterprise = checked
        }

        Selector {
            label: Translation.tr("EAP method")
            visible: root.enterprise
            currentValue: root.eapValue
            options: [
                { "displayName": "PEAP", "value": "peap" },
                { "displayName": "TTLS", "value": "ttls" },
                { "displayName": "TLS", "value": "tls" },
                { "displayName": "MD5", "value": "md5" }
            ]
            onPicked: newValue => root.eapValue = newValue
        }

        MaterialTextField {
            id: identityField
            Layout.fillWidth: true
            visible: root.enterprise
            placeholderText: Translation.tr("Identity")
        }

        MaterialTextField {
            id: anonymousField
            Layout.fillWidth: true
            visible: root.enterprise && !root.certificateAuth
            placeholderText: Translation.tr("Anonymous identity (optional)")
        }

        MaterialTextField {
            id: secretField
            Layout.fillWidth: true
            visible: root.enterprise && !root.certificateAuth
            echoMode: revealSecret.checked ? TextInput.Normal : TextInput.Password
            placeholderText: Translation.tr("Password")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.enterprise && !root.certificateAuth
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

        Selector {
            label: Translation.tr("Inner authentication")
            visible: root.enterprise && !root.certificateAuth
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
            visible: root.enterprise
            buttonIcon: "shield"
            text: Translation.tr("Use the system certificate store")
        }

        MaterialTextField {
            id: caCertField
            Layout.fillWidth: true
            visible: root.enterprise
            placeholderText: Translation.tr("CA certificate path (optional)")
        }

        MaterialTextField {
            id: domainField
            Layout.fillWidth: true
            visible: root.enterprise
            placeholderText: Translation.tr("Domain suffix match, e.g. example.edu")
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
