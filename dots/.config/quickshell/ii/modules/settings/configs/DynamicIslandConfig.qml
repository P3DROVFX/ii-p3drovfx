import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: dynamicIslandConfigRoot
    forceWidth: false

    NoticeBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        isFirst: true
        materialIcon: "warning"
        text: Translation.tr("The Floating Dynamic Island only works when the Bar is in Vertical mode.")

        RippleButtonWithIcon {
            buttonRadius: Appearance.rounding.small
            materialIcon: "arrow_forward"
            mainText: Translation.tr("Go to Bar Position")
            onClicked: {
                var win = dynamicIslandConfigRoot.QsWindow.window;
                if (win && win.currentPage !== undefined) {
                    win.pendingSectionHighlight = Translation.tr("Positioning");
                    win.currentPage = 1; // Bar Config page index
                }
            }
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
        }
    }

        ContentSection {
            icon: "water_drop"
            title: Translation.tr("Floating Dynamic Island")

            ConfigSwitch {
                buttonIcon: "water_drop"
                text: Translation.tr("Floating Dynamic Island")
                checked: Config.options.bar.floatingNotch.enable
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Enables an independent, floating Dynamic Island at the top of the screen")
                }
            }

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Always hide floating island")
                visible: Config.options.bar.floatingNotch.enable
                checked: Config.options.bar.floatingNotch.autoHide
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.autoHide = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Hides the island at the top of the screen, revealing it on hover")
                }
            }

            ConfigSwitch {
                buttonIcon: "filter_drama"
                text: Translation.tr("Floating Island drop-shadow")
                visible: Config.options.bar.floatingNotch.enable
                checked: Config.options.bar.floatingNotch.dropShadow
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.dropShadow = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Shows a drop shadow underneath the floating island")
                }
            }

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Only show island on single monitor")
                visible: Config.options.bar.floatingNotch.enable
                checked: Config.options.bar.floatingNotch.onlyShowOnSingleMonitor
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.onlyShowOnSingleMonitor = checked;
                    if (checked && Config.options.bar.floatingNotch.singleMonitorName === "" && Quickshell.screens.length > 0) {
                        Config.options.bar.floatingNotch.singleMonitorName = Quickshell.screens[0].name;
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Display the dynamic island on only one chosen monitor instead of following focus")
                }
            }

            ContentSubsection {
                title: Translation.tr("Selected Monitor")
                icon: "settings_input_hdmi"
                visible: Config.options.bar.floatingNotch.enable && Config.options.bar.floatingNotch.onlyShowOnSingleMonitor

                ConfigSelectionArray {
                    currentValue: Config.options.bar.floatingNotch.singleMonitorName
                    onSelected: newValue => {
                        Config.options.bar.floatingNotch.singleMonitorName = newValue;
                    }
                    options: {
                        let list = [];
                        for (let i = 0; i < Quickshell.screens.length; i++) {
                            let name = Quickshell.screens[i].name;
                            list.push({ displayName: name, icon: "desktop_windows", value: name });
                        }
                        return list;
                    }
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Workspaces Group ---
            ConfigSwitch {
                buttonIcon: "tab"
                text: Translation.tr("Workspaces Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableWorkspaces
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableWorkspaces = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the workspaces notch notification on workspace changes") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Workspaces contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableWorkspaces
                value: Config.options.bar.floatingNotch.heightWorkspaces
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightWorkspaces = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Keyboard Group ---
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Keyboard Layout Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableKeyboard
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableKeyboard = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the keyboard layout switcher notch notification on layout changes") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Keyboard Layout contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableKeyboard
                value: Config.options.bar.floatingNotch.heightKeyboard
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightKeyboard = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Wi-Fi Group ---
            ConfigSwitch {
                buttonIcon: "wifi"
                text: Translation.tr("Wi-Fi Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableWifi
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableWifi = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the Wi-Fi status notch notification") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Wi-Fi contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableWifi
                value: Config.options.bar.floatingNotch.heightWifi
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightWifi = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Bluetooth Group ---
            ConfigSwitch {
                buttonIcon: "bluetooth"
                text: Translation.tr("Bluetooth Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableBluetooth
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableBluetooth = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the Bluetooth connection status notch notification") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Bluetooth contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableBluetooth
                value: Config.options.bar.floatingNotch.heightBluetooth
                from: 24
                to: 88
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightBluetooth = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Media Group ---
            ConfigSwitch {
                buttonIcon: "play_circle"
                text: Translation.tr("Media Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableMedia
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableMedia = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the Media Player status notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Media contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableMedia
                value: Config.options.bar.floatingNotch.heightMedia
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightMedia = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Notification Group ---
            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Notification Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableNotification
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableNotification = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the notification popups inside the notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Notification contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableNotification
                value: Config.options.bar.floatingNotch.heightNotification
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightNotification = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Volume OSD Group ---
            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("OSD Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableOsd
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableOsd = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the volume/brightness OSD inside the notch") }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Screen Recording Group ---
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Screen Recording Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableRecording
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableRecording = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the screen recording indicator notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Screen Recording contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableRecording
                value: Config.options.bar.floatingNotch.heightRecording
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightRecording = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Timer/Stopwatch Group ---
            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Timer/Stopwatch Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableTimer
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableTimer = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the Pomodoro/Stopwatch timer notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Timer/Stopwatch contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableTimer
                value: Config.options.bar.floatingNotch.heightTimer
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightTimer = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Clipboard Group ---
            ConfigSwitch {
                buttonIcon: "assignment"
                text: Translation.tr("Clipboard Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableClipboard
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableClipboard = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the clipboard history notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Clipboard contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableClipboard
                value: Config.options.bar.floatingNotch.heightClipboard
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightClipboard = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- LocalSend Group ---
            ConfigSwitch {
                buttonIcon: "share"
                text: Translation.tr("LocalSend Share Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableLocalSend
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableLocalSend = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the LocalSend files sharing and receiving notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("LocalSend contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableLocalSend
                value: Config.options.bar.floatingNotch.heightLocalSend
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightLocalSend = value;
                }
            }
            ConfigSwitch {
                buttonIcon: "smartphone"
                text: Translation.tr("KDE Connect column in drag panel")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableLocalSend
                checked: !Config.options.bar.floatingNotch.disableKdeConnectInLocalSend
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableKdeConnectInLocalSend = !checked;
                }
                StyledToolTip { text: Translation.tr("Show the KDE Connect drop column alongside LocalSend when dragging files into the notch") }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Checklist Group ---
            ConfigSwitch {
                buttonIcon: "playlist_add_check"
                text: Translation.tr("Checklist Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableChecklist
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableChecklist = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the checklist notch") }
            }
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Checklist always visible (Contracted)")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableChecklist
                checked: Config.options.bar.floatingNotch.checklistAlwaysVisible
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.checklistAlwaysVisible = checked;
                    if (checked) {
                        Config.options.bar.floatingNotch.checklistOnlyExpanded = false;
                    }
                }
                StyledToolTip { text: Translation.tr("Make checklist always visible on the dynamic island, even when contracted and idle") }
            }
            ConfigSwitch {
                buttonIcon: "open_in_full"
                text: Translation.tr("Checklist always visible (Expanded Only)")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableChecklist
                checked: Config.options.bar.floatingNotch.checklistOnlyExpanded
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.checklistOnlyExpanded = checked;
                    if (checked) {
                        Config.options.bar.floatingNotch.checklistAlwaysVisible = false;
                    }
                }
                StyledToolTip { text: Translation.tr("Make checklist always show when the dynamic island is expanded, but not when contracted") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Checklist contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableChecklist
                value: Config.options.bar.floatingNotch.heightChecklist
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightChecklist = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Calendar Group ---
            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Calendar Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableCalendar
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableCalendar = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the calendar notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Calendar contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableCalendar
                value: Config.options.bar.floatingNotch.heightCalendar
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightCalendar = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Audio Group ---
            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Audio Output Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableAudio
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableAudio = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the audio output switcher notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Audio contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableAudio
                value: Config.options.bar.floatingNotch.heightAudio
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightAudio = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Live Progress Group ---
            ConfigSwitch {
                buttonIcon: "trending_up"
                text: Translation.tr("Live Progress Notch")
                visible: Config.options.bar.floatingNotch.enable
                checked: !Config.options.bar.floatingNotch.disableProgress
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableProgress = !checked;
                }
                StyledToolTip { text: Translation.tr("Toggle the live transfer/build progress notch") }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Progress contracted height")
                visible: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableProgress
                value: Config.options.bar.floatingNotch.heightProgress
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightProgress = value;
                }
            }

            Item {
                visible: Config.options.bar.floatingNotch.enable
                Layout.preferredHeight: 8
            }

            // --- Idle/Home Group ---
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Idle/Home contracted height")
                visible: Config.options.bar.floatingNotch.enable
                value: Config.options.bar.floatingNotch.heightHome
                from: 24
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.floatingNotch.heightHome = value;
                }
            }
        }
}
