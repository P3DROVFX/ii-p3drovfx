pragma ComponentBehavior: Bound

import QtQuick

/**
 * Every source the island has, in one place.
 *
 * The controller stays generic: it asks this object for the source of an activity id and
 * never knows what a clipboard or a workspace is. Adding an activity is a descriptor in
 * IslandRegistry, a source here, and a presentation - no edits to the arbitration.
 *
 * The clock has no source: there is no event that makes a clock happen, it is simply
 * what the centre shows when nothing else needs it. The controller synthesises it.
 */
Item {
    id: sources

    visible: false

    readonly property list<QtObject> all: [
        // Interrupts first, only because it reads in priority order here; the actual
        // arbitration is IslandRegistry's tier, not this list.
        search, wallpaper, session, colorPicker, notification, osd,
        // Live and ambient.
        ai, media, timer, recording, dictation, localSend, progress,
        // Side glances.
        earbuds, weather,
        // Announcements.
        workspaces, clipboard, battery, wifi, bluetooth, keyboard, mode, update
    ]

    readonly property SearchSource search: SearchSource {}
    readonly property WallpaperSource wallpaper: WallpaperSource {}
    readonly property SessionSource session: SessionSource {}
    readonly property ColorPickerSource colorPicker: ColorPickerSource {}
    readonly property NotificationSource notification: NotificationSource {}
    readonly property OsdSource osd: OsdSource {}
    readonly property AiSource ai: AiSource {}
    readonly property MediaSource media: MediaSource {}
    readonly property TimerSource timer: TimerSource {}
    readonly property RecordingSource recording: RecordingSource {}
    readonly property DictationSource dictation: DictationSource {}
    readonly property LocalSendSource localSend: LocalSendSource {}
    readonly property ProgressSource progress: ProgressSource {}
    readonly property EarbudsSource earbuds: EarbudsSource {}
    readonly property WeatherSource weather: WeatherSource {}
    readonly property WorkspaceSource workspaces: WorkspaceSource {}
    readonly property ClipboardSource clipboard: ClipboardSource {}
    readonly property BatterySource battery: BatterySource {}
    readonly property WifiSource wifi: WifiSource {}
    readonly property BluetoothSource bluetooth: BluetoothSource {}
    readonly property KeyboardLayoutSource keyboard: KeyboardLayoutSource {}
    readonly property ModeSource mode: ModeSource {}
    readonly property UpdateSource update: UpdateSource {}

    function sourceFor(activityId) {
        for (let i = 0; i < sources.all.length; i++) {
            if (sources.all[i].activityId === activityId)
                return sources.all[i];
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
