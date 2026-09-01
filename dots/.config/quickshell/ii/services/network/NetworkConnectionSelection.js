/*
 * Selects the connection name presented by shell surfaces that collapse the
 * wired and Wi-Fi states into one network indicator.
 */

function preferredConnectionName(wiredConnected, wiredName, wifiConnected, wifiName) {
    if (wiredConnected)
        return wiredName || "";
    if (wifiConnected)
        return wifiName || "";
    return "";
}

function preferredInterface(wiredConnected, wiredInterface, wifiConnected, wifiInterface) {
    if (wiredConnected)
        return wiredInterface || "";
    if (wifiConnected)
        return wifiInterface || "";
    return "";
}

function activeConnectionName(rows, type) {
    const suffix = ":" + type;
    for (const row of rows) {
        if (!row.endsWith(suffix))
            continue;
        return row.slice(0, -suffix.length).replace(/\\:/g, ":");
    }
    return "";
}

function seededConnectionName(rows) {
    return activeConnectionName(rows, "802-3-ethernet")
        || activeConnectionName(rows, "802-11-wireless");
}
