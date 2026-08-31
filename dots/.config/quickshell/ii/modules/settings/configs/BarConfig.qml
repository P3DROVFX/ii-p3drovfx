pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: barConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    property string autoSwitchNoticeMessage: ""

    readonly property int barWidgetCount: (Config.options.bar.layouts.left?.length ?? 0)
        + (Config.options.bar.layouts.center?.length ?? 0)
        + (Config.options.bar.layouts.right?.length ?? 0)

    Timer {
        id: autoSwitchNoticeTimer
        interval: 6000
        repeat: false
        onTriggered: {
            barConfigRoot.autoSwitchNoticeMessage = "";
        }
    }

    function triggerAutoSwitchNotice(msg: string) {
        autoSwitchNoticeMessage = msg;
        autoSwitchNoticeTimer.restart();
    }

    function openWidgetPage(componentId) {
        page.openWidgetPage(componentId);
    }

    ContentPage {
        id: page

        function openWidgetPage(componentId) {
            const compInfo = BarComponentRegistry.getComponent(componentId);
            if (compInfo) {
                if (typeof compInfo.pageId !== "undefined") {
                    var win = barConfigRoot.QsWindow.window;
                    if (win && win.pageIndexById !== undefined) {
                        if (compInfo.sectionTitle)
                            win.pendingSectionHighlight = Translation.tr(compInfo.sectionTitle);

                        win.currentPage = win.pageIndexById(compInfo.pageId);
                    }
                } else if (compInfo.configPage) {
                    barConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/" + compInfo.configPage);
                }
            }
        }

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── Shell mode ────────────────────────────────────────────────────
        ContentSection {
            icon: "phone_android"
            title: Translation.tr("Shell mode")
            tooltip: Translation.tr("Switch between Default desktop mode and Connect mode.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Style")
                    icon: "style"
                    Layout.fillWidth: true

                    NoticeBox {
                        Layout.fillWidth: true
                        visible: ShellModePolicy.barPositionLocked
                        materialIcon: "lock"
                        text: Translation.tr("Shell mode is locked to Default while 'Dynamic Island in bar center' is active. The search runs independently of the Dynamic Island in this mode.")
                    }

                    ConfigSelectionArray {
                        id: shellStyleSelector
                        currentValue: Config.options.sidebar.sidebarStyle
                        onSelected: (newValue) => {
                            if (newValue === "connect" && Config.options.bar.cornerStyle === 3 && !Config.options.bar.vertical) {
                                barConfigRoot.triggerAutoSwitchNotice(Translation.tr("Dynamic Island at top/bottom is incompatible with Connect mode. Bar corner style was automatically set to Hug."));
                            }
                            ShellModePolicy.setMode(newValue);
                        }
                        options: {
                            var opts = [{
                                "displayName": Translation.tr("Default"),
                                "icon": "view_sidebar",
                                "value": "default"
                            }, {
                                "displayName": Translation.tr("Connect"),
                                "icon": "phone_android",
                                "value": "connect",
                                "enabled": ShellModePolicy.canSelectConnect
                            }];
                            opts[0].enabled = ShellModePolicy.canSelectDefault;
                            return opts;
                        }
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: barConfigRoot.autoSwitchNoticeMessage.length > 0
                    materialIcon: "info"
                    text: barConfigRoot.autoSwitchNoticeMessage
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: ShellModePolicy.defaultBlockedReasonKey.length > 0
                    materialIcon: "water_drop"
                    text: Translation.tr(ShellModePolicy.defaultBlockedReasonKey)

                    ShortcutBox {
                        targetPageId: "dynamicIsland"
                        targetSectionTitle: Translation.tr("Floating Dynamic Island")
                        materialIcon: "arrow_forward"
                        text: Translation.tr("Go to Dynamic Island settings")
                        linkText: Translation.tr("Go there")
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: Config.options.bar.autoHide.enable
                    text: Translation.tr("Bar auto-hide is not supported by Search Connect Mode yet. Disable auto-hide to use the drop search.")
                }
            }
        }

        // ── Bar basics & Navigation ───────────────────────────────────────
        ContentSection {
            icon: "space_bar"
            title: Translation.tr("Bar basics & placement")
            tooltip: Translation.tr("Set bar position, dimensions and jump to detailed appearance or layout configuration.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Bar position")
                    icon: "dock"

                    NoticeBox {
                        Layout.fillWidth: true
                        visible: ShellModePolicy.barPositionLocked
                        materialIcon: "lock"
                        text: Translation.tr("Bar position is locked to Top while 'Dynamic Island in bar center' is active. Disable that feature first to change position.")
                    }

                    ConfigSelectionArray {
                        currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                        onSelected: (newValue) => {
                            const isVertical = (newValue & 2) !== 0;
                            if (!isVertical && Config.options.bar.cornerStyle === 3 && Config.options.sidebar.sidebarStyle === "connect") {
                                barConfigRoot.triggerAutoSwitchNotice(Translation.tr("Dynamic Island is only supported in vertical orientation in Connect mode. Shell mode was automatically switched to Default."));
                            }
                            ShellModePolicy.setBarPosition(newValue);
                        }
                        options: {
                            const locked = ShellModePolicy.barPositionLocked;
                            return [{
                                "displayName": Translation.tr("Top"),
                                "icon": "arrow_upward",
                                "value": 0
                            }, {
                                "displayName": Translation.tr("Left"),
                                "icon": "arrow_back",
                                "value": 2,
                                "enabled": !locked
                            }, {
                                "displayName": Translation.tr("Bottom"),
                                "icon": "arrow_downward",
                                "value": 1,
                                "enabled": !locked
                            }, {
                                "displayName": Translation.tr("Right"),
                                "icon": "arrow_forward",
                                "value": 3,
                                "enabled": !locked
                            }];
                        }
                    }
                }

                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Bar height")
                    value: Config.options.bar.sizes.height
                    from: 30
                    to: 50
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.sizes.height = value;
                    }
                }

                ConfigSpinBox {
                    visible: Config.options.bar.vertical
                    icon: "width"
                    text: Translation.tr("Bar width")
                    value: Config.options.bar.sizes.width
                    from: 30
                    to: 50
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.sizes.width = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Automatically hide")
                    checked: Config.options.bar.autoHide.enable
                    enabled: !ShellModePolicy.barPositionLocked
                    onCheckedChanged: Config.options.bar.autoHide.enable = checked
                    StyledToolTip {
                        text: ShellModePolicy.barPositionLocked ? Translation.tr("Auto-hide is locked while 'Dynamic Island in bar center' is active.") : Translation.tr("Automatically hide the bar when not in use")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Sensitivity & trigger")
                    icon: "touch_app"
                    visible: Config.options.bar.autoHide.enable

                    ConfigSelectionArray {
                        currentValue: Config.options.bar.autoHide.mode ?? "instant"
                        onSelected: (newValue) => {
                            Config.options.bar.autoHide.mode = newValue;
                            if (newValue === "instant") {
                                Config.options.bar.autoHide.hoverRegionWidth = 6;
                                Config.options.bar.autoHide.hoverDelay = 0;
                            } else if (newValue === "dwell") {
                                Config.options.bar.autoHide.hoverRegionWidth = 16;
                                Config.options.bar.autoHide.hoverDelay = 250;
                            } else if (newValue === "wide") {
                                Config.options.bar.autoHide.hoverRegionWidth = 32;
                                Config.options.bar.autoHide.hoverDelay = 0;
                            } else if (newValue === "cautious") {
                                Config.options.bar.autoHide.hoverRegionWidth = 32;
                                Config.options.bar.autoHide.hoverDelay = 250;
                            }
                        }
                        options: [
                            {
                                "displayName": Translation.tr("Instant"),
                                "icon": "bolt",
                                "value": "instant",
                                "tooltip": Translation.tr("Reveals immediately on edge touch (6px edge, 0ms delay)")
                            },
                            {
                                "displayName": Translation.tr("Hold"),
                                "icon": "timer",
                                "value": "dwell",
                                "tooltip": Translation.tr("Requires holding pointer on edge for 250ms (16px edge, 250ms delay)")
                            },
                            {
                                "displayName": Translation.tr("Wide edge"),
                                "icon": "open_in_full",
                                "value": "wide",
                                "tooltip": Translation.tr("Large 32px trigger area for easy multi-monitor activation (32px edge, 0ms delay)")
                            },
                            {
                                "displayName": Translation.tr("Cautious"),
                                "icon": "security",
                                "value": "cautious",
                                "tooltip": Translation.tr("Wide 32px area requiring a 250ms hold, ideal for multi-monitor setups (32px edge, 250ms delay)")
                            }
                        ]
                    }
                }

                ConfigSpinBox {
                    visible: Config.options.bar.autoHide.enable
                    icon: "straighten"
                    text: Translation.tr("Trigger area width (px)")
                    value: Config.options.bar.autoHide.hoverRegionWidth
                    from: 2
                    to: 64
                    stepSize: 2
                    onValueChanged: {
                        Config.options.bar.autoHide.hoverRegionWidth = value;
                    }
                    StyledToolTip {
                        text: Translation.tr("Width of the interactive edge zone that detects the pointer")
                    }
                }

                ConfigSpinBox {
                    visible: Config.options.bar.autoHide.enable
                    icon: "hourglass_top"
                    text: Translation.tr("Hold delay (ms)")
                    value: Config.options.bar.autoHide.hoverDelay
                    from: 0
                    to: 1000
                    stepSize: 50
                    onValueChanged: {
                        Config.options.bar.autoHide.hoverDelay = value;
                    }
                    StyledToolTip {
                        text: Translation.tr("Delay in milliseconds the pointer must stay on the edge before the bar reveals")
                    }
                }

                ConfigSwitch {
                    visible: Config.options.bar.autoHide.enable
                    buttonIcon: "keyboard"
                    text: Translation.tr("Reveal with Super key")
                    checked: Config.options.bar.autoHide.showWhenPressingSuper.enable
                    onCheckedChanged: Config.options.bar.autoHide.showWhenPressingSuper.enable = checked
                    StyledToolTip {
                        text: Translation.tr("Temporarily reveals the bar while holding the Super/Windows key")
                    }
                }

                ConfigSubpageRow {
                    buttonIcon: "palette"
                    title: Translation.tr("Appearance & style")
                    description: Translation.tr("Corners, background styles, glow, drop shadows, and brand icon")
                    summary: (Config.options.bar.cornerStyle === 0 ? "Hug" : Config.options.bar.cornerStyle === 1 ? "Float" : Config.options.bar.cornerStyle === 2 ? "Rect" : "Dynamic Island") + " · " + (Config.options.bar.barBackgroundStyle === 0 ? "Transparent" : Config.options.bar.barBackgroundStyle === 1 ? "Visible" : Config.options.bar.barBackgroundStyle === 2 ? "Adaptive" : "Islands")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/BarAppearanceConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "view_stream"
                    title: Translation.tr("Bar Widgets & Widgets Layout")
                    description: Translation.tr("Left, center, and right widget placement and reordering")
                    summary: barConfigRoot.barWidgetCount + " " + Translation.tr("widgets · 3 groups")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/BarLayoutConfig.qml"))
                }
            }
        }

        // ── Behavior & Interactions ───────────────────────────────────────
        ContentSection {
            icon: "tune"
            title: Translation.tr("Behavior & Interactions")
            tooltip: Translation.tr("Configure scroll actions, bar popups, floating popups, and monitor targeting.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Scroll actions")
                    checked: Config.options.bar.enableVolumeScroll || Config.options.bar.enableBrightnessScroll
                    configPage: Qt.resolvedUrl("widgets/BarScrollActionsConfig.qml")
                    property bool readyForToggle: false
                    Component.onCompleted: readyForToggle = true
                    onCheckedChanged: {
                        if (!readyForToggle)
                            return;
                        Config.options.bar.enableVolumeScroll = checked;
                        Config.options.bar.enableBrightnessScroll = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "tooltip"
                    text: Translation.tr("Bar popups")
                    checked: Config.options.bar.tooltips.enableTooltips
                    configPage: Qt.resolvedUrl("widgets/BarTooltipsConfig.qml")
                    property bool readyForToggle: false
                    Component.onCompleted: readyForToggle = true
                    onCheckedChanged: {
                        if (!readyForToggle || !Config.ready)
                            return;
                        Config.options.bar.tooltips.enableTooltips = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "open_in_new"
                    text: Translation.tr("Floating popups")
                    checked: Config.options.bar.tooltips.enablePopups
                    configPage: Qt.resolvedUrl("widgets/BarPopupsConfig.qml")
                    property bool readyForToggle: false
                    Component.onCompleted: readyForToggle = true
                    onCheckedChanged: {
                        if (!readyForToggle || !Config.ready)
                            return;
                        Config.options.bar.tooltips.enablePopups = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Only show bar on single monitor")
                    checked: Config.options.bar.onlyShowOnSingleMonitor
                    onCheckedChanged: {
                        Config.options.bar.onlyShowOnSingleMonitor = checked;
                        if (checked && Config.options.bar.singleMonitorName === "" && Quickshell.screens.length > 0)
                            Config.options.bar.singleMonitorName = Quickshell.screens[0].name;
                    }
                    StyledToolTip {
                        text: Translation.tr("Display the bar on only one chosen monitor instead of all monitors")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Selected Monitor")
                    icon: "settings_input_hdmi"
                    visible: Config.options.bar.onlyShowOnSingleMonitor

                    MonitorPicker {
                        currentValue: Config.options.bar.singleMonitorName
                        onSelected: newValue => Config.options.bar.singleMonitorName = newValue
                    }
                }
            }
        }

        // ── Widgets & Waffle ──────────────────────────────────────────────
        ContentSection {
            icon: "widgets"
            title: Translation.tr("Widgets & Waffle")
            tooltip: Translation.tr("Configure individual bar widgets and Waffle panel tweaks.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "widgets"
                    title: Translation.tr("Widgets & Waffle Settings")
                    description: Translation.tr("Configure individual bar widgets and Waffle panel tweaks")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/BarWidgetsWaffleConfig.qml"))
                }
            }
        }
    }

    // ── Sub-page overlay (slides in from the right) ───────────────────────
    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
