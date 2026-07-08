pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // Default and Expressive style options shared by most components
    readonly property var defaultStyleOptions: [
        {
            displayName: qsTr("Default"),
            icon: "style",
            value: "default"
        },
        {
            displayName: qsTr("Expressive"),
            icon: "fluid_med",
            value: "expressive"
        }
    ]

    readonly property var allComponents: [
        {
            id: "policies_panel_button",
            icon: "star",
            title: "Policies panel button",
            styleConfigKey: "policies",
            styleOptions: defaultStyleOptions,
            configPage: "CorePoliciesConfig.qml"
        },
        {
            id: "active_window",
            icon: "label",
            title: "Active window",
            styleConfigKey: "activeWindow",
            styleOptions: defaultStyleOptions,
            configPage: "ActiveWindowConfig.qml"
        },
        {
            id: "music_player",
            icon: "music_note",
            title: "Music player",
            styleConfigKey: "media",
            styleOptions: [
                {
                    displayName: qsTr("Default"),
                    icon: "style",
                    value: "default"
                },
                {
                    displayName: qsTr("Expressive"),
                    icon: "fluid_med",
                    value: "expressive"
                },
                {
                    displayName: qsTr("Neural"),
                    icon: "graphic_eq",
                    value: "neural"
                }
            ],
            configPage: "MediaPlayerConfig.qml"
        },
        {
            id: "workspaces",
            icon: "workspaces",
            title: "Workspaces",
            styleConfigKey: "workspaces",
            configPage: "../WorkspacesConfig.qml",
            styleOptions: [
                {
                    displayName: qsTr("Default"),
                    icon: "workspaces",
                    value: "default"
                },
                {
                    displayName: qsTr("Minimal"),
                    icon: "navigation",
                    value: "minimal"
                },
                {
                    displayName: qsTr("Expressive"),
                    icon: "fluid_med",
                    value: "expressive"
                },
                {
                    displayName: qsTr("Dock"),
                    icon: "dock_to_left",
                    value: "dock"
                }
            ]
        },
        {
            id: "system_monitor",
            icon: "monitor_heart",
            title: "System monitor",
            styleConfigKey: "resources",
            styleOptions: defaultStyleOptions,
            configPage: "SystemMonitorConfig.qml"
        },
        {
            id: "clock",
            icon: "nest_clock_farsight_analog",
            title: "Clock",
            styleConfigKey: "clock",
            styleOptions: defaultStyleOptions,
            configPage: "CoreTimeDateConfig.qml"
        },
        {
            id: "system_tray",
            icon: "system_update_alt",
            title: "System tray",
            styleConfigKey: "systray",
            styleOptions: defaultStyleOptions,
            configPage: "SystemTrayConfig.qml"
        },
        {
            id: "dashboard_panel_button",
            icon: "notifications",
            title: "Dashboard panel button",
            styleConfigKey: "dashboard",
            styleOptions: defaultStyleOptions,
            configPage: "DashboardButtonConfig.qml"
        },
        {
            id: "record_indicator",
            icon: "screen_record",
            title: "Record indicator",
            configPage: "IndicatorsConfig.qml"
        },
        {
            id: "screen_share_indicator",
            icon: "screen_share",
            title: "Screen share indicator",
            configPage: "IndicatorsConfig.qml"
        },
        {
            id: "phone_scrcpy_indicator",
            icon: "smart_display",
            title: "Phone scrcpy indicator",
            configPage: "CorePoliciesConfig.qml"
        },
        {
            id: "date",
            icon: "date_range",
            title: "Date",
            configPage: "CoreTimeDateConfig.qml"
        },
        {
            id: "battery",
            icon: "battery_android_6",
            title: "Battery",
            styleConfigKey: "battery",
            styleOptions: defaultStyleOptions,
            configPage: "BatteryConfig.qml"
        },
        {
            id: "timer",
            icon: "timer",
            title: "Timer & Pomodoro",
            configPage: "IndicatorsConfig.qml"
        },
        {
            id: "weather",
            icon: "weather_mix",
            title: "Weather",
            styleConfigKey: "weather",
            styleOptions: defaultStyleOptions,
            configPage: "CoreWeatherConfig.qml"
        },
        {
            id: "utility_buttons",
            icon: "build",
            title: "Utility buttons",
            styleConfigKey: "utilButtons",
            styleOptions: defaultStyleOptions,
            configPage: "UtilButtonsConfig.qml"
        },
        {
            id: "bluetooth_devices",
            icon: "bluetooth_connected",
            title: "Bluetooth Devices",
            styleConfigKey: "bluetooth",
            styleOptions: defaultStyleOptions,
            configPage: "BluetoothConfig.qml"
        },
        {
            id: "keyboard_layout",
            icon: "keyboard",
            title: "Keyboard Layout",
            styleConfigKey: "keyboard",
            styleOptions: defaultStyleOptions,
            configPage: "KeyboardLayoutConfig.qml"
        },
        {
            id: "sports",
            icon: "sports_soccer",
            title: "Sports",
            styleConfigKey: "sports",
            styleOptions: defaultStyleOptions,
            configPage: "SportsConfig.qml"
        },
        {
            id: "power",
            icon: "power_settings_new",
            title: "Power button",
            styleConfigKey: "power",
            styleOptions: defaultStyleOptions,
            configPage: "CorePowerConfig.qml"
        }
    ]

    function getComponent(id) {
        return allComponents.find(c => c.id === id) || null;
    }

    function getAvailableComponents(usedIds) {
        return allComponents.filter(c => !usedIds.includes(c.id));
    }
}
