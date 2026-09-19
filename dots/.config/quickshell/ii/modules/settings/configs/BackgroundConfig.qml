import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
                        }
                    ]
                }
            }
        }

        ContentSection {
            title: Translation.tr("Background Overview Design")
            icon: "dashboard_customize"

            NoticeBox {
                Layout.fillWidth: true
                visible: page.videoWallpaper
                materialIcon: "movie"
                text: Translation.tr("Video wallpaper active: overview background design styles are not available.")
            }

            ConfigSwitch {
                buttonIcon: "dashboard_customize"
                text: Translation.tr("Keep overview background design always active")
                enabled: !page.videoWallpaper
                checked: Config.options.background.useBackgroundOverviewAlways ?? false
                onCheckedChanged: {
                    Config.options.background.useBackgroundOverviewAlways = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Keep overview designs (Gnome Like, Material Shape, etc.) permanently active and static on the desktop, freezing background blur to minimize resource usage.")
                }
            }

            ContentSubsection {
                visible: (Config.options.background.useBackgroundOverviewAlways ?? false) && !page.videoWallpaper
                title: Translation.tr("Background design style")
                icon: "style"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: {
                        const style = Config.options.background.overviewBackgroundStyle;
                        const allowed = ["gnome", "material-shape", "card-lift", "camera-push", "desaturate", "directional"];
                        if (style && allowed.indexOf(style) >= 0)
                            return style;
                        return "gnome";
                    }
                    onSelected: newValue => {
                        Config.options.background.overviewBackgroundStyle = newValue;
                        Config.options.background.zoomOutStyle = newValue === "gnome" ? 0 : 2;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Gnome Like"),
                            icon: "blur_on",
                            tooltip: Translation.tr("Zooms the wallpaper out with rounded corners, shadow and a blurred backing."),
                            enabled: !page.videoWallpaper,
                            value: "gnome"
                        },
                        {
                            displayName: Translation.tr("Material Shape"),
                            icon: "shapes",
                            tooltip: Translation.tr("Cuts the wallpaper with a random Material Shape focusing on center widgets with a solid primary container background."),
                            enabled: !page.videoWallpaper,
                            value: "material-shape"
                        },
                        {
                            displayName: Translation.tr("Card Lift"),
                            icon: "style",
                            tooltip: Translation.tr("Lifts the wallpaper into a rounded card with a blurred/dimmed backing."),
                            value: "card-lift"
                        },
                        {
                            displayName: Translation.tr("Camera Push"),
                            icon: "zoom_in",
                            tooltip: Translation.tr("Pushes the camera in with brightness and saturation adjustment; no blur."),
                            enabled: !page.videoWallpaper,
                            value: "camera-push"
                        },
                        {
                            displayName: Translation.tr("Desaturate"),
                            icon: "tonality",
                            tooltip: Translation.tr("Low-cost preset using desaturation and reduced brightness without blur."),
                            value: "desaturate"
                        },
                        {
                            displayName: Translation.tr("Directional"),
                            icon: "open_in_new",
                            tooltip: Translation.tr("Adds a small movement away from the configured bar position."),
                            value: "directional"
                        }
                    ]
                }
            }

            ConfigSwitch {
                visible: (Config.options.background.useBackgroundOverviewAlways ?? false)
                    && ((Config.options.background.overviewBackgroundStyle ?? "") === "material-shape")
                    && !page.videoWallpaper
                enabled: !page.videoWallpaper
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
                visible: (Config.options.background.useBackgroundOverviewAlways ?? false)
                    && ((Config.options.background.overviewBackgroundStyle ?? "") === "material-shape")
                    && !page.videoWallpaper
                enabled: !page.videoWallpaper
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
