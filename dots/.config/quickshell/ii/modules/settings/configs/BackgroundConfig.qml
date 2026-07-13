import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    ContentSection {
        title: Translation.tr("Parallax Engine")
        icon: "sync_alt"

        ConfigSwitch {
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Vertical movement")
            checked: Config.options.background.parallax.vertical
            onCheckedChanged: {
                HyprlandSettings.changeAnimation("workspaces", checked ? "slidevert" : "slide");
                Config.options.background.parallax.vertical = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr("Depends on workspace")
            checked: Config.options.background.parallax.enableWorkspace
            onCheckedChanged: {
                Config.options.background.parallax.enableWorkspace = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "loop"
            text: Translation.tr("Loop wallpaper")
            checked: Config.options.background.parallax.loop
            onCheckedChanged: {
                Config.options.background.parallax.loop = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Invert horizontal movement")
            checked: Config.options.background.parallax.invertHorizontal
            onCheckedChanged: {
                Config.options.background.parallax.invertHorizontal = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "swap_vert"
            text: Translation.tr("Invert vertical movement")
            checked: Config.options.background.parallax.invertVertical
            onCheckedChanged: {
                Config.options.background.parallax.invertVertical = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "side_navigation"
            text: Translation.tr("Depends on sidebars")
            checked: Config.options.background.parallax.enableSidebar
            onCheckedChanged: {
                Config.options.background.parallax.enableSidebar = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Parallax movement intensity")
            visible: Config.options.background.parallax.enableWorkspace
            usePercentTooltip: false
            from: 1
            to: 10
            stepSize: 1
            value: Config.options.background.parallax.intensity ?? 4
            onValueChanged: {
                Config.options.background.parallax.intensity = value;
            }
        }

        ConfigSlider {
            buttonIcon: "loupe"
            text: Translation.tr("Preferred wallpaper zoom (%)")
            from: 100
            to: 150
            stepSize: 1
            value: Config.options.background.parallax.workspaceZoom * 100
            onValueChanged: {
                Config.options.background.parallax.workspaceZoom = value / 100;
            }
        }

        ConfigSwitch {
            buttonIcon: "timer_off"
            text: Translation.tr("Disable clock animation on lock")
            checked: Config.options.background.widgets.clock.disableAnimationOnLock
            onCheckedChanged: {
                Config.options.background.widgets.clock.disableAnimationOnLock = checked;
            }
            StyledToolTip {
                text: Translation.tr("Skip loading the clock widget during lock screen for better animation performance.")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Transition Animations")
        icon: "animation"

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Animate wallpaper changes")
            checked: Config.options.background.animateWallpaperChanges
            onCheckedChanged: {
                Config.options.background.animateWallpaperChanges = checked;
            }
        }

        ContentSubsection {
            visible: Config.options.background.animateWallpaperChanges
            title: Translation.tr("Transition style")
            icon: "style"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.wallpaperAnimation
                onSelected: newValue => {
                    Config.options.background.wallpaperAnimation = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Random"),
                        icon: "shuffle",
                        value: "random"
                    },
                    {
                        displayName: Translation.tr("Crossfade"),
                        icon: "blur_on",
                        value: ""
                    },
                    {
                        displayName: Translation.tr("Circle Pit"),
                        icon: "circle",
                        value: "circlePit"
                    },
                    {
                        displayName: Translation.tr("Circle Select"),
                        icon: "radio_button_checked",
                        value: "circleSelect"
                    },
                    {
                        displayName: Translation.tr("Magic"),
                        icon: "auto_awesome",
                        value: "magic"
                    },
                    {
                        displayName: Translation.tr("Peel"),
                        icon: "sticky_note_2",
                        value: "Peel"
                    },
                    {
                        displayName: Translation.tr("Transition"),
                        icon: "swap_horiz",
                        value: "transition"
                    },
                    {
                        displayName: Translation.tr("Pixelate"),
                        icon: "grid_on",
                        value: "pixelate"
                    },
                    {
                        displayName: Translation.tr("Stripes"),
                        icon: "view_column",
                        value: "stripes"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "blur_circular"
            text: Translation.tr("Blur wallpaper when a window is open")
            checked: Config.options.background.blurWhenWindowsOpen
            onCheckedChanged: {
                Config.options.background.blurWhenWindowsOpen = checked;
            }
            StyledToolTip {
                text: Translation.tr("Experimental - Blur the wallpaper and widgets when a window is open on the current workspace.")
            }
        }

        ConfigSlider {
            buttonIcon: "lens_blur"
            text: Translation.tr("Blur intensity when a window is open")
            visible: Config.options.background.blurWhenWindowsOpen
            usePercentTooltip: true
            from: 0
            to: 100
            stepSize: 1
            value: Config.options.background.blurWhenWindowsOpenRadius ?? 80
            onValueChanged: {
                Config.options.background.blurWhenWindowsOpenRadius = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "zoom_in_map"
            text: Translation.tr("Zoom animation when overview/cheatsheet is open (Beta)")
            checked: Config.options.background.zoomOutEnabled
            onCheckedChanged: {
                Config.options.background.zoomOutEnabled = checked;
            }
            StyledToolTip {
                text: Translation.tr("Experimental - Scale windows with wallpaper when Overview/Cheatsheet is opened, this is a work in progress, expect bugs and a lags on low end hardware.")
            }
        }

        ContentSubsection {
            visible: Config.options.background.zoomOutEnabled
            title: Translation.tr("Zoom background style")
            icon: "style"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.zoomOutStyle
                onSelected: newValue => {
                    Config.options.background.zoomOutStyle = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Gnome Like"),
                        icon: "blur_on",
                        value: 0
                    },
                    {
                        displayName: Translation.tr("Default"),
                        icon: "grid_view",
                        value: 1
                    },
                    {
                        displayName: Translation.tr("Zoom In"),
                        icon: "zoom_in",
                        value: 2
                    }
                ]
            }
        }

        ConfigSwitch {
            visible: Config.options.background.zoomOutEnabled && Config.options.background.zoomOutStyle === 0
            buttonIcon: "open_with"
            text: Translation.tr("Experimental - Scale windows with wallpaper")
            checked: Config.options.background.windowZoomOnOverview
            onCheckedChanged: {
                Config.options.background.windowZoomOnOverview = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shows scaled ScreencopyView of windows zooming out with the wallpaper when the overview opens.\nWindows on the active workspace follow the wallpaper zoom animation.\nWorkspace switching slides the window previews alongside the workspace animation.")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Media Mode Background")
        icon: "music_note"

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Enable background animation")
            checked: Config.options.background.mediaMode.backgroundAnimation.enable
            onCheckedChanged: {
                Config.options.background.mediaMode.backgroundAnimation.enable = checked;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.background.mediaMode.backgroundAnimation.enable
            icon: "speed"
            text: Translation.tr("Speed scale")
            value: Config.options.background.mediaMode.backgroundAnimation.speedScale
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.background.mediaMode.backgroundAnimation.speedScale = value;
            }
            MouseArea {
                id: spinBoxMouseArea
                z: -1
                anchors.fill: parent
                hoverEnabled: true
            }
            StyledToolTip {
                extraVisibleCondition: spinBoxMouseArea.containsMouse
                text: Translation.tr("1: very slow | 10: default | 20: 2x speed...")
            }
        }

        ConfigSpinBox {
            icon: "opacity"
            text: Translation.tr("Background album art opacity (%)")
            value: Config.options.background.mediaMode.backgroundOpacity
            from: 0
            to: 100
            stepSize: 10
            onValueChanged: {
                Config.options.background.mediaMode.backgroundOpacity = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Background shape")
            icon: "category"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.mediaMode.backgroundShape
                onSelected: newValue => {
                    Config.options.background.mediaMode.backgroundShape = newValue;
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

        ConfigSwitch {
            buttonIcon: "format_color_fill"
            text: Translation.tr("Change shell color to match album art")
            checked: Config.options.background.mediaMode.changeShellColor
            onCheckedChanged: {
                Config.options.background.mediaMode.changeShellColor = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Text highlight style")
            icon: "highlight"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.mediaMode.syllable.textHighlightStyle
                onSelected: newValue => {
                    Config.options.background.mediaMode.syllable.textHighlightStyle = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Vertical"),
                        icon: "vertical_distribute",
                        value: 0
                    },
                    {
                        displayName: Translation.tr("Horizontal"),
                        icon: "horizontal_distribute",
                        value: 1
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr("Toggle per monitor")
            checked: Config.options.background.mediaMode.togglePerMonitor
            onCheckedChanged: {
                Config.options.background.mediaMode.togglePerMonitor = checked;
            }
        }
    }


    ShortcutBox {
        Layout.fillWidth: true
        value: Translation.tr("Desktop Clock Widget settings")
        targetPageIndex: 9
        targetSectionTitle: Translation.tr("Widget Manager")
    }
}
