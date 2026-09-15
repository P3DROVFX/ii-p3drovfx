import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: backgroundRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        readonly property bool videoWallpaper: {
            const background = Config.options && Config.options.background ? Config.options.background : null;
            if (!background)
                return false;
            return background.useWallpaperEngine === true || Wallpapers.isVideoFile(background.wallpaperPath || "");
        }

        ContentSection {
            title: Translation.tr("Parallax Engine")
            icon: "sync_alt"

            NoticeBox {
                Layout.fillWidth: true
                visible: page.videoWallpaper
                materialIcon: "movie"
                text: Translation.tr("Video wallpaper active: window blur and parallax are disabled automatically; only the Default zoom style is available.")
            }

            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Depends on workspace")
                enabled: !page.videoWallpaper
                checked: Config.options.background.parallax.enableWorkspace
                configPage: Qt.resolvedUrl("widgets/ParallaxConfig.qml")
                onCheckedChanged: {
                    Config.options.background.parallax.enableWorkspace = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Click button text to configure parallax movement directions, sidebars, and intensity.")
                }
            }

            ConfigSlider {
                buttonIcon: "loupe"
                text: Translation.tr("Preferred wallpaper zoom (%)")
                enabled: !page.videoWallpaper
                usePercentTooltip: true
                from: 100
                to: 150
                stepSize: 1
                value: Math.round((Config.options.background.parallax.workspaceZoom ?? 1.07) * 100)
                onValueChanged: {
                    Config.options.background.parallax.workspaceZoom = value / 100;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Wallpaper Quality & Performance")
            icon: "high_quality"

            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("Downscale wallpaper to reduce VRAM usage")
                enabled: !page.videoWallpaper
                checked: Config.options.background.scaleLargeWallpapers ?? false
                onCheckedChanged: {
                    Config.options.background.scaleLargeWallpapers = checked;
                }
                StyledToolTip {
                    text: Translation.tr("When enabled, decodes large wallpapers at screen resolution to save VRAM. When disabled (default, like upstream end-4), loads wallpapers at full native resolution for maximum sharpness.")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Wallpaper Transitions")
            icon: "animation"

            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("Animate wallpaper changes")
                enabled: !page.videoWallpaper
                checked: Config.options.background.animateWallpaperChanges ?? true
                onCheckedChanged: {
                    Config.options.background.animateWallpaperChanges = checked;
                }
            }

            ContentSubsection {
                visible: (Config.options.background.animateWallpaperChanges ?? true) && !page.videoWallpaper
                title: Translation.tr("Transition shader effect")
                icon: "style"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.wallpaperAnimation ?? ""
                    onSelected: newValue => {
                        Config.options.background.wallpaperAnimation = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Crossfade"),
                            icon: "blur_on",
                            value: ""
                        },
                        {
                            displayName: Translation.tr("Random"),
                            icon: "shuffle",
                            value: "random"
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
                        },
                        {
                            displayName: Translation.tr("Circle"),
                            icon: "circle",
                            value: "circle"
                        },
                        {
                            displayName: Translation.tr("CRT"),
                            icon: "tv",
                            value: "crt"
                        },
                        {
                            displayName: Translation.tr("Dissolve"),
                            icon: "blur_off",
                            value: "dissolve"
                        },
                        {
                            displayName: Translation.tr("Doom"),
                            icon: "deployed_code",
                            value: "Doom"
                        },
                        {
                            displayName: Translation.tr("Glitch"),
                            icon: "broken_image",
                            value: "glitch"
                        },
                        {
                            displayName: Translation.tr("Ripple"),
                            icon: "water_drop",
                            value: "ripple"
                        },
                        {
                            displayName: Translation.tr("Shatter"),
                            icon: "shutter_speed",
                            value: "shatter"
                        }
                    ]
                }
            }
        }

        ContentSection {
            title: Translation.tr("Centered Wallpaper")
            icon: "crop_free"

            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.centeredWallpaper
                onCheckedChanged: {
                    Config.options.background.centeredWallpaper = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Crops the wallpaper into a material shape floating over a flat background color instead of filling the screen.")
                }
            }

            ConfigSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Show only when locked")
                checked: Config.options.background.centeredWallpaperOnlyWhenLocked
                onCheckedChanged: {
                    Config.options.background.centeredWallpaperOnlyWhenLocked = checked;
                }
                enabled: Config.options.background.centeredWallpaper
            }

            ContentSubsection {
                visible: Config.options.background.centeredWallpaper
                title: Translation.tr("Shape")
                icon: "interests"
                Layout.fillWidth: true

                ConfigSelectionShapeArray {
                    currentValue: Config.options.background.centeredWallpaperShape
                    shapeColor: Appearance.colors.colPrimary
                    backgroundColor: Appearance.colors.colPrimaryContainer
                    onSelected: (newValue) => {
                        if (newValue === "Random") {
                            GlobalStates.randomizeCenteredWallpaperShape();
                        } else {
                            Config.options.background.centeredWallpaperShape = newValue;
                        }
                    }
                    options: ["Random", "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                        "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                        "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                        "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]
                }
            }

            ContentSubsection {
                visible: Config.options.background.centeredWallpaper
                title: Translation.tr("Background color")
                icon: "palette"
                Layout.fillWidth: true

                ColorSelectionArray {
                    currentValue: Config.options.background.centeredWallpaperColor
                    onSelected: (newValue) => {
                        Config.options.background.centeredWallpaperColor = newValue;
                    }
                    options: ["primary", "secondary", "tertiary", "primaryContainer", "secondaryContainer", "tertiaryContainer", "layer0", "layer1"]
                }
            }

            ConfigSlider {
                visible: Config.options.background.centeredWallpaper
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Size")
                usePercentTooltip: false
                from: 400
                to: 1040
                stepSize: 10
                value: Config.options.background.centeredWallpaperSize ?? 600
                onValueChanged: {
                    Config.options.background.centeredWallpaperSize = value;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Background Blur")
            icon: "grain"

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Blur wallpaper when window open (Experimental)")
                enabled: !page.videoWallpaper
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
                enabled: !page.videoWallpaper
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
        }

        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Toggle Media Mode")
            keys: ["Super", "Z"]
        }

        ContentSection {
            title: Translation.tr("Media Mode Background")
            icon: "music_note"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("These settings apply exclusively to the full-screen Media Mode background overlay.")
            }

            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Media mode background overlay")
                checked: Config.options.background.mediaMode.showLyrics ?? true
                configPage: Qt.resolvedUrl("widgets/MediaModeBackgroundConfig.qml")
                onCheckedChanged: {
                    Config.options.background.mediaMode.showLyrics = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Click button text to configure lyrics, visualizers, album art opacity, and music video settings.")
                }
            }
        }

        ShortcutBox {
            Layout.fillWidth: true
            value: Translation.tr("Desktop Clock Widget settings")
            targetPageId: "widgets"
            targetSectionTitle: Translation.tr("Widget Manager")
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "windows"
                    label: Translation.tr("Window blur")
                    sectionHighlight: Translation.tr("Transparency & Blur")
                }

                RelatedChip {
                    pageId: "lockScreen"
                    label: Translation.tr("Lock screen blur")
                    sectionHighlight: Translation.tr("Blur style")
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
