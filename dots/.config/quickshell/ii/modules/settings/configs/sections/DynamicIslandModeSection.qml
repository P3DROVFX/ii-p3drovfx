import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for the Dynamic Island page: where the island lives, what opens inside
// it and the teleprompter. The page draws these as mode cards and feature tiles;
// SearchRegistry indexes this file (see SettingsPageRegistry `searchSources`) so the
// plain switches stay searchable and keep the page's side effects.
ColumnLayout {
    id: proxyRoot
    readonly property bool barNotTop: Config.options.bar.bottom || Config.options.bar.vertical
    readonly property bool centerInBarActive: Config.options.bar.floatingNotch.centerInBar
    readonly property bool islandOn: Config.options.bar.floatingNotch.enable
        || Config.options.bar.floatingNotch.centerInBar

    // ── Mode ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: "toggle_on"
        title: Translation.tr("Island mode")
        tooltip: Translation.tr("Where the island lives: inside the bar's centre, or floating from the top edge.")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin / 2

            ConfigSwitch {
                buttonIcon: "align_justify_center"
                text: Translation.tr("Dynamic Island in bar center")
                checked: Config.options.bar.floatingNotch.centerInBar
                enabled: !proxyRoot.barNotTop && ShellModePolicy.centerInBarStyleSupported

                onCheckedChanged: {
                    if (checked === Config.options.bar.floatingNotch.centerInBar)
                        return;

                    if (checked) {
                        // Refused rather than coerced: silently rewriting the user's
                        // bar style to enable a different feature is worse than not
                        // enabling it. The selector blocks the reverse direction too.
                        if (!ShellModePolicy.centerInBarStyleSupported)
                            return;
                        Config.options.bar.floatingNotch.enable = false;
                        Config.options.sidebar.sidebarStyle = "default";
                        Config.options.bar.bottom = false;
                        Config.options.bar.vertical = false;
                        if (Config.options.bar.barBackgroundStyle !== 3)
                            Config.options.bar.barBackgroundStyle = 0;
                        if (Config.options.appearance.fakeScreenRounding === 3 || Config.options.appearance.fakeScreenRounding === 4)
                            Config.options.appearance.fakeScreenRounding = 1;
                        Config.options.bar.autoHide.enable = false;

                        // The centre belongs to the island: stash the user's
                        // layout and empty the group. The old code only hid the
                        // entries, which left zombie widgets occupying the centre
                        // in the layout editor and in the saved config.
                        var cl = Config.options.bar.layouts.center;
                        if (cl && cl.length) {
                            var stashed = [];
                            for (var i = 0; i < cl.length; i++) {
                                stashed.push({
                                    id: cl[i].id,
                                    centered: cl[i].centered === true,
                                    visible: cl[i].visible !== false,
                                });
                            }
                            Persistent.states.bar.centerStash = stashed;
                            Config.options.bar.layouts.center = [];
                        }

                        Config.options.bar.floatingNotch.centerInBar = true;
                    } else {
                        Config.options.bar.floatingNotch.centerInBar = false;
                        // Give back what was taken, but only while the centre is
                        // still empty: if the user rebuilt it by hand meanwhile,
                        // their new layout wins and the stash is dropped.
                        var stash = Persistent.states.bar.centerStash;
                        var current = Config.options.bar.layouts.center;
                        if (stash && stash.length > 0 && (!current || current.length === 0))
                            Config.options.bar.layouts.center = stash;
                        Persistent.states.bar.centerStash = [];
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Positions the Dynamic Island on top of the bar center. Forces Default mode, bar Top, Transparent background, and stashes the center widgets until the mode is turned off again.")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: !proxyRoot.centerInBarActive
                materialIcon: "info"
                text: Translation.tr("Prerequisites to enable:\n• Bar position must be set to Top\n• Bar style must be Hug or Dynamic Island, unless the shape below is set to Island — that one also sits in a Float or Rect bar\n• Bar background style must be Transparent or Islands\nCenter widgets are stashed automatically while the island holds the centre, and restored when it gives it back.")

                ShortcutBox {
                    targetPageId: "bar"
                    targetSectionTitle: Translation.tr("Bar position")
                    materialIcon: "arrow_forward"
                    text: Translation.tr("Go to Bar settings")
                    linkText: Translation.tr("Go there")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: proxyRoot.centerInBarActive
                materialIcon: "check_circle"
                text: Translation.tr("Active: Dynamic Island floats above the bar center. All prerequisites are active and locked (Bar at Top, Transparent background, Center widgets hidden).")
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: proxyRoot.centerInBarActive && Config.options.bar.cornerStyle === 3
                materialIcon: "expand"
                text: Translation.tr("With the Dynamic Island bar style the bar flanks the island: its widget groups sit on either side and are pushed outward as the island grows, then close back in as it shrinks.")
            }

            ConfigSwitch {
                buttonIcon: "water_drop"
                text: Translation.tr("Floating Dynamic Island")
                checked: Config.options.bar.floatingNotch.enable
                enabled: proxyRoot.barNotTop
                onCheckedChanged: {
                    if (checked === Config.options.bar.floatingNotch.enable)
                        return;

                    if (checked && !proxyRoot.barNotTop)
                        return;

                    if (checked && Config.options.bar.floatingNotch.centerInBar) {
                        Config.options.bar.floatingNotch.centerInBar = false;
                    }
                    // The island takes the top edge: the bar's auto-hide would hide
                    // the bar out from under it. Same rule "island in bar center"
                    // enforces; Bar → Behavior locks the toggle while this holds.
                    if (checked && !Config.options.bar.vertical)
                        Config.options.bar.autoHide.enable = false;
                    Config.options.bar.floatingNotch.enable = checked;
                }

                StyledToolTip {
                    text: proxyRoot.barNotTop
                        ? Translation.tr("Enables an independent, floating Dynamic Island at the top of the screen")
                        : Translation.tr("Floating Dynamic Island requires the bar to be Vertical or at the Bottom")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: !proxyRoot.barNotTop
                materialIcon: "info"
                text: Translation.tr("Floating Dynamic Island is only supported with a Vertical or Bottom bar. Change bar position to enable.")

                ShortcutBox {
                    targetPageId: "bar"
                    targetSectionTitle: Translation.tr("Bar position")
                    materialIcon: "arrow_forward"
                    text: Translation.tr("Go to Bar settings")
                    linkText: Translation.tr("Go there")
                }
            }
        }
    }

    ContentSection {
        visible: proxyRoot.islandOn
        icon: "interests"
        title: Translation.tr("Shape")

        ConfigSelectionArray {
            currentValue: Config.options.bar.floatingNotch.shape
            onSelected: newValue => Config.options.bar.floatingNotch.shape = newValue
            options: [{
                "displayName": Translation.tr("Notch"),
                "icon": "horizontal_rule",
                "value": "notch",
                "enabled": !ShellModePolicy.notchShapeBlockedByCenterInBar
            }, {
                "displayName": Translation.tr("Sculpted"),
                "icon": "line_curve",
                "value": "sculpted",
                "enabled": !ShellModePolicy.notchShapeBlockedByCenterInBar
            }, {
                "displayName": Translation.tr("Island"),
                "icon": "pill",
                "value": "island"
            }]
        }
    }

    // ── Integrations ──────────────────────────────────────────────────────
    ContentSection {
        visible: proxyRoot.islandOn
        icon: "apps"
        title: Translation.tr("Island integrations")
        tooltip: Translation.tr("What the island owns: bubbles beside it, and which surfaces open inside it.")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin / 2

            ConfigSwitch {
                buttonIcon: "bubble_chart"
                text: Translation.tr("Auxiliary bubble")
                checked: Config.options.bar.floatingNotch.auxiliaryBubble
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.auxiliaryBubble = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Media and workspace changes move into a small bubble beside the island instead of replacing what it shows. Hover the bubble to open it in the island")
                }
            }

            ConfigSwitch {
                buttonIcon: "grid_view"
                text: Translation.tr("Overview in the island")
                checked: Config.options.bar.floatingNotch.integratedOverview
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.integratedOverview = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Lays the workspace overview out for the island: a small fixed grid under the search field that opens and closes with it. Off restores the desktop overview's own grid, scale and animations, and unlocks those settings in Overview")
                }
            }

            ConfigSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("Session menu in the island")
                checked: Config.options.bar.floatingNotch.integratedSessionMenu
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.integratedSessionMenu = checked;
                }

                StyledToolTip {
                    text: Translation.tr("The power button opens the session menu inside the island - the same eight actions in the same four-by-two grid - instead of the full-screen session screen")
                }
            }

            ConfigSwitch {
                buttonIcon: "tab"
                text: Translation.tr("Alt+Tab in the island")
                checked: !Config.options.bar.floatingNotch.disableWindowSwitcher
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.disableWindowSwitcher = !checked;
                }

                StyledToolTip {
                    text: Translation.tr("Alt+Tab grows the island into a cover flow of live window previews. Off opens the floating switcher panel instead")
                }
            }

            ConfigSwitch {
                buttonIcon: "wallpaper"
                text: Translation.tr("Wallpaper picker in the island")
                checked: Config.options.bar.floatingNotch.integratedWallpaperBrowser
                onCheckedChanged: {
                    Config.options.bar.floatingNotch.integratedWallpaperBrowser = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Picks a wallpaper inside the island - a plain row or a carousel, set below - with the folder path above it and the usual toolbars below. Off opens the full-screen wallpaper selector instead")
                }
            }

            // Right under its toggle, and last, so it doesn't split the toggles up.
            ContentSubsection {
                title: Translation.tr("Wallpaper picker layout")
                icon: "view_carousel"
                visible: Config.options.bar.floatingNotch.integratedWallpaperBrowser

                ConfigSelectionArray {
                    currentValue: Config.options.bar.floatingNotch.wallpaperBrowserStyle
                    onSelected: newValue => Config.options.bar.floatingNotch.wallpaperBrowserStyle = newValue
                    options: [{
                        "displayName": Translation.tr("Row"),
                        "icon": "view_column",
                        "value": "row"
                    }, {
                        "displayName": Translation.tr("Carousel"),
                        "icon": "view_carousel",
                        "value": "carousel"
                    }]
                }
            }
        }
    }

    // ── Teleprompter ────────────────────────────────────────────────────
    ContentSection {
        visible: proxyRoot.islandOn
        icon: "subtitles"
        title: Translation.tr("Teleprompter")
        tooltip: Translation.tr("Read a script scrolling on the island, for recordings and interviews")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin / 2

            ConfigSwitch {
                buttonIcon: "subtitles"
                text: Translation.tr("Teleprompter")
                checked: Config.options.dynamicIsland.widgets.teleprompter.enable === true
                onCheckedChanged: {
                    const cfg = Config.options.dynamicIsland.widgets.teleprompter;
                    if (checked === (cfg.enable === true))
                        return;
                    cfg.enable = checked;
                    if (!checked)
                        Teleprompter.stop();
                }
            }
        }
    }
}
