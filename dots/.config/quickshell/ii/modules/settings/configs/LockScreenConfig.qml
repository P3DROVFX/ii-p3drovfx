import QtQuick
import QtQuick.Layouts
import qs.services
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.lockscreen

Item {
    id: lockScreenRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var lock: Config.options.lock

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── The lock, live, with its look ───────────────────────────────
        LockHero {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
        }

        // ── What the lock draws ─────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            icon: "widgets"
            title: Translation.tr("Elements")

            ContentSubsection {
                title: Translation.tr("Centered widgets")
                icon: "align_vertical_center"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: lockScreenRoot.lock.centerAlignment ?? "horizontal"
                    onSelected: newValue => lockScreenRoot.lock.centerAlignment = newValue
                    options: [
                        { displayName: Translation.tr("Side by side"), icon: "view_column", value: "horizontal" },
                        { displayName: Translation.tr("Stacked"), icon: "view_agenda", value: "vertical" }
                    ]
                }
            }

            ConfigSlider {
                buttonIcon: "space_bar"
                text: Translation.tr("Center spacing")
                from: 0
                to: 100
                stepSize: 5
                usePercentTooltip: false
                value: lockScreenRoot.lock.centerSpacing ?? 20
                onValueChanged: lockScreenRoot.lock.centerSpacing = value
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "text_fields"
                    text: Translation.tr("Show \"Locked\" text")
                    checked: lockScreenRoot.lock.showLockedText
                    onCheckedChanged: lockScreenRoot.lock.showLockedText = checked
                    StyledToolTip {
                        text: Translation.tr("Write \"Locked\" under the clock while the screen is locked.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "timer_off"
                    text: Translation.tr("Disable clock animation on lock")
                    checked: Config.options.background.widgets.clock_cookie.disableAnimationOnLock
                    onCheckedChanged: Config.options.background.widgets.clock_cookie.disableAnimationOnLock = checked
                    StyledToolTip {
                        text: Translation.tr("Keep the cookie clock still when the screen locks.")
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr("Show Now Playing widget")
                    checked: lockScreenRoot.lock.nowPlaying ?? true
                    onCheckedChanged: lockScreenRoot.lock.nowPlaying = checked
                    StyledToolTip {
                        text: Translation.tr("Show the playing media at the top while something plays.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "sports_soccer"
                    text: Translation.tr("Show sports widget")
                    checked: lockScreenRoot.lock.sports ?? true
                    onCheckedChanged: lockScreenRoot.lock.sports = checked
                    StyledToolTip {
                        text: Translation.tr("Show the live score of a followed game at the top.")
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "alarm"
                    text: Translation.tr("Show next alarm")
                    checked: lockScreenRoot.lock.showAlarm ?? true
                    onCheckedChanged: lockScreenRoot.lock.showAlarm = checked
                    StyledToolTip {
                        text: Translation.tr("Show the next alarm in the left island.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "cloud"
                    text: Translation.tr("Show weather icon")
                    checked: lockScreenRoot.lock.showWeather ?? true
                    onCheckedChanged: lockScreenRoot.lock.showWeather = checked
                    StyledToolTip {
                        text: Translation.tr("Show the current weather in the left island.")
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "category"
                    text: Translation.tr("Shaped password characters")
                    checked: lockScreenRoot.lock.materialShapeChars
                    onCheckedChanged: lockScreenRoot.lock.materialShapeChars = checked
                    StyledToolTip {
                        text: Translation.tr("Draw each typed character as a different Material shape instead of a dot.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "waves"
                    text: Translation.tr("Ripple effect on touch")
                    checked: lockScreenRoot.lock.rippleEffect ?? true
                    onCheckedChanged: lockScreenRoot.lock.rippleEffect = checked
                    StyledToolTip {
                        text: Translation.tr("Send a ripple across the wallpaper where the lock screen is touched or clicked.")
                    }
                }
            }

            RippleButton {
                Layout.topMargin: 4
                implicitHeight: 40
                implicitWidth: arrangeRow.implicitWidth + 32
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.normal
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: {
                    GlobalStates.openEditMode();
                    if (GlobalStates.editMode)
                        GlobalStates.editTab = EditModeLogic.lockscreenTab;
                }

                contentItem: Item {
                    RowLayout {
                        id: arrangeRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: "edit"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: Translation.tr("Arrange widgets and islands on the desktop")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Open Edit Mode on the Lockscreen tab to move widgets and reorder the islands.")
                }
            }
        }

        // ── Security & privacy ──────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 12
            title: Translation.tr("Security & privacy")
            symbol: "shield_lock"

            Item {
                id: tiles
                Layout.fillWidth: true
                implicitHeight: tileFlow.implicitHeight

                readonly property int gap: 12
                readonly property int fits: Math.max(1, Math.floor((width + gap) / (300 + gap)))
                // Four tiles: one row of four, two of two or a column, never 3 + 1.
                readonly property int columns: fits >= 4 ? 4 : fits >= 2 ? 2 : 1
                readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)
                readonly property int tileHeight: 200

                Flow {
                    id: tileFlow
                    width: parent.width
                    spacing: tiles.gap

                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        symbol: "fingerprint"
                        shapeOn: MaterialShape.Shape.Cookie12Sided
                        title: Translation.tr("Fingerprint")
                        summary: {
                            if (!checked)
                                return Translation.tr("Unlock with your password only");
                            if (Fingerprint.probed && !Fingerprint.deviceAvailable)
                                return Translation.tr("No fingerprint reader found");
                            if (!Fingerprint.enrolledLoaded)
                                return Translation.tr("Looking for enrolled fingers…");
                            const count = Fingerprint.enrolled.length;
                            if (count === 0)
                                return Translation.tr("No finger enrolled yet");
                            return count === 1 ? Translation.tr("1 finger enrolled") : Translation.tr("%1 fingers enrolled").arg(count);
                        }
                        checked: lockScreenRoot.lock.security.fingerprint.enable
                        configurable: true
                        onToggled: value => lockScreenRoot.lock.security.fingerprint.enable = value
                        onConfigureRequested: lockScreenRoot.activeSubPage = Qt.resolvedUrl("widgets/FingerprintConfig.qml")
                    }

                    ColorsFeatureTile {
                        id: notificationsTile
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        symbol: "notifications"
                        shapeOn: MaterialShape.Shape.Flower
                        title: Translation.tr("Notifications")
                        readonly property var conf: lockScreenRoot.lock.notifications
                        readonly property var positionNames: ({
                            "top_left": Translation.tr("Top left"),
                            "top_right": Translation.tr("Top right"),
                            "bottom_left": Translation.tr("Bottom left"),
                            "bottom_right": Translation.tr("Bottom right")
                        })
                        readonly property var privacyNames: ({
                            "full": Translation.tr("Full content"),
                            "redacted": Translation.tr("Content hidden"),
                            "countOnly": Translation.tr("Count only")
                        })
                        summary: checked
                            ? `${positionNames[conf.position] ?? ""} · ${privacyNames[conf.privacy] ?? ""}`
                            : Translation.tr("Nothing shows while locked")
                        checked: conf.enable
                        configurable: true
                        onToggled: value => notificationsTile.conf.enable = value
                        onConfigureRequested: lockScreenRoot.activeSubPage = Qt.resolvedUrl("widgets/LockscreenNotificationsConfig.qml")

                        LockPrivacyPicker {
                            enabled: notificationsTile.checked
                            colContent: notificationsTile.colContent
                            currentValue: notificationsTile.conf.privacy
                            onSelected: value => notificationsTile.conf.privacy = value
                        }
                    }

                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        symbol: "power_settings_new"
                        shapeOn: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Guarded power")
                        summary: checked
                            ? Translation.tr("Power off and restart need your password")
                            : Translation.tr("Anyone can power off from the lock screen")
                        checked: lockScreenRoot.lock.security.requirePasswordToPower
                        onToggled: value => lockScreenRoot.lock.security.requirePasswordToPower = value
                    }

                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        symbol: "key"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        title: Translation.tr("Keyring")
                        summary: checked
                            ? Translation.tr("The login keyring opens when you unlock")
                            : Translation.tr("Apps ask for the keyring password")
                        checked: lockScreenRoot.lock.security.unlockKeyring
                        onToggled: value => lockScreenRoot.lock.security.unlockKeyring = value
                    }
                }
            }
        }

        // ── Always On Display ───────────────────────────────────────────
        LockOledCard {
            Layout.topMargin: 12
            Layout.fillWidth: true
        }

        // ── Behavior ────────────────────────────────────────────────────
        ContentSection {
            icon: "tune"
            title: Translation.tr("Behavior")

            ContentSubsection {
                title: Translation.tr("Lock screen")
                icon: "lock"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: lockScreenRoot.lock.useHyprlock
                    onSelected: newValue => lockScreenRoot.lock.useHyprlock = newValue
                    options: [
                        { displayName: "Quickshell", icon: "auto_awesome", value: false },
                        { displayName: "Hyprlock", icon: "terminal", value: true }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Lock animation")
                icon: "animation"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: {
                        const style = lockScreenRoot.lock.zoomAnimation?.style ?? "default";
                        return (style === "gnome" || style === "material-shape") ? style : "default";
                    }
                    onSelected: newValue => lockScreenRoot.lock.zoomAnimation.style = newValue
                    options: [
                        {
                            displayName: Translation.tr("Default zoom"),
                            icon: "zoom_in",
                            tooltip: Translation.tr("Centers the wallpaper and zooms into it, the classic lock animation."),
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Gnome Like"),
                            icon: "blur_on",
                            tooltip: Translation.tr("The overview's Gnome design on lock: the wallpaper zooms out into a rounded card over a blurred, dimmed backing."),
                            value: "gnome"
                        },
                        {
                            displayName: Translation.tr("Material Shape"),
                            icon: "shapes",
                            tooltip: Translation.tr("The overview's Material Shape design on lock: a random shape closes in over a solid backdrop, framing the lock's center."),
                            value: "material-shape"
                        }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("Launch on startup")
                checked: lockScreenRoot.lock.launchOnStartup
                onCheckedChanged: lockScreenRoot.lock.launchOnStartup = checked
                StyledToolTip {
                    text: Translation.tr("Start the lock screen daemon when the session begins.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Touch keyboard")
                icon: "keyboard"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: lockScreenRoot.lock.touchKeyboard.show
                    onSelected: newValue => lockScreenRoot.lock.touchKeyboard.show = newValue
                    options: [
                        { displayName: Translation.tr("Auto"), icon: "auto_mode", value: "auto" },
                        { displayName: Translation.tr("Always"), icon: "keyboard", value: "always" },
                        { displayName: Translation.tr("Never"), icon: "keyboard_hide", value: "never" }
                    ]
                }
            }

            ContentSubsection {
                visible: lockScreenRoot.lock.touchKeyboard.show !== "never"
                title: Translation.tr("Touch keys")
                icon: "dialpad"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: lockScreenRoot.lock.touchKeyboard.mode
                    onSelected: newValue => lockScreenRoot.lock.touchKeyboard.mode = newValue
                    options: [
                        { displayName: Translation.tr("Letters"), icon: "abc", value: "text" },
                        { displayName: Translation.tr("PIN"), icon: "dialpad", value: "pin" }
                    ]
                }
            }
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "colors"
                    label: Translation.tr("Lock wallpaper")
                }
                RelatedChip {
                    pageId: "wallpaper"
                    label: Translation.tr("Wallpaper zoom")
                    sectionHighlight: Translation.tr("Parallax Engine")
                }
                RelatedChip {
                    pageId: "windows"
                    label: Translation.tr("Window blur")
                    sectionHighlight: Translation.tr("Transparency & Blur")
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
