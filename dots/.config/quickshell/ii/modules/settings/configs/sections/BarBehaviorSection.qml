import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentSection {
    icon: "tune"
    title: Translation.tr("Behavior")

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

    ConfigSwitch {
        buttonIcon: "swap_vert"
        text: Translation.tr("Scroll actions")
        checked: Config.options.bar.enableVolumeScroll || Config.options.bar.enableBrightnessScroll
        configPage: Qt.resolvedUrl("../widgets/BarScrollActionsConfig.qml")
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
        configPage: Qt.resolvedUrl("../widgets/BarTooltipsConfig.qml")
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
        configPage: Qt.resolvedUrl("../widgets/BarPopupsConfig.qml")
        property bool readyForToggle: false
        Component.onCompleted: readyForToggle = true
        onCheckedChanged: {
            if (!readyForToggle || !Config.ready)
                return;
            Config.options.bar.tooltips.enablePopups = checked;
        }
    }
}
