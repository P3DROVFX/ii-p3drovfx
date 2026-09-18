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
            compact: { width: 280, height: -1 },
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
            expanded: { width: 320, height: 150 },
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
            compact: { width: 380, height: -1 },
            orb: { size: -1 },
            expanded: { width: 440, height: 180 },
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
            id: "osd",
            tier: "interrupt",
            icon: "volume_up",
            label: "Volume & brightness",
            preferredSide: "right",
            canDetach: false,          // a slider belongs where the eye already is
            settleMs: 0,
            ttlMs: 1500,
            compact: { width: 340, height: -1 },
            orb: { size: -1 },
            expanded: { width: 340, height: -1 },
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
            expanded: { width: 340, height: 150 },
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
            compact: { width: 150, height: -1 },
            orb: { size: -1 },
            expanded: { width: 280, height: 160 },
            content: {
                compact: "activities/battery/BatteryCompact.qml",
                expanded: "activities/battery/BatteryExpanded.qml"
            }
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
            expanded: { width: 300, height: 150 },
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
            compact: { width: 300, height: -1 },
            orb: { size: -1 },
            expanded: { width: 360, height: 170 },
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
            compact: { width: 180, height: -1 },
            orb: { size: -1 },
            expanded: { width: 260, height: 140 },
            content: { compact: "activities/keyboard/KeyboardCompact.qml" }
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
            compact: { width: 240, height: -1 },
            orb: { size: -1 },
            expanded: { width: 360, height: 180 },
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
            compact: { width: 260, height: -1 },
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
            tier: "transient",
            icon: "tune",
            label: "Modes",
            preferredSide: "right",
            canDetach: false,
            settleMs: 0,
            ttlMs: 3000,
            compact: { width: 290, height: -1 },
            orb: { size: -1 },
            expanded: { width: 340, height: 150 },
            content: { compact: "activities/mode/ModeCompact.qml" }
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
