pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.models.quickToggles

Singleton {
    id: root

    property var _instantiatedModels: ({})
    property bool suspended: true

    function ensureLoaded(): void {
        if (!root.suspended)
            return;
        for (const entry of root.allEntries)
            root.getModel(entry.id);
        root.suspended = false;
    }

    function getModel(id: string): var {
        if (root._instantiatedModels[id])
            return root._instantiatedModels[id];
        const comp = root._modelComponentMap[id];
        if (comp) {
            const m = comp.createObject(root);
            root._instantiatedModels[id] = m;
            return m;
        }
        return null;
    }

    function purge(): void {
        // Disable the reactive entries binding before clearing its model map;
        // otherwise evaluating entry.model creates every model again on purge.
        root.suspended = true;
        for (const id in root._instantiatedModels) {
            const m = root._instantiatedModels[id];
            if (m && typeof m.destroy === "function") {
                m.destroy();
            }
        }
        root._instantiatedModels = ({});
    }

    readonly property var _modelComponentMap: ({
        "network": networkComp,
        "bluetooth": bluetoothComp,
        "vpn": vpnComp,
        "tailscale": tailscaleComp,
        "kdeConnect": kdeConnectComp,
        "dnsOverTls": dnsOverTlsComp,
        "idleInhibitor": idleInhibitorComp,
        "easyEffects": easyEffectsComp,
        "nightLight": nightLightComp,
        "darkMode": darkModeComp,
        "cloudflareWarp": cloudflareWarpComp,
        "gameMode": gameModeComp,
        "screenSnip": screenSnipComp,
        "screenRecord": screenRecordComp,
        "colorPicker": colorPickerComp,
        "videoEditor": videoEditorComp,
        "onScreenKeyboard": onScreenKeyboardComp,
        "mic": micComp,
        "audio": audioComp,
        "notifications": notificationComp,
        "autoDnd": autoDndComp,
        "powerProfile": powerProfilesComp,
        "musicRecognition": musicRecognitionComp,
        "discordVoice": discordVoiceComp,
        "phoneCamera": phoneCameraComp,
        "phoneMic": phoneMicComp,
        "phoneMirror": phoneMirrorComp,
        "speedTest": speedTestComp,
        "antiFlashbang": antiFlashbangComp,
        "screenShader": screenShaderComp,
        "soundcoreAnc": soundcoreAncComp,
        "systemSounds": systemSoundsComp,
        "localSend": localSendComp,
        "keyboardBacklight": keyboardBacklightComp,
        "laptopKeyboard": laptopKeyboardComp,
        "modes": modesComp
    })

    readonly property var allEntries: [
        { id: "network", keywords: ["internet", "wifi", "network", "rede"], get model() { return root.getModel("network"); } },
        { id: "bluetooth", keywords: ["bluetooth", "bt", "fone"], get model() { return root.getModel("bluetooth"); } },
        { id: "vpn", keywords: ["vpn", "private", "rede privada"], get model() { return root.getModel("vpn"); } },
        { id: "tailscale", keywords: ["tailscale", "vpn", "mesh"], get model() { return root.getModel("tailscale"); } },
        { id: "kdeConnect", keywords: ["kde connect", "kdeconnect", "phone", "celular", "android", "device"], get model() { return root.getModel("kdeConnect"); } },
        { id: "dnsOverTls", keywords: ["dns", "tls", "secure dns"], get model() { return root.getModel("dnsOverTls"); } },
        { id: "idleInhibitor", keywords: ["idle", "sleep", "suspender"], get model() { return root.getModel("idleInhibitor"); } },
        { id: "easyEffects", keywords: ["effects", "audio", "equalizer"], get model() { return root.getModel("easyEffects"); } },
        { id: "nightLight", keywords: ["night", "light", "luz noturna"], get model() { return root.getModel("nightLight"); } },
        { id: "darkMode", keywords: ["dark", "light", "tema escuro"], get model() { return root.getModel("darkMode"); } },
        { id: "cloudflareWarp", keywords: ["warp", "cloudflare", "vpn"], get model() { return root.getModel("cloudflareWarp"); } },
        { id: "gameMode", keywords: ["game", "gaming", "jogo"], get model() { return root.getModel("gameMode"); } },
        { id: "screenSnip", keywords: ["screenshot", "snip", "captura"], get model() { return root.getModel("screenSnip"); } },
        { id: "screenRecord", keywords: ["record", "gravar", "screen"], get model() { return root.getModel("screenRecord"); } },
        { id: "colorPicker", keywords: ["color", "picker", "cor"], get model() { return root.getModel("colorPicker"); } },
        { id: "videoEditor", keywords: ["video", "editor", "editar"], get model() { return root.getModel("videoEditor"); } },
        { id: "onScreenKeyboard", keywords: ["keyboard", "teclado", "osk"], get model() { return root.getModel("onScreenKeyboard"); } },
        { id: "mic", keywords: ["microphone", "mic", "microfone"], get model() { return root.getModel("mic"); } },
        { id: "audio", keywords: ["audio", "sound", "som"], get model() { return root.getModel("audio"); } },
        { id: "notifications", keywords: ["notifications", "dnd", "notificacoes"], get model() { return root.getModel("notifications"); } },
        { id: "autoDnd", keywords: ["auto dnd", "focus", "nao perturbe"], get model() { return root.getModel("autoDnd"); } },
        { id: "powerProfile", keywords: ["power", "battery", "energia"], get model() { return root.getModel("powerProfile"); } },
        { id: "musicRecognition", keywords: ["music", "recognition", "musica"], get model() { return root.getModel("musicRecognition"); } },
        { id: "discordVoice", keywords: ["discord", "voice", "call", "mute", "deafen"], get model() { return root.getModel("discordVoice"); } },
        { id: "phoneCamera", keywords: ["phone", "camera", "webcam", "droidcam"], get model() { return root.getModel("phoneCamera"); } },
        { id: "phoneMic", keywords: ["phone", "microphone", "mic"], get model() { return root.getModel("phoneMic"); } },
        { id: "phoneMirror", keywords: ["phone", "mirror", "scrcpy", "screen", "espelhamento", "celular", "tela"], get model() { return root.getModel("phoneMirror"); } },
        { id: "speedTest", keywords: ["speed", "test", "internet", "bandwidth"], get model() { return root.getModel("speedTest"); } },
        { id: "antiFlashbang", keywords: ["flash", "brightness", "brilho"], get model() { return root.getModel("antiFlashbang"); } },
        { id: "screenShader", keywords: ["shader", "screen", "tela"], get model() { return root.getModel("screenShader"); } },
        { id: "soundcoreAnc", keywords: ["anc", "noise", "cancelamento"], get model() { return root.getModel("soundcoreAnc"); } },
        { id: "systemSounds", keywords: ["system sounds", "sons", "sistema"], get model() { return root.getModel("systemSounds"); } },
        { id: "localSend", keywords: ["localsend", "send", "enviar"], get model() { return root.getModel("localSend"); } },
        { id: "keyboardBacklight", keywords: ["backlight", "keyboard", "teclado"], get model() { return root.getModel("keyboardBacklight"); } },
        { id: "laptopKeyboard", keywords: ["laptop", "keyboard", "teclado", "builtin", "internal"], get model() { return root.getModel("laptopKeyboard"); } },
        { id: "modes", keywords: ["modes", "routines", "rotinas"], get model() { return root.getModel("modes"); } }
    ]

    readonly property var entries: root.suspended ? [] : root.allEntries.filter(entry => entry.model?.available && !Config.options.search.modules.quickToggles.hidden.includes(entry.id))
    readonly property int revision: root.suspended ? 0 : Object.keys(root._instantiatedModels).reduce((value, id) => {
        const m = root._instantiatedModels[id];
        return value + (m?.toggled ? 1 : 0) + String(m?.statusText ?? "").length;
    }, 0)

    Component { id: networkComp; NetworkToggle {} }
    Component { id: bluetoothComp; BluetoothToggle {} }
    Component { id: vpnComp; VpnToggle {} }
    Component { id: tailscaleComp; TailscaleToggle {} }
    Component { id: kdeConnectComp; KdeConnectToggle {} }
    Component { id: dnsOverTlsComp; DnsOverTlsToggle {} }
    Component { id: idleInhibitorComp; IdleInhibitorToggle {} }
    Component { id: easyEffectsComp; EasyEffectsToggle {} }
    Component { id: nightLightComp; NightLightToggle {} }
    Component { id: darkModeComp; DarkModeToggle {} }
    Component { id: cloudflareWarpComp; CloudflareWarpToggle {} }
    Component { id: gameModeComp; GameModeToggle {} }
    Component { id: screenSnipComp; ScreenSnipToggle {} }
    Component { id: screenRecordComp; ScreenRecordToggle {} }
    Component { id: colorPickerComp; ColorPickerToggle {} }
    Component { id: videoEditorComp; VideoEditorToggle {} }
    Component { id: onScreenKeyboardComp; OnScreenKeyboardToggle {} }
    Component { id: micComp; MicToggle {} }
    Component { id: audioComp; AudioToggle {} }
    Component { id: notificationComp; NotificationToggle {} }
    Component { id: autoDndComp; AutoDndToggle {} }
    Component { id: powerProfilesComp; PowerProfilesToggle {} }
    Component { id: musicRecognitionComp; MusicRecognitionToggle {} }
    Component { id: discordVoiceComp; DiscordVoiceToggle {} }
    Component { id: phoneCameraComp; PhoneCameraToggle {} }
    Component { id: phoneMicComp; PhoneMicToggle {} }
    Component { id: phoneMirrorComp; PhoneMirrorToggle {} }
    Component { id: speedTestComp; SpeedTestToggle {} }
    Component { id: antiFlashbangComp; AntiFlashbangToggle {} }
    Component { id: screenShaderComp; ScreenShaderToggle {} }
    Component { id: soundcoreAncComp; SoundcoreAncToggle {} }
    Component { id: systemSoundsComp; SystemSoundsToggle {} }
    Component { id: localSendComp; LocalSendToggle {} }
    Component { id: keyboardBacklightComp; KeyboardBacklightToggle {} }
    Component { id: laptopKeyboardComp; LaptopKeyboardToggle {} }
    Component { id: modesComp; ModesToggle {} }
}
