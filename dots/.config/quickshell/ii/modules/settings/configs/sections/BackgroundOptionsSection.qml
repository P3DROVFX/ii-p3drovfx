import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for the Background page: every option its hero, dial cards, chips, grouped
// list, backend cards and tiles draw, as the original controls. The page shows them in those
// forms; SearchRegistry indexes this file (see SettingsPageRegistry `searchSources`) so
// they stay searchable. The depth effect, libmpv set-up and colour frame are indexed
// from their own sub-pages.
ColumnLayout {
    ContentSection {
        title: Translation.tr("Parallax Engine")
        icon: "sync_alt"

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr("Depends on workspace")
            checked: Config.options.background.parallax.enableWorkspace
            configPage: Qt.resolvedUrl("../widgets/ParallaxConfig.qml")
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
        title: Translation.tr("Background Blur")
        icon: "grain"

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Blur wallpaper when window open (Experimental)")
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

    ContentSection {
        title: Translation.tr("Wallpaper Transitions")
        icon: "animation"

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Animate wallpaper changes")
            checked: Config.options.background.animateWallpaperChanges ?? true
            onCheckedChanged: {
                Config.options.background.animateWallpaperChanges = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Transition shader effect")
            icon: "style"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.wallpaperAnimation ?? ""
                onSelected: newValue => {
                    Config.options.background.wallpaperAnimation = newValue;
                }
                options: [
                    { displayName: Translation.tr("Crossfade"), icon: "blur_on", value: "" },
                    { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                    { displayName: Translation.tr("Circle Pit"), icon: "circle", value: "circlePit" },
                    { displayName: Translation.tr("Circle Select"), icon: "radio_button_checked", value: "circleSelect" },
                    { displayName: Translation.tr("Magic"), icon: "auto_awesome", value: "magic" },
                    { displayName: Translation.tr("Peel"), icon: "sticky_note_2", value: "Peel" },
                    { displayName: Translation.tr("Transition"), icon: "swap_horiz", value: "transition" },
                    { displayName: Translation.tr("Pixelate"), icon: "grid_on", value: "pixelate" },
                    { displayName: Translation.tr("Stripes"), icon: "view_column", value: "stripes" }
                ]
            }
        }
    }

    ContentSection {
        title: Translation.tr("Background Overview Design")
        icon: "dashboard_customize"

        ConfigSwitch {
            buttonIcon: "dashboard_customize"
            text: Translation.tr("Keep overview background design always active")
            checked: Config.options.background.useBackgroundOverviewAlways ?? false
            onCheckedChanged: {
                Config.options.background.useBackgroundOverviewAlways = checked;
            }
            StyledToolTip {
                text: Translation.tr("Keep overview designs (Gnome Like, Material Shape, etc.) permanently active and static on the desktop, freezing background blur to minimize resource usage.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Background design style")
            icon: "style"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.overviewBackgroundStyle ?? "gnome"
                onSelected: newValue => {
                    Config.options.background.overviewBackgroundStyle = newValue;
                    Config.options.background.zoomOutStyle = (newValue === "gnome" || newValue === "real-gnome") ? 0 : 2;
                }
                options: [
                    { displayName: Translation.tr("Gnome Like"), icon: "blur_on", value: "gnome" },
                    { displayName: Translation.tr("Real Gnome"), icon: "auto_awesome_mosaic", value: "real-gnome" },
                    { displayName: Translation.tr("Material Shape"), icon: "shapes", value: "material-shape" },
                    { displayName: Translation.tr("Card Lift"), icon: "style", value: "card-lift" },
                    { displayName: Translation.tr("Camera Push"), icon: "zoom_in", value: "camera-push" },
                    { displayName: Translation.tr("Desaturate"), icon: "tonality", value: "desaturate" },
                    { displayName: Translation.tr("Directional"), icon: "open_in_new", value: "directional" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "wb_twilight"
            text: Translation.tr("Material Shape drop-shadow")
            checked: Config.options.background.materialShapeShadow === true
            onCheckedChanged: {
                Config.options.background.materialShapeShadow = checked;
            }
            StyledToolTip {
                text: Translation.tr("Renders a subtle outer drop shadow around the material shape mask.")
            }
        }

        ConfigSlider {
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Material Shape scale (%)")
            usePercentTooltip: true
            from: 30
            to: 200
            stepSize: 1
            value: Math.round((Config.options.background.materialShapeScale ?? 1.0) * 100)
            onValueChanged: {
                Config.options.background.materialShapeScale = value / 100;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Video Wallpapers")
        icon: "movie"

        ContentSubsection {
            title: Translation.tr("Video player")
            icon: "play_circle"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.videoBackend ?? "mpvpaper"
                onSelected: newValue => {
                    Config.options.background.videoBackend = newValue;
                }
                options: [
                    { displayName: Translation.tr("mpvpaper"), icon: "layers", value: "mpvpaper" },
                    { displayName: Translation.tr("Shell"), icon: "wallpaper", value: "shell" }
                ]
            }
        }
    }

    ContentSection {
        title: Translation.tr("Wallpaper Quality & Performance")
        icon: "high_quality"

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr("Downscale wallpaper to reduce VRAM usage")
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
        title: Translation.tr("Media Mode Background")
        icon: "music_note"

        ConfigSwitch {
            buttonIcon: "music_note"
            text: Translation.tr("Media mode background overlay")
            checked: Config.options.background.mediaMode.showLyrics ?? true
            configPage: Qt.resolvedUrl("../widgets/MediaModeBackgroundConfig.qml")
            onCheckedChanged: {
                Config.options.background.mediaMode.showLyrics = checked;
            }
            StyledToolTip {
                text: Translation.tr("Click button text to configure lyrics, visualizers, album art opacity, and music video settings.")
            }
        }
    }
}
