.pragma library

var controlOrder = ["12", "16", "18", "1A"];

function parseDetectedDisplays(text) {
    const displays = [];
    const blocks = String(text || "").split(/\n\s*\n/);

    for (let i = 0; i < blocks.length; i++) {
        const lines = blocks[i].split("\n").map(line => line.trim()).filter(line => line.length > 0);
        if (lines.length === 0 || !/^Display\s+\d+/.test(lines[0]))
            continue;

        const busLine = lines.find(line => line.startsWith("I2C bus:"));
        const connectorLine = lines.find(line => /^DRM(?: connector|_connector):/.test(line));
        if (!busLine || !connectorLine)
            continue;

        const busMatch = busLine.match(/\/dev\/i2c-(\d+)/);
        const connectorValue = connectorLine.substring(connectorLine.indexOf(":") + 1).trim();
        const connectorMatch = connectorValue.match(/^card\d+-(.+)$/);
        const connectorName = connectorMatch ? connectorMatch[1] : connectorValue;
        if (!busMatch || !connectorName)
            continue;

        displays.push({
            name: connectorName,
            busNum: busMatch[1]
        });
    }

    return displays;
}

function operationMatches(operationGeneration, operationBus, currentGeneration, currentBus) {
    return Number(operationGeneration) === Number(currentGeneration)
        && String(operationBus) === String(currentBus);
}

function parseVcpValues(text) {
    const values = {};
    const lines = String(text || "").split("\n");

    for (let i = 0; i < lines.length; i++) {
        const match = lines[i].trim().match(/^VCP\s+([0-9A-Fa-f]{2})\s+C\s+(-?\d+)\s+(-?\d+)/);
        if (!match)
            continue;

        const code = match[1].toUpperCase();
        const current = Number(match[2]);
        const maximum = Number(match[3]);
        if (!isFinite(current) || !isFinite(maximum) || maximum <= 0)
            continue;

        values[code] = {
            current,
            maximum
        };
    }

    return values;
}

function percentForValue(current, maximum) {
    if (!isFinite(current) || !isFinite(maximum) || maximum <= 0)
        return 0;
    return Math.max(0, Math.min(100, Math.round(Number(current) / Number(maximum) * 100)));
}

function rawValueForPercent(percent, maximum) {
    if (!isFinite(maximum) || maximum <= 0)
        return 0;
    const bounded = Math.max(0, Math.min(100, Number(percent)));
    return Math.round(bounded / 100 * Number(maximum));
}

function buildSetCommand(busNum, pendingValues) {
    const command = ["ddcutil", "-b", String(busNum), "setvcp"];
    const pending = pendingValues || {};

    for (let i = 0; i < controlOrder.length; i++) {
        const code = controlOrder[i];
        if (pending[code] === undefined)
            continue;
        command.push(code, String(Math.round(Number(pending[code]))));
    }

    return command;
}
