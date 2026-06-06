import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQml.Models

ContentPage {
    id: page
    forceWidth: true
    readonly property int index: 2
    property bool register: parent.register ?? false

    property var componentMap: ({
            "active_window": activeWindow,
            "music_player": musicPlayer,
            "utility_buttons": utilityButtons,
            "system_tray": systemTray,
            "workspaces": workspaces,
            "timer": indicators,
            "record_indicator": indicators,
            "system_monitor": resourcesConfig,
            "sports": sportsConfig,
            "dashboard_panel_button": dashboardButtonConfig
        })

    function scrollTo(stringId) {
        const item = componentMap[stringId];
        page.contentY = item.y;
    }

    ContentSection {
        icon: "mobile_layout"
        title: Translation.tr("Bar layout")
        ContentSubsection {
            title: Translation.tr("Left layout")
            tooltip: Translation.tr("Top layout in vertical mode")
            ConfigListView {
                barSection: 0
                listModel: Config.options.bar.layouts.left
                onUpdated: newList => {
                    Config.options.bar.layouts.left = newList;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Center layout")
            tooltip: Translation.tr("Center the component with the button")
            ConfigListView {
                barSection: 1
                listModel: Config.options.bar.layouts.center
                onUpdated: newList => {
                    Config.options.bar.layouts.center = newList;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Right layout")
            tooltip: Translation.tr("Bottom layout in vertical mode")
            ConfigListView {
                barSection: 2
                listModel: Config.options.bar.layouts.right
                onUpdated: newList => {
                    Config.options.bar.layouts.right = newList;
                }
            }
        }
    }

    ContentSection {
        icon: "open_in_full"
        title: Translation.tr("Bar sizes")

        ConfigSpinBox {
            icon: "height"
            text: Translation.tr("Bar height")
            value: Config.options.bar.sizes.height
            from: 30
            to: 50
            stepSize: 1
            onValueChanged: {
                Config.options.bar.sizes.height = value;
            }
        }
        ConfigSpinBox {
            icon: "width"
            text: Translation.tr("Bar width")
            value: Config.options.bar.sizes.width
            from: 30
            to: 50
            stepSize: 1
            onValueChanged: {
                Config.options.bar.sizes.width = value;
            }
        }
    }

    ContentSection {
        icon: "spoke"
        title: Translation.tr("Positioning & appearance")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Automatically hide")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.autoHide.enable
                    onSelected: newValue => {
                        Config.options.bar.autoHide.enable = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: true
                        }
                    ]
                }
            }
        }

        ConfigRow {
            Layout.fillHeight: false
            ContentSubsection {
                title: Translation.tr("Corner style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Dynamic Island"),
                            icon: "water_drop",
                            value: 3
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Group style")
                tooltip: Translation.tr("Island style makes the group background opaque when bar is transparent")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.barGroupStyle
                    onSelected: newValue => {
                        Config.options.bar.barGroupStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Pills"),
                            icon: "location_chip",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Island"),
                            icon: "shadow",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Transparent"),
                            icon: "opacity",
                            value: 2
                        }
                    ]
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Bar background style")
            tooltip: Translation.tr("Adaptive style makes the bar background transparent when there are no active windows")
            Layout.fillWidth: false

            ConfigSelectionArray {
                currentValue: Config.options.bar.barBackgroundStyle
                onSelected: newValue => {
                    Config.options.bar.barBackgroundStyle = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Visible"),
                        icon: "visibility",
                        value: 1
                    },
                    {
                        displayName: Translation.tr("Adaptive"),
                        icon: "masked_transitions",
                        value: 2
                    },
                    {
                        displayName: Translation.tr("Transparent"),
                        icon: "opacity",
                        value: 0
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Expressive bar solid colors")
            tooltip: Translation.tr("Use expressive solid layer colors")
            Layout.fillWidth: true

            ConfigRow {
                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Enable")
                    checked: Config.options.bar.expressiveColors
                    onCheckedChanged: {
                        Config.options.bar.expressiveColors = checked;
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ConfigSelectionArray {
                    enabled: Config.options.bar.expressiveColors
                    currentValue: Config.options.bar.expressiveColorTheme
                    onSelected: newValue => {
                        Config.options.bar.expressiveColorTheme = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Content"),
                            icon: "brush",
                            value: "content"
                        },
                        {
                            displayName: Translation.tr("Vibrant"),
                            icon: "brush",
                            value: "primary"
                        },
                        {
                            displayName: Translation.tr("Secondary"),
                            icon: "brush",
                            value: "secondary"
                        },
                        {
                            displayName: Translation.tr("Surface"),
                            icon: "brush",
                            value: "surface"
                        }
                    ]
                }
            }
        }
    }

    ContentSection {
        id: componentStyles
        icon: "dashboard_customize"
        title: Translation.tr("Component styles")

        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Clock")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.clock
                    onSelected: newValue => {
                        Config.options.bar.styles.clock = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "schedule",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Media player")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.media
                    onSelected: newValue => {
                        Config.options.bar.styles.media = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "music_note",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
        }

        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Workspaces")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.workspaces
                    onSelected: newValue => {
                        Config.options.bar.styles.workspaces = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "workspaces",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Minimal"),
                            icon: "navigation",
                            value: "minimal"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Utility buttons")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.utilButtons
                    onSelected: newValue => {
                        Config.options.bar.styles.utilButtons = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "widgets",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
        }

        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Weather")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.weather
                    onSelected: newValue => {
                        Config.options.bar.styles.weather = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "partly_cloudy_day",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Notifications")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.notification
                    onSelected: newValue => {
                        Config.options.bar.styles.notification = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "notifications",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
        }
        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Dashboard")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.dashboard
                    onSelected: newValue => {
                        Config.options.bar.styles.dashboard = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "dashboard",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Resources")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.resources
                    onSelected: newValue => {
                        Config.options.bar.styles.resources = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "memory",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
        }

        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Policies")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.policies
                    onSelected: newValue => {
                        Config.options.bar.styles.policies = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "policy",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Power")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.power
                    onSelected: newValue => {
                        Config.options.bar.styles.power = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "power_settings_new",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
        }
        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Battery")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.battery
                    onSelected: newValue => {
                        Config.options.bar.styles.battery = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "battery_charging_full",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Bluetooth")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.bluetooth
                    onSelected: newValue => {
                        Config.options.bar.styles.bluetooth = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "bluetooth",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
        }

        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Keyboard Layout")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.keyboard
                    onSelected: newValue => {
                        Config.options.bar.styles.keyboard = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "keyboard",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
        }

        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Sports")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.sports
                    onSelected: newValue => {
                        Config.options.bar.styles.sports = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "sports_soccer",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Expressive"),
                            icon: "fluid_med",
                            value: "expressive"
                        }
                    ]
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }
    }

    ContentSection {
        id: activeWindow
        icon: "ad"
        title: Translation.tr("Active window")
        ConfigSwitch {
            buttonIcon: "crop_free"
            text: Translation.tr("Use fixed size")
            checked: Config.options.bar.activeWindow.fixedSize
            onCheckedChanged: {
                Config.options.bar.activeWindow.fixedSize = checked;
            }
        }
    }

    ContentSection {
        id: musicPlayer
        icon: "music_cast"
        title: Translation.tr("Media player")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "crop_free"
                text: Translation.tr("Use fixed size")
                checked: Config.options.bar.mediaPlayer.useFixedSize
                onCheckedChanged: {
                    Config.options.bar.mediaPlayer.useFixedSize = checked;
                }
            }

            ConfigSpinBox {
                enabled: !Config.options.bar.vertical && Config.options.bar.mediaPlayer.useFixedSize
                icon: "width_full"
                text: Translation.tr("Custom size")
                value: Config.options.bar.mediaPlayer.customSize
                from: 100
                to: 500
                stepSize: 25
                onValueChanged: {
                    Config.options.bar.mediaPlayer.customSize = value;
                }
            }
        }

        ConfigSpinBox {
            enabled: !Config.options.bar.vertical
            icon: "width_full"
            text: Translation.tr("Lyrics width")
            value: Config.options.bar.mediaPlayer.lyrics.customSize
            from: 100
            to: 750
            stepSize: 25
            onValueChanged: {
                Config.options.bar.mediaPlayer.lyrics.customSize = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "fluid_med"
            text: Translation.tr("Expressive media popup")
            checked: Config.options.bar.mediaPlayer.expressivePopup
            onCheckedChanged: {
                Config.options.bar.mediaPlayer.expressivePopup = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Artwork")

            ConfigSwitch {
                enabled: !Config.options.bar.vertical
                buttonIcon: "image"
                text: Translation.tr("Enable artwork")
                checked: Config.options.bar.mediaPlayer.artwork.enable
                onCheckedChanged: {
                    Config.options.bar.mediaPlayer.artwork.enable = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Lyrics")

            ConfigRow {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    Layout.fillWidth: false
                    checked: Config.options.bar.mediaPlayer.lyrics.enable
                    onCheckedChanged: {
                        Config.options.bar.mediaPlayer.lyrics.enable = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Lyrics will be visible when they are fetched with API")
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ConfigSelectionArray {
                    Layout.fillWidth: false
                    currentValue: Config.options.bar.mediaPlayer.lyrics.style
                    onSelected: newValue => {
                        Config.options.bar.mediaPlayer.lyrics.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Static"),
                            icon: "format_size",
                            value: "static"
                        },
                        {
                            displayName: Translation.tr("Scroller"),
                            icon: "keyboard_double_arrow_up",
                            value: "scroller"
                        }
                    ]
                }
            }

            ConfigSwitch {
                enabled: Config.options.bar.mediaPlayer.lyrics.enable && Config.options.bar.mediaPlayer.lyrics.style === "scroller"
                buttonIcon: "gradient"
                text: Translation.tr("Use gradient mask")
                checked: Config.options.bar.mediaPlayer.lyrics.useGradientMask
                onCheckedChanged: {
                    Config.options.bar.mediaPlayer.lyrics.useGradientMask = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")
        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Unread indicator: show count")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }
    }

    ContentSection {
        id: systemTray
        icon: "shelf_auto_hide"
        title: Translation.tr("Tray")

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr('Make icons pinned by default')
            checked: Config.options.tray.invertPinnedItems
            onCheckedChanged: {
                Config.options.tray.invertPinnedItems = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "colorize"
            text: Translation.tr("Tint System Tray icons")
            checked: Config.options.tray.monochromeIcons
            onCheckedChanged: {
                Config.options.tray.monochromeIcons = checked;
            }
        }
    }

    ContentSection {
        id: indicators
        icon: "ad"
        title: Translation.tr("Indicators")

        ContentSubsection {
            title: Translation.tr("Timer and pomodoro")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "timer"
                    text: Translation.tr("Show stopwatch")
                    checked: Config.options.bar.timers.showStopwatch
                    onCheckedChanged: {
                        Config.options.bar.timers.showStopwatch = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "search_activity"
                    text: Translation.tr("Show pomodoro")
                    checked: Config.options.bar.timers.showPomodoro
                    onCheckedChanged: {
                        Config.options.bar.timers.showPomodoro = checked;
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Record")

            ConfigSwitch {
                buttonIcon: "check_indeterminate_small"
                text: Translation.tr("Minimal mode")
                checked: Config.options.bar.indicators.record.minimal
                onCheckedChanged: {
                    Config.options.bar.indicators.record.minimal = checked;
                }
            }
        }
    }

    ContentSection {
        id: utilityButtons
        icon: "widgets"
        title: Translation.tr("Utility buttons")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "content_cut"
                text: Translation.tr("Screen snip")
                checked: Config.options.bar.utilButtons.showScreenSnip
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenSnip = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "colorize"
                text: Translation.tr("Color picker")
                checked: Config.options.bar.utilButtons.showColorPicker
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showColorPicker = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Keyboard toggle")
                checked: Config.options.bar.utilButtons.showKeyboardToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showKeyboardToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Mic toggle")
                checked: Config.options.bar.utilButtons.showMicToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showMicToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Dark/Light toggle")
                checked: Config.options.bar.utilButtons.showDarkModeToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showDarkModeToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Performance Profile toggle")
                checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showPerformanceProfileToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
                checked: Config.options.bar.utilButtons.showScreenRecord
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenRecord = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "imagesmode"
                text: Translation.tr("Wallpaper Selector")
                checked: Config.options.bar.utilButtons.showWallpaperToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showWallpaperToggle = checked;
                }
            }
        }
    }

    ContentSection {
        id: workspaces
        icon: "workspaces"
        title: Translation.tr("Workspaces")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "grid_3x3"
                text: Translation.tr('Use workspace map')
                checked: Config.options.bar.workspaces.useWorkspaceMap
                onCheckedChanged: {
                    Config.options.bar.workspaces.useWorkspaceMap = checked;
                }
                StyledToolTip {
                    text: Translation.tr("For multi-monitor setups, isolates workspaces ranges for each monitor")
                }
            }
            ConfigSwitch {
                buttonIcon: "sync"
                text: Translation.tr('Sync overview map')
                checked: Config.options.overview.useWorkspaceMap
                onCheckedChanged: {
                    Config.options.overview.useWorkspaceMap = checked;
                    if (checked) {
                        Config.options.overview.workspaceMap = JSON.parse(JSON.stringify(Config.options.bar.workspaces.workspaceMap || []));
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Apply the same workspace map constraints to the Overview screen")
                }
            }
        }

        ContentSubsection {
            visible: Config.options.bar.workspaces.useWorkspaceMap
            title: Translation.tr("Workspace Map Configuration")
            tooltip: Translation.tr("Set the starting workspace offset for each connected monitor.")
            
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                NoticeBox {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 8
                    materialIcon: "info"
                    text: Translation.tr("To prevent overlapping workspaces, set starting workspaces based on the number of workspaces shown (e.g. if workspaces shown is 7, Monitor 1 starts at 1, Monitor 2 starts at 8).")
                }

                Repeater {
                    model: HyprlandData.monitors
                    delegate: ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "monitor"
                        text: modelData.name ? modelData.name : (Translation.tr("Monitor ") + (index + 1))
                        value: {
                            let map = Config.options.bar.workspaces.workspaceMap || [];
                            let offset = map.length > index ? map[index] : (index * (Config.options.bar.workspaces.shown || 10));
                            return offset + 1;
                        }
                        from: 1
                        to: 100
                        stepSize: 1
                        onValueChanged: {
                            let map = JSON.parse(JSON.stringify(Config.options.bar.workspaces.workspaceMap || []));
                            // Ensure array reaches this index
                            while (map.length <= index) {
                                map.push(map.length > 0 ? map[map.length - 1] + (Config.options.bar.workspaces.shown || 10) : 0);
                            }
                            map[index] = value - 1;
                            Config.options.bar.workspaces.workspaceMap = map;
                            if (Config.options.overview.useWorkspaceMap) {
                                Config.options.overview.workspaceMap = map;
                            }
                        }
                    }
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr('Always show numbers')
            checked: Config.options.bar.workspaces.alwaysShowNumbers
            onCheckedChanged: {
                Config.options.bar.workspaces.alwaysShowNumbers = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "award_star"
            text: Translation.tr('Show app icons')
            checked: Config.options.bar.workspaces.showAppIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.showAppIcons = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "hdr_weak"
            text: Translation.tr("Dynamic workspaces")
            checked: Config.options.bar.workspaces.dynamicWorkspaces
            onCheckedChanged: {
                Config.options.bar.workspaces.dynamicWorkspaces = checked;
            }
            StyledToolTip {
                text: Translation.tr("Hides the empty workspaces and only shows the ones with windows")
            }
        }

        ConfigSpinBox {
            enabled: !Config.options.bar.workspaces.dynamicWorkspaces
            icon: "view_column"
            text: Translation.tr("Workspaces shown")
            value: Config.options.bar.workspaces.shown
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.bar.workspaces.shown = value;
            }
        }

        ConfigSpinBox {
            icon: "select_window"
            text: Translation.tr("Maximum window count per workspace")
            value: Config.options.bar.workspaces.maxWindowCount
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.bar.workspaces.maxWindowCount = value;
            }
        }

        ConfigSpinBox {
            icon: "touch_long"
            text: Translation.tr("Number show delay when pressing Super (ms)")
            value: Config.options.bar.workspaces.showNumberDelay
            from: 0
            to: 1000
            stepSize: 50
            onValueChanged: {
                Config.options.bar.workspaces.showNumberDelay = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Number style")

            ConfigSelectionArray {
                currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
                onSelected: newValue => {
                    Config.options.bar.workspaces.numberMap = JSON.parse(newValue);
                }
                options: [
                    {
                        displayName: Translation.tr("Normal"),
                        icon: "timer_10",
                        value: '[]'
                    },
                    {
                        displayName: Translation.tr("Han chars"),
                        icon: "square_dot",
                        value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]'
                    },
                    {
                        displayName: Translation.tr("Roman"),
                        icon: "account_balance",
                        value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]'
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Icon Shape Mask")
            tooltip: Translation.tr("Apply a shape to crop icons")
            ConfigRow {
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "masks"
                    text: Translation.tr("Apply shape mask to icons")
                    checked: Config.options.appearance.icons.enableShapeMask
                    onCheckedChanged: {
                        Config.options.appearance.icons.enableShapeMask = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Crops the icons using the selected material shape")
                    }
                }

                RippleButtonWithShape {
                    Layout.fillWidth: false
                    shapeString: Config.options.appearance.icons.shapeMask
                    implicitWidth: 60
                    extraIcon: "edit"

                    onClicked: {
                        iconsShapeMaskLoader.active = !iconsShapeMaskLoader.active;
                    }
                    StyledToolTip {
                        text: Translation.tr("Edit the material shape")
                    }
                }
            }

            Loader {
                id: iconsShapeMaskLoader
                active: false
                visible: active
                Layout.fillWidth: true
                sourceComponent: ContentSubsection {
                    title: Translation.tr("Mask shape")

                    ConfigSelectionArray {
                        currentValue: Config.options.appearance.icons.shapeMask
                        onSelected: newValue => {
                            Config.options.appearance.icons.shapeMask = newValue;
                        }
                        options: (["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map(icon => {
                            return {
                                displayName: "",
                                shape: icon,
                                value: icon
                            };
                        })
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Active Indicator Shape")
            tooltip: Translation.tr("Apply a Material Shape to the active workspace indicator")
            ConfigRow {
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "frame_person"
                    text: Translation.tr("Use Material Shape for indicator")
                    checked: Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                    onCheckedChanged: {
                        Config.options.bar.workspaces.useMaterialShapeForActiveIndicator = checked;
                    }
                }

                RippleButtonWithShape {
                    enabled: Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                    Layout.fillWidth: false
                    shapeString: Config.options.bar.workspaces.activeIndicatorShape
                    implicitWidth: 60
                    extraIcon: "edit"

                    onClicked: {
                        activeIndicatorShapeLoader.active = !activeIndicatorShapeLoader.active;
                    }
                    StyledToolTip {
                        text: Translation.tr("Edit the material shape")
                    }
                }
            }

            ConfigSwitch {
                enabled: !Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                buttonIcon: "shuffle"
                text: Translation.tr("Use random shape for active indicator")
                checked: Config.options.bar.workspaces.useRandomShapeForActiveIndicator
                onCheckedChanged: {
                    Config.options.bar.workspaces.useRandomShapeForActiveIndicator = checked;
                }
            }

            Loader {
                id: activeIndicatorShapeLoader
                active: false
                visible: active && Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                Layout.fillWidth: true
                sourceComponent: ContentSubsection {
                    title: Translation.tr("Indicator shape")

                    ConfigSelectionArray {
                        currentValue: Config.options.bar.workspaces.activeIndicatorShape
                        onSelected: newValue => {
                            Config.options.bar.workspaces.activeIndicatorShape = newValue;
                        }
                        options: (["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map(icon => {
                            return {
                                displayName: "",
                                shape: icon,
                                value: icon
                            };
                        })
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "tooltip"
        title: Translation.tr("Tooltips")

        ContentSubsection {
            title: Translation.tr("Bluetooth devices layout")
            tooltip: Translation.tr("Choose the layout for the Bluetooth devices popup in the bar")
            ConfigSelectionArray {
                currentValue: Config.options.bar.bluetoothDevicesLayout
                onSelected: newValue => {
                    Config.options.bar.bluetoothDevicesLayout = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "style",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Expressive"),
                        icon: "fluid_med",
                        value: "expressive"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "ads_click"
            text: Translation.tr("Click to show")
            checked: Config.options.bar.tooltips.clickToShow
            onCheckedChanged: {
                Config.options.bar.tooltips.clickToShow = checked;
            }
            StyledToolTip {
                text: Translation.tr("You will not be able to use the buttons on some popups if you enable this option.")
            }
        }
        ConfigSwitch {
            buttonIcon: "compress"
            text: Translation.tr("Compact popups")
            checked: Config.options.bar.tooltips.compactPopups
            onCheckedChanged: {
                Config.options.bar.tooltips.compactPopups = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "colorize"
            text: Translation.tr("Enable color picker popup")
            checked: Config.options.bar.tooltips.enableColorPickerPopup
            onCheckedChanged: {
                Config.options.bar.tooltips.enableColorPickerPopup = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "bluetooth"
            text: Translation.tr("Enable Bluetooth connection popup")
            checked: Config.options.bar.tooltips.enableBluetoothConnectionPopup
            onCheckedChanged: {
                Config.options.bar.tooltips.enableBluetoothConnectionPopup = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "keyboard"
            text: Translation.tr("Enable keyboard layout transition popup")
            checked: Config.options.bar.tooltips.enableKeyboardLayoutTransitionPopup
            onCheckedChanged: {
                Config.options.bar.tooltips.enableKeyboardLayoutTransitionPopup = checked;
            }
        }
    }

    ContentSection {
        id: resourcesConfig
        icon: "memory"
        title: Translation.tr("Resources")

        ConfigSwitch {
            buttonIcon: "percent"
            text: Translation.tr("Show percentage text")
            checked: Config.options.bar.resources.showPercentageText
            onCheckedChanged: {
                Config.options.bar.resources.showPercentageText = checked;
            }
        }

        ConfigRow {
            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("RAM")
                checked: Config.options.bar.resources.alwaysShowRam
                onCheckedChanged: Config.options.bar.resources.alwaysShowRam = checked
            }
            ConfigSwitch {
                buttonIcon: "planner_review"
                text: Translation.tr("CPU")
                checked: Config.options.bar.resources.alwaysShowCpu
                onCheckedChanged: Config.options.bar.resources.alwaysShowCpu = checked
            }
        }
        ConfigRow {
            ConfigSwitch {
                buttonIcon: "thermostat"
                text: Translation.tr("Temp")
                checked: Config.options.bar.resources.alwaysShowCpuTemp
                onCheckedChanged: Config.options.bar.resources.alwaysShowCpuTemp = checked
            }
            ConfigSwitch {
                buttonIcon: "hard_drive"
                text: Translation.tr("Disk")
                checked: Config.options.bar.resources.alwaysShowDisk
                onCheckedChanged: Config.options.bar.resources.alwaysShowDisk = checked
            }
        }
        ConfigSwitch {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Swap")
            checked: Config.options.bar.resources.alwaysShowSwap
            onCheckedChanged: Config.options.bar.resources.alwaysShowSwap = checked
        }
        ConfigSwitch {
            buttonIcon: "dns"
            text: Translation.tr("Docker")
            checked: Config.options.bar.resources.showDocker
            onCheckedChanged: Config.options.bar.resources.showDocker = checked
        }
    }

    ContentSection {
        id: sportsConfig
        icon: "sports_soccer"
        title: Translation.tr("Sports")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable sports tracker")
            checked: Config.options.bar.sports.enable
            onCheckedChanged: {
                Config.options.bar.sports.enable = checked;
            }
        }

        function isSportFollowed(sportName) {
            let list = Config.options.bar.sports.monitoredLeagues || [];
            return list.some(l => l.sport === sportName && l.enabled);
        }

        function toggleSport(sportName, enable) {
            let list = JSON.parse(JSON.stringify(Config.options.bar.sports.monitoredLeagues || []));
            let hasMatch = false;
            list.forEach(l => {
                if (l.sport === sportName) {
                    l.enabled = enable;
                    hasMatch = true;
                }
            });
            if (enable && !hasMatch) {
                let presets = [
                    {
                        sport: "soccer",
                        league: "bra.1",
                        name: "Brasileirão",
                        enabled: true
                    },
                    {
                        sport: "basketball",
                        league: "nba",
                        name: "NBA",
                        enabled: true
                    },
                    {
                        sport: "football",
                        league: "nfl",
                        name: "NFL",
                        enabled: true
                    },
                    {
                        sport: "racing",
                        league: "f1",
                        name: "Formula 1",
                        enabled: true
                    },
                    {
                        sport: "hockey",
                        league: "nhl",
                        name: "NHL",
                        enabled: true
                    },
                    {
                        sport: "baseball",
                        league: "mlb",
                        name: "MLB",
                        enabled: true
                    }
                ];
                let defaultPreset = presets.find(p => p.sport === sportName);
                if (defaultPreset) {
                    list.push(defaultPreset);
                }
            }
            Config.options.bar.sports.monitoredLeagues = list;
        }

        function getUniqueSports() {
            let list = Config.options.bar.sports.monitoredLeagues || [];
            let sports = [];
            list.forEach(l => {
                if (sports.indexOf(l.sport) === -1) {
                    sports.push(l.sport);
                }
            });
            let defaults = ["soccer", "basketball", "football", "racing", "hockey", "baseball"];
            defaults.forEach(d => {
                if (sports.indexOf(d) === -1) {
                    sports.push(d);
                }
            });
            return sports;
        }

        function getLeaguesForSport(sportName) {
            let list = Config.options.bar.sports.monitoredLeagues || [];
            return list.filter(l => l.sport === sportName);
        }

        ContentSubsection {
            title: Translation.tr("Monitored Sports")
            Layout.fillWidth: true

            Flow {
                Layout.fillWidth: true
                spacing: 8
                topPadding: 4
                bottomPadding: 4

                Repeater {
                    model: sportsConfig.getUniqueSports()
                    delegate: LeagueChip {
                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        checked: sportsConfig.isSportFollowed(modelData)
                        onToggled: c => sportsConfig.toggleSport(modelData, c)
                    }
                }
            }
        }

        Repeater {
            model: sportsConfig.getUniqueSports()
            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                visible: {
                    let sportKey = modelData;
                    let followed = sportsConfig.isSportFollowed(sportKey);
                    let leagues = sportsConfig.getLeaguesForSport(sportKey);
                    return followed && leagues.length > 1;
                }

                ContentSubsection {
                    title: {
                        let displayName = modelData.charAt(0).toUpperCase() + modelData.slice(1);
                        return displayName + " " + Translation.tr("Leagues");
                    }
                    Layout.fillWidth: true

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        topPadding: 4
                        bottomPadding: 4

                        Repeater {
                            model: sportsConfig.getLeaguesForSport(modelData)
                            delegate: LeagueChip {
                                text: modelData.name
                                checked: modelData.enabled
                                onToggled: c => {
                                    let list = JSON.parse(JSON.stringify(Config.options.bar.sports.monitoredLeagues));
                                    let indexInMain = list.findIndex(l => l.league === modelData.league && l.sport === modelData.sport);
                                    if (indexInMain !== -1) {
                                        list[indexInMain].enabled = c;
                                        Config.options.bar.sports.monitoredLeagues = list;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Add Preset League")
            Layout.fillWidth: true

            Flow {
                Layout.fillWidth: true
                spacing: 8

                property var presets: [
                    {
                        sport: "soccer",
                        league: "bra.1",
                        name: "Brasileirão"
                    },
                    {
                        sport: "soccer",
                        league: "eng.1",
                        name: "Premier League"
                    },
                    {
                        sport: "soccer",
                        league: "uefa.champions",
                        name: "Champions League"
                    },
                    {
                        sport: "soccer",
                        league: "ger.1",
                        name: "Bundesliga"
                    },
                    {
                        sport: "soccer",
                        league: "esp.1",
                        name: "LaLiga"
                    },
                    {
                        sport: "soccer",
                        league: "conmebol.libertadores",
                        name: "Libertadores"
                    },
                    {
                        sport: "basketball",
                        league: "nba",
                        name: "NBA"
                    },
                    {
                        sport: "football",
                        league: "nfl",
                        name: "NFL"
                    },
                    {
                        sport: "racing",
                        league: "f1",
                        name: "Formula 1"
                    },
                    {
                        sport: "hockey",
                        league: "nhl",
                        name: "NHL"
                    },
                    {
                        sport: "baseball",
                        league: "mlb",
                        name: "MLB"
                    }
                ]

                Repeater {
                    model: parent.presets
                    delegate: RippleButton {
                        buttonText: "+ " + modelData.name
                        enabled: {
                            let list = Config.options.bar.sports.monitoredLeagues || [];
                            return !list.some(l => l.league === modelData.league && l.sport === modelData.sport);
                        }
                        onClicked: {
                            let list = JSON.parse(JSON.stringify(Config.options.bar.sports.monitoredLeagues || []));
                            list.push({
                                sport: modelData.sport,
                                league: modelData.league,
                                name: modelData.name,
                                enabled: true
                            });
                            Config.options.bar.sports.monitoredLeagues = list;
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Add Custom League")
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: newSportInput
                        Layout.preferredWidth: 100
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Sport (e.g. soccer)")
                    }

                    MaterialTextField {
                        id: newLeagueInput
                        Layout.preferredWidth: 100
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("League (e.g. f1)")
                    }

                    MaterialTextField {
                        id: newNameInput
                        Layout.preferredWidth: 100
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Name (e.g. F1)")
                    }
                }

                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignRight
                    materialIcon: "add"
                    mainText: Translation.tr("Add Custom League")
                    enabled: newSportInput.text.trim() !== "" && newLeagueInput.text.trim() !== "" && newNameInput.text.trim() !== ""
                    onClicked: {
                        let list = JSON.parse(JSON.stringify(Config.options.bar.sports.monitoredLeagues || []));
                        list.push({
                            sport: newSportInput.text.trim().toLowerCase(),
                            league: newLeagueInput.text.trim().toLowerCase(),
                            name: newNameInput.text.trim(),
                            enabled: true
                        });
                        Config.options.bar.sports.monitoredLeagues = list;
                        newSportInput.text = "";
                        newLeagueInput.text = "";
                        newNameInput.text = "";
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Team Filter")
            tooltip: Translation.tr("Comma-separated list of teams to show (e.g. Real Madrid, Arsenal)")
            Layout.fillWidth: true

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Filter by team name...")
                text: Config.options.bar.sports.teamFilter
                onTextChanged: Config.options.bar.sports.teamFilter = text
            }
        }

        ContentSubsection {
            title: Translation.tr("Preferences")
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "av_timer"
                    text: Translation.tr("Update Interval (s)")
                    value: Config.options.bar.sports.updateInterval
                    from: 10
                    to: 600
                    stepSize: 10
                    onValueChanged: {
                        Config.options.bar.sports.updateInterval = value;
                    }
                }
                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "layers"
                    text: Translation.tr("Max cards in popup")
                    value: Config.options.bar.sports.maxCardsPopup
                    from: 1
                    to: 15
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.sports.maxCardsPopup = value;
                    }
                }
                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "schedule"
                    text: Translation.tr("Show matches before (hours)")
                    value: Config.options.bar.sports.showBeforeHours
                    from: 1
                    to: 72
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.sports.showBeforeHours = value;
                    }
                }
                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "history"
                    text: Translation.tr("Keep ended matches for (mins)")
                    value: Config.options.bar.sports.showAfterMinutes
                    from: 0
                    to: 1440
                    stepSize: 30
                    onValueChanged: {
                        Config.options.bar.sports.showAfterMinutes = value;
                    }
                }
            }
        }
    }

    ContentSection {
        id: policiesConfig
        icon: "policy"
        title: Translation.tr("Policies Panel Button")

        ContentSubsection {
            title: Translation.tr("Preset icons")
            tooltip: Translation.tr("Choose from a list of predefined SVG icons for the policies panel button")
            ConfigSelectionArray {
                currentValue: Config.options.bar.useMaterialSymbolForTopLeftIcon ? "" : Config.options.bar.topLeftIcon
                onSelected: newValue => {
                    Config.options.bar.topLeftIcon = newValue;
                    Config.options.bar.useMaterialSymbolForTopLeftIcon = false;
                }
                options: [
                    {
                        displayName: Translation.tr("System Distro"),
                        value: "distro"
                    },
                    {
                        displayName: Translation.tr("Spark"),
                        value: "spark"
                    },
                    {
                        displayName: Translation.tr("Arch Linux"),
                        value: "arch"
                    },
                    {
                        displayName: Translation.tr("Debian"),
                        value: "debian"
                    },
                    {
                        displayName: Translation.tr("Fedora"),
                        value: "fedora"
                    },
                    {
                        displayName: Translation.tr("Ubuntu"),
                        value: "ubuntu"
                    },
                    {
                        displayName: Translation.tr("Gentoo"),
                        value: "gentoo"
                    },
                    {
                        displayName: Translation.tr("NixOS"),
                        value: "nixos"
                    },
                    {
                        displayName: Translation.tr("CachyOS"),
                        value: "cachyos"
                    },
                    {
                        displayName: Translation.tr("EndeavourOS"),
                        value: "endeavouros"
                    },
                    {
                        displayName: Translation.tr("Nyarch"),
                        value: "nyarch"
                    },
                    {
                        displayName: Translation.tr("Linux Generic"),
                        value: "linux"
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Custom Material Symbol Icon")
            tooltip: Translation.tr("Type a Material Symbol name to use as a custom icon (e.g. policy, shield, fingerprint, home)")

            MaterialTextField {
                id: customMaterialSymbolField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Type a MaterialSymbol name...")

                Component.onCompleted: {
                    text = Config.options.bar.useMaterialSymbolForTopLeftIcon ? Config.options.bar.topLeftIcon : "";
                }

                Connections {
                    target: Config.options.bar
                    function onTopLeftIconChanged() {
                        customMaterialSymbolField.text = Config.options.bar.useMaterialSymbolForTopLeftIcon ? Config.options.bar.topLeftIcon : "";
                    }
                    function onUseMaterialSymbolForTopLeftIconChanged() {
                        customMaterialSymbolField.text = Config.options.bar.useMaterialSymbolForTopLeftIcon ? Config.options.bar.topLeftIcon : "";
                    }
                }

                onTextChanged: {
                    var val = text.trim();
                    if (val !== "" && activeFocus) {
                        Config.options.bar.topLeftIcon = val;
                        Config.options.bar.useMaterialSymbolForTopLeftIcon = true;
                    }
                }
            }
        }
    }

    ContentSection {
        id: dashboardButtonConfig
        icon: "dashboard"
        title: Translation.tr("Dashboard button")

        ContentSubsection {
            title: Translation.tr("Visible status indicators")
            tooltip: Translation.tr("Toggle which status indicators to show on the dashboard panel button")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Volume")
                    checked: Config.options.bar.dashboardButton.showVolume
                    onCheckedChanged: {
                        Config.options.bar.dashboardButton.showVolume = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "mic"
                    text: Translation.tr("Microphone")
                    checked: Config.options.bar.dashboardButton.showMic
                    onCheckedChanged: {
                        Config.options.bar.dashboardButton.showMic = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "wifi"
                    text: Translation.tr("Network")
                    checked: Config.options.bar.dashboardButton.showNetwork
                    onCheckedChanged: {
                        Config.options.bar.dashboardButton.showNetwork = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "bluetooth"
                    text: Translation.tr("Bluetooth")
                    checked: Config.options.bar.dashboardButton.showBluetooth
                    onCheckedChanged: {
                        Config.options.bar.dashboardButton.showBluetooth = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Notifications")
                    checked: Config.options.bar.dashboardButton.showNotifications
                    onCheckedChanged: {
                        Config.options.bar.dashboardButton.showNotifications = checked;
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    component LeagueChip: Rectangle {
        property string text
        property bool checked: false
        signal toggled(bool checked)
        width: chipText.implicitWidth + 32
        height: 36
        radius: Appearance.rounding.full

        HoverHandler {
            id: chipHover
            cursorShape: Qt.PointingHandCursor
        }

        color: checked ? (chipHover.hovered ? Qt.lighter(Appearance.colors.colPrimary, 1.15) : Appearance.colors.colPrimary) : (chipHover.hovered ? Appearance.colors.colSurfaceContainerHigh : Appearance.colors.colSurfaceContainerHighest)

        border.width: checked ? 0 : 1
        border.color: Appearance.colors.colOutlineVariant

        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: parent.text
            color: parent.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
        }

        MouseArea {
            anchors.fill: parent
            onClicked: parent.toggled(!parent.checked)
            cursorShape: Qt.PointingHandCursor
        }

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
    }
}
