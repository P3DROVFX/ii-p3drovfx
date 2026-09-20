import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Every island activity in one page, grouped by how it behaves on the island:
 * announcements flash and leave, live activities stay while they run, side
 * glances sit beside the clock on the resting face, and the system pair owns
 * popups elsewhere in the shell.
 *
 * All of them are plain switches. The per-widget contracted-height sliders this
 * page used to carry are gone (config v25): the faces that genuinely need more
 * than a pill declare their height in IslandRegistry, and every other slider
 * sat below the pill height where it could do nothing.
 */
Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property bool islandOn: Config.options.bar.floatingNotch.enable
        || Config.options.bar.floatingNotch.centerInBar

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Island Activities & Glances")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Announcements ─────────────────────────────────────────────────────
        ContentSection {
            icon: "campaign"
            title: Translation.tr("Announcements")
            tooltip: Translation.tr("Notches that flash when something happens and leave after a moment.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "tab"
                    text: Translation.tr("Workspaces")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableWorkspaces
                    onCheckedChanged: Config.options.bar.floatingNotch.disableWorkspaces = !checked
                    StyledToolTip { text: Translation.tr("Show the workspace strip when the workspace changes") }
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Keyboard layout")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableKeyboard
                    onCheckedChanged: Config.options.bar.floatingNotch.disableKeyboard = !checked
                    StyledToolTip { text: Translation.tr("Show the layout switcher when the keyboard layout changes") }
                }

                ConfigSwitch {
                    buttonIcon: "wifi"
                    text: Translation.tr("Wi-Fi")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableWifi
                    onCheckedChanged: Config.options.bar.floatingNotch.disableWifi = !checked
                    StyledToolTip { text: Translation.tr("Show the network name when Wi-Fi connects") }
                }

                ConfigSwitch {
                    buttonIcon: "bluetooth"
                    text: Translation.tr("Bluetooth")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableBluetooth
                    onCheckedChanged: Config.options.bar.floatingNotch.disableBluetooth = !checked
                    StyledToolTip { text: Translation.tr("Show the device and its battery when Bluetooth connects. Off hands the connection popup back to the bar") }
                }

                ConfigSwitch {
                    buttonIcon: "battery_charging_full"
                    text: Translation.tr("Battery charging")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableBattery
                    onCheckedChanged: Config.options.bar.floatingNotch.disableBattery = !checked
                    StyledToolTip { text: Translation.tr("Show the charging status when the charger is plugged in") }
                }

                ConfigSwitch {
                    buttonIcon: "content_paste"
                    text: Translation.tr("Clipboard")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableClipboard
                    onCheckedChanged: Config.options.bar.floatingNotch.disableClipboard = !checked
                    StyledToolTip { text: Translation.tr("Show a new clipboard entry as it is copied") }
                }
            }
        }

        // ── Live activities ───────────────────────────────────────────────────
        ContentSection {
            icon: "bolt"
            title: Translation.tr("Live activities")
            tooltip: Translation.tr("Faces that stay on the island for exactly as long as the thing is happening.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr("Media")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableMedia
                    onCheckedChanged: Config.options.bar.floatingNotch.disableMedia = !checked
                    StyledToolTip { text: Translation.tr("Show the playing track, its cover and the visualizer") }
                }

                ConfigSwitch {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("AI agent status")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableAiStatus
                    onCheckedChanged: Config.options.bar.floatingNotch.disableAiStatus = !checked
                    StyledToolTip { text: Translation.tr("Show agents working, waiting or finished") }
                }

                ConfigSwitch {
                    buttonIcon: "timer"
                    text: Translation.tr("Timer & stopwatch")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableTimer
                    onCheckedChanged: Config.options.bar.floatingNotch.disableTimer = !checked
                    StyledToolTip { text: Translation.tr("Show a running Pomodoro, countdown or stopwatch") }
                }

                ConfigSwitch {
                    buttonIcon: "screen_record"
                    text: Translation.tr("Screen recording")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableRecording
                    onCheckedChanged: Config.options.bar.floatingNotch.disableRecording = !checked
                    StyledToolTip { text: Translation.tr("Show the recording indicator while the screen is captured") }
                }

                ConfigSwitch {
                    buttonIcon: "mic"
                    text: Translation.tr("Dictation")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableDictation
                    onCheckedChanged: Config.options.bar.floatingNotch.disableDictation = !checked
                    StyledToolTip { text: Translation.tr("Show the waveform while dictating") }
                }

                ConfigSwitch {
                    buttonIcon: "progress_activity"
                    text: Translation.tr("Live progress")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableProgress
                    onCheckedChanged: Config.options.bar.floatingNotch.disableProgress = !checked
                    StyledToolTip { text: Translation.tr("Show background transfers and builds while they run") }
                }

                ConfigSwitch {
                    buttonIcon: "share"
                    text: Translation.tr("LocalSend sharing")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableLocalSend
                    onCheckedChanged: Config.options.bar.floatingNotch.disableLocalSend = !checked
                    StyledToolTip { text: Translation.tr("The drop target, transfers and the incoming request card. Off hands them back to the floating popups") }
                }

                ConfigSwitch {
                    buttonIcon: "tune"
                    text: Translation.tr("Modes & Routines")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableMode
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.disableMode = !checked;
                        if (Config.options.dynamicIsland?.widgets?.mode)
                            Config.options.dynamicIsland.widgets.mode.enable = checked;
                    }
                    StyledToolTip { text: Translation.tr("Show the active mode beside the clock and as an auxiliary bubble") }
                }
            }
        }

        // ── Side glances ──────────────────────────────────────────────────────
        ContentSection {
            icon: "visibility"
            title: Translation.tr("Side glances")
            tooltip: Translation.tr("Small always-on widgets that sit beside the clock on the resting island. Off by default.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "headphones"
                    text: Translation.tr("Earbuds battery")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableEarbuds
                    onCheckedChanged: Config.options.bar.floatingNotch.disableEarbuds = !checked
                    StyledToolTip { text: Translation.tr("The connected headset's battery beside the clock, with the device picture from Settings → Bluetooth device images when it has one") }
                }

                ConfigSwitch {
                    buttonIcon: "partly_cloudy_day"
                    text: Translation.tr("Weather")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableWeather
                    onCheckedChanged: Config.options.bar.floatingNotch.disableWeather = !checked
                    StyledToolTip { text: Translation.tr("The weather icon and temperature beside the clock, kept fresh on the service's fetch interval") }
                }
            }
        }

        // ── System ────────────────────────────────────────────────────────────
        ContentSection {
            icon: "settings"
            title: Translation.tr("System notches")
            tooltip: Translation.tr("Notifications and volume/brightness feedback inside the island. Turning one off hands it back to its own surface.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Notifications")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableNotification
                    onCheckedChanged: Config.options.bar.floatingNotch.disableNotification = !checked
                    StyledToolTip { text: Translation.tr("Incoming notifications open inside the island instead of as floating toasts") }
                }

                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("OSD")
                    visible: root.islandOn
                    checked: !Config.options.bar.floatingNotch.disableOsd
                    onCheckedChanged: Config.options.bar.floatingNotch.disableOsd = !checked
                    StyledToolTip { text: Translation.tr("Volume, brightness and input feedback inside the island instead of the floating indicators") }
                }
            }
        }
    }
}
