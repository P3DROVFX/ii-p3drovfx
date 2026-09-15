import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: colorsThemesRoot
    anchors.fill: parent

    property alias contentY: pageRoot.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: pageRoot
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        property bool showRestartFab: false

        Connections {
            target: Config.options.appearance.palette
            function onTypeChanged() {
                pageRoot.showRestartFab = true;
            }
        }

        Connections {
            target: Appearance.m3colors
            function onDarkmodeChanged() {
                pageRoot.showRestartFab = true;
            }
        }

        FloatingActionButton {
            id: restartFab
            parent: pageRoot.parent
            anchors {
                right: parent ? parent.right : undefined
                bottom: parent ? parent.bottom : undefined
                margins: 30
            }
            z: 100
            iconText: "restart_alt"
            buttonText: Translation.tr("Restart Shell")
            expanded: false
            visible: opacity > 0
            opacity: pageRoot.showRestartFab ? 1 : 0
            scale: opacity

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            colBackground: Appearance.colors.colTertiaryContainer
            colBackgroundHover: Appearance.colors.colTertiaryContainerHover
            colRipple: Appearance.colors.colTertiaryContainerActive
            colOnBackground: Appearance.colors.colOnTertiaryContainer

            onClicked: {
                Quickshell.execDetached(["bash", "-c", "qs kill -c ii && qs -c ii &"]);
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: restartFab.expanded = true
                onExited: restartFab.expanded = false
            }
        }

        ContentSection {
            title: Translation.tr("Appearance Preferences")
            icon: "palette"

            RowLayout {
                Layout.fillWidth: true

                ConfigWallpaperSelector {
                    text: Translation.tr("Wallpaper Selector")
                }

                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    ConfigLightDarkToggle {
                        text: Translation.tr("Light / Dark Theme")
                    }

                    Item {
                        id: colorGridItem
                        z: 1
                        Layout.fillHeight: true
                        Layout.fillWidth: true

                        StyledFlickable {
                            id: flickable
                            anchors.fill: parent
                            contentHeight: contentLayout.implicitHeight
                            contentWidth: width
                            clip: true

                            ColumnLayout {
                                id: contentLayout
                                width: flickable.width

                                Repeater {
                                    model: [
                                        {
                                            customTheme: false,
                                            builtInTheme: false
                                        },
                                        {
                                            customTheme: false,
                                            builtInTheme: true
                                        },
                                        {
                                            customTheme: true,
                                            builtInTheme: false
                                        }
                                    ]

                                    delegate: ColorPreviewGrid {
                                        customTheme: modelData.customTheme
                                        builtInTheme: modelData.builtInTheme
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "schedule"
            title: Translation.tr("Scheduling (Dark Mode & Night Light)")

            ConfigSwitch {
                buttonIcon: "nightlight_round"
                text: Translation.tr("Automatic Dark Mode & Night Light")
                checked: Config.options.light.darkMode.automatic || Config.options.light.night.automatic
                configPage: Qt.resolvedUrl("widgets/SchedulingConfig.qml")
                onCheckedChanged: {
                    // `checked` is derived from both options, so writing them
                    // back whenever it changes re-enters this handler - QML
                    // reported that as a binding loop. Only a real change of
                    // the derived value is a user toggle worth persisting.
                    const current = Config.options.light.darkMode.automatic
                        || Config.options.light.night.automatic;
                    if (current === checked)
                        return;
                    Config.options.light.darkMode.automatic = checked;
                    Config.options.light.night.automatic = checked;
                    if (!checked) {
                        Hyprsunset.disableTemperature();
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Configure scheduled Dark Mode, Night Light color temperature, and eye protection")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Wallpaper Theming & Matugen Integration")
            icon: "wallpaper"

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Application theming")
                checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                configPage: Qt.resolvedUrl("widgets/WallpaperThemingConfig.qml")
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Apply Matugen color schemes to Shell, Qt apps, and Terminal. Click for subpage options.")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Wallpaper Variants")
            icon: "collections"

            // The switch stays a direct child of the section, as everywhere else
            // in Settings — ContentSubsection is for selectors and notices, not
            // for switches. Only the row under each switch was rebuilt.
            ContentSubsectionLabel {
                text: Translation.tr("Lockscreen wallpaper")
            }

            ConfigSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Separate Lockscreen Wallpaper")
                checked: Config.options.background.useSeparateLockscreenWallpaper
                onCheckedChanged: {
                    Config.options.background.useSeparateLockscreenWallpaper = checked;
                    if (checked && !Config.options.background.lockscreenWallpaperPath) {
                        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggleLockscreen"]);
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Use a different wallpaper on the lockscreen with custom Matugen color scheme transition")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                // Was 0: the preview and the buttons were touching.
                spacing: 12
                visible: Config.options.background.useSeparateLockscreenWallpaper

                ConfigWallpaperSelector {
                    targetMode: "lockscreen"
                    // 360x220 by default, which dwarfed the two buttons beside it.
                    Layout.preferredWidth: 240
                    Layout.preferredHeight: 135
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    // Centred against the preview. It used to be fillHeight with
                    // two buttons that do not stretch, so they sat pinned to the
                    // top with an empty gap underneath.
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6

                    RippleButtonWithIcon {
                        useDynamicRadius: true
                        Layout.fillWidth: true
                        materialIcon: "wallpaper"
                        mainText: Translation.tr("Select Lockscreen Wallpaper")
                        onClicked: {
                            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggleLockscreen"]);
                        }
                    }

                    RippleButtonWithIcon {
                        useDynamicRadius: true
                        Layout.fillWidth: true
                        materialIcon: "swap_horiz"
                        mainText: Translation.tr("Swap Desktop & Lockscreen")
                        onClicked: {
                            const desktopWall = Config.options.background.wallpaperPath;
                            const lockWall = Config.options.background.lockscreenWallpaperPath;
                            if (desktopWall && lockWall) {
                                Config.options.background.wallpaperPath = lockWall;
                                Wallpapers.applyLockscreen(desktopWall);
                                Wallpapers.apply(lockWall);
                            }
                        }
                    }
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Light-mode wallpaper")
            }

            ConfigSwitch {
                buttonIcon: "light_mode"
                text: Translation.tr("Separate Light Mode Wallpaper")
                checked: Config.options.background.useSeparateLightModeWallpaper
                onCheckedChanged: {
                    Config.options.background.useSeparateLightModeWallpaper = checked;
                    if (checked && !Config.options.background.lightModeWallpaperPath) {
                        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggleLightmode"]);
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Use a different wallpaper when in light mode. The current desktop wallpaper will be used for dark mode.")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                visible: Config.options.background.useSeparateLightModeWallpaper

                ConfigWallpaperSelector {
                    targetMode: "lightmode"
                    Layout.preferredWidth: 240
                    Layout.preferredHeight: 135
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6

                    RippleButtonWithIcon {
                        useDynamicRadius: true
                        Layout.fillWidth: true
                        materialIcon: "wallpaper"
                        mainText: Translation.tr("Select Light Mode Wallpaper")
                        onClicked: {
                            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggleLightmode"]);
                        }
                    }

                    RippleButtonWithIcon {
                        useDynamicRadius: true
                        Layout.fillWidth: true
                        materialIcon: "swap_horiz"
                        mainText: Translation.tr("Swap Dark & Light")
                        onClicked: {
                            const darkWall = Config.options.background.wallpaperPath;
                            const lightWall = Config.options.background.lightModeWallpaperPath;
                            if (darkWall && lightWall) {
                                Config.options.background.wallpaperPath = lightWall;
                                Config.options.background.lightModeWallpaperPath = darkWall;
                                if (Appearance.m3colors.darkmode) {
                                    Wallpapers.apply(darkWall, true);
                                } else {
                                    Wallpapers.applyLightModeWallpaper(lightWall);
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Integrations & Engines")
            icon: "science"

            ContentSubsection {
                title: Translation.tr("Color generation mode")
                icon: "settings_brightness"
                tooltip: Translation.tr("ii-vynx: uses the original switchwall pipeline.\n\nFork: uses the fork's color generation pipeline, use this if vynx doesn't work.")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.colorEngine ?? "vynx"
                    onSelected: newValue => {
                        Config.options.appearance.colorEngine = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("ii-vynx"),
                            value: "vynx",
                            icon: "verified"
                        },
                        {
                            displayName: Translation.tr("Fork"),
                            value: "fork",
                            icon: "build"
                        }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("OpenRGB integration")
                checked: Config.options.appearance.openrgb.enable
                configPage: Qt.resolvedUrl("widgets/OpenRGBConfig.qml")
                onCheckedChanged: {
                    Config.options.appearance.openrgb.enable = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "play_circle"
                text: Translation.tr("Enable Wallpaper Engine")
                checked: Config.options.background.useWallpaperEngine
                configPage: Qt.resolvedUrl("widgets/WallpaperEngineConfig.qml")
                onCheckedChanged: {
                    if (Config.options.background.useWallpaperEngine === checked)
                        return;
                    Config.options.background.useWallpaperEngine = checked;
                    Config.saveOptionsNow();
                    if (checked && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    } else if (!checked) {
                        Quickshell.execDetached(["bash", "-c", "pkill -f linux-wallpaperengine; sleep 0.3; pkill -9 -f linux-wallpaperengine 2>/dev/null; true"]);
                        if (Config.options.background.wallpaperPath)
                            Wallpapers.apply(Config.options.background.wallpaperPath);
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "folder_shared"
                text: Translation.tr("Use system file picker")
                checked: Config.options.wallpaperSelector.useSystemFileDialog
                onCheckedChanged: {
                    Config.options.wallpaperSelector.useSystemFileDialog = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Uses xdg-desktop-portal instead of the built-in quickshell picker")
                }
            }

            ContentSubsection {
                title: Translation.tr("Wallpaper Browser download path")
                icon: "download"
                Layout.fillWidth: true

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Download path...")
                    text: Config.options.wallpapers.paths.download
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.wallpapers.paths.download = text;
                    }
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
