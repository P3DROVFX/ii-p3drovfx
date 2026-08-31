pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.models.quickToggles

Singleton {
    id: root

    readonly property var allEntries: [
        { id: "network", model: networkToggle, keywords: ["internet", "wifi", "network", "rede"] },
        { id: "bluetooth", model: bluetoothToggle, keywords: ["bluetooth", "bt", "fone"] },
        { id: "vpn", model: vpnToggle, keywords: ["vpn", "private", "rede privada"] },
        { id: "tailscale", model: tailscaleToggle, keywords: ["tailscale", "vpn", "mesh"] },
        { id: "dnsOverTls", model: dnsOverTlsToggle, keywords: ["dns", "tls", "secure dns"] },
        { id: "idleInhibitor", model: idleInhibitorToggle, keywords: ["idle", "sleep", "suspender"] },
        { id: "easyEffects", model: easyEffectsToggle, keywords: ["effects", "audio", "equalizer"] },
        { id: "nightLight", model: nightLightToggle, keywords: ["night", "light", "luz noturna"] },
        { id: "darkMode", model: darkModeToggle, keywords: ["dark", "light", "tema escuro"] },
        { id: "cloudflareWarp", model: cloudflareWarpToggle, keywords: ["warp", "cloudflare", "vpn"] },
        { id: "gameMode", model: gameModeToggle, keywords: ["game", "gaming", "jogo"] },
        { id: "screenSnip", model: screenSnipToggle, keywords: ["screenshot", "snip", "captura"] },
        { id: "screenRecord", model: screenRecordToggle, keywords: ["record", "gravar", "screen"] },
        { id: "colorPicker", model: colorPickerToggle, keywords: ["color", "picker", "cor"] },
        { id: "videoEditor", model: videoEditorToggle, keywords: ["video", "editor", "editar"] },
        { id: "onScreenKeyboard", model: onScreenKeyboardToggle, keywords: ["keyboard", "teclado", "osk"] },
        { id: "mic", model: micToggle, keywords: ["microphone", "mic", "microfone"] },
        { id: "audio", model: audioToggle, keywords: ["audio", "sound", "som"] },
        { id: "notifications", model: notificationToggle, keywords: ["notifications", "dnd", "notificacoes"] },
        { id: "autoDnd", model: autoDndToggle, keywords: ["auto dnd", "focus", "nao perturbe"] },
        { id: "powerProfile", model: powerProfilesToggle, keywords: ["power", "battery", "energia"] },
        { id: "musicRecognition", model: musicRecognitionToggle, keywords: ["music", "recognition", "musica"] },
        { id: "antiFlashbang", model: antiFlashbangToggle, keywords: ["flash", "brightness", "brilho"] },
        { id: "screenShader", model: screenShaderToggle, keywords: ["shader", "screen", "tela"] },
        { id: "soundcoreAnc", model: soundcoreAncToggle, keywords: ["anc", "noise", "cancelamento"] },
        { id: "systemSounds", model: systemSoundsToggle, keywords: ["system sounds", "sons", "sistema"] },
        { id: "localSend", model: localSendToggle, keywords: ["localsend", "send", "enviar"] },
        { id: "keyboardBacklight", model: keyboardBacklightToggle, keywords: ["backlight", "keyboard", "teclado"] },
        { id: "modes", model: modesToggle, keywords: ["modes", "routines", "rotinas"] }
    ]

    readonly property var entries: root.allEntries.filter(entry => entry.model.available && !Config.options.search.modules.quickToggles.hidden.includes(entry.id))
    readonly property int revision: root.allEntries.reduce((value, entry) => value + (entry.model.toggled ? 1 : 0) + String(entry.model.statusText).length, 0)

    NetworkToggle { id: networkToggle }
    BluetoothToggle { id: bluetoothToggle }
    VpnToggle { id: vpnToggle }
    TailscaleToggle { id: tailscaleToggle }
    DnsOverTlsToggle { id: dnsOverTlsToggle }
    IdleInhibitorToggle { id: idleInhibitorToggle }
    EasyEffectsToggle { id: easyEffectsToggle }
    NightLightToggle { id: nightLightToggle }
    DarkModeToggle { id: darkModeToggle }
    CloudflareWarpToggle { id: cloudflareWarpToggle }
    GameModeToggle { id: gameModeToggle }
    ScreenSnipToggle { id: screenSnipToggle }
    ScreenRecordToggle { id: screenRecordToggle }
    ColorPickerToggle { id: colorPickerToggle }
    VideoEditorToggle { id: videoEditorToggle }
    OnScreenKeyboardToggle { id: onScreenKeyboardToggle }
    MicToggle { id: micToggle }
    AudioToggle { id: audioToggle }
    NotificationToggle { id: notificationToggle }
    AutoDndToggle { id: autoDndToggle }
    PowerProfilesToggle { id: powerProfilesToggle }
    MusicRecognitionToggle { id: musicRecognitionToggle }
    AntiFlashbangToggle { id: antiFlashbangToggle }
    ScreenShaderToggle { id: screenShaderToggle }
    SoundcoreAncToggle { id: soundcoreAncToggle }
    SystemSoundsToggle { id: systemSoundsToggle }
    LocalSendToggle { id: localSendToggle }
    KeyboardBacklightToggle { id: keyboardBacklightToggle }
    ModesToggle { id: modesToggle }
}
