pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.dynamicIsland.core

/**
 * Every source the island has, in one place.
 *
 * The controller stays generic: it asks this object for the source of an activity id and
 * never knows what a clipboard or a workspace is. Adding an activity is a descriptor in
 * IslandRegistry, a source here, and a presentation - no edits to the arbitration.
 *
 * Core / explicit-surface sources stay eager; optional activity sources load via URL
 * only while enabled in `IslandPolicy.widgetEnabled(...)`, avoiding compiling unused
 * sources and waking their `qs.services` singletons at boot.
 */
Item {
    id: sources

    visible: false

    // Helper for optional sources loaded by URL only when enabled in IslandPolicy.
    component OptionalSourceLoader: Loader {
        required property string policyId
        required property string fileName
        active: IslandPolicy.widgetEnabled(policyId)
        source: active ? Qt.resolvedUrl(fileName) : ""
    }

    // ── Core / explicit surfaces (always active) ──────────────────────────────
    readonly property WindowSwitcherSource windowSwitcher: WindowSwitcherSource {}
    readonly property AskpassSource askpass: AskpassSource {}
    readonly property SearchSource search: SearchSource {}
    readonly property WallpaperSource wallpaper: WallpaperSource {}
    readonly property SessionSource session: SessionSource {}
    readonly property ColorPickerSource colorPicker: ColorPickerSource {}
    readonly property DisplayModesSource displayModes: DisplayModesSource {}
    readonly property NotificationSource notification: NotificationSource {}
    readonly property OsdSource osd: OsdSource {}
    readonly property LocalSendSource localSend: LocalSendSource {}
    readonly property WifiSource wifi: WifiSource {}
    readonly property TeleprompterSource teleprompter: TeleprompterSource {}

    // ── Optional activity sources (URL-loaded only while enabled) ─────────────
    OptionalSourceLoader { id: phoneCallLoader; policyId: "phoneCall"; fileName: "PhoneCallSource.qml" }
    OptionalSourceLoader { id: fingerprintLoader; policyId: "fingerprint"; fileName: "FingerprintSource.qml" }
    OptionalSourceLoader { id: alarmLoader; policyId: "alarm"; fileName: "AlarmSource.qml" }
    OptionalSourceLoader { id: reminderLoader; policyId: "reminder"; fileName: "ReminderSource.qml" }
    OptionalSourceLoader { id: reminderSoonLoader; policyId: "reminderSoon"; fileName: "ReminderSoonSource.qml" }
    OptionalSourceLoader { id: songRecLoader; policyId: "songRec"; fileName: "SongRecSource.qml" }
    OptionalSourceLoader { id: sportsLoader; policyId: "sports"; fileName: "SportsSource.qml" }
    OptionalSourceLoader { id: phoneLiveLoader; policyId: "phoneLive"; fileName: "PhoneLiveSource.qml" }
    OptionalSourceLoader { id: vpnLoader; policyId: "vpn"; fileName: "VpnSource.qml" }
    OptionalSourceLoader { id: aiLoader; policyId: "ai"; fileName: "AiSource.qml" }
    OptionalSourceLoader { id: mediaLoader; policyId: "media"; fileName: "MediaSource.qml" }
    OptionalSourceLoader { id: timerLoader; policyId: "timer"; fileName: "TimerSource.qml" }
    OptionalSourceLoader { id: recordingLoader; policyId: "recording"; fileName: "RecordingSource.qml" }
    OptionalSourceLoader { id: dictationLoader; policyId: "dictation"; fileName: "DictationSource.qml" }
    OptionalSourceLoader { id: shelfLoader; policyId: "shelf"; fileName: "ShelfSource.qml" }
    OptionalSourceLoader { id: progressLoader; policyId: "progress"; fileName: "ProgressSource.qml" }
    OptionalSourceLoader { id: earbudsLoader; policyId: "earbuds"; fileName: "EarbudsSource.qml" }
    OptionalSourceLoader { id: btPhoneLoader; policyId: "bluetooth"; fileName: "BluetoothPhoneSource.qml" }
    OptionalSourceLoader { id: weatherLoader; policyId: "weather"; fileName: "WeatherSource.qml" }
    OptionalSourceLoader { id: batteryGlanceLoader; policyId: "batteryGlance"; fileName: "BatteryGlanceSource.qml" }
    OptionalSourceLoader { id: dateGlanceLoader; policyId: "date"; fileName: "DateGlanceSource.qml" }
    OptionalSourceLoader { id: privacyLoader; policyId: "privacy"; fileName: "PrivacySource.qml" }
    OptionalSourceLoader { id: discordVoiceLoader; policyId: "discordVoice"; fileName: "DiscordVoiceSource.qml" }
    OptionalSourceLoader { id: phoneMirrorLoader; policyId: "phoneMirror"; fileName: "PhoneMirrorSource.qml" }
    OptionalSourceLoader { id: phoneMirrorErrorLoader; policyId: "phoneMirrorError"; fileName: "PhoneMirrorErrorSource.qml" }
    OptionalSourceLoader { id: phoneKeyboardLoader; policyId: "phoneKeyboard"; fileName: "PhoneKeyboardSource.qml" }
    OptionalSourceLoader { id: phoneLinkLoader; policyId: "phoneLink"; fileName: "PhoneLinkSource.qml" }
    OptionalSourceLoader { id: workspacesLoader; policyId: "workspaces"; fileName: "WorkspaceSource.qml" }
    OptionalSourceLoader { id: clipboardLoader; policyId: "clipboard"; fileName: "ClipboardSource.qml" }
    OptionalSourceLoader { id: batteryLoader; policyId: "battery"; fileName: "BatterySource.qml" }
    OptionalSourceLoader { id: bluetoothLoader; policyId: "bluetooth"; fileName: "BluetoothSource.qml" }
    OptionalSourceLoader { id: keyboardLoader; policyId: "keyboard"; fileName: "KeyboardLayoutSource.qml" }
    OptionalSourceLoader { id: modeLoader; policyId: "mode"; fileName: "ModeSource.qml" }
    OptionalSourceLoader { id: updateLoader; policyId: "update"; fileName: "UpdateSource.qml" }
    OptionalSourceLoader { id: systemTrayLoader; policyId: "systemTray"; fileName: "SystemTraySource.qml" }
    OptionalSourceLoader { id: easyEffectsLoader; policyId: "easyEffects"; fileName: "EasyEffectsSource.qml" }
    OptionalSourceLoader { id: healthLoader; policyId: "health"; fileName: "HealthSource.qml" }

    readonly property var phoneCall: phoneCallLoader.item
    readonly property var fingerprint: fingerprintLoader.item
    readonly property var alarm: alarmLoader.item
    readonly property var reminder: reminderLoader.item
    readonly property var reminderSoon: reminderSoonLoader.item
    readonly property var songRec: songRecLoader.item
    readonly property var sports: sportsLoader.item
    readonly property var phoneLive: phoneLiveLoader.item
    readonly property var vpn: vpnLoader.item
    readonly property var ai: aiLoader.item
    readonly property var media: mediaLoader.item
    readonly property var timer: timerLoader.item
    readonly property var recording: recordingLoader.item
    readonly property var dictation: dictationLoader.item
    readonly property var shelf: shelfLoader.item
    readonly property var progress: progressLoader.item
    readonly property var earbuds: earbudsLoader.item
    readonly property var btPhone: btPhoneLoader.item
    readonly property var weather: weatherLoader.item
    readonly property var batteryGlance: batteryGlanceLoader.item
    readonly property var dateGlance: dateGlanceLoader.item
    readonly property var privacy: privacyLoader.item
    readonly property var discordVoice: discordVoiceLoader.item
    readonly property var phoneMirror: phoneMirrorLoader.item
    readonly property var phoneMirrorError: phoneMirrorErrorLoader.item
    readonly property var phoneKeyboard: phoneKeyboardLoader.item
    readonly property var phoneLink: phoneLinkLoader.item
    readonly property var workspaces: workspacesLoader.item
    readonly property var clipboard: clipboardLoader.item
    readonly property var battery: batteryLoader.item
    readonly property var bluetooth: bluetoothLoader.item
    readonly property var keyboard: keyboardLoader.item
    readonly property var mode: modeLoader.item
    readonly property var update: updateLoader.item
    readonly property var systemTray: systemTrayLoader.item
    readonly property var easyEffects: easyEffectsLoader.item
    readonly property var health: healthLoader.item

    readonly property var all: [
        // Interrupts first, only because it reads in priority order here; the actual
        // arbitration is IslandRegistry's tier, not this list.
        windowSwitcher, askpass, search, wallpaper, session, colorPicker, displayModes, notification, osd, phoneCall, alarm, reminder, fingerprint,
        // Live and ambient.
        ai, media, timer, recording, dictation, localSend, shelf, progress, songRec, teleprompter,
        // Side glances.
        earbuds, btPhone, weather, batteryGlance, dateGlance, reminderSoon, privacy, discordVoice, phoneMirror, phoneLink, sports, phoneLive,
        // Announcements.
        health, phoneMirrorError, phoneKeyboard, workspaces, clipboard, battery, wifi, bluetooth, keyboard, mode, update, vpn, systemTray,
        easyEffects
    ].filter(s => s !== null)

    function sourceFor(activityId) {
        const list = sources.all;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].activityId === activityId)
                return list[i];
        }
        return null;
    }

    /** Tell every source whether the pointer is on its activity, to hold TTLs open. */
    function setHovered(activityId, hovered) {
        const source = sources.sourceFor(activityId);
        if (source)
            source.hovered = hovered;
    }
}
