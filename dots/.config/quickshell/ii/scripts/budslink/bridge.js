'use strict';

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GioUnix from 'gi://GioUnix';

// Promisify Gio async methods
Gio._promisify(Gio.DBusProxy.prototype, 'call');
Gio._promisify(Gio.DBusProxy, 'new_for_bus');
Gio._promisify(Gio.DBusConnection.prototype, 'call');
Gio._promisify(Gio.DataInputStream.prototype, 'read_line_async');

const CLIENT_ID = 'ii-p3drovfx-budslink';
const BUS_NAME = 'io.github.maniacx.BudsLink';
const MANAGER_PATH = '/io/github/maniacx/BudsLink';
const MANAGER_INTERFACE = 'io.github.maniacx.BudsLink.DeviceManager';
const DEVICE_INTERFACE = 'io.github.maniacx.BudsLink.Device';
const HEARTBEAT_INTERVAL_SEC = 120;

// Explicit supported D-Bus interface contract (currently 0.0.1)
const SUPPORTED_VERSIONS = new Set(['0.0.1']);

function isVersionSupported(version) {
    if (typeof version !== 'string') return false;
    return SUPPORTED_VERSIONS.has(version.trim());
}

const loop = new GLib.MainLoop(null, false);

let bus = null;
let managerProxy = null;
let managerSignalHandlerId = 0;
let nameWatcherId = 0;
let heartbeatTimerId = null;

let isServiceAvailable = false;
let isServiceHeld = false;
let desiredHeld = false;
let currentServiceVersion = '';

// Tracked devices: Map<string, { path: string, mac: string, proxy: Gio.DBusProxy, alias: string, config: object, state: object, propHandlerId: number }>()
const trackedDevices = new Map();

/**
 * Emit JSON-lines event to stdout.
 * Diagnostics and errors MUST only go to stderr.
 */
function emitEvent(obj) {
    try {
        const line = JSON.stringify(obj);
        print(line);
    } catch (err) {
        printerr(`[BudsLink bridge] Failed to serialize event: ${err.message}`);
    }
}

function emitError(code, message) {
    emitEvent({
        type: 'error',
        code: String(code || 'unknownError'),
        message: String(message || '')
    });
}

/**
 * Safe JSON parser returning an object on failure without crashing.
 */
function safeParseJson(str) {
    if (!str || typeof str !== 'string') return {};
    try {
        const parsed = JSON.parse(str);
        return (parsed && typeof parsed === 'object') ? parsed : {};
    } catch (err) {
        printerr(`[BudsLink bridge] Malformed JSON in property: ${err.message}`);
        return {};
    }
}

/**
 * Extract canonical MAC address (AA:BB:CC:DD:EE:FF) only from object path dev_AA_BB_CC_DD_EE_FF.
 */
function deriveMacFromPath(path) {
    if (typeof path !== 'string') return '';
    const match = path.match(/dev_([0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2})/);
    if (match) {
        return match[1].replace(/_/g, ':').toUpperCase();
    }
    return '';
}

let deviceGenerationCounter = 0;

/**
 * Validate action name against Section 45 allowlist / dynamic patterns.
 */
function isValidActionName(action) {
    if (!action || typeof action !== 'string') return false;
    if (action === 'settingsButtonClicked') return true;
    if (/^toggle[1-2]State$/.test(action)) return true;
    if (/^box[1-4]SliderValue$/.test(action)) return true;
    if (/^box[1-4]SliderIsDragging$/.test(action)) return true;
    if (/^box[1-4]CheckButton[1-2]State$/.test(action)) return true;
    if (/^box[1-4]RadioButtonState$/.test(action)) return true;
    return false;
}

/**
 * Validate action value: reject non-finite/non-integer numbers or invalid strings.
 */
function parseAndValidateActionValue(rawValue) {
    if (rawValue === null || rawValue === undefined) {
        return { valid: false, error: 'Value is required' };
    }
    if (typeof rawValue === 'boolean') {
        return { valid: true, value: rawValue ? 1 : 0 };
    }
    if (typeof rawValue === 'number') {
        if (!Number.isFinite(rawValue) || !Number.isInteger(rawValue)) {
            return { valid: false, error: 'Numeric value must be a finite integer' };
        }
        return { valid: true, value: rawValue };
    }
    if (typeof rawValue === 'string') {
        const trimmed = rawValue.trim();
        if (/^-?\d+$/.test(trimmed)) {
            const num = Number(trimmed);
            if (Number.isSafeInteger(num)) {
                return { valid: true, value: num };
            }
        }
        return { valid: false, error: 'String value must represent a valid integer' };
    }
    return { valid: false, error: 'Value must be an integer, integer string, or boolean' };
}

function startHeartbeat() {
    stopHeartbeat();
    heartbeatTimerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, HEARTBEAT_INTERVAL_SEC, () => {
        if (isServiceAvailable && isVersionSupported(currentServiceVersion) && desiredHeld && managerProxy) {
            managerProxy.call('HoldService', GLib.Variant.new('(s)', [CLIENT_ID]), Gio.DBusCallFlags.NONE, 2000, null)
                .then(() => {
                    if (!isServiceHeld) {
                        isServiceHeld = true;
                        emitEvent({
                            type: 'serviceStatus',
                            available: true,
                            version: currentServiceVersion,
                            held: true
                        });
                    }
                })
                .catch(err => {
                    isServiceHeld = false;
                    printerr(`[BudsLink bridge] Heartbeat HoldService error: ${err.message}`);
                    emitError('holdFailed', `Heartbeat HoldService error: ${err.message}`);
                    emitEvent({
                        type: 'serviceStatus',
                        available: isServiceAvailable,
                        version: currentServiceVersion,
                        held: false
                    });
                });
            return GLib.SOURCE_CONTINUE;
        }
        heartbeatTimerId = null;
        return GLib.SOURCE_REMOVE;
    });
}

function stopHeartbeat() {
    if (heartbeatTimerId !== null) {
        GLib.source_remove(heartbeatTimerId);
        heartbeatTimerId = null;
    }
}

async function doHoldService() {
    if (!isServiceAvailable || !managerProxy || !isVersionSupported(currentServiceVersion)) return;
    try {
        await managerProxy.call('HoldService', GLib.Variant.new('(s)', [CLIENT_ID]), Gio.DBusCallFlags.NONE, 2000, null);
        isServiceHeld = true;
        startHeartbeat();
    } catch (err) {
        isServiceHeld = false;
        printerr(`[BudsLink bridge] HoldService failed: ${err.message}`);
        emitError('holdFailed', `HoldService failed: ${err.message}`);
    }
}

async function doReleaseService() {
    stopHeartbeat();
    if (!isServiceAvailable || !managerProxy) {
        isServiceHeld = false;
        return;
    }
    try {
        await managerProxy.call('ReleaseService', GLib.Variant.new('(s)', [CLIENT_ID]), Gio.DBusCallFlags.NONE, 2000, null);
        isServiceHeld = false;
    } catch (err) {
        isServiceHeld = false;
        printerr(`[BudsLink bridge] ReleaseService failed: ${err.message}`);
        emitError('releaseFailed', `ReleaseService failed: ${err.message}`);
    }
}

async function fetchDeviceSnapshot(devEntry) {
    if (!devEntry || devEntry.removed || !devEntry.proxy || trackedDevices.get(devEntry.path) !== devEntry) return;

    try {
        const res = await devEntry.proxy.call(
            'org.freedesktop.DBus.Properties.GetAll',
            GLib.Variant.new('(s)', [DEVICE_INTERFACE]),
            Gio.DBusCallFlags.NONE,
            2000,
            null
        );

        if (devEntry.removed || trackedDevices.get(devEntry.path) !== devEntry) return;

        const [propsMap] = res.deepUnpack();
        if (propsMap) {
            if (propsMap.Alias !== undefined) {
                const aliasVal = propsMap.Alias;
                devEntry.alias = String(aliasVal !== undefined ? (aliasVal.deepUnpack ? aliasVal.deepUnpack() : aliasVal) : '');
            }
            if (propsMap.Config !== undefined) {
                const configVal = propsMap.Config;
                const rawConfig = configVal !== undefined ? (configVal.deepUnpack ? configVal.deepUnpack() : configVal) : '';
                devEntry.config = safeParseJson(rawConfig);
            }
            if (propsMap.State !== undefined) {
                const stateVal = propsMap.State;
                const rawState = stateVal !== undefined ? (stateVal.deepUnpack ? stateVal.deepUnpack() : stateVal) : '';
                devEntry.state = safeParseJson(rawState);
            }
        }
    } catch (e) {
        if (devEntry.removed || !devEntry.proxy || trackedDevices.get(devEntry.path) !== devEntry) return;

        const aliasVar = devEntry.proxy.get_cached_property('Alias');
        const configVar = devEntry.proxy.get_cached_property('Config');
        const stateVar = devEntry.proxy.get_cached_property('State');

        if (aliasVar) devEntry.alias = String(aliasVar.deepUnpack());
        if (configVar) devEntry.config = safeParseJson(configVar.deepUnpack());
        if (stateVar) devEntry.state = safeParseJson(stateVar.deepUnpack());
    }

    if (devEntry.removed || trackedDevices.get(devEntry.path) !== devEntry) return;

    emitEvent({
        type: 'deviceSnapshot',
        path: devEntry.path,
        mac: devEntry.mac,
        alias: devEntry.alias,
        config: devEntry.config,
        state: devEntry.state
    });
}

async function onDevicePropertiesChanged(devEntry, changedProps, invalidatedProps) {
    if (!devEntry || devEntry.removed || !devEntry.proxy || trackedDevices.get(devEntry.path) !== devEntry) return;
    const path = devEntry.path;

    let propsMap = null;
    if (changedProps) {
        try {
            propsMap = changedProps.deepUnpack ? changedProps.deepUnpack() : changedProps;
        } catch (err) {
            printerr(`[BudsLink bridge] Error unpacking PropertiesChanged for ${path}: ${err.message}`);
        }
    }

    let invalidatedList = [];
    if (invalidatedProps) {
        try {
            const unp = invalidatedProps.deepUnpack ? invalidatedProps.deepUnpack() : invalidatedProps;
            if (Array.isArray(unp)) {
                invalidatedList = unp;
            }
        } catch (err) {
            printerr(`[BudsLink bridge] Error unpacking invalidatedProperties for ${path}: ${err.message}`);
        }
    }

    if (devEntry.removed || trackedDevices.get(path) !== devEntry) return;

    if (propsMap && typeof propsMap === 'object') {
        if ('Alias' in propsMap) {
            const aliasVal = propsMap.Alias;
            devEntry.alias = String(aliasVal !== undefined ? (aliasVal.deepUnpack ? aliasVal.deepUnpack() : aliasVal) : '');
            if (!devEntry.removed && trackedDevices.get(path) === devEntry) {
                emitEvent({
                    type: 'deviceAlias',
                    path: path,
                    alias: devEntry.alias
                });
            }
        }

        if ('Config' in propsMap) {
            const configVal = propsMap.Config;
            const raw = configVal !== undefined ? (configVal.deepUnpack ? configVal.deepUnpack() : configVal) : '';
            devEntry.config = safeParseJson(raw);
            if (!devEntry.removed && trackedDevices.get(path) === devEntry) {
                emitEvent({
                    type: 'deviceConfig',
                    path: path,
                    config: devEntry.config
                });
            }
        }

        if ('State' in propsMap) {
            const stateVal = propsMap.State;
            const raw = stateVal !== undefined ? (stateVal.deepUnpack ? stateVal.deepUnpack() : stateVal) : '';
            devEntry.state = safeParseJson(raw);
            if (!devEntry.removed && trackedDevices.get(path) === devEntry) {
                emitEvent({
                    type: 'deviceState',
                    path: path,
                    state: devEntry.state
                });
            }
        }
    }

    if (invalidatedList.length > 0) {
        for (const propName of invalidatedList) {
            if (devEntry.removed || !devEntry.proxy || trackedDevices.get(path) !== devEntry) return;
            try {
                const res = await devEntry.proxy.call(
                    'org.freedesktop.DBus.Properties.Get',
                    GLib.Variant.new('(ss)', [DEVICE_INTERFACE, propName]),
                    Gio.DBusCallFlags.NONE,
                    2000,
                    null
                );
                if (devEntry.removed || trackedDevices.get(path) !== devEntry) return;
                const [propVal] = res.deepUnpack();
                const unwrapped = propVal && propVal.deepUnpack ? propVal.deepUnpack() : propVal;
                if (propName === 'Alias') {
                    devEntry.alias = String(unwrapped || '');
                    if (!devEntry.removed && trackedDevices.get(path) === devEntry) {
                        emitEvent({
                            type: 'deviceAlias',
                            path: path,
                            alias: devEntry.alias
                        });
                    }
                } else if (propName === 'Config') {
                    devEntry.config = safeParseJson(unwrapped);
                    if (!devEntry.removed && trackedDevices.get(path) === devEntry) {
                        emitEvent({
                            type: 'deviceConfig',
                            path: path,
                            config: devEntry.config
                        });
                    }
                } else if (propName === 'State') {
                    devEntry.state = safeParseJson(unwrapped);
                    if (!devEntry.removed && trackedDevices.get(path) === devEntry) {
                        emitEvent({
                            type: 'deviceState',
                            path: path,
                            state: devEntry.state
                        });
                    }
                }
            } catch (err) {
                printerr(`[BudsLink bridge] Failed to re-fetch invalidated property ${propName} on ${path}: ${err.message}`);
            }
        }
    }
}

async function addOrUpdateDevice(path) {
    if (typeof path !== 'string' || !path.startsWith('/')) return;
    const mac = deriveMacFromPath(path);
    if (!mac) {
        printerr(`[BudsLink bridge] Skipping device path without canonical MAC pattern: ${path}`);
        return;
    }

    let devEntry = trackedDevices.get(path);
    if (!devEntry) {
        const gen = ++deviceGenerationCounter;
        devEntry = {
            path: path,
            mac: mac,
            proxy: null,
            alias: '',
            config: {},
            state: {},
            propHandlerId: 0,
            generation: gen,
            removed: false
        };
        trackedDevices.set(path, devEntry);

        try {
            const proxy = await Gio.DBusProxy.new_for_bus(
                Gio.BusType.SESSION,
                Gio.DBusProxyFlags.NONE,
                null,
                BUS_NAME,
                path,
                DEVICE_INTERFACE,
                null
            );

            if (devEntry.removed || !isServiceAvailable || trackedDevices.get(path) !== devEntry) {
                return;
            }

            devEntry.proxy = proxy;
            devEntry.propHandlerId = proxy.connect('g-properties-changed', (p, changedProps, invalidatedProps) => {
                onDevicePropertiesChanged(devEntry, changedProps, invalidatedProps).catch(err => {
                    printerr(`[BudsLink bridge] Error in PropertiesChanged handler: ${err.message}`);
                });
            });

            emitEvent({ type: 'deviceAdded', path: path });
        } catch (err) {
            if (trackedDevices.get(path) === devEntry) {
                trackedDevices.delete(path);
            }
            printerr(`[BudsLink bridge] Failed to create proxy for ${path}: ${err.message}`);
            emitError('deviceProxyFailed', `Failed creating proxy for ${path}: ${err.message}`);
            return;
        }
    }

    await fetchDeviceSnapshot(devEntry);
}

function removeDevice(path) {
    const devEntry = trackedDevices.get(path);
    if (devEntry) {
        devEntry.removed = true;
        if (devEntry.propHandlerId && devEntry.proxy) {
            try {
                devEntry.proxy.disconnect(devEntry.propHandlerId);
            } catch (e) {}
        }
        trackedDevices.delete(path);
        emitEvent({ type: 'deviceRemoved', path: path });
    }
}

async function enumerateDevices() {
    if (!isServiceAvailable || !managerProxy || !isVersionSupported(currentServiceVersion)) return;
    try {
        const res = await managerProxy.call('ListDevices', null, Gio.DBusCallFlags.NONE, 3000, null);
        const [devicePaths] = res.deepUnpack();
        if (Array.isArray(devicePaths)) {
            const activeSet = new Set(devicePaths);
            for (const path of Array.from(trackedDevices.keys())) {
                if (!activeSet.has(path)) {
                    removeDevice(path);
                }
            }
            for (const path of devicePaths) {
                await addOrUpdateDevice(path);
            }
        }
    } catch (err) {
        printerr(`[BudsLink bridge] ListDevices error: ${err.message}`);
        emitError('enumerateFailed', `ListDevices failed: ${err.message}`);
    }
}

async function onServiceAppeared() {
    let proxy = null;
    try {
        proxy = await Gio.DBusProxy.new_for_bus(
            Gio.BusType.SESSION,
            Gio.DBusProxyFlags.NONE,
            null,
            BUS_NAME,
            MANAGER_PATH,
            MANAGER_INTERFACE,
            null
        );
    } catch (err) {
        isServiceAvailable = false;
        isServiceHeld = false;
        currentServiceVersion = '';
        emitError('managerProxyFailed', `Failed creating manager proxy: ${err.message}`);
        emitEvent({
            type: 'serviceStatus',
            available: false,
            version: '',
            held: false
        });
        return;
    }

    let ver = '';
    try {
        const res = await proxy.call('ServiceVersion', null, Gio.DBusCallFlags.NONE, 2000, null);
        const [verVal] = res.deepUnpack();
        ver = String(verVal || '').trim();
    } catch (err) {
        isServiceAvailable = false;
        isServiceHeld = false;
        currentServiceVersion = '';
        emitError('serviceVersionFailed', `ServiceVersion query error: ${err.message}`);
        emitEvent({
            type: 'serviceStatus',
            available: false,
            version: '',
            held: false
        });
        return;
    }

    if (!isVersionSupported(ver)) {
        isServiceAvailable = false;
        isServiceHeld = false;
        currentServiceVersion = ver;
        emitError('serviceVersionUnsupported', `Unsupported BudsLink version: ${ver}`);
        emitEvent({
            type: 'serviceStatus',
            available: false,
            version: ver,
            held: false
        });
        return;
    }

    managerProxy = proxy;
    isServiceAvailable = true;
    currentServiceVersion = ver;

    if (managerSignalHandlerId && managerProxy) {
        try { managerProxy.disconnect(managerSignalHandlerId); } catch (e) {}
        managerSignalHandlerId = 0;
    }

    managerSignalHandlerId = managerProxy.connect('g-signal', (proxyObj, senderName, signalName, parameters) => {
        try {
            const unpacked = parameters.deepUnpack();
            if (signalName === 'DeviceAdded' && Array.isArray(unpacked) && unpacked.length > 0) {
                const devPath = unpacked[0];
                addOrUpdateDevice(devPath).catch(err => {
                    printerr(`[BudsLink bridge] Error in DeviceAdded handler for ${devPath}: ${err.message}`);
                });
            } else if (signalName === 'DeviceRemoved' && Array.isArray(unpacked) && unpacked.length > 0) {
                const devPath = unpacked[0];
                removeDevice(devPath);
            }
        } catch (err) {
            printerr(`[BudsLink bridge] Error handling manager signal ${signalName}: ${err.message}`);
        }
    });

    if (desiredHeld) {
        await doHoldService();
    }

    emitEvent({
        type: 'serviceStatus',
        available: true,
        version: currentServiceVersion,
        held: isServiceHeld
    });

    await enumerateDevices();
}

function onServiceVanished() {
    isServiceAvailable = false;
    isServiceHeld = false;
    currentServiceVersion = '';
    stopHeartbeat();

    if (managerSignalHandlerId && managerProxy) {
        try { managerProxy.disconnect(managerSignalHandlerId); } catch (e) {}
        managerSignalHandlerId = 0;
    }
    managerProxy = null;

    for (const [path, dev] of trackedDevices.entries()) {
        dev.removed = true;
        if (dev.propHandlerId && dev.proxy) {
            try { dev.proxy.disconnect(dev.propHandlerId); } catch (e) {}
        }
        emitEvent({ type: 'deviceRemoved', path: path });
    }
    trackedDevices.clear();

    emitEvent({
        type: 'serviceStatus',
        available: false,
        version: '',
        held: false
    });
}

async function handleActionCommand(cmd) {
    const path = cmd.path;
    const action = cmd.action;
    const rawValue = cmd.value;

    if (!path || typeof path !== 'string' || !path.startsWith('/io/github/maniacx/BudsLink/Devices/')) {
        emitError('invalidPath', `Invalid device path: ${path}`);
        return;
    }

    const mac = deriveMacFromPath(path);
    if (!mac) {
        emitError('invalidPath', `Device path lacks valid MAC address: ${path}`);
        return;
    }

    if (!isValidActionName(action)) {
        emitError('invalidAction', `Invalid action name: ${action}`);
        return;
    }

    const valResult = parseAndValidateActionValue(rawValue);
    if (!valResult.valid) {
        emitError('invalidValue', valResult.error);
        return;
    }
    const intValue = valResult.value;

    if (!isServiceAvailable) {
        emitError('serviceUnavailable', 'BudsLink service is not available');
        return;
    }

    if (!isVersionSupported(currentServiceVersion)) {
        emitError('serviceVersionUnsupported', `Cannot execute action on unsupported service version: ${currentServiceVersion}`);
        return;
    }

    let devEntry = trackedDevices.get(path);
    if (!devEntry) {
        emitError('deviceNotFound', `Device not tracked: ${path}`);
        return;
    }

    try {
        await devEntry.proxy.call(
            'UiAction',
            GLib.Variant.new('(si)', [action, intValue]),
            Gio.DBusCallFlags.NONE,
            3000,
            null
        );
    } catch (err) {
        printerr(`[BudsLink bridge] UiAction failed on ${path}: ${err.message}`);
        emitError('actionFailed', `UiAction failed: ${err.message}`);
    }
}

function sleepMs(ms) {
    return new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
        resolve();
        return GLib.SOURCE_REMOVE;
    }));
}

/**
 * Restart the BudsLink service process so it re-registers its BlueZ profiles.
 * Used when BudsLink is up but never claimed a connected audio device (its
 * RegisterProfile lost a race against another RFCOMM client at startup).
 * Only works when nothing else keeps BudsLink alive (no open window, no other
 * holder); in that case the restart is skipped and the hold is re-established.
 */
async function doRestartService() {
    if (isServiceAvailable) {
        await doReleaseService();
        for (let i = 0; i < 48 && isServiceAvailable; i++) {
            await sleepMs(250);
        }
        if (isServiceAvailable) {
            printerr('[BudsLink bridge] Service restart skipped: BudsLink is still running (window open or other holder)');
            emitError('restartSkipped', 'BudsLink did not exit; restart skipped');
            if (desiredHeld) await doHoldService();
            emitEvent({
                type: 'serviceStatus',
                available: true,
                version: currentServiceVersion,
                held: isServiceHeld
            });
            return;
        }
    }

    // Re-activate via D-Bus autostart; the name watcher then runs the normal appear flow.
    try {
        await Gio.DBusProxy.new_for_bus(
            Gio.BusType.SESSION,
            Gio.DBusProxyFlags.DO_NOT_LOAD_PROPERTIES,
            null,
            BUS_NAME,
            MANAGER_PATH,
            MANAGER_INTERFACE,
            null
        );
    } catch (err) {
        emitError('restartFailed', `Failed to re-activate BudsLink: ${err.message}`);
    }
}

async function processCommand(line) {
    if (!line || line.trim().length === 0) return;
    let cmdObj;
    try {
        cmdObj = JSON.parse(line);
    } catch (e) {
        emitError('malformedJson', `Malformed command JSON: ${e.message}`);
        return;
    }

    if (!cmdObj || typeof cmdObj !== 'object' || typeof cmdObj.command !== 'string') {
        emitError('invalidCommand', 'Missing or invalid command property');
        return;
    }

    const cmd = cmdObj.command;
    switch (cmd) {
    case 'hold':
        desiredHeld = true;
        if (isServiceAvailable && isVersionSupported(currentServiceVersion)) {
            await doHoldService();
            emitEvent({
                type: 'serviceStatus',
                available: true,
                version: currentServiceVersion,
                held: isServiceHeld
            });
        } else if (isServiceAvailable && !isVersionSupported(currentServiceVersion)) {
            emitError('serviceVersionUnsupported', `Cannot hold incompatible version: ${currentServiceVersion}`);
            emitEvent({
                type: 'serviceStatus',
                available: false,
                version: currentServiceVersion,
                held: false
            });
        } else {
            emitEvent({
                type: 'serviceStatus',
                available: false,
                version: '',
                held: false
            });
        }
        break;

    case 'restartService':
        await doRestartService();
        break;

    case 'release':
        desiredHeld = false;
        if (isServiceAvailable && isServiceHeld) {
            await doReleaseService();
            emitEvent({
                type: 'serviceStatus',
                available: true,
                version: currentServiceVersion,
                held: false
            });
        } else {
            emitEvent({
                type: 'serviceStatus',
                available: isServiceAvailable && isVersionSupported(currentServiceVersion),
                version: currentServiceVersion,
                held: false
            });
        }
        break;

    case 'enumerate':
        if (isServiceAvailable && isVersionSupported(currentServiceVersion)) {
            await enumerateDevices();
            emitEvent({
                type: 'serviceStatus',
                available: true,
                version: currentServiceVersion,
                held: isServiceHeld
            });
        } else if (isServiceAvailable && !isVersionSupported(currentServiceVersion)) {
            emitError('serviceVersionUnsupported', `Cannot enumerate on incompatible version: ${currentServiceVersion}`);
        } else {
            emitEvent({
                type: 'serviceStatus',
                available: false,
                version: '',
                held: false
            });
        }
        break;

    case 'action':
        await handleActionCommand(cmdObj);
        break;

    case 'shutdown':
        desiredHeld = false;
        stopHeartbeat();
        if (isServiceAvailable && isServiceHeld && managerProxy) {
            try {
                await doReleaseService();
            } catch (e) {}
        }
        if (nameWatcherId) {
            Gio.bus_unwatch_name(nameWatcherId);
            nameWatcherId = 0;
        }
        for (const dev of trackedDevices.values()) {
            dev.removed = true;
            if (dev.propHandlerId && dev.proxy) {
                try { dev.proxy.disconnect(dev.propHandlerId); } catch (e) {}
            }
        }
        trackedDevices.clear();
        loop.quit();
        break;

    default:
        emitError('unknownCommand', `Unknown command: ${cmd}`);
        break;
    }
}

async function startStdinLoop() {
    const stdinStream = new Gio.DataInputStream({
        base_stream: new GioUnix.InputStream({ fd: 0, close_fd: false })
    });

    while (true) {
        try {
            const [bytes, len] = await stdinStream.read_line_async(GLib.PRIORITY_DEFAULT, null);
            if (bytes === null) {
                // EOF on stdin
                printerr('[BudsLink bridge] EOF on stdin, exiting cleanly');
                desiredHeld = false;
                stopHeartbeat();
                if (isServiceAvailable && isServiceHeld && managerProxy) {
                    try {
                        await doReleaseService();
                    } catch (e) {}
                }
                if (nameWatcherId) {
                    Gio.bus_unwatch_name(nameWatcherId);
                    nameWatcherId = 0;
                }
                for (const dev of trackedDevices.values()) {
                    dev.removed = true;
                    if (dev.propHandlerId && dev.proxy) {
                        try { dev.proxy.disconnect(dev.propHandlerId); } catch (e) {}
                    }
                }
                trackedDevices.clear();
                loop.quit();
                break;
            }
            const line = new TextDecoder().decode(bytes).trim();
            if (line.length > 0) {
                await processCommand(line);
            }
        } catch (err) {
            printerr(`[BudsLink bridge] Stdin read error: ${err.message}`);
            loop.quit();
            break;
        }
    }
}

function main() {
    try {
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, null);
    } catch (err) {
        printerr(`[BudsLink bridge] Failed to connect to session bus: ${err.message}`);
        emitError('dbusConnectionFailed', err.message);
    }

    emitEvent({ type: 'bridgeReady', protocol: 1 });

    nameWatcherId = Gio.bus_watch_name(
        Gio.BusType.SESSION,
        BUS_NAME,
        Gio.BusNameWatcherFlags.AUTO_START,
        (connection, name, nameOwner) => {
            onServiceAppeared().catch(err => {
                printerr(`[BudsLink bridge] Error in service appeared handler: ${err.message}`);
            });
        },
        (connection, name) => {
            onServiceVanished();
        }
    );

    startStdinLoop().catch(err => {
        printerr(`[BudsLink bridge] Unhandled stdin loop error: ${err.message}`);
        loop.quit();
    });

    loop.run();
}

main();
