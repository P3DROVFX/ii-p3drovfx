pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "network/NmcliDeviceStatus.js" as Nmcli

/**
 * Every NetworkManager write the shell makes, through one serialised nmcli queue.
 *
 * Quickshell's native backend covers state but cannot build a settings
 * dictionary from QML, so profile creation, 802.1X, hidden SSIDs, addressing and
 * the hotspot all have to go through nmcli. Commands are argument vectors rather
 * than assembled shell strings.
 *
 * Secrets never go on a command line: /proc/<pid>/cmdline is readable by every
 * local user, and nmcli only takes secrets as arguments. The scripts that carry
 * one read it from $PASSWORD (/proc/<pid>/environ is private) and hand it to
 * scripts/network/set_secret.py, which stores it over D-Bus. A profile is
 * therefore always written in two steps: its settings through nmcli, then its
 * secret.
 */
Singleton {
    id: root

    readonly property string secretHelper: Quickshell.shellPath("scripts/network/set_secret.py")

    // $1 uuid, $2 setting.property; the secret is $PASSWORD.
    readonly property string kStoreSecret: `
        store_secret() { python3 "$SECRET_HELPER" "$1" "$2"; }
    `

    // $1 setting.property of the secret, then the arguments of `nmcli
    // connection add`. A profile whose secret cannot be stored is removed
    // again rather than left half made.
    readonly property string kAddWithSecret: root.kStoreSecret + `
        key="$1"; shift
        uuid=$(cat /proc/sys/kernel/random/uuid)
        nmcli connection add "$@" connection.uuid "$uuid" || exit
        store_secret "$uuid" "$key" || { nmcli connection delete uuid "$uuid" >/dev/null; exit 1; }
    `

    // $1 uuid, $2 setting.property of the secret, then settings to change first.
    readonly property string kModifySecret: root.kStoreSecret + `
        uuid="$1"; key="$2"; shift 2
        if [ $# -gt 0 ]; then nmcli connection modify uuid "$uuid" "$@" || exit; fi
        store_secret "$uuid" "$key"
    `

    // ---- 802.1X -----------------------------------------------------------
    // Printed by the scripts below on a line of their own, for Network to read.
    readonly property string kNoProfile: "no-profile"
    readonly property string kCertificateProfile: "eap-tls"

    // Defines find_profile: the uuid of the saved Wi-Fi profile for the SSID in
    // $1. Matched on the SSID rather than the name, which a provisioning tool —
    // or nmcli's own "eduroam 1" — can set to anything. One batched show: every
    // Wi-Fi profile carries both fields, so records are always uuid, SSID and a
    // blank separator.
    readonly property string kFindProfile: `
        find_profile() {
            local ids=() uuid type ssid
            while IFS=: read -r uuid type; do
                [ "$type" = 802-11-wireless ] && ids+=(uuid "$uuid")
            done < <(nmcli -t -f UUID,TYPE connection show)
            [ \${#ids[@]} -gt 0 ] || return
            nmcli -e no -g connection.uuid,802-11-wireless.ssid connection show "\${ids[@]}" |
                while IFS= read -r uuid && IFS= read -r ssid; do
                    [ "$ssid" = "$1" ] && { echo "$uuid"; break; }
                    IFS= read -r
                done
        }
    `

    // $1 SSID, $2 device (may be empty). `nmcli device wifi connect` would
    // reuse the profile as well, but this way a certificate profile can say
    // there is no password to ask for, and a failed login gives up after 30 s
    // rather than 90 — every other nmcli call queues behind it.
    readonly property string kConnectEnterprise: root.kFindProfile + `
        uuid=$(find_profile "$1")
        [ -n "$uuid" ] || { echo ${root.kNoProfile}; exit 10; }
        [ "$(nmcli -g 802-1x.eap connection show uuid "$uuid")" = tls ] && echo ${root.kCertificateProfile}
        up=(); [ -n "$2" ] && up=(ifname "$2")
        exec nmcli --wait 30 connection up uuid "$uuid" "\${up[@]}"
    `

    // $1 SSID, $2 device (may be empty), then extra settings for a profile
    // created here. An existing profile is updated in place, so whatever set it
    // up (CA certificate, anonymous identity, another phase 2) stays. A new one
    // offers PEAP and TTLS, both with MSCHAPv2 inside, which covers most
    // networks; the server picks. The password is stored with the profile
    // (flags 0) because the shell runs no secret agent to hand it over later.
    // The server domain is only written when it differs from $SAVED_DOMAIN: set,
    // the server certificate must chain to a system CA and match it; cleared,
    // that check is turned off.
    readonly property string kSaveEnterprise: root.kFindProfile + root.kStoreSecret + `
        ssid="$1"; ifname="$2"; shift 2
        args=(802-1x.password-flags 0)
        [ -n "$IDENTITY" ] && args+=(802-1x.identity "$IDENTITY")
        if [ "$DOMAIN" != "$SAVED_DOMAIN" ]; then
            if [ -n "$DOMAIN" ]; then
                args+=(802-1x.system-ca-certs yes 802-1x.domain-suffix-match "$DOMAIN")
            else
                args+=(802-1x.system-ca-certs no 802-1x.domain-suffix-match "")
            fi
        fi
        uuid=$(find_profile "$ssid")
        if [ -n "$uuid" ]; then
            nmcli connection modify uuid "$uuid" "\${args[@]}" || exit
        else
            [ -n "$IDENTITY" ] || { echo ${root.kNoProfile}; exit 10; }
            uuid=$(cat /proc/sys/kernel/random/uuid)
            nmcli connection add type wifi con-name "$ssid" ssid "$ssid" connection.uuid "$uuid" wifi-sec.key-mgmt wpa-eap \\
                802-1x.eap peap,ttls 802-1x.phase2-auth mschapv2 "\${args[@]}" "$@" >/dev/null || exit
        fi
        store_secret "$uuid" 802-1x.password || exit
        up=(); [ -n "$ifname" ] && up=(ifname "$ifname")
        exec nmcli --wait 30 connection up uuid "$uuid" "\${up[@]}"
    `

    // $1 SSID, $2 device (may be empty), $3 what the scan says a new profile
    // needs (wpa-psk, sae or wep), then extra settings for a profile created
    // here. Like `nmcli device wifi connect`, which takes the password only
    // as an argument: reuse the profile for the SSID or make one, then store
    // the secret where that profile keeps it.
    readonly property string kConnectPsk: root.kFindProfile + root.kStoreSecret + `
        ssid="$1"; ifname="$2"; kind="$3"; shift 3
        uuid=$(find_profile "$ssid")
        if [ -z "$uuid" ]; then
            if [ "$kind" = wep ]; then
                # nmcli's own guess: 5 or 13 characters, or 10 or 26 hex digits,
                # are a key; anything else is a passphrase.
                type=passphrase
                if [[ \${#PASSWORD} =~ ^(5|13)$ ]] || [[ \${#PASSWORD} =~ ^(10|26)$ && $PASSWORD =~ ^[0-9A-Fa-f]+$ ]]; then
                    type=key
                fi
                security=(wifi-sec.key-mgmt none wifi-sec.wep-key-type "$type")
            else
                security=(wifi-sec.key-mgmt "$kind")
            fi
            uuid=$(cat /proc/sys/kernel/random/uuid)
            nmcli connection add type wifi con-name "$ssid" ssid "$ssid" connection.uuid "$uuid" \\
                "\${security[@]}" "$@" >/dev/null || exit
        fi
        key=802-11-wireless-security.psk
        [ "$(nmcli -g 802-11-wireless-security.key-mgmt connection show uuid "$uuid")" = none ] && key=802-11-wireless-security.wep-key0
        store_secret "$uuid" "$key" || exit
        up=(); [ -n "$ifname" ] && up=(ifname "$ifname")
        exec nmcli connection up uuid "$uuid" "\${up[@]}"
    `

    // No secrets: --show-secrets is never passed. A profile without an 802-1x
    // setting prints nothing at all, so every field comes back empty.
    readonly property string kReadEnterprise: root.kFindProfile + `
        uuid=$(find_profile "$1")
        [ -n "$uuid" ] && nmcli -e no -g 802-1x.identity,802-1x.domain-suffix-match,802-1x.ca-cert connection show uuid "$uuid"
    `

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

    // The environment of a script that carries a secret.
    function secretEnv(secret: string, extra = ({})): var {
        return Object.assign({
            PASSWORD: secret,
            SECRET_HELPER: root.secretHelper
        }, extra);
    }

    // `options` takes ifname, hidden and kind: wpa-psk (default), sae or wep,
    // for a profile that has to be created.
    function connectWithPsk(ssid: string, psk: string, options = ({}), callback = null): void {
        const extra = options.hidden ? ["802-11-wireless.hidden", "yes"] : [];
        root.runScript(root.kConnectPsk, [ssid, options.ifname ?? "", options.kind ?? "wpa-psk", ...extra], "connect", callback, root.secretEnv(psk));
    }

    // Brings up the saved 802.1X profile for `ssid`. With none saved it prints
    // kNoProfile and fails, which is the cue to ask for credentials.
    function connectEnterprise(ssid: string, ifname = "", callback = null): void {
        root.runScript(root.kConnectEnterprise, [ssid, ifname], "connect", callback);
    }

    /**
     * Stores 802.1X credentials for `ssid` — in the saved profile if there is
     * one, in a new PEAP/TTLS profile if not — and brings it up. `options` takes
     * identity (empty keeps the saved one), domain and savedDomain (the server
     * domain is only written when they differ), ifname and hidden.
     */
    function saveEnterprise(ssid: string, password: string, options = ({}), callback = null): void {
        const extra = options.hidden ? ["802-11-wireless.hidden", "yes"] : [];
        root.runScript(root.kSaveEnterprise, [ssid, options.ifname ?? "", ...extra], "enterprise", callback, root.secretEnv(password, {
            IDENTITY: options.identity ?? "",
            DOMAIN: options.domain ?? "",
            SAVED_DOMAIN: options.savedDomain ?? ""
        }));
    }

    // What a credentials prompt can show back: the saved profile's identity,
    // server domain and whether it pins a CA certificate (as provisioning tools
    // do), or empty values.
    function readEnterpriseProfile(ssid: string, callback): void {
        root.runScript(root.kReadEnterprise, [ssid], "settings", (code, out) => {
            const lines = code === 0 ? out.split("\n") : [];
            callback({
                identity: lines[0] ?? "",
                domain: lines[1] ?? "",
                caCert: (lines[2] ?? "").length > 0
            });
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
    // Shared with the device parser, which needs the same escape rules and is
    // tested on its own.
    function splitEscaped(line: string): var {
        return Nmcli.splitEscaped(line);
    }

    /**
     * Per access point extras the D-Bus backend doesn't expose: BSSID, frequency
     * and NetworkManager's own security string. Keyed by SSID.
     */
    function readWifiDetails(callback): void {
        root.run(["nmcli", "-t", "-e", "yes", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "device", "wifi"], "details", (code, out) => {
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
                security: parts[5] ?? ""
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

    // The SSIDs the saved Wi-Fi profiles connect to, which a profile's name
    // need not be. One batched show: a record per profile, blank-separated.
    readonly property string kSavedSsids: `
        ids=()
        while IFS=: read -r uuid type; do
            [ "$type" = 802-11-wireless ] && ids+=(uuid "$uuid")
        done < <(nmcli -t -f UUID,TYPE connection show)
        [ \${#ids[@]} -eq 0 ] || nmcli -e no -g 802-11-wireless.ssid connection show "\${ids[@]}"
    `

    function readSavedWifiSsids(callback): void {
        root.runScript(root.kSavedSsids, [], "saved", (code, out) => {
            callback(code === 0 ? out.split("\n").filter(line => line.length > 0) : []);
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
        root.runScript(root.kModifySecret, [uuid, secretKey, ...root.settingsToArgv(settings)], "modify", callback, root.secretEnv(secret));
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
        root.runScript(root.kAddWithSecret, [secretKey, "type", "wifi", "con-name", name, "ssid", ssid, ...pairs], "add", callback, root.secretEnv(secret));
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
        // Prints nmcli's success line, which is where the caller reads the uuid.
        root.runScript(root.kAddWithSecret, ["802-11-wireless-security.psk", "type", "wifi", "con-name", name,
            ...device, "ssid", ssid, ...pairs], "add", callback, root.secretEnv(secret));
    }

    // ---- Wired ------------------------------------------------------------

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
        root.runScript(root.kAddWithSecret, [secretKey, "type", "ethernet", "con-name", name, ...device, ...pairs], "add",
            callback, root.secretEnv(secret));
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
