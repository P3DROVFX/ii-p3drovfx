.pragma library

/**
 * Every activity the Activities page offers, in the order the page lists them.
 *
 *   id      the activity's id in IslandRegistry: the preview loads its real files from it
 *   key     the floatingNotch flag that switches it off (the legacy schema stores the inverse)
 *   widget  dynamicIsland.widgets entry that mirrors the flag, where one exists
 *   group   one of `groups` below
 *   shape   the icon's shape while it is on; off is always a circle
 *   tip     what it does, said once on the stage (the old switch's tooltip)
 *
 * Strings are English keys: the page passes them through Translation.tr.
 */
const groups = [
    { id: "announce", label: "Announcements", icon: "campaign",
      hint: "Flash when something happens and leave after a moment" },
    { id: "live", label: "Live activities", icon: "bolt",
      hint: "Stay on the island for exactly as long as the thing is happening" },
    { id: "glance", label: "Side glances", icon: "visibility",
      hint: "Always-on widgets beside the clock on the resting island" },
    { id: "alert", label: "Calls & alerts", icon: "notification_important",
      hint: "Need an answer now: they take the centre ahead of everything else" },
    { id: "system", label: "System notches", icon: "tune",
      hint: "Off hands them back to their own surface elsewhere in the shell" }
];

const activities = [
    // ── Announcements ────────────────────────────────────────────────────
    { id: "workspaces", key: "disableWorkspaces", group: "announce", icon: "tab", shape: "Cookie4Sided",
      label: "Workspaces", tip: "Show the workspace strip when the workspace changes" },
    { id: "keyboard", key: "disableKeyboard", group: "announce", icon: "keyboard", shape: "Square",
      label: "Keyboard layout", tip: "Show the layout switcher when the keyboard layout changes" },
    { id: "wifi", key: "disableWifi", group: "announce", icon: "wifi", shape: "Fan",
      label: "Wi-Fi", tip: "Show the network name when Wi-Fi connects" },
    { id: "bluetooth", key: "disableBluetooth", group: "announce", icon: "bluetooth", shape: "Gem",
      label: "Bluetooth", tip: "Show the device and its battery when Bluetooth connects. Off hands the connection popup back to the bar" },
    { id: "battery", key: "disableBattery", group: "announce", icon: "battery_charging_full", shape: "Pill",
      label: "Battery charging", tip: "Show the charging status when the charger is plugged in" },
    { id: "clipboard", key: "disableClipboard", group: "announce", icon: "content_paste", shape: "Slanted",
      label: "Clipboard", tip: "Show a new clipboard entry as it is copied" },
    { id: "vpn", key: "disableVpn", group: "announce", icon: "vpn_key", shape: "Pentagon",
      label: "VPN", tip: "Say when a VPN or Tailscale connects or drops, including connections started outside the shell" },

    // ── Live activities ──────────────────────────────────────────────────
    { id: "media", key: "disableMedia", group: "live", icon: "music_note", shape: "Cookie12Sided",
      label: "Media", tip: "Show the playing track, its cover and the visualizer" },
    { id: "ai", key: "disableAiStatus", group: "live", icon: "auto_awesome", shape: "SoftBurst",
      label: "AI agent status", tip: "Show agents working, waiting or finished" },
    { id: "timer", key: "disableTimer", group: "live", icon: "timer", shape: "Cookie9Sided",
      label: "Timer & stopwatch", tip: "Show a running Pomodoro, countdown or stopwatch" },
    { id: "recording", key: "disableRecording", group: "live", icon: "screen_record", shape: "Burst",
      label: "Screen recording", tip: "Show the recording indicator while the screen is captured" },
    { id: "privacy", key: "disablePrivacy", group: "live", icon: "privacy_tip", shape: "Clover4Leaf",
      label: "Privacy indicator", tip: "A microphone, camera or screen share in use: named once in the centre, then a pill beside the island - in the auxiliary bubble - for as long as it is held" },
    { id: "dictation", key: "disableDictation", group: "live", icon: "mic", shape: "Oval",
      label: "Dictation", tip: "Show the waveform while dictating" },
    { id: "songRec", key: "disableSongRec", group: "live", icon: "music_cast", shape: "Flower",
      label: "Song recognition", tip: "Show that a song is being listened for, then the song it found" },
    { id: "sports", key: "disableSports", group: "live", icon: "sports_soccer", shape: "Sunny",
      label: "Live sports", tip: "The score of a live game beside the clock, and a moment in the centre when it changes. Follows the bar's sports team filter" },
    { id: "progress", key: "disableProgress", group: "live", icon: "progress_activity", shape: "Arch",
      label: "Live progress", tip: "Show background transfers and builds while they run" },
    { id: "localSend", key: "disableLocalSend", group: "live", icon: "share", shape: "Arrow",
      label: "LocalSend sharing", tip: "The drop target, transfers and the incoming request card. Off hands them back to the floating popups" },
    { id: "mode", key: "disableMode", widget: "mode", group: "live", icon: "tune", shape: "Cookie7Sided",
      label: "Modes & Routines", tip: "Show the active mode beside the clock and as an auxiliary bubble" },
    { id: "update", key: "disableUpdate", widget: "update", group: "live", icon: "deployed_code_update", shape: "Diamond",
      label: "Shell update", tip: "Announce a waiting shell update once, then keep it beside the clock or in an auxiliary bubble until it is installed" },
    { id: "systemTray", key: "disableSystemTray", widget: "systemTray", group: "live", icon: "apps", shape: "Puffy",
      label: "System tray", tip: "The tray's programs as a bubble beside the island: its first icon contracted, every program aligned in the card, with the bar tray's activate, context menus and drag-to-pin. Off by default" },
    { id: "easyEffects", key: "disableEasyEffects", widget: "easyEffects", group: "live", icon: "graphic_eq", shape: "Clover8Leaf",
      label: "EasyEffects", tip: "EasyEffects' preset as a bubble beside the island while it runs: scroll it to switch presets, rest on it for the device's presets, bypass and the app",
      needs: "easyEffects" },

    // ── Side glances ─────────────────────────────────────────────────────
    { id: "earbuds", key: "disableEarbuds", group: "glance", icon: "headphones", shape: "Bun",
      label: "Earbuds battery", tip: "The connected headset: with bubbles on, a bubble whose ring is its battery, opening into each bud's battery and the noise control; otherwise its battery beside the clock" },
    { id: "weather", key: "disableWeather", group: "glance", icon: "partly_cloudy_day", shape: "VerySunny",
      label: "Weather", tip: "The weather icon and temperature beside the clock, kept fresh on the service's fetch interval" },
    { id: "batteryGlance", key: "disableBatteryGlance", group: "glance", icon: "battery_android_full", shape: "Pill",
      label: "Battery level", tip: "The laptop battery beside the clock, with a bolt while it charges. Separate from the charging announcement" },
    { id: "discordVoice", key: "disableDiscordVoice", group: "glance", icon: "headset_mic", shape: "Ghostish",
      label: "Discord voice", tip: "Name the channel when you join a Discord call, then show who is talking and whether you are muted. Click it to mute. Only starts watching once Discord or Vesktop has opened a window" },
    { id: "phoneLink", key: "disablePhoneLink", group: "glance", icon: "phonelink", shape: "ClamShell",
      label: "Phone camera & mic", tip: "Show when the phone's camera or microphone is streaming into this computer, with a way to stop it" },
    { id: "phoneMirror", key: "disablePhoneMirror", group: "glance", icon: "mobile_screen_share", shape: "Square",
      label: "Phone mirror", tip: "Show while the phone's screen or one of its apps is mirrored into a window, with a way to jump to it or stop it" },

    // ── Calls & alerts ───────────────────────────────────────────────────
    { id: "phoneCall", key: "disablePhoneCall", group: "alert", icon: "call", shape: "Cookie6Sided",
      label: "Phone calls", tip: "A call ringing on the paired phone, with Answer and Decline over ADB, then the call in progress" },
    { id: "fingerprint", key: "disableFingerprint", group: "alert", icon: "fingerprint", shape: "PixelCircle",
      label: "Fingerprint prompt", tip: "Ask for a touch whenever anything waits on the fingerprint reader: sudo in a terminal, polkit, pkexec. The lock screen keeps its own prompt" },
    { id: "alarm", key: "disableAlarm", group: "alert", icon: "alarm", shape: "SoftBoom",
      label: "Alarms", tip: "A ringing alarm, with Stop and Snooze, instead of the fullscreen alarm popup" },

    // ── System ───────────────────────────────────────────────────────────
    { id: "notification", key: "disableNotification", group: "system", icon: "notifications", shape: "Cookie9Sided",
      label: "Notifications", tip: "Incoming notifications open inside the island instead of as floating toasts" },
    { id: "osd", key: "disableOsd", group: "system", icon: "volume_up", shape: "Cookie12Sided",
      label: "OSD", tip: "Volume, brightness and input feedback inside the island instead of the floating indicators" }
];

function byId(id) {
    for (let i = 0; i < activities.length; i++) {
        if (activities[i].id === id)
            return activities[i];
    }
    return null;
}

function group(id) {
    for (let i = 0; i < groups.length; i++) {
        if (groups[i].id === id)
            return groups[i];
    }
    return null;
}

/**
 * Example data for the faces whose content arrives as an event, handed to the real
 * widgets. Faces that read a source walk up to the nearest `controller` and take
 * `controller.sources.<id>`; the few that read a service directly take `sample`.
 * The rest show what is really happening.
 */
const sources = {
    clipboard: { payload: "1\tMeeting notes for Friday", fromPhone: false },
    fingerprint: { phase: "scan", hint: "", requester: "sudo pacman -Syu" },
    phoneCall: { phase: "ringing", missedName: "" },
    phoneLink: { announcedKind: "camera" },
    phoneMirrorError: { payload: { reason: "device", title: "Phone disconnected", sessionId: "" } },
    privacy: { announcedKind: "microphone", announcedApps: "Firefox" },
    songRec: { phase: "listening", failureMessage: "", dismiss: function() {} },
    sports: { liveGame: null },
    vpn: { payload: { connected: true, provider: "Tailscale", detail: "exit node" } }
};

function samplesFor(nowSeconds) {
    return {
        alarm: { alarm: { time: "07:30", label: "Morning run" } },
        recording: { state: { active: true, paused: false, seconds: 83 } },
        progress: { jobs: [{ id: "preview", state: "running", percent: 62, message: "Building shell", appName: "make", icon: "build" }] },
        phoneCall: { displayName: "Ana Souza", avatarPath: "" },
        discordVoice: {
            channel: { name: "General" },
            participants: [
                { id: "", nick: "Ana", speaking: true, mute: false, deaf: false },
                { id: "", nick: "Leo", speaking: false, mute: true, deaf: false }
            ]
        },
        notification: {
            notificationId: -1, appName: "Messages", appIcon: "", image: "",
            summary: "Ana", body: "Are we still on for tonight?", urgency: "1",
            actions: [], time: nowSeconds * 1000, notification: null
        },
        ai: {
            agents: [{ pid: -1, name: "Claude", icon: "bootstrap_claude.svg", source: "cli",
                       state: "working", requiresAttention: false, startedAtEpoch: nowSeconds - 83 }]
        }
    };
}
