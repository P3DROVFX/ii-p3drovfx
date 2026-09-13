/*
 * Parses the `nmcli` device and radio output that NetworkFallback publishes.
 *
 * Kept out of QML so the shape of every state a NetworkManager device can be
 * in can be tested without a NetworkManager to put a device into it.
 */

/**
 * nmcli --escape writes a literal colon inside a field as a backslash pair, so
 * the separator can only be found by walking the line.
 */
function splitEscaped(line) {
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

/** `nmcli -t -f WIFI,WIFI-HW radio`, which prints one line: "enabled:enabled". */
function parseRadio(text) {
    const parts = (text ?? "").trim().split(":");
    return {
        enabled: parts[0] === "enabled",
        // A machine with no radio at all reports "missing", which is not a
        // block software could lift. Only "disabled" is the rfkill the UI
        // offers to explain, so anything else counts as unblocked.
        hardwareEnabled: (parts[1] ?? "enabled") !== "disabled"
    };
}

/**
 * nmcli reports the state as "100 (connected)", where the number is its own
 * scale and means nothing outside it, and nests a second pair of brackets
 * around the phase of a connection still being made — "70 (connecting (getting
 * IP configuration))" — or around "connected (externally)". Only the first
 * word carries the state every surface here asks about.
 */
function stateWord(value) {
    const match = (value ?? "").match(/\(([^()]*)/);
    return (match ? match[1] : (value ?? "")).trim().split(" ")[0];
}

/**
 * `nmcli -t -e yes -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,
 * GENERAL.CONNECTION,GENERAL.HWADDR device show`, which prints one block per
 * device separated by a blank line. A block is opened by its DEVICE line
 * rather than by counting blank lines, so a field nmcli leaves out — it drops
 * whole lines rather than printing them empty — cannot shift the rest.
 */
function parseDevices(text) {
    const rows = [];
    let current = null;
    (text ?? "").split("\n").forEach(line => {
        const parts = splitEscaped(line);
        if (parts.length < 2)
            return;
        const key = parts[0];
        // The hardware address is the one value carrying colons of its own,
        // and nmcli leaves them unescaped even when asked not to.
        const value = parts.slice(1).join(":");
        if (key === "GENERAL.DEVICE") {
            current = {
                device: value,
                type: "",
                state: "",
                connection: "",
                mac: ""
            };
            rows.push(current);
            return;
        }
        if (!current)
            return;
        if (key === "GENERAL.TYPE")
            current.type = value;
        else if (key === "GENERAL.STATE")
            current.state = stateWord(value);
        else if (key === "GENERAL.CONNECTION")
            current.connection = value === "--" ? "" : value;
        else if (key === "GENERAL.HWADDR")
            current.mac = value === "--" ? "" : value;
    });
    return rows;
}

/**
 * A machine can carry more than one adapter of a kind — a built-in card and a
 * USB stick — and the one carrying the connection is the one every surface in
 * the shell is asking about.
 */
function pickDevice(rows, type) {
    const matching = (rows ?? []).filter(row => row.type === type);
    return matching.find(row => row.state === "connected") ?? (matching[0] ?? null);
}
