'use strict';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import { ProfileManager } from './lib/devices/profileManager.js';
import { getBluezDeviceProxy } from './lib/bluezDeviceProxy.js';

// Samsung Galaxy Buds imports
import { GalaxyBudsSocket } from './lib/devices/galaxyBuds/galaxyBudsSocket.js';
import { GalaxyBudsModelList, GalaxyBudsAnc } from './lib/devices/galaxyBuds/galaxyBudsConfig.js';
import { checkForSamsungBuds } from './lib/devices/galaxyBuds/galaxyBudsDetector.js';

// Nothing Buds imports
import { NothingBudsSocket } from './lib/devices/nothingBuds/nothingBudsSocket.js';
import { NothingBudsModelList } from './lib/devices/nothingBuds/nothingBudsConfig.js';

// Google Buds imports
import { GoogleBudsSocket } from './lib/devices/googleBuds/googleBudsSocket.js';
import { MaestroUUID, AncState } from './lib/devices/googleBuds/googleBudsConfig.js';

// Sony imports
import { SonySocketV1 } from './lib/devices/sony/sonySocketV1.js';
import { SonySocketV2 } from './lib/devices/sony/sonySocketV2.js';
import { SonyConfiguration, AmbientSoundMode } from './lib/devices/sony/sonyConfig.js';

// AirPods / Beats imports
import { AirpodsSocket } from './lib/devices/airpods/airpodsSocket.js';
import { AirpodsModelList, ANCMode } from './lib/devices/airpods/airpodsConfig.js';

// Promisify DBus and socket methods
Gio._promisify(Gio.DBusProxy, 'new');
Gio._promisify(Gio.DBusProxy, 'new_for_bus');
Gio._promisify(Gio.DBusProxy.prototype, 'call');
Gio._promisify(Gio.DBusConnection.prototype, 'call');
Gio._promisify(Gio.InputStream.prototype, 'read_bytes_async');
Gio._promisify(Gio.OutputStream.prototype, 'write_all_async');

const loop = new GLib.MainLoop(null, false);

// Parse arguments
let mac = null;
let modeStr = null;
let command = null; // 'get' or 'set'

const args = ARGV; // In GJS, ARGV contains the script arguments
for (let i = 0; i < args.length; i++) {
    if (args[i] === '--mac' && i + 1 < args.length) {
        mac = args[i + 1];
        i++;
    } else if (args[i] === '--mode' && i + 1 < args.length) {
        modeStr = args[i + 1];
        i++;
    }
}

if (!mac && args.length >= 2) {
    if (args[0] === 'get') {
        command = 'get';
        mac = args[1];
    } else if (args[0] === 'set' && args.length >= 3) {
        command = 'set';
        mac = args[1];
        modeStr = args[2];
    }
} else if (mac) {
    if (modeStr) {
        command = 'set';
    } else {
        command = 'get';
    }
}

if (!mac) {
    console.error("Usage: gjs core.js --mac <MAC> [--mode <anc|transparency|off>]");
    console.error("Alternative Usage: gjs core.js get <MAC> OR gjs core.js set <MAC> <anc|transparency|off>");
    GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        loop.quit();
        return GLib.SOURCE_REMOVE;
    });
    loop.run();
    imports.system.exit(1);
}

// Normalize MAC to bluez object path format
const macClean = mac.toUpperCase().replace(/:/g, '_');
const devicePath = `/org/bluez/hci0/dev_${macClean}`;

// Map mode string to GalaxyBudsAnc enum (Galaxy legacy/FE support)
let targetAncMode = null;
if (modeStr) {
    const m = modeStr.toLowerCase();
    if (m === 'anc' || m === 'noisecanceling' || m === 'noise_canceling') {
        targetAncMode = GalaxyBudsAnc.NoiseReduction;
    } else if (m === 'transparency' || m === 'ambient') {
        targetAncMode = GalaxyBudsAnc.AmbientSound;
    } else if (m === 'off' || m === 'normal') {
        targetAncMode = GalaxyBudsAnc.Off;
    } else if (m === 'adaptive') {
        targetAncMode = GalaxyBudsAnc.Adaptive;
    } else {
        console.error(`Unknown mode: ${modeStr}. Supported: anc, transparency, off, adaptive`);
        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            loop.quit();
            return GLib.SOURCE_REMOVE;
        });
        loop.run();
        imports.system.exit(1);
    }
}

console.log(`MAC Address: ${mac}`);
console.log(`Device Path: ${devicePath}`);
console.log(`Command: ${command} ${modeStr ? `(${modeStr})` : ''}`);

const profileManager = new ProfileManager((type) => {
    console.error(`Profile registration error: ${type}`);
});

let socket = null;
let currentMode = null;
let isFinished = false;
let deviceType = null; // 'galaxybuds', 'nothingbuds', 'googlebuds', 'sonyV1', 'sonyV2'
let modelDataLoaded = null;

function cleanupAndExit(code = 0) {
    if (socket) {
        try {
            socket.destroy();
        } catch (e) {
            console.error(`Error destroying socket: ${e}`);
        }
    }
    loop.quit();
    imports.system.exit(code);
}

// Helper to resolve Nothing Buds noise control bytes
function getNothingBudsByte(modelData, modeName) {
    const nc = modelData.noiseControl;
    if (!nc) return null;
    
    const m = modeName.toLowerCase();
    if (m === 'off' || m === 'normal') {
        return nc.off?.byte ?? null;
    } else if (m === 'transparency' || m === 'ambient') {
        return nc.transparency?.byte ?? null;
    } else if (m === 'anc' || m === 'noisecanceling' || m === 'noise_canceling') {
        if (nc.noiseCancellation?.levels) {
            return nc.noiseCancellation.levels.high ?? nc.noiseCancellation.levels.mid ?? nc.noiseCancellation.levels.low;
        }
        return nc.noiseCancellation?.byte ?? null;
    }
    return null;
}

const callbacks = {
    // ----------------------------------------------------
    // Samsung Galaxy Buds Callbacks
    // ----------------------------------------------------
    updateNCModes: (mode) => {
        if (deviceType !== 'galaxybuds') return;
        currentMode = mode;
        let modeName = "Unknown";
        if (mode === GalaxyBudsAnc.Off) modeName = "Normal";
        else if (mode === GalaxyBudsAnc.AmbientSound) modeName = "Transparency";
        else if (mode === GalaxyBudsAnc.NoiseReduction) modeName = "NoiseCanceling";
        else if (mode === GalaxyBudsAnc.Adaptive) modeName = "Adaptive";
        
        console.log(`Current ANC Mode: ${modeName} (Value: ${mode})`);
        
        if (command === 'get') {
            print(modeName);
            isFinished = true;
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
                cleanupAndExit(0);
                return GLib.SOURCE_REMOVE;
            });
        } else if (command === 'set' && targetAncMode !== null && !isFinished) {
            console.log(`Setting ANC mode to: ${targetAncMode}`);
            socket.setNCModes(targetAncMode);
            isFinished = true;
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 800, () => {
                console.log("Mode successfully set!");
                cleanupAndExit(0);
                return GLib.SOURCE_REMOVE;
            });
        }
    },

    // ----------------------------------------------------
    // Nothing Buds Callbacks
    // ----------------------------------------------------
    modelIntialized: (m) => {
        modelDataLoaded = m;
        console.log(`Nothing Buds Model Initialized: ${m.name}`);
    },
    updateNoiseControl: (mode) => {
        if (deviceType !== 'nothingbuds') return;
        currentMode = mode;
        
        let modeName = "Unknown";
        if (modelDataLoaded && modelDataLoaded.noiseControl) {
            const nc = modelDataLoaded.noiseControl;
            if (mode === nc.off?.byte) modeName = "Normal";
            else if (mode === nc.transparency?.byte) modeName = "Transparency";
            else if (nc.noiseCancellation?.levels && Object.values(nc.noiseCancellation.levels).includes(mode)) modeName = "NoiseCanceling";
            else if (mode === nc.noiseCancellation?.byte) modeName = "NoiseCanceling";
        }
        
        console.log(`Current ANC Mode: ${modeName} (Value: ${mode})`);
        
        if (command === 'get') {
            print(modeName);
            isFinished = true;
            cleanupAndExit(0);
        } else if (command === 'set' && !isFinished && modelDataLoaded) {
            const targetByte = getNothingBudsByte(modelDataLoaded, modeStr);
            if (targetByte !== null) {
                console.log(`Setting ANC mode to byte: ${targetByte}`);
                socket.setNoiseControl(targetByte);
                isFinished = true;
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 800, () => {
                    console.log("Mode successfully set!");
                    cleanupAndExit(0);
                    return GLib.SOURCE_REMOVE;
                });
            } else {
                console.error(`Could not map mode '${modeStr}' for Nothing Buds model ${modelDataLoaded.name}`);
                cleanupAndExit(1);
            }
        }
    },

    // ----------------------------------------------------
    // Google Buds Callbacks
    // ----------------------------------------------------
    updateAncState: (ancState) => {
        if (deviceType !== 'googlebuds') return;
        currentMode = ancState;
        
        let modeName = "Unknown";
        if (ancState === AncState.OFF) modeName = "Normal";
        else if (ancState === AncState.AWARE) modeName = "Transparency";
        else if (ancState === AncState.ACTIVE) modeName = "NoiseCanceling";
        else if (ancState === AncState.ADAPTIVE) modeName = "Adaptive";
        
        console.log(`Current ANC Mode: ${modeName} (Value: ${ancState})`);
        
        if (command === 'get') {
            print(modeName);
            isFinished = true;
            cleanupAndExit(0);
        } else if (command === 'set' && !isFinished) {
            let targetState = null;
            const m = modeStr.toLowerCase();
            if (m === 'off' || m === 'normal') targetState = AncState.OFF;
            else if (m === 'transparency' || m === 'ambient') targetState = AncState.AWARE;
            else if (m === 'anc' || m === 'noisecanceling' || m === 'noise_canceling') targetState = AncState.ACTIVE;
            else if (m === 'adaptive') targetState = AncState.ADAPTIVE;
            
            if (targetState !== null) {
                console.log(`Setting ANC state to: ${targetState}`);
                socket.setAncState(targetState);
                isFinished = true;
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 800, () => {
                    console.log("Mode successfully set!");
                    cleanupAndExit(0);
                    return GLib.SOURCE_REMOVE;
                });
            } else {
                console.error(`Could not map mode '${modeStr}' for Google Buds`);
                cleanupAndExit(1);
            }
        }
    },

    // ----------------------------------------------------
    // Sony V1/V2 Callbacks
    // ----------------------------------------------------
    updateAmbientSoundControl: (mode, focusOnVoice, level, naMode, naSensitivity) => {
        if (deviceType !== 'sonyV1' && deviceType !== 'sonyV2') return;
        currentMode = mode;
        
        let modeName = "Unknown";
        if (mode === AmbientSoundMode.ANC_OFF) modeName = "Normal";
        else if (mode === AmbientSoundMode.AMBIENT) modeName = "Transparency";
        else if (mode === AmbientSoundMode.ANC_ON) modeName = "NoiseCanceling";
        
        console.log(`Current ANC Mode: ${modeName} (Value: ${mode})`);
        
        if (command === 'get') {
            print(modeName);
            isFinished = true;
            cleanupAndExit(0);
        } else if (command === 'set' && !isFinished) {
            let targetModeVal = null;
            const m = modeStr.toLowerCase();
            if (m === 'off' || m === 'normal') targetModeVal = AmbientSoundMode.ANC_OFF;
            else if (m === 'transparency' || m === 'ambient') targetModeVal = AmbientSoundMode.AMBIENT;
            else if (m === 'anc' || m === 'noisecanceling' || m === 'noise_canceling') targetModeVal = AmbientSoundMode.ANC_ON;
            
            if (targetModeVal !== null) {
                console.log(`Setting ANC mode to: ${targetModeVal}`);
                socket.setAmbientSoundControl(targetModeVal, false, 10, false, 0);
                isFinished = true;
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 800, () => {
                    console.log("Mode successfully set!");
                    cleanupAndExit(0);
                    return GLib.SOURCE_REMOVE;
                });
            } else {
                console.error(`Could not map mode '${modeStr}' for Sony`);
                cleanupAndExit(1);
            }
        }
    },

    // ----------------------------------------------------
    // AirPods / Beats Callbacks
    // ----------------------------------------------------
    updateAncMode: (mode) => {
        if (deviceType !== 'airpods') return;
        currentMode = mode;
        
        let modeName = "Unknown";
        if (mode === ANCMode.ANC_OFF) modeName = "Normal";
        else if (mode === ANCMode.TRANSPARENCY) modeName = "Transparency";
        else if (mode === ANCMode.ANC_ON) modeName = "NoiseCanceling";
        else if (mode === ANCMode.ADAPTIVE) modeName = "Adaptive";
        
        console.log(`Current ANC Mode: ${modeName} (Value: ${mode})`);
        
        if (command === 'get') {
            print(modeName);
            isFinished = true;
            cleanupAndExit(0);
        } else if (command === 'set' && !isFinished) {
            let targetModeVal = null;
            const m = modeStr.toLowerCase();
            if (m === 'off' || m === 'normal') targetModeVal = ANCMode.ANC_OFF;
            else if (m === 'transparency' || m === 'ambient') targetModeVal = ANCMode.TRANSPARENCY;
            else if (m === 'anc' || m === 'noisecanceling' || m === 'noise_canceling') targetModeVal = ANCMode.ANC_ON;
            else if (m === 'adaptive') targetModeVal = ANCMode.ADAPTIVE;
            
            if (targetModeVal !== null) {
                console.log(`Setting ANC mode to: ${targetModeVal}`);
                socket.setAncMode(targetModeVal);
                isFinished = true;
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 800, () => {
                    console.log("Mode successfully set!");
                    cleanupAndExit(0);
                    return GLib.SOURCE_REMOVE;
                });
            } else {
                console.error(`Could not map mode '${modeStr}' for AirPods`);
                cleanupAndExit(1);
            }
        }
    },

    // ----------------------------------------------------
    // Shared / Stub Callbacks
    // ----------------------------------------------------
    updateFirmwareInfo: (fw) => { console.log(`Firmware Version: ${fw}`); },
    updateFirmwareVersion: (fw) => { console.log(`Firmware Version: ${fw}`); },
    updateBatteryProps: (props) => {
        console.log(`Battery Status: Left ${props.battery1Level ?? 0}%, Right ${props.battery2Level ?? 0}%, Case ${props.battery3Level ?? 0}%`);
    },
    updateInEarState: (left, right) => { console.log(`In-ear State: Left: ${left}, Right: ${right}`); },
    updateInEarStatus: (left, right) => { console.log(`In-ear Status: Left: ${left}, Right: ${right}`); },
    updateInEar: (enable) => { console.log(`In-ear Detection: ${enable}`); },
    updateAdaptiveLevel: (level) => { console.log(`Adaptive level: ${level}`); },
    updateAwarenessMode: (mode) => { console.log(`Awareness Mode: ${mode}`); },
    updateAwarenessData: (attenuated) => { console.log(`Awareness attenuated: ${attenuated}`); },
    updateCapabilities: (cap1, cap2) => {},
    updateExtendedStatusStarted: () => {},
    updateExtendedStatusEnded: () => {
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
            if (!isFinished) {
                console.log("Extended status reading complete.");
                cleanupAndExit(0);
            }
            return GLib.SOURCE_REMOVE;
        });
    }
};

// Global safety timeout to prevent hanging
GLib.timeout_add(GLib.PRIORITY_DEFAULT, 10000, () => {
    console.error("Timeout: Device is not responding or not connected.");
    cleanupAndExit(1);
    return GLib.SOURCE_REMOVE;
});

// Asynchronous detection & socket startup
async function main() {
    console.log("Connecting to Bluez device...");
    const bluezDeviceProxy = getBluezDeviceProxy(devicePath);
    
    let uuids = [];
    let name = '';
    let modalias = '';
    
    try {
        uuids = bluezDeviceProxy.UUIDs || [];
        name = bluezDeviceProxy.Name || '';
        modalias = bluezDeviceProxy.Modalias || '';
    } catch (e) {
        console.warn(`Cached properties read warning: ${e}.`);
    }
    
    // If attributes not resolved yet, yield back to main loop briefly
    if (uuids.length === 0) {
        await new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
            resolve();
            return GLib.SOURCE_REMOVE;
        }));
        uuids = bluezDeviceProxy.UUIDs || [];
        name = bluezDeviceProxy.Name || '';
        modalias = bluezDeviceProxy.Modalias || '';
    }

    console.log(`Device Name: "${name}"`);
    console.log(`Device UUIDs: ${uuids.join(', ')}`);
    console.log(`Device Modalias: ${modalias}`);

    let targetProfile = null;
    let modelData = null;
    let SocketClass = null;

    // Match device variant
    if (uuids.includes('aeac4a03-dff5-498f-843a-34487cf133eb')) {
        deviceType = 'nothingbuds';
        targetProfile = { type: 'nothingBuds', uuid: 'aeac4a03-dff5-498f-843a-34487cf133eb' };
        SocketClass = NothingBudsSocket;
        console.log("Device matched: Nothing Buds!");
    } else if (uuids.includes('74ec2172-0bad-4d01-8f77-997b2be0722a')) {
        deviceType = 'airpods';
        targetProfile = { type: 'airpods', uuid: '74ec2172-0bad-4d01-8f77-997b2be0722a' };
        SocketClass = AirpodsSocket;
        const regex = /v004Cp([0-9A-Fa-f]{4})d/;
        const match = modalias.match(regex);
        const modelKey = match ? match[1].toUpperCase() : null;
        modelData = AirpodsModelList.find(m => m.key === modelKey) || 
                    AirpodsModelList.find(m => m.name.includes("Pro")) || 
                    AirpodsModelList[0];
        console.log(`Device matched: Apple AirPods/Beats (${modelData ? modelData.name : 'AirPods Pro'})!`);
    } else if (uuids.includes(MaestroUUID)) {
        deviceType = 'googlebuds';
        targetProfile = { type: 'googleBuds', uuid: MaestroUUID };
        SocketClass = GoogleBudsSocket;
        console.log("Device matched: Google Buds!");
    } else if (uuids.includes('956c7b26-d49a-4ba8-b03f-b17d393cb6e2')) {
        deviceType = 'sonyV2';
        targetProfile = { type: 'sonyV2', uuid: '956c7b26-d49a-4ba8-b03f-b17d393cb6e2' };
        SocketClass = SonySocketV2;
        modelData = SonyConfiguration.find(model =>
            model.modaliasPrefix && modalias.includes(model.modaliasPrefix) ||
            model.pattern && model.pattern.test(name)
        ) || SonyConfiguration[0];
        console.log(`Device matched: Sony Protocol V2 (${modelData ? modelData.name : 'Unknown'})!`);
    } else if (uuids.includes('96cc203e-5068-46ad-b32d-e316f5e069ba')) {
        deviceType = 'sonyV1';
        targetProfile = { type: 'sonyV1', uuid: '96cc203e-5068-46ad-b32d-e316f5e069ba' };
        SocketClass = SonySocketV1;
        modelData = SonyConfiguration.find(model =>
            model.modaliasPrefix && modalias.includes(model.modaliasPrefix) ||
            model.pattern && model.pattern.test(name)
        ) || SonyConfiguration[0];
        console.log(`Device matched: Sony Protocol V1 (${modelData ? modelData.name : 'Unknown'})!`);
    } else {
        // Default / Fallback to Galaxy Buds
        const samsungModelId = checkForSamsungBuds(uuids, name);
        deviceType = 'galaxybuds';
        targetProfile = { type: 'galaxyBuds', uuid: '00001101-0000-1000-8000-00805f9b34fb' };
        SocketClass = GalaxyBudsSocket;
        modelData = GalaxyBudsModelList.find(m => m.modelId === (samsungModelId || 7));
        console.log(`Device matched: Samsung Galaxy Buds (${modelData ? modelData.name : 'FE'})!`);
    }

    try {
        if (deviceType === 'galaxybuds' || deviceType === 'sonyV1' || deviceType === 'sonyV2' || deviceType === 'airpods') {
            socket = new SocketClass(
                devicePath,
                profileManager,
                targetProfile,
                modelData,
                callbacks
            );
        } else {
            // Nothing / Google Buds constructors do not accept modelData
            socket = new SocketClass(
                devicePath,
                profileManager,
                targetProfile,
                callbacks
            );
        }
    } catch (e) {
        console.error(`Failed to create socket handler: ${e}`);
        cleanupAndExit(1);
    }
}

main();
loop.run();
