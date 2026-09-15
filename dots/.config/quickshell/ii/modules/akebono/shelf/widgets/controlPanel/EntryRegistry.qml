pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.akebono.shelf.widgets.controlPanel.toggles
import qs.modules.lunae.sidebarRight.notifications
import qs.modules.common.panels.quickToggles
import qs.modules.common.notifications

QtObject {
    id: root

    readonly property var entries: [
        { id: "network", title: Translation.tr("Wi-Fi"), toggle: root.networkToggle, detail: root.networkDetail },
        { id: "bluetooth", title: Translation.tr("Bluetooth"), toggle: root.bluetoothToggle, detail: root.bluetoothDetail },
        { id: "nightLight", title: Translation.tr("Eye protection"), toggle: root.nightLightToggle, detail: root.nightLightDetail },
        { id: "gameMode", title: Translation.tr("Game mode"), toggle: root.gameModeToggle, detail: root.gameModeDetail },
        { id: "idleInhibitor", title: "", toggle: root.idleInhibitorToggle, detail: null },
        { id: "easyEffects", title: "", toggle: root.easyEffectsToggle, detail: null },
        { id: "cloudflareWarp", title: "", toggle: root.cloudflareWarpToggle, detail: null },
        { id: "darkMode", title: "", toggle: root.darkModeToggle, detail: null },
        { id: "audio", title: Translation.tr("Audio output"), toggle: root.audioToggle, detail: root.audioDetail },
        { id: "mic", title: Translation.tr("Audio input"), toggle: root.micToggle, detail: root.micDetail },
        { id: "screenSnip", title: "", toggle: root.screenSnipToggle, detail: null },
        { id: "record", title: Translation.tr("Recording"), toggle: root.recordToggle, detail: root.recordDetail },
        { id: "onScreenKeyboard", title: "", toggle: root.onScreenKeyboardToggle, detail: null },
        { id: "musicRecognition", title: "", toggle: root.musicRecognitionToggle, detail: null },
        { id: "notifications", title: Translation.tr("Notifications"), toggle: null, detail: root.notificationsDetail }
    ]

    readonly property var toggleIds: root.entries.filter(entry => entry.toggle).map(entry => entry.id)

    function entryFor(id) {
        return root.entries.find(entry => entry.id === id) ?? null
    }

    function toggleFor(id) {
        return root.entryFor(id)?.toggle ?? null
    }

    function detailFor(id) {
        return root.entryFor(id)?.detail ?? null
    }

    function titleFor(id) {
        return root.entryFor(id)?.title ?? ""
    }

    function hasDetail(id) {
        return root.detailFor(id) !== null
    }

    readonly property Component networkToggle: Component { NetworkToggle {} }
    readonly property Component bluetoothToggle: Component { BluetoothToggle {} }
    readonly property Component nightLightToggle: Component { NightLightToggle {} }
    readonly property Component gameModeToggle: Component { GameModeToggle {} }
    readonly property Component idleInhibitorToggle: Component { IdleInhibitorToggle {} }
    readonly property Component easyEffectsToggle: Component { EasyEffectsToggle {} }
    readonly property Component cloudflareWarpToggle: Component { CloudflareWarpToggle {} }
    readonly property Component darkModeToggle: Component { DarkModeToggle {} }
    readonly property Component audioToggle: Component { AudioToggle {} }
    readonly property Component micToggle: Component { MicToggle {} }
    readonly property Component screenSnipToggle: Component { ScreenSnipToggle {} }
    readonly property Component recordToggle: Component { RecordToggle {} }
    readonly property Component onScreenKeyboardToggle: Component { OnScreenKeyboardToggle {} }
    readonly property Component musicRecognitionToggle: Component { MusicRecognitionToggle {} }

    readonly property Component networkDetail: Component { NetworkDialog {} }
    readonly property Component bluetoothDetail: Component { BluetoothDialog {} }
    readonly property Component nightLightDetail: Component { NightLightDialog {} }
    readonly property Component gameModeDetail: Component { GameModeDialog {} }
    readonly property Component audioDetail: Component { AudioOutputDialog {} }
    readonly property Component micDetail: Component { AudioInputDialog {} }
    readonly property Component recordDetail: Component { RecordDialog {} }
    readonly property Component notificationsDetail: Component { NotificationList { placeholderScale: 0.7 } }
}
