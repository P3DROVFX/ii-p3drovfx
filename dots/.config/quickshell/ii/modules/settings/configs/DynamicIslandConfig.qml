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

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Dynamic Island in Bar Center ──────────────────────────────────────
        ContentSection {
            icon: "align_justify_center"
            title: Translation.tr("Dynamic Island in Bar Center")
            tooltip: Translation.tr("Positions the Dynamic Island seamlessly inside the top bar center.")

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

                            var cl = Config.options.bar.layouts.center;
                            if (cl && cl.length) {
                                var cleared = [];
                                for (var i = 0; i < cl.length; i++) {
                                    cleared.push({ id: cl[i].id, centered: cl[i].centered, visible: false });
                                }
                                Config.options.bar.layouts.center = cleared;
                            }

                            Config.options.bar.floatingNotch.centerInBar = true;
                        } else {
                            Config.options.bar.floatingNotch.centerInBar = false;
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Positions the Dynamic Island on top of the bar center. Forces Default mode, bar Top, Transparent background, hides center widgets.")
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: !dynamicIslandConfigRoot.centerInBarActive
                    materialIcon: "info"
                    text: Translation.tr("Prerequisites to enable:\n• Bar position must be set to Top\n• Bar style must be Hug or Dynamic Island (Float and Rect leave no centre to sit in)\n• Bar background style must be Transparent or Islands\n• No widgets can be placed in the bar center layout")

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
            }
        }

        // ── Floating Dynamic Island ───────────────────────────────────────────
        ContentSection {
            icon: "water_drop"
            title: Translation.tr("Floating Dynamic Island")
            tooltip: Translation.tr("Independent island hanging from the top edge.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

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

                ContentSubsectionLabel {
                    visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    text: Translation.tr("Island design")
                }

                ConfigSelectionArray {
                    visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    currentValue: Config.options.bar.floatingNotch.shape
                    onSelected: newValue => Config.options.bar.floatingNotch.shape = newValue
                    options: [{
                        "displayName": Translation.tr("Notch"),
                        "icon": "horizontal_rule",
                        "value": "notch"
                    }, {
                        "displayName": Translation.tr("Island"),
                        "icon": "pill",
                        "value": "island"
                    }]
                }

                ConfigSwitch {
                    buttonIcon: "bubble_chart"
                    text: Translation.tr("Auxiliary bubble")
                    visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    checked: Config.options.bar.floatingNotch.auxiliaryBubble
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.auxiliaryBubble = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Media and workspace changes move into a small bubble beside the island instead of replacing what it shows. Hover the bubble to open it in the island")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Always hide floating island")
                    visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
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
                    visible: (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar)
                        && Config.options.bar.floatingNotch.autoHide
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
                    buttonIcon: "filter_drama"
                    text: Translation.tr("Floating Island drop-shadow")
                    visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    checked: Config.options.bar.floatingNotch.dropShadow
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.dropShadow = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Shows a drop shadow underneath the floating island")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Only show island on single monitor")
                    visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
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
                    visible: (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar) && Config.options.bar.floatingNotch.onlyShowOnSingleMonitor

                    MonitorPicker {
                        currentValue: Config.options.bar.floatingNotch.singleMonitorName
                        onSelected: (newValue) => {
                            Config.options.bar.floatingNotch.singleMonitorName = newValue;
                        }
                    }
                }
            }
        }

        // ── Island Features & Notches ─────────────────────────────────────────
        ContentSection {
            visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
            icon: "category"
            title: Translation.tr("Island features & notches")
            tooltip: Translation.tr("Configure status indicators and interactive activity notches.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "sensors"
                    title: Translation.tr("Status notches")
                    description: Translation.tr("Workspaces, keyboard layout, Wi-Fi, Bluetooth and battery charging")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/DynamicIslandStatusConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "notifications_active"
                    title: Translation.tr("Activity notches & dimensions")
                    description: Translation.tr("Media, notifications, OSD, recordings, clipboard, checklists and idle height")
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
