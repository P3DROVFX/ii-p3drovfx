pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * The single description of every activity the island can show.
 *
 * Geometry, priority, which side an activity drifts to and which files draw it all live
 * here. The old panel answered those questions from a 200-line `if (type === …)` ladder
 * plus a second ladder for visibility and a third for ordering, so adding an activity
 * meant editing four places and the settings page by hand. Here a descriptor is data:
 * the controller arbitrates from it, the styles size themselves from it, and the
 * settings page is generated from it.
 *
 * `-1` on a size means "use the island's own metric" (IslandMotion.pillHeight / orbSize),
 * so activities follow the user's sizing instead of pinning their own.
 */
Singleton {
    id: root

    readonly property var descriptors: [
        {
            id: "clock",
            tier: "idle",
            icon: "schedule",
            label: "Clock",
            preferredSide: "right",
            canDetach: false,          // the resting face belongs in the centre
            settleMs: 0,
            compact: { width: 168, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // the centre expands into the dashboard
            content: { compact: "activities/clock/ClockCompact.qml" }
        },
        {
            id: "media",
            legacyContent: "FloatingNotchMedia.qml",
            tier: "ambient",
            icon: "music_note",
            label: "Media",
            preferredSide: "right",
            canDetach: true,
            settleMs: 2500,
            compact: { width: 280, height: 52 },
            orb: { size: -1 },
            expanded: { width: 420, height: 196 },
            content: {
                compact: "activities/media/MediaCompact.qml",
                orb: "activities/media/MediaOrb.qml",
                expanded: "activities/media/MediaExpanded.qml"
            }
        },
        {
            id: "workspaces",
            legacyContent: "FloatingNotchWorkspaces.qml",
            tier: "transient",
            icon: "grid_view",
            label: "Workspaces",
            preferredSide: "left",
            canDetach: true,
            settleMs: 700,
            ttlMs: 2000,
            compact: { width: 132, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: {
                compact: "activities/workspaces/WorkspacesCompact.qml",
                orb: "activities/workspaces/WorkspacesCompact.qml",
                expanded: "activities/workspaces/WorkspacesExpanded.qml"
            }
        },
        {
            id: "notification",
            legacyContent: "FloatingNotchNotification.qml",
            tier: "interrupt",
            icon: "notifications",
            label: "Notifications",
            preferredSide: "right",
            canDetach: true,
            settleMs: 4000,
            ttlMs: 4500,
            compact: { width: 380, height: 60 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: {
                compact: "activities/notification/NotificationCompact.qml",
                orb: "activities/notification/NotificationOrb.qml",
                expanded: "activities/notification/NotificationExpanded.qml"
            }
        },
        {
            id: "search",
            tier: "interrupt",
            icon: "search",
            label: "Search",
            preferredSide: "right",
            canDetach: false,          // the thing being typed into belongs in the centre
            settleMs: 0,
            // Sized by the search widget itself: the surface overrides these, because a
            // result list's height is whatever the results need.
            compact: { width: 0, height: 0 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            id: "wallpaper",
            tier: "interrupt",
            icon: "wallpaper",
            label: "Wallpapers",
            preferredSide: "right",
            canDetach: false,          // a picker being browsed belongs in the centre
            settleMs: 0,
            // Sized by the browser itself, like search: one row of wallpapers, the path
            // above it and the toolbars below come to whatever the island is given.
            compact: { width: 0, height: 0 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            id: "session",
            tier: "interrupt",
            icon: "power_settings_new",
            label: "Session",
            preferredSide: "right",
            canDetach: false,          // a menu being chosen from belongs in the centre
            settleMs: 0,
            // Sized by the menu itself: four by two buttons and a header.
            compact: { width: 0, height: 0 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            id: "colorPicker",
            tier: "interrupt",
            icon: "colorize",
            label: "Colour picker",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            // Sized by the picker card itself, which is the popup's own layout.
            compact: { width: 0, height: 0 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            id: "osd",
            tier: "interrupt",
            icon: "volume_up",
            label: "Volume & brightness",
            preferredSide: "right",
            canDetach: false,          // a slider belongs where the eye already is
            settleMs: 0,
            ttlMs: 1500,
            // The indicator's own size (OsdConnectValueIndicator.osdWidth/osdHeight).
            // The island needs it before the indicator is loaded - the face swap lags
            // the activity by the morph - so it is declared here and refined from the
            // loaded item; see NotchContent.osdTargetWidth.
            compact: { width: 380, height: 72 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: { compact: "activities/osd/OsdCompact.qml" }
        },
        {
            id: "ai",
            legacyContent: "FloatingNotchAiStatus.qml",
            tier: "live",
            icon: "neurology",
            label: "AI agents",
            preferredSide: "right",
            canDetach: true,
            settleMs: 1800,
            compact: { width: 230, height: -1 },
            orb: { size: -1 },
            expanded: { width: 360, height: 200 },
            content: {
                compact: "activities/ai/AiCompact.qml",
                orb: "activities/ai/AiOrb.qml",
                expanded: "activities/ai/AiExpanded.qml"
            }
        },
        {
            id: "clipboard",
            legacyContent: "FloatingNotchClipboard.qml",
            tier: "transient",
            icon: "content_paste",
            label: "Clipboard",
            preferredSide: "left",
            canDetach: false,          // it says one thing and leaves
            settleMs: 0,
            ttlMs: 2500,
            compact: { width: 190, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: {
                compact: "activities/clipboard/ClipboardCompact.qml",
                expanded: "activities/clipboard/ClipboardExpanded.qml"
            }
        },
        {
            id: "timer",
            legacyContent: "FloatingNotchTimer.qml",
            tier: "live",
            icon: "timer",
            label: "Timer & stopwatch",
            preferredSide: "left",
            canDetach: true,
            settleMs: 1500,
            compact: { width: 160, height: -1 },
            orb: { size: -1 },
            expanded: { width: 260, height: 160 },
            content: {
                compact: "activities/timer/TimerCompact.qml",
                orb: "activities/timer/TimerOrb.qml",
                expanded: "activities/timer/TimerExpanded.qml"
            }
        },
        {
            id: "recording",
            legacyContent: "FloatingNotchRecording.qml",
            tier: "live",
            icon: "fiber_manual_record",
            label: "Screen recording",
            preferredSide: "left",
            canDetach: true,
            settleMs: 1500,
            compact: { width: 140, height: -1 },
            orb: { size: -1 },
            expanded: { width: 260, height: 150 },
            content: {
                compact: "activities/recording/RecordingCompact.qml",
                orb: "activities/recording/RecordingOrb.qml",
                expanded: "activities/recording/RecordingExpanded.qml"
            }
        },
        {
            id: "battery",
            legacyContent: "FloatingNotchBattery.qml",
            tier: "transient",
            icon: "battery_charging_full",
            label: "Battery",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            ttlMs: 5000,
            compact: { width: 340, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: {
                compact: "activities/battery/BatteryCompact.qml",
                expanded: "activities/battery/BatteryExpanded.qml"
            }
        },
        {
            id: "earbuds",
            tier: "live",
            icon: "headphones",
            label: "Earbuds battery",
            preferredSide: "right",
            canDetach: false,          // a side glance; it never leaves the resting face
            settleMs: 0,
            compact: { width: 120, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face
            content: { compact: "activities/earbuds/EarbudsCompact.qml" }
        },
        {
            id: "weather",
            tier: "live",
            icon: "partly_cloudy_day",
            label: "Weather",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            compact: { width: 130, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: { compact: "activities/weather/WeatherCompact.qml" }
        },
        {
            id: "batteryGlance",
            tier: "live",
            icon: "battery_android_full",
            label: "Battery level",
            preferredSide: "right",
            canDetach: false,          // a side glance; it never leaves the resting face
            settleMs: 0,
            compact: { width: 90, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face
            content: { compact: "activities/battery/BatteryGlanceCompact.qml" }
        },
        {
            // Ringing takes the centre ahead of every other interrupt; a call in progress
            // sits beside the clock; a missed call is said once. See PhoneCallSource.
            id: "phoneCall",
            legacyContent: "FloatingNotchPhoneCall.qml",
            tier: "interrupt",
            priority: 0,
            interactive: true,         // its buttons are the point: hovering must not open the dashboard
            icon: "call",
            label: "Phone calls",
            preferredSide: "left",
            canDetach: false,
            settleMs: 0,
            compact: { width: 420, height: 76 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            // A followed team's game in play, beside the clock; a score change takes the
            // centre for a moment (see SportsSource).
            id: "sports",
            legacyContent: "FloatingNotchSports.qml",
            tier: "live",
            icon: "sports_soccer",
            label: "Live sports",
            preferredSide: "right",
            canDetach: false,          // a side glance; bubbles never take it
            settleMs: 0,
            compact: { width: 380, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            // Listening for a song, then what it was (see SongRecSource). Holds the centre
            // while listening: it is short, and Cancel has to be somewhere.
            id: "songRec",
            legacyContent: "FloatingNotchSongRec.qml",
            tier: "live",
            interactive: true,
            icon: "music_cast",
            label: "Song recognition",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            compact: { width: 400, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            // A ringing alarm, with Snooze and Stop. Only a ringing call outranks it.
            id: "alarm",
            legacyContent: "FloatingNotchAlarm.qml",
            tier: "interrupt",
            priority: 1,
            interactive: true,
            icon: "alarm",
            label: "Alarms",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            compact: { width: 440, height: 68 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            // Anything waiting on the fingerprint reader - sudo, polkit - whoever asked.
            // Behind a ringing call and an alarm, ahead of every other interrupt.
            id: "fingerprint",
            legacyContent: "FloatingNotchFingerprint.qml",
            tier: "interrupt",
            priority: 2,
            icon: "fingerprint",
            label: "Fingerprint prompt",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            compact: { width: 330, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            // A sensor being taken is announced once in the centre with the app's name,
            // then folds into an auxiliary bubble for as long as it is held (beside the
            // clock when bubbles are off). See PrivacySource.
            id: "privacy",
            legacyContent: "FloatingNotchPrivacy.qml",
            tier: "live",
            icon: "privacy_tip",
            label: "Privacy indicator",
            preferredSide: "left",
            canDetach: true,
            settleMs: 0,
            compact: { width: 300, height: -1 },
            orb: { size: -1 },
            expanded: { width: 300, height: 120 },   // the bubble's card: every sensor and who holds it
            content: {}
        },
        {
            id: "wifi",
            legacyContent: "FloatingNotchWifi.qml",
            tier: "transient",
            icon: "wifi",
            label: "Wi-Fi",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            ttlMs: 3000,
            compact: { width: 240, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: { compact: "activities/wifi/WifiCompact.qml" }
        },
        {
            id: "bluetooth",
            legacyContent: "FloatingNotchBluetooth.qml",
            tier: "transient",
            icon: "bluetooth",
            label: "Bluetooth",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            ttlMs: 3000,
            compact: { width: 300, height: 88 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: {
                compact: "activities/bluetooth/BluetoothCompact.qml",
                expanded: "activities/bluetooth/BluetoothExpanded.qml"
            }
        },
        {
            id: "keyboard",
            legacyContent: "FloatingNotchKeyboard.qml",
            tier: "transient",
            icon: "keyboard",
            label: "Keyboard layout",
            preferredSide: "left",
            canDetach: false,
            settleMs: 0,
            ttlMs: 1500,
            compact: { width: 200, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: { compact: "activities/keyboard/KeyboardCompact.qml" }
        },
        {
            // A VPN or Tailscale connecting or dropping, including from outside the shell.
            id: "vpn",
            legacyContent: "FloatingNotchVpn.qml",
            tier: "transient",
            icon: "vpn_key",
            label: "VPN",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            ttlMs: 3500,
            compact: { width: 300, height: -1 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },
            content: {}
        },
        {
            id: "localSend",
            legacyContent: "FloatingNotchLocalSend.qml",
            tier: "live",
            icon: "send_to_mobile",
            label: "File sharing",
            preferredSide: "right",
            canDetach: true,
            settleMs: 2000,
            compact: { width: 240, height: -1 },
            orb: { size: -1 },
            expanded: { width: 360, height: 200 },
            content: {
                compact: "activities/localsend/LocalSendCompact.qml",
                orb: "activities/localsend/LocalSendOrb.qml",
                expanded: "activities/localsend/LocalSendExpanded.qml"
            }
        },
        {
            id: "progress",
            legacyContent: "FloatingNotchProgress.qml",
            tier: "live",
            icon: "downloading",
            label: "Background jobs",
            preferredSide: "left",
            canDetach: true,
            settleMs: 2000,
            compact: { width: 240, height: 48 },
            orb: { size: -1 },
            expanded: { width: 0, height: 0 },   // no expanded face: expanding opens the dashboard
            content: {
                compact: "activities/progress/ProgressCompact.qml",
                orb: "activities/progress/ProgressOrb.qml",
                expanded: "activities/progress/ProgressExpanded.qml"
            }
        },
        {
            id: "dictation",
            legacyContent: "FloatingNotchDictation.qml",
            tier: "live",
            icon: "mic",
            label: "Dictation",
            preferredSide: "left",
            canDetach: true,
            settleMs: 1500,
            compact: { width: 260, height: 44 },
            orb: { size: -1 },
            expanded: { width: 360, height: 170 },
            content: {
                compact: "activities/dictation/DictationCompact.qml",
                orb: "activities/dictation/DictationOrb.qml",
                expanded: "activities/dictation/DictationExpanded.qml"
            }
        },
        {
            id: "mode",
            legacyContent: "FloatingNotchMode.qml",
            tier: "ambient",
            icon: "tune",
            label: "Modes",
            preferredSide: "right",
            canDetach: true,
            settleMs: 1500,
            compact: { width: 290, height: -1 },
            orb: { size: -1 },
            expanded: { width: 330, height: 160 },
            content: { compact: "activities/mode/ModeCompact.qml" }
        },
        {
            // Days-long, so ambient: it announces itself once (see UpdateSource) and
            // otherwise keeps to a bubble or the clock's side.
            id: "update",
            legacyContent: "FloatingNotchUpdate.qml",
            tier: "ambient",
            icon: "deployed_code_update",
            label: "Shell update",
            preferredSide: "right",
            canDetach: true,
            settleMs: 1500,
            compact: { width: 250, height: -1 },
            orb: { size: -1 },
            expanded: { width: 300, height: 108 },
            content: { compact: "activities/update/UpdateCompact.qml" }
        }
    ]

    readonly property var ids: root.descriptors.map(descriptor => descriptor.id)

    /**
     * The widget the legacy notch already draws for an activity.
     *
     * The notch style is ported to the engine before the presentations are redrawn, so
     * it keeps rendering these while the new compact/orb/expanded content is written
     * activity by activity. Each already honours an `isExpanded` property, which is the
     * only contract the notch host needs. They disappear with the last port.
     */
    function legacyContentFor(id) {
        const descriptor = root.byId(id);
        if (!descriptor || !descriptor.legacyContent)
            return "";
        // Resolved from the shell root rather than stored as a relative path: a relative
        // `source` resolves against whichever file instantiates the Loader, and the
        // notch surface lives two directories away from the widgets.
        return Quickshell.shellPath("modules/ii/dynamicIsland/widgets/" + descriptor.legacyContent);
    }

    /** The tier of an activity, for anything that needs to compare two of them. */
    function tierOf(id) {
        const descriptor = root.byId(id);
        return descriptor ? descriptor.tier : "idle";
    }

    function byId(id) {
        for (let i = 0; i < root.descriptors.length; i++) {
            if (root.descriptors[i].id === id)
                return root.descriptors[i];
        }
        return null;
    }

    /** Resolved width for a presentation, with `-1` meaning the island's own metric. */
    function widthFor(id, presentation) {
        const descriptor = root.byId(id);
        if (!descriptor)
            return 0;
        if (presentation === "orb") {
            const size = descriptor.orb ? descriptor.orb.size : -1;
            return size > 0 ? size : IslandMotion.orbSize;
        }
        const box = presentation === "expanded" ? descriptor.expanded : descriptor.compact;
        if (!box)
            return 0;
        return box.width > 0 ? box.width : IslandMotion.pillHeight;
    }

    function heightFor(id, presentation) {
        const descriptor = root.byId(id);
        if (!descriptor)
            return 0;
        if (presentation === "orb")
            return root.widthFor(id, "orb");
        const box = presentation === "expanded" ? descriptor.expanded : descriptor.compact;
        if (!box)
            return 0;
        return box.height > 0 ? box.height : IslandMotion.pillHeight;
    }

    /**
     * Whether an activity has an expanded face at all. Most do not any more: expanding
     * the island opens the dashboard, and only the activities with an auxiliary bubble
     * (and LocalSend's drop flow) keep one, shown in the bubble's card.
     */
    function hasExpanded(id) {
        const descriptor = root.byId(id);
        return !!(descriptor && descriptor.expanded && descriptor.expanded.width > 0);
    }

    /**
     * Whether an activity's face is something to press rather than look at - a call's
     * Answer, an alarm's Stop. The island must not turn a hover on it into the dashboard.
     */
    function isInteractive(id) {
        const descriptor = root.byId(id);
        return !!(descriptor && descriptor.interactive === true);
    }

    /** The file that draws an activity, or "" when it has no such presentation. */
    function contentFor(id, presentation) {
        const descriptor = root.byId(id);
        if (!descriptor || !descriptor.content)
            return "";
        return descriptor.content[presentation] ?? "";
    }

    function hasPresentation(id, presentation) {
        return root.contentFor(id, presentation) !== "";
    }
}
