pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Cue bus for the dashboard button's animated icons.
 *
 * The icons live on the bar; the settings page that previews them lives in
 * another window. A signal bus is the only thing that reaches both without
 * either one holding a reference to the other, and it doubles as the seam the
 * test buttons plug into — the same call the real state changes make.
 */
Singleton {
    id: root

    // One channel per icon; see modules/ii/bar/widgets/dashboard/icons/.
    signal cue(string channel, string name)

    // Every cue any icon answers to, in the order a person would try them.
    readonly property var catalog: [
        {
            channel: "wifi",
            title: "Wi-Fi",
            icon: "wifi",
            cues: [
                { name: "searching", label: "Searching" },
                { name: "connected", label: "Connected" },
                { name: "disconnected", label: "Disconnected" },
                { name: "disabled", label: "Turned off" }
            ]
        },
        {
            channel: "bluetooth",
            title: "Bluetooth",
            icon: "bluetooth",
            cues: [
                { name: "scanning", label: "Scanning" },
                { name: "connected", label: "Device connected" },
                { name: "disconnected", label: "Device left" },
                { name: "disabled", label: "Turned off" }
            ]
        },
        {
            channel: "volume",
            title: "Volume",
            icon: "volume_up",
            cues: [
                { name: "up", label: "Volume up" },
                { name: "down", label: "Volume down" },
                { name: "mute", label: "Mute" },
                { name: "unmute", label: "Unmute" }
            ]
        },
        {
            channel: "mic",
            title: "Microphone",
            icon: "mic",
            cues: [
                { name: "mute", label: "Mute" },
                { name: "unmute", label: "Unmute" }
            ]
        },
        {
            channel: "caffeine",
            title: "Caffeine",
            icon: "coffee",
            cues: [
                { name: "on", label: "Keep awake on" },
                { name: "off", label: "Keep awake off" }
            ]
        },
        {
            channel: "vpn",
            title: "VPN",
            icon: "vpn_key",
            cues: [
                { name: "connected", label: "Connected" },
                { name: "disconnected", label: "Disconnected" }
            ]
        },
        {
            channel: "tailscale",
            title: "Tailscale",
            icon: "hub",
            cues: [
                { name: "connected", label: "Mesh up" },
                { name: "disconnected", label: "Mesh down" }
            ]
        },
        {
            channel: "pomodoro",
            title: "Pomodoro",
            icon: "timer",
            cues: [
                { name: "start", label: "Start" },
                { name: "pause", label: "Pause" },
                { name: "complete", label: "Lap done" },
                { name: "reset", label: "Reset" }
            ]
        },
        {
            channel: "stopwatch",
            title: "Stopwatch",
            icon: "timer",
            cues: [
                { name: "start", label: "Start" },
                { name: "lap", label: "Lap" },
                { name: "stop", label: "Stop" },
                { name: "reset", label: "Reset" }
            ]
        },
        {
            channel: "countdown",
            title: "Countdown timer",
            icon: "hourglass_top",
            cues: [
                { name: "start", label: "Timer added" },
                { name: "pause", label: "Paused" },
                { name: "resume", label: "Resumed" },
                { name: "complete", label: "Finished" },
                { name: "removed", label: "Timer removed" }
            ]
        },
        {
            channel: "easyeffects",
            title: "EasyEffects",
            icon: "graphic_eq",
            cues: [
                { name: "on", label: "Effects on" },
                { name: "off", label: "Effects off" }
            ]
        },
        {
            channel: "dns",
            title: "Encrypted DNS",
            icon: "encrypted",
            cues: [
                { name: "on", label: "Encrypted" },
                { name: "switching", label: "Switching" },
                { name: "off", label: "Plain" }
            ]
        },
        {
            channel: "warp",
            title: "Cloudflare WARP",
            icon: "cloud_lock",
            cues: [
                { name: "connected", label: "Connected" },
                { name: "disconnected", label: "Disconnected" }
            ]
        },
        {
            channel: "gamemode",
            title: "Game mode",
            icon: "gamepad",
            cues: [
                { name: "on", label: "Game mode on" },
                { name: "off", label: "Game mode off" }
            ]
        },
        {
            channel: "songrec",
            title: "Identify Music",
            icon: "music_cast",
            cues: [
                { name: "listening", label: "Listening" },
                { name: "found", label: "Match found" },
                { name: "off", label: "Stopped" }
            ]
        },
        {
            channel: "alarm",
            title: "System alarm",
            icon: "alarm",
            cues: [
                { name: "open", label: "Alarm added" },
                { name: "ringing", label: "Ringing" },
                { name: "stopped", label: "Stopped" },
                { name: "removed", label: "Alarm removed" }
            ]
        },
        {
            channel: "notification",
            title: "Notifications",
            icon: "notifications",
            cues: [
                { name: "arrive", label: "New notification" },
                { name: "silence", label: "Silence" },
                { name: "unsilence", label: "Unsilence" }
            ]
        }
    ]

    function play(channel: string, name: string): void {
        root.cue(channel, name);
    }
}
