import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    function openComponentPage(componentId) {
        const compInfo = BarComponentRegistry.getComponent(componentId);
        if (!compInfo) return;

        var p = root.parent;
        while (p) {
            if (typeof p.activeSubPage !== "undefined") {
                if (compInfo.configPage) {
                    p.activeSubPage = Qt.resolvedUrl(compInfo.configPage);
                    return;
                } else if (compInfo.pageId) {
                    var win = root.QsWindow.window;
                    if (win && win.pageIndexById) {
                        win.currentPage = win.pageIndexById(compInfo.pageId);
                        p.activeSubPage = "";
                        return;
                    }
                }
            }
            p = p.parent;
        }
    }

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Widgets & Waffle Settings")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Bar Widgets Section ───────────────────────────────────────────────
    ContentSection {
        id: widgetsSection
        icon: "widgets"
        title: Translation.tr("Bar Widgets")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Settings for individual widgets that sit on the status bar, organized by category.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        // Group 1: Navigation & Windows (Blue Pair)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ServiceCard {
                cardIcon: "workspaces"
                cardShape: "Circle"
                cardHue: 210
                title: Translation.tr("Workspaces")
                description: Translation.tr("Workspaces style, minimal mode, dock mode, and compaction")
                onOpenCard: root.openComponentPage("workspaces")
            }

            ServiceCard {
                cardIcon: "search"
                cardShape: "SoftBurst"
                cardHue: 210
                title: Translation.tr("Search")
                description: Translation.tr("Launcher button style, width, colour treatment, and shortcut hint")
                onOpenCard: root.openComponentPage("search")
            }

            ServiceCard {
                cardIcon: "label"
                cardShape: "Circle"
                cardHue: 210
                title: Translation.tr("Active Window")
                description: Translation.tr("Window title truncation, app icons, and titlebar styling")
                onOpenCard: root.openComponentPage("active_window")
            }

            ServiceCard {
                cardIcon: "apps"
                cardShape: "Circle"
                cardHue: 210
                title: Translation.tr("Dock to Panel")
                description: Translation.tr("Embedded panel app launcher and dock integration settings")
                onOpenCard: root.openComponentPage("dock_to_panel")
            }
        }

        Item { Layout.preferredHeight: 12 }

        // Group 2: System Controls & Privacy (Purple Pair)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ServiceCard {
                cardIcon: "notifications"
                cardShape: "Circle"
                cardHue: 280
                title: Translation.tr("Dashboard Panel Button")
                description: Translation.tr("Quick settings trigger, notification badge, and style options")
                onOpenCard: root.openComponentPage("dashboard_panel_button")
            }

            ServiceCard {
                cardIcon: "power_settings_new"
                cardShape: "Circle"
                cardHue: 280
                title: Translation.tr("Power Button")
                description: Translation.tr("Session controls, power menu, reboot, and suspend actions")
                onOpenCard: root.openComponentPage("power")
            }

            ServiceCard {
                cardIcon: "star"
                cardShape: "Circle"
                cardHue: 280
                title: Translation.tr("Policies Panel Button")
                description: Translation.tr("Privacy controls, content filtering, and work safety policies")
                onOpenCard: root.openComponentPage("policies_panel_button")
            }
        }

        Item { Layout.preferredHeight: 12 }

        // Group 3: Time, Calendar & Weather (Orange Pair)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ServiceCard {
                cardIcon: "nest_clock_farsight_analog"
                cardShape: "Sunny"
                cardHue: 35
                title: Translation.tr("Clock")
                description: Translation.tr("Neural and Relief clock designs, die-cut variants, and colour treatment")
                onOpenCard: root.openComponentPage("clock")
            }

            ServiceCard {
                cardIcon: "date_range"
                cardShape: "Cookie9Sided"
                cardHue: 35
                title: Translation.tr("Date")
                description: Translation.tr("Expressive and Neural date designs, variants, colour treatment, and capitals")
                onOpenCard: root.openComponentPage("date")
            }

            ServiceCard {
                cardIcon: "timer"
                cardShape: "Circle"
                cardHue: 35
                title: Translation.tr("Timer & Pomodoro")
                description: Translation.tr("Focus timer, break intervals, countdowns, and sound alerts")
                onOpenCard: root.openComponentPage("timer")
            }

            ServiceCard {
                cardIcon: "weather_mix"
                cardShape: "Circle"
                cardHue: 35
                title: Translation.tr("Weather")
                description: Translation.tr("Compact Horizon and Tessera designs, visual variants, colours, and weather service")
                onOpenCard: root.openComponentPage("weather")
            }
        }

        Item { Layout.preferredHeight: 12 }

        // Group 4: Media & Entertainment (Pink Pair)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ServiceCard {
                cardIcon: "music_note"
                cardShape: "Circle"
                cardHue: 320
                title: Translation.tr("Music Player")
                description: Translation.tr("Media controls, album art, lyrics, and visualizer styles")
                onOpenCard: root.openComponentPage("music_player")
            }

            ServiceCard {
                cardIcon: "sports_soccer"
                cardShape: "Circle"
                cardHue: 320
                title: Translation.tr("Sports")
                description: Translation.tr("Live sports score ticker, team tracking, and match updates")
                onOpenCard: root.openComponentPage("sports")
            }
        }

        Item { Layout.preferredHeight: 12 }

        // Group 5: System Resources & Hardware (Green Pair)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ServiceCard {
                cardIcon: "monitor_heart"
                cardShape: "Circle"
                cardHue: 140
                title: Translation.tr("System Monitor")
                description: Translation.tr("CPU, RAM, disk, and network usage gauges and graphs")
                onOpenCard: root.openComponentPage("system_monitor")
            }

            ServiceCard {
                cardIcon: "neurology"
                cardShape: "Circle"
                cardHue: 165
                title: Translation.tr("AI Plan Usage")
                description: Translation.tr("ChatGPT, Claude, and Antigravity plan quotas and bar gauges")
                onOpenCard: root.openComponentPage("ai_plan_usage")
            }

            ServiceCard {
                cardIcon: "shield_lock"
                cardShape: "Circle"
                cardHue: 100
                title: Translation.tr("Privacy pill")
                description: Translation.tr("Android-style indicator for camera, microphone, screen and location access")
                onOpenCard: root.openComponentPage("privacy_pill")
            }

            ServiceCard {
                cardIcon: "lan"
                cardShape: "Circle"
                cardHue: 140
                title: Translation.tr("Port Watcher")
                description: Translation.tr("Listening ports, live connections, exposure filters, and process actions")
                onOpenCard: root.openComponentPage("port_watcher")
            }

            ServiceCard {
                cardIcon: "battery_android_6"
                cardShape: "Circle"
                cardHue: 140
                title: Translation.tr("Battery")
                description: Translation.tr("Battery percentage, power profiles, and low charge alerts")
                onOpenCard: root.openComponentPage("battery")
            }
        }

        Item { Layout.preferredHeight: 12 }

        // Group 6: Input, Connectivity & Tray (Blue Pair)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ServiceCard {
                cardIcon: "bluetooth_connected"
                cardShape: "Circle"
                cardHue: 210
                title: Translation.tr("Bluetooth Devices")
                description: Translation.tr("Bluetooth quick connect, device battery list, and popups")
                onOpenCard: root.openComponentPage("bluetooth_devices")
            }

            ServiceCard {
                cardIcon: "keyboard"
                cardShape: "Circle"
                cardHue: 210
                title: Translation.tr("Keyboard Layout")
                description: Translation.tr("Input source switcher, layout transition popups, and badges")
                onOpenCard: root.openComponentPage("keyboard_layout")
            }

            ServiceCard {
                cardIcon: "build"
                cardShape: "Circle"
                cardHue: 210
                title: Translation.tr("Utility Buttons")
                description: Translation.tr("Quick action buttons: screenshot, color picker, and shortcuts")
                onOpenCard: root.openComponentPage("utility_buttons")
            }

            ServiceCard {
                cardIcon: "system_update_alt"
                cardShape: "Circle"
                cardHue: 210
                title: Translation.tr("System Tray")
                description: Translation.tr("System tray icon sizes, item filtering, and overflow behavior")
                onOpenCard: root.openComponentPage("system_tray")
            }
        }

        Item { Layout.preferredHeight: 12 }

        // Group 7: Status Indicators & Phone (Purple Pair)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ServiceCard {
                cardIcon: "screen_record"
                cardShape: "Circle"
                cardHue: 280
                title: Translation.tr("Record Indicator")
                description: Translation.tr("Screen recording status, active recorder control, and snip tools")
                onOpenCard: root.openComponentPage("record_indicator")
            }

            ServiceCard {
                cardIcon: "screen_share"
                cardShape: "Circle"
                cardHue: 280
                title: Translation.tr("Screen Share Indicator")
                description: Translation.tr("Active screen sharing status indicator and portal warning")
                onOpenCard: root.openComponentPage("screen_share_indicator")
            }

            ServiceCard {
                cardIcon: "smart_display"
                cardShape: "Circle"
                cardHue: 280
                title: Translation.tr("Phone Indicator")
                description: Translation.tr("Wireless debugging, phone screen mirroring, and scrcpy status")
                onOpenCard: root.openComponentPage("phone_scrcpy_indicator")
            }

            ServiceCard {
                cardIcon: "tune"
                cardShape: "Circle"
                cardHue: 280
                title: Translation.tr("Mode Indicator")
                description: Translation.tr("The active mode's name and colour; hidden while no mode is on")
                onOpenCard: root.openComponentPage("mode_indicator")
            }
        }
    }

    // ── Waffle Tweaks Section ──────────────────────────────────────────────
    ContentSection {
        icon: "grid_view"
        title: Translation.tr("Waffle Tweaks")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "align_horizontal_center"
                text: Translation.tr("Fix switch handle position")
                checked: Config.options.waffles.tweaks.switchHandlePositionFix
                onCheckedChanged: {
                    Config.options.waffles.tweaks.switchHandlePositionFix = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("Smoother menu animations")
                checked: Config.options.waffles.tweaks.smootherMenuAnimations
                onCheckedChanged: {
                    Config.options.waffles.tweaks.smootherMenuAnimations = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "search"
                text: Translation.tr("Smoother search bar")
                checked: Config.options.waffles.tweaks.smootherSearchBar
                onCheckedChanged: {
                    Config.options.waffles.tweaks.smootherSearchBar = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Force 2-character day of week on calendar")
                checked: Config.options.waffles.calendar.force2CharDayOfWeek
                onCheckedChanged: {
                    Config.options.waffles.calendar.force2CharDayOfWeek = checked;
                }
            }
        }
    }
}
