pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: dynamicIslandConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property bool barNotTop: Config.options.bar.bottom || Config.options.bar.vertical
    readonly property bool centerInBarActive: Config.options.bar.floatingNotch.centerInBar
    /** One answer for "is any island on?"; every island control gates on it. */
    readonly property bool islandOn: Config.options.bar.floatingNotch.enable
        || Config.options.bar.floatingNotch.centerInBar

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

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
                    enabled: !dynamicIslandConfigRoot.barNotTop && ShellModePolicy.centerInBarStyleSupported

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
                    visible: !dynamicIslandConfigRoot.centerInBarActive
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
                    visible: dynamicIslandConfigRoot.centerInBarActive
                    materialIcon: "check_circle"
                    text: Translation.tr("Active: Dynamic Island floats above the bar center. All prerequisites are active and locked (Bar at Top, Transparent background, Center widgets hidden).")
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: dynamicIslandConfigRoot.centerInBarActive && Config.options.bar.cornerStyle === 3
                    materialIcon: "expand"
                    text: Translation.tr("With the Dynamic Island bar style the bar flanks the island: its widget groups sit on either side and are pushed outward as the island grows, then close back in as it shrinks.")
                }

                ConfigSwitch {
                    buttonIcon: "water_drop"
                    text: Translation.tr("Floating Dynamic Island")
                    checked: Config.options.bar.floatingNotch.enable
                    enabled: Config.options.sidebar.sidebarStyle !== "default"
                    onCheckedChanged: {
                        if (checked === Config.options.bar.floatingNotch.enable)
                            return;

                        if (checked && Config.options.bar.floatingNotch.centerInBar) {
                            Config.options.bar.floatingNotch.centerInBar = false;
                        }
                        Config.options.bar.floatingNotch.enable = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Enables an independent, floating Dynamic Island at the top of the screen")
                    }
                }
            }
        }

        // ── Appearance ────────────────────────────────────────────────────────
        ContentSection {
            visible: dynamicIslandConfigRoot.islandOn
            icon: "palette"
            title: Translation.tr("Island appearance")
            tooltip: Translation.tr("The body's shape and its shadow.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                NoticeBox {
                    Layout.fillWidth: true
                    visible: ShellModePolicy.notchShapeBlockedReasonKey.length > 0
                    materialIcon: "lock"
                    text: Translation.tr(ShellModePolicy.notchShapeBlockedReasonKey)
                }

                ConfigSelectionArray {
                    currentValue: Config.options.bar.floatingNotch.shape
                    onSelected: newValue => Config.options.bar.floatingNotch.shape = newValue
                    // Refused rather than coerced, as everywhere else here: the notch
                    // cannot sit in a Float or Rect bar centre, and dropping back to it
                    // would silently switch the island off instead of changing a shape.
                    options: [{
                        "displayName": Translation.tr("Notch"),
                        "icon": "horizontal_rule",
                        "value": "notch",
                        "enabled": !ShellModePolicy.notchShapeBlockedByCenterInBar
                    }, {
                        "displayName": Translation.tr("Island"),
                        "icon": "pill",
                        "value": "island"
                    }]
                }

                ConfigSwitch {
                    buttonIcon: "filter_drama"
                    text: Translation.tr("Floating Island drop-shadow")
                    checked: Config.options.bar.floatingNotch.dropShadow
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.dropShadow = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Shows a drop shadow underneath the floating island")
                    }
                }
            }
        }

        // ── Behavior ──────────────────────────────────────────────────────────
        ContentSection {
            visible: dynamicIslandConfigRoot.islandOn
            icon: "mouse"
            title: Translation.tr("Island behavior")
            tooltip: Translation.tr("When the island shows itself and how it reacts to the pointer.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Always hide floating island")
                    checked: Config.options.bar.floatingNotch.autoHide
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.autoHide = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Hides the island until a workspace, media, Bluetooth, notification, or other activity trigger reveals it")
                    }
                }

                ConfigSpinBox {
                    icon: "touch_app"
                    text: Translation.tr("Hover time to expand (ms)")
                    visible: Config.options.bar.floatingNotch.autoHide
                    value: Config.options.bar.floatingNotch.hoverExpandDelayMs
                    from: 0
                    to: 5000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.bar.floatingNotch.hoverExpandDelayMs = value;
                    }

                    StyledToolTip {
                        text: Translation.tr("Hovering shows the contracted island at once; resting the pointer this long opens the expanded view")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "touch_app"
                    text: Translation.tr("Hold to reveal")
                    checked: Config.options.dynamicIsland.behavior.holdToReveal
                    onCheckedChanged: {
                        if (checked === Config.options.dynamicIsland.behavior.holdToReveal)
                            return;
                        Config.options.dynamicIsland.behavior.holdToReveal = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("The dashboard opens once the pointer has rested on the island for this long. The island grows a little while it waits, so the hold is visible.")
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Hold time (ms)")
                    visible: Config.options.dynamicIsland.behavior.holdToReveal
                    value: Config.options.dynamicIsland.behavior.holdToRevealMs
                    from: 200
                    to: 3000
                    stepSize: 50
                    onValueChanged: {
                        Config.options.dynamicIsland.behavior.holdToRevealMs = value;
                    }

                    StyledToolTip {
                        text: Translation.tr("Hold the pointer on the island to open the dashboard")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Only show island on single monitor")
                    checked: Config.options.bar.floatingNotch.onlyShowOnSingleMonitor
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.onlyShowOnSingleMonitor = checked;
                        if (checked && Config.options.bar.floatingNotch.singleMonitorName === "" && Quickshell.screens.length > 0)
                            Config.options.bar.floatingNotch.singleMonitorName = Quickshell.screens[0].name;
                    }

                    StyledToolTip {
                        text: Translation.tr("Display the dynamic island on only one chosen monitor instead of following focus")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Selected Monitor")
                    icon: "settings_input_hdmi"
                    visible: Config.options.bar.floatingNotch.onlyShowOnSingleMonitor

                    MonitorPicker {
                        currentValue: Config.options.bar.floatingNotch.singleMonitorName
                        onSelected: (newValue) => {
                            Config.options.bar.floatingNotch.singleMonitorName = newValue;
                        }
                    }
                }
            }
        }

        // ── Integrations ──────────────────────────────────────────────────────
        ContentSection {
            visible: dynamicIslandConfigRoot.islandOn
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
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Wallpaper picker in the island")
                    checked: Config.options.bar.floatingNotch.integratedWallpaperBrowser
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.integratedWallpaperBrowser = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Picks a wallpaper from one row inside the island, with the folder path above it and the usual toolbars below. Off opens the full-screen wallpaper selector instead")
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
            }
        }

        // ── Activities ────────────────────────────────────────────────────────
        ContentSection {
            visible: dynamicIslandConfigRoot.islandOn
            icon: "category"
            title: Translation.tr("Island activities")
            tooltip: Translation.tr("Which activities may appear on the island: announcements, live faces and the glances beside the clock.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "notifications_active"
                    title: Translation.tr("Activities & glances")
                    description: Translation.tr("Announcements, live activities, side glances and system notches")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/DynamicIslandActivitiesConfig.qml"))
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
