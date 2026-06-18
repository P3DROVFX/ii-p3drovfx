import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: pageRoot
    forceWidth: false

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
            right: parent?.right
            bottom: parent?.bottom
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
        title: Translation.tr("Color Engine")
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
    }

    ContentSection {
        icon: "nightlight"
        title: Translation.tr("Scheduling (Dark Mode & Night Light)")

        ConfigSwitch {
            buttonIcon: "dark_mode"
            text: Translation.tr("Automatic Dark Mode")
            checked: Config.options.light.darkMode.automatic
            onCheckedChanged: {
                Config.options.light.darkMode.automatic = checked;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.darkMode.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Dark Mode start time (e.g. 18:00)")
            text: Config.options.light.darkMode.from
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.darkMode.from = text;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.darkMode.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Dark Mode end time (e.g. 06:00)")
            text: Config.options.light.darkMode.to
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.darkMode.to = text;
            }
        }

        ConfigSwitch {
            buttonIcon: "nightlight_round"
            text: Translation.tr("Automatic Night Light")
            checked: Config.options.light.night.automatic
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.night.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Night Light start time (e.g. 19:00)")
            text: Config.options.light.night.from
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.night.from = text;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.night.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Night Light end time (e.g. 06:00)")
            text: Config.options.light.night.to
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.night.to = text;
            }
        }

        ConfigSlider {
            buttonIcon: "wb_twilight"
            text: Translation.tr("Night Light Color Temperature")
            usePercentTooltip: false
            from: 1000
            to: 10000
            stepSize: 100
            value: Config.options.light.night.colorTemperature ?? 5000
            onValueChanged: {
                Config.options.light.night.colorTemperature = Math.round(value);
            }
        }

        ConfigSwitch {
            buttonIcon: "flash_off"
            text: Translation.tr("Anti-flashbang light filter")
            checked: Config.options.light.antiFlashbang.enable
            onCheckedChanged: {
                Config.options.light.antiFlashbang.enable = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Wallpaper Theming & Matugen Integration")
        icon: "wallpaper"

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Shell & utilities")
            checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "widgets"
            text: Translation.tr("Qt apps")
            checked: Config.options.appearance.wallpaperTheming.enableQtApps
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableQtApps = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shell & utilities theming must also be enabled")
            }
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Terminal")
            checked: Config.options.appearance.wallpaperTheming.enableTerminal
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableTerminal = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shell & utilities theming must also be enabled")
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
    }
}
