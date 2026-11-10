import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for Bar → Appearance & style: the corner, group, background, colour theme,
// screen-corner and brand-icon choices, which that page draws as cards, chips and swatches
// (configs/bar/); SearchRegistry indexes this file (SettingsPageRegistry `searchSources`)
// so they stay searchable, with the original controls. The switches are on the page itself.
ColumnLayout {
    ContentSection {
        icon: "rounded_corner"
        title: Translation.tr("Corner & Group Style")

        ContentSubsection {
            title: Translation.tr("Corner style")
            icon: "rounded_corner"

            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options.bar.barBackgroundStyle === 3 && (Config.options.bar.cornerStyle === 2 || Config.options.bar.cornerStyle === 3)
                materialIcon: "grid_view"
                text: Translation.tr("Rect and Dynamic Island corner styles are incompatible with Islands background. Only Hug and Float are available while Islands is active.")
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: ShellModePolicy.floatStyleBlockedReasonKey.length > 0
                materialIcon: "lock"
                text: Translation.tr(ShellModePolicy.floatStyleBlockedReasonKey)
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: ShellModePolicy.barStyleBlockedByCenterInBarReasonKey.length > 0
                materialIcon: "lock"
                text: Translation.tr(ShellModePolicy.barStyleBlockedByCenterInBarReasonKey)

                ShortcutBox {
                    targetPageId: "dynamicIsland"
                    targetSectionTitle: Translation.tr("Dynamic Island in Bar Center")
                    materialIcon: "arrow_forward"
                    text: Translation.tr("Go to Dynamic Island settings")
                    linkText: Translation.tr("Go there")
                }
            }

            ConfigSelectionArray {
                id: cornerStyleSelector
                currentValue: Config.options.bar.cornerStyle
                onSelected: (newValue) => {
                    if (newValue === 3 && !Config.options.bar.vertical && Config.options.sidebar.sidebarStyle === "connect") {
                        Config.options.sidebar.sidebarStyle = "default";
                    }
                    Config.options.bar.cornerStyle = newValue;
                }
                options: {
                    var opts = [{
                        "displayName": Translation.tr("Hug"),
                        "icon": "line_curve",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Float"),
                        "icon": "page_header",
                        "value": 1,
                        "enabled": !ShellModePolicy.wrappedFrameActive
                    }, {
                        "displayName": Translation.tr("Rect"),
                        "icon": "toolbar",
                        "value": 2
                    }, {
                        "displayName": Translation.tr("Dynamic Island"),
                        "icon": "water_drop",
                        "value": 3
                    }];
                    if (Config.options.bar.barBackgroundStyle === 3) {
                        opts[2].enabled = false;
                        opts[3].enabled = false;
                    }
                    // Which styles the centred island fits in depends on its
                    // shell, so the allow-list is ShellModePolicy's to state:
                    // an edge-attached notch needs Hug or Dynamic Island, an
                    // island-shaped one drops into Float and Rect as well. The
                    // `&&` keeps whatever the rules above already refused.
                    if (ShellModePolicy.centerInBarActive) {
                        const centred = ShellModePolicy.centerInBarStyles;
                        opts[1].enabled = opts[1].enabled !== false && centred.indexOf(1) !== -1;
                        opts[2].enabled = opts[2].enabled !== false && centred.indexOf(2) !== -1;
                    }
                    // The tablet family renders no dynamic island at all, so the
                    // style is not merely disabled here — it is not on offer.
                    if (PanelFamily.isTablet)
                        return opts.slice(0, 3);
                    return opts;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Group style")
            icon: "group_work"
            tooltip: Translation.tr("Style for widget group containers on the bar")

            ConfigSelectionArray {
                currentValue: Config.options.bar.barGroupStyle
                onSelected: (newValue) => {
                    Config.options.bar.barGroupStyle = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Pills"),
                    "icon": "location_chip",
                    "value": 0
                }, {
                    "displayName": Translation.tr("Island"),
                    "icon": "shadow",
                    "value": 1
                }, {
                    "displayName": Translation.tr("Transparent"),
                    "icon": "opacity",
                    "value": 2
                }]
            }
        }
    }

    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Background & Colors")

        ContentSubsection {
            title: Translation.tr("Bar background style")
            icon: "format_paint"
            tooltip: Translation.tr("Adaptive style makes the bar background transparent when there are no active windows")

            NoticeBox {
                Layout.fillWidth: true
                visible: ShellModePolicy.barPositionLocked
                materialIcon: "lock"
                text: Translation.tr("Bar background is locked to Transparent or Islands while 'Dynamic Island in bar center' is active. Visible and Adaptive options are unavailable.")
            }

            ConfigSelectionArray {
                currentValue: Config.options.bar.barBackgroundStyle
                onSelected: (newValue) => {
                    Config.options.bar.barBackgroundStyle = newValue;
                    if (newValue === 3 && (Config.options.bar.cornerStyle === 2 || Config.options.bar.cornerStyle === 3))
                        Config.options.bar.cornerStyle = 0;

                    if (newValue === 3) {
                        let centerList = Config.options.bar.layouts.center;
                        let hasCentered = centerList.some((item) => {
                            return item.centered;
                        });
                        if (hasCentered)
                            Config.options.bar.layouts.center = centerList.map((item) => {
                            return ({
                                "id": item.id,
                                "centered": false,
                                "visible": item.visible
                            });
                        });
                    }
                }
                options: {
                    const locked = ShellModePolicy.barPositionLocked;
                    return [{
                        "displayName": Translation.tr("Visible"),
                        "icon": "visibility",
                        "value": 1,
                        "enabled": !locked
                    }, {
                        "displayName": Translation.tr("Adaptive"),
                        "icon": "masked_transitions",
                        "value": 2,
                        "enabled": !locked
                    }, {
                        "displayName": Translation.tr("Transparent"),
                        "icon": "opacity",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Islands"),
                        "icon": "grid_view",
                        "value": 3
                    }];
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Expressive color theme")
            icon: "palette"
            visible: Config.options.bar.expressiveColors

            ConfigSelectionArray {
                currentValue: Config.options.bar.expressiveColorTheme
                onSelected: (newValue) => {
                    Config.options.bar.expressiveColorTheme = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Content"),
                    "icon": "brush",
                    "value": "content"
                }, {
                    "displayName": Translation.tr("Vibrant"),
                    "icon": "brush",
                    "value": "primary"
                }, {
                    "displayName": Translation.tr("Secondary"),
                    "icon": "brush",
                    "value": "secondary"
                }, {
                    "displayName": Translation.tr("Surface"),
                    "icon": "brush",
                    "value": "surface"
                }]
            }
        }
    }

    ContentSection {
        icon: "fullscreen_exit"
        title: Translation.tr("Fake screen rounding")

        ContentSubsection {
            title: Translation.tr("Fake screen rounding")
            icon: "fullscreen_exit"
            Layout.fillWidth: true

            NoticeBox {
                Layout.fillWidth: true
                visible: ShellModePolicy.barPositionLocked
                materialIcon: "lock"
                text: Translation.tr("Wrapped Frame and Edge modes are locked while 'Dynamic Island in bar center' is active. They would render floating above the island, causing visual conflicts.")
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: ShellModePolicy.wrappedFrameBlockedReasonKey.length > 0
                materialIcon: "lock"
                text: Translation.tr(ShellModePolicy.wrappedFrameBlockedReasonKey)
            }

            ConfigSelectionArray {
                currentValue: Config.options.appearance.fakeScreenRounding
                onSelected: (newValue) => {
                    Config.options.appearance.fakeScreenRounding = newValue;
                }
                options: {
                    const locked = ShellModePolicy.barPositionLocked;
                    return [{
                        "displayName": Translation.tr("No"),
                        "icon": "close",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Yes"),
                        "icon": "check",
                        "value": 1
                    }, {
                        "displayName": Translation.tr("When not fullscreen"),
                        "icon": "fullscreen_exit",
                        "value": 2
                    }, {
                        "displayName": Translation.tr("Wrapped"),
                        "icon": "capture",
                        "value": 3,
                        "enabled": !locked && !ShellModePolicy.floatStyleActive
                    }, {
                        "displayName": Translation.tr("Edge"),
                        "icon": "border_bottom",
                        "value": 4,
                        "enabled": !locked
                    }];
                }
            }
        }
    }

    ContentSection {
        icon: "brand_family"
        title: Translation.tr("Top-left brand icon")

        ContentSubsection {
            title: Translation.tr("Preset icons")
            icon: "image"
            Layout.fillWidth: true

            ConfigSelectionArray {
                enabled: !Config.options.bar.useMaterialSymbolForTopLeftIcon
                opacity: enabled ? 1.0 : 0.4
                currentValue: Config.options.bar.useMaterialSymbolForTopLeftIcon ? "" : Config.options.bar.topLeftIcon
                onSelected: (newValue) => {
                    Config.options.bar.topLeftIcon = newValue;
                }
                options: [
                    { "displayName": Translation.tr("Distro"), "symbol": SystemInfo.distroIcon, "value": "distro" },
                    { "displayName": "Arch", "symbol": "arch-symbolic", "value": "arch" },
                    { "displayName": "CachyOS", "symbol": "cachyos-symbolic", "value": "cachyos" },
                    { "displayName": "EndeavourOS", "symbol": "endeavouros-symbolic", "value": "endeavouros" },
                    { "displayName": "Fedora", "symbol": "fedora-symbolic", "value": "fedora" },
                    { "displayName": "Red Hat", "symbol": "redhat-symbolic", "value": "redhat" },
                    { "displayName": "Debian", "symbol": "debian-symbolic", "value": "debian" },
                    { "displayName": "Ubuntu", "symbol": "ubuntu-symbolic", "value": "ubuntu" },
                    { "displayName": "Mint", "symbol": "mint-symbolic", "value": "mint" },
                    { "displayName": "Pop!_OS", "symbol": "popos-symbolic", "value": "popos" },
                    { "displayName": "Manjaro", "symbol": "manjaro-symbolic", "value": "manjaro" },
                    { "displayName": "NixOS", "symbol": "nixos-symbolic", "value": "nixos" },
                    { "displayName": "openSUSE", "symbol": "opensuse-symbolic", "value": "opensuse" },
                    { "displayName": "Gentoo", "symbol": "gentoo-symbolic", "value": "gentoo" },
                    { "displayName": "Void", "symbol": "void-symbolic", "value": "void" },
                    { "displayName": "Alpine", "symbol": "alpine-symbolic", "value": "alpine" },
                    { "displayName": "Kali", "symbol": "kali-symbolic", "value": "kali" },
                    { "displayName": "FreeBSD", "symbol": "freebsd-symbolic", "value": "freebsd" },
                    { "displayName": "SteamOS", "symbol": "steamos-symbolic", "value": "steamos" },
                    { "displayName": "Linux", "symbol": "linux-symbolic", "value": "linux" },
                    { "displayName": "Android", "symbol": "android-symbolic", "value": "android" },
                    { "displayName": "Apple", "symbol": "apple-symbolic", "value": "apple" },
                    { "displayName": "Windows", "symbol": "microsoft-symbolic", "value": "microsoft" },
                    { "displayName": "Spark", "symbol": "spark-symbolic", "value": "spark" },
                    { "displayName": "Nyarch", "symbol": "nyarch-symbolic", "value": "nyarch" },
                    { "displayName": "Docker", "symbol": "docker.svg", "value": "docker" },
                    { "displayName": "Flatpak", "symbol": "flatpak-symbolic", "value": "flatpak" },
                    { "displayName": "GitHub", "symbol": "github-symbolic", "value": "github" },
                    { "displayName": "Desktop", "symbol": "desktop-symbolic", "value": "desktop" },
                    { "displayName": "Crosshair", "symbol": "crosshair-symbolic", "value": "crosshair" },
                    { "displayName": "Cloudflare", "symbol": "cloudflare-dns-symbolic", "value": "cloudflare-dns" },
                    { "displayName": "Gemini", "symbol": "google-gemini-symbolic", "value": "google-gemini" },
                    { "displayName": "DeepSeek", "symbol": "deepseek-symbolic", "value": "deepseek" },
                    { "displayName": "OpenAI", "symbol": "openai-symbolic", "value": "openai" },
                    { "displayName": "Mistral", "symbol": "mistral-symbolic", "value": "mistral" },
                    { "displayName": "Ollama", "symbol": "ollama-symbolic", "value": "ollama" },
                    { "displayName": "OpenRouter", "symbol": "openrouter-symbolic", "value": "openrouter" }
                ]
            }
        }
    }
}
