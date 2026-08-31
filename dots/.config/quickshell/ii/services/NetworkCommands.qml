pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Every NetworkManager write the shell makes, through one serialised nmcli queue.
 *
 * Quickshell's native backend covers state but cannot build a settings
 * dictionary from QML, so profile creation, 802.1X, hidden SSIDs, addressing and
 * the hotspot all have to go through nmcli. Commands are argument vectors rather
 * than assembled shell strings; the handful that carry a secret run a fixed
 * script that reads it out of the environment, because /proc/<pid>/cmdline is
 * world readable and /proc/<pid>/environ is not.
 */
Singleton {
    id: root

    readonly property string kConnectPsk: 'nmcli device wifi connect "$1" password "$PASSWORD" "${@:2}"'
    readonly property string kSetPsk: 'nmcli connection modify "$1" wifi-sec.psk "$PASSWORD"'
    readonly property string kAddEnterprise: 'nmcli connection add type wifi con-name "$1" ifname "$2" ssid "$3" wifi-sec.key-mgmt wpa-eap 802-1x.password "$PASSWORD" "${@:4}"'
    readonly property string kAddWifi: 'name="$1"; ssid="$2"; key="$3"; shift 3; nmcli connection add type wifi con-name "$name" ssid "$ssid" "$key" "$PASSWORD" "$@"'
    readonly property string kModifySecret: 'uuid="$1"; key="$2"; shift 2; nmcli connection modify uuid "$uuid" "$key" "$PASSWORD" "$@"'

    readonly property bool busy: root.active !== null
    property var active: null
    property var pending: []

    signal commandFinished(string tag, int exitCode, string output, string error)

    function run(argv: var, tag = "", callback = null, env = null): void {
        root.pending = [...root.pending, {
            argv: argv,
            tag: tag,
            callback: callback,
            env: env
        }];
        root.pump();
    }

    function runScript(script: string, args: var, tag = "", callback = null, env = null): void {
        root.run(["bash", "-c", script, "--", ...args], tag, callback, env);
    }

    function pump(): void {
        if (root.active || root.pending.length === 0)
            return;
        const job = root.pending[0];
        root.pending = root.pending.slice(1);
        root.active = job;
        runner.running = false;
        runner.environment = Object.assign({
            LANG: "C",
            LC_ALL: "C"
        }, job.env ?? {});
        runner.command = job.argv;
        runner.running = true;
    }

    // ---- Radio ------------------------------------------------------------
    function setWifiRadio(enabled: bool, callback = null): void {
        root.run(["nmcli", "radio", "wifi", enabled ? "on" : "off"], "radio", callback);
    }

    // Blocks until the scan results are in, which is what makes it usable as a
    // "scanning finished" signal.
    function rescanWifi(callback = null): void {
        root.run(["nmcli", "device", "wifi", "list", "--rescan", "yes"], "rescan", callback);
    }

    // ---- Wi-Fi connections ------------------------------------------------
    function connectToSsid(ssid: string, ifname = "", callback = null): void {
        const argv = ["nmcli", "device", "wifi", "connect", ssid];
        if (ifname.length > 0)
            argv.push("ifname", ifname);
        root.run(argv, "connect", callback);
    }

    function activateProfile(name: string, callback = null): void {
        root.run(["nmcli", "connection", "up", "id", name], "activate", callback);
    }

    function connectWithPsk(ssid: string, psk: string, options = ({}), callback = null): void {
        const extra = [];
        if (options.ifname)
            extra.push("ifname", options.ifname);
        if (options.hidden)
            extra.push("hidden", "yes");
        root.runScript(root.kConnectPsk, [ssid, ...extra], "connect", callback, {
            PASSWORD: psk
        });
    }

    function setProfilePsk(profile: string, psk: string, callback = null): void {
        root.runScript(root.kSetPsk, [profile], "modify", callback, {
            PASSWORD: psk
        });
    }

    /**
     * Creates an 802.1X profile and brings it up. `options` takes eap ("peap",
     * "ttls", "tls", "pwd"), identity, anonymousIdentity, phase2, caCert,
     * domainSuffix, clientCert, privateKey, profile, ifname and hidden.
     */
    function connectWithEnterprise(ssid: string, password: string, options = ({}), callback = null): void {
        const profile = options.profile ?? ssid;
        const extra = ["802-1x.eap", options.eap ?? "peap"];
        if (options.identity)
            extra.push("802-1x.identity", options.identity);
        if (options.anonymousIdentity)
            extra.push("802-1x.anonymous-identity", options.anonymousIdentity);
        if (options.phase2)
            extra.push("802-1x.phase2-auth", options.phase2);
        if (options.caCert)
            extra.push("802-1x.ca-cert", options.caCert);
        if (options.domainSuffix)
            extra.push("802-1x.domain-suffix-match", options.domainSuffix);
        if (options.clientCert)
            extra.push("802-1x.client-cert", options.clientCert);
        if (options.privateKey)
            extra.push("802-1x.private-key", options.privateKey);
        if (options.hidden)
            extra.push("802-11-wireless.hidden", "yes");
        root.runScript(root.kAddEnterprise, [profile, options.ifname ?? "", ssid, ...extra], "enterprise", (code, out, err) => {
            if (code !== 0) {
                if (callback)
                    callback(code, out, err);
                return;
            }
            root.activateProfile(profile, callback);
        }, {
            PASSWORD: password
        });
    }

    function connectToHidden(ssid: string, psk: string, options = ({}), callback = null): void {
        root.connectWithPsk(ssid, psk, Object.assign({}, options, {
            hidden: true
        }), callback);
    }

    function disconnectProfile(name: string, callback = null): void {
        root.run(["nmcli", "connection", "down", "id", name], "down", callback);
    }

    function disconnectDevice(ifname: string, callback = null): void {
        root.run(["nmcli", "device", "disconnect", ifname], "down", callback);
    }

    function forgetProfile(name: string, callback = null): void {
        root.run(["nmcli", "connection", "delete", "id", name], "forget", callback);
    }

    function setAutoconnect(name: string, enabled: bool, callback = null): void {
        root.run(["nmcli", "connection", "modify", "id", name, "connection.autoconnect", enabled ? "yes" : "no"], "modify", callback);
    }

    // ---- Reads nmcli still owns -------------------------------------------
    // nmcli --escape writes a literal colon inside a field as a backslash pair,
    // so the separator can only be found by walking the line.
    function splitEscaped(line: string): var {
        const fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const c = line.charAt(i);
            if (c === "\\" && i + 1 < line.length) {
                current += line.charAt(++i);
            } else if (c === ":") {
                fields.push(current);
                current = "";
            } else {
                current += c;
            }
        }
        fields.push(current);
        return fields;
    }

    /**
     * Per access point extras the D-Bus backend doesn't expose: BSSID, frequency
     * and NetworkManager's own security string. Keyed by SSID.
     */
    function readWifiDetails(callback): void {
        root.run(["nmcli", "-t", "-e", "yes", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY,NAME", "device", "wifi"], "details", (code, out) => {
            callback(code === 0 ? root.parseWifiDetails(out) : ({}));
        });
    }

    function parseWifiDetails(text: string): var {
        const bySsid = ({});
        text.trim().split("\n").forEach(line => {
            if (line.length === 0)
                return;
            const parts = root.splitEscaped(line);
            const ssid = parts[3] ?? "";
            if (ssid.length === 0)
                return;
            const entry = {
                active: parts[0] === "yes",
                strength: parseInt(parts[1]) || 0,
                frequency: parseInt(parts[2]) || 0,
                ssid: ssid,
                bssid: parts[4] ?? "",
                security: parts[5] ?? "",
                profile: parts[6] ?? ""
            };
            // Several radios can advertise the same SSID; keep the connected one,
            // then the strongest, so these extras describe the same access point
            // the backend collapsed them into.
            const existing = bySsid[ssid];
            if (!existing || (entry.active && !existing.active) || (!existing.active && entry.strength > existing.strength))
                bySsid[ssid] = entry;
        });
        return bySsid;
    }

    function readSavedConnections(callback): void {
        root.run(["nmcli", "-t", "-e", "yes", "-g", "NAME,UUID,TYPE,DEVICE,AUTOCONNECT,TIMESTAMP", "connection", "show"], "saved", (code, out) => {
            callback(code === 0 ? root.parseSavedConnections(out) : []);
        });
    }

    function parseSavedConnections(text: string): var {
        const rows = [];
        text.trim().split("\n").forEach(line => {
            if (line.length === 0)
                return;
            const parts = root.splitEscaped(line);
            if (!parts[0] || parts[0].length === 0)
                return;
            rows.push({
                name: parts[0],
                uuid: parts[1] ?? "",
                type: parts[2] ?? "",
                device: parts[3] ?? "",
                autoconnect: parts[4] === "yes",
                timestamp: parseInt(parts[5]) || 0
            });
        });
        return rows;
    }

    function readIpConfig(ifname: string, callback): void {
        if (ifname.length === 0) {
            callback({});
            return;
        }
        root.run(["nmcli", "-t", "-e", "yes", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS", "device", "show", ifname], "ipconfig", (code, out) => {
            callback(code === 0 ? root.parseIpConfig(out) : ({}));
        });
    }

    function parseIpConfig(text: string): var {
        const result = {
            address: "",
            prefix: 0,
            gateway: "",
            dns: [],
            address6: ""
        };
        text.trim().split("\n").forEach(line => {
            const parts = root.splitEscaped(line);
            if (parts.length < 2)
                return;
            const key = parts[0];
            const value = parts.slice(1).join(":");
            if (key.startsWith("IP4.ADDRESS") && result.address.length === 0) {
                const bits = value.split("/");
                result.address = bits[0] ?? "";
                result.prefix = parseInt(bits[1]) || 0;
            } else if (key.startsWith("IP4.GATEWAY")) {
                result.gateway = value === "--" ? "" : value;
            } else if (key.startsWith("IP4.DNS")) {
                result.dns.push(value);
            } else if (key.startsWith("IP6.ADDRESS") && result.address6.length === 0) {
                result.address6 = value.split("/")[0] ?? "";
            }
        });
        return result;
    }

    function prefixToMask(prefix: int): string {
        if (prefix <= 0 || prefix > 32)
            return "";
        const bits = (0xFFFFFFFF << (32 - prefix)) >>> 0;
        return [bits >>> 24, (bits >>> 16) & 255, (bits >>> 8) & 255, bits & 255].join(".");
    }

    // ---- Saved profiles ---------------------------------------------------
    function readProfiles(callback): void {
        root.run(["nmcli", "-t", "-e", "yes", "-g",
            "NAME,UUID,TYPE,DEVICE,ACTIVE,AUTOCONNECT,AUTOCONNECT-PRIORITY,TIMESTAMP,TIMESTAMP-REAL",
            "connection", "show"], "profiles", (code, out) => {
            callback(code === 0 ? root.parseProfiles(out) : []);
        });
    }

    function parseProfiles(text: string): var {
        const rows = [];
        text.trim().split("\n").forEach(line => {
            if (line.length === 0)
                return;
            const parts = root.splitEscaped(line);
            if (!parts[1] || parts[1].length === 0)
                return;
            rows.push({
                name: parts[0] ?? "",
                uuid: parts[1],
                type: parts[2] ?? "",
                device: parts[3] ?? "",
                active: parts[4] === "yes",
                autoconnect: parts[5] === "yes",
                priority: parseInt(parts[6]) || 0,
                timestamp: parseInt(parts[7]) || 0,
                lastUsed: (parts[8] ?? "") === "never" ? "" : (parts[8] ?? "")
            });
        });
        return rows;
    }

    /**
     * Every property of one saved profile, flattened to a key -> value map.
     * --show-secrets is deliberately not passed, so stored passwords come back
     * as the literal "<hidden>": the editor only ever writes a new secret, it
     * never puts an existing one back on screen.
     */
    function readProfileSettings(uuid: string, callback): void {
        if (uuid.length === 0) {
            callback({});
            return;
        }
        root.run(["nmcli", "-t", "-e", "yes", "connection", "show", "uuid", uuid], "settings", (code, out) => {
            callback(code === 0 ? root.parseProfileSettings(out) : ({}));
        });
    }

    function parseProfileSettings(text: string): var {
        const settings = ({});
        text.split("\n").forEach(line => {
            const parts = root.splitEscaped(line);
            if (parts.length < 2)
                return;
            settings[parts[0]] = parts.slice(1).join(":");
        });
        return settings;
    }

    function settingsToArgv(settings: var): var {
        const pairs = [];
        Object.keys(settings ?? ({})).forEach(key => {
            pairs.push(key, String(settings[key]));
        });
        return pairs;
    }

    function modifyProfile(uuid: string, settings: var, callback = null): void {
        const pairs = root.settingsToArgv(settings);
        if (pairs.length === 0) {
            if (callback)
                callback(0, "", "");
            return;
        }
        root.run(["nmcli", "connection", "modify", "uuid", uuid, ...pairs], "modify", callback);
    }

    function modifyProfileWithSecret(uuid: string, secretKey: string, secret: string, settings: var, callback = null): void {
        if (secret.length === 0 || secretKey.length === 0) {
            root.modifyProfile(uuid, settings, callback);
            return;
        }
        root.runScript(root.kModifySecret, [uuid, secretKey, ...root.settingsToArgv(settings)], "modify", callback, {
            PASSWORD: secret
        });
    }

    // A setting cannot be emptied key by key: NetworkManager rejects an empty
    // key-mgmt as "property is missing", so dropping security off a profile has
    // to remove the whole setting group.
    function removeSetting(uuid: string, setting: string, callback = null): void {
        root.run(["nmcli", "connection", "modify", "uuid", uuid, "remove", setting], "modify", callback);
    }

    function addWifiProfile(name: string, ssid: string, settings: var, secretKey = "", secret = "", callback = null): void {
        const pairs = root.settingsToArgv(settings);
        if (secret.length === 0 || secretKey.length === 0) {
            root.run(["nmcli", "connection", "add", "type", "wifi", "con-name", name, "ssid", ssid, ...pairs], "add", callback);
            return;
        }
        root.runScript(root.kAddWifi, [name, ssid, secretKey, ...pairs], "add", callback, {
            PASSWORD: secret
        });
    }

    // Names repeat — NetworkManager happily keeps three profiles called
    // "PlanetCampus" — so everything the profile manager does addresses a uuid.
    function activateProfileUuid(uuid: string, callback = null): void {
        root.run(["nmcli", "connection", "up", "uuid", uuid], "activate", callback);
    }

    function deactivateProfileUuid(uuid: string, callback = null): void {
        root.run(["nmcli", "connection", "down", "uuid", uuid], "down", callback);
    }

    function deleteProfileUuid(uuid: string, callback = null): void {
        root.run(["nmcli", "connection", "delete", "uuid", uuid], "forget", callback);
    }

    function setAutoconnectUuid(uuid: string, enabled: bool, callback = null): void {
        root.modifyProfile(uuid, {
            "connection.autoconnect": enabled ? "yes" : "no"
        }, callback);
    }

    // ---- Hotspot ----------------------------------------------------------
    /**
     * Sharing a connection needs more of the system than NetworkManager admits
     * to: it spawns dnsmasq for DHCP and DNS, and it needs a firewall backend
     * for the NAT. Neither is a hard dependency of the package, and neither is
     * mentioned until the moment a hotspot comes up and hands out nothing.
     */
    readonly property string kHotspotDeps: 'for b in dnsmasq iptables nft iw; do if command -v $b >/dev/null 2>&1 || [ -x /usr/bin/$b ] || [ -x /usr/sbin/$b ]; then echo "$b=yes"; else echo "$b=no"; fi; done'
    // The radio decides whether an access point may run beside the connection
    // it is sharing, and how many channels it can hold while doing it.
    readonly property string kIwCombinations: 'iw list 2>/dev/null | sed -n "/valid interface combinations/,/^[[:space:]]*[A-Z]/p"'
    readonly property string kAddHotspotSecret: 'name="$1"; ssid="$2"; key="$3"; shift 3; nmcli connection add type wifi con-name "$name" ssid "$ssid" "$key" "$PASSWORD" "$@"'

    function readHotspotDeps(callback): void {
        root.runScript(root.kHotspotDeps, [], "deps", (code, out) => {
            const deps = ({});
            out.trim().split("\n").forEach(line => {
                const parts = line.split("=");
                if (parts.length === 2)
                    deps[parts[0]] = parts[1] === "yes";
            });
            callback(deps);
        });
    }

    function readInterfaceCombinations(callback): void {
        root.runScript(root.kIwCombinations, [], "combinations", (code, out) => {
            callback(root.parseCombinations(code === 0 ? out : ""));
        });
    }

    /**
     * One combination is a bullet that wraps onto a second line, so the block is
     * split on the bullet and flattened rather than read line by line.
     */
    function parseCombinations(text: string): var {
        const result = {
            known: false,
            concurrent: false,
            channels: 0
        };
        text.split("*").forEach(entry => {
            const flat = entry.replace(/\s+/g, " ");
            if (flat.indexOf("#{") < 0)
                return;
            result.known = true;
            // AP/VLAN is a different mode that carries no access point of its
            // own, so the name has to end at the brace or the comma.
            if (flat.indexOf("managed") < 0 || !/[{,]\s*AP\s*[,}]/.test(flat))
                return;
            result.concurrent = true;
            const match = flat.match(/#channels <= (\d+)/);
            result.channels = Math.max(result.channels, match ? parseInt(match[1]) : 0);
        });
        return result;
    }

    function readWifiCapabilities(ifname: string, callback): void {
        if (ifname.length === 0) {
            callback({});
            return;
        }
        root.run(["nmcli", "-t", "-f", "WIFI-PROPERTIES", "device", "show", ifname], "wificaps", (code, out) => {
            callback(code === 0 ? root.parseWifiCapabilities(out) : ({}));
        });
    }

    function parseWifiCapabilities(text: string): var {
        const caps = ({});
        text.trim().split("\n").forEach(line => {
            const parts = root.splitEscaped(line);
            if (parts.length < 2)
                return;
            caps[parts[0].replace("WIFI-PROPERTIES.", "").toLowerCase()] = parts[1] === "yes";
        });
        return caps;
    }

    function wirelessUuids(text: string): var {
        const uuids = [];
        text.trim().split("\n").forEach(line => {
            const parts = root.splitEscaped(line);
            if ((parts[1] ?? "") === "802-11-wireless" && (parts[0] ?? "").length > 0)
                uuids.push(parts[0]);
        });
        return uuids;
    }

    /**
     * The saved access points. A connection's mode is not part of the list
     * output, so the wireless profiles are asked for theirs in one batched call
     * rather than one call each.
     */
    function readHotspotProfiles(callback): void {
        root.run(["nmcli", "-t", "-g", "UUID,TYPE", "connection", "show"], "aplist", (code, out) => {
            const uuids = code === 0 ? root.wirelessUuids(out) : [];
            if (uuids.length === 0) {
                callback([]);
                return;
            }
            const fields = ["connection.uuid", "connection.id", "connection.autoconnect",
                "802-11-wireless.mode", "802-11-wireless.ssid", "802-11-wireless.band",
                "802-11-wireless.hidden", "802-11-wireless-security.key-mgmt"];
            const argv = ["nmcli", "-t", "-f", fields.join(","), "connection", "show"];
            uuids.forEach(uuid => argv.push("uuid", uuid));
            root.run(argv, "apshow", (showCode, showOut) => {
                callback(showCode === 0 ? root.parseHotspotProfiles(showOut) : []);
            });
        });
    }

    function parseHotspotProfiles(text: string): var {
        const rows = [];
        text.split("\n\n").forEach(block => {
            const entry = root.parseProfileSettings(block);
            if ((entry["802-11-wireless.mode"] ?? "") !== "ap")
                return;
            rows.push({
                uuid: entry["connection.uuid"] ?? "",
                name: entry["connection.id"] ?? "",
                ssid: entry["802-11-wireless.ssid"] ?? "",
                band: entry["802-11-wireless.band"] ?? "",
                hidden: (entry["802-11-wireless.hidden"] ?? "") === "yes",
                keyMgmt: entry["802-11-wireless-security.key-mgmt"] ?? "",
                autoconnect: (entry["connection.autoconnect"] ?? "") === "yes"
            });
        });
        return rows;
    }

    // Who is actually associated with the access point. The DHCP leases would
    // name them, but NetworkManager keeps that file root-only, while the radio
    // will list its stations to anyone.
    function readStations(ifname: string, callback): void {
        if (ifname.length === 0) {
            callback([]);
            return;
        }
        root.run(["iw", "dev", ifname, "station", "dump"], "stations", (code, out) => {
            callback(code === 0 ? root.parseStations(out) : []);
        });
    }

    function parseStations(text: string): var {
        const rows = [];
        let current = null;
        text.split("\n").forEach(line => {
            const station = line.match(/^Station ([0-9a-fA-F:]{17})/);
            if (station) {
                current = {
                    mac: station[1].toLowerCase(),
                    signal: 0,
                    rxBytes: 0,
                    txBytes: 0,
                    inactive: 0
                };
                rows.push(current);
                return;
            }
            const sep = line.indexOf(":");
            if (!current || sep < 0)
                return;
            const key = line.slice(0, sep).trim();
            const value = line.slice(sep + 1).trim();
            if (key === "signal")
                current.signal = parseInt(value) || 0;
            else if (key === "rx bytes")
                current.rxBytes = parseInt(value) || 0;
            else if (key === "tx bytes")
                current.txBytes = parseInt(value) || 0;
            else if (key === "inactive time")
                current.inactive = parseInt(value) || 0;
        });
        return rows;
    }

    /**
     * An empty ifname is left out rather than passed through: nmcli takes it as
     * a device named "", and a profile pinned to a device that does not exist
     * never activates.
     */
    function addHotspotProfile(name: string, ssid: string, ifname: string, settings: var, secret = "", callback = null): void {
        const pairs = root.settingsToArgv(settings);
        const device = ifname.length > 0 ? ["connection.interface-name", ifname] : [];
        if (secret.length === 0) {
            root.run(["nmcli", "connection", "add", "type", "wifi", "con-name", name, ...device,
                "ssid", ssid, ...pairs], "add", callback);
            return;
        }
        root.runScript(root.kAddHotspotSecret, [name, ssid, "802-11-wireless-security.psk",
            ...device, ...pairs], "add", callback, {
                PASSWORD: secret
            });
    }

    // ---- Wired ------------------------------------------------------------
    readonly property string kAddWiredSecret: 'name="$1"; key="$2"; shift 2; nmcli connection add type ethernet con-name "$name" "$key" "$PASSWORD" "$@"'

    /**
     * What a port actually is beyond its name: the chip, its driver, the MTU in
     * force, and whether a cable is in it. None of that is on the device's D-Bus
     * interface, so it comes back through nmcli like the rest of the reads.
     */
    function readDeviceDetails(ifname: string, callback): void {
        if (ifname.length === 0) {
            callback({});
            return;
        }
        const fields = ["GENERAL.VENDOR", "GENERAL.PRODUCT", "GENERAL.DRIVER", "GENERAL.MTU",
            "GENERAL.STATE", "GENERAL.CONNECTION", "GENERAL.HWADDR", "CAPABILITIES.SPEED",
            "WIRED-PROPERTIES.CARRIER"];
        root.run(["nmcli", "-t", "-e", "yes", "-f", fields.join(","), "device", "show", ifname],
            "device", (code, out) => {
                callback(code === 0 ? root.parseDeviceDetails(out) : ({}));
            });
    }

    /**
     * nmcli drops whole field groups that do not apply to the device rather than
     * printing them empty, so a missing carrier line means "not a wired port"
     * and not "no cable".
     */
    function parseDeviceDetails(text: string): var {
        const result = {
            vendor: "",
            product: "",
            driver: "",
            mtu: 0,
            state: "",
            connection: "",
            mac: "",
            speed: "",
            carrier: ""
        };
        const plain = {
            "GENERAL.VENDOR": "vendor",
            "GENERAL.PRODUCT": "product",
            "GENERAL.DRIVER": "driver",
            "GENERAL.CONNECTION": "connection",
            "GENERAL.HWADDR": "mac",
            "CAPABILITIES.SPEED": "speed",
            "WIRED-PROPERTIES.CARRIER": "carrier"
        };
        text.trim().split("\n").forEach(line => {
            const parts = root.splitEscaped(line);
            if (parts.length < 2)
                return;
            const key = parts[0];
            // The hardware address is the one value carrying colons of its own,
            // and nmcli leaves them unescaped even when asked not to.
            const value = parts.slice(1).join(":");
            if (plain[key] !== undefined) {
                result[plain[key]] = value === "--" ? "" : value;
                return;
            }
            if (key === "GENERAL.MTU") {
                result.mtu = parseInt(value) || 0;
                return;
            }
            if (key !== "GENERAL.STATE")
                return;
            // Reported as "100 (connected)", where the number is NetworkManager's
            // own scale and means nothing outside it.
            const match = value.match(/\(([^)]*)\)/);
            result.state = match ? match[1] : value;
        });
        return result;
    }

    /**
     * A wired profile, pinned to the port it was made for. As with the hotspot,
     * an empty ifname is left out rather than passed through: nmcli would take
     * it as a device named "", which nothing ever matches.
     */
    function addWiredProfile(name: string, ifname: string, settings: var, secretKey = "", secret = "", callback = null): void {
        const pairs = root.settingsToArgv(settings);
        const device = ifname.length > 0 ? ["connection.interface-name", ifname] : [];
        if (secret.length === 0 || secretKey.length === 0) {
            root.run(["nmcli", "connection", "add", "type", "ethernet", "con-name", name,
                ...device, ...pairs], "add", callback);
            return;
        }
        root.runScript(root.kAddWiredSecret, [name, secretKey, ...device, ...pairs], "add",
            callback, {
                PASSWORD: secret
            });
    }

    Process {
        id: runner
        stdout: StdioCollector {
            id: outCollector
        }
        stderr: StdioCollector {
            id: errCollector
        }
        onExited: exitCode => {
            const job = root.active;
            root.active = null;
            const out = outCollector.text ?? "";
            const err = errCollector.text ?? "";
            if (job) {
                if (job.callback)
                    job.callback(exitCode, out, err);
                root.commandFinished(job.tag ?? "", exitCode, out, err);
            }
            Qt.callLater(root.pump);
        }
    }
}
