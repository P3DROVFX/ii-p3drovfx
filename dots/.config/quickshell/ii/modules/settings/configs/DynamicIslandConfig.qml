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
                    enabled: !dynamicIslandConfigRoot.barNotTop

                    onCheckedChanged: {
                        if (checked === Config.options.bar.floatingNotch.centerInBar)
                            return;

                        if (checked) {
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
                    text: Translation.tr("Prerequisites to enable:\n• Bar position must be set to Top\n• Bar background style must be Transparent or Islands\n• No widgets can be placed in the bar center layout")

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
            }
        }

        // ── Floating Dynamic Island ───────────────────────────────────────────
        ContentSection {
            icon: "water_drop"
            title: Translation.tr("Floating Dynamic Island")
            tooltip: Translation.tr("Independent island when using Connect shell mode.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "warning"
                    text: Translation.tr("The search only works with dynamic island in connect mode.")

                    RippleButtonWithIcon {
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "arrow_forward"
                        mainText: Translation.tr("Switch to connect mode")
                        onClicked: {
                            var win = dynamicIslandConfigRoot.QsWindow.window;
                            if (!win || win.pageIndexById === undefined)
                                return;

                            const idx = win.pageIndexById("bar");
                            if (idx < 0)
                                return;

                            win.pendingSectionHighlight = Translation.tr("Shell mode");
                            win.currentPage = idx;
                        }
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: Config.options.sidebar.sidebarStyle === "default" && !Config.options.bar.floatingNotch.centerInBar
                    materialIcon: "block"
                    text: Translation.tr("The Floating Dynamic Island requires Connect shell mode. Switch to Connect mode to use this feature.")

                    ShortcutBox {
                        targetPageId: "bar"
                        targetSectionTitle: Translation.tr("Shell mode")
                        materialIcon: "arrow_forward"
                        text: Translation.tr("Go to Shell mode settings")
                        linkText: Translation.tr("Go there")
                    }
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

                ConfigSwitch {
                    buttonIcon: "compress"
                    text: Translation.tr("Extra Compact Mode")
                    visible: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    checked: Config.options.bar.floatingNotch.extraCompact
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.extraCompact = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Wider and shorter island with smoother concave corners (−25% height, +60% width)")
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
