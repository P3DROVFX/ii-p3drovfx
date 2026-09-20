import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
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
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("KDE Connect Service")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "sync"
            title: Translation.tr("Connection Settings")

            ConfigSwitch {
                buttonIcon: "wifi"
                text: Translation.tr("Use wireless debugging")
                checked: Config.options.phone.scrcpy.useWireless
                onCheckedChanged: Config.options.phone.scrcpy.useWireless = checked
            }

            ConfigSwitch {
                buttonIcon: "sync_alt"
                text: Translation.tr("Auto-detect IP (KDE Connect)")
                checked: Config.options.phone.scrcpy.autoWirelessIp
                enabled: Config.options.phone.scrcpy.useWireless
                onCheckedChanged: Config.options.phone.scrcpy.autoWirelessIp = checked
            }

            ConfigSwitch {
                buttonIcon: "push_pin"
                text: Translation.tr("Pin ADB to port 5555")
                checked: Config.options.phone.scrcpy.pinAdbPort
                enabled: Config.options.phone.scrcpy.useWireless
                onCheckedChanged: Config.options.phone.scrcpy.pinAdbPort = checked

                StyledToolTip {
                    text: Translation.tr("Wireless debugging picks a new random port every time the phone's ADB daemon restarts — an unlock is enough — which cuts the connection. Pinning holds a fixed port that survives those restarts, until the phone reboots.")
                }
            }

            ConfigSwitch {
                buttonIcon: "restart_alt"
                text: Translation.tr("Reopen windows after a drop")
                checked: Config.options.phone.scrcpy.autoResume
                onCheckedChanged: Config.options.phone.scrcpy.autoResume = checked

                StyledToolTip {
                    text: Translation.tr("Reopens the same mirror or app window here once the phone answers again. Only affects windows on this machine, not what the phone is doing.")
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: Config.options.phone.scrcpy.useWireless && KdeConnectService.pinnedAdbHost !== ""
                text: Translation.tr("Pinned to %1").arg(KdeConnectService.pinnedAdbHost)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: Config.options.phone.scrcpy.useWireless && Config.options.phone.scrcpy.autoWirelessIp
                text: KdeConnectService.resolvedWirelessHost !== ""
                    ? Translation.tr("Will connect to %1").arg(KdeConnectService.resolvedWirelessHost)
                    : Translation.tr("Waiting for KDE Connect to report the phone's IP…")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            ConfigTextField {
                icon: "dns"
                text: Translation.tr("Wireless IP")
                placeholderText: Translation.tr("e.g. 192.168.1.50")
                inputText: Config.options.phone.scrcpy.wirelessIp
                visible: Config.options.phone.scrcpy.useWireless && !Config.options.phone.scrcpy.autoWirelessIp
                enabled: visible
                textField.onTextChanged: Config.options.phone.scrcpy.wirelessIp = textField.text
            }

            ConfigTextField {
                icon: "tag"
                text: Translation.tr("Wireless Port")
                placeholderText: Translation.tr("Default: 5555")
                inputText: Config.options.phone.scrcpy.wirelessPort
                visible: Config.options.phone.scrcpy.useWireless && !Config.options.phone.scrcpy.autoWirelessIp
                enabled: visible
                textField.onTextChanged: Config.options.phone.scrcpy.wirelessPort = textField.text
            }

            ConfigSwitch {
                buttonIcon: "terminal"
                text: Translation.tr("Show terminal window")
                checked: Config.options.phone.scrcpy.showTerminal
                onCheckedChanged: Config.options.phone.scrcpy.showTerminal = checked
            }
        }

        ContentSection {
            icon: "phone_android"
            title: Translation.tr("scrcpy Options")

            ConfigSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Stay awake")
                checked: Config.options.phone.scrcpy.stayAwake
                onCheckedChanged: Config.options.phone.scrcpy.stayAwake = checked
            }
            ConfigSwitch {
                buttonIcon: "phone_android"
                text: Translation.tr("Turn screen off")
                checked: Config.options.phone.scrcpy.turnScreenOff
                onCheckedChanged: Config.options.phone.scrcpy.turnScreenOff = checked
            }
            ConfigSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("No power on device")
                checked: Config.options.phone.scrcpy.noPowerOn
                onCheckedChanged: Config.options.phone.scrcpy.noPowerOn = checked
            }
            ConfigSwitch {
                buttonIcon: "volume_off"
                text: Translation.tr("No audio forwarding")
                checked: Config.options.phone.scrcpy.noAudio
                onCheckedChanged: Config.options.phone.scrcpy.noAudio = checked
            }
            ConfigSwitch {
                buttonIcon: "gesture"
                text: Translation.tr("Show touches")
                checked: Config.options.phone.scrcpy.showTouches
                onCheckedChanged: Config.options.phone.scrcpy.showTouches = checked
            }
            ConfigSwitch {
                buttonIcon: "fullscreen"
                text: Translation.tr("Fullscreen")
                checked: Config.options.phone.scrcpy.fullscreen
                onCheckedChanged: Config.options.phone.scrcpy.fullscreen = checked
            }
            ConfigSwitch {
                buttonIcon: "vertical_align_top"
                text: Translation.tr("Always on top")
                checked: Config.options.phone.scrcpy.alwaysOnTop
                onCheckedChanged: Config.options.phone.scrcpy.alwaysOnTop = checked
            }
            ConfigSlider {
                buttonIcon: "speed"
                text: Translation.tr("Max FPS")
                value: Config.options.phone.scrcpy.maxFps
                from: 0
                to: 120
                stepSize: 5
                usePercentTooltip: false
                onValueChanged: Config.options.phone.scrcpy.maxFps = value
            }
            ConfigTextField {
                icon: "wifi_tethering"
                text: Translation.tr("Bitrate")
                placeholderText: Translation.tr("e.g. 8M, 4M")
                inputText: Config.options.phone.scrcpy.bitRate
                textField.onTextChanged: Config.options.phone.scrcpy.bitRate = textField.text
            }
            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Max Size (0 for unrestricted)")
                value: Config.options.phone.scrcpy.maxSize
                from: 0
                to: 3840
                stepSize: 120
                usePercentTooltip: false
                onValueChanged: Config.options.phone.scrcpy.maxSize = value
            }
            ConfigSlider {
                buttonIcon: "av_timer"
                text: Translation.tr("Video Buffer (ms)")
                value: Config.options.phone.scrcpy.videoBuffer
                from: 0
                to: 1000
                stepSize: 10
                usePercentTooltip: false
                onValueChanged: Config.options.phone.scrcpy.videoBuffer = value
            }
        }

        ContentSection {
            icon: "apps"
            title: Translation.tr("Android App Mode (scrcpy 4.0+)")

            ConfigSwitch {
                buttonIcon: "apps"
                text: Translation.tr("Enable Android App Mode")
                checked: Config.options.phone.scrcpy.appMode.enabled
                onCheckedChanged: Config.options.phone.scrcpy.appMode.enabled = checked

                StyledToolTip {
                    text: Translation.tr("Allows launching individual Android apps directly from the II Phone panel.")
                }
            }

            ConfigSwitch {
                buttonIcon: "wallpaper"
                text: Translation.tr("Show real app icons")
                checked: Config.options.phone.scrcpy.appMode.showAppIcons
                enabled: Config.options.phone.scrcpy.appMode.enabled
                onCheckedChanged: Config.options.phone.scrcpy.appMode.showAppIcons = checked

                StyledToolTip {
                    text: Translation.tr("Reads each app's launcher icon off the phone when you refresh the app list, then caches it. Apps without a cached icon keep a generic Android glyph.")
                }

                extraComponent: Component {
                    RippleButtonWithIcon {
                        materialIcon: "delete_sweep"
                        mainText: ""
                        centerContent: true
                        implicitWidth: 40
                        enabled: Config.options.phone.scrcpy.appMode.enabled && Config.options.phone.scrcpy.appMode.showAppIcons
                        onClicked: PhoneAppIconService.clearCache()

                        StyledToolTip {
                            text: Translation.tr("Forgets every extracted icon, including the apps that failed, so the next app-list refresh reads them all again.")
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Icon shape")
                visible: Config.options.phone.scrcpy.appMode.showAppIcons
                tooltip: Translation.tr("How the phone's launcher would cut each icon: Pixel, One UI and iOS use those launchers' measured shapes; the rest are the stock Android mask options most other brands pick from. Only affects extracted icons; the generic Android glyph keeps its own shape.")

                ConfigSelectionArray {
                    currentValue: Config.options.phone.scrcpy.appMode.iconShape
                    onSelected: newValue => {
                        Config.options.phone.scrcpy.appMode.iconShape = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Pixel"), icon: "circle", value: "circle" },
                        { displayName: Translation.tr("Samsung One UI"), icon: "rounded_corner", value: "oneui" },
                        { displayName: Translation.tr("iOS"), icon: "ios", value: "ios" },
                        { displayName: Translation.tr("Squircle"), icon: "crop_square", value: "squircle" },
                        { displayName: Translation.tr("Rounded square"), icon: "square", value: "roundedSquare" },
                        { displayName: Translation.tr("Square"), icon: "check_box_outline_blank", value: "square" },
                        { displayName: Translation.tr("Sharp square"), icon: "crop_din", value: "sharpSquare" },
                        { displayName: Translation.tr("Teardrop"), icon: "water_drop", value: "teardrop" },
                        { displayName: Translation.tr("Cylinder"), icon: "panorama_horizontal", value: "cylinder" }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Use Virtual Secondary Display (--flex-display)")
                checked: Config.options.phone.scrcpy.appMode.flexDisplay
                onCheckedChanged: Config.options.phone.scrcpy.appMode.flexDisplay = checked

                StyledToolTip {
                    text: Translation.tr("Launches apps in secondary virtual display. On Samsung Galaxy devices, this opens Samsung DeX. Disable to launch directly on main phone screen.")
                }
            }

            ConfigSwitch {
                buttonIcon: "lock_open_right"
                text: Translation.tr("Unlock the phone automatically")
                checked: Config.options.phone.scrcpy.appMode.autoUnlock
                onCheckedChanged: Config.options.phone.scrcpy.appMode.autoUnlock = checked

                StyledToolTip {
                    text: Translation.tr("Dismisses the lockscreen before launching, without lighting the phone's screen when \"Turn screen off\" is on. Only gets through when the phone already trusts this situation — otherwise a small mirror opens so it can be unlocked from here.")
                }

                // Setting the trust up lives on the phone, so the action
                // belongs on this row rather than as a button of its own —
                // a bare pill between two cards breaks the column.
                extraComponent: Component {
                    RippleButtonWithIcon {
                        materialIcon: "open_in_new"
                        // Icon only: RippleButtonWithIcon otherwise shows its
                        // "Button text" placeholder and runs into the toggle.
                        mainText: ""
                        centerContent: true
                        implicitWidth: 40
                        enabled: KdeConnectService.adbReachable
                        onClicked: KdeConnectService.openExtendedUnlockSettings()

                        StyledToolTip {
                            text: Translation.tr("Android gives a desktop no way to make itself trusted — the phone has to be told once. Opens Extended unlock on the phone, where this machine can be added as a trusted device. After that the lockscreen is a plain swipe, which the shell does for you.")
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("When a session ends")
                icon: "exit_to_app"
                tooltip: Translation.tr("What the phone is left doing after you close the window. \"Keep the app\" moves it back to the phone's own screen instead of dropping it with the virtual display. Nothing runs when the window closed because the connection dropped.")

                ConfigSelectionArray {
                    currentValue: Config.options.phone.scrcpy.appMode.onSessionEnd
                    onSelected: newValue => {
                        Config.options.phone.scrcpy.appMode.onSessionEnd = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Home screen"), icon: "home", value: "home" },
                        { displayName: Translation.tr("Keep the app"), icon: "phonelink", value: "continue" },
                        { displayName: Translation.tr("Lock"), icon: "lock", value: "lock" }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "keep"
                text: Translation.tr("Keep virtual display active")
                checked: Config.options.phone.scrcpy.appMode.keepActive
                enabled: Config.options.phone.scrcpy.appMode.flexDisplay
                onCheckedChanged: Config.options.phone.scrcpy.appMode.keepActive = checked

                StyledToolTip {
                    text: Translation.tr("Prevents virtual display from being destroyed when app window closes.")
                }
            }

            ConfigSwitch {
                buttonIcon: "web_asset"
                text: Translation.tr("Show Android system decorations")
                checked: Config.options.phone.scrcpy.appMode.systemDecorations
                enabled: Config.options.phone.scrcpy.appMode.flexDisplay
                onCheckedChanged: Config.options.phone.scrcpy.appMode.systemDecorations = checked

                StyledToolTip {
                    text: Translation.tr("Shows status bar and navigation controls inside the virtual display.")
                }
            }

            ConfigSlider {
                buttonIcon: "desktop_mac"
                text: Translation.tr("Virtual Display Width")
                value: Config.options.phone.scrcpy.appMode.displayWidth
                from: 640
                to: 2560
                stepSize: 80
                usePercentTooltip: false
                enabled: Config.options.phone.scrcpy.appMode.flexDisplay
                onValueChanged: Config.options.phone.scrcpy.appMode.displayWidth = value
            }

            ConfigSlider {
                buttonIcon: "desktop_mac"
                text: Translation.tr("Virtual Display Height")
                value: Config.options.phone.scrcpy.appMode.displayHeight
                from: 480
                to: 1920
                stepSize: 60
                usePercentTooltip: false
                enabled: Config.options.phone.scrcpy.appMode.flexDisplay
                onValueChanged: Config.options.phone.scrcpy.appMode.displayHeight = value
            }

            ConfigSlider {
                buttonIcon: "display_settings"
                text: Translation.tr("Virtual Display Density (DPI)")
                value: Config.options.phone.scrcpy.appMode.density
                from: 120
                to: 480
                stepSize: 20
                usePercentTooltip: false
                enabled: Config.options.phone.scrcpy.appMode.flexDisplay
                onValueChanged: Config.options.phone.scrcpy.appMode.density = value
            }
        }
    }
}
